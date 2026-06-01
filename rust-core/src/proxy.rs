//! SOCKS5 proxy server that routes connections through specific network interfaces.
//!
//! Listens on localhost and uses the rule engine to determine which interface
//! each connection should be routed through.

use std::io;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::sync::Arc;

use tokio::io::{AsyncReadExt, AsyncWriteExt, copy_bidirectional};
use tokio::net::{TcpListener, TcpStream, TcpSocket};

use crate::rule_engine::RuleEngine;

/// SOCKS5 protocol constants
const SOCKS5_VERSION: u8 = 0x05;
const AUTH_NO_AUTH: u8 = 0x00;
const CMD_CONNECT: u8 = 0x01;
const ATYP_IPV4: u8 = 0x01;
const ATYP_DOMAIN: u8 = 0x03;
const ATYP_IPV6: u8 = 0x04;
const REPLY_SUCCESS: u8 = 0x00;
const REPLY_GENERAL_FAILURE: u8 = 0x01;
const REPLY_CONNECTION_REFUSED: u8 = 0x05;

/// Configuration for the SOCKS5 proxy server.
#[derive(Clone)]
pub struct ProxyConfig {
    pub listen_addr: SocketAddr,
}

impl Default for ProxyConfig {
    fn default() -> Self {
        Self {
            listen_addr: SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 1080),
        }
    }
}

/// Run the SOCKS5 proxy server.
pub async fn run_proxy(engine: Arc<RuleEngine>, config: ProxyConfig) -> io::Result<()> {
    let listener = TcpListener::bind(config.listen_addr).await?;
    println!("[RouteFlow] SOCKS5 proxy listening on {}", config.listen_addr);

    loop {
        let (stream, peer_addr) = listener.accept().await?;
        let engine = engine.clone();

        tokio::spawn(async move {
            if let Err(e) = handle_client(stream, peer_addr, &engine).await {
                eprintln!("[RouteFlow] Connection from {} error: {}", peer_addr, e);
            }
        });
    }
}

/// Handle a single SOCKS5 client connection.
async fn handle_client(
    mut stream: TcpStream,
    peer_addr: SocketAddr,
    engine: &RuleEngine,
) -> io::Result<()> {
    // Step 1: Auth negotiation
    let version = stream.read_u8().await?;
    if version != SOCKS5_VERSION {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "not SOCKS5"));
    }

    let nmethods = stream.read_u8().await?;
    let mut methods = vec![0u8; nmethods as usize];
    stream.read_exact(&mut methods).await?;

    // We only support no-auth
    stream.write_all(&[SOCKS5_VERSION, AUTH_NO_AUTH]).await?;

    // Step 2: Read connect request
    let version = stream.read_u8().await?;
    if version != SOCKS5_VERSION {
        return Err(io::Error::new(io::ErrorKind::InvalidData, "not SOCKS5"));
    }

    let cmd = stream.read_u8().await?;
    let _rsv = stream.read_u8().await?; // reserved
    let atyp = stream.read_u8().await?;

    if cmd != CMD_CONNECT {
        send_reply(&mut stream, REPLY_GENERAL_FAILURE).await?;
        return Err(io::Error::new(io::ErrorKind::Unsupported, "only CONNECT supported"));
    }

    // Parse destination address
    let (hostname, dest_addr) = match atyp {
        ATYP_IPV4 => {
            let mut addr = [0u8; 4];
            stream.read_exact(&mut addr).await?;
            let ip = Ipv4Addr::from(addr);
            let port = stream.read_u16().await?;
            let addr_str = format!("{}:{}", ip, port);
            (ip.to_string(), addr_str)
        }
        ATYP_DOMAIN => {
            let len = stream.read_u8().await? as usize;
            let mut domain = vec![0u8; len];
            stream.read_exact(&mut domain).await?;
            let port = stream.read_u16().await?;
            let domain_str = String::from_utf8_lossy(&domain).to_string();
            let addr_str = format!("{}:{}", domain_str, port);
            (domain_str, addr_str)
        }
        ATYP_IPV6 => {
            let mut addr = [0u8; 16];
            stream.read_exact(&mut addr).await?;
            let port = stream.read_u16().await?;
            let ip = std::net::Ipv6Addr::from(addr);
            let addr_str = format!("[{}]:{}", ip, port);
            (ip.to_string(), addr_str)
        }
        _ => {
            send_reply(&mut stream, REPLY_GENERAL_FAILURE).await?;
            return Err(io::Error::new(io::ErrorKind::InvalidData, "unsupported address type"));
        }
    };

    // Step 3: Resolve interface using rule engine
    let decision = engine.resolve(&hostname);
    let interface_name = &decision.interface;

    println!(
        "[RouteFlow] {} -> {} via {}",
        peer_addr, dest_addr, interface_name
    );

    // Step 4: Connect to destination, optionally bound to interface
    let outbound = connect_via_interface(&dest_addr, interface_name).await;

    match outbound {
        Ok(mut remote) => {
            // Send success reply
            send_reply(&mut stream, REPLY_SUCCESS).await?;

            // Step 5: Relay data bidirectionally
            let result = copy_bidirectional(&mut stream, &mut remote).await;
            match result {
                Ok((client_to_remote, remote_to_client)) => {
                    println!(
                        "[RouteFlow] {} closed: ↑{}B ↓{}B",
                        dest_addr, client_to_remote, remote_to_client
                    );
                }
                Err(e) => {
                    // Connection closed, not necessarily an error
                    if e.kind() != io::ErrorKind::NotConnected {
                        eprintln!("[RouteFlow] relay error for {}: {}", dest_addr, e);
                    }
                }
            }
        }
        Err(e) => {
            eprintln!("[RouteFlow] failed to connect to {}: {}", dest_addr, e);
            send_reply(&mut stream, REPLY_CONNECTION_REFUSED).await?;
        }
    }

    Ok(())
}

