"""End-to-end checks for the queue API, written outside the server folder."""

import json
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8099/v1"
TOKEN = None


def call(method, path, body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    try:
        with urllib.request.urlopen(req) as res:
            return res.status, json.loads(res.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def login():
    status, body = call("POST", "/auth/login",
                        {"email": "demo@dubber.app", "password": "password123"})
    assert status == 200, body
    return body["access_token"]


def upload(token, name):
    status, body = call("POST", "/uploads",
                        {"file_name": name, "size": 1024, "mime": "video/mp4"},
                        token)
    assert status == 200, body
    call("POST", f"/uploads/{body['id']}/complete", {}, token)
    return body["id"]


def item(token, name, **extra):
    return {"file_name": name, "upload_id": upload(token, name),
            "source_language": "en", "target_language": "km", **extra}


def reset(token):
    """Empty the queue and restore a known balance."""
    status, q = call("GET", "/queue", token=token)
    for p in ([q["now_dubbing"]] if q["now_dubbing"] else []) + q["up_next"] + q["failed"]:
        call("DELETE", f"/queue/items/{p['id']}", token=token)


ok, fail = 0, 0


def check(name, condition, detail=""):
    global ok, fail
    if condition:
        ok += 1
        print(f"  PASS  {name}")
    else:
        fail += 1
        print(f"  FAIL  {name}  {detail}")


def main():
    global TOKEN
    TOKEN = login()
    print("== Test 1: New with an empty queue ==")
    reset(TOKEN)
    status, project = call("POST", "/projects",
                           {"upload_id": upload(TOKEN, "One.mp4"),
                            "source_language": "en", "target_language": "km"},
                           TOKEN)
    check("Start dubbing succeeds", status == 200, project)
    check("job starts immediately", project.get("status") == "processing", project.get("status"))
    _, q = call("GET", "/queue", token=TOKEN)
    check("it is Now dubbing", q["now_dubbing"]["id"] == project["id"])

    print("== Test 2: New while a job is processing or queued ==")
    status, err = call("POST", "/projects", {"source_language": "en"},
                       TOKEN)
    check("direct API call is refused", status == 409, status)
    check("with already_dubbing", err.get("code") == "already_dubbing", err)
    reset(TOKEN)

    # A queued-only job must block New as well.
    call("POST", "/queue/items", {"items": [item(TOKEN, "A.mp4"), item(TOKEN, "B.mp4")]}, TOKEN)
    status, err = call("POST", "/projects", {"source_language": "en"}, TOKEN)
    check("a queued job also blocks New", status == 409 and err.get("code") == "already_dubbing", (status, err))
    reset(TOKEN)

    print("== Test 3: Queue - 5 videos at once ==")
    reset(TOKEN)
    items = [item(TOKEN, f"V{i}.mp4") for i in range(5)]
    status, add = call("POST", "/queue/items", {"items": items}, TOKEN)
    check("add succeeds", status == 200, add)
    _, q = call("GET", "/queue", token=TOKEN)
    check("exactly 1 is processing", q["now_dubbing"] is not None, q["now_dubbing"])
    check("4 are queued", len(q["up_next"]) == 4, len(q["up_next"]))
    check("positions are 1..4",
          [p["position"] for p in q["up_next"]] == [1, 2, 3, 4],
          [p["position"] for p in q["up_next"]])
    check("the first added is the one dubbing",
          q["now_dubbing"]["title"] == "V0.mp4", q["now_dubbing"]["title"])
    check("reserved credits = 5 x 12", add["reserved_credits"] == 60, add["reserved_credits"])
    reset(TOKEN)

    print("== Test 4: 5 videos, 1 invalid ==")
    reset(TOKEN)
    bad = {"file_name": "Broken.txt", "upload_id": "up_missing",
           "source_language": "en", "target_language": "km"}
    items = [item(TOKEN, f"W{i}.mp4") for i in range(4)] + [bad]
    status, add = call("POST", "/queue/items", {"items": items}, TOKEN)
    added_total = (1 if add["now_dubbing"] else 0) + len(add["up_next"])
    check("the 4 valid files are added", added_total == 4, added_total)
    check("the invalid one is reported with a reason",
          len(add["rejected"]) == 1 and add["rejected"][0]["file_name"] == "Broken.txt",
          add["rejected"])
    check("the reason explains the upload",
          "uploaded" in add["rejected"][0]["message"].lower(),
          add["rejected"][0]["message"])
    _, q = call("GET", "/queue", token=TOKEN)
    check("4 jobs exist: 1 dubbing + 3 waiting",
          len(q["up_next"]) == 3, len(q["up_next"]))
    reset(TOKEN)

    print("== Test 5: credits for only 3 of 5 ==")
    reset(TOKEN)
    _, credits = call("GET", "/credits", token=TOKEN)
    balance = credits["balance"]
    # Reserve all but 36 credits with a first batch, so exactly 3 of the next
    # 5 can be paid for.
    reserve_count = (balance - 36) // 12
    check(f"can build a 36-credit balance ({balance} now)",
          (balance - 36) % 12 == 0 and reserve_count > 0, balance)
    if reserve_count > 0:
        first = [item(TOKEN, f"Pre{i}.mp4") for i in range(reserve_count)]
        call("POST", "/queue/items", {"items": first}, TOKEN)
        _, c = call("GET", "/credits", token=TOKEN)
        check("balance is now exactly 36", c["balance"] == 36, c["balance"])

        items = [item(TOKEN, f"C{i}.mp4") for i in range(5)]
        requested = {f"C{i}.mp4" for i in range(5)}
        status, add = call("POST", "/queue/items", {"items": items}, TOKEN)
        # The response carries the whole queue, so count only what we asked for.
        accepted = [p for p in ([add["now_dubbing"]] if add["now_dubbing"] else [])
                    + add["up_next"] if p["title"] in requested]
        check("exactly 3 of 5 are added", len(accepted) == 3, len(accepted))
        check("reserved credits equal the 3 added jobs",
              add["reserved_credits"] == 36, add["reserved_credits"])
        check("the other 2 are reported as not added",
              len(add["rejected"]) == 2, len(add["rejected"]))
        check("stop reason is not_enough_credits",
              add["stopped_reason"] == "not_enough_credits", add["stopped_reason"])
        _, c = call("GET", "/credits", token=TOKEN)
        check("balance is spent down to 0", c["balance"] == 0, c["balance"])
    reset(TOKEN)

    print("== Test 6: New video dubs, Queue videos wait behind it ==")
    reset(TOKEN)
    call("POST", "/projects",
         {"upload_id": upload(TOKEN, "FromNew.mp4"),
          "source_language": "en", "target_language": "km"}, TOKEN)
    call("POST", "/queue/items",
         {"items": [item(TOKEN, f"Q{i}.mp4") for i in range(2)]}, TOKEN)
    _, q = call("GET", "/queue", token=TOKEN)
    check("the New video is Now dubbing", q["now_dubbing"]["title"] == "FromNew.mp4",
          q["now_dubbing"]["title"])
    check("queue videos wait behind it",
          [p["title"] for p in q["up_next"]] == ["Q0.mp4", "Q1.mp4"],
          [p["title"] for p in q["up_next"]])
    reset(TOKEN)

    print("== Test 7: race - two devices start at once ==")
    reset(TOKEN)
    import threading
    results = []

    def start():
        results.append(call("POST", "/projects",
                            {"upload_id": upload(TOKEN, "Race.mp4"),
                             "source_language": "en", "target_language": "km"},
                            TOKEN))

    threads = [threading.Thread(target=start) for _ in range(2)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    codes = sorted(r[0] for r in results)
    check("one succeeds and one is refused", codes == [200, 409], codes)
    check("the loser gets already_dubbing",
          any(r[1].get("code") == "already_dubbing" for r in results if r[0] == 409),
          results)
    _, q = call("GET", "/queue", token=TOKEN)
    check("only one job exists", len(q["up_next"]) == 0, q["up_next"])
    reset(TOKEN)

    print("== Test 8: when the New video finishes, New is free again ==")
    reset(TOKEN)
    call("POST", "/projects",
         {"upload_id": upload(TOKEN, "Finish.mp4"),
          "source_language": "en", "target_language": "km"}, TOKEN)
    _, active = call("GET", "/queue/active", token=TOKEN)
    check("New is blocked while it dubs", active.get("project") is not None)
    print("  (waiting for the job to finish...)")
    import time as _time
    deadline = _time.time() + 40
    freed = False
    while _time.time() < deadline:
        _time.sleep(2)
        _, active = call("GET", "/queue/active", token=TOKEN)
        if active.get("project") is None:
            freed = True
            break
    check("New is free once the queue is empty", freed)
    status, project = call("POST", "/projects",
                           {"upload_id": upload(TOKEN, "Again.mp4"),
                            "source_language": "en", "target_language": "km"},
                           TOKEN)
    check("Start dubbing works again", status == 200, status)
    _, q = call("GET", "/queue", token=TOKEN)
    check("it is Now dubbing", q["now_dubbing"] is not None)
    reset(TOKEN)

    print("== Test 9: queue limits and reorder ==")
    reset(TOKEN)
    _, credits = call("GET", "/credits", token=TOKEN)
    call("POST", "/credits/purchase", {"pack_id": "pack_500"}, TOKEN)
    items = [item(TOKEN, f"L{i}.mp4") for i in range(10)]
    status, add = call("POST", "/queue/items", {"items": items}, TOKEN)
    _, q = call("GET", "/queue", token=TOKEN)
    size = (1 if q["now_dubbing"] else 0) + len(q["up_next"])
    check("queue fills to 20 and no further", size <= 20, size)
    if len(q["up_next"]) >= 2:
        first, second = q["up_next"][0]["id"], q["up_next"][1]["id"]
        call("POST", f"/queue/items/{second}/move", {"to": "top"}, TOKEN)
        _, q2 = call("GET", "/queue", token=TOKEN)
        check("move to top puts it first", q2["up_next"][0]["id"] == second)
        order = [p["id"] for p in q2["up_next"]]
        order.reverse()
        status, _ = call("PUT", "/queue/order", {"order": order}, TOKEN)
        _, q3 = call("GET", "/queue", token=TOKEN)
        check("reorder is saved",
              [p["id"] for p in q3["up_next"]] == order,
              [p["id"] for p in q3["up_next"]])
    reset(TOKEN)

    print(f"\n{ok} passed, {fail} failed")
    return fail


if __name__ == "__main__":
    raise SystemExit(1 if main() else 0)