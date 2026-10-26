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

fn main() {
    gods_eye_view_e2e::runner::run_single_tier(
        3,
        "Combination Tests",
        gods_eye_view_e2e::tier3::run,
    );
}

#[cfg(test)]
mod tests {
    #[test]
    fn tier3_combination_suite() {
        let mut ctx = gods_eye_view_e2e::runner::TestContext::new(
            gods_eye_view_e2e::runner::find_repo_root(),
            false,
        );
        gods_eye_view_e2e::tier3::run(&mut ctx);
        assert_eq!(ctx.results.len(), 20);
        let failed: Vec<_> = ctx
            .results
            .iter()
            .filter(|r| r.status == gods_eye_view_e2e::runner::TestStatus::Fail)
            .collect();
        assert!(failed.is_empty(), "Tier 3 failures: {:?}", failed);
    }
}
