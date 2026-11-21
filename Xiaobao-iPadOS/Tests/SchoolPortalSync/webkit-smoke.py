"""Launch the actual bundled JS in Apple WebKit against a fake HTTP-only session on loopback."""
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit
from pathlib import Path
import json
import subprocess
import tempfile
import threading

class Handler(BaseHTTPRequestHandler):
    # Every value is a loopback-only fixture. Expiry is server-side; retaining an old cookie is not enough.
    home_body = b"<html><body>Fixture</body></html>"
    generation = 1
    allow_device = True
    homes = 0
    login_pages = 0
    grade_generations = []
    attendance_reads = []
    refuse_first_daily = False
    unexpected_posts = 0

    def cookies(self):
        return SimpleCookie(self.headers.get("Cookie", ""))

    def current_session(self):
        sid = self.cookies().get("fixture_session")
        return sid is not None and sid.value == str(self.generation)

    def log_message(self, *args):
        pass  # No request/response contents in logs.
    def respond(self, data, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(json.dumps({"state": 0, "data": data}).encode())
    def do_GET(self):
        route = self.path.split("?")[0]
        if route == "/Home":
            cls = type(self)
            cls.homes += 1
            device = self.cookies().get("fixture_device")
            if cls.homes != 1 and not self.current_session() and not (self.allow_device and device and device.value == "local"):
                self.send_response(302); self.send_header("Location", "/Account/Login")
                self.send_header("Cache-Control", "no-store"); self.end_headers(); return
            self.send_response(200); self.send_header("Content-Type", "text/html")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Set-Cookie", f"fixture_session={self.generation}; Path=/; HttpOnly; SameSite=Strict")
            if cls.homes == 1:
                self.send_header("Set-Cookie", "fixture_device=local; Path=/; HttpOnly; SameSite=Strict")
            self.end_headers(); self.wfile.write(self.home_body); return
        if route == "/Account/Login":
            type(self).login_pages += 1
            self.send_response(200); self.send_header("Content-Type", "text/html"); self.end_headers()
            self.wfile.write(b"<title>Interaction required</title>"); return
        if not self.current_session():
            return self.respond(None, 401)
        if route == "/api/MemberShip/GetCurrentStudentInfo":
            return self.respond({"orgId": 4, "userId": 3})
        if route == "/api/DynamicScore/GetStuSemesterDynamicScore":
            self.grade_generations.append(self.generation)
        if route.startswith("/api/Attendance/"):
            query = parse_qs(urlsplit(self.path).query)
            if query.get("BeginTime") != ["2025-02-01 00:00:00"] or query.get("EndTime") != ["2025-06-30 23:59:59"]:
                return self.respond(None, 400)
            self.attendance_reads.append(route.rsplit("/", 1)[-1])
            if query.get("AttendanceType") == ["1"]:
                if route == "/api/Attendance/GetAttendanceStatistic":
                    if self.refuse_first_daily:
                        type(self).refuse_first_daily = False
                        return self.respond(None, 403)
                    return self.respond({"totalCount":0,"sataeCountList":[]})
                if route == "/api/Attendance/GetAttendanceStatisticDetail" and query.get("Page.PageIndex") == ["1"]:
                    return self.respond({"totalCount":0,"list":[]})
            if route == "/api/Attendance/GetAttendanceStatistic" and query.get("AttendanceType") == ["7"]:
                return self.respond({"totalCount":4,"attendanceRate":75,"sataeCountList":[
                    {"attendanceState":0,"count":3},{"attendanceState":1,"count":1}]})
            if route == "/api/Attendance/GetSubjectAttendanceStatistic":
                return self.respond([{"subjectId":51,"subjectName":"色彩观察","normalCount":3,"lateCount":1,"earlyLeaveCount":0,"absentCount":0}])
            if route == "/api/Attendance/GetSubjectAttendanceDetail" and query.get("SubjectId") == ["51"] and query.get("Page.PageIndex") == ["1"]:
                return self.respond({"totalCount":1,"list":[{"subjectId":51,"subjectName":"色彩观察","attendanceState":1,
                    "beginTime":"2025-03-17 08:10:00","endTime":"2025-03-17 08:50:00"}]})
            return self.respond(None, 404)
        data = {
            "/api/School/GetSchoolSemesters": [{"id":5,"year":2024,"semester":2,"isNow":True,
                                                 "startDate":"2025-02-01","endDate":"2025-06-30"}],
            "/api/DynamicScore/GetStuSemesterDynamicScore": {"studentSemesterDynamicScoreBasicDtos":[
                {"classId":9,"subjectId":3,"subjectName":"Form","scoreType":1,"subjectScore":17,"subjectTotalScore":20}]},
            "/api/DynamicScore/GetGpa": 2.75 if self.generation == 1 else 3.5,
            "/api/DynamicScore/GetDynamicScoreDetail": {"evaluationProjectList":[{"evaluationProjectName":"Portfolio",
                                                                                "proportion":20}]},
            "/api/LearningTask/GetList": {"totalCount":1,"list":[{"id":3,"name":"Contour","learningTaskState":4,
                "mode":0,"isSynchroToMobiled":1,"scoreType":1,"score":0,"totalScore":5}]}
        }
        if route not in data:
            return self.respond(None, 404)
        self.respond(data[route])
    def do_POST(self):
        if self.path in ("/fixture/expire", "/fixture/revoke-device") and self.current_session():
            cls = type(self)
            cls.generation += 1; cls.allow_device = self.path == "/fixture/expire"
            return self.respond(None)
        if self.path != "/api/Schedule/ListScheduleByParent":
            type(self).unexpected_posts += 1
            return self.respond(None, 403)
        if not self.current_session():
            return self.respond(None, 403)
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if payload != {"beginTime":"2025-02-16","endTime":"2025-02-22"}:
            return self.respond(None, 400)
        self.respond([{"id":4,"scheduleType":3,"name":"Form","playgroundName":"Loft",
                       "beginTime":"2025-02-20T09:00:00","endTime":"2025-02-20T09:45:00"}])

if __name__ == "__main__":
    root = Path(__file__).resolve().parent
    sources = root.parents[1]/"Sources"
    with tempfile.TemporaryDirectory(prefix="tschedule-webkit-") as scratch, ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        binary = Path(scratch)/"probe"
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-whole-module-optimization",
                        *sorted((sources/"Core").rglob("*.swift")), sources/"Native/SchoolPortalSync/SchoolPortalEntry.swift",
                        root/"WebKitSmoke.swift", "-o", binary], check=True, timeout=120)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            result = subprocess.run([binary, "http://127.0.0.1:" + str(server.server_port),
                                     sources/"Native/SchoolPortalSync"], timeout=100)
        finally:
            server.shutdown()
        if result.returncode == 0:
            assert (Handler.homes, Handler.login_pages, Handler.grade_generations, Handler.unexpected_posts) == (3, 1, [1, 2], 0)
            assert Handler.attendance_reads == ["GetAttendanceStatistic", "GetSubjectAttendanceStatistic", "GetSubjectAttendanceDetail"]
            print("PASS: server saw three scoped attendance reads, two grade snapshots, one entry per expiry and no credential submission")
    raise SystemExit(result.returncode)
