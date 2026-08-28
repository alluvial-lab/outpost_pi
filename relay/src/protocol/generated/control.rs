// GENERATED CODE - DO NOT EDIT BY HAND.
// Source: protocol/schema/manifest.json via protocol-codegen IR.
// Module: control.

#![allow(dead_code)]

use super::room::{RoomMeta, RoomMetaPatch};
use serde::{Deserialize, Serialize};

pub const RELAY_AUTH_DOMAIN_PREFIX: &[u8] = b"outpost-pi-relay-auth-v1\n";

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientAuthMsg {
    Hello {
        pubkey: String,
        device_id: String,
        #[serde(default = "default_room")]
        room_id: String,
        #[serde(default)]
        room_meta: Option<HelloRoomMeta>,
    },
    Auth {
        sig: String,
    },
}

#[derive(Debug, Default, Clone, Deserialize)]
pub struct HelloRoomMeta {
    pub name: Option<String>,
    pub cwd: Option<String>,
    pub model: Option<String>,
    pub thinking: Option<String>,
    pub session_id: Option<String>,
    #[serde(default)]
    pub working: bool,
    #[serde(default)]
    pub background: bool,
}

fn default_room() -> String {
    "main".to_string()
}

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ServerAuthMsg {
    Challenge { nonce: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RelayPresenceState {
    pub peer: String,
    pub online: bool,
    pub since_ts: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum RelayServerControlFrame {
    #[serde(rename = "peer_offline")]
    PeerOffline { peer: String, since_ts: i64 },
    #[serde(rename = "peer_online")]
    PeerOnline { peer: String },
    #[serde(rename = "presence")]
    Presence { states: Vec<RelayPresenceState> },
    #[serde(rename = "room_announced")]
    RoomAnnounced {
        peer: String,
        #[serde(flatten)]
        room: RoomMeta,
    },
    #[serde(rename = "room_ended")]
    RoomEnded {
        peer: String,
        room_id: String,
        since_ts: i64,
    },
    #[serde(rename = "rooms")]
    Rooms { peer: String, rooms: Vec<RoomMeta> },
}

pub const RELAY_SERVER_CONTROL_FRAME_TYPES: &[&str] = &[
    "peer_offline",
    "peer_online",
    "presence",
    "room_announced",
    "room_ended",
    "rooms",
];

#[derive(Debug, Clone, Deserialize)]
pub struct RoomMetaUpdateFrame {
    #[serde(default)]
    pub room_id: Option<String>,
    pub meta: RoomMetaPatch,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum RelayControlFrame {
    #[serde(rename = "presence_check")]
    PresenceCheck {
        #[serde(default)]
        peers: Vec<String>,
    },
    #[serde(rename = "room_meta_update")]
    RoomMetaUpdate(RoomMetaUpdateFrame),
    #[serde(rename = "rooms_check")]
    RoomsCheck {
        #[serde(default)]
        peers: Vec<String>,
    },
    #[serde(rename = "subscribe_presence")]
    SubscribePresence {
        #[serde(default)]
        peers: Vec<String>,
    },
    #[serde(rename = "subscribe_rooms")]
    SubscribeRooms {
        #[serde(default)]
        peers: Vec<String>,
    },
    #[serde(rename = "unsubscribe_presence")]
    UnsubscribePresence {
        #[serde(default)]
        peers: Vec<String>,
    },
    #[serde(rename = "unsubscribe_rooms")]
    UnsubscribeRooms {
        #[serde(default)]
        peers: Vec<String>,
    },
}

impl RelayControlFrame {
    pub const fn wire_type(&self) -> &'static str {
        match self {
            Self::PresenceCheck { .. } => "presence_check",
            Self::RoomMetaUpdate(..) => "room_meta_update",
            Self::RoomsCheck { .. } => "rooms_check",
            Self::SubscribePresence { .. } => "subscribe_presence",
            Self::SubscribeRooms { .. } => "subscribe_rooms",
            Self::UnsubscribePresence { .. } => "unsubscribe_presence",
            Self::UnsubscribeRooms { .. } => "unsubscribe_rooms",
        }
    }
}

pub const RELAY_CONTROL_FRAME_TYPES: &[&str] = &[
    "presence_check",
    "room_meta_update",
    "rooms_check",
    "subscribe_presence",
    "subscribe_rooms",
    "unsubscribe_presence",
    "unsubscribe_rooms",
];

pub fn is_relay_control_frame_type(frame_type: &str) -> bool {
    RELAY_CONTROL_FRAME_TYPES.contains(&frame_type)
}
