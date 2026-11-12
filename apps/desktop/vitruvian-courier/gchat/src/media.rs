// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use crate::auth::map_reqwest_error;
use crate::cookies::{DomainCookieJar, DEFAULT_MACOS_SAFARI_UA};
use crate::netguard::{EndpointRole, NetGuard};
use crate::{pb, GChatClient, GChatError};
use base64::Engine as _;
use prost::Message as _;
use std::time::Duration;
use url::Url;

pub const MAX_MEDIA_BYTES: usize = 200 * 1024 * 1024;
pub const MAX_AVATAR_OR_EXTERNAL_BYTES: usize = 20 * 1024 * 1024;
pub const MAX_AVATAR_BYTES: usize = 10 * 1024 * 1024;
pub const MAX_EXTERNAL_IMAGE_BYTES: usize = MAX_AVATAR_OR_EXTERNAL_BYTES;
pub const MAX_ATTACHMENT_REDIRECT_HOPS: usize = 10;
pub const MAX_AVATAR_REDIRECT_HOPS: usize = 5;

const FIFE_IMAGE_SIZE: &str = "w10000-h10000";
const MAX_UPLOAD_METADATA_RESPONSE_BYTES: usize = 1024 * 1024;

fn scotty_start_url(base_url: &Url, raw_group_id: &str) -> Result<Url, GChatError> {
    let mut start_url = base_url
        .join("/uploads")
        .map_err(|e| GChatError::Internal(format!("invalid Scotty start URL: {e}")))?;
    start_url
        .query_pairs_mut()
        .append_pair("group_id", raw_group_id.trim());
    Ok(start_url)
}

fn decode_upload_metadata(raw: &[u8]) -> Result<pb::UploadMetadata, GChatError> {
    let cleaned: Vec<u8> = raw
        .iter()
        .copied()
        .filter(|b| !b.is_ascii_whitespace())
        .collect();
    let decoded_bytes = base64::engine::general_purpose::STANDARD
        .decode(&cleaned)
        .or_else(|_| base64::engine::general_purpose::STANDARD_NO_PAD.decode(&cleaned))
        .unwrap_or_else(|_| raw.to_vec());

    if let Ok(wrapped) = pb::ComGoogleRtcMeetingsV1UploadMetadata::decode(decoded_bytes.as_slice())
    {
        if let Some(inner) = wrapped.upload_metadata {
            if inner.payload.is_some()
                || inner.content_name.is_some()
                || inner.content_type.is_some()
                || inner.cloned_drive_id.is_some()
            {
                return Ok(inner);
            }
        }
    }

    let direct = pb::UploadMetadata::decode(decoded_bytes.as_slice()).map_err(|e| {
        GChatError::Proto(format!(
            "failed to decode Scotty UploadMetadata response: {e}"
        ))
    })?;
    if direct.payload.is_none() && direct.cloned_drive_id.is_none() {
        return Err(GChatError::Proto(
            "Scotty UploadMetadata response contained no attachment_token".to_string(),
        ));
    }
    Ok(direct)
}

fn cookie_header_for_download_hop(jar: &DomainCookieJar, url: &Url) -> Option<String> {
    jar.cookie_header_for_request(url)
}

