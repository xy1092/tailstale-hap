use std::os::fd::RawFd;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread::{self, JoinHandle};

use crate::error::TunnelError;
use crate::wireguard::TunnelManager;

fn read_exact_fd(fd: RawFd, buf: &mut [u8]) -> Result<usize, TunnelError> {
    let n = unsafe {
        libc::read(fd, buf.as_mut_ptr() as *mut libc::c_void, buf.len())
    };
    if n < 0 {
        let err = std::io::Error::last_os_error();
        if err.kind() == std::io::ErrorKind::WouldBlock {
            return Ok(0);
        }
        return Err(TunnelError::Io(err));
    }
    Ok(n as usize)
}

fn write_all_fd(fd: RawFd, buf: &[u8]) -> Result<usize, TunnelError> {
    let n = unsafe {
        libc::write(fd, buf.as_ptr() as *const libc::c_void, buf.len())
    };
    if n < 0 {
        return Err(TunnelError::Io(std::io::Error::last_os_error()));
    }
    Ok(n as usize)
}

pub struct LoopHandle {
    stop_flag: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl LoopHandle {
    pub fn stop(&mut self) {
        self.stop_flag.store(true, Ordering::Relaxed);
        if let Some(handle) = self.thread.take() {
            let _ = handle.join();
        }
    }
}

pub fn start_tunnel_loop(
    tunnel: Arc<TunnelManager>,
    tun_fd: RawFd,
    sock_fd: RawFd,
) -> LoopHandle {
    let stop_flag = Arc::new(AtomicBool::new(false));
    let flag = stop_flag.clone();

    let handle = thread::spawn(move || {
        let mut tun_buf = vec![0u8; 2048];
        let mut net_buf = vec![0u8; 2048];
        let mut pfd = [
            libc::pollfd {
                fd: tun_fd,
                events: libc::POLLIN,
                revents: 0,
            },
            libc::pollfd {
                fd: sock_fd,
                events: libc::POLLIN,
                revents: 0,
            },
        ];

        while !flag.load(Ordering::Relaxed) {
            let ret = unsafe { libc::poll(pfd.as_mut_ptr(), 2, 200) };

            if ret < 0 {
                break;
            }

            if pfd[0].revents & libc::POLLIN != 0 {
                if let Ok(n) = read_exact_fd(tun_fd, &mut tun_buf) {
                    if n > 0 {
                        if let Ok(Some(encrypted)) = tunnel.process_outgoing(&tun_buf[..n]) {
                            let _ = write_all_fd(sock_fd, &encrypted);
                        }
                    }
                }
            }

            if pfd[1].revents & libc::POLLIN != 0 {
                let n = unsafe {
                    libc::read(
                        sock_fd,
                        net_buf.as_mut_ptr() as *mut libc::c_void,
                        net_buf.len(),
                    )
                };
                if n > 0 {
                    let n = n as usize;
                    if let Ok(Some(decrypted)) = tunnel.process_incoming(&net_buf[..n]) {
                        let _ = write_all_fd(tun_fd, &decrypted);
                    }
                }
            }
        }
    });

    LoopHandle {
        stop_flag,
        thread: Some(handle),
    }
}
