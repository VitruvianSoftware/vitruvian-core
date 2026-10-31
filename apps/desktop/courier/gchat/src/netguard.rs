// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use crate::GChatError;
use reqwest::dns::{Addrs, Name, Resolve, Resolving};
use reqwest::Client;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};
use std::sync::Arc;
use url::Url;

const ALLOWED_API_HOSTS: &[&str] = &[
    "chat.google.com",
    "mail.google.com",
    "accounts.google.com",
    "clients6.google.com",
    "upload.video.google.com",
];

#[cfg(any(test, feature = "test-loopback"))]
static TEST_LOOPBACK_OVERRIDE: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);

#[cfg(any(test, feature = "test-loopback"))]
pub fn set_global_test_loopback_override(allow: bool) {
    TEST_LOOPBACK_OVERRIDE.store(allow, std::sync::atomic::Ordering::SeqCst);
}

#[derive(Clone, Debug)]
pub struct NetGuard {
    #[cfg(any(test, feature = "test-loopback"))]
    allow_loopback_for_test: bool,
    #[cfg(not(any(test, feature = "test-loopback")))]
    _production_only: (),
}

impl NetGuard {
    pub fn production() -> Self {
        Self {
            #[cfg(any(test, feature = "test-loopback"))]
            allow_loopback_for_test: false,
            #[cfg(not(any(test, feature = "test-loopback")))]
            _production_only: (),
        }
    }

    pub(crate) fn from_ambient() -> Self {
        Self {
            #[cfg(any(test, feature = "test-loopback"))]
            allow_loopback_for_test: TEST_LOOPBACK_OVERRIDE
                .load(std::sync::atomic::Ordering::SeqCst),
            #[cfg(not(any(test, feature = "test-loopback")))]
            _production_only: (),
        }
    }

    #[cfg(any(test, feature = "test-loopback"))]
    pub fn allow_loopback_for_test() -> Self {
        Self {
            allow_loopback_for_test: true,
        }
    }

    #[inline]
    pub fn is_loopback_test_allowed(&self) -> bool {
        #[cfg(any(test, feature = "test-loopback"))]
        {
            self.allow_loopback_for_test
        }
        #[cfg(not(any(test, feature = "test-loopback")))]
        {
            false
        }
    }

    pub fn build_http_client(&self) -> Result<Client, GChatError> {
        Client::builder()
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .dns_resolver(Arc::new(self.clone()))
            .build()
            .map_err(|e| GChatError::Internal(format!("failed to build HTTP client: {e}")))
    }

    pub fn validate_ip(&self, ip: IpAddr) -> Result<(), GChatError> {
        match ip {
            IpAddr::V4(v4) => self.validate_ipv4(v4),
            IpAddr::V6(v6) => self.validate_ipv6(v6),
        }
    }

