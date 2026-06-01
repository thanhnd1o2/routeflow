use crate::config::Config;
use crate::matcher;
use crate::types::{Rule, RoutingDecision};

/// The rule engine evaluates domains against an ordered list of rules.
pub struct RuleEngine {
    rules: Vec<Rule>,
    default_interface: String,
}

impl RuleEngine {
    /// Create a new rule engine from a parsed configuration.
    pub fn from_config(config: &Config) -> Result<Self, crate::config::ConfigError> {
        let rules = config.parse_rules()?;
        Ok(Self {
            rules,
            default_interface: config.default.clone(),
        })
    }

    /// Create a rule engine directly from rules and a default.
    pub fn new(rules: Vec<Rule>, default_interface: String) -> Self {
        Self {
            rules,
            default_interface,
        }
    }

    /// Evaluate a domain and return the routing decision.
    /// Rules are evaluated in order; first match wins.
    pub fn resolve(&self, domain: &str) -> RoutingDecision {
        for rule in &self.rules {
            if matcher::matches(domain, rule) {
                return RoutingDecision {
                    interface: rule.interface.clone(),
                    matched_rule: Some(format!(
                        "{:?},{},{}",
                        rule.match_type, rule.pattern, rule.interface
                    )),
                };
            }
        }

        RoutingDecision {
            interface: self.default_interface.clone(),
            matched_rule: None,
        }
    }

    /// Return the number of loaded rules.
    pub fn rule_count(&self) -> usize {
        self.rules.len()
    }

    /// Return the default interface name.
    pub fn default_interface(&self) -> &str {
        &self.default_interface
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::Config;

    const TEST_CONFIG: &str = r#"
interfaces:
  - name: wifi
    type: wifi
  - name: ethernet
    type: ethernet

rules:
  - DOMAIN-SUFFIX,github.com,wifi
  - DOMAIN-SUFFIX,company.com,ethernet
  - DOMAIN,secret.internal.org,ethernet
  - DOMAIN-KEYWORD,cdn,wifi

default: wifi
"#;

    fn engine() -> RuleEngine {
        let config = Config::from_str(TEST_CONFIG).unwrap();
        RuleEngine::from_config(&config).unwrap()
    }

    #[test]
    fn test_suffix_match_github() {
        let e = engine();
        let decision = e.resolve("api.github.com");
        assert_eq!(decision.interface, "wifi");
        assert!(decision.matched_rule.is_some());
    }

    #[test]
    fn test_suffix_match_company() {
        let e = engine();
        let decision = e.resolve("mail.company.com");
        assert_eq!(decision.interface, "ethernet");
    }

    #[test]
    fn test_exact_match() {
        let e = engine();
        let decision = e.resolve("secret.internal.org");
        assert_eq!(decision.interface, "ethernet");
        // Subdomain should NOT match exact rule
        let decision2 = e.resolve("sub.secret.internal.org");
        assert_ne!(decision2.matched_rule, decision.matched_rule);
    }

    #[test]
    fn test_keyword_match() {
        let e = engine();
        let decision = e.resolve("assets.cdn.example.com");
        assert_eq!(decision.interface, "wifi");
    }

    #[test]
    fn test_default_fallback() {
        let e = engine();
        let decision = e.resolve("unknown.example.org");
        assert_eq!(decision.interface, "wifi");
        assert!(decision.matched_rule.is_none());
    }

    #[test]
    fn test_first_match_wins() {
        // "cdn.company.com" matches both DOMAIN-SUFFIX,company.com and DOMAIN-KEYWORD,cdn
        // First rule in order should win (company.com -> ethernet)
        let e = engine();
        let decision = e.resolve("cdn.company.com");
        assert_eq!(decision.interface, "ethernet");
    }

    #[test]
    fn test_rule_count() {
        let e = engine();
        assert_eq!(e.rule_count(), 4);
    }
}
