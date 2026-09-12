#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT


def get_app_name(pkg_path):
    parts = pkg_path.strip("/").split("/")
    if len(parts) >= 3 and parts[0] == "apps":
        return f"{parts[1]}/{parts[2]}"
    elif len(parts) >= 2 and parts[0] == "apps":
        return parts[1]
    elif len(parts) > 0 and parts[0]:
        return parts[0]
    return ""


def test_boundaries():
    assert get_app_name("apps/web/gods-eye-view") == "web/gods-eye-view", (
        "failed web app"
    )
    assert get_app_name("apps/services/tabula-api") == "services/tabula-api", (
        "failed service app"
    )
    assert get_app_name("apps/mcp/slack") == "mcp/slack", "failed mcp app"
    assert get_app_name("apps/suites/tabula/web") == "suites/tabula", (
        "failed suite app web"
    )
    assert get_app_name("apps/suites/tabula/api") == "suites/tabula", (
        "failed suite app api"
    )
    assert get_app_name("apps/web/gods-eye-view") != get_app_name(
        "apps/web/analytics"
    ), "firewall collision detected"
