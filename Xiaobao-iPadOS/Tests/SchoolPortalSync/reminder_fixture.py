"""Loopback-only clock-relative calendar, including a dated class due during the UI test."""
from datetime import datetime, timedelta
import json
from zoneinfo import ZoneInfo
from annual_fixture import AnnualFixture


class ReminderFixture(AnnualFixture):
    def __init__(self):
        super().__init__()
        self.clock = ZoneInfo("Asia/Shanghai")
        start = datetime.now(self.clock).date() - timedelta(days=25)
        days, rotation = [], 1
        for offset in range(60):
            day = start + timedelta(days=offset)
            row = {"date": day.isoformat(), "status": "weekend", "notices": []}
            if day.weekday() < 5:
                row.update(status="teaching", day=rotation)
                rotation = rotation % 6 + 1
            days.append(row)
        self.publication = dict(campus="main", division="HS", academic_year="QA", source_sha256="loopback",
                                days=days, **{"from": days[0]["date"], "through": days[-1]["date"]})
        self.days = {r["date"]: r["day"] for r in days if r["status"] == "teaching"}
        self.start = None
        self.state = {}
        self.before_offline = None
        self.transitions = []

    def extra_rows(self, start, end):
        if self.start is None:
            self.start = (datetime.now(self.clock) + timedelta(minutes=7)).replace(second=0, microsecond=0)
            # Keep the synthetic period within one school date, including midnight-edge runs.
            if self.start.hour == 23 and self.start.minute == 59: self.start += timedelta(minutes=1)
        when = self.start
        if not start <= when.date() <= end: return []
        return [dict(id=999, scheduleType=3, name="Fixture lab", beginTime=when.isoformat(),
                     endTime=(when+timedelta(minutes=1)).isoformat(), playgroundName="Fixture studio")]

    def post(self, handler):
        path = handler.path
        if path == "/control/annual/qa-state":
            sample = json.loads(handler.rfile.read(int(handler.headers["Content-Length"])))
            if sample != self.state:
                self.transitions.append({k: v for k, v in sample.items() if k in
                    ("personal", "school", "deliveredTotal", "permission", "optIn", "issue", "revoked")})
            self.state = sample
            handler.respond(None); return True
        if path == "/control/annual/offline": self.before_offline = self.state.get("process")
        if path.startswith("/control/annual/qa-"):
            p, s = self.state.get("personal", -1), self.state.get("school", -1)
            okay = {"qa-armed": p >= 2 and s > 0 and self.state.get("private") is True,
                    "qa-due": self.start is not None and datetime.now(self.clock) >= self.start-timedelta(minutes=5)+timedelta(seconds=3),
                    "qa-delivered": self.state.get("deliveredBoth") is True and p >= 1,
                    "qa-cold-delivered": self.state.get("deliveredBoth") is True and p >= 1 and
                        self.before_offline != self.state.get("process") and not self.state.get("hasOwner"),
                    "qa-personal-only": p >= 1 and s == 0 and self.state.get("deliveredSchool") == 0,
                    "qa-cleared": p == s == 0 and self.state.get("deliveredTotal") == 0}.get(path.rsplit("/", 1)[1], False)
            handler.respond(None, 200 if okay else 409); return True
        return super().post(handler)
