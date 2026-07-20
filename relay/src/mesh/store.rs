use std::path::Path;
use std::sync::Mutex;

use rusqlite::{Connection, OptionalExtension, params};

use crate::resource_limits::{
    FixedWindowBudget, MAX_MESH_OWNER_ROWS, MAX_MESH_RETAINED_BYTES,
    MAX_NEW_MESH_OWNERS_PER_WINDOW, NEW_MESH_OWNER_WINDOW,
};

use super::types::{MeshEnvelope, MeshRecord};

/// Describes SQLite, filesystem, and monotonic-version failures in mesh storage.
#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("sqlite: {0}")]
    Sql(#[from] rusqlite::Error),
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("monotonic version violation: new={new} <= current={current}")]
    StaleVersion { new: u64, current: u64 },
    #[error("mesh retained-state quota exceeded: {resource}")]
    QuotaExceeded { resource: &'static str },
    #[error("new mesh Owner creation rate exceeded")]
    NewOwnerRateLimited,
}

const SCHEMA: &str = include_str!("../../migrations/001_mesh_versions.sql");

#[derive(Debug, Clone, Copy)]
struct MeshStoreLimits {
    max_owner_rows: usize,
    max_retained_bytes: usize,
    new_owner_window: std::time::Duration,
    max_new_owners_per_window: usize,
}

impl Default for MeshStoreLimits {
    fn default() -> Self {
        Self {
            max_owner_rows: MAX_MESH_OWNER_ROWS,
            max_retained_bytes: MAX_MESH_RETAINED_BYTES,
            new_owner_window: NEW_MESH_OWNER_WINDOW,
            max_new_owners_per_window: MAX_NEW_MESH_OWNERS_PER_WINDOW,
        }
    }
}

/// Mesh blob storage backed by SQLite. Single-table UPSERT keyed by
/// `owner_pk_hash`. Thread-safe via `std::sync::Mutex<Connection>`.
pub struct MeshStore {
    conn: Mutex<Connection>,
    limits: MeshStoreLimits,
    new_owner_budget: Mutex<FixedWindowBudget>,
}

impl std::fmt::Debug for MeshStore {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("MeshStore").finish_non_exhaustive()
    }
}

impl MeshStore {
    /// Opens (or creates) the SQLite database at `path` and applies the
    /// schema migration idempotently. The parent directory is created if it
    /// doesn't exist — so callers can pass nested paths like `data/mesh.db`
    /// on first boot without pre-creating the folder.
    ///
    /// SQLite runs in the default (rollback-journal) mode — only `mesh.db`
    /// persists; a transient `mesh.db-journal` may appear briefly during a
    /// write transaction and is deleted on commit. WAL mode is NOT enabled.
    ///
    /// # Errors
    ///
    /// Returns [`StoreError::Sql`] if SQLite cannot open or initialize the
    /// schema, or [`StoreError::Io`] on a filesystem failure.
    pub fn open(path: impl AsRef<Path>) -> Result<Self, StoreError> {
        let path = path.as_ref();
        if let Some(parent) = path.parent()
            && !parent.as_os_str().is_empty()
        {
            std::fs::create_dir_all(parent)?;
        }
        let conn = Connection::open(path)?;
        conn.execute_batch(SCHEMA)?;
        Ok(Self::from_connection(conn, MeshStoreLimits::default()))
    }

    /// Opens an in-memory database (for tests).
    pub fn open_in_memory() -> Result<Self, StoreError> {
        let conn = Connection::open_in_memory()?;
        conn.execute_batch(SCHEMA)?;
        Ok(Self::from_connection(conn, MeshStoreLimits::default()))
    }

    fn from_connection(conn: Connection, limits: MeshStoreLimits) -> Self {
        Self {
            conn: Mutex::new(conn),
            limits,
            new_owner_budget: Mutex::new(FixedWindowBudget::new(
                limits.new_owner_window,
                limits.max_new_owners_per_window,
            )),
        }
    }

    /// Returns the current version for `owner_pk_hash`, or `None` if absent.
    ///
    /// # Errors
    ///
    /// Returns [`StoreError::Sql`] if the query fails.
    pub fn current_version(&self, owner_pk_hash: &str) -> Result<Option<u64>, StoreError> {
        let conn = self.conn.lock().expect("mesh store mutex poisoned");
        let v: Option<i64> = conn
            .query_row(
                "SELECT version FROM mesh_versions WHERE owner_pk_hash = ?1",
                params![owner_pk_hash],
                |r| r.get(0),
            )
            .optional()?;
        Ok(v.map(|n| n as u64))
    }

