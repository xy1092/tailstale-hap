use std::sync::Mutex;
use std::time::Instant;

use boringtun::noise::{Tunn, TunnResult};

use crate::config::ParsedConfig;
use crate::error::TunnelError;

pub struct TunnelStats {
    pub handshake_completed: bool,
    pub tx_bytes: u64,
    pub rx_bytes: u64,
    pub last_handshake: Option<u64>,
    pub peer_endpoint: String,
}

struct Inner {
    tunn: Tunn,
    handshake_done: bool,
    tx_bytes: u64,
    rx_bytes: u64,
    last_handshake: Option<Instant>,
    running: bool,
    peer_endpoint: String,
    addresses: Vec<String>,
    dns_servers: Vec<String>,
    mtu: u32,
}

pub struct TunnelManager {
    inner: Mutex<Inner>,
    out_buf: Mutex<Vec<u8>>,
}

impl TunnelManager {
    pub fn new(config: &ParsedConfig) -> Result<Self, TunnelError> {
        let index: u32 = rand::random();

        let tunn = Tunn::new(
            config.private_key.clone(),
            config.peer_public_key,
            None,
            Some(config.keepalive_seconds),
            index,
            None,
        );

        let inner = Inner {
            tunn,
            handshake_done: false,
            tx_bytes: 0,
            rx_bytes: 0,
            last_handshake: None,
            running: true,
            peer_endpoint: config.peer_endpoint.clone(),
            addresses: config.addresses.clone(),
            dns_servers: config.dns_servers.clone(),
            mtu: config.mtu,
        };

        Ok(Self {
            inner: Mutex::new(inner),
            out_buf: Mutex::new(vec![0u8; 65536]),
        })
    }

    #[allow(dead_code)]
    pub fn config_info(&self) -> (Vec<String>, Vec<String>, u32) {
        let inner = self.inner.lock().unwrap();
        (inner.addresses.clone(), inner.dns_servers.clone(), inner.mtu)
    }

    /// Process a packet from TUN (outgoing → encrypt for WireGuard).
    /// Returns the encrypted packet to send over the network, or None.
    pub fn process_outgoing(&self, packet: &[u8]) -> Result<Option<Vec<u8>>, TunnelError> {
        let mut inner = self.inner.lock().unwrap();
        if !inner.running {
            return Err(TunnelError::TunnelClosed);
        }

        let mut out_buf = self.out_buf.lock().unwrap();
        out_buf.fill(0);

        let mut result = inner.tunn.encapsulate(packet, &mut out_buf);

        loop {
            match result {
                TunnResult::Done => return Ok(None),
                TunnResult::WriteToNetwork(data) => {
                    let len = data.len();
                    inner.tx_bytes += len as u64;
                    return Ok(Some(out_buf[..len].to_vec()));
                }
                TunnResult::WriteToTunnelV4(..) | TunnResult::WriteToTunnelV6(..) => {
                    inner.rx_bytes += packet.len() as u64;
                    result = inner.tunn.encapsulate(&[], &mut out_buf);
                }
                TunnResult::Err(e) => {
                    return Err(TunnelError::WireGuard(format!("{e:?}")));
                }
            }
        }
    }

    /// Process a WireGuard packet from the network (incoming → decrypt for TUN).
    /// Returns the decrypted IP packet, or None.
    pub fn process_incoming(&self, packet: &[u8]) -> Result<Option<Vec<u8>>, TunnelError> {
        let mut inner = self.inner.lock().unwrap();
        if !inner.running {
            return Err(TunnelError::TunnelClosed);
        }

        let mut out_buf = self.out_buf.lock().unwrap();
        out_buf.fill(0);

        let mut result = inner.tunn.decapsulate(None, packet, &mut out_buf);

        loop {
            match result {
                TunnResult::Done => return Ok(None),
                TunnResult::WriteToTunnelV4(data, _addr) => {
                    let len = data.len();
                    inner.rx_bytes += len as u64;

                    if !inner.handshake_done {
                        inner.handshake_done = true;
                        inner.last_handshake = Some(Instant::now());
                    }

                    return Ok(Some(out_buf[..len].to_vec()));
                }
                TunnResult::WriteToTunnelV6(data, _addr) => {
                    let len = data.len();
                    inner.rx_bytes += len as u64;

                    if !inner.handshake_done {
                        inner.handshake_done = true;
                        inner.last_handshake = Some(Instant::now());
                    }

                    return Ok(Some(out_buf[..len].to_vec()));
                }
                TunnResult::WriteToNetwork(data) => {
                    let len = data.len();
                    inner.tx_bytes += len as u64;
                    // Drain: repeat with empty datagram until Done
                    result = inner.tunn.decapsulate(None, &[], &mut out_buf);
                    let _ = len;
                }
                TunnResult::Err(e) => {
                    return Err(TunnelError::WireGuard(format!("{e:?}")));
                }
            }
        }
    }

    pub fn stats(&self) -> Result<TunnelStats, TunnelError> {
        let inner = self.inner.lock().unwrap();
        Ok(TunnelStats {
            handshake_completed: inner.handshake_done,
            tx_bytes: inner.tx_bytes,
            rx_bytes: inner.rx_bytes,
            last_handshake: inner
                .last_handshake
                .map(|t| t.elapsed().as_secs()),
            peer_endpoint: inner.peer_endpoint.clone(),
        })
    }

    pub fn stop(&self) {
        let mut inner = self.inner.lock().unwrap();
        inner.running = false;
    }
}

impl TunnelStats {
    pub fn to_json(&self) -> String {
        serde_json::json!({
            "handshake_completed": self.handshake_completed,
            "tx_bytes": self.tx_bytes,
            "rx_bytes": self.rx_bytes,
            "last_handshake_secs_ago": self.last_handshake,
            "peer_endpoint": self.peer_endpoint,
        })
        .to_string()
    }
}
