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

#[test]
fn test_app_holds_mermaid() {
    let app_name = std::env::var("APP_NAME").unwrap_or_else(|_| "NexusAgent".to_string());
    let archive_paths = std::env::var("ARCHIVE_PATHS").expect("ARCHIVE_PATHS not set");
    let resource_paths = std::env::var("RESOURCE_PATHS").expect("RESOURCE_PATHS not set");
    let mut args = vec!["bazel-app-holds-mermaid".to_string(), app_name];
    args.extend(archive_paths.split_whitespace().map(|s| s.to_string()));
    args.extend(resource_paths.split_whitespace().map(|s| s.to_string()));
    let code = nexus_agent_scripts_lib::bazel_app_holds_mermaid::run(&args);
    assert_eq!(code, 0);
}
