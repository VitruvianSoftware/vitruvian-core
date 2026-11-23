// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! The dashboard's pages, as HTML strings. No JavaScript, and no inline
//! style: the CSP is `default-src 'self'`, so everything a page looks like
//! comes from `/static/relay.css`.
//!
//! Every piece of text that did not come from this file goes through [`esc`],
//! which is the one place HTML is escaped. The pages are written for a person,
//! not an engineer: plain words, and what to do next.

use std::time::{SystemTime, UNIX_EPOCH};

use crate::devices::DEVICE_NAME_MAX;
use crate::mcp::ago;
use crate::store::ACTIVITY_RETENTION_DAYS;

use super::ACTIVITY_PAGE;

/// Escapes text for HTML, in a text position or inside a quoted attribute.
pub fn esc(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    for c in raw.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            c => out.push(c),
        }
    }
    out
}

// -------------------------------------------------------------------- times

/// Year, month and day of a day count since 1970-01-01 (proleptic Gregorian).
fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (yoe + era * 400 + i64::from(m <= 2), m, d)
}

fn utc_parts(t: SystemTime) -> (i64, u32, u32, u64, u64, u64) {
    let secs = match t.duration_since(UNIX_EPOCH) {
        Ok(d) => d.as_secs() as i64,
        Err(e) => -(e.duration().as_secs() as i64),
    };
    let (y, m, d) = civil_from_days(secs.div_euclid(86_400));
    let rest = secs.rem_euclid(86_400) as u64;
    (y, m, d, rest / 3600, rest % 3600 / 60, rest % 60)
}

/// `2026-11-20T09:05:00Z`, for the `<time>` element's `datetime`.
pub fn iso_utc(t: SystemTime) -> String {
    let (y, mo, d, h, mi, s) = utc_parts(t);
    format!("{y:04}-{mo:02}-{d:02}T{h:02}:{mi:02}:{s:02}Z")
}

/// `2026-11-20 09:05:00 UTC`, what the page shows.
pub fn show_utc(t: SystemTime) -> String {
    let (y, mo, d, h, mi, s) = utc_parts(t);
    format!("{y:04}-{mo:02}-{d:02} {h:02}:{mi:02}:{s:02} UTC")
}

/// A time as a `<time>` element: UTC, because a page with no JavaScript does
/// not know the viewer's zone. The `datetime` lets the browser (or an
/// extension) show it locally.
fn time_tag(t: SystemTime) -> String {
    format!("<time datetime=\"{}\">{}</time>", iso_utc(t), show_utc(t))
}

/// How long a call took, as a person would say it.
pub fn took(ms: Option<u32>) -> String {
    match ms {
        None => "not recorded".into(),
        Some(ms) if ms < 1000 => format!("{ms} ms"),
        Some(ms) if ms < 60_000 => format!("{:.1} s", f64::from(ms) / 1000.0),
        Some(ms) => format!("{} min {} s", ms / 60_000, ms % 60_000 / 1000),
    }
}

// -------------------------------------------------------------------- views

/// What the pages know about one computer.
pub struct DeviceView {
    pub id: String,
    pub name: String,
    pub online: bool,
    pub last_seen: Option<SystemTime>,
    /// The address to give an AI app.
    pub mcp_url: String,
    /// The address for Gemini, which signs in with the relay and needs no
    /// client id or secret. Only when app sign-in is on.
    pub app_mcp_url: Option<String>,
}

/// The address block of a computer's row: one address when app sign-in is off
/// (as it always was), or one for Claude and one for Gemini when it is on.
fn row_addresses(d: &DeviceView) -> String {
    match &d.app_mcp_url {
        None => format!(
            "<p class=\"meta\">Address for your AI app:</p>\
             <p><code class=\"url\">{}</code></p>",
            esc(&d.mcp_url)
        ),
        Some(app) => format!(
            "<p class=\"meta\">For Claude:</p>\
             <p><code class=\"url\">{}</code></p>\
             <p class=\"meta\">For Gemini:</p>\
             <p><code class=\"url\">{}</code></p>",
            esc(&d.mcp_url),
            esc(app)
        ),
    }
}

