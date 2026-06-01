//! RouteFlow SOCKS5 Proxy - Routes traffic through specific network interfaces.
//!
//! Usage: routeflow-proxy [config_path] [listen_addr]
//! Example: routeflow-proxy config/rules.yaml 127.0.0.1:1080

use std::env;
use std::net::SocketAddr;
use std::path::Path;
use std::sync::Arc;

use routeflow_core::proxy::{run_proxy, ProxyConfig};
use routeflow_core::{Config, RuleEngine};

#[tokio::main]
async fn main() {
    let args: Vec<String> = env::args().collect();

    let config_path = if args.len() >= 2 {
        args[1].clone()
    } else {
        "config/rules.yaml".to_string()
    };

    let listen_addr: SocketAddr = if args.len() >= 3 {
        args[2].parse().unwrap_or_else(|_| {
            eprintln!("Invalid listen address '{}', using default", args[2]);
            "127.0.0.1:1080".parse().unwrap()
        })
    } else {
        "127.0.0.1:1080".parse().unwrap()
    };

    // Load configuration
    let config = match Config::from_file(Path::new(&config_path)) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("[RouteFlow] Error loading config '{}': {}", config_path, e);
            std::process::exit(1);
        }
    };

    let engine = match RuleEngine::from_config(&config) {
        Ok(e) => e,
        Err(e) => {
            eprintln!("[RouteFlow] Error building rule engine: {}", e);
            std::process::exit(1);
        }
    };

    println!("[RouteFlow] Loaded {} rules from {}", engine.rule_count(), config_path);
    println!("[RouteFlow] Default interface: {}", engine.default_interface());
    println!();

    let engine = Arc::new(engine);
    let proxy_config = ProxyConfig { listen_addr };

    // Run the proxy
    if let Err(e) = run_proxy(engine, proxy_config).await {
        eprintln!("[RouteFlow] Proxy error: {}", e);
        std::process::exit(1);
    }
}
