use crate::protocol::outer::DEFAULT_MAX_CT_MIB;

/// Environment variable that overrides the outer-envelope limit in whole MiB.
pub const MAX_CT_ENV: &str = "RELAY_MAX_CT_MIB";

/// Relay configuration parsed at the process boundary.
#[derive(Debug, Clone, Copy)]
pub struct RelayConfig {
    max_ct_bytes: usize,
}

impl RelayConfig {
    /// Read relay configuration from the process environment.
    pub fn from_env() -> Self {
        Self::from_max_ct_mib(std::env::var(MAX_CT_ENV).ok().as_deref())
    }

    /// Return the configured decoded ciphertext ceiling in bytes.
    pub const fn max_ct_bytes(self) -> usize {
        self.max_ct_bytes
    }

    fn from_max_ct_mib(value: Option<&str>) -> Self {
        let mib = value
            .and_then(|raw| raw.trim().parse::<usize>().ok())
            .filter(|&mib| mib > 0)
            .unwrap_or(DEFAULT_MAX_CT_MIB);
        Self {
            max_ct_bytes: mib.saturating_mul(1024 * 1024),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{DEFAULT_MAX_CT_MIB, RelayConfig};

    #[test]
    fn defaults_when_limit_is_missing_or_invalid() {
        let default_bytes = DEFAULT_MAX_CT_MIB * 1024 * 1024;
        for value in [None, Some(""), Some("0"), Some("not-a-number")] {
            assert_eq!(
                RelayConfig::from_max_ct_mib(value).max_ct_bytes(),
                default_bytes
            );
        }
    }

    #[test]
    fn parses_trimmed_positive_mib_and_saturates_overflow() {
        assert_eq!(
            RelayConfig::from_max_ct_mib(Some(" 7 ")).max_ct_bytes(),
            7 * 1024 * 1024
        );
        assert_eq!(
            RelayConfig::from_max_ct_mib(Some(&usize::MAX.to_string())).max_ct_bytes(),
            usize::MAX
        );
    }
}