crate::edition2021! {
    async fn read_stream_capped(
        mut resp: reqwest::Response,
        max_bytes: usize,
        label: &str,
    ) -> Result<(Vec<u8>, String), GChatError> {
        if let Some(len) = resp.content_length() {
            if len > max_bytes as u64 {
                return Err(GChatError::Protocol(format!(
                    "{label} Content-Length ({len} bytes) exceeds maximum allowed ({max_bytes} bytes)"
                )));
            }
        }
        let content_type = resp
            .headers()
            .get(reqwest::header::CONTENT_TYPE)
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.split(';').next())
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "application/octet-stream".to_string());

        let mut buf = Vec::new();
        while let Some(chunk) = resp
            .chunk()
            .await
            .map_err(|e| GChatError::Network(format!("reading {label} stream: {e}")))?
        {
            let next_len = buf.len().saturating_add(chunk.len());
            if next_len > max_bytes {
                return Err(GChatError::Protocol(format!(
                    "{label} stream exceeded maximum allowed size ({max_bytes} bytes)"
                )));
            }
            buf.extend_from_slice(&chunk);
        }
        Ok((buf, content_type))
    }

    async fn download_with_redirects(
        http: &reqwest::Client,
        guard: &NetGuard,
        initial_url: Url,
        role: EndpointRole,
        cookies: Option<&DomainCookieJar>,
        user_agent: &str,
        max_bytes: usize,
        max_redirect_hops: usize,
        label: &str,
    ) -> Result<(Vec<u8>, String), GChatError> {
        let mut current_url = initial_url;
        for hop in 0..=max_redirect_hops {
            guard.validate_url_with_role(&current_url, role).await?;

            let mut req = http
                .get(current_url.clone())
                .timeout(Duration::from_secs(60))
                .header("User-Agent", user_agent);

            if role == EndpointRole::AuthenticatedAttachment {
                if let Some(jar) = cookies {
                    if let Some(cookie_hdr) = cookie_header_for_download_hop(jar, &current_url) {
                        req = req.header("Cookie", cookie_hdr);
                    }
                }
            }

            let resp = req
                .send()
                .await
                .map_err(|e| map_reqwest_error(&format!("{label} GET failed"), e))?;

            let status = resp.status();
            if matches!(status.as_u16(), 301 | 302 | 303 | 307 | 308) {
                if hop >= max_redirect_hops {
                    return Err(GChatError::SsrfBlocked(format!(
                        "{label} exceeded maximum redirect hops ({max_redirect_hops})"
                    )));
                }
                let loc = resp
                    .headers()
                    .get(reqwest::header::LOCATION)
                    .and_then(|v| v.to_str().ok())
                    .map(|s| s.trim())
                    .filter(|s| !s.is_empty())
                    .ok_or_else(|| {
                        GChatError::Protocol(format!(
                            "{label} redirect HTTP {} missing Location header",
                            status.as_u16()
                        ))
                    })?;
                if loc.contains("accounts.google.com") || loc.contains("ServiceLogin") {
                    return Err(GChatError::AuthExpired(
                        "attachment download redirected to Google sign-in".to_string(),
                    ));
                }
                current_url = current_url.join(loc).map_err(|e| {
                    GChatError::SsrfBlocked(format!("{label} invalid redirect Location '{loc}': {e}"))
                })?;
                continue;
            }

            if status.as_u16() == 401 || status.as_u16() == 403 {
                return Err(GChatError::AuthExpired(format!(
                    "{label} returned HTTP {}",
                    status.as_u16()
                )));
            }
            if status.as_u16() == 429 {
                return Err(GChatError::RateLimited);
            }
            if !status.is_success() {
                return Err(GChatError::HttpStatus(
                    status.as_u16(),
                    format!("{label} failed"),
                ));
            }

            return read_stream_capped(resp, max_bytes, label).await;
        }

        Err(GChatError::SsrfBlocked(format!(
            "{label} exceeded maximum redirect hops ({max_redirect_hops})"
        )))
    }

    pub async fn scotty_upload(
        client: &GChatClient,
        raw_group_id: &str,
        filename: &str,
        content_type: &str,
        data: &[u8],
    ) -> Result<pb::UploadMetadata, GChatError> {
        if raw_group_id.trim().is_empty() {
            return Err(GChatError::Protocol(
                "scotty_upload requires a non-empty group_id".to_string(),
            ));
        }
        if data.is_empty() {
            return Err(GChatError::Protocol(
                "scotty_upload refuses empty media payload".to_string(),
            ));
        }
        if data.len() > MAX_MEDIA_BYTES {
            return Err(GChatError::Protocol(format!(
                "media payload ({} bytes) exceeds 200 MiB limit ({MAX_MEDIA_BYTES} bytes)",
                data.len()
            )));
        }

        let safe_filename = if filename.trim().is_empty() {
            "attachment.bin"
        } else {
            filename.trim()
        };
        let safe_content_type = if content_type.trim().is_empty() {
            "application/octet-stream"
        } else {
            content_type.trim()
        };

        let start_url = scotty_start_url(&client.base_url, raw_group_id)?;

        client
            .guard
            .validate_url_with_role(&start_url, EndpointRole::ChatRpcAndUpload)
            .await?;

        let (xsrf_token, _) = client.xsrf.get_token().await?;
        let start_body = serde_json::json!({
            "filename": safe_filename,
        })
        .to_string();

        let mut start_req = client
            .http
            .post(start_url.clone())
            .timeout(Duration::from_secs(30))
            .header("User-Agent", &client.user_agent)
            .header("x-framework-xsrf-token", &xsrf_token)
            .header("Content-Type", "application/json; charset=UTF-8")
            .header("x-goog-upload-command", "start")
            .header("x-goog-upload-protocol", "resumable")
            .header("x-goog-upload-content-length", data.len().to_string())
            .header("x-goog-upload-content-type", safe_content_type)
            .header("x-goog-upload-file-name", safe_filename)
            .header(
                "x-goog-upload-header-content-length",
                data.len().to_string(),
            )
            .header("x-goog-upload-header-content-type", safe_content_type)
            .body(start_body);

        if let Some(cookie_hdr) = client.jar.cookie_header_for_request(&start_url) {
            start_req = start_req.header("Cookie", cookie_hdr);
        }

        let start_resp = start_req
            .send()
            .await
            .map_err(|e| map_reqwest_error("Scotty start upload failed", e))?;

        let start_status = start_resp.status();
        if start_status.as_u16() == 401 || start_status.as_u16() == 403 {
            return Err(GChatError::AuthExpired(format!(
                "Scotty start upload returned HTTP {}",
                start_status.as_u16()
            )));
        }
        if start_status.as_u16() == 429 {
            return Err(GChatError::RateLimited);
        }
        if !start_status.is_success() {
            return Err(GChatError::HttpStatus(
                start_status.as_u16(),
                "Scotty start upload failed".to_string(),
            ));
        }

        let upload_url_raw = start_resp
            .headers()
            .get("x-goog-upload-url")
            .and_then(|v| v.to_str().ok())
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .ok_or_else(|| {
                GChatError::Protocol(
                    "Scotty start response missing x-goog-upload-url header".to_string(),
                )
            })?;

        let upload_url = Url::parse(&upload_url_raw).map_err(|e| {
            GChatError::SsrfBlocked(format!(
                "Scotty returned invalid x-goog-upload-url '{upload_url_raw}': {e}"
            ))
        })?;

        // Validate upload URL against ChatRpcAndUpload role + DNS/IP guard BEFORE sending any byte or header.
        client
            .guard
            .validate_url_with_role(&upload_url, EndpointRole::ChatRpcAndUpload)
            .await?;

        let mut put_req = client
            .http
            .put(upload_url.clone())
            .timeout(Duration::from_secs(120))
            .header("User-Agent", &client.user_agent)
            .header(
                "Content-Type",
                "application/x-www-form-urlencoded;charset=utf-8",
            )
            .header("x-goog-upload-command", "upload, finalize")
            .header("x-goog-upload-protocol", "resumable")
            .header("x-goog-upload-offset", "0")
            .body(data.to_vec());

        if !xsrf_token.is_empty()
            && client
                .guard
                .is_host_allowed(upload_url.host_str().unwrap_or_default(), false)
        {
            put_req = put_req.header("x-framework-xsrf-token", &xsrf_token);
        }
        if let Some(cookie_hdr) = client.jar.cookie_header_for_request(&upload_url) {
            put_req = put_req.header("Cookie", cookie_hdr);
        }

        let put_resp = put_req
            .send()
            .await
            .map_err(|e| map_reqwest_error("Scotty finalize upload failed", e))?;

        let put_status = put_resp.status();
        if put_status.as_u16() == 401 || put_status.as_u16() == 403 {
            return Err(GChatError::AuthExpired(format!(
                "Scotty finalize upload returned HTTP {}",
                put_status.as_u16()
            )));
        }
        if put_status.as_u16() == 429 {
            return Err(GChatError::RateLimited);
        }
        if !put_status.is_success() {
            return Err(GChatError::HttpStatus(
                put_status.as_u16(),
                "Scotty finalize upload failed".to_string(),
            ));
        }

        let (resp_bytes, _) = read_stream_capped(
            put_resp,
            MAX_UPLOAD_METADATA_RESPONSE_BYTES,
            "Scotty upload response",
        )
        .await?;
        let mut meta = decode_upload_metadata(&resp_bytes)?;
        if meta.content_name.as_deref().unwrap_or_default().is_empty() {
            meta.content_name = Some(safe_filename.to_string());
        }
        if meta.content_type.as_deref().unwrap_or_default().is_empty() {
            meta.content_type = Some(safe_content_type.to_string());
        }
        Ok(meta)
    }

    pub async fn download_attachment(
        client: &GChatClient,
        attachment_token: &str,
    ) -> Result<(Vec<u8>, String), GChatError> {
        download_attachment_with_content_type(client, attachment_token, "").await
    }

    pub async fn download_attachment_with_content_type(
        client: &GChatClient,
        attachment_token: &str,
        content_type: &str,
    ) -> Result<(Vec<u8>, String), GChatError> {
        let token = attachment_token.trim();
        if token.is_empty() {
            return Err(GChatError::Protocol(
                "download_attachment requires a non-empty attachment_token".to_string(),
            ));
        }
        let mut url = client
            .base_url
            .join("/u/0/api/get_attachment_url")
            .map_err(|e| GChatError::Internal(format!("invalid get_attachment_url: {e}")))?;
        {
            let mut qp = url.query_pairs_mut();
            qp.append_pair("alt", "proto")
                .append_pair("attachment_token", token);
            let trimmed_ct = content_type.trim();
            if trimmed_ct.to_ascii_lowercase().starts_with("image/") {
                qp.append_pair("url_type", "FIFE_URL")
                    .append_pair("sz", FIFE_IMAGE_SIZE)
                    .append_pair("content_type", trimmed_ct);
            } else {
                qp.append_pair("url_type", "DOWNLOAD_URL");
            }
        }

        let (bytes, resp_ct) = download_with_redirects(
            &client.http,
            &client.guard,
            url,
            EndpointRole::AuthenticatedAttachment,
            Some(&client.jar),
            &client.user_agent,
            MAX_MEDIA_BYTES,
            MAX_ATTACHMENT_REDIRECT_HOPS,
            "attachment download",
        )
        .await?;
        if resp_ct.to_ascii_lowercase().starts_with("text/html") {
            return Err(GChatError::Protocol(
                "attachment download returned unexpected text/html response".to_string(),
            ));
        }
        Ok((bytes, resp_ct))
    }

    pub async fn download_avatar(
        guard: &NetGuard,
        avatar_url: &str,
    ) -> Result<(Vec<u8>, String), GChatError> {
        let url = Url::parse(avatar_url.trim())
            .map_err(|e| GChatError::SsrfBlocked(format!("invalid avatar URL: {e}")))?;
        let http = guard.http_client()?;
        download_with_redirects(
            http,
            guard,
            url,
            EndpointRole::AvatarHost,
            None,
            DEFAULT_MACOS_SAFARI_UA,
            MAX_AVATAR_BYTES,
            MAX_AVATAR_REDIRECT_HOPS,
            "avatar download",
        )
        .await
    }

    pub async fn download_external_image_if_enabled(
        guard: &NetGuard,
        url_str: &str,
        enabled: bool,
    ) -> Result<Option<(Vec<u8>, String)>, GChatError> {
        if !enabled {
            return Ok(None);
        }
        let url = Url::parse(url_str.trim())
            .map_err(|e| GChatError::SsrfBlocked(format!("invalid external image URL: {e}")))?;
        let http = guard.http_client()?;
        let res = download_with_redirects(
            http,
            guard,
            url,
            EndpointRole::ExternalPublicImage,
            None,
            DEFAULT_MACOS_SAFARI_UA,
            MAX_EXTERNAL_IMAGE_BYTES,
            MAX_AVATAR_REDIRECT_HOPS,
            "external image download",
        )
        .await?;
        Ok(Some(res))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{Arc, Mutex};
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;

    crate::edition2021! {
    async fn read_http_request(stream: &mut tokio::net::TcpStream) -> (String, Vec<String>, Vec<u8>) {
        let mut buf = Vec::new();
        let mut temp = [0u8; 4096];
        let mut header_end = None;
        let mut content_length = 0usize;

        loop {
            let n = stream.read(&mut temp).await.unwrap_or(0);
            if n == 0 {
                break;
            }
            buf.extend_from_slice(&temp[..n]);
            if header_end.is_none() {
                if let Some(pos) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
                    header_end = Some(pos + 4);
                    let hdr_str = String::from_utf8_lossy(&buf[..pos]);
                    for line in hdr_str.lines() {
                        if let Some((k, v)) = line.split_once(':') {
                            if k.trim().eq_ignore_ascii_case("content-length") {
                                content_length = v.trim().parse().unwrap_or(0);
                            }
                        }
                    }
                }
            }
            if let Some(end) = header_end {
                if buf.len() >= end + content_length {
                    break;
                }
            }
        }

        let end = header_end.unwrap_or(buf.len());
        let hdr_text = String::from_utf8_lossy(&buf[..end]).into_owned();
        let mut lines = hdr_text.lines();
        let request_line = lines.next().unwrap_or_default().to_string();
        let headers: Vec<String> = lines
            .filter(|l| !l.trim().is_empty())
            .map(|l| l.to_string())
            .collect();
        let body = if end < buf.len() {
            buf[end..std::cmp::min(buf.len(), end + content_length)].to_vec()
        } else {
            Vec::new()
        };
        (request_line, headers, body)
    }

    fn build_loopback_client(base_url: &str) -> GChatClient {
        let cfg = serde_json::json!({
            "cookie_map": {
                "COMPASS": "dynamite-ui=synthetic_compass",
                "OSID": "synthetic_osid",
                "SID": "synthetic_sid",
                "HSID": "synthetic_hsid",
                "SSID": "synthetic_ssid"
            },
            "base_url": base_url
        });
        GChatClient::from_config_json_with_guard(&cfg.to_string(), NetGuard::allow_loopback_for_test())
            .expect("loopback GChatClient")
    }

    #[test]
    fn test_scotty_two_step_upload_and_redirect_download_strip_cookies_on_cdn() {
        let client_holder: Arc<Mutex<Option<GChatClient>>> = Arc::new(Mutex::new(None));
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        rt.block_on(async {
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let base_url = format!("http://{addr}/");

            let start_headers_recorded: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
            let start_body_recorded: Arc<Mutex<Vec<u8>>> = Arc::new(Mutex::new(Vec::new()));
            let put_headers_recorded: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
            let put_body_recorded: Arc<Mutex<Vec<u8>>> = Arc::new(Mutex::new(Vec::new()));
            let cdn_headers_recorded: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
            let hostile_put_hits = Arc::new(AtomicUsize::new(0));
            let next_upload_url: Arc<Mutex<String>> =
                Arc::new(Mutex::new(format!("http://{addr}/u/0/upload_put?upload_id=up_1")));

            let sh_clone = Arc::clone(&start_headers_recorded);
            let sb_clone = Arc::clone(&start_body_recorded);
            let ph_clone = Arc::clone(&put_headers_recorded);
            let pb_clone = Arc::clone(&put_body_recorded);
            let ch_clone = Arc::clone(&cdn_headers_recorded);
            let hp_clone = Arc::clone(&hostile_put_hits);
            let nu_clone = Arc::clone(&next_upload_url);

            let server_task = tokio::spawn(async move {
                loop {
                    let Ok((mut stream, _)) = listener.accept().await else {
                        break;
                    };
                    let sh = Arc::clone(&sh_clone);
                    let sb = Arc::clone(&sb_clone);
                    let ph = Arc::clone(&ph_clone);
                    let pb = Arc::clone(&pb_clone);
                    let ch = Arc::clone(&ch_clone);
                    let hp = Arc::clone(&hp_clone);
                    let nu = Arc::clone(&nu_clone);
                    tokio::spawn(async move {
                        let (req_line, headers, body) = read_http_request(&mut stream).await;
                        if req_line.contains("/u/0/mole/world") {
                            let html = r#"<!DOCTYPE html><script>window.WIZ_global_data = {"xsrf_token":"AF1QipP_scotty_token:1710000000000"};</script>"#;
                            let resp = format!(
                                "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                                html.len(),
                                html
                            );
                            let _ = stream.write_all(resp.as_bytes()).await;
                        } else if req_line.starts_with("POST /uploads?group_id=space_xyz") {
                            *sh.lock().unwrap() = headers;
                            *sb.lock().unwrap() = body;
                            let up_url = nu.lock().unwrap().clone();
                            let resp = format!(
                                "HTTP/1.1 200 OK\r\nx-goog-upload-url: {up_url}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                            );
                            let _ = stream.write_all(resp.as_bytes()).await;
                        } else if req_line.starts_with("PUT /u/0/upload_put?upload_id=up_1") {
                            *ph.lock().unwrap() = headers;
                            *pb.lock().unwrap() = body;
                            let upload_meta = pb::UploadMetadata {
                                payload: Some(pb::upload_metadata::Payload::AttachmentToken(
                                    "tok_1".to_string(),
                                )),
                                content_name: Some("diagram.png".to_string()),
                                content_type: Some("image/png".to_string()),
                                local_id: None,
                                cloned_drive_id: None,
                            };
                            let wrapped = pb::ComGoogleRtcMeetingsV1UploadMetadata {
                                upload_metadata: Some(upload_meta),
                            }
                            .encode_to_vec();
                            let b64 = base64::engine::general_purpose::STANDARD.encode(&wrapped);
                            let resp = format!(
                                "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                                b64.len(),
                                b64
                            );
                            let _ = stream.write_all(resp.as_bytes()).await;
                        } else if req_line.starts_with("PUT ") {
                            hp.fetch_add(1, Ordering::SeqCst);
                            let _ = stream
                                .write_all(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                                .await;
                        } else if req_line.starts_with("GET /u/0/api/get_attachment_url?alt=proto&attachment_token=tok_1")
                            || req_line.starts_with("GET /api/get_attachment_url?alt=proto&attachment_token=tok_1")
                        {
                            let cdn_url = format!("http://lh3.googleusercontent.com:{}/cdn/blob_tok_1", addr.port());
                            let resp = format!(
                                "HTTP/1.1 302 Found\r\nLocation: {cdn_url}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                            );
                            let _ = stream.write_all(resp.as_bytes()).await;
                        } else if req_line.starts_with("GET /u/0/api/get_attachment_url?alt=proto&attachment_token=tok_loop")
                            || req_line.starts_with("GET /cdn/loop")
                        {
                            let loop_url = format!("http://{addr}/cdn/loop");
                            let resp = format!(
                                "HTTP/1.1 302 Found\r\nLocation: {loop_url}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                            );
                            let _ = stream.write_all(resp.as_bytes()).await;
                        } else if req_line.starts_with("GET /u/0/api/get_attachment_url?alt=proto&attachment_token=tok_hostile") {
                            let resp = "HTTP/1.1 302 Found\r\nLocation: https://attacker.invalid/blob\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                            let _ = stream.write_all(resp.as_bytes()).await;
                        } else if req_line.starts_with("GET /u/0/api/get_attachment_url?alt=proto&attachment_token=tok_private") {
                            let resp = "HTTP/1.1 302 Found\r\nLocation: https://10.0.0.1/blob\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                            let _ = stream.write_all(resp.as_bytes()).await;
                        } else if req_line.starts_with("GET /u/0/api/get_attachment_url?alt=proto&attachment_token=tok_oversized") {
                            let over = MAX_MEDIA_BYTES + 1;
                            let resp = format!(
                                "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: {over}\r\nConnection: close\r\n\r\n"
                            );
                            let _ = stream.write_all(resp.as_bytes()).await;
                        } else if req_line.starts_with("GET /cdn/blob_tok_1") {
                            *ch.lock().unwrap() = headers;
                            let payload = b"\x89PNG\r\n\x1a\nsynthetic-png-payload";
                            let resp_hdr = format!(
                                "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                                payload.len()
                            );
                            let _ = stream.write_all(resp_hdr.as_bytes()).await;
                            let _ = stream.write_all(payload).await;
                        } else {
                            let _ = stream
                                .write_all(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                                .await;
                        }
                    });
                }
            });

            let client = build_loopback_client(&base_url);

            // Step 1 + Step 2: Scotty 2-step upload
            let file_bytes = b"\x89PNG\r\n\x1a\nsynthetic-png-payload";
            let uploaded = scotty_upload(&client, "space_xyz", "diagram.png", "image/png", file_bytes)
                .await
                .expect("scotty_upload should succeed");
            assert_eq!(
                uploaded.payload,
                Some(pb::upload_metadata::Payload::AttachmentToken("tok_1".to_string()))
            );
            assert_eq!(uploaded.content_name.as_deref(), Some("diagram.png"));
            assert_eq!(uploaded.content_type.as_deref(), Some("image/png"));

            let start_hdrs = start_headers_recorded.lock().unwrap().join("\n").to_ascii_lowercase();
            assert!(start_hdrs.contains("x-goog-upload-command: start"));
            assert!(start_hdrs.contains("x-goog-upload-protocol: resumable"));
            assert!(start_hdrs.contains("x-goog-upload-header-content-length: 29"));
            assert!(start_hdrs.contains("x-goog-upload-header-content-type: image/png"));
            let start_body_str = String::from_utf8_lossy(&start_body_recorded.lock().unwrap()).into_owned();
            assert!(start_body_str.contains("diagram.png"));

            let put_hdrs = put_headers_recorded.lock().unwrap().join("\n").to_ascii_lowercase();
            assert!(put_hdrs.contains("x-goog-upload-command: upload, finalize"));
            assert!(put_hdrs.contains("x-goog-upload-protocol: resumable"));
            assert!(put_hdrs.contains("x-goog-upload-offset: 0"));
            assert_eq!(put_body_recorded.lock().unwrap().as_slice(), file_bytes);

            // Security check: hostile upload URLs returned in x-goog-upload-url must be refused BEFORE any PUT is sent
            for hostile in [
                "https://attacker.invalid/upload",
                "https://93.184.216.34/upload",
                "http://chat.google.com/u/0/upload_put",
                "https://user:pass@chat.google.com/u/0/upload_put",
                "https://ch\u{0430}t.google.com/u/0/upload_put",
            ] {
                *next_upload_url.lock().unwrap() = hostile.to_string();
                let res = scotty_upload(&client, "space_xyz", "diagram.png", "image/png", file_bytes).await;
                assert!(res.is_err(), "hostile x-goog-upload-url {hostile} must be refused");
            }
            assert_eq!(
                hostile_put_hits.load(Ordering::SeqCst),
                0,
                "no bytes or headers may be sent to a hostile upload URL"
            );

            // Download attachment via get_attachment_url -> 302 redirect to CDN hop, stripping Cookie and XSRF headers
            let (dl_bytes, dl_mime) = download_attachment(&client, "tok_1")
                .await
                .expect("download_attachment should succeed");
            assert_eq!(dl_bytes.as_slice(), file_bytes);
            assert_eq!(dl_mime, "image/png");

            let cdn_hdrs = cdn_headers_recorded.lock().unwrap().join("\n").to_ascii_lowercase();
            assert!(
                !cdn_hdrs.contains("cookie:"),
                "CDN redirect hop must NOT receive Cookie header, got:\n{cdn_hdrs}"
            );
            assert!(
                !cdn_hdrs.contains("x-framework-xsrf-token:"),
                "CDN redirect hop must NOT receive x-framework-xsrf-token header, got:\n{cdn_hdrs}"
            );

            // Redirect cap check (> 10 hops refused)
            let loop_res = download_attachment(&client, "tok_loop").await;
            assert!(
                matches!(loop_res, Err(GChatError::SsrfBlocked(_))),
                "redirect loop exceeding MAX_REDIRECT_HOPS must be rejected, got: {loop_res:?}"
            );

            // Redirect hop to hostile host refused
            let hostile_redir = download_attachment(&client, "tok_hostile").await;
            assert!(
                matches!(hostile_redir, Err(GChatError::SsrfBlocked(_))),
                "redirect hop to non-allowlisted host must be rejected, got: {hostile_redir:?}"
            );

            // Redirect hop to private IP refused
            let private_redir = download_attachment(&client, "tok_private").await;
            assert!(
                matches!(private_redir, Err(GChatError::SsrfBlocked(_))),
                "redirect hop to private IP must be rejected, got: {private_redir:?}"
            );

            // Oversized download body (> 200 MiB) refused
            let oversized_res = download_attachment(&client, "tok_oversized").await;
            assert!(
                oversized_res.is_err(),
                "download body exceeding 200 MiB cap must be rejected"
            );

            // Avatar download from loopback CDN works and rejects non-avatar host in production
            let avatar_url = format!("http://{addr}/cdn/blob_tok_1");
            let (av_bytes, av_mime) = download_avatar(&client.guard, &avatar_url)
                .await
                .expect("avatar download should succeed");
            assert_eq!(av_bytes.as_slice(), file_bytes);
            assert_eq!(av_mime, "image/png");
            assert!(
                download_avatar(&NetGuard::production(), "https://chat.google.com/a/avatar")
                    .await
                    .is_err(),
                "download_avatar must reject non-avatar host chat.google.com"
            );

            // External image download disabled by default returns Ok(None) with zero network traffic
            let ext_disabled = download_external_image_if_enabled(
                &NetGuard::production(),
                "https://127.0.0.1/should-not-be-fetched.png",
                false,
            )
            .await
            .expect("disabled external image must return Ok(None)");
            assert!(ext_disabled.is_none());

            *client_holder.lock().unwrap() = Some(client);
            server_task.abort();
        });
        drop(rt);
        drop(client_holder);
    }

    #[test]
    fn test_scotty_upload_and_get_attachment_url_include_all_protocol_fields() {
        let client_holder: Arc<Mutex<Option<GChatClient>>> = Arc::new(Mutex::new(None));
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        rt.block_on(async {
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let base_url = format!("http://{addr}/");

            let start_headers_recorded: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
            let put_headers_recorded: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
            let get_att_req_lines: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));

            let sh_clone = Arc::clone(&start_headers_recorded);
            let ph_clone = Arc::clone(&put_headers_recorded);
            let ga_clone = Arc::clone(&get_att_req_lines);

            let server_task = tokio::spawn(async move {
                loop {
                    let Ok((mut stream, _)) = listener.accept().await else {
                        break;
                    };
                    let sh = Arc::clone(&sh_clone);
                    let ph = Arc::clone(&ph_clone);
                    let ga = Arc::clone(&ga_clone);
                    tokio::spawn(async move {
                        let (req_line, headers, _) = read_http_request(&mut stream).await;
                        if req_line.contains("/u/0/mole/world") {
                            let html = r#"<!DOCTYPE html><script>window.WIZ_global_data = {"xsrf_token":"AF1QipP_scotty_token:1710000000000"};</script>"#;
                            let resp = format!(
                                "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                                html.len(),
                                html
                            );
                            let _ = stream.write_all(resp.as_bytes()).await;
                        } else if req_line.starts_with("POST /uploads?group_id=space_xyz") {
                            *sh.lock().unwrap() = headers;
                            let up_url = format!("http://{addr}/u/0/upload_put?upload_id=up_f4");
                            let resp = format!(
                                "HTTP/1.1 200 OK\r\nx-goog-upload-url: {up_url}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                            );
                            let _ = stream.write_all(resp.as_bytes()).await;
                        } else if req_line.starts_with("PUT /u/0/upload_put?upload_id=up_f4") {
                            *ph.lock().unwrap() = headers;
                            let upload_meta = pb::UploadMetadata {
                                payload: Some(pb::upload_metadata::Payload::AttachmentToken(
                                    "tok_f4".to_string(),
                                )),
                                content_name: Some("photo.png".to_string()),
                                content_type: Some("image/png".to_string()),
                                local_id: None,
                                cloned_drive_id: None,
                            };
                            let b64 = base64::engine::general_purpose::STANDARD
                                .encode(upload_meta.encode_to_vec());
                            let resp = format!(
                                "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                                b64.len(),
                                b64
                            );
                            let _ = stream.write_all(resp.as_bytes()).await;
                        } else if req_line.starts_with("GET /u/0/api/get_attachment_url?") {
                            ga.lock().unwrap().push(req_line);
                            let payload = b"ok-bytes";
                            let resp = format!(
                                "HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                                payload.len()
                            );
                            let _ = stream.write_all(resp.as_bytes()).await;
                            let _ = stream.write_all(payload).await;
                        }
                    });
                }
            });

            let client = build_loopback_client(&base_url);
            let file_bytes = b"\x89PNG\r\n\x1a\nsynthetic-png-payload";
            let _ = scotty_upload(&client, "space_xyz", "photo.png", "image/png", file_bytes)
                .await
                .expect("scotty_upload should succeed");

            let start_hdrs = start_headers_recorded.lock().unwrap().join("\n").to_ascii_lowercase();
            assert!(
                start_hdrs.contains("x-goog-upload-content-length: 29"),
                "Scotty Step 1 must include x-goog-upload-content-length header, got:\n{start_hdrs}"
            );
            assert!(
                start_hdrs.contains("x-goog-upload-content-type: image/png"),
                "Scotty Step 1 must include x-goog-upload-content-type header, got:\n{start_hdrs}"
            );
            assert!(
                start_hdrs.contains("x-goog-upload-file-name: photo.png"),
                "Scotty Step 1 must include x-goog-upload-file-name header, got:\n{start_hdrs}"
            );

            let put_hdrs = put_headers_recorded.lock().unwrap().join("\n").to_ascii_lowercase();
            assert!(
                put_hdrs.contains("x-framework-xsrf-token: af1qipp_scotty_token:1710000000000"),
                "Scotty Step 2 PUT must include x-framework-xsrf-token on allowlisted host, got:\n{put_hdrs}"
            );

            let _ = download_attachment(&client, "tok_f4").await.unwrap();
            let req_lines = get_att_req_lines.lock().unwrap().clone();
            assert!(
                req_lines.iter().any(|l| l.contains("url_type=")),
                "get_attachment_url must include url_type query param, got: {req_lines:?}"
            );

            *client_holder.lock().unwrap() = Some(client);
            server_task.abort();
        });
        drop(rt);
        drop(client_holder);
    }

    #[test]
    fn test_cookie_stripping_depends_purely_on_hostname_via_test_dns() {
        let client_holder: Arc<Mutex<Option<GChatClient>>> = Arc::new(Mutex::new(None));
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        rt.block_on(async {
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let port = addr.port();
            let base_url = format!("http://chat.google.com:{port}/");

            let guc_headers_recorded: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
            let chat_hop2_headers_recorded: Arc<Mutex<Vec<String>>> = Arc::new(Mutex::new(Vec::new()));
            let guc_clone = Arc::clone(&guc_headers_recorded);
            let chat_clone = Arc::clone(&chat_hop2_headers_recorded);

            let server_task = tokio::spawn(async move {
                loop {
                    let Ok((mut stream, _)) = listener.accept().await else {
                        break;
                    };
                    let guc = Arc::clone(&guc_clone);
                    let chat2 = Arc::clone(&chat_clone);
                    tokio::spawn(async move {
                        let (req_line, headers, _) = read_http_request(&mut stream).await;
                        if req_line.starts_with("GET /u/0/api/get_attachment_url") {
                            let loc = format!("http://lh3.googleusercontent.com:{port}/cdn/reauth");
                            let resp = format!(
                                "HTTP/1.1 302 Found\r\nLocation: {loc}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                            );
                            let _ = stream.write_all(resp.as_bytes()).await;
                        } else if req_line.starts_with("GET /cdn/reauth") {
                            *guc.lock().unwrap() = headers;
                            let loc = format!("http://chat.google.com:{port}/u/0/api/final_blob");
                            let resp = format!(
                                "HTTP/1.1 302 Found\r\nLocation: {loc}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                            );
                            let _ = stream.write_all(resp.as_bytes()).await;
                        } else if req_line.starts_with("GET /u/0/api/final_blob") {
                            *chat2.lock().unwrap() = headers;
                            let payload = b"reauth-blob";
                            let resp = format!(
                                "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                                payload.len()
                            );
                            let _ = stream.write_all(resp.as_bytes()).await;
                            let _ = stream.write_all(payload).await;
                        }
                    });
                }
            });

            let client = build_loopback_client(&base_url);
            let (bytes, _) = download_attachment(&client, "tok_dns")
                .await
                .expect("download_attachment across hostname hops via test DNS should succeed");
            assert_eq!(bytes, b"reauth-blob");

            let guc_hdrs = guc_headers_recorded.lock().unwrap().join("\n").to_ascii_lowercase();
            assert!(
                !guc_hdrs.contains("cookie:"),
                "lh3.googleusercontent.com hop must NEVER receive cookies, got:\n{guc_hdrs}"
            );

            let chat2_hdrs = chat_hop2_headers_recorded.lock().unwrap().join("\n").to_ascii_lowercase();
            assert!(
                chat2_hdrs.contains("cookie:") && chat2_hdrs.contains("compass="),
                "redirect hop back to chat.google.com must retain Google cookies, got:\n{chat2_hdrs}"
            );

            *client_holder.lock().unwrap() = Some(client);
            server_task.abort();
        });
        drop(rt);
        drop(client_holder);
    }

    #[test]
    fn test_redirect_status_codes_and_hop_caps_across_downloads() {
        let client_holder: Arc<Mutex<Option<GChatClient>>> = Arc::new(Mutex::new(None));
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();

        rt.block_on(async {
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let port = addr.port();
            let base_url = format!("http://{addr}/");
            let guard = NetGuard::allow_loopback_for_test();

            let server_task = tokio::spawn(async move {
                loop {
                    let Ok((mut stream, _)) = listener.accept().await else {
                        break;
                    };
                    tokio::spawn(async move {
                        let (req_line, _, _) = read_http_request(&mut stream).await;
                        if let Some(rest) = req_line.strip_prefix("GET /a/hop") {
                            let hop_str = rest.split_whitespace().next().unwrap_or("");
                            if let Ok(hop_num) = hop_str.parse::<usize>() {
                                if hop_num == 0 {
                                    let _ = stream.write_all(b"HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok").await;
                                } else {
                                    let status_line = match hop_num % 4 {
                                        0 => "HTTP/1.1 301 Moved Permanently",
                                        1 => "HTTP/1.1 302 Found",
                                        2 => "HTTP/1.1 307 Temporary Redirect",
                                        _ => "HTTP/1.1 308 Permanent Redirect",
                                    };
                                    let next_hop = hop_num - 1;
                                    let loc = format!("http://127.0.0.1:{port}/a/hop{next_hop}");
                                    let resp = format!("{status_line}\r\nLocation: {loc}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                                    let _ = stream.write_all(resp.as_bytes()).await;
                                }
                                return;
                            }
                        }
                        if req_line.starts_with("GET /u/0/api/get_attachment_url?alt=proto&attachment_token=tok_10") {
                            let loc = format!("http://127.0.0.1:{port}/a/hop9");
                            let resp = format!("HTTP/1.1 302 Found\r\nLocation: {loc}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                            let _ = stream.write_all(resp.as_bytes()).await;
                        } else if req_line.starts_with("GET /u/0/api/get_attachment_url?alt=proto&attachment_token=tok_11") {
                            let loc = format!("http://127.0.0.1:{port}/a/hop10");
                            let resp = format!("HTTP/1.1 302 Found\r\nLocation: {loc}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                            let _ = stream.write_all(resp.as_bytes()).await;
                        } else if req_line.starts_with("GET /a/hostile_chain") {
                            let loc = "https://evil.example.com/steal";
                            let resp = format!("HTTP/1.1 302 Found\r\nLocation: {loc}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                            let _ = stream.write_all(resp.as_bytes()).await;
                        } else if req_line.starts_with("GET /a/status304") {
                            let loc = format!("http://127.0.0.1:{port}/a/hop0");
                            let resp = format!("HTTP/1.1 304 Not Modified\r\nLocation: {loc}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                            let _ = stream.write_all(resp.as_bytes()).await;
                        }
                    });
                }
            });

            // 5-hop avatar redirect chain (hop5 -> ... -> hop0) must succeed
            let five_hop_url = format!("http://127.0.0.1:{port}/a/hop5");
            let five_hop_res = download_avatar(&guard, &five_hop_url).await.expect("5-hop avatar chain should succeed");
            assert_eq!(five_hop_res.0, b"ok");

            // Hostile redirect chain to non-allowlisted host must be rejected by NetGuard
            let hostile_url = format!("http://127.0.0.1:{port}/a/hostile_chain");
            let hostile_res = download_avatar(&guard, &hostile_url).await;
            assert!(
                matches!(hostile_res, Err(GChatError::SsrfBlocked(_))),
                "hostile redirect chain must be blocked by NetGuard, got: {hostile_res:?}"
            );

            // 6-hop avatar redirect chain must fail because MAX_AVATAR_REDIRECT_HOPS is 5
            let six_hop_url = format!("http://127.0.0.1:{port}/a/hop6");
            let six_hop_res = download_avatar(&guard, &six_hop_url).await;
            assert!(
                matches!(six_hop_res, Err(GChatError::SsrfBlocked(_))),
                "avatar redirect chain of 6 hops must be rejected by 5-hop cap, got: {six_hop_res:?}"
            );

            // 10-hop attachment redirect chain must succeed, while 11-hop must fail (MAX_ATTACHMENT_REDIRECT_HOPS is 10)
            let client = build_loopback_client(&base_url);
            let ten_hop_att = download_attachment(&client, "tok_10").await.expect("10-hop attachment chain should succeed");
            assert_eq!(ten_hop_att.0, b"ok");

            let eleven_hop_att = download_attachment(&client, "tok_11").await;
            assert!(
                matches!(eleven_hop_att, Err(GChatError::SsrfBlocked(_))),
                "attachment redirect chain of 11 hops must be rejected by 10-hop cap, got: {eleven_hop_att:?}"
            );

            // Non-redirect 3xx status (304 Not Modified with Location) must not be followed
            let status_304_url = format!("http://127.0.0.1:{port}/a/status304");
            let status_304_res = download_avatar(&guard, &status_304_url).await;
            assert!(
                status_304_res.is_err(),
                "HTTP 304 must not be followed as a redirect, got: {status_304_res:?}"
            );

            *client_holder.lock().unwrap() = Some(client);
            server_task.abort();
        });
        drop(rt);
        drop(client_holder);

        let base = Url::parse("https://chat.google.com/").unwrap();
        let start_url = scotty_start_url(&base, "space_xyz").unwrap();
        assert_eq!(start_url.as_str(), "https://chat.google.com/uploads?group_id=space_xyz");
        assert_eq!(MAX_ATTACHMENT_REDIRECT_HOPS, 10);
        assert_eq!(MAX_AVATAR_REDIRECT_HOPS, 5);
    }

    #[test]
    fn test_build_loopback_client_does_not_mutate_global_test_override() {
        crate::netguard::set_global_test_loopback_override(false);
        let client = build_loopback_client("http://127.0.0.1:8080/");
        assert!(
            !NetGuard::from_ambient().is_loopback_test_allowed(),
            "build_loopback_client must not leave global TEST_LOOPBACK_OVERRIDE set to true"
        );
        drop(client);
    }
    }
}