/// Connect to a destination address, binding to a specific network interface if possible.
async fn connect_via_interface(dest: &str, interface: &str) -> io::Result<TcpStream> {
    // Resolve the destination address
    let addrs: Vec<SocketAddr> = tokio::net::lookup_host(dest).await?.collect();
    let dest_addr = addrs
        .first()
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "DNS resolution failed"))?;

    // Create a socket and bind to the interface
    let socket = if dest_addr.is_ipv4() {
        TcpSocket::new_v4()?
    } else {
        TcpSocket::new_v6()?
    };

    // Bind to interface using SO_BINDTODEVICE (Linux) or IP_BOUND_IF (macOS)
    bind_to_interface(&socket, interface)?;

    // Connect to destination
    let stream = socket.connect(*dest_addr).await?;
    Ok(stream)
}

/// Bind a socket to a specific network interface.
/// Uses platform-specific socket options.
#[cfg(target_os = "macos")]
fn bind_to_interface(socket: &TcpSocket, interface: &str) -> io::Result<()> {
    use std::os::fd::AsRawFd;

    let fd = socket.as_raw_fd();
    let ifindex = get_interface_index(interface);

    if let Some(idx) = ifindex {
        // IP_BOUND_IF for macOS
        let result = unsafe {
            libc::setsockopt(
                fd,
                libc::IPPROTO_IP,
                libc::IP_BOUND_IF,
                &idx as *const u32 as *const libc::c_void,
                std::mem::size_of::<u32>() as libc::socklen_t,
            )
        };
        if result != 0 {
            return Err(io::Error::last_os_error());
        }
        println!("[RouteFlow] Bound to interface {} (index {})", interface, idx);
    } else {
        println!("[RouteFlow] Interface '{}' not found, using default route", interface);
    }

    Ok(())
}

#[cfg(target_os = "linux")]
fn bind_to_interface(socket: &TcpSocket, interface: &str) -> io::Result<()> {
    use std::os::fd::AsRawFd;

    let fd = socket.as_raw_fd();
    let iface_bytes = interface.as_bytes();

    if iface_bytes.len() >= libc::IFNAMSIZ {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "interface name too long"));
    }

    let mut ifname = [0u8; libc::IFNAMSIZ];
    ifname[..iface_bytes.len()].copy_from_slice(iface_bytes);

    let result = unsafe {
        libc::setsockopt(
            fd,
            libc::SOL_SOCKET,
            libc::SO_BINDTODEVICE,
            ifname.as_ptr() as *const libc::c_void,
            iface_bytes.len() as libc::socklen_t,
        )
    };

    if result != 0 {
        return Err(io::Error::last_os_error());
    }

    println!("[RouteFlow] Bound to interface {}", interface);
    Ok(())
}

#[cfg(not(any(target_os = "macos", target_os = "linux")))]
fn bind_to_interface(_socket: &TcpSocket, interface: &str) -> io::Result<()> {
    println!("[RouteFlow] Interface binding not supported on this platform, using default for '{}'", interface);
    Ok(())
}

/// Get the interface index by name (macOS).
#[cfg(target_os = "macos")]
fn get_interface_index(name: &str) -> Option<u32> {
    use std::ffi::CString;

    let cname = CString::new(name).ok()?;
    let idx = unsafe { libc::if_nametoindex(cname.as_ptr()) };
    if idx == 0 {
        // Try matching by type keyword
        match name.to_lowercase().as_str() {
            "wifi" | "wi-fi" => find_interface_by_prefix("en"),
            "ethernet" | "wired" => find_interface_by_prefix("en"),
            "vpn" | "tunnel" => find_interface_by_prefix("utun"),
            _ => None,
        }
    } else {
        Some(idx)
    }
}

/// Find an interface index by name prefix (e.g., "en" for ethernet/wifi).
#[cfg(target_os = "macos")]
fn find_interface_by_prefix(prefix: &str) -> Option<u32> {
    use std::ffi::CStr;

    unsafe {
        let ifaddrs_ptr = std::ptr::null_mut();
        let mut ifaddrs: *mut libc::ifaddrs = ifaddrs_ptr;
        if libc::getifaddrs(&mut ifaddrs) != 0 {
            return None;
        }

        let mut current = ifaddrs;
        let mut result = None;

        while !current.is_null() {
            let name = CStr::from_ptr((*current).ifa_name).to_string_lossy();
            if name.starts_with(prefix) {
                let idx = libc::if_nametoindex((*current).ifa_name);
                if idx != 0 {
                    result = Some(idx);
                    break;
                }
            }
            current = (*current).ifa_next;
        }

        libc::freeifaddrs(ifaddrs);
        result
    }
}

/// Send a SOCKS5 reply.
async fn send_reply(stream: &mut TcpStream, reply: u8) -> io::Result<()> {
    let response = [
        SOCKS5_VERSION,
        reply,
        0x00, // reserved
        ATYP_IPV4,
        0, 0, 0, 0, // bind addr (0.0.0.0)
        0, 0, // bind port (0)
    ];
    stream.write_all(&response).await
}
