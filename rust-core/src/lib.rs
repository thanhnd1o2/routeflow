//! RouteFlow Core - Domain-based network interface routing engine.
//!
//! This crate provides the core routing logic for RouteFlow.
//! Given a domain name and a set of rules, it determines which
//! network interface should be used for the connection.

pub mod config;
pub mod ffi;
pub mod matcher;
pub mod proxy;
pub mod rule_engine;
pub mod types;

pub use config::Config;
pub use rule_engine::RuleEngine;
pub use types::RoutingDecision;
