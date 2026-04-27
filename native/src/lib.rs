mod config;
mod error;
mod r#loop;
mod wireguard;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::{Arc, Mutex, OnceLock};

use config::{generate_keypair, ParsedConfig};
use wireguard::TunnelManager;

static TUNNEL: OnceLock<Mutex<Option<Arc<TunnelManager>>>> = OnceLock::new();
static LOOP_HANDLE: OnceLock<Mutex<Option<crate::r#loop::LoopHandle>>> = OnceLock::new();

fn get_tunnel() -> &'static Mutex<Option<Arc<TunnelManager>>> {
    TUNNEL.get_or_init(|| Mutex::new(None))
}

fn get_loop_handle() -> &'static Mutex<Option<crate::r#loop::LoopHandle>> {
    LOOP_HANDLE.get_or_init(|| Mutex::new(None))
}

unsafe fn cstr_to_str<'a>(ptr: *const c_char) -> Result<&'a str, String> {
    if ptr.is_null() {
        return Err("null pointer".into());
    }
    CStr::from_ptr(ptr)
        .to_str()
        .map_err(|e| format!("invalid utf8: {e}"))
}

fn make_c_string(s: String) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

// ── Key Management ──────────────────────────────────────────

#[no_mangle]
pub extern "C" fn wg_generate_keypair() -> *mut c_char {
    let (priv_key, pub_key) = generate_keypair();
    let json = serde_json::json!({
        "private_key": priv_key,
        "public_key": pub_key,
    })
    .to_string();
    make_c_string(json)
}

// ── Tunnel Lifecycle ────────────────────────────────────────