    fn validate_ipv4(&self, ip: Ipv4Addr) -> Result<(), GChatError> {
        if self.is_loopback_test_allowed() && ip.is_loopback() {
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
        if self.is_loopback_test_allowed() && ip.is_loopback() {
            return Ok(());
        }
        let segments = ip.segments();
        let octets = ip.octets();

        // Unwrap embedded IPv4 transition mechanisms before general checks:
        // 1. IPv4-compatible ::a.b.c.d/96 (excluding :: and ::1 which are caught below)
        if segments[0..6] == [0, 0, 0, 0, 0, 0] && !ip.is_unspecified() && !ip.is_loopback() {
            let v4 = Ipv4Addr::new(octets[12], octets[13], octets[14], octets[15]);
            return self.validate_ipv4(v4);
        }
        // 2. NAT64 well-known prefix 64:ff9b::/96 (RFC 6052) and local-use 64:ff9b:1::/48 (RFC 8215)
        if segments[0] == 0x0064
            && segments[1] == 0xff9b
            && (segments[2..6] == [0, 0, 0, 0] || segments[2] == 0x0001)
        {
            let v4 = Ipv4Addr::new(octets[12], octets[13], octets[14], octets[15]);
            return self.validate_ipv4(v4);
        }
        // 3. 6to4 prefix 2002::/16 (RFC 3056) embeds IPv4 in bits 16..48 (octets 2..6)
        if segments[0] == 0x2002 {
            let v4 = Ipv4Addr::new(octets[2], octets[3], octets[4], octets[5]);
            return self.validate_ipv4(v4);
        }
        // 4. Teredo prefix 2001:0000::/32 (RFC 4380) embeds XOR-inverted client IPv4 in octets 12..16
        if segments[0] == 0x2001 && segments[1] == 0x0000 {
            let v4_xor = Ipv4Addr::new(!octets[12], !octets[13], !octets[14], !octets[15]);
            self.validate_ipv4(v4_xor)?;
            let v4_raw = Ipv4Addr::new(octets[12], octets[13], octets[14], octets[15]);
            return self.validate_ipv4(v4_raw);
        }
        // 5. ISATAP interface identifier *:0000:5efe:a.b.c.d or *:0200:5efe:a.b.c.d (RFC 5214)
        if (segments[4] & 0xfcff) == 0x0000 && segments[5] == 0x5efe {
            let v4 = Ipv4Addr::new(octets[12], octets[13], octets[14], octets[15]);
            return self.validate_ipv4(v4);
        }

        let is_unique_local = (segments[0] & 0xfe00) == 0xfc00;
        let is_link_local = (segments[0] & 0xffc0) == 0xfe80;
        let is_documentation = segments[0] == 0x2001 && segments[1] == 0x0db8;
        if ip.is_loopback()
            || ip.is_unspecified()
            || ip.is_multicast()
            || is_unique_local
            || is_link_local
            || is_documentation
        {
            return Err(GChatError::SsrfBlocked(format!(
                "disallowed IPv6 address: {ip}"
            )));
        }
        Ok(())
    }

    pub fn is_host_allowed(&self, host: &str, allow_media_hosts: bool) -> bool {
        let lower = host
            .trim_matches(|c| c == '[' || c == ']')
            .to_ascii_lowercase();
        if self.is_loopback_test_allowed()
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

    pub fn validate_host_and_scheme(
        &self,
        url: &Url,
        allow_media_hosts: bool,
    ) -> Result<(String, u16), GChatError> {
        let scheme = url.scheme();
        if scheme != "https" && !(self.is_loopback_test_allowed() && scheme == "http") {
            return Err(GChatError::SsrfBlocked(format!(
                "disallowed URL scheme: {scheme}"
            )));
        }
        let raw_host = url
            .host_str()
            .ok_or_else(|| GChatError::SsrfBlocked("URL missing host".to_string()))?;
        let host = raw_host
            .trim_matches(|c| c == '[' || c == ']')
            .to_ascii_lowercase();
        if !self.is_host_allowed(&host, allow_media_hosts) {
            return Err(GChatError::SsrfBlocked(format!(
                "host not in allowlist: {host}"
            )));
        }
        if let Ok(ip) = host.parse::<IpAddr>() {
            self.validate_ip(ip)?;
        }
        let port = url.port_or_known_default().unwrap_or(443);
        Ok((host, port))
    }
}

crate::edition2021! {
    impl NetGuard {
        pub async fn resolve_and_validate_host(
            &self,
            host: &str,
            port: u16,
        ) -> Result<Vec<SocketAddr>, GChatError> {
            let clean_host = host.trim_matches(|c| c == '[' || c == ']');
            if let Ok(ip) = clean_host.parse::<IpAddr>() {
                self.validate_ip(ip)?;
                return Ok(vec![SocketAddr::new(ip, port)]);
            }
            let addrs = tokio::net::lookup_host((clean_host, port))
                .await
                .map_err(|e| GChatError::Network(format!("DNS lookup failed for {clean_host}: {e}")))?;
            let mut validated = Vec::new();
            for sock_addr in addrs {
                self.validate_ip(sock_addr.ip())?;
                validated.push(sock_addr);
            }
            if validated.is_empty() {
                return Err(GChatError::SsrfBlocked(format!(
                    "DNS lookup returned no addresses for {clean_host}"
                )));
            }
            Ok(validated)
        }

        pub async fn validate_url(&self, url: &Url, allow_media_hosts: bool) -> Result<(), GChatError> {
            let (host, port) = self.validate_host_and_scheme(url, allow_media_hosts)?;
            self.resolve_and_validate_host(&host, port).await?;
            Ok(())
        }
    }

    impl Resolve for NetGuard {
        fn resolve(&self, name: Name) -> Resolving {
            let guard = self.clone();
            let host = name.as_str().to_string();
            Box::pin(async move {
                let validated = guard
                    .resolve_and_validate_host(&host, 0)
                    .await
                    .map_err(|e| -> Box<dyn std::error::Error + Send + Sync> { Box::new(e) })?;
                let iter: Addrs = Box::new(validated.into_iter());
                Ok(iter)
            })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    crate::edition2021! {
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

        #[tokio::test]
        async fn test_netguard_dns_resolver_pins_validated_addrs_and_blocks_private_resolution() {
            let guard = NetGuard::production();
            let res = guard.resolve_and_validate_host("localhost", 443).await;
            assert!(
                matches!(res, Err(GChatError::SsrfBlocked(_))),
                "production DNS resolver must reject localhost resolution, got: {res:?}"
            );

            let test_guard = NetGuard::allow_loopback_for_test();
            let pinned = test_guard
                .resolve_and_validate_host("127.0.0.1", 8443)
                .await
                .expect("test loopback guard resolves 127.0.0.1");
            assert_eq!(pinned.len(), 1);
            assert_eq!(pinned[0].ip().to_string(), "127.0.0.1");
        }
    }

    #[test]
    fn test_netguard_rejects_ipv6_transition_and_private_ranges() {
        let guard = NetGuard::production();
        let blocked_addrs = [
            "::1",
            "::",
            "fe80::1",
            "fc00::1",
            "fd12:3456:789a::1",
            "ff02::1",
            "2001:db8::1",
            "::ffff:127.0.0.1",
            "::ffff:10.0.0.1",
            "::ffff:100.64.0.1",
            "::ffff:169.254.169.254",
            "::7f00:1",
            "::a00:1",
            "64:ff9b::7f00:1",
            "64:ff9b::a00:1",
            "64:ff9b:1::a00:1",
            "2002:7f00:0001::",
            "2002:0a00:0001::",
            "2001:0000:4136:e378:8000:63bf:80ff:fffe",
            "2001:0000:4136:e378:8000:63bf:f5ff:fffe",
            "2607:f8b0:4005:800:0:5efe:7f00:1",
            "2607:f8b0:4005:800:200:5efe:a00:1",
        ];
        for raw in blocked_addrs {
            let ip: IpAddr = raw.parse().expect(raw);
            let res = guard.validate_ip(ip);
            assert!(
                matches!(res, Err(GChatError::SsrfBlocked(_))),
                "expected NetGuard to block {raw} ({ip}), got: {res:?}"
            );
        }

        let public_v6: IpAddr = "2607:f8b0:4005:800::200e".parse().unwrap();
        assert!(guard.validate_ip(public_v6).is_ok());
    }
}