/// The Gemini steps on a computer's page. Without app sign-in, Gemini is given
/// the same address as Claude and a client id and secret from the person who
/// invited you; with it, one address is all Gemini needs.
fn gemini_steps(d: &DeviceView) -> String {
    match &d.app_mcp_url {
        None => format!(
            "<li>In Gemini, add a custom connector (an MCP server).</li>\
             <li>For the server URL, paste:<br><code class=\"url\">{}</code></li>\
             <li>Gemini also asks for a client ID and secret. Ask the person who invited you \
             for the ones made for Gemini.</li>\
             <li>Sign in with the same account you used here.</li>",
            esc(&d.mcp_url)
        ),
        Some(app) => format!(
            "<li>In Gemini, add a custom connector (an MCP server).</li>\
             <li>For the server URL, paste:<br><code class=\"url\">{}</code></li>\
             <li>Gemini needs only this address. Leave the client ID and secret blank.</li>\
             <li>Sign in with the same account you used here.</li>",
            esc(app)
        ),
    }
}

/// One row of the activity page. Names and times only: the relay keeps no
/// arguments, so there are none to show.
pub struct ActivityView {
    pub at: SystemTime,
    pub computer: String,
    pub app: String,
    pub tool: String,
    pub outcome: String,
    pub duration_ms: Option<u32>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Flash {
    Renamed,
    Removed,
}

impl Flash {
    pub fn from_query(query: Option<&str>) -> Option<Flash> {
        match super::query_param(query, "done").as_deref() {
            Some("renamed") => Some(Flash::Renamed),
            Some("removed") => Some(Flash::Removed),
            _ => None,
        }
    }

    fn text(self) -> &'static str {
        match self {
            Flash::Renamed => "Name saved.",
            Flash::Removed => {
                "That computer was removed. Claude and Gemini can no longer reach it."
            }
        }
    }
}

/// Who is looking and when: the signed-in person's form token (None when
/// signed out) and the time the page is made at.
#[derive(Clone, Copy)]
pub struct Ctx<'a> {
    pub csrf: Option<&'a str>,
    pub now: SystemTime,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Nav {
    None,
    Computers,
    Activity,
}

/// The words for an outcome the relay recorded, and how to colour them.
fn outcome_words(outcome: &str) -> (String, &'static str) {
    let (words, tone) = match outcome {
        "ok" => ("Done", "ok"),
        "tool_error" => ("The tool reported an error", "warn"),
        "rejoined" => ("Joined a request that was already running", "neutral"),
        "waiting_approval" => ("Waiting for you to approve it on your Mac", "warn"),
        "still_working" => ("Still running when it was checked", "neutral"),
        "parked" => ("Still running when the AI app stopped waiting", "neutral"),
        "cancelled" => ("Cancelled by the AI app", "neutral"),
        "rate_limited" => ("Refused: too many requests at once", "warn"),
        "store_unavailable" => ("Not run: the relay could not reach its database", "bad"),
        "offline" => ("Not run: the computer was offline", "bad"),
        "disconnected" => ("Interrupted: the computer disconnected", "bad"),
        "not_received" => ("Not run: the computer did not receive it", "bad"),
        "deadline" => ("Stopped: it took too long", "bad"),
        "duplicate" => ("Refused: the same request was already running", "warn"),
        "revoked" => ("Stopped: the computer was removed", "bad"),
        "unknown_request" => ("Asked about a request the relay did not know", "neutral"),
        other => return (other.to_string(), "neutral"),
    };
    (words.to_string(), tone)
}

// ------------------------------------------------------------------- layout

fn layout(ctx: Ctx<'_>, nav: Nav, title: &str, main: &str) -> String {
    let current = |which: Nav| {
        if nav == which {
            " aria-current=\"page\""
        } else {
            ""
        }
    };
    let header_right = match ctx.csrf {
        Some(csrf) => format!(
            "<nav class=\"nav\" aria-label=\"Main\">\
             <a href=\"/devices\"{}>Computers</a>\
             <a href=\"/activity\"{}>Activity</a></nav>\
             <form class=\"signout\" method=\"post\" action=\"/auth/logout\">\
             <input type=\"hidden\" name=\"csrf\" value=\"{}\">\
             <button class=\"link\" type=\"submit\">Sign out</button></form>",
            current(Nav::Computers),
            current(Nav::Activity),
            esc(csrf)
        ),
        None => String::new(),
    };
    format!(
        "<!doctype html>\n<html lang=\"en\">\n<head>\n\
         <meta charset=\"utf-8\">\n\
         <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n\
         <meta name=\"color-scheme\" content=\"light dark\">\n\
         <title>{} - Vitruvian Relay</title>\n\
         <link rel=\"stylesheet\" href=\"/static/relay.css\">\n\
         </head>\n<body>\n\
         <header class=\"top\"><div class=\"bar\">\
         <a class=\"brand\" href=\"/\">Vitruvian Relay</a>{header_right}</div></header>\n\
         <main>\n{main}\n</main>\n\
         <footer><p>Vitruvian Relay keeps which tool ran, when, how long it took and \
         whether it worked, for {ACTIVITY_RETENTION_DAYS} days. It never keeps what your AI app asked \
         for or what came back.</p></footer>\n\
         </body>\n</html>\n",
        esc(title)
    )
}