#[no_mangle]
pub extern "C" fn wg_init_tunnel(config_json: *const c_char) -> *mut c_char {
    let result = (|| -> Result<String, String> {
        let json = unsafe { cstr_to_str(config_json)? };
        let config = ParsedConfig::from_json(json).map_err(|e| e.to_string())?;
        let tunnel = Arc::new(TunnelManager::new(&config).map_err(|e| e.to_string())?);

        let mut guard = get_tunnel().lock().unwrap();
        *guard = Some(tunnel);

        Ok(r#"{"ok":true}"#.into())
    })();

    match result {
        Ok(s) => make_c_string(s),
        Err(e) => make_c_string(format!(r#"{{"ok":false,"error":"{}"}}"#, e.replace('"', "'"))),
    }
}

#[no_mangle]
pub extern "C" fn wg_get_stats() -> *mut c_char {
    let guard = get_tunnel().lock().unwrap();
    match guard.as_ref() {
        Some(tunnel) => match tunnel.stats() {
            Ok(s) => make_c_string(s.to_json()),
            Err(e) => make_c_string(format!(r#"{{"error":"{}"}}"#, e)),
        },
        None => make_c_string(r#"{"error":"no active tunnel"}"#.into()),
    }
}

#[no_mangle]
pub extern "C" fn wg_close_tunnel() -> *mut c_char {
    // Stop the I/O loop first
    let mut loop_guard = get_loop_handle().lock().unwrap();
    if let Some(mut handle) = loop_guard.take() {
        handle.stop();
    }
    drop(loop_guard);

    let mut guard = get_tunnel().lock().unwrap();
    if let Some(tunnel) = guard.take() {
        tunnel.stop();
        make_c_string(r#"{"ok":true}"#.into())
    } else {
        make_c_string(r#"{"ok":false,"error":"no active tunnel"}"#.into())
    }
}

// ── Packet Processing (single-shot, for simple usage) ──────

#[no_mangle]
pub extern "C" fn wg_process_tun_packet(
    data: *const u8,
    len: u32,
    out_len: *mut u32,
) -> *mut u8 {
    let guard = get_tunnel().lock().unwrap();
    let tunnel = match guard.as_ref() {
        Some(t) => t,
        None => {
            unsafe { *out_len = 0 };
            return std::ptr::null_mut();
        }
    };

    let packet = unsafe { std::slice::from_raw_parts(data, len as usize) };

    match tunnel.process_outgoing(packet) {
        Ok(Some(output)) => {
            let mut buf = output.into_boxed_slice();
            let ptr = buf.as_mut_ptr();
            unsafe { *out_len = buf.len() as u32 };
            std::mem::forget(buf);
            ptr
        }
        _ => {
            unsafe { *out_len = 0 };
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn wg_process_network_packet(
    data: *const u8,
    len: u32,
    out_len: *mut u32,
) -> *mut u8 {
    let guard = get_tunnel().lock().unwrap();
    let tunnel = match guard.as_ref() {
        Some(t) => t,
        None => {
            unsafe { *out_len = 0 };
            return std::ptr::null_mut();
        }
    };

    let packet = unsafe { std::slice::from_raw_parts(data, len as usize) };

    match tunnel.process_incoming(packet) {
        Ok(Some(output)) => {
            let mut buf = output.into_boxed_slice();
            let ptr = buf.as_mut_ptr();
            unsafe { *out_len = buf.len() as u32 };
            std::mem::forget(buf);
            ptr
        }
        _ => {
            unsafe { *out_len = 0 };
            std::ptr::null_mut()
        }
    }
}

// ── Tunnel I/O Loop ─────────────────────────────────────────

/// Create a connected UDP socket for WireGuard traffic.
/// Returns the file descriptor (0 on error).
#[no_mangle]
pub extern "C" fn wg_create_socket(endpoint: *const c_char) -> i32 {
    let addr_str = match unsafe { cstr_to_str(endpoint) } {
        Ok(s) => s,
        Err(_) => return 0,
    };

    // Parse "ip:port" into sockaddr
    let (host, port_str) = match addr_str.rsplit_once(':') {
        Some(p) => p,
        None => return 0,
    };
    let port: u16 = match port_str.parse() {
        Ok(p) => p,
        Err(_) => return 0,
    };

    let sock = unsafe { libc::socket(libc::AF_INET, libc::SOCK_DGRAM, 0) };
    if sock < 0 {
        return 0;
    }

    // Set non-blocking
    let flags = unsafe { libc::fcntl(sock, libc::F_GETFL, 0) };
    if flags >= 0 {
        unsafe { libc::fcntl(sock, libc::F_SETFL, flags | libc::O_NONBLOCK) };
    }

    // Resolve host and connect
    let addr_bytes: std::net::Ipv4Addr = match host.parse() {
        Ok(a) => a,
        Err(_) => {
            unsafe { libc::close(sock) };
            return 0;
        }
    };

    let addr: libc::sockaddr_in = {
        let octets = addr_bytes.octets();
        libc::sockaddr_in {
            sin_family: libc::AF_INET as u16,
            sin_port: port.to_be(),
            sin_addr: libc::in_addr {
                s_addr: u32::from_ne_bytes(octets),
            },
            sin_zero: [0u8; 8],
        }
    };

    let ret = unsafe {
        libc::connect(
            sock,
            &addr as *const _ as *const libc::sockaddr,
            std::mem::size_of::<libc::sockaddr_in>() as u32,
        )
    };

    if ret < 0 {
        unsafe { libc::close(sock) };
        return 0;
    }

    sock
}

/// Start the background I/O loop: reads TUN, encrypts, sends via socket
#[no_mangle]
pub extern "C" fn wg_start_loop(tun_fd: i32, sock_fd: i32) -> *mut c_char {
    let result = (|| -> Result<String, String> {
        let guard = get_tunnel().lock().unwrap();
        let tunnel = guard
            .as_ref()
            .ok_or("no tunnel initialized")?
            .clone();
        drop(guard);

        let handle = crate::r#loop::start_tunnel_loop(tunnel, tun_fd, sock_fd);

        let mut loop_guard = get_loop_handle().lock().unwrap();
        *loop_guard = Some(handle);

        Ok(r#"{"ok":true}"#.into())
    })();

    match result {
        Ok(s) => make_c_string(s),
        Err(e) => make_c_string(format!(r#"{{"ok":false,"error":"{}"}}"#, e)),
    }
}

/// Stop the background I/O loop (no-op if not running)
#[no_mangle]
pub extern "C" fn wg_stop_loop() -> *mut c_char {
    let mut guard = get_loop_handle().lock().unwrap();
    if let Some(mut handle) = guard.take() {
        handle.stop();
        make_c_string(r#"{"ok":true}"#.into())
    } else {
        make_c_string(r#"{"ok":true}"#.into())
    }
}

// ── Memory Management ───────────────────────────────────────

#[no_mangle]
pub extern "C" fn wg_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe { let _ = CString::from_raw(ptr); }
    }
}

#[no_mangle]
pub extern "C" fn wg_free_buffer(ptr: *mut u8, len: u32) {
    if !ptr.is_null() && len > 0 {
        unsafe { let _ = Vec::from_raw_parts(ptr, len as usize, len as usize); }
    }
}
