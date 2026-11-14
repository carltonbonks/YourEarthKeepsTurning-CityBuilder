#!/usr/bin/env python3
"""Pulls players' shared runs, sessions and visits out of the playtest database (tools/telemetry/schema.sql).

Usage: SUPABASE_SECRET_KEY=... python3 tools/telemetry/export.py <raw folder> <csv folder>

Writes <raw>/players.jsonl (one run record per line, newest save of each run, ready for tools/export_csv.py)
and <csv>/visits.csv and <csv>/sessions.csv. The project address comes from telemetry.json; the secret key
only from the environment, never from a file in the repo. Standard library only.
"""
import csv
import json
import os
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PAGE = 500


def fetch(base, key, table, select, order):
    headers = {"apikey": key}
    if key.startswith("eyJ"):  # an older service-role key also wants a bearer header
        headers["Authorization"] = "Bearer " + key
    rows, start = [], 0
    while True:
        url = "%s/rest/v1/%s?select=%s&order=%s" % (base, table, select, order)
        req = urllib.request.Request(url, headers=dict(headers, Range="%d-%d" % (start, start + PAGE - 1)))
        with urllib.request.urlopen(req, timeout=60) as resp:
            page = json.load(resp)
        rows.extend(page)
        if len(page) < PAGE:
            return rows
        start += PAGE


def write_csv(path, rows):
    if not rows:
        return
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)


def main(raw, out):
    config = json.load(open(os.path.join(ROOT, "telemetry.json")))
    base = config.get("url", "").rstrip("/")
    key = os.environ.get("SUPABASE_SECRET_KEY", "")
    if not base or not key:
        sys.exit("telemetry.json needs a url and SUPABASE_SECRET_KEY must be set")
    runs = fetch(base, key, "runs", "run_id,player_id,first_at,updated_at,uploads,record", "first_at")
    os.makedirs(raw, exist_ok=True)
    with open(os.path.join(raw, "players.jsonl"), "w") as f:
        for r in runs:
            rec = r["record"]
            rec.setdefault("id", r["run_id"])
            rec["player"] = "human"
            rec["source"] = "web"
            rec["player_id"] = r["player_id"]
            rec["first_at"], rec["updated_at"], rec["uploads"] = r["first_at"], r["updated_at"], r["uploads"]
            f.write(json.dumps(rec, separators=(",", ":")) + "\n")
    os.makedirs(out, exist_ok=True)
    write_csv(os.path.join(out, "visits.csv"), fetch(base, key, "visits", "*", "at"))
    write_csv(os.path.join(out, "sessions.csv"), fetch(base, key, "sessions", "*", "at"))
    print("%d runs" % len(runs))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
