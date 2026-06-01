//! RouteFlow CLI - Test the rule engine from the command line.
//!
//! Usage: routeflow-cli <domain> [config_path]

use std::env;
use std::path::Path;
use std::process;

use routeflow_core::{Config, RuleEngine};

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: routeflow-cli <domain> [config_path]");
        eprintln!("Example: routeflow-cli github.com config/rules.yaml");
        process::exit(1);
    }

    let domain = &args[1];
    let config_path = if args.len() >= 3 {
        args[2].clone()
    } else {
        "config/rules.yaml".to_string()
    };

    let config = match Config::from_file(Path::new(&config_path)) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Error loading config '{}': {}", config_path, e);
            process::exit(1);
        }
    };

    let engine = match RuleEngine::from_config(&config) {
        Ok(e) => e,
        Err(e) => {
            eprintln!("Error building rule engine: {}", e);
            process::exit(1);
        }
    };

    let decision = engine.resolve(domain);
    println!("{}", decision.interface);
    if let Some(rule) = &decision.matched_rule {
        eprintln!("Matched: {}", rule);
    } else {
        eprintln!("No rule matched, using default");
    }
}