fn flash_html(flash: Option<Flash>) -> String {
    flash
        .map(|f| format!("<p class=\"note ok\" role=\"status\">{}</p>", f.text()))
        .unwrap_or_default()
}

fn badge(online: bool) -> &'static str {
    if online {
        "<span class=\"badge ok\">Online</span>"
    } else {
        "<span class=\"badge off\">Offline</span>"
    }
}

fn seen_html(d: &DeviceView, now: SystemTime) -> String {
    if d.online {
        return "Connected now.".into();
    }
    match d.last_seen {
        Some(at) => format!("Last seen {} ({}).", esc(&ago(Some(at), now)), time_tag(at)),
        None => "This computer has not connected yet.".into(),
    }
}

// -------------------------------------------------------------------- pages

/// The front page for someone who is not signed in. Just after signing out,
/// the way to end the account sign-in too comes first: the relay's own
/// session is over, but the identity service would sign the next person at
/// this browser straight back in.
pub fn sign_in_page(ctx: Ctx<'_>, signed_out: bool, end_session_url: &str) -> String {
    let main = if signed_out {
        format!(
            "<section class=\"hero\">\
             <h1>You are signed out of Vitruvian Relay</h1>\
             <p class=\"lead\">That ended your session here. It does not sign you out of your \
             account itself, so the next person to open this page on this browser could still \
             sign in as you. On a shared computer, end your account sign-in too.</p>\
             <p><a class=\"button\" href=\"{}\">Also sign out of my account</a></p>\
             <p class=\"meta\">Or <a href=\"/auth/login\">sign in again</a>.</p>\
             </section>",
            esc(end_session_url)
        )
    } else {
        "<section class=\"hero\">\
         <h1>Use your AI app on your own Mac</h1>\
         <p class=\"lead\">Vitruvian Relay lets Claude or Gemini reach your Mac from anywhere, \
         including your phone. For anything beyond reading files, your Mac asks you first.</p>\
         <p><a class=\"button\" href=\"/auth/login\">Sign in</a></p>\
         <p class=\"meta\">Vitruvian Relay is by invitation. Sign in with the account you were \
         invited with. If it does not work, ask the person who invited you.</p>\
         </section>"
            .to_string()
    };
    layout(
        ctx,
        Nav::None,
        if signed_out { "Signed out" } else { "Sign in" },
        &main,
    )
}

/// The page frame (header, stylesheet, footer) around `main`, for a page
/// that is not part of a dashboard session: no navigation and no sign-out
/// button. `main` must already be escaped.
pub(crate) fn page_shell(title: &str, main: &str) -> String {
    layout(
        Ctx {
            csrf: None,
            now: UNIX_EPOCH,
        },
        Nav::None,
        title,
        main,
    )
}

/// A page that only says something: an error, or a dead end, with a way on.
pub fn message_page(ctx: Ctx<'_>, title: &str, text: &str, link: (&str, &str)) -> String {
    let main = format!(
        "<section class=\"message\"><h1>{}</h1><p class=\"lead\">{}</p>\
         <p><a class=\"button\" href=\"{}\">{}</a></p></section>",
        esc(title),
        esc(text),
        esc(link.0),
        esc(link.1)
    );
    layout(ctx, Nav::None, title, &main)
}

pub fn devices_page(ctx: Ctx<'_>, devices: &[DeviceView], flash: Option<Flash>) -> String {
    let body = if devices.is_empty() {
        "<div class=\"empty\"><p><strong>No computers yet.</strong></p>\
         <p>To add one, install the Vitruvian Relay connector on your Mac and run \
         <code>vrelay login</code> there. It signs you in and adds the Mac to this list. \
         Then reload this page.</p></div>"
            .to_string()
    } else {
        let cards: String = devices
            .iter()
            .map(|d| {
                let id = esc(&d.id);
                format!(
                    "<li class=\"card\">\
                     <div class=\"card-head\"><a class=\"name\" href=\"/devices/{id}\">{}</a>{}</div>\
                     <p class=\"meta\">{}</p>\
                     {}\
                     <p class=\"actions\"><a href=\"/devices/{id}\">Set up and manage</a>\
                     <a href=\"/activity?device={id}\">See its activity</a></p></li>",
                    esc(&d.name),
                    badge(d.online),
                    seen_html(d, ctx.now),
                    row_addresses(d),
                )
            })
            .collect();
        format!("<ul class=\"cards\">{cards}</ul>")
    };
    let main = format!(
        "<h1>Your computers</h1>{}\
         <p class=\"lead\">These Macs are connected to your Vitruvian Relay account. \
         Choose one to add it to Claude or Gemini.</p>{body}",
        flash_html(flash)
    );
    layout(ctx, Nav::Computers, "Your computers", &main)
}

