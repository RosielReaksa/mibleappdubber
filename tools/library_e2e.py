#!/usr/bin/env python3
"""E2E test for Dubber Library endpoints: Logos, Styles, and Presets."""

import json
import subprocess
import sys
import time
import urllib.request
import urllib.error

BASE = "http://127.0.0.1:8097/v1"

def req(method: str, path: str, token: str | None = None, body: dict | None = None):
    url = BASE + path
    data = json.dumps(body).encode("utf-8") if body is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request) as resp:
            content = resp.read()
            return resp.status, json.loads(content.decode("utf-8")) if content else {}
    except urllib.error.HTTPError as e:
        content = e.read()
        return e.code, json.loads(content.decode("utf-8")) if content else {}

def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    print("Testing Dubber Library endpoints...")
    # 1. Login
    code, res = req("POST", "/auth/login", body={"email": "demo@dubber.app", "password": "password123"})
    assert code == 200, f"Login failed: {code} {res}"
    token = res["access_token"]
    print("[PASS] Auth login succeeded")

    # 2. Logos
    code, logos = req("GET", "/assets/logos", token=token)
    assert code == 200 and isinstance(logos, list), f"GET logos failed: {code} {logos}"
    print(f"[PASS] GET /assets/logos returned {len(logos)} items")

    code, new_logo = req("POST", "/assets/logos", token=token, body={"name": "Test Brand", "url": "/media/test.png"})
    assert code == 201 and new_logo["name"] == "Test Brand", f"POST logo failed: {code} {new_logo}"
    logo_id = new_logo["id"]
    print(f"[PASS] POST /assets/logos created {logo_id}")

    code, updated_logo = req("PUT", f"/assets/logos/{logo_id}", token=token, body={"name": "Renamed Brand"})
    assert code == 200 and updated_logo["name"] == "Renamed Brand", f"PUT logo failed: {code} {updated_logo}"
    print("[PASS] PUT /assets/logos/:id updated name")

    code, del_res = req("DELETE", f"/assets/logos/{logo_id}", token=token)
    assert code == 200, f"DELETE logo failed: {code} {del_res}"
    print("[PASS] DELETE /assets/logos/:id succeeded")

    # 3. Styles
    code, styles = req("GET", "/styles", token=token)
    assert code == 200 and isinstance(styles, list), f"GET styles failed: {code} {styles}"
    print(f"[PASS] GET /styles returned {len(styles)} items")

    code, new_style = req("POST", "/styles", token=token, body={
        "name": "Custom Subtitle",
        "kind": "subtitle",
        "size": 50,
        "color": "#00FF00",
        "subtitle_style": "bold"
    })
    assert code == 201 and new_style["name"] == "Custom Subtitle", f"POST style failed: {code} {new_style}"
    style_id = new_style["id"]
    print(f"[PASS] POST /styles created {style_id}")

    code, updated_style = req("PUT", f"/styles/{style_id}", token=token, body={"name": "Updated Subtitle", "size": 65})
    assert code == 200 and updated_style["name"] == "Updated Subtitle" and updated_style["size"] == 65, f"PUT style failed: {code} {updated_style}"
    print("[PASS] PUT /styles/:id updated style")

    code, del_res = req("DELETE", f"/styles/{style_id}", token=token)
    assert code == 200, f"DELETE style failed: {code} {del_res}"
    print("[PASS] DELETE /styles/:id succeeded")

    # 4. Presets
    code, presets = req("GET", "/presets", token=token)
    assert code == 200 and isinstance(presets, list), f"GET presets failed: {code} {presets}"
    print(f"[PASS] GET /presets returned {len(presets)} items")

    code, new_preset = req("POST", "/presets", token=token, body={
        "name": "Action Reel",
        "settings": {
            "format": "portrait",
            "mix": {"dubbed_voice": 100, "original_voice": 20, "music": 80}
        }
    })
    assert code == 201 and new_preset["name"] == "Action Reel", f"POST preset failed: {code} {new_preset}"
    preset_id = new_preset["id"]
    print(f"[PASS] POST /presets created {preset_id}")

    code, updated_preset = req("PUT", f"/presets/{preset_id}", token=token, body={"name": "Action Reel V2"})
    assert code == 200 and updated_preset["name"] == "Action Reel V2", f"PUT preset failed: {code} {updated_preset}"
    print("[PASS] PUT /presets/:id updated preset")

    code, del_res = req("DELETE", f"/presets/{preset_id}", token=token)
    assert code == 200, f"DELETE preset failed: {code} {del_res}"
    print("[PASS] DELETE /presets/:id succeeded")

    print("\nALL LIBRARY E2E TESTS PASSED!")

if __name__ == "__main__":
    main()
