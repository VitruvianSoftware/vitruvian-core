// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use crate::GChatError;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use url::Url;

const ALLOWED_API_HOSTS: &[&str] = &[
    "chat.google.com",
    "mail.google.com",
    "accounts.google.com",
    "clients6.google.com",
    "upload.video.google.com",
];

#[derive(Clone, Debug)]
pub struct NetGuard {
    allow_loopback_for_test: bool,
}

impl NetGuard {
    pub fn production() -> Self {
        Self {
            allow_loopback_for_test: false,
        }
    }

    pub(crate) fn from_test_flag(allow_loopback_for_test: bool) -> Self {
        Self {
            allow_loopback_for_test,
        }
    }

    #[cfg(test)]
    pub fn allow_loopback_for_test() -> Self {
        Self {
            allow_loopback_for_test: true,
        }
    }

    pub fn is_loopback_test_allowed(&self) -> bool {
        self.allow_loopback_for_test
    }

    pub fn validate_ip(&self, ip: IpAddr) -> Result<(), GChatError> {
        match ip {
            IpAddr::V4(v4) => self.validate_ipv4(v4),
            IpAddr::V6(v6) => self.validate_ipv6(v6),
        }
    }

    fn validate_ipv4(&self, ip: Ipv4Addr) -> Result<(), GChatError> {
        if self.allow_loopback_for_test && ip.is_loopback() {
            return Ok(());
        }
        let octets = ip.octets();
        let is_cgnat = octets[0] == 100 && (octets[1] & 0b1100_0000) == 64;
        let is_benchmark = octets[0] == 198 && (octets[1] == 18 || octets[1] == 19);
        if ip.is_loopback()
            || ip.is_private()
            || ip.is_link_local()
            || ip.is_broadcast()
            || ip.is_documentation()
            || ip.is_unspecified()
            || ip.is_multicast()
            || is_cgnat
            || is_benchmark
        {
            return Err(GChatError::SsrfBlocked(format!(
                "disallowed IPv4 address: {ip}"
            )));
        }
        Ok(())
    }

    fn validate_ipv6(&self, ip: Ipv6Addr) -> Result<(), GChatError> {
        if let Some(mapped_v4) = ip.to_ipv4_mapped() {
            return self.validate_ipv4(mapped_v4);
        }
        if self.allow_loopback_for_test && ip.is_loopback() {
            return Ok(());
        }
        let segments = ip.segments();
        let is_unique_local = (segments[0] & 0xfe00) == 0xfc00;
        let is_link_local = (segments[0] & 0xffc0) == 0xfe80;
        if ip.is_loopback()
            || ip.is_unspecified()
            || ip.is_multicast()
            || is_unique_local
            || is_link_local
        {
            return Err(GChatError::SsrfBlocked(format!(
                "disallowed IPv6 address: {ip}"
            )));
        }
        Ok(())
    }

    pub fn is_host_allowed(&self, host: &str, allow_media_hosts: bool) -> bool {
        let lower = host.to_ascii_lowercase();
        if self.allow_loopback_for_test
            && (lower == "127.0.0.1" || lower == "localhost" || lower == "::1")
        {
            return true;
        }
        if ALLOWED_API_HOSTS.contains(&lower.as_str()) {
            return true;
        }
        if allow_media_hosts
            && (lower.ends_with(".googleusercontent.com")
                || lower.ends_with(".ggpht.com")
                || lower.ends_with(".google.com"))
        {
            return true;
        }
        false
    }

    pub async fn validate_url(&self, url: &Url, allow_media_hosts: bool) -> Result<(), GChatError> {
        let scheme = url.scheme();
        if scheme != "https" && !(self.allow_loopback_for_test && scheme == "http") {
            return Err(GChatError::SsrfBlocked(format!(
                "disallowed URL scheme: {scheme}"
            )));
        }
        let host = url
            .host_str()
            .ok_or_else(|| GChatError::SsrfBlocked("URL missing host".to_string()))?;
        if !self.is_host_allowed(host, allow_media_hosts) {
            return Err(GChatError::SsrfBlocked(format!(
                "host not in allowlist: {host}"
            )));
        }
        if let Ok(ip) = host.parse::<IpAddr>() {
            return self.validate_ip(ip);
        }
        let port = url.port_or_known_default().unwrap_or(443);
        let addrs = tokio::net::lookup_host((host, port))
            .await
            .map_err(|e| GChatError::Network(format!("DNS lookup failed for {host}: {e}")))?;
        let mut checked = 0usize;
        for sock_addr in addrs {
            self.validate_ip(sock_addr.ip())?;
            checked += 1;
        }
        if checked == 0 {
            return Err(GChatError::SsrfBlocked(format!(
                "DNS lookup returned no addresses for {host}"
            )));
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_production_config_rejects_loopback() {
        let guard = NetGuard::production();
        let loopback_url = Url::parse("http://127.0.0.1:8080/u/0/mole/world").unwrap();
        let err = guard.validate_url(&loopback_url, false).await;
        assert!(
            matches!(err, Err(GChatError::SsrfBlocked(_))),
            "production NetGuard must reject loopback URL, got: {err:?}"
        );

        let https_loopback = Url::parse("https://127.0.0.1:8443/u/0/mole/world").unwrap();
        assert!(
            matches!(
                guard.validate_url(&https_loopback, false).await,
                Err(GChatError::SsrfBlocked(_))
            ),
            "production NetGuard must reject https loopback URL"
        );

        let private_ip: IpAddr = "10.0.0.1".parse().unwrap();
        assert!(
            matches!(
                guard.validate_ip(private_ip),
                Err(GChatError::SsrfBlocked(_))
            ),
            "production NetGuard must reject RFC1918 private IP"
        );
    }
}