    /// UPSERTs a strictly newer row while enforcing deployment-wide retained-state admission.
    ///
    /// Existing Owners may replace their row without consuming the new-Owner
    /// rate budget. When a database already exceeds the byte quota, updates
    /// that do not increase retained bytes remain allowed so state can converge.
    /// All checks and the write run inside one SQLite transaction.
    ///
    /// # Errors
    ///
    /// Returns [`StoreError::StaleVersion`] for a non-increasing version,
    /// [`StoreError::QuotaExceeded`] when a write would grow storage past its
    /// row or byte ceiling, [`StoreError::NewOwnerRateLimited`] when creation
    /// admission is exhausted, or [`StoreError::Sql`] on a database failure.
    pub fn upsert(
        &self,
        owner_pk_hash: &str,
        owner_pk: &[u8],
        new_version: u64,
        blob: &[u8],
        sig: &[u8],
        updated_at_ms: i64,
    ) -> Result<(), StoreError> {
        let mut conn = self.conn.lock().expect("mesh store mutex poisoned");
        let tx = conn.transaction()?;
        let current: Option<(i64, i64)> = tx
            .query_row(
                "SELECT version,
                        length(owner_pk_hash) + length(owner_pk) + length(blob) + length(sig)
                 FROM mesh_versions WHERE owner_pk_hash = ?1",
                params![owner_pk_hash],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()?;
        if let Some((current_version, _)) = current {
            let current_version = current_version as u64;
            if new_version <= current_version {
                return Err(StoreError::StaleVersion {
                    new: new_version,
                    current: current_version,
                });
            }
        }

        let (owner_rows, retained_bytes): (i64, i64) = tx.query_row(
            "SELECT COUNT(*),
                    COALESCE(SUM(length(owner_pk_hash) + length(owner_pk) + length(blob) + length(sig)), 0)
             FROM mesh_versions",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )?;
        let is_new_owner = current.is_none();
        if is_new_owner && owner_rows as usize >= self.limits.max_owner_rows {
            return Err(StoreError::QuotaExceeded {
                resource: "owner_rows",
            });
        }

        let proposed_bytes = owner_pk_hash
            .len()
            .saturating_add(owner_pk.len())
            .saturating_add(blob.len())
            .saturating_add(sig.len());
        let current_bytes = current.map_or(0, |(_, bytes)| bytes as usize);
        let retained_bytes = retained_bytes as usize;
        let projected_bytes = retained_bytes
            .saturating_sub(current_bytes)
            .saturating_add(proposed_bytes);
        if projected_bytes > self.limits.max_retained_bytes && projected_bytes > retained_bytes {
            return Err(StoreError::QuotaExceeded {
                resource: "retained_bytes",
            });
        }

        if is_new_owner
            && !self
                .new_owner_budget
                .lock()
                .expect("mesh new-Owner budget mutex poisoned")
                .allow(1)
        {
            return Err(StoreError::NewOwnerRateLimited);
        }

        tx.execute(
            "INSERT INTO mesh_versions (owner_pk_hash, owner_pk, version, blob, sig, updated_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)
             ON CONFLICT(owner_pk_hash) DO UPDATE SET
                 owner_pk   = excluded.owner_pk,
                 version    = excluded.version,
                 blob       = excluded.blob,
                 sig        = excluded.sig,
                 updated_at = excluded.updated_at",
            params![
                owner_pk_hash,
                owner_pk,
                new_version as i64,
                blob,
                sig,
                updated_at_ms,
            ],
        )?;
        tx.commit()?;
        Ok(())
    }

    /// Returns every stored mesh envelope with its row key. Used by mesh
    /// authorization to re-verify Owner signatures before trusting members.
    ///
    /// # Errors
    ///
    /// Returns [`StoreError::Sql`] if the query or row deserialization fails.
    pub fn all_envelopes(&self) -> Result<Vec<(String, MeshEnvelope)>, StoreError> {
        let conn = self.conn.lock().expect("mesh store mutex poisoned");
        let mut stmt = conn.prepare("SELECT owner_pk_hash, blob, sig FROM mesh_versions")?;
        let rows: Result<Vec<(String, MeshEnvelope)>, _> = stmt
            .query_map([], |r| {
                Ok((
                    r.get::<_, String>(0)?,
                    MeshEnvelope {
                        blob: r.get(1)?,
                        sig: r.get(2)?,
                    },
                ))
            })?
            .collect();
        Ok(rows?)
    }

    /// Fetches the current record for `owner_pk_hash`, or `None` if absent.
    ///
    /// # Errors
    ///
    /// Returns [`StoreError::Sql`] if the query fails.
    pub fn get(&self, owner_pk_hash: &str) -> Result<Option<MeshRecord>, StoreError> {
        let conn = self.conn.lock().expect("mesh store mutex poisoned");
        let row = conn
            .query_row(
                "SELECT version, blob, sig, updated_at
                 FROM mesh_versions WHERE owner_pk_hash = ?1",
                params![owner_pk_hash],
                |r| {
                    Ok(MeshRecord {
                        version: r.get::<_, i64>(0)? as u64,
                        blob: r.get(1)?,
                        sig: r.get(2)?,
                        updated_at: r.get(3)?,
                    })
                },
            )
            .optional()?;
        Ok(row)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fake_pk() -> Vec<u8> {
        vec![0u8; 32]
    }

    #[test]
    fn upsert_then_get_roundtrip() {
        let store = MeshStore::open_in_memory().unwrap();
        store
            .upsert("abc", &fake_pk(), 1, b"{\"version\":1}", &[0u8; 64], 100)
            .unwrap();
        let rec = store.get("abc").unwrap().unwrap();
        assert_eq!(rec.version, 1);
        assert_eq!(rec.updated_at, 100);
    }

    #[test]
    fn upsert_rejects_stale_version() {
        let store = MeshStore::open_in_memory().unwrap();
        store
            .upsert("abc", &fake_pk(), 5, b"v5", &[0u8; 64], 100)
            .unwrap();
        let err = store
            .upsert("abc", &fake_pk(), 5, b"v5", &[0u8; 64], 200)
            .unwrap_err();
        assert!(matches!(
            err,
            StoreError::StaleVersion { new: 5, current: 5 }
        ));
        let err = store
            .upsert("abc", &fake_pk(), 3, b"v3", &[0u8; 64], 200)
            .unwrap_err();
        assert!(matches!(
            err,
            StoreError::StaleVersion { new: 3, current: 5 }
        ));
        // current still 5
        assert_eq!(store.current_version("abc").unwrap(), Some(5));
    }

    #[test]
    fn upsert_advances_version() {
        let store = MeshStore::open_in_memory().unwrap();
        store
            .upsert("abc", &fake_pk(), 1, b"v1", &[0u8; 64], 100)
            .unwrap();
        store
            .upsert("abc", &fake_pk(), 2, b"v2", &[0u8; 64], 200)
            .unwrap();
        let rec = store.get("abc").unwrap().unwrap();
        assert_eq!(rec.version, 2);
        assert_eq!(rec.blob, b"v2");
        assert_eq!(rec.updated_at, 200);
    }

    #[test]
    fn upsert_bounds_retained_bytes() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(SCHEMA).unwrap();
        let store = MeshStore::from_connection(
            conn,
            MeshStoreLimits {
                max_owner_rows: 10,
                max_retained_bytes: 101,
                new_owner_window: std::time::Duration::from_secs(60),
                max_new_owners_per_window: 10,
            },
        );
        store
            .upsert("a", &fake_pk(), 1, b"mesh", &[0u8; 64], 100)
            .unwrap();

        let err = store
            .upsert("a", &fake_pk(), 2, b"mesh!", &[0u8; 64], 200)
            .unwrap_err();

        assert!(matches!(
            err,
            StoreError::QuotaExceeded {
                resource: "retained_bytes"
            }
        ));
        assert_eq!(store.get("a").unwrap().unwrap().blob, b"mesh");
    }

    #[tokio::test(start_paused = true)]
    async fn upsert_rate_limits_distinct_owner_creation() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(SCHEMA).unwrap();
        let window = std::time::Duration::from_secs(60);
        let store = MeshStore::from_connection(
            conn,
            MeshStoreLimits {
                max_owner_rows: 10,
                max_retained_bytes: usize::MAX,
                new_owner_window: window,
                max_new_owners_per_window: 2,
            },
        );
        store
            .upsert("a", &fake_pk(), 1, b"mesh", &[0u8; 64], 100)
            .unwrap();
        store
            .upsert("b", &fake_pk(), 1, b"mesh", &[0u8; 64], 100)
            .unwrap();

        let err = store
            .upsert("c", &fake_pk(), 1, b"mesh", &[0u8; 64], 100)
            .unwrap_err();
        assert!(matches!(err, StoreError::NewOwnerRateLimited));
        assert!(store.get("c").unwrap().is_none());

        tokio::time::advance(window).await;
        store
            .upsert("c", &fake_pk(), 1, b"mesh", &[0u8; 64], 100)
            .unwrap();
    }

    #[tokio::test(start_paused = true)]
    async fn upsert_bounds_distinct_owner_rows() {
        let store = MeshStore::open_in_memory().unwrap();
        for index in 0..MAX_MESH_OWNER_ROWS {
            if index > 0 && index % MAX_NEW_MESH_OWNERS_PER_WINDOW == 0 {
                tokio::time::advance(NEW_MESH_OWNER_WINDOW).await;
            }
            store
                .upsert(
                    &format!("{index:064x}"),
                    &fake_pk(),
                    1,
                    b"mesh",
                    &[0u8; 64],
                    index as i64,
                )
                .unwrap();
        }

        tokio::time::advance(NEW_MESH_OWNER_WINDOW).await;
        let overflow = store.upsert(
            &format!("{:064x}", MAX_MESH_OWNER_ROWS),
            &fake_pk(),
            1,
            b"mesh",
            &[0u8; 64],
            MAX_MESH_OWNER_ROWS as i64,
        );

        assert!(matches!(
            overflow,
            Err(StoreError::QuotaExceeded {
                resource: "owner_rows"
            })
        ));
        assert_eq!(store.all_envelopes().unwrap().len(), MAX_MESH_OWNER_ROWS);
    }

    #[test]
    fn get_missing_returns_none() {
        let store = MeshStore::open_in_memory().unwrap();
        assert!(store.get("nope").unwrap().is_none());
        assert_eq!(store.current_version("nope").unwrap(), None);
    }
}
