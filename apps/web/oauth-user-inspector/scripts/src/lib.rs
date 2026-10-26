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

pub mod check_sensitive;
pub mod smoke;

#[cfg(test)]
mod tests {
    use super::check_sensitive::is_sensitive;
    use super::smoke::find_chrome_binary;

    #[test]
    fn env_file_at_root() {
        assert!(is_sensitive(".env.local"));
    }

    #[test]
    fn env_file_in_subdir() {
        assert!(is_sensitive("some/path/.env.production"));
    }

    #[test]
    fn bare_env_file() {
        assert!(is_sensitive(".env"));
    }

    #[test]
    fn dist_dir() {
        assert!(is_sensitive("dist/bundle.js"));
    }

    #[test]
    fn dist_server_dir() {
        assert!(is_sensitive("dist-server/index.js"));
    }

    #[test]
    fn dist_at_root() {
        assert!(is_sensitive("dist/"));
    }

    #[test]
    fn nested_dist() {
        assert!(is_sensitive("foo/dist/bar.js"));
    }

    #[test]
    fn safe_file() {
        assert!(!is_sensitive("src/index.ts"));
    }

    #[test]
    fn safe_env_like() {
        assert!(!is_sensitive("environment.ts"));
    }

    #[test]
    fn safe_dist_like() {
        assert!(!is_sensitive("distribute.sh"));
    }

    #[test]
    fn chrome_binary_returns_none_when_missing() {
        let result = find_chrome_binary(|_| false);
        assert!(result.is_none());
    }

    #[test]
    fn chrome_binary_prefers_stable() {
        let result = find_chrome_binary(|name| name == "google-chrome-stable");
        assert_eq!(result, Some("google-chrome-stable".to_string()));
    }

    #[test]
    fn chrome_binary_falls_back_to_chrome() {
        let result = find_chrome_binary(|name| name == "google-chrome");
        assert_eq!(result, Some("google-chrome".to_string()));
    }

    #[test]
    fn chrome_binary_falls_back_to_chromium() {
        let result = find_chrome_binary(|name| name == "chromium-browser");
        assert_eq!(result, Some("chromium-browser".to_string()));
    }
}
