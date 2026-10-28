"""Failure and retry checks for the queue API."""

import json
import time
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8099/v1"


def call(method, path, body=None, token=None, headers=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req) as res:
            return res.status, json.loads(res.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


ok = fail = 0


def check(name, condition, detail=""):
    global ok, fail
    if condition:
        ok += 1
        print(f"  PASS  {name}")
    else:
        fail += 1
        print(f"  FAIL  {name}  {detail}")


def main():
    _, tok = call("POST", "/auth/login",
                  {"email": "demo@dubber.app", "password": "password123"})
    token = tok["access_token"]

    def upload(name):
        _, b = call("POST", "/uploads", {"file_name": name, "size": 10}, token)
        call("POST", f"/uploads/{b['id']}/complete", {}, token)
        return b["id"]

    def item(name):
        return {"file_name": name, "upload_id": upload(name),
                "source_language": "en", "target_language": "km"}

    def clear():
        _, q = call("GET", "/queue", token=token)
        for p in ([q["now_dubbing"]] if q["now_dubbing"] else []) + q["up_next"] + q["failed"]:
            call("DELETE", f"/queue/items/{p['id']}", token=token)

    print("== A failed job leaves the first place and keeps its place in Failed ==")
    clear()
    _, credits = call("GET", "/credits", token=token)
    before = credits["balance"]
    status, add = call("POST", "/queue/items",
                       {"items": [item("Doomed.mp4")]}, token,
                       {"X-Fail-Next": "1"})
    check("add succeeds", status == 200, add)

    deadline = time.time() + 40
    failed = None
    while time.time() < deadline:
        time.sleep(2)
        _, q = call("GET", "/queue", token=token)
        if q["failed"]:
            failed = q["failed"][0]
            break
    check("the job ends up in Failed", failed is not None)
    if failed:
        check("with a reason", failed.get("reason") == "unsupported_file", failed.get("reason"))
        check("and no reserved credits", failed.get("credits") == 0, failed.get("credits"))
        _, q = call("GET", "/queue", token=token)
        check("it is not Now dubbing", q["now_dubbing"] is None, q["now_dubbing"])
        check("it is not in Up next", q["up_next"] == [], q["up_next"])

    _, c = call("GET", "/credits", token=token)
    check("credits were returned", c["balance"] == before, (before, c["balance"]))

    print("== One failure does not stop the next video ==")
    clear()
    call("POST", "/queue/items",
         {"items": [item("Fails.mp4"), item("Runs.mp4")]}, token,
         {"X-Fail-Next": "1"})
    deadline = time.time() + 40
    saw_failed = False
    while time.time() < deadline:
        time.sleep(2)
        _, q = call("GET", "/queue", token=token)
        if q["failed"]:
            saw_failed = True
        if q["now_dubbing"] and q["now_dubbing"]["title"] == "Runs.mp4":
            break
    check("the second video starts after the first fails", saw_failed and
          q["now_dubbing"] is not None, q["now_dubbing"])

    print("== Retry starts the failed job again ==")
    clear()
    call("POST", "/queue/items", {"items": [item("Retry.mp4")]}, token,
         {"X-Fail-Next": "1"})
    deadline = time.time() + 40
    failed_id = None
    while time.time() < deadline:
        time.sleep(2)
        _, q = call("GET", "/queue", token=token)
        if q["failed"]:
            failed_id = q["failed"][0]["id"]
            break
    check("job failed", failed_id is not None)

    if failed_id:
        status, project = call("POST", f"/queue/items/{failed_id}/retry", {}, token)
        check("retry is accepted", status == 200, (status, project))
        _, q = call("GET", "/queue", token=token)
        check("it is back in the queue, not Failed",
              q["failed"] == [], q["failed"])
        check("and is dubbing", q["now_dubbing"] is not None and
              q["now_dubbing"]["id"] == failed_id, q["now_dubbing"])

    print("== Remove returns credits and the next video starts ==")
    clear()
    _, c0 = call("GET", "/credits", token=token)
    call("POST", "/queue/items",
         {"items": [item("First.mp4"), item("Second.mp4")]}, token)
    _, q = call("GET", "/queue", token=token)
    first_id = q["now_dubbing"]["id"]
    _, c1 = call("GET", "/credits", token=token)
    status, _ = call("DELETE", f"/queue/items/{first_id}", token=token)
    check("remove is accepted", status == 200)
    _, c2 = call("GET", "/credits", token=token)
    check("its credits come back", c2["balance"] == c1["balance"] + 12,
          (c1["balance"], c2["balance"]))
    _, q = call("GET", "/queue", token=token)
    check("the next video is dubbing",
          q["now_dubbing"] is not None and q["now_dubbing"]["title"] == "Second.mp4",
          q["now_dubbing"])

    clear()
    print(f"\n{ok} passed, {fail} failed")
    return fail


if __name__ == "__main__":
    raise SystemExit(1 if main() else 0)
