// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
// SPDX-License-Identifier: MIT

//! The Roborock cloud HTTP API: region discovery, emailed-code login, and
//! the home data that lists the account's devices and rooms.
//!
//! A port of the parts of python-roborock 7.12.1's `roborock/web_api.py`
//! this crate uses: `getUrlByEmail`, `request_code_v4` (falling back to the
//! v1 `sendEmailCode`), `code_login_v4` (with the `x-mercy-k` signed nonce
//! and the latest user agreement version, falling back to the v1
//! `loginWithCode`), `getHomeDetail`, `/v3/user/homes/<id>` and
//! `/user/homes/<id>/rooms`, the last two signed with Hawk.

use crate::auth::{ApiClient, ApiError};
use crate::crypto;
use crate::protocol::Rriot;
use serde_json::{Map, Value};
use std::sync::Mutex;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub const BASE_URLS: [&str; 4] = [
    "https://usiot.roborock.com",
    "https://euiot.roborock.com",
    "https://cniot.roborock.com",
    "https://ruiot.roborock.com",
];

const DEFAULT_AGREEMENT: (i64, i64) = (14, 0);
const TIMEOUT: Duration = Duration::from_secs(30);

fn err(class: &str, msg: impl Into<String>) -> ApiError {
    ApiError::new(class, msg)
}

fn generic(doc: &Value) -> ApiError {
    err(
        "RoborockException",
        format!(
            "{} - response code: {}",
            doc.get("msg")
                .and_then(Value::as_str)
                .unwrap_or("unknown error"),
            doc.get("code")
                .map(Value::to_string)
                .unwrap_or_else(|| "none".into())
        ),
    )
}

/// How a request is sent. Kept as data so tests can check what would go
/// over the wire without a network.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpRequest {
    pub method: &'static str,
    pub url: String,
    pub query: Vec<(String, String)>,
    pub headers: Vec<(String, String)>,
    pub form: Option<Vec<(String, String)>>,
}

pub trait Transport: Send + Sync {
    fn send(&self, req: &HttpRequest) -> Result<Value, ApiError>;
}

/// The real transport: ureq with rustls.
pub struct Ureq {
    agent: ureq::Agent,
}

impl Default for Ureq {
    fn default() -> Self {
        Self {
            // Base URLs come from server responses; never follow one to
            // plain HTTP.
            agent: ureq::AgentBuilder::new()
                .timeout(TIMEOUT)
                .https_only(true)
                .build(),
        }
    }
}

impl Transport for Ureq {
    fn send(&self, req: &HttpRequest) -> Result<Value, ApiError> {
        let mut r = self.agent.request(req.method, &req.url);
        for (k, v) in &req.query {
            r = r.query(k, v);
        }
        for (k, v) in &req.headers {
            r = r.set(k, v);
        }
        let result = match &req.form {
            Some(form) => {
                let pairs: Vec<(&str, &str)> =
                    form.iter().map(|(k, v)| (k.as_str(), v.as_str())).collect();
                r.send_form(&pairs)
            }
            None => r.call(),
        };
        let response = match result {
            Ok(resp) => resp,
            // Roborock puts its error code in a JSON body even on HTTP errors.
            Err(ureq::Error::Status(_, resp)) => resp,
            // Only the kind of failure: ureq's own message repeats the whole
            // URL, query string (email, login code) included.
            Err(ureq::Error::Transport(t)) => {
                return Err(err(
                    "RoborockNoResponseFromBaseURL",
                    format!(
                        "Network error contacting {}: {}",
                        strip_query(&req.url),
                        t.kind()
                    ),
                ))
            }
        };
        let body = response.into_string().map_err(|e| {
            err(
                "RoborockNoResponseFromBaseURL",
                format!("Network error contacting {}: {e}", strip_query(&req.url)),
            )
        })?;
        serde_json::from_str(&body).map_err(|e| {
            err(
                "RoborockException",
                format!("{} did not return JSON: {e}", strip_query(&req.url)),
            )
        })
    }
}

fn strip_query(url: &str) -> &str {
    url.split('?').next().unwrap_or(url)
}