/// One computer: how to add it to an AI app, and how to rename or remove it.
/// `error` is shown above the rename box when a name was refused.
pub fn device_page(
    ctx: Ctx<'_>,
    d: &DeviceView,
    claude_client_id: &str,
    flash: Option<Flash>,
    error: Option<&str>,
) -> String {
    let (id, name, url) = (esc(&d.id), esc(&d.name), esc(&d.mcp_url));
    let csrf = esc(ctx.csrf.unwrap_or(""));
    let error = error
        .map(|e| format!("<p class=\"note bad\" role=\"alert\">{}</p>", esc(e)))
        .unwrap_or_default();
    let main = format!(
        "<p class=\"crumb\"><a href=\"/devices\">Back to your computers</a></p>\
         <h1>{name} {}</h1>{}\
         <p class=\"meta\">{}</p>\
         <section><h2>Add it to Claude</h2><ol class=\"steps\">\
         <li>In Claude, open <strong>Settings</strong>, then <strong>Connectors</strong>, \
         then <strong>Add custom connector</strong>.</li>\
         <li>Give it any name, such as <em>{name}</em>.</li>\
         <li>For the server URL, paste:<br><code class=\"url\">{url}</code></li>\
         <li>Open <strong>Advanced settings</strong> and set the OAuth client ID to \
         <code>{}</code>. Leave the secret empty.</li>\
         <li>Choose <strong>Add</strong>, then <strong>Connect</strong>, and sign in with \
         the same account you used here.</li></ol></section>\
         <section><h2>Add it to Gemini</h2><ol class=\"steps\">{gemini}</ol></section>\
         <section><h2>Rename</h2>{error}\
         <form method=\"post\" action=\"/devices/{id}/rename\" class=\"inline\">\
         <input type=\"hidden\" name=\"csrf\" value=\"{csrf}\">\
         <label for=\"name\">Name (1 to {DEVICE_NAME_MAX} characters)</label>\
         <div class=\"row\"><input id=\"name\" name=\"name\" type=\"text\" value=\"{name}\" \
         maxlength=\"{DEVICE_NAME_MAX}\" required autocomplete=\"off\">\
         <button type=\"submit\">Save name</button></div></form></section>\
         <section><h2>Activity</h2>\
         <p><a href=\"/activity?device={id}\">See what your AI apps did on this computer</a></p></section>\
         <section><h2>Remove</h2>\
         <details class=\"danger\"><summary>Remove this computer</summary>\
         <p>Claude and Gemini stop being able to reach <strong>{name}</strong> straight away, \
         and any call still running fails. To connect it again later, run \
         <code>vrelay login</code> on that Mac.</p>\
         <form method=\"post\" action=\"/devices/{id}/remove\">\
         <input type=\"hidden\" name=\"csrf\" value=\"{csrf}\">\
         <button class=\"danger\" type=\"submit\">Yes, remove {name}</button></form>\
         </details></section>",
        badge(d.online),
        flash_html(flash),
        seen_html(d, ctx.now),
        esc(claude_client_id),
        gemini = gemini_steps(d),
    );
    layout(ctx, Nav::Computers, &d.name, &main)
}

