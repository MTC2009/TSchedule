"""Synthetic calendar-bound course rows and request counters for the isolated iPad test."""
from datetime import date, timedelta
import json
from pathlib import Path


class AnnualFixture:
    def __init__(self):
        school = Path(__file__).resolve().parents[3] / "xiaobao-backend/src/provider/academic-calendar-hs-2026-2027.json"
        dates = json.loads(school.read_text())["days"]
        self.days = {r["date"]: r["day"] for r in dates if r["status"] == "teaching"}
        self.count = self.baseline = 0
        self.block_reads = self.offline = False

    def get(self, handler):
        if self.offline:
            handler.respond(None, 503)
            return True
        return False

    def extra_rows(self, start, end):
        return []

    def post(self, handler):
        command = handler.path.removeprefix("/control/annual/")
        if handler.path.startswith("/control/annual/"):
            good = True
            if command == "baseline":
                good = 3 <= self.count <= 6
                if good: self.baseline = self.count
            elif command == "unchanged": good = self.baseline > 0 and self.count == self.baseline
            elif command == "failed-once": good = self.count == self.baseline + 1
            elif command == "deny": self.block_reads = True
            elif command == "offline": self.offline = True
            elif command == "live": good = bool(handler.grade_generations and handler.attendance_reads)
            else: good = False
            handler.respond(None, 200 if good else 409)
            return True
        if handler.path != "/api/Schedule/ListScheduleByParent": return False
        self.count += 1
        if self.offline or self.block_reads: handler.respond(None, 503); return True
        if not handler.current_session(): handler.respond(None, 401); return True
        args = json.loads(handler.rfile.read(int(handler.headers["Content-Length"])))
        start, end = [date.fromisoformat(args[k]) for k in ("beginTime","endTime")]
        if end-start != timedelta(days=6): handler.respond(None,400); return True
        rows = []
        for offset in range(7):
            key = (start+timedelta(days=offset)).isoformat()
            if cycle := self.days.get(key):
                rows.append({"id":offset+1,"scheduleType":3,"name":"Ceramics "+str(cycle),
                             "beginTime":key+"T08:40:00","endTime":key+"T09:47:00","playgroundName":"East studio"})
        handler.respond(rows + self.extra_rows(start, end))
        return True
