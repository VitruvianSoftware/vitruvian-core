# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Candidate smoke for oauth-user-inspector: reachable AND the React SPA actually
# mounts. index.html is a static shell that 200s even when the bundle throws on
# mount (how the 2026-06-27 react/react-dom mismatch reached prod past an
# HTTP-200-only check), so a plain curl is not enough. $CAND is the candidate
# revision's dedicated URL, exported by //tools/deploy:cloud-run.
#
# Single source of truth for the oauth smoke: BOTH the local `:deploy` target
# (BUILD custom_smoke_script_file) and CI (oauth-user-inspector-deploy.yaml's
# custom-smoke-script-file) read this exact file, so they can't drift.
echo "Smoke-checking ${CAND}/"
curl --fail --retry 10 --retry-delay 5 --retry-connrefused "${CAND}/" >/dev/null
CHROME="$(command -v google-chrome-stable || command -v google-chrome || command -v chromium-browser || true)"
if [ -z "$CHROME" ]; then
	echo "::error::no headless Chrome available -- cannot verify the app mounts"
	exit 1
fi
DOM="$("$CHROME" --headless=new --no-sandbox --disable-gpu --virtual-time-budget=10000 --dump-dom "${CAND}/" 2>/dev/null || true)"
if printf '%s' "$DOM" | grep -q "Select a provider"; then
	echo "Smoke OK: React app mounted."
else
	echo "::error::App did NOT mount -- served only the static fallback (broken frontend bundle)."
	printf '%s' "$DOM" | head -c 800
	exit 1
fi
