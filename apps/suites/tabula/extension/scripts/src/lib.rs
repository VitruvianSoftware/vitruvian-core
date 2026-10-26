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

pub mod publish_dev_latest;

#[cfg(test)]
mod tests {
    use super::publish_dev_latest::*;

    #[test]
    fn default_tag() {
        assert_eq!(tag_from_env(None), "tabula-extension-dev-latest");
    }

    #[test]
    fn custom_tag() {
        assert_eq!(tag_from_env(Some("custom-tag".to_string())), "custom-tag");
    }

    #[test]
    fn build_info_json_format() {
        let json = build_info_json("abc123", "2026-10-25T12:00:00Z", "9.9.9");
        assert!(json.contains("\"commit\":\"abc123\""));
        assert!(json.contains("\"builtAt\":\"2026-10-25T12:00:00Z\""));
        assert!(json.contains("\"version\":\"9.9.9\""));
        assert!(json.starts_with('{'));
        assert!(json.trim_end().ends_with('}'));
    }

    #[test]
    fn build_info_json_no_trailing_garbage() {
        let json = build_info_json("deadbeef", "2026-01-01T00:00:00Z", "1.0.0");
        let trimmed = json.trim();
        assert_eq!(trimmed.matches('{').count(), 1);
        assert_eq!(trimmed.matches('}').count(), 1);
    }

    #[test]
    fn archive_src_path() {
        assert_eq!(
            chrome_zip_bazel_bin_path(),
            "bazel-bin/apps/suites/tabula/extension/tabula-extension-chrome.zip"
        );
    }

    #[test]
    fn bazel_target_path() {
        assert_eq!(
            chrome_zip_bazel_target(),
            "//apps/suites/tabula/extension:chrome_zip"
        );
    }
}
