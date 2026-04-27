use std::fmt;

#[derive(Debug)]
pub enum TunnelError {
    Config(String),
    WireGuard(String),
    Io(std::io::Error),
    InvalidKey(String),
    TunnelClosed,
}

impl fmt::Display for TunnelError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Config(s) => write!(f, "config error: {s}"),
            Self::WireGuard(s) => write!(f, "wireguard error: {s}"),
            Self::Io(e) => write!(f, "io error: {e}"),
            Self::InvalidKey(s) => write!(f, "invalid key: {s}"),
            Self::TunnelClosed => write!(f, "tunnel closed"),
        }
    }
}

impl std::error::Error for TunnelError {}

impl From<std::io::Error> for TunnelError {
    fn from(e: std::io::Error) -> Self {
        Self::Io(e)
    }
}
