use std::{env, net::SocketAddr};

use axum::{
    extract::Request,
    http::{header, HeaderValue},
    middleware::{self, Next},
    response::Response,
    routing::get,
    Router,
};
use tower_http::{services::ServeDir, trace::TraceLayer};

/// Extensões servidas como download (attachment) com cache imutável —
/// artefatos vivem em diretórios versionados, então a URL nunca é reusada.
const ARTIFACT_EXTENSIONS: [&str; 5] = [".dmg", ".exe", ".deb", ".rpm", ".zip"];

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "rp_s3=info,tower_http=info".into()),
        )
        .init();

    let data_dir = env::var("DATA_DIR").unwrap_or_else(|_| "/data".to_string());
    let port: u16 = env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8080);

    let app = Router::new()
        .route("/healthz", get(|| async { "ok" }))
        .nest_service(
            "/downloads",
            ServeDir::new(&data_dir).append_index_html_on_directories(false),
        )
        .layer(middleware::from_fn(set_download_headers))
        .layer(TraceLayer::new_for_http());

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .unwrap_or_else(|e| panic!("falha ao bindar {addr}: {e}"));
    tracing::info!("servindo {data_dir} em http://{addr}/downloads");
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .expect("servidor encerrou com erro");
}

async fn set_download_headers(req: Request, next: Next) -> Response {
    let path = req.uri().path().to_owned();
    let mut res = next.run(req).await;
    if !path.starts_with("/downloads") || !res.status().is_success() {
        return res;
    }

    let headers = res.headers_mut();
    // O site (Next.js) e qualquer cliente podem ler o manifest de outro domínio.
    headers.insert(
        header::ACCESS_CONTROL_ALLOW_ORIGIN,
        HeaderValue::from_static("*"),
    );

    let lower = path.to_lowercase();
    if ARTIFACT_EXTENSIONS.iter().any(|ext| lower.ends_with(ext)) {
        headers.insert(
            header::CACHE_CONTROL,
            HeaderValue::from_static("public, max-age=31536000, immutable"),
        );
        if let Some(name) = path.rsplit('/').next() {
            if let Ok(value) = HeaderValue::from_str(&format!("attachment; filename=\"{name}\"")) {
                headers.insert(header::CONTENT_DISPOSITION, value);
            }
        }
    } else {
        // latest.json / SHA256SUMS: URL fixa, release novo precisa propagar rápido.
        headers.insert(
            header::CACHE_CONTROL,
            HeaderValue::from_static("public, max-age=300"),
        );
    }
    res
}

async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("instalar handler de Ctrl+C");
    };

    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("instalar handler de SIGTERM")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
}
