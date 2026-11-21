"""Compare local release binaries over one persistent HTTP connection (Python 3.9+)."""

import argparse
from datetime import date, timedelta
import http.client
import json
import math
import os
from pathlib import Path
from statistics import median
import subprocess
from tempfile import TemporaryDirectory
from time import perf_counter_ns


def measure(binary, samples, include_calendar_42d=False):
    env = dict(os.environ, XIAOBAO_ADDR="127.0.0.1:0")
    with TemporaryDirectory() as tmp, subprocess.Popen(
        [binary], env=dict(env, XIAOBAO_SESSION_DB=str(Path(tmp) / "sessions.sqlite3")),
        stderr=subprocess.PIPE, text=True
    ) as server:
        try:
            address = server.stderr.readline().split("http://")[1].split()[0]
            conn = http.client.HTTPConnection(address, timeout=5)
            tokens = []
            for profile in ("demo-a", "demo-b"):
                conn.request("POST", "/api/v1/demo/sessions", json.dumps({"profile": profile}),
                             {"Content-Type": "application/json"})
                res = conn.getresponse()
                assert res.status == 201
                tokens.append(json.load(res)["data"]["access_token"])

            def get(path, token):
                conn.request("GET", "/api/v1/" + path, headers={"Authorization": "Bearer " + token})
                res = conn.getresponse()
                assert res.status == 200, (path, res.status)
                return res.read()

            ref = date.fromisoformat(json.loads(get("me", tokens[0]))["data"]["profile"]["reference_date"])
            monday = ref - timedelta(days=ref.weekday())
            paths = {"schedule": f"schedule?date={monday + timedelta(days=2)}",
                     "calendar_week": f"calendar?from={monday}&to={monday + timedelta(days=6)}",
                     "grades": "grades", "attendance": "attendance"}
            if include_calendar_42d:
                paths["calendar_42d"] = f"calendar?from={monday}&to={monday + timedelta(days=41)}"
            timings = {key: [] for key in paths}
            for i in range(samples + 20):
                for key, path in paths.items():
                    start = perf_counter_ns()
                    get(path, tokens[i % 2])
                    elapsed = (perf_counter_ns() - start) / 1000
                    if i >= 20:
                        timings[key].append(elapsed)
            rss = int(subprocess.check_output(["ps", "-o", "rss=", "-p", str(server.pid)]))
            conn.close()
        finally:
            server.terminate()
            server.wait(timeout=5)
    assert server.returncode == 0
    return timings, rss


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binaries", type=Path, nargs="+")
    parser.add_argument("--runs", type=int, default=6)
    parser.add_argument("--samples", type=int, default=500, help="requests per route per run")
    parser.add_argument("--calendar-42d", action="store_true", help="also measure the largest supported calendar window")
    args = parser.parse_args()
    if args.runs < 1 or args.samples < 1:
        parser.error("runs and samples must be positive")
    binaries = [path.resolve() for path in args.binaries]
    runs = {path: [] for path in binaries}
    for i in range(args.runs):
        for binary in (binaries if i % 2 == 0 else reversed(binaries)):
            runs[binary].append(measure(binary, args.samples, args.calendar_42d))
    for binary, trials in runs.items():
        routes = {}
        for key in trials[0][0]:
            values = sorted(t for timings, _ in trials for t in timings[key])
            routes[key] = {"p50_us": round(median(values), 1),
                           "p95_us": round(values[math.ceil(0.95 * len(values)) - 1], 1)}
        print(json.dumps({"binary": str(binary), "binary_bytes": binary.stat().st_size,
                          "requests_per_route": args.runs * args.samples, "routes": routes,
                          "median_warm_rss_kib": median(rss for _, rss in trials)}))


if __name__ == "__main__":
    main()
