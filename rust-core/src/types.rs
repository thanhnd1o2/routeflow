use serde::Deserialize;
use std::fmt;

/// Network interface type.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum InterfaceType {
    Wifi,
    Ethernet,
    Vpn,
    Other,
}

/// A network interface definition.
#[derive(Debug, Clone, Deserialize)]
pub struct Interface {
    pub name: String,
    #[serde(rename = "type")]
    pub interface_type: InterfaceType,
}

/// Rule match strategy.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MatchType {
    /// Exact domain match.
    Domain,
    /// Matches domain and all subdomains.
    DomainSuffix,
    /// Matches if keyword appears anywhere in the domain.
    DomainKeyword,
}

/// A single routing rule.
#[derive(Debug, Clone)]
pub struct Rule {
    pub match_type: MatchType,
    pub pattern: String,
    pub interface: String,
}

/// Result of a routing decision.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoutingDecision {
    pub interface: String,
    pub matched_rule: Option<String>,
}

impl fmt::Display for RoutingDecision {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match &self.matched_rule {
            Some(rule) => write!(f, "{} (matched: {})", self.interface, rule),
            None => write!(f, "{} (default)", self.interface),
        }
    }
}
