// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

//! Decides whether a beta publish may go ahead, from how the commit being
//! published relates to the commit the rolling tag already points at, and
//! never touches the network.
//!
//! The status is `status` from GitHub's compare API for
//! `<tag commit>...<this commit>`, or `absent` when the tag does not exist
//! yet:
//!
//! | status                     | decision | why                                        |
//! |----------------------------|----------|--------------------------------------------|
//! | `absent`, `ahead`, `identical` | publish | nothing newer is on the release; a re-run of the same commit is fine |
//! | `behind`                   | skip     | the release already holds a newer build; uploading would put an older DMG over it |
//! | anything else              | refuse   | diverged cannot happen on main, and an answer we do not know is not a yes |
//!
//! Two beta jobs for two pushes can run out of order (one concurrency group
//! queues them, and does not order them by commit). The older one used to
//! upload its DMGs over the newer one's and then fail moving the tag
//! backwards.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Decision {
    Publish,
    Skip,
    Refuse,
}

impl Decision {
    pub fn word(self) -> &'static str {
        match self {
            Decision::Publish => "publish",
            Decision::Skip => "skip",
            Decision::Refuse => "refuse",
        }
    }
}

pub fn decide(status: &str) -> Decision {
    match status {
        "absent" | "ahead" | "identical" => Decision::Publish,
        "behind" => Decision::Skip,
        _ => Decision::Refuse,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_status_has_its_decision() {
        for (status, word) in [
            ("absent", "publish"),
            ("ahead", "publish"),
            ("identical", "publish"),
            ("behind", "skip"),
            ("diverged", "refuse"),
            ("", "refuse"),
            ("Ahead", "refuse"),
            (" ahead", "refuse"),
        ] {
            assert_eq!(decide(status).word(), word, "status {:?}", status);
        }
    }
}
