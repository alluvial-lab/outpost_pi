use std::collections::HashSet;

use serde::Deserialize;
use thiserror::Error;

pub use crate::protocol::generated::mesh::{
    MeshEnvelopeWire, MeshGetQuery, MeshGetResponse, MeshPostResponse,
};

/// Decoded envelope after base64-decoding the wire fields.
/// The `blob` bytes are the canonical-JSON payload that was signed;
/// the relay never re-canonicalizes — it only verifies the bytes received.
#[derive(Debug, Clone)]
pub struct MeshEnvelope {
    pub blob: Vec<u8>,
    pub sig: Vec<u8>,
}

/// Header extracted from `blob` JSON. Members and other fields exist in the
/// blob but are NOT inspected by the relay — only `version` and `owner_pk`
/// are needed for verification + storage.
#[derive(Debug, Deserialize)]
pub struct MeshHeader {
    pub version: u64,
    pub owner_pk: String, // base64 STANDARD
}

/// Stored row returned by `MeshStore::get`.
#[derive(Debug, Clone)]
pub struct MeshRecord {
    pub version: u64,
    pub blob: Vec<u8>,
    pub sig: Vec<u8>,
    pub updated_at: i64,
}

/// Signed mesh-blob projection used only for membership authorization.
///
/// Every member must have a string `remote_epk`; malformed entries reject the
/// entire record so authorization can never be derived from a partial blob.
#[derive(Debug, Deserialize)]
pub(crate) struct MeshMembersBlob {
    pub(crate) members: Vec<MeshMember>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct MeshMember {
    pub(crate) remote_epk: String,
}

/// Reports a signed mesh blob that cannot supply a complete member projection.
#[derive(Debug, Error)]
pub(crate) enum MeshMembersDecodeError {
    #[error("invalid mesh members blob: {0}")]
    InvalidJson(#[from] serde_json::Error),
}

/// Decode all member identities from an already-verified signed mesh blob.
///
/// Unknown fields are intentionally tolerated for forward compatibility, while
/// missing or wrongly typed membership fields fail the entire authorization
/// projection.
pub(crate) fn decode_member_keys(blob: &[u8]) -> Result<HashSet<String>, MeshMembersDecodeError> {
    let members: MeshMembersBlob = serde_json::from_slice(blob)?;
    Ok(members
        .members
        .into_iter()
        .map(|member| member.remote_epk)
        .collect())
}

#[cfg(test)]
mod tests {
    use super::decode_member_keys;

    #[test]
    fn decodes_every_typed_member_key() {
        let keys =
            decode_member_keys(br#"{"members":[{"remote_epk":"pi_a"},{"remote_epk":"pi_b"}]}"#)
                .expect("well-formed members blob must decode");

        assert_eq!(keys.len(), 2);
        assert!(keys.contains("pi_a"));
        assert!(keys.contains("pi_b"));
    }

    #[test]
    fn rejects_non_array_members() {
        assert!(decode_member_keys(br#"{"members":{}}"#).is_err());
    }

    #[test]
    fn rejects_any_member_without_a_string_remote_epk() {
        assert!(
            decode_member_keys(br#"{"members":[{"remote_epk":"pi_a"},{"remote_epk":7}]}"#,)
                .is_err()
        );
    }
}
