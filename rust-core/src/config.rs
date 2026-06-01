use serde::Deserialize;
use std::fs;
use std::path::Path;

use crate::types::{Interface, MatchType, Rule};

/// Raw configuration as deserialized from YAML.
#[derive(Debug, Deserialize)]
pub struct Config {
    pub interfaces: Vec<Interface>,
    pub rules: Vec<String>,
    pub default: String,
}

impl Config {
    /// Load configuration from a YAML file.
    pub fn from_file(path: &Path) -> Result<Self, ConfigError> {
        let content = fs::read_to_string(path)
            .map_err(|e| ConfigError::IoError(e.to_string()))?;
        Self::from_str(&content)
    }

    /// Parse configuration from a YAML string.
    pub fn from_str(content: &str) -> Result<Self, ConfigError> {
        serde_yaml::from_str(content)
            .map_err(|e| ConfigError::ParseError(e.to_string()))
    }

    /// Parse raw rule strings into structured Rule objects.
    pub fn parse_rules(&self) -> Result<Vec<Rule>, ConfigError> {
        self.rules.iter().map(|s| parse_rule_string(s)).collect()
    }
}

/// Parse a single rule string like "DOMAIN-SUFFIX,github.com,wifi".
fn parse_rule_string(s: &str) -> Result<Rule, ConfigError> {
    let parts: Vec<&str> = s.splitn(3, ',').collect();
    if parts.len() != 3 {
        return Err(ConfigError::InvalidRule(format!(
            "expected 3 comma-separated parts, got {}: '{}'",
            parts.len(),
            s
        )));
    }

    let match_type = match parts[0].trim() {
        "DOMAIN" => MatchType::Domain,
        "DOMAIN-SUFFIX" => MatchType::DomainSuffix,
        "DOMAIN-KEYWORD" => MatchType::DomainKeyword,
        other => {
            return Err(ConfigError::InvalidRule(format!(
                "unknown match type '{}'",
                other
            )))
        }
    };

    Ok(Rule {
        match_type,
        pattern: parts[1].trim().to_string(),
        interface: parts[2].trim().to_string(),
    })
}

/// Configuration errors.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConfigError {
    IoError(String),
    ParseError(String),
    InvalidRule(String),
}

impl std::fmt::Display for ConfigError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::IoError(e) => write!(f, "IO error: {}", e),
            Self::ParseError(e) => write!(f, "parse error: {}", e),
            Self::InvalidRule(e) => write!(f, "invalid rule: {}", e),
        }
    }
}

impl std::error::Error for ConfigError {}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_CONFIG: &str = r#"
interfaces:
  - name: wifi
    type: wifi
  - name: ethernet
    type: ethernet

rules:
  - DOMAIN-SUFFIX,github.com,wifi
  - DOMAIN-SUFFIX,company.com,ethernet
  - DOMAIN,exact.example.org,ethernet
  - DOMAIN-KEYWORD,internal,ethernet

default: wifi
"#;

    #[test]
    fn test_parse_config() {
        let config = Config::from_str(SAMPLE_CONFIG).unwrap();
        assert_eq!(config.interfaces.len(), 2);
        assert_eq!(config.rules.len(), 4);
        assert_eq!(config.default, "wifi");
    }

    #[test]
    fn test_parse_rules() {
        let config = Config::from_str(SAMPLE_CONFIG).unwrap();
        let rules = config.parse_rules().unwrap();
        assert_eq!(rules.len(), 4);
        assert_eq!(rules[0].match_type, MatchType::DomainSuffix);
        assert_eq!(rules[0].pattern, "github.com");
        assert_eq!(rules[0].interface, "wifi");
        assert_eq!(rules[3].match_type, MatchType::DomainKeyword);
    }

    #[test]
    fn test_invalid_rule_format() {
        let config = Config::from_str(
            "interfaces: []\nrules:\n  - BAD_RULE\ndefault: wifi\n",
        )
        .unwrap();
        let result = config.parse_rules();
        assert!(result.is_err());
    }

    #[test]
    fn test_unknown_match_type() {
        let config = Config::from_str(
            "interfaces: []\nrules:\n  - UNKNOWN,example.com,wifi\ndefault: wifi\n",
        )
        .unwrap();
        let result = config.parse_rules();
        assert!(result.is_err());
    }
}
