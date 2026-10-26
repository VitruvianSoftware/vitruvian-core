// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

//! Native Rust implementation of the Space arrangement recovery helpers in
//! `Tools/uninstall.sh` and the full test suite in `Tests/UninstallSpacesTests.sh`.

pub struct ProbeEnv {
    pub probe_xml: String,
    pub probe_status: i32,
    pub probe_pid: String,
    pub probe_pid_status: i32,
    pub recovery_xml: String,
}

impl Default for ProbeEnv {
    fn default() -> Self {
        Self {
            probe_xml:
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict/></plist>"
                    .to_string(),
            probe_status: 0,
            probe_pid: "500".to_string(),
            probe_pid_status: 0,
            recovery_xml: String::new(),
        }
    }
}

impl ProbeEnv {
    pub fn defaults_export(&self, domain: &str) -> Result<String, i32> {
        if domain == "example" && !self.recovery_xml.is_empty() {
            return Ok(self.recovery_xml.clone());
        }
        if self.probe_status == 0 {
            Ok(self.probe_xml.clone())
        } else {
            Err(self.probe_status)
        }
    }

    pub fn pgrep_dock(&self) -> (i32, String) {
        (self.probe_pid_status, self.probe_pid.clone())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PlistValue {
    String(String),
    Integer(String),
    Bool(bool),
    Data(String),
    Other,
}

fn is_valid_plist_xml(xml: &str) -> bool {
    let trimmed = xml.trim();
    trimmed.contains("<plist")
        && trimmed.ends_with("</plist>")
        && (trimmed.contains("<dict/>")
            || (trimmed.contains("<dict>") && trimmed.contains("</dict>")))
}

fn lookup_plist_key(xml: &str, key: &str) -> Result<Option<PlistValue>, ()> {
    if !is_valid_plist_xml(xml) {
        return Err(());
    }
    let needle = format!("<key>{}</key>", key);
    let Some(idx) = xml.find(&needle) else {
        return Ok(None);
    };
    let rest = xml[idx + needle.len()..].trim_start();
    if rest.starts_with("<true/>") {
        Ok(Some(PlistValue::Bool(true)))
    } else if rest.starts_with("<false/>") {
        Ok(Some(PlistValue::Bool(false)))
    } else if let Some(after) = rest.strip_prefix("<string>") {
        let end = after.find("</string>").ok_or(())?;
        Ok(Some(PlistValue::String(after[..end].to_string())))
    } else if rest.starts_with("<string/>") {
        Ok(Some(PlistValue::String(String::new())))
    } else if let Some(after) = rest.strip_prefix("<integer>") {
        let end = after.find("</integer>").ok_or(())?;
        Ok(Some(PlistValue::Integer(after[..end].trim().to_string())))
    } else if let Some(after) = rest.strip_prefix("<data>") {
        let end = after.find("</data>").ok_or(())?;
        Ok(Some(PlistValue::Data(after[..end].trim().to_string())))
    } else {
        Ok(Some(PlistValue::Other))
    }
}

pub fn spaces_read_domain(env: &ProbeEnv, domain: &str) -> Result<String, ()> {
    let snapshot = env.defaults_export(domain).map_err(|_| ())?;
    if !is_valid_plist_xml(&snapshot) {
        return Err(());
    }
    Ok(snapshot)
}

pub fn spaces_recovery_value(snapshot: &str, key: &str) -> Result<String, ()> {
    match lookup_plist_key(snapshot, key)? {
        None => Ok(String::new()),
        Some(PlistValue::String(s)) if !s.is_empty() => Ok(s),
        _ => Err(()),
    }
}

pub fn spaces_dock_preference(env: &ProbeEnv) -> String {
    let Ok(snapshot) = spaces_read_domain(env, "com.apple.dock") else {
        return "unknown".to_string();
    };
    match lookup_plist_key(&snapshot, "mru-spaces") {
        Ok(None) => String::new(),
        Ok(Some(PlistValue::Bool(false))) => "0".to_string(),
        Ok(Some(PlistValue::Integer(ref s))) if s == "0" => "0".to_string(),
        Ok(Some(PlistValue::Bool(true))) => "1".to_string(),
        Ok(Some(PlistValue::Integer(ref s))) if s == "1" => "1".to_string(),
        _ => "unknown".to_string(),
    }
}

pub fn spaces_dock_pid(env: &ProbeEnv) -> String {
    let (status, pids) = env.pgrep_dock();
    if status == 0 {
        let first = pids.lines().next().unwrap_or("").trim();
        if !first.is_empty() {
            first.to_string()
        } else {
            "unknown".to_string()
        }
    } else if status == 1 {
        String::new()
    } else {
        "unknown".to_string()
    }
}

pub fn spaces_leftover(owed: &str, journal: &str, preference: &str, dock_pid: &str) -> String {
    if (owed.is_empty() || owed == "off") && journal.is_empty() {
        return String::new();
    }
    match owed {
        "" | "absent" | "on" | "off" => {}
        _ => return "unknown".to_string(),
    }
    if preference == "unknown" || (!journal.is_empty() && dock_pid == "unknown") {
        return "unknown".to_string();
    }

    let mut journal_pid = "";
    let mut journal_runs = "";
    let mut journal_wrote: Vec<&str> = Vec::new();

    if !journal.is_empty() {
        let mut parts = journal.split_whitespace();
        journal_pid = parts.next().unwrap_or("");
        journal_runs = parts.next().unwrap_or("");
        journal_wrote = parts.collect();

        let pid_is_numeric =
            !journal_pid.is_empty() && journal_pid.bytes().all(|b| b.is_ascii_digit());
        let runs_valid = journal_runs == "fixed" || journal_runs == "rearranging";
        if !pid_is_numeric || !runs_valid || journal_wrote.is_empty() {
            return "unknown".to_string();
        }
        for &written in &journal_wrote {
            match written {
                "absent" | "on" | "off" => {}
                _ => return "unknown".to_string(),
            }
        }
    }

    let reads = match preference {
        "0" => "off",
        "1" => "on",
        "" => "absent",
        _ => return "unknown".to_string(),
    };

    if !owed.is_empty() && owed != "off" && preference == "0" {
        "stuck".to_string()
    } else if journal_runs == "fixed"
        && preference != "0"
        && !dock_pid.is_empty()
        && journal_pid == dock_pid
        && journal_wrote.contains(&reads)
    {
        "unloaded".to_string()
    } else {
        String::new()
    }
}

pub fn spaces_removal_state(env: &ProbeEnv, owed: &str, journal: &str) -> String {
    if (owed.is_empty() || owed == "off") && journal.is_empty() {
        return String::new();
    }
    let pref = spaces_dock_preference(env);
    let pid = spaces_dock_pid(env);
    spaces_leftover(owed, journal, &pref, &pid)
}

pub fn preflight_guard(env: &ProbeEnv, bundle: &str, ran_app: bool) -> Result<(), String> {
    let snapshot = spaces_read_domain(env, bundle)
        .map_err(|_| "Could not read Space arrangement recovery.".to_string())?;
    let owed = spaces_recovery_value(&snapshot, "spacesOrderRestore")
        .map_err(|_| "Could not read spacesOrderRestore.".to_string())?;
    let journal = spaces_recovery_value(&snapshot, "spacesOrderRestartPending")
        .map_err(|_| "Could not read spacesOrderRestartPending.".to_string())?;

    let state = spaces_removal_state(env, &owed, &journal);
    if !state.is_empty() && ran_app {
        return Err(state);
    }
    Ok(())
}

/// Runs the full `Tests/UninstallSpacesTests.sh` suite.
pub fn run_uninstall_spaces_test_suite() -> Result<(), String> {
    let mut failures = Vec::new();
    let mut expect = |wanted: &str, owed: &str, journal: &str, preference: &str, dock_pid: &str| {
        let found = spaces_leftover(owed, journal, preference, dock_pid);
        if found != wanted {
            failures.push(format!(
                "spaces_leftover '{}' '{}' '{}' '{}': wanted '{}', found '{}'",
                owed, journal, preference, dock_pid, wanted, found
            ));
        }
    };

    // Settled: nothing owed, or a restore the Dock already reads.
    expect("", "", "", "", "500");
    expect("", "", "", "1", "500");
    expect("", "absent", "", "", "500");
    expect("", "on", "", "1", "500");
    // Rearranging the user turned off themselves is theirs, not a failed restore.
    expect("", "", "", "0", "500");
    // Nor is rearranging that was already off when fixed order turned on.
    expect("", "off", "", "0", "500");
    expect("", "off", "", "1", "500");
    expect("", "off", "", "", "500");
    // A restore that never happened.
    expect("stuck", "absent", "", "0", "500");
    expect("stuck", "on", "500 rearranging off", "0", "500");
    // A restore written back while the same Dock still keeps a fixed order.
    expect("unloaded", "", "500 fixed absent", "", "500");
    expect("unloaded", "", "500 fixed on", "1", "500");
    expect("unloaded", "absent", "500 fixed absent", "", "500");
    expect("unloaded", "", "500 fixed absent off absent", "", "500");
    // A Dock that restarted since, or none running, has read the preference.
    expect("", "", "500 fixed absent", "", "501");
    expect("", "", "500 fixed absent", "", "");
    // A value never written is a later change the Dock applied itself.
    expect("", "", "500 fixed absent", "1", "500");
    // The Dock already runs what an owed restart would load.
    expect("", "", "500 fixed absent off", "0", "500");
    expect("", "", "500 rearranging off absent", "", "500");

    // An unreadable value is never a confirmed absent key while recovery is owed.
    expect("unknown", "on", "", "unknown", "500");
    expect("unknown", "", "500 fixed absent", "unknown", "500");
    expect("unknown", "", "500 fixed on", "1", "unknown");
    expect("unknown", "on", "", "unexpected", "500");
    expect("unknown", "unexpected", "", "1", "500");
    expect("unknown", "", "broken journal", "1", "500");
    expect("unknown", "", "500 fixed unexpected", "1", "500");
    // No recorded debt, including a setting that was already fixed, needs no probe.
    expect("", "", "", "unknown", "unknown");
    expect("", "off", "", "unknown", "unknown");

    let mut env = ProbeEnv::default();

    let expect_probe = |env: &ProbeEnv, wanted: &str, failures: &mut Vec<String>| {
        let found = spaces_dock_preference(env);
        if found != wanted {
            failures.push(format!(
                "spaces_dock_preference wanted '{}', found '{}'",
                wanted, found
            ));
        }
    };
    let expect_state =
        |env: &ProbeEnv, wanted: &str, owed: &str, journal: &str, failures: &mut Vec<String>| {
            let found = spaces_removal_state(env, owed, journal);
            if found != wanted {
                failures.push(format!(
                    "spaces_removal_state wanted '{}', found '{}'",
                    wanted, found
                ));
            }
        };

    expect_probe(&env, "", &mut failures);
    expect_state(&env, "", "on", "", &mut failures);

    env.probe_status = 1;
    expect_probe(&env, "unknown", &mut failures);
    expect_state(&env, "unknown", "on", "", &mut failures);
    expect_state(&env, "", "", "", &mut failures);
    expect_state(&env, "", "off", "", &mut failures);

    if spaces_read_domain(&env, "example").is_ok() {
        failures.push("a failed app-domain read must stop before recovery is removed".to_string());
    }

    env.probe_status = 0;
    env.probe_xml = "unreadable plist".to_string();
    expect_probe(&env, "unknown", &mut failures);

    env.probe_xml =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>mru-spaces</key><false/></dict></plist>"
            .to_string();
    expect_probe(&env, "0", &mut failures);
    expect_state(&env, "stuck", "on", "", &mut failures);
    expect_state(&env, "", "off", "", &mut failures);

    env.probe_xml =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>mru-spaces</key><true/></dict></plist>"
            .to_string();
    expect_probe(&env, "1", &mut failures);
    expect_state(&env, "", "on", "", &mut failures);
    expect_state(&env, "unloaded", "", "500 fixed on", &mut failures);

    env.probe_pid_status = 2;
    expect_state(&env, "unknown", "", "500 fixed on", &mut failures);
    env.probe_pid_status = 1;
    expect_state(&env, "", "", "500 fixed on", &mut failures);
    env.probe_pid_status = 0;

    env.probe_xml =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>mru-spaces</key><integer>0</integer></dict></plist>"
            .to_string();
    expect_probe(&env, "0", &mut failures);

    env.probe_xml =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>mru-spaces</key><integer>1</integer></dict></plist>"
            .to_string();
    expect_probe(&env, "1", &mut failures);

    env.probe_xml =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>mru-spaces</key><string>0</string></dict></plist>"
            .to_string();
    expect_probe(&env, "unknown", &mut failures);

    // A valid domain may contain unrelated data values that JSON cannot represent.
    env.probe_xml =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>unrelated</key><data>AA==</data></dict></plist>"
            .to_string();
    let snapshot = spaces_read_domain(&env, "example")
        .map_err(|_| "failed to read domain with data".to_string())?;
    if spaces_recovery_value(&snapshot, "spacesOrderRestore") != Ok(String::new()) {
        failures.push("expected empty spacesOrderRestore on unrelated data plist".to_string());
    }

    env.probe_xml =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>spacesOrderRestore</key><string>on</string><key>spacesOrderRestartPending</key><string>500 fixed on</string></dict></plist>"
            .to_string();
    let snapshot = spaces_read_domain(&env, "example")
        .map_err(|_| "failed to read recovery domain".to_string())?;
    if spaces_recovery_value(&snapshot, "spacesOrderRestore").as_deref() != Ok("on") {
        failures.push("expected spacesOrderRestore == 'on'".to_string());
    }
    if spaces_recovery_value(&snapshot, "spacesOrderRestartPending").as_deref()
        != Ok("500 fixed on")
    {
        failures.push("expected spacesOrderRestartPending == '500 fixed on'".to_string());
    }

    env.probe_xml =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>spacesOrderRestore</key><array/></dict></plist>"
            .to_string();
    let snapshot = spaces_read_domain(&env, "example")
        .map_err(|_| "failed to read array domain".to_string())?;
    if spaces_recovery_value(&snapshot, "spacesOrderRestore").is_ok() {
        failures.push(
            "an unreadable recovery value must stop before preferences are removed".to_string(),
        );
    }

    // Run preflight guard checks:
    let bundle = "example";
    env.recovery_xml =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>spacesOrderRestore</key><string>on</string></dict></plist>"
            .to_string();
    env.probe_status = 1;
    if preflight_guard(&env, bundle, true).is_ok() {
        failures
            .push("unknown restoration must exit before resets or preference deletion".to_string());
    }

    env.probe_status = 0;
    env.probe_xml =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>mru-spaces</key><false/></dict></plist>"
            .to_string();
    if preflight_guard(&env, bundle, true).is_ok() {
        failures
            .push("a failed restore must keep its recovery rather than remove the app".to_string());
    }

    // An app trashed by hand never ran, so keeping its preferences fixes nothing.
    if preflight_guard(&env, bundle, false).is_err() {
        failures.push(
            "an app already removed by hand must not block the rest of the removal".to_string(),
        );
    }

    env.recovery_xml =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>spacesOrderRestore</key><string>off</string></dict></plist>"
            .to_string();
    env.probe_status = 1;
    if preflight_guard(&env, bundle, true).is_err() {
        failures.push(
            "an original fixed order without restart debt must not block removal".to_string(),
        );
    }

    env.recovery_xml =
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict/></plist>"
            .to_string();
    if preflight_guard(&env, bundle, true).is_err() {
        failures.push("no recorded recovery must not block removal".to_string());
    }

    if !failures.is_empty() {
        return Err(failures.join("\n"));
    }
    Ok(())
}

pub fn run_cli(_args: &[String]) -> i32 {
    match run_uninstall_spaces_test_suite() {
        Ok(()) => {
            println!("UNINSTALL SPACES TESTS OK");
            0
        }
        Err(e) => {
            eprintln!("{}", e);
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_uninstall_spaces_suite() {
        run_uninstall_spaces_test_suite().unwrap();
    }
}
