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

"""Robust Fail-Safe HTTP Transport for OpenTelemetry Collector."""

import gzip
import json
import sys
import urllib.error
import urllib.request
from typing import Any, Dict, Optional, Tuple


class TelemetryHttpClient:
    """Fail-safe HTTP Client using urllib.request with strict timeouts."""

    def __init__(
        self,
        base_url: str = "https://otel.lab.ipv1337.dev",
        timeout: float = 2.0,
        user_agent: str = "antigravity-telemetry/1.0.0",
    ):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.user_agent = user_agent

    def resolve_url(self, path_or_url: str) -> str:
        """Resolve full URL from path or existing absolute URL."""
        if path_or_url.startswith(("http://", "https://")):
            return path_or_url
        p = path_or_url.lstrip("/")
        if self.base_url.endswith(p):
            return self.base_url
        return f"{self.base_url}/{p}"

    def post_json(
        self,
        path_or_url: str,
        payload: Dict[str, Any],
        compress: bool = False,
        silent: bool = True,
    ) -> Tuple[bool, int, str]:
        """
        Post JSON payload to OTLP endpoint with fail-safe error isolation.

        Returns:
            (success: bool, status_code: int, response_or_error: str)
        """
        url = self.resolve_url(path_or_url)
        try:
            raw_data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            headers = {
                "Content-Type": "application/json",
                "User-Agent": self.user_agent,
                "Accept": "application/json",
            }
            if compress and len(raw_data) > 1024:
                raw_data = gzip.compress(raw_data)
                headers["Content-Encoding"] = "gzip"

            req = urllib.request.Request(
                url=url,
                data=raw_data,
                headers=headers,
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                status_code = resp.status
                resp_body = resp.read().decode("utf-8", errors="replace")
                return (True, status_code, resp_body)
        except urllib.error.HTTPError as e:
            err_msg = f"HTTP {e.code}: {e.reason}"
            if not silent:
                sys.stderr.write(f"[TelemetryHttpClient] {err_msg}\n")
            return (False, e.code, err_msg)
        except urllib.error.URLError as e:
            err_msg = f"URLError: {e.reason}"
            if not silent:
                sys.stderr.write(f"[TelemetryHttpClient] {err_msg}\n")
            return (False, 0, err_msg)
        except TimeoutError:
            err_msg = f"Timeout ({self.timeout}s) connecting to {url}"
            if not silent:
                sys.stderr.write(f"[TelemetryHttpClient] {err_msg}\n")
            return (False, 0, err_msg)
        except Exception as e:
            err_msg = f"Unexpected error: {type(e).__name__}: {e}"
            if not silent:
                sys.stderr.write(f"[TelemetryHttpClient] {err_msg}\n")
            return (False, 0, err_msg)

    def check_health(self) -> Tuple[bool, str]:
        """Verify endpoint connectivity by sending minimal OTLP probe."""
        probe_payload = {"resourceMetrics": []}
        ok, code, msg = self.post_json("v1/metrics", probe_payload, silent=True)
        if ok or code in (200, 202):
            return (
                True,
                f"OpenTelemetry Collector reachable at {self.base_url} (HTTP {code})",
            )
        return (False, f"OpenTelemetry Collector unreachable at {self.base_url}: {msg}")
