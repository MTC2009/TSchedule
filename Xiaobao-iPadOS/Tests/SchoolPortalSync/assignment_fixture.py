"""Synthetic student changes. Offline means the school socket closes without any HTTP response."""
import json
import socket
from datetime import datetime, timedelta, timezone
from urllib.parse import parse_qs, urlsplit


class AssignmentFixture:
    def __init__(self, english=False):
        self.english = english
        self.phase = "initial"
        self.offline = False
        self.disconnects = 0
        self.archive_reads = 0
        self.material_reads, self.file_reads = set(), 0
        self.origin_time = datetime.now(timezone.utc).replace(microsecond=0) + timedelta(hours=3)
        self.state = {}
        self.first_id = self.first_process = None
        self.passed = set()

    def handle(self, h):
        path = urlsplit(h.path).path
        if path.startswith("/control/assignments/"):
            op = path.rsplit("/", 1)[1]
            if op == "sample":
                self.state = json.loads(h.rfile.read(int(h.headers["Content-Length"])))
                h.respond(None); return True
            if op in ("offline", "online"):
                self.offline = op == "offline"
            elif op in ("initial", "moved", "withdrawn", "malformed", "other"):
                self.phase = op
            else:
                q = self.state.get("pending", [])
                wanted = int(self.origin_time.timestamp()) - 3600
                item = q[0] if len(q) == 1 else {}
                generic = item.get("title") == ("Assignment due soon" if self.english else "作业即将截止") and item.get("emptyInfo") is True
                at = item.get("fire")
                checks = {
                    "lazily-read": {81,82} <= self.material_reads and self.file_reads == 0,
                    "downloaded": self.file_reads == 1,
                    "armed": generic and at == wanted,
                    "archive-unread": self.archive_reads == 0 and generic and at == wanted,
                    "archive-local": self.offline and self.archive_reads > 0 and item.get("id") == self.first_id and generic and at == wanted,
                    "offline-verified": self.offline and self.disconnects > 0 and not self.state.get("online", True)
                        and self.state.get("issue") == "network" and generic and at == wanted
                        and self.state.get("process") not in (None, self.first_process),
                    "retimed": item.get("id") == self.first_id and generic and at == wanted + 2*86400,
                    "retained": item.get("id") == self.first_id and generic and at == wanted + 2*86400
                        and self.state.get("taskError") == "format",
                    "named": item.get("id") == self.first_id and item.get("title") == "Copperplate study" and at == wanted + 2*86400,
                    "rearmed": bool(item.get("id")) and item.get("id") != self.first_id and item.get("title") == "Copperplate study" and at == wanted + 2*86400,
                    "removed": self.phase == "withdrawn" and self.state.get("optIn") and len(q) == 0,
                    "other-offline": self.offline and self.phase == "other" and self.state.get("issue") == "network" and not self.state.get("optIn") and not q,
                    "held": self.offline and self.state.get("issue") == "network" and self.state.get("review") and not q,
                    "isolated": self.phase == "other" and self.state.get("online") and not self.state.get("optIn") and not q,
                }
                okay = self.state.get("pendingKnown") is True and checks.get(op, False)
                if okay:
                    self.passed.add(op)
                    if op == "armed":
                        self.first_id, self.first_process = item["id"], self.state["process"]
                h.respond(None, 200 if okay else 409); return True
            h.respond(None); return True
        if self.offline:
            self.disconnects += 1
            h.close_connection = True
            try: h.connection.shutdown(socket.SHUT_RDWR)
            except OSError: pass
            return True
        if path == "/api/MemberShip/GetCurrentStudentInfo" and h.current_session():
            n = 2 if self.phase == "other" else 1
            h.respond({"orgId": 7, "userId": 90+n, "studentInfoId": 80+n}); return True
        if path == "/api/School/GetSchoolSemesters" and h.current_session():
            h.respond([{"id":5,"year":2024,"semester":2,"isNow":True,"startDate":"2025-02-01","endDate":"2025-06-30"},
                       {"id":7,"year":2023,"semester":1,"isNow":False,"name":"Print archive",
                        "startDate":"2023-09-01","endDate":"2024-01-20"}]); return True
        if path == "/api/LearningTask/GetDetail" and h.current_session():
            key = int(parse_qs(urlsplit(h.path).query)["learningTaskId"][0])
            if key not in {81,82,83,84}:
                h.respond(None, 403); return True
            self.material_reads.add(key)
            private = self.phase == "other"
            h.respond({"mode":0, "learningTaskState":4 if key==82 else 2,
                "isSynchroToMobiled":1 if key==82 else 0,
                "content":"Cut a square window" if private else "Arrange the four samples",
                "remark":"Mounted on linen" if key==82 else None, "comment":"The edge is even",
                "stuCommitTime":"2025-05-08 13:12:00" if key==82 else None,
                "learningTaskStudentDocuments":[{"id":62,"name":"mounting.txt"}] if key==82 else [],
                "learningTaskDocuments":[],"teacherCommentDocuments":[]})
            return True
        if path == "/api/LearningTask/DownloadDocument" and h.current_session():
            if parse_qs(urlsplit(h.path).query) != {"learningTaskId":["82"],"documentId":["62"],"documentType":["2"]}:
                h.respond(None, 403); return True
            self.file_reads += 1
            data=b"Independent loopback attachment.\n"
            h.send_response(200);h.send_header("Content-Type","text/plain");h.send_header("Content-Length",str(len(data)));h.end_headers();h.wfile.write(data)
            return True
        if path == "/api/LearningTask/GetList" and h.current_session():
            if parse_qs(urlsplit(h.path).query).get("SemesterId") == ["7"]:
                self.archive_reads += 1
                h.respond({"list":[{"id":83,"name":"Etching plate","learningTaskState":2,"endTime":self.origin_time.isoformat()}],
                           "totalCount":1}); return True
            if self.phase == "malformed":
                h.respond({"list":[]}); return True
            moved = self.phase in ("moved", "withdrawn")
            end = self.origin_time + (timedelta(days=2) if moved else timedelta())
            task = {"id":81, "name":"Bookbinding draft" if self.phase == "other" else "Copperplate study",
                    "endTime":end.isoformat(), "learningTaskState":2}
            passive = {"id":82,"name":"Ink inventory","learningTaskState":3}
            if self.phase == "withdrawn":
                task = {"id":84,"name":"Pigment notes","learningTaskState":3}
            # A different owner deliberately reuses the task ID and semester.
            data = [task] if self.phase == "other" else [task, passive]
            h.respond({"list":data,"totalCount":len(data)}); return True
        return False
