use boringtun::x25519::{PublicKey, StaticSecret};
use serde::Deserialize;

use crate::error::TunnelError;

#[derive(Debug, Clone, Deserialize)]
pub struct TunnelConfig {
    pub private_key: String,
    pub peer_public_key: String,
    pub peer_endpoint: String,
    pub addresses: Vec<String>,
    pub dns_servers: Vec<String>,
    pub mtu: u32,
    pub keepalive_seconds: u16,
}

pub struct ParsedConfig {
    pub private_key: StaticSecret,
    pub peer_public_key: PublicKey,
    pub peer_endpoint: String,
    pub addresses: Vec<String>,
    pub dns_servers: Vec<String>,
    pub mtu: u32,
    pub keepalive_seconds: u16,
}

fn decode_base64_key<const N: usize>(b64: &str, label: &str) -> Result<[u8; N], TunnelError> {
    let bytes = base64::Engine::decode(
        &base64::engine::general_purpose::STANDARD,
        b64,
    )
    .map_err(|e| TunnelError::InvalidKey(format!("{label}: base64 decode failed: {e}")))?;

    if bytes.len() != N {
        return Err(TunnelError::InvalidKey(format!(
            "{label}: expected {N} bytes, got {}",
            bytes.len()
        )));
    }

    let mut arr = [0u8; N];
    arr.copy_from_slice(&bytes);
    Ok(arr)
}

impl ParsedConfig {
    pub fn from_json(json: &str) -> Result<Self, TunnelError> {
        let cfg: TunnelConfig =
            serde_json::from_str(json).map_err(|e| TunnelError::Config(e.to_string()))?;
        Self::from_config(cfg)
    }

    pub fn from_config(cfg: TunnelConfig) -> Result<Self, TunnelError> {
        let private_bytes = decode_base64_key::<32>(&cfg.private_key, "private_key")?;
        let peer_bytes = decode_base64_key::<32>(&cfg.peer_public_key, "peer_public_key")?;

        let private_key = StaticSecret::from(private_bytes);
        let peer_public_key = PublicKey::from(peer_bytes);

        Ok(Self {
            private_key,
            peer_public_key,
            peer_endpoint: cfg.peer_endpoint,
            addresses: cfg.addresses,
            dns_servers: cfg.dns_servers,
            mtu: cfg.mtu,
            keepalive_seconds: cfg.keepalive_seconds,
        })
    }
}

pub fn generate_keypair() -> (String, String) {
    use rand::rngs::OsRng;
    let secret = StaticSecret::random_from_rng(OsRng);
    let public = PublicKey::from(&secret);

    let priv_b64 = base64::Engine::encode(
        &base64::engine::general_purpose::STANDARD,
        secret.as_bytes(),
    );
    let pub_b64 = base64::Engine::encode(
        &base64::engine::general_purpose::STANDARD,
        public.as_bytes(),
    );

    (priv_b64, pub_b64)
}
