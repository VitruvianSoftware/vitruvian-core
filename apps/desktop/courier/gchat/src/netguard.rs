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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EndpointRole {
    ChatRpcAndUpload,        // chat.google.com, mail.google.com/chat
    AuthenticatedAttachment, // chat.google.com, mail.google.com, *.googleusercontent.com, *.ggpht.com, docs.google.com, drive.google.com
    AvatarHost,              // *.googleusercontent.com, *.ggpht.com
    ExternalPublicImage,     // HTTPS-only, non-private IP, no cookies
}

pub fn is_globally_routable_ip(ip: IpAddr) -> bool {
    NetGuard::production().validate_ip(ip).is_ok()
}

fn has_valid_subdomain_suffix(host: &str, suffix: &str) -> bool {
    let Some(prefix) = host.strip_suffix(suffix) else {
        return false;
    };
    if prefix.is_empty() || prefix.contains("..") {
        return false;
    }
    prefix.split('.').all(|label| {
        !label.is_empty()
            && !label.starts_with('-')
            && !label.ends_with('-')
            && !label.starts_with("xn--")
            && label.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
    })
}

pub fn validate_url_for_role(
    url: &Url,
    role: EndpointRole,
    allow_loopback_test: bool,
) -> Result<(), GChatError> {
    if !url.username().is_empty() || url.password().is_some() {
        return Err(GChatError::SsrfBlocked(
            "URL must not contain userinfo credentials".to_string(),
        ));
    }
    let raw_host = url
        .host_str()
        .ok_or_else(|| GChatError::SsrfBlocked("URL missing host".to_string()))?;
    let host = raw_host
        .trim_matches(|c| c == '[' || c == ']')
        .to_ascii_lowercase();
    let is_loopback_host = host == "127.0.0.1" || host == "localhost" || host == "::1";
    let scheme = url.scheme();
    if allow_loopback_test && is_loopback_host {
        if scheme != "https" && scheme != "http" {
            return Err(GChatError::SsrfBlocked(format!(
                "disallowed URL scheme: {scheme}"
            )));
        }
        return Ok(());
    }
    let allow_test_http_with_port = allow_loopback_test && url.port().is_some();
    if scheme != "https" && !(allow_test_http_with_port && scheme == "http") {
        return Err(GChatError::SsrfBlocked(format!(
            "disallowed non-HTTPS URL scheme: {scheme}"
        )));
    }

    let is_ip_literal = matches!(
        url.host(),
        Some(url::Host::Ipv4(_)) | Some(url::Host::Ipv6(_))
    ) || host.parse::<IpAddr>().is_ok();

    match role {
        EndpointRole::ChatRpcAndUpload => {
            if is_ip_literal || host.contains("xn--") {
                return Err(GChatError::SsrfBlocked(format!(
                    "disallowed upload/RPC host: {host}"
                )));
            }
            let allowed = host == "chat.google.com"
                || host == "upload.video.google.com"
                || (host == "mail.google.com"
                    && (url.path() == "/chat" || url.path().starts_with("/chat/")));
            if !allowed {
                return Err(GChatError::SsrfBlocked(format!(
                    "upload/RPC URL not in allowlist: {url}"
                )));
            }
            Ok(())
        }
        EndpointRole::AuthenticatedAttachment => {
            if is_ip_literal || host.contains("xn--") {
                return Err(GChatError::SsrfBlocked(format!(
                    "disallowed attachment host: {host}"
                )));
            }
            let allowed = matches!(
                host.as_str(),
                "chat.google.com" | "mail.google.com" | "docs.google.com" | "drive.google.com"
            ) || has_valid_subdomain_suffix(&host, ".googleusercontent.com")
                || has_valid_subdomain_suffix(&host, ".ggpht.com");
            if !allowed {
                return Err(GChatError::SsrfBlocked(format!(
                    "attachment host not in allowlist: {host}"
                )));
            }
            Ok(())
        }
        EndpointRole::AvatarHost => {
            if is_ip_literal || host.contains("xn--") {
                return Err(GChatError::SsrfBlocked(format!(
                    "disallowed avatar host: {host}"
                )));
            }
            let allowed = has_valid_subdomain_suffix(&host, ".googleusercontent.com")
                || has_valid_subdomain_suffix(&host, ".ggpht.com");
            if !allowed {
                return Err(GChatError::SsrfBlocked(format!(
                    "avatar host not in allowlist: {host}"
                )));
            }
            Ok(())
        }
        EndpointRole::ExternalPublicImage => {
            if is_ip_literal || host.contains("xn--") {
                return Err(GChatError::SsrfBlocked(format!(
                    "disallowed external image host: {host}"
                )));
            }
            let allowed = has_valid_subdomain_suffix(&host, ".googleusercontent.com")
                || has_valid_subdomain_suffix(&host, ".ggpht.com");
            if !allowed {
                return Err(GChatError::SsrfBlocked(format!(
                    "external image host not in allowlist: {host}"
                )));
            }
            Ok(())
        }
    }
}

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
    client: Arc<std::sync::OnceLock<Client>>,
}