/// `PreparedRequest`'s URL joining: strip slashes at the seams.
fn join(base: &str, path: &str) -> String {
    format!(
        "{}/{}",
        base.trim_end_matches('/'),
        path.trim_start_matches('/')
    )
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct IotLogin {
    base_url: String,
    country: Option<String>,
    country_code: Option<String>,
}

/// `RoborockApiClient` for one email address. Login is two calls that must
/// share one client: Roborock ties the emailed code to the client id.
pub struct CloudClient {
    username: String,
    device_identifier: String,
    base_urls: Mutex<Vec<String>>,
    fixed_base_url: Option<String>,
    login: Mutex<Option<IotLogin>>,
    transport: Box<dyn Transport>,
}

impl CloudClient {
    pub fn new(username: &str, base_url: Option<String>) -> Self {
        Self::with_transport(username, base_url, Box::new(Ureq::default()))
    }

    pub fn with_transport(
        username: &str,
        base_url: Option<String>,
        transport: Box<dyn Transport>,
    ) -> Self {
        let base_urls = match &base_url {
            Some(u) => vec![u.clone()],
            None => BASE_URLS.iter().map(|s| s.to_string()).collect(),
        };
        Self {
            username: username.to_string(),
            device_identifier: crypto::token_urlsafe(16),
            base_urls: Mutex::new(base_urls),
            fixed_base_url: base_url,
            login: Mutex::new(None),
            transport,
        }
    }

    fn header_client_id(&self) -> String {
        let mut input = self.username.as_bytes().to_vec();
        input.extend_from_slice(self.device_identifier.as_bytes());
        crypto::b64(&crypto::md5(&input))
    }

    fn iot_login(&self) -> Result<IotLogin, ApiError> {
        if let Some(l) = self.login.lock().unwrap_or_else(|e| e.into_inner()).clone() {
            return Ok(l);
        }
        let urls = self
            .base_urls
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .clone();
        for iot_url in urls {
            let req = HttpRequest {
                method: "POST",
                url: join(&iot_url, "/api/v1/getUrlByEmail"),
                query: vec![
                    ("email".into(), self.username.clone()),
                    ("needtwostepauth".into(), "false".into()),
                ],
                headers: vec![],
                form: None,
            };
            let Ok(doc) = self.transport.send(&req) else {
                continue;
            };
            match doc.get("code").and_then(Value::as_i64) {
                Some(200) => {}
                Some(2003) => return Err(err("RoborockInvalidEmail", "Your email was incorrectly formatted.")),
                Some(1001) => {
                    return Err(err(
                        "RoborockMissingParameters",
                        "You are missing parameters for this request, are you sure you entered your username?",
                    ))
                }
                _ => return Err(generic(&doc)),
            }
            let data = doc.get("data").cloned().unwrap_or(Value::Null);
            let as_string = |v: Option<&Value>| match v {
                Some(Value::String(s)) => Some(s.clone()),
                Some(Value::Number(n)) => Some(n.to_string()),
                _ => None,
            };
            let country = as_string(data.get("country"));
            let country_code = as_string(data.get("countrycode"));
            if country.is_some() || country_code.is_some() {
                let login = IotLogin {
                    base_url: data
                        .get("url")
                        .and_then(Value::as_str)
                        .unwrap_or(&iot_url)
                        .to_string(),
                    country,
                    country_code,
                };
                *self.login.lock().unwrap_or_else(|e| e.into_inner()) = Some(login.clone());
                return Ok(login);
            }
        }
        Err(err(
            "RoborockNoResponseFromBaseURL",
            "No account was found for any base url we tried. Either your email is incorrect or we do not have a record of the roborock server your device is on.",
        ))
    }

    fn resolved_base_url(&self) -> Result<String, ApiError> {
        match &self.fixed_base_url {
            Some(u) => Ok(u.clone()),
            None => Ok(self.iot_login()?.base_url),
        }
    }

    fn request_code_v1(&self) -> Result<(), ApiError> {
        let req = HttpRequest {
            method: "POST",
            url: join(&self.resolved_base_url()?, "/api/v1/sendEmailCode"),
            query: vec![
                ("username".into(), self.username.clone()),
                ("type".into(), "auth".into()),
            ],
            headers: vec![("header_clientid".into(), self.header_client_id())],
            form: None,
        };
        let doc = self.transport.send(&req)?;
        match doc.get("code").and_then(Value::as_i64) {
            Some(200) => Ok(()),
            Some(2008) => Err(err(
                "RoborockAccountDoesNotExist",
                "Account does not exist - check your login and try again.",
            )),
            Some(9002) => Err(err(
                "RoborockTooFrequentCodeRequests",
                "You have attempted to request too many codes. Try again later",
            )),
            _ => Err(generic(&doc)),
        }
    }

    fn sign_key_v3(&self, s: &str) -> Result<String, ApiError> {
        let req = HttpRequest {
            method: "POST",
            url: join(&self.resolved_base_url()?, "/api/v3/key/sign"),
            query: vec![("s".into(), s.into())],
            headers: vec![("header_clientid".into(), self.header_client_id())],
            form: None,
        };
        let doc = self.transport.send(&req)?;
        let k = doc
            .get("data")
            .and_then(|d| d.get("k"))
            .and_then(Value::as_str)
            .ok_or_else(|| {
                err(
                    "RoborockException",
                    "Failed to get a response from sign key",
                )
            })?;
        if doc.get("code").and_then(Value::as_i64) != Some(200) {
            return Err(generic(&doc));
        }
        Ok(k.to_string())
    }

    fn agreement_version(&self, country: &str) -> (i64, i64) {
        let Ok(base) = self.resolved_base_url() else {
            return DEFAULT_AGREEMENT;
        };
        let req = HttpRequest {
            method: "GET",
            url: join(&base, "/api/v3/app/agreement/latest"),
            query: vec![("country".into(), country.into())],
            headers: vec![("header_clientlang".into(), "en".into())],
            form: None,
        };
        let Ok(doc) = self.transport.send(&req) else {
            return DEFAULT_AGREEMENT;
        };
        if doc.get("code").and_then(Value::as_i64) == Some(200) {
            let data = doc.get("data").cloned().unwrap_or(Value::Null);
            if let (Some(major), Some(minor)) = (
                data.get("majorVersion").and_then(Value::as_i64),
                data.get("minorVersion").and_then(Value::as_i64),
            ) {
                return (major, minor);
            }
        }
        DEFAULT_AGREEMENT
    }

    fn login_result(doc: Value) -> Result<Map<String, Value>, ApiError> {
        match doc.get("code").and_then(Value::as_i64) {
            Some(200) => {}
            Some(2018) => return Err(err("RoborockInvalidCode", "Invalid code - check your code and try again.")),
            Some(3009) => {
                return Err(err(
                    "RoborockNoUserAgreement",
                    "You must accept the user agreement in the Roborock app to continue.",
                ))
            }
            Some(3006) => {
                return Err(err(
                    "RoborockInvalidUserAgreement",
                    "User agreement must be accepted again - or you are attempting to use the Mi Home app account.",
                ))
            }
            Some(3039) => {
                return Err(err(
                    "RoborockAccountDoesNotExist",
                    "This account does not exist - please ensure that you selected the right region and email.",
                ))
            }
            _ => return Err(generic(&doc)),
        }
        doc.get("data")
            .and_then(Value::as_object)
            .cloned()
            .ok_or_else(|| {
                err(
                    "RoborockException",
                    "Got unexpected data type for user_data",
                )
            })
    }

    fn code_login_v1(&self, code: &str) -> Result<Map<String, Value>, ApiError> {
        let req = HttpRequest {
            method: "POST",
            url: join(&self.resolved_base_url()?, "/api/v1/loginWithCode"),
            query: vec![
                ("username".into(), self.username.clone()),
                ("verifycode".into(), code.into()),
                ("verifycodetype".into(), "AUTH_EMAIL_CODE".into()),
            ],
            headers: vec![("header_clientid".into(), self.header_client_id())],
            form: None,
        };
        Self::login_result(self.transport.send(&req)?)
    }
}

impl ApiClient for CloudClient {
    fn request_code_v4(&self) -> Result<(), ApiError> {
        let login = self.iot_login()?;
        if login.country.is_none() || login.country_code.is_none() {
            return self.request_code_v1();
        }
        let req = HttpRequest {
            method: "POST",
            url: join(&self.resolved_base_url()?, "/api/v4/email/code/send"),
            query: vec![],
            headers: vec![
                ("header_clientid".into(), self.header_client_id()),
                ("header_clientlang".into(), "en".into()),
            ],
            form: Some(vec![
                ("email".into(), self.username.clone()),
                ("type".into(), "login".into()),
                ("platform".into(), String::new()),
            ]),
        };
        let doc = self.transport.send(&req)?;
        match doc.get("code").and_then(Value::as_i64) {
            Some(200) => Ok(()),
            Some(2008) => Err(err(
                "RoborockAccountDoesNotExist",
                "Account does not exist - check your login and try again.",
            )),
            Some(9002) => Err(err(
                "RoborockTooFrequentCodeRequests",
                "You have attempted to request too many codes. Try again later",
            )),
            Some(3030) => {
                // Wrong region: drop the first base URL and rediscover.
                let retry = {
                    let mut urls = self.base_urls.lock().unwrap_or_else(|e| e.into_inner());
                    if urls.len() > 1 {
                        urls.remove(0);
                        true
                    } else {
                        false
                    }
                };
                if !retry {
                    return Err(generic(&doc));
                }
                *self.login.lock().unwrap_or_else(|e| e.into_inner()) = None;
                self.request_code_v4()
            }
            _ => Err(generic(&doc)),
        }
    }

    fn code_login_v4(&self, code: &str) -> Result<Map<String, Value>, ApiError> {
        let login = self.iot_login()?;
        let (Some(country), Some(country_code)) =
            (login.country.clone(), login.country_code.clone())
        else {
            return self.code_login_v1(code);
        };
        let ks = crypto::random_alphanumeric(16);
        let k = self.sign_key_v3(&ks)?;
        let (major, minor) = self.agreement_version(&country);
        let req = HttpRequest {
            method: "POST",
            url: join(&self.resolved_base_url()?, "/api/v4/auth/email/login/code"),
            query: vec![],
            headers: vec![
                ("header_clientid".into(), self.header_client_id()),
                ("x-mercy-ks".into(), ks),
                ("x-mercy-k".into(), k),
                ("header_clientlang".into(), "en".into()),
                ("header_appversion".into(), "4.54.02".into()),
                ("header_phonesystem".into(), "iOS".into()),
                ("header_phonemodel".into(), "iPhone16,1".into()),
            ],
            form: Some(vec![
                ("country".into(), country),
                ("countryCode".into(), country_code),
                ("email".into(), self.username.clone()),
                ("code".into(), code.into()),
                ("majorVersion".into(), major.to_string()),
                ("minorVersion".into(), minor.to_string()),
            ]),
        };
        Self::login_result(self.transport.send(&req)?)
    }

    fn base_url(&self) -> Option<String> {
        self.resolved_base_url().ok()
    }
}

/// `_get_hawk_authentication` for a GET with no query or body.
pub fn hawk(rriot: &Rriot, path: &str, timestamp: u64, nonce: &str) -> String {
    let prestr = [
        rriot.u.as_str(),
        rriot.s.as_str(),
        nonce,
        &timestamp.to_string(),
        &crypto::md5_hex(path.as_bytes()),
        "",
        "",
    ]
    .join(":");
    let mac = crypto::b64(&crypto::hmac_sha256(rriot.h.as_bytes(), prestr.as_bytes()));
    format!(
        "Hawk id=\"{}\",s=\"{}\",ts=\"{}\",nonce=\"{}\",mac=\"{}\"",
        rriot.u, rriot.s, timestamp, nonce, mac
    )
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// The signed-in part of the API, bound to one stored login.
pub struct UserApi<'a> {
    pub client: &'a CloudClient,
    pub user_data: &'a Map<String, Value>,
    pub rriot: Rriot,
}

impl<'a> UserApi<'a> {
    /// `_get_home_id`. Code 2010 means the stored login was revoked.
    pub fn home_id(&self) -> Result<i64, ApiError> {
        let token = self
            .user_data
            .get("token")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string();
        let req = HttpRequest {
            method: "GET",
            url: join(&self.client.resolved_base_url()?, "/api/v1/getHomeDetail"),
            query: vec![],
            headers: vec![
                ("header_clientid".into(), self.client.header_client_id()),
                ("Authorization".into(), token),
            ],
            form: None,
        };
        let doc = self.client.transport.send(&req)?;
        match doc.get("code").and_then(Value::as_i64) {
            Some(200) => {}
            Some(2010) => {
                return Err(err(
                    "RoborockInvalidCredentials",
                    format!(
                        "Invalid credentials ({}) - check your login and try again.",
                        doc.get("msg").and_then(Value::as_str).unwrap_or("")
                    ),
                ))
            }
            _ => return Err(generic(&doc)),
        }
        doc.get("data")
            .and_then(|d| d.get("rrHomeId"))
            .and_then(Value::as_i64)
            .ok_or_else(|| err("RoborockException", "getHomeDetail returned no rrHomeId"))
    }

    fn hawk_get(&self, path: &str) -> Result<Value, ApiError> {
        let req = HttpRequest {
            method: "GET",
            url: join(&self.rriot.api_url, path),
            query: vec![],
            headers: vec![(
                "Authorization".into(),
                hawk(&self.rriot, path, now(), &crypto::token_urlsafe(6)),
            )],
            form: None,
        };
        let doc = self.client.transport.send(&req)?;
        if doc.get("success").and_then(Value::as_bool) != Some(true) {
            return Err(err("RoborockException", doc.to_string()));
        }
        Ok(doc.get("result").cloned().unwrap_or(Value::Null))
    }

    /// `get_home_data_v3`: every device, product and room on the account.
    pub fn home_data(&self) -> Result<Map<String, Value>, ApiError> {
        let home_id = self.home_id()?;
        match self.hawk_get(&format!("/v3/user/homes/{home_id}"))? {
            Value::Object(o) => Ok(o),
            other => Err(err(
                "RoborockException",
                format!("home_response result was an unexpected type: {other}"),
            )),
        }
    }

    /// `get_rooms`: the account's rooms, as (iot id, name).
    pub fn rooms(&self) -> Result<Vec<(String, String)>, ApiError> {
        let home_id = self.home_id()?;
        match self.hawk_get(&format!("/user/homes/{home_id}/rooms"))? {
            Value::Array(rooms) => Ok(rooms_from(&rooms)),
            _ => Err(err(
                "RoborockException",
                "home_response result was an unexpected type",
            )),
        }
    }
}

pub fn rooms_from(rooms: &[Value]) -> Vec<(String, String)> {
    rooms
        .iter()
        .filter_map(|r| {
            let id = r.get("id")?;
            let id = match id {
                Value::Number(n) => n.to_string(),
                Value::String(s) => s.clone(),
                _ => return None,
            };
            Some((id, r.get("name")?.as_str()?.to_string()))
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::sync::Arc;

    /// Answers by path and records every request.
    struct Script {
        log: Arc<Mutex<Vec<HttpRequest>>>,
        answer: Box<dyn Fn(&HttpRequest) -> Value + Send + Sync>,
    }

    impl Transport for Script {
        fn send(&self, req: &HttpRequest) -> Result<Value, ApiError> {
            self.log.lock().unwrap().push(req.clone());
            Ok((self.answer)(req))
        }
    }

    fn client(
        answer: impl Fn(&HttpRequest) -> Value + Send + Sync + 'static,
    ) -> (CloudClient, Arc<Mutex<Vec<HttpRequest>>>) {
        let log = Arc::new(Mutex::new(Vec::new()));
        let c = CloudClient::with_transport(
            "me@example.com",
            None,
            Box::new(Script {
                log: log.clone(),
                answer: Box::new(answer),
            }),
        );
        (c, log)
    }

    fn region_ok(req: &HttpRequest) -> Option<Value> {
        req.url.ends_with("/api/v1/getUrlByEmail").then(|| {
            json!({"code": 200, "data": {"url": "https://usiot.roborock.com", "country": "US", "countrycode": "1"}})
        })
    }

    #[test]
    fn request_code_v4_discovers_the_region_then_posts_the_form() {
        let (c, log) = client(|req| region_ok(req).unwrap_or(json!({"code": 200})));
        c.request_code_v4().unwrap();
        let log = log.lock().unwrap();
        assert_eq!(log.len(), 2);
        let send = &log[1];
        assert_eq!(
            send.url,
            "https://usiot.roborock.com/api/v4/email/code/send"
        );
        assert_eq!(
            send.form.as_ref().unwrap(),
            &vec![
                ("email".to_string(), "me@example.com".to_string()),
                ("type".to_string(), "login".to_string()),
                ("platform".to_string(), String::new())
            ]
        );
        assert!(send.headers.iter().any(|(k, _)| k == "header_clientid"));
    }

    #[test]
    fn request_code_maps_roborock_error_codes() {
        let (c, _) =
            client(|req| region_ok(req).unwrap_or(json!({"code": 9002, "msg": "too often"})));
        assert_eq!(
            c.request_code_v4().unwrap_err().class_name,
            "RoborockTooFrequentCodeRequests"
        );
        let (c, _) = client(|req| region_ok(req).unwrap_or(json!({"code": 2008})));
        assert_eq!(
            c.request_code_v4().unwrap_err().class_name,
            "RoborockAccountDoesNotExist"
        );
    }

    #[test]
    fn code_login_v4_signs_a_nonce_and_sends_the_agreement_version() {
        let (c, log) = client(|req| {
            if let Some(v) = region_ok(req) {
                return v;
            }
            if req.url.ends_with("/api/v3/key/sign") {
                return json!({"code": 200, "data": {"k": "signed"}});
            }
            if req.url.ends_with("/api/v3/app/agreement/latest") {
                return json!({"code": 200, "data": {"majorVersion": 15, "minorVersion": 2}});
            }
            json!({"code": 200, "data": {"token": "t", "rriot": {}}})
        });
        let user = c.code_login_v4("123456").unwrap();
        assert_eq!(user["token"], "t");
        let log = log.lock().unwrap();
        let login = log.last().unwrap();
        assert_eq!(
            login.url,
            "https://usiot.roborock.com/api/v4/auth/email/login/code"
        );
        let headers: std::collections::HashMap<_, _> = login.headers.iter().cloned().collect();
        assert_eq!(headers["x-mercy-k"], "signed");
        assert_eq!(headers["x-mercy-ks"].len(), 16);
        let form: std::collections::HashMap<_, _> =
            login.form.clone().unwrap().into_iter().collect();
        assert_eq!(form["code"], "123456");
        assert_eq!(form["majorVersion"], "15");
        assert_eq!(form["countryCode"], "1");
        assert_eq!(c.base_url().as_deref(), Some("https://usiot.roborock.com"));
    }

    #[test]
    fn network_errors_never_repeat_the_query_string() {
        let ureq = Ureq::default();
        for url in [
            // Nothing listens on port 1: a transport error.
            "https://127.0.0.1:1/api/v1/loginWithCode",
            // Plain HTTP is refused outright.
            "http://127.0.0.1:1/api/v1/loginWithCode",
        ] {
            let e = ureq
                .send(&HttpRequest {
                    method: "POST",
                    url: url.into(),
                    query: vec![
                        ("username".into(), "secret@example.com".into()),
                        ("verifycode".into(), "424242".into()),
                    ],
                    headers: vec![],
                    form: None,
                })
                .unwrap_err();
            assert_eq!(e.class_name, "RoborockNoResponseFromBaseURL", "{url}");
            assert!(
                !e.message.contains("secret") && !e.message.contains("424242"),
                "{url}: {}",
                e.message
            );
        }
    }

    #[test]
    fn plain_http_is_refused_before_any_connection() {
        let e = Ureq::default()
            .send(&HttpRequest {
                method: "GET",
                url: "http://example.invalid/".into(),
                query: vec![],
                headers: vec![],
                form: None,
            })
            .unwrap_err();
        assert!(
            e.message.to_lowercase().contains("insecure")
                || e.message.contains("InsecureRequestHttpsOnly"),
            "{}",
            e.message
        );
    }

    #[test]
    fn a_wrong_code_is_reported_as_invalid_code() {
        let (c, _) = client(|req| {
            region_ok(req).unwrap_or_else(|| {
                if req.url.ends_with("/key/sign") {
                    json!({"code": 200, "data": {"k": "k"}})
                } else {
                    json!({"code": 2018})
                }
            })
        });
        assert_eq!(
            c.code_login_v4("1").unwrap_err().class_name,
            "RoborockInvalidCode"
        );
    }

    #[test]
    fn hawk_header_matches_python_roborock() {
        // The mac is the reference value from python-roborock 7.12.1's
        // formula (hmac-sha256 over "u:s:nonce:ts:md5(path)::", base64),
        // computed independently with Python's hashlib/hmac.
        let rriot = Rriot {
            u: "u".into(),
            s: "s".into(),
            h: "h".into(),
            k: "k".into(),
            api_url: String::new(),
            mqtt_url: String::new(),
        };
        let header = hawk(&rriot, "/v3/user/homes/1", 1_700_000_000, "nonce");
        assert_eq!(
            header,
            "Hawk id=\"u\",s=\"s\",ts=\"1700000000\",nonce=\"nonce\",mac=\"OI6u08uNjhAfJJUjOKZcmz3MWfvC/DqPoocxDmUjoxc=\""
        );
    }

    #[test]
    fn a_revoked_login_is_invalid_credentials() {
        let (c, _) =
            client(|req| region_ok(req).unwrap_or(json!({"code": 2010, "msg": "token expired"})));
        let user_data: Map<String, Value> = json!({"token": "t"}).as_object().unwrap().clone();
        let api = UserApi {
            client: &c,
            user_data: &user_data,
            rriot: Rriot {
                u: "u".into(),
                s: "s".into(),
                h: "h".into(),
                k: "k".into(),
                api_url: "https://api".into(),
                mqtt_url: String::new(),
            },
        };
        assert_eq!(
            api.home_id().unwrap_err().class_name,
            "RoborockInvalidCredentials"
        );
    }
}