/// What your AI apps did. `filter` is the one computer being looked at, or
/// `None` for all of them; `devices` are the person's computers, to switch
/// between them.
pub fn activity_page(
    ctx: Ctx<'_>,
    filter: Option<&DeviceView>,
    devices: &[DeviceView],
    rows: &[ActivityView],
) -> String {
    let switch = if devices.len() > 1 || filter.is_some() {
        let mut links = format!(
            "<a href=\"/activity\"{}>All computers</a>",
            if filter.is_none() {
                " aria-current=\"true\""
            } else {
                ""
            }
        );
        for d in devices {
            let on = filter.is_some_and(|f| f.id == d.id);
            links.push_str(&format!(
                "<a href=\"/activity?device={}\"{}>{}</a>",
                esc(&d.id),
                if on { " aria-current=\"true\"" } else { "" },
                esc(&d.name)
            ));
        }
        format!("<p class=\"filter\" aria-label=\"Show activity for\">{links}</p>")
    } else {
        String::new()
    };
    let body = if rows.is_empty() {
        "<div class=\"empty\"><p><strong>Nothing yet.</strong></p>\
         <p>When an AI app uses one of your computers, each call shows up here.</p></div>"
            .to_string()
    } else {
        let trs: String = rows
            .iter()
            .map(|r| {
                let (words, tone) = outcome_words(&r.outcome);
                format!(
                    "<tr><td data-label=\"When\">{}</td><td data-label=\"Computer\">{}</td>\
                     <td data-label=\"AI app\">{}</td><td data-label=\"Tool\"><code>{}</code></td>\
                     <td data-label=\"Result\"><span class=\"badge {tone}\">{}</span></td>\
                     <td data-label=\"Took\">{}</td></tr>",
                    time_tag(r.at),
                    esc(&r.computer),
                    esc(&r.app),
                    esc(&r.tool),
                    esc(&words),
                    esc(&took(r.duration_ms)),
                )
            })
            .collect();
        let more = if rows.len() >= ACTIVITY_PAGE as usize {
            format!(
                "<p class=\"meta\">Showing the most recent {ACTIVITY_PAGE} calls. \
                 Older ones are not shown here, and calls are kept for {ACTIVITY_RETENTION_DAYS} days.</p>"
            )
        } else {
            String::new()
        };
        format!(
            "<table class=\"activity\"><thead><tr><th>When</th><th>Computer</th>\
             <th>AI app</th><th>Tool</th><th>Result</th><th>Took</th></tr></thead>\
             <tbody>{trs}</tbody></table>{more}"
        )
    };
    let heading = match filter {
        Some(d) => format!("Activity on {}", esc(&d.name)),
        None => "Activity".to_string(),
    };
    let main = format!(
        "<h1>{heading}</h1>\
         <p class=\"lead\">What your AI apps asked your computers to do. Times are in UTC. \
         This page shows which tool ran, never what it was asked to do.</p>{switch}{body}"
    );
    layout(ctx, Nav::Activity, "Activity", &main)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    fn at_secs(secs: u64) -> SystemTime {
        UNIX_EPOCH + Duration::from_secs(secs)
    }

    #[test]
    fn escaping_covers_every_character_that_can_break_out() {
        assert_eq!(
            esc(r#"<script>alert("x" & 'y')</script>"#),
            "&lt;script&gt;alert(&quot;x&quot; &amp; &#39;y&#39;)&lt;/script&gt;"
        );
        assert_eq!(esc("plain é text"), "plain é text");
    }

    #[test]
    fn times_are_utc_and_exact() {
        assert_eq!(iso_utc(UNIX_EPOCH), "1970-01-01T00:00:00Z");
        assert_eq!(iso_utc(at_secs(1_795_161_907)), "2026-11-20T08:05:07Z");
        // Leap days.
        assert_eq!(iso_utc(at_secs(1_709_164_800)), "2024-02-29T00:00:00Z");
        assert_eq!(show_utc(at_secs(951_782_400)), "2000-02-29 00:00:00 UTC");
        assert_eq!(
            time_tag(UNIX_EPOCH),
            "<time datetime=\"1970-01-01T00:00:00Z\">1970-01-01 00:00:00 UTC</time>"
        );
    }

    #[test]
    fn durations_read_like_a_person_would_say_them() {
        assert_eq!(took(None), "not recorded");
        assert_eq!(took(Some(40)), "40 ms");
        assert_eq!(took(Some(1500)), "1.5 s");
        assert_eq!(took(Some(125_000)), "2 min 5 s");
    }

    #[test]
    fn every_outcome_the_relay_records_has_plain_words() {
        for o in [
            "ok",
            "tool_error",
            "rejoined",
            "waiting_approval",
            "still_working",
            "parked",
            "cancelled",
            "rate_limited",
            "store_unavailable",
            "offline",
            "disconnected",
            "not_received",
            "deadline",
            "duplicate",
            "revoked",
            "unknown_request",
        ] {
            let (words, _) = outcome_words(o);
            assert_ne!(words, o, "{o} needs words");
        }
        assert_eq!(outcome_words("something_new").0, "something_new");
    }
}
