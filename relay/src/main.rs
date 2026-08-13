use std::net::SocketAddr;
use std::sync::Arc;

use anyhow::Context;
use tokio::net::TcpListener;
use tracing::info;
use tracing_subscriber::{filter::EnvFilter, fmt, prelude::*};

/// Max age (in days) of rotated relay log files to keep. Older files are
/// deleted on startup so `/data/logs/relay.log.YYYY-MM-DD` can't grow the
/// named volume without limit (`tracing-appender` rotates but does not
/// retain — without this sweep, one file per day accumulates indefinitely).
const RELAY_LOG_RETENTION_DAYS: u64 = 14;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let _log_guard = init_tracing();

    let port: u16 = std::env::var("OUTPOSTPI_RELAY_PORT")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(3000);

    let config = relay::RelayConfig::from_env();
    let outer_parser = relay::protocol::outer::OuterEnvelopeParser::new(config.max_ct_bytes());
    info!(
        max_ct_bytes = outer_parser.max_ct_bytes(),
        "outer envelope size limit"
    );

    // Default puts the SQLite file (and any transient -journal) under data/,
    // so bare-metal `cargo run` doesn't litter the project root.
    let db_path =
        std::env::var("OUTPOSTPI_MESH_DB_PATH").unwrap_or_else(|_| "data/mesh.db".to_string());

    let mesh = Arc::new(
        relay::MeshStore::open(&db_path)
            .with_context(|| format!("failed to open mesh DB at {db_path}"))?,
    );
    info!("mesh storage opened at {db_path}");

    let presence = Arc::new(relay::PresenceManager::new());
    let rooms = Arc::new(relay::RoomManager::new());
    let metrics = Arc::new(relay::FirehoseMetrics::new());
    let registry = Arc::new(relay::PeerRegistry::new(
        presence.clone(),
        rooms.clone(),
        metrics.clone(),
    ));
    let mesh_auth = Arc::new(relay::MeshAuthCache::new());

    // Background reporter: drain firehose counters every 10 s and emit a
    // single structured log line. Quiet windows are silent.
    let metrics_for_reporter = metrics.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_secs(10));
        interval.tick().await; // first tick is immediate; skip it
        loop {
            interval.tick().await;
            metrics_for_reporter.report_and_reset();
        }
    });

    let state = relay::AppState {
        registry,
        presence,
        rooms,
        mesh,
        outer_parser,
        mesh_auth,
        metrics,
    };
    let app = relay::build_router(state);

    let addr = format!("0.0.0.0:{port}");
    let listener = TcpListener::bind(&addr)
        .await
        .with_context(|| format!("failed to bind {addr}"))?;

    info!("relay listening on {addr} (WebSocket + /health + /mesh)");

    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(async {
        tokio::signal::ctrl_c()
            .await
            .expect("failed to install ctrl_c handler");
        info!("ctrl_c received, shutting down");
    })
    .await
    .context("axum::serve failed")?;

    Ok(())
}

/// Installs the global `tracing` subscriber.
///
/// Default: an `EnvFilter` built from `RUST_LOG` (fallback `info`) fanned out to
/// stdout only — matching the prior `tracing_subscriber::fmt::init()` behavior,
/// so bare-metal `cargo run` is unchanged.
///
/// When `OUTPOSTPI_RELAY_LOG_DIR` is set, additionally fans out to a
/// non-blocking daily-rotated file appender in that directory, so relay logs
/// survive stdout scroll/restart and become retroactively diagnosable (closes
/// the relay-side half of `idea-cross-side-logging-for-debug`). The returned
/// `WorkerGuard` must live for the program lifetime so buffered file records
/// flush on shutdown; `main` holds it in `_log_guard`.
///
/// Privacy: handler `tracing` calls log only routing metadata — shortened peer
/// tails, room ids, byte counts, frame type names, coarse reasons, and (on the
/// cross-PC `pi_envelope` path only) the envelope `id` tail, which is a
/// structural routing field already used for `re` correlation, not payload.
/// The app↔pi data-plane path stays payload-opaque (no message id). Never
/// `ct`, envelope bodies, prompts, output, or signatures (see
/// `.agents/skills/rust-relay/SKILL.md`).
fn init_tracing() -> Option<tracing_appender::non_blocking::WorkerGuard> {
    let filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));
    let stdout_layer = fmt::layer().with_writer(std::io::stdout);

    if let Ok(log_dir) = std::env::var("OUTPOSTPI_RELAY_LOG_DIR") {
        let file_appender = tracing_appender::rolling::daily(&log_dir, "relay.log");
        let (file_writer, file_guard) = tracing_appender::non_blocking(file_appender);
        let file_layer = fmt::layer().with_writer(file_writer);
        tracing_subscriber::registry()
            .with(filter)
            .with(stdout_layer)
            .with(file_layer)
            .init();
        info!(log_dir = %log_dir, "relay file logging enabled (daily rotation)");
        prune_old_relay_logs(&log_dir);
        Some(file_guard)
    } else {
        tracing_subscriber::registry()
            .with(filter)
            .with(stdout_layer)
            .init();
        None
    }
}

/// Delete rotated `relay.log.YYYY-MM-DD` files older than
/// `RELAY_LOG_RETENTION_DAYS`. `tracing-appender`'s `rolling::daily` rotates
/// but does not retain, so without this sweep one file per day accumulates
/// in the named volume without limit. Best-effort: a failure to read the dir
/// or delete a file is logged at `warn!` and skipped, never fatal — logging
/// must not break the relay.
fn prune_old_relay_logs(log_dir: &str) {
    let entries = match std::fs::read_dir(log_dir) {
        Ok(e) => e,
        Err(err) => {
            tracing::warn!(%err, log_dir, "failed to read relay log dir for retention sweep");
            return;
        }
    };
    let cutoff = std::time::SystemTime::now()
        - std::time::Duration::from_secs(60 * 60 * 24 * RELAY_LOG_RETENTION_DAYS);
    let mut pruned = 0u32;
    for entry in entries.flatten() {
        let path = entry.path();
        let name = match path.file_name().and_then(|n| n.to_str()) {
            Some(n) => n,
            None => continue,
        };
        // Only touch rotated files matching the appender's naming scheme.
        if !name.starts_with("relay.log.") {
            continue;
        }
        let modified = match entry.metadata().and_then(|m| m.modified()) {
            Ok(m) => m,
            Err(_) => continue,
        };
        if modified < cutoff {
            if let Err(err) = std::fs::remove_file(&path) {
                tracing::warn!(%err, ?path, "failed to prune old relay log file");
            } else {
                pruned += 1;
            }
        }
    }
    if pruned > 0 {
        info!(
            pruned,
            retention_days = RELAY_LOG_RETENTION_DAYS,
            "pruned old rotated relay log files"
        );
    }
}