impl NetGuard {
    pub fn production() -> Self {
        Self {
            #[cfg(any(test, feature = "test-loopback"))]
            allow_loopback_for_test: false,
            #[cfg(not(any(test, feature = "test-loopback")))]
            _production_only: (),
            client: Arc::new(std::sync::OnceLock::new()),
        }
    }

    pub(crate) fn from_ambient() -> Self {
        Self {
            #[cfg(any(test, feature = "test-loopback"))]
            allow_loopback_for_test: TEST_LOOPBACK_OVERRIDE
                .load(std::sync::atomic::Ordering::SeqCst),
            #[cfg(not(any(test, feature = "test-loopback")))]
            _production_only: (),
            client: Arc::new(std::sync::OnceLock::new()),
        }
    }

    #[cfg(any(test, feature = "test-loopback"))]
    pub fn allow_loopback_for_test() -> Self {
        Self {
            allow_loopback_for_test: true,
            client: Arc::new(std::sync::OnceLock::new()),
        }
    }

    fn resolver_clone(&self) -> Self {
        Self {
            #[cfg(any(test, feature = "test-loopback"))]
            allow_loopback_for_test: self.allow_loopback_for_test,
            #[cfg(not(any(test, feature = "test-loopback")))]
            _production_only: (),
            client: Arc::new(std::sync::OnceLock::new()),
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
            .dns_resolver(Arc::new(self.resolver_clone()))
            .build()
            .map_err(|e| GChatError::Internal(format!("failed to build HTTP client: {e}")))
    }

    pub fn http_client(&self) -> Result<&Client, GChatError> {
        if let Some(c) = self.client.get() {
            return Ok(c);
        }
        let built = self.build_http_client()?;
        let _ = self.client.set(built);
        self.client
            .get()
            .ok_or_else(|| GChatError::Internal("failed to initialize HTTP client".to_string()))
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
        if lower.parse::<IpAddr>().is_ok() || lower.contains("xn--") {
            return false;
        }
        if ALLOWED_API_HOSTS.contains(&lower.as_str()) {
            return true;
        }
        if allow_media_hosts
            && (matches!(lower.as_str(), "docs.google.com" | "drive.google.com")
                || has_valid_subdomain_suffix(&lower, ".googleusercontent.com")
                || has_valid_subdomain_suffix(&lower, ".ggpht.com"))
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
            #[cfg(any(test, feature = "test-loopback"))]
            if self.is_loopback_test_allowed()
                && !clean_host.eq_ignore_ascii_case("localhost")
                && self.is_host_allowed(&clean_host.to_ascii_lowercase(), true)
            {
                return Ok(vec![SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), port)]);
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

        pub async fn validate_url_with_role(
            &self,
            url: &Url,
            role: EndpointRole,
        ) -> Result<Vec<SocketAddr>, GChatError> {
            validate_url_for_role(url, role, self.is_loopback_test_allowed())?;
            let raw_host = url
                .host_str()
                .ok_or_else(|| GChatError::SsrfBlocked("URL missing host".to_string()))?;
            let host = raw_host
                .trim_matches(|c| c == '[' || c == ']')
                .to_ascii_lowercase();
            let port = url.port_or_known_default().unwrap_or(443);
            self.resolve_and_validate_host(&host, port).await
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

    #[test]
    fn test_ssrf_guard_rejects_private_and_embedded_ipv6_addresses() {
        let non_routable_ips = [
            "127.0.0.1",
            "10.0.0.1",
            "172.16.0.1",
            "192.168.1.1",
            "100.64.0.1",
            "169.254.169.254",
            "0.0.0.0",
            "::1",
            "fe80::1",
            "fc00::1",
            "fd12:3456::1",
            "::ffff:127.0.0.1",
            "::ffff:169.254.169.254",
            "::10.0.0.1",
            "2002:7f00:0001::1",
            "64:ff9b::a00:1",
            "64:ff9b:1::c0a8:101",
            "2001:0000:4136:e378:8000:63bf:f5ff:fefe",
            "fe80::200:5efe:10.0.0.1",
            "2607:f8b0:4005:800:200:5efe:10.0.0.1",
        ];
        for raw in non_routable_ips {
            let ip: IpAddr = raw.parse().expect("valid IP");
            assert!(
                !is_globally_routable_ip(ip),
                "expected {raw} to be rejected by is_globally_routable_ip"
            );
        }

        assert!(is_globally_routable_ip("8.8.8.8".parse().unwrap()));
        assert!(is_globally_routable_ip("142.250.190.46".parse().unwrap()));
        assert!(is_globally_routable_ip(
            "2607:f8b0:4005:800::200e".parse().unwrap()
        ));

        // Role validation: ChatRpcAndUpload
        let ok_chat = Url::parse("https://chat.google.com/u/0/uploads?group_id=space_1").unwrap();
        assert!(validate_url_for_role(&ok_chat, EndpointRole::ChatRpcAndUpload, false).is_ok());
        let ok_mail =
            Url::parse("https://mail.google.com/chat/u/0/uploads?group_id=space_1").unwrap();
        assert!(validate_url_for_role(&ok_mail, EndpointRole::ChatRpcAndUpload, false).is_ok());

        let hostile_upload_urls = [
            "https://evil.example.com/upload",
            "https://142.250.190.46/upload",
            "https://127.0.0.1/upload",
            "http://chat.google.com/u/0/uploads",
            "https://chat.google.com@evil.example.com/upload",
            "https://user:pass@chat.google.com/u/0/uploads",
            "https://ch\u{0430}t.google.com/u/0/uploads", // Cyrillic 'а' IDN lookalike
            "https://mail.google.com/mail/u/0/",
            "https://lh3.googleusercontent.com/upload",
        ];
        for raw in hostile_upload_urls {
            let url = Url::parse(raw).expect("parse URL");
            assert!(
                validate_url_for_role(&url, EndpointRole::ChatRpcAndUpload, false).is_err(),
                "expected hostile upload URL {raw} to be rejected"
            );
        }

        // Role validation: AuthenticatedAttachment
        for allowed in [
            "https://chat.google.com/u/0/api/get_attachment_url?alt=proto&attachment_token=t",
            "https://mail.google.com/chat/u/0/api/get_attachment_url",
            "https://lh3.googleusercontent.com/attachment/blob1",
            "https://yt3.ggpht.com/attachment/blob2",
            "https://docs.google.com/document/d/1",
            "https://drive.google.com/file/d/1",
        ] {
            let url = Url::parse(allowed).unwrap();
            assert!(
                validate_url_for_role(&url, EndpointRole::AuthenticatedAttachment, false).is_ok(),
                "expected attachment URL {allowed} to be allowed"
            );
        }
        for rejected in [
            "https://evil.googleusercontent.com.attacker.invalid/blob",
            "http://lh3.googleusercontent.com/blob",
            "https://user@lh3.googleusercontent.com/blob",
            "https://142.250.190.46/blob",
        ] {
            let url = Url::parse(rejected).unwrap();
            assert!(
                validate_url_for_role(&url, EndpointRole::AuthenticatedAttachment, false).is_err(),
                "expected attachment URL {rejected} to be rejected"
            );
        }

        // Role validation: AvatarHost
        assert!(validate_url_for_role(
            &Url::parse("https://lh3.googleusercontent.com/a/avatar").unwrap(),
            EndpointRole::AvatarHost,
            false
        )
        .is_ok());
        assert!(validate_url_for_role(
            &Url::parse("https://yt3.ggpht.com/a/avatar").unwrap(),
            EndpointRole::AvatarHost,
            false
        )
        .is_ok());
        assert!(validate_url_for_role(
            &Url::parse("https://chat.google.com/a/avatar").unwrap(),
            EndpointRole::AvatarHost,
            false
        )
        .is_err());

        // Role validation: ExternalPublicImage (must restrict to Google media hosts, rejecting arbitrary third-party domains)
        assert!(validate_url_for_role(
            &Url::parse("https://lh3.googleusercontent.com/pic.png").unwrap(),
            EndpointRole::ExternalPublicImage,
            false
        )
        .is_ok());
        assert!(validate_url_for_role(
            &Url::parse("https://yt3.ggpht.com/pic.png").unwrap(),
            EndpointRole::ExternalPublicImage,
            false
        )
        .is_ok());
        assert!(
            validate_url_for_role(
                &Url::parse("https://images.example.com/pic.png").unwrap(),
                EndpointRole::ExternalPublicImage,
                false
            )
            .is_err(),
            "ExternalPublicImage must reject non-Google third-party host images.example.com"
        );
        assert!(validate_url_for_role(
            &Url::parse("http://lh3.googleusercontent.com/pic.png").unwrap(),
            EndpointRole::ExternalPublicImage,
            false
        )
        .is_err());
        assert!(validate_url_for_role(
            &Url::parse("https://127.0.0.1/pic.png").unwrap(),
            EndpointRole::ExternalPublicImage,
            false
        )
        .is_err());
        assert!(validate_url_for_role(
            &Url::parse("https://user@lh3.googleusercontent.com/pic.png").unwrap(),
            EndpointRole::ExternalPublicImage,
            false
        )
        .is_err());
    }

    #[test]
    fn test_only_netguard_constructs_reqwest_client() {
        let non_netguard_sources = [
            ("lib.rs", include_str!("lib.rs")),
            ("auth.rs", include_str!("auth.rs")),
            ("channel.rs", include_str!("channel.rs")),
            ("cookies.rs", include_str!("cookies.rs")),
            ("ffi.rs", include_str!("ffi.rs")),
            ("media.rs", include_str!("media.rs")),
            ("pblite.rs", include_str!("pblite.rs")),
            ("rpc.rs", include_str!("rpc.rs")),
            ("fmt/mod.rs", include_str!("fmt/mod.rs")),
            ("fmt/inbound.rs", include_str!("fmt/inbound.rs")),
            ("fmt/outbound.rs", include_str!("fmt/outbound.rs")),
        ];
        for (name, src) in non_netguard_sources {
            assert!(
                !src.contains("Client::builder(")
                    && !src.contains("reqwest::Client::new(")
                    && !src.contains("reqwest::Client::builder("),
                "{name} must not construct a reqwest::Client; all HTTP requests must go through NetGuard::build_http_client"
            );
        }
    }

    #[test]
    fn test_is_host_allowed_enforces_subdomain_suffix_and_rejects_punycode_and_arbitrary_google_com() {
        let guard = NetGuard::production();
        assert!(guard.is_host_allowed("lh3.googleusercontent.com", true));
        assert!(guard.is_host_allowed("yt3.ggpht.com", true));
        assert!(guard.is_host_allowed("docs.google.com", true));
        assert!(guard.is_host_allowed("drive.google.com", true));
        assert!(!guard.is_host_allowed(".googleusercontent.com", true));
        assert!(!guard.is_host_allowed("-bad.googleusercontent.com", true));
        assert!(!guard.is_host_allowed("xn--evil.googleusercontent.com", true));
        assert!(!guard.is_host_allowed("arbitrary.google.com", true));
        assert!(!guard.is_host_allowed("142.250.190.46", true));
    }
}
