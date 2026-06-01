use crate::types::{MatchType, Rule};

/// Check if a domain matches a given rule.
pub fn matches(domain: &str, rule: &Rule) -> bool {
    let domain = domain.to_lowercase();
    let pattern = rule.pattern.to_lowercase();

    match rule.match_type {
        MatchType::Domain => domain == pattern,
        MatchType::DomainSuffix => {
            if domain == pattern {
                return true;
            }
            domain.ends_with(&format!(".{}", pattern))
        }
        MatchType::DomainKeyword => domain.contains(&pattern),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_rule(match_type: MatchType, pattern: &str) -> Rule {
        Rule {
            match_type,
            pattern: pattern.to_string(),
            interface: "wifi".to_string(),
        }
    }

    #[test]
    fn test_exact_domain_match() {
        let rule = make_rule(MatchType::Domain, "github.com");
        assert!(matches("github.com", &rule));
        assert!(matches("GitHub.com", &rule)); // case insensitive
        assert!(!matches("api.github.com", &rule));
        assert!(!matches("notgithub.com", &rule));
    }

    #[test]
    fn test_domain_suffix_match() {
        let rule = make_rule(MatchType::DomainSuffix, "github.com");
        assert!(matches("github.com", &rule));
        assert!(matches("api.github.com", &rule));
        assert!(matches("raw.api.github.com", &rule));
        assert!(!matches("notgithub.com", &rule));
        assert!(!matches("fakegithub.com.evil.org", &rule));
    }

    #[test]
    fn test_domain_keyword_match() {
        let rule = make_rule(MatchType::DomainKeyword, "github");
        assert!(matches("github.com", &rule));
        assert!(matches("api.github.com", &rule));
        assert!(matches("mygithubmirror.org", &rule));
        assert!(!matches("example.com", &rule));
    }

    #[test]
    fn test_case_insensitive() {
        let rule = make_rule(MatchType::DomainSuffix, "GitHub.COM");
        assert!(matches("api.github.com", &rule));
        assert!(matches("API.GITHUB.COM", &rule));
    }
}
