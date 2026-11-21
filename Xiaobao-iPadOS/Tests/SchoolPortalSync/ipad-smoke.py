"""Run a real sidebar tap in an isolated iPad simulator bundle, without a school account."""
import argparse
import importlib
import hmac
import json
import os
from datetime import datetime, timedelta
from http.server import ThreadingHTTPServer
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import uuid
from zoneinfo import ZoneInfo

sys.dont_write_bytecode = True
Handler = importlib.import_module("webkit-smoke").Handler
tests = Path(__file__).resolve().parent
root = tests.parents[1]
school = "https://tsinglanstudent.schoolis.cn"


class UIHandler(Handler):
    release_home = threading.Event()
    delegated = False
    account_boundary = False
    annual = None
    navigation = False
    overviews = set()
    archive_reads = 0
    hold_identity = False
    identity_resume = threading.Event()
    native_reads = False
    lesson_activity = False
    activity_started = threading.Event()
    release_activity = threading.Event()
    activity_clock = None
    refuse_first_daily = True
    expected = None
    submissions = []

    def do_GET(self):
        if self.account_boundary and self.path == "/?fixture-maintenance=1":
            self.send_response(503); self.send_header("Content-Type", "text/html"); self.end_headers()
            self.wfile.write(b"<title>Unavailable</title>"); return
        if self.annual and self.annual.get(self): return
        if self.navigation and self.path == "/api/MemberShip/GetCurrentStudentInfo" and self.hold_identity:
            self.identity_resume.wait(timeout=14)
        if self.navigation and self.current_session():
            from urllib.parse import urlsplit, parse_qs
            q = urlsplit(self.path); params = parse_qs(q.query)
            if q.path == "/api/School/GetSchoolSemesters":
                return self.respond([{"id":5,"year":2024,"semester":2,"isNow":True,"startDate":"2025-02-01","endDate":"2025-06-30"},
                       {"id":8,"year":2023,"semester":1,"isNow":False,"startDate":"2023-09-01","endDate":"2024-01-20"}])
            if q.path == "/api/LearningTask/GetList" and params.get("SemesterId") == ["8"]:
                type(self).archive_reads += 1
                return self.respond({"totalCount":1,"list":[{"id":6,"name":"Archive field notes","learningTaskState":4,"mode":0}]})
            if q.path == "/api/DynamicScore/GetGpa" and params.get("semesterId") == ["8"]:
                return self.respond(3.25)
        if self.account_boundary and self.path.startswith("/api/v1/"):
            return self.respond(None, 401)
        if self.path == "/":
            self.send_response(302); self.send_header("Location", "/Home"); self.end_headers()
        elif self.delegated and self.path == "/fixture/home-note":
            self.send_response(200); self.send_header("Content-Type","text/html"); self.end_headers()
            self.wfile.write(b"<p>Footer</p>")
        elif self.delegated and self.path == "/Account/Login":
            type(self).login_pages += 1
            self.send_response(200); self.send_header("Content-Type","text/html; charset=utf-8")
            self.send_header("Cache-Control","no-store"); self.end_headers()
            # The fixture page owns its ordinary click handler; these credentials are local to QA.
            page = """<!doctype html><meta charset=utf-8><title>Fixture</title>
<input type=text placeholder="请输入用户名"><input type=password placeholder="请输入密码"><button>登录</button><p></p>
<script>document.querySelector('button').onclick=async()=>{
const button=document.querySelector('button');button.disabled=true;button.textContent='正在登录';
const [n,p]=document.querySelectorAll('input');
const r=await fetch('/fixture/session',{method:'POST',body:JSON.stringify([n.value,p.value])});
await new Promise(resolve=>setTimeout(resolve,850));
if(r.ok){location.replace('/Home')}else{button.disabled=false;button.textContent='登录';document.querySelector('p').textContent='密码错误'}
}</script>"""
            self.wfile.write(page.encode())
        elif self.path == "/api/MemberShip/GetCurrentStudentInfo" and self.current_session():
            self.respond({"orgId":4,"userId":3,"studentInfoId":31,"loginName":"fixture-portrait"})
        elif self.path.split("?")[0] == "/api/Exam/GetList" and self.current_session():
            self.overviews.add("exams")
            self.respond({"totalCount": 1, "list": [{"id": 21, "name": "Cartography practical"}]})
        elif self.delegated and self.path.split("?")[0] == "/api/DynamicScore/GetGpa" and self.generation == 3 and self.current_session():
            self.respond(3.75)
        elif self.native_reads and self.path.split("?")[0] == "/api/DynamicScore/GetGpa" and self.current_session():
            self.respond(2.75 if len(self.grade_generations) == 1 else 3.25)
        else:
            if self.path == "/Home" and self.homes == 0 and not self.release_home.wait(timeout=45):
                return self.respond(None, 503)
            super().do_GET()

    def do_DELETE(self):
        if self.account_boundary and self.path == "/api/v1/session":
            self.send_response(204); self.end_headers()
        else: self.send_error(404)

    def do_POST(self):
        if self.annual and self.annual.post(self): return
        if self.account_boundary and self.path == "/api/v1/demo/sessions":
            info = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            reply = {"access_token": "fixture-only", "expires_at": "2099-01-01T00:00:00Z"}
            if info.get("remember"): reply.update(refresh_token="fixture-only", refresh_expires_at="2099-02-01T00:00:00Z")
            self.send_response(201); self.send_header("Content-Type", "application/json")
            self.end_headers(); self.wfile.write(json.dumps({"data": reply}).encode()); return
        if self.account_boundary and self.path.startswith("/api/v1/"):
            return self.respond(None, 401)
        if self.navigation and self.path == "/control/warm-overviews":
            return self.respond(None, 200 if self.overviews == {"exams","evaluations","resources"} and not self.archive_reads and not self.grade_generations else 409)
        if self.navigation and self.path in ("/control/hold-identity","/control/resume-identity"):
            type(self).hold_identity = self.path.endswith("/hold-identity")
            if not self.hold_identity: self.identity_resume.set()
            return self.respond(None)
        if self.path == "/v2/basic/CareerAssessment/MyAssessments" and self.current_session():
            self.overviews.add("evaluations")
            return self.respond([{"id": 22, "name": "Studio survey", "hasSubmitted": True}])
        if self.path == "/v2/clouddisk/StudentShare/SharedToMePagedList" and self.current_session():
            data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            if str(data.get("stuInfoId")) != "31": return self.respond(None, 403)
            self.overviews.add("resources")
            return self.respond({"list": [{"id": 8, "name": "Materials guide", "format": "PDF"}], "totalCount": 1})
        if self.lesson_activity and self.path == "/control/lesson-activity":
            self.activity_started.set()
            return self.respond(None, 200 if self.release_activity.wait(timeout=28) else 503)
        if self.lesson_activity and self.path == "/api/Schedule/ListScheduleByParent":
            if not self.current_session(): return self.respond(None, 401)
            request = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            cls = type(self)
            if cls.activity_clock is None:
                cls.activity_clock = datetime.now(ZoneInfo("Asia/Shanghai")).replace(second=0, microsecond=0)
            now = cls.activity_clock
            date = now.date().isoformat()
            if not request["beginTime"] <= date <= request["endTime"]: return self.respond([])
            midnight = now.replace(hour=0, minute=0)
            tomorrow = midnight + timedelta(days=1)
            def lesson(identifier, title, start, end):
                return {"id":identifier,"scheduleType":3,"name":title,
                        "beginTime":max(midnight, now+timedelta(minutes=start)).isoformat(),
                        "endTime":min(tomorrow, now+timedelta(minutes=end)).isoformat()}
            rows = [lesson(17, "Printmaking Lab", -5, 12)]
            if now+timedelta(minutes=20) < tomorrow:
                rows.append(lesson(31, "Visual Systems Lab: Designing Across Motion, Sound and Generative Fields", 20, 62))
            return self.respond(rows)
        if self.delegated and self.path == "/control/no-submissions":
            return self.respond(None,200 if not self.submissions else 409)
        if self.delegated and self.path == "/control/recovered-on-launch":
            return self.respond(None, 200 if self.submissions == [True, True] and self.grade_generations == [1, 2] else 409)
        if self.delegated and self.path == "/control/test-input":
            size = int(self.headers.get("Content-Length",0))
            if size != 36: return self.respond(None,400)
            type(self).expected = self.rfile.read(size); return self.respond(None)
        if self.delegated and self.path == "/fixture/session":
            size = int(self.headers.get("Content-Length",0))
            if not 0 < size < 300: return self.respond(None,400)
            name, supplied = json.loads(self.rfile.read(size))
            ok = self.expected is not None and name == "fixture-portrait" and hmac.compare_digest(self.expected,supplied.encode())
            self.submissions.append(ok)
            if not ok: return self.respond(None,403)
            self.send_response(200); self.send_header("Cache-Control","no-store")
            self.send_header("Set-Cookie",f"fixture_session={self.generation}; Path=/; HttpOnly; SameSite=Strict")
            self.end_headers(); return
        if self.path == "/control/ready":
            self.release_home.set(); return self.respond(None)
        if self.path in ("/control/expire", "/control/revoke-device"):
            type(self).generation += 1
            type(self).allow_device = self.path == "/control/expire"
            return self.respond(None)
        super().do_POST()


# The release project and its source tree are never rewritten. Only the throwaway
# simulator target has a loopback origin, entitlement-free bundle ID and UI test target.
def run(device, space, base, *, settings=False, planner_rotation=False, reminders=False):
    app = space/"app"
    shutil.copytree(root/"Xiaobao.xcodeproj", app/"Xiaobao.xcodeproj",
                    ignore=shutil.ignore_patterns("xcuserdata"))
    shutil.copytree(root/"Sources", app/"Sources")
    shutil.copytree(root/"Config", app/"Config")
    (app/"Resources").symlink_to(root/"Resources", target_is_directory=True)
    if reminders:
        calendar = space/"xiaobao-backend/src/provider/academic-calendar-hs-2026-2027.json"
        calendar.parent.mkdir(parents=True)
        calendar.write_text(json.dumps(UIHandler.annual.publication))
    else:
        (space/"xiaobao-backend").symlink_to(root.parent/"xiaobao-backend", target_is_directory=True)

    def replace(path, old, new):
        source = path.read_text()
        if source.count(old) != 1: raise RuntimeError("Review fixture substitution in " + path.name)
        path.write_text(source.replace(old, new))

    access = app/"Sources/Core/SchoolPortalData/SchoolPortalAccess.swift"
    replace(access, school, base)
    replace(access, 'url.scheme == "https"', 'url.scheme == origin.scheme')
    replace(access, '(url.port == nil || url.port == 443)', 'url.port == origin.port')
    replace(app/"Sources/Native/SchoolPortalSync/PortalRead.js", school, base)
    replace(app/"Sources/Native/SchoolPortalLogin/PortalLogin.js", school, base)
    replace(app/"Sources/Native/SchoolPortal.swift", 'if url.scheme == "https" ||',
            'if SchoolPortalPage.isOfficial(url) ||')
    shutil.copy2(tests/"GradeEntryUITests.swift", app/"GradeEntryUITests.swift")
    if UIHandler.annual:
        shutil.copy2(tests/"AnnualTimetableUITests.swift", app/"AnnualTimetableUITests.swift")
        replace(app/"AnnualTimetableUITests.swift", "__ANNUAL_FIXTURE_ORIGIN__", base)
    if reminders:
        with (app/"Sources/Native/AppModel.swift").open("a") as target:
            target.write("\n"+(tests/"ReminderQueueProbe.swift").read_text())
        replace(app/"Sources/Native/XiaobaoApp.swift", "RootView()\n", "RootView().task { await model.sampleFixtureQueue() }\n")
    elif UIHandler.annual:
        # Only the disposable copy has clock switches; the installed product uses Date().
        clock = ('(ProcessInfo.processInfo.arguments.contains("-AnnualAfterSchool") ? SchoolClock.date(2026, 9, 30, minute: 1040) : '
                 'ProcessInfo.processInfo.arguments.contains("-AnnualHoliday") ? SchoolClock.date(2026, 10, 2) : SchoolClock.date(2026, 9, 10, minute: 540))')
        replace(app/"Sources/Native/AppModel.swift", "var now = Date()", "var now = "+clock)
        replace(app/"Sources/Native/AppModel.swift", "        now = Date()", "        now = "+clock)
        replace(app/"Sources/Native/XiaobaoApp.swift", "model.now = Date()", "model.now = "+clock)
    if UIHandler.lesson_activity:
        shutil.copy2(tests/"LessonActivityUITests.swift", app/"LessonActivityUITests.swift")
        replace(app/"LessonActivityUITests.swift", "__ACTIVITY_FIXTURE_ORIGIN__", base)
        # Multiple fixture apps can be installed on the same QA device.
        replace(app/"Config/Info.plist", "<string>tschedule</string>", "<string>tschedule-activity-qa</string>")
        replace(app/"Sources/ActivityWidget/LessonActivityAttributes.swift",
                "tschedule://lesson-activity", "tschedule-activity-qa://lesson-activity")
    if UIHandler.account_boundary:
        shutil.copy2(tests/"AccountBoundaryTests.swift", app/"AccountBoundaryTests.swift")
        source = (app/"AccountBoundaryTests.swift").read_text().replace("__FIXTURE_ORIGIN__", base)
        (app/"AccountBoundaryTests.swift").write_text(source)
    if UIHandler.navigation:
        shutil.copy2(tests/"SchoolNavigationUITests.swift", app/"SchoolNavigationUITests.swift")
        replace(app/"SchoolNavigationUITests.swift", "__FIXTURE_ORIGIN__", base)
    if settings:
        shutil.copy2(tests/"SettingsUITests.swift", app/"SettingsUITests.swift")
        # Constrain the parent pane in the simulator copy, not the view under test. No QA flags ship.
        replace(app/"Sources/Native/XiaobaoApp.swift", "            SettingsView()",
                '            SettingsView().frame(maxWidth: ProcessInfo.processInfo.arguments.contains("-SettingsFixtureNarrow") ? 420 : .infinity)')
    replace(app/"GradeEntryUITests.swift", "__FIXTURE_ORIGIN__", base)
    replace(app/"GradeEntryUITests.swift", "__FIXTURE_STUDENT_ORIGIN__", base)
    # The test-only runner uses Xcodeproj if installed, not a dependency of TSchedule.
    spec = """
require 'xcodeproj'
p = Xcodeproj::Project.open('Xiaobao.xcodeproj')
host = p.targets.find { |t| t.name == 'Xiaobao' }
fixture_id = ARGV.fetch(0)
p.build_configurations.each { |c| c.build_settings['TSCHEDULE_APP_BUNDLE_IDENTIFIER'] = fixture_id }
unit = ARGV[1] == 'unit'
if unit
  p.targets.each { |target| target.build_configurations.select { |c| c.name == 'Debug' }.each { |c|
    c.build_settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = '$(inherited) DEBUG TSCHEDULE_INTERNAL_FIXTURES'
    c.build_settings['ENABLE_TESTABILITY'] = 'YES' } }
end
t = p.new_target(unit ? :unit_test_bundle : :ui_test_bundle, 'GradeEntryUITests', :ios, '26.0')
t.add_dependency(host)
t.add_file_references((unit ? ['AccountBoundaryTests.swift'] : Dir.glob('*UITests.swift').sort).map { |path| p.main_group.new_file(path) })
t.build_configurations.each { |c| c.build_settings.merge!('GENERATE_INFOPLIST_FILE'=>'YES','TEST_TARGET_NAME'=>'Xiaobao','PRODUCT_NAME'=>'GradeEntryUITests',
 'PRODUCT_BUNDLE_IDENTIFIER'=>fixture_id+'.tests','SWIFT_VERSION'=>'5.0','TARGETED_DEVICE_FAMILY'=>'2',
 'SUPPORTED_PLATFORMS'=>'iphonesimulator','CODE_SIGN_STYLE'=>'Automatic') }
if unit
  t.build_configurations.each { |c| c.build_settings.merge!('TEST_HOST'=>'$(BUILT_PRODUCTS_DIR)/Xiaobao.app/Xiaobao','BUNDLE_LOADER'=>'$(TEST_HOST)') }
end
p.save
s = Xcodeproj::XCScheme.new
s.configure_with_targets(host, t)
s.save_as('Xiaobao.xcodeproj', 'GradeEntryFixture')
"""
    fixture_id = ("cn.xiaobao.fixture.navigation" if UIHandler.navigation else "cn.xiaobao.fixture.boundary" if UIHandler.account_boundary else "cn.xiaobao.fixture.settings" if settings else
                  "cn.xiaobao.fixture.lesson-activity" if UIHandler.lesson_activity else "cn.xiaobao.fixture.grade-entry")
    if UIHandler.annual: fixture_id = "cn.xiaobao.fixture.annual.r"+uuid.uuid4().hex[:12]
    if UIHandler.delegated:
        # Each loopback port represents a different school origin. Never carry a previous
        # run's bound identity into it. The process restart inside one run keeps its Keychain.
        fixture_id = "cn.xiaobao.fixture.signin.r" + uuid.uuid4().hex[:12]
    subprocess.run(["ruby", "-e", spec, fixture_id, "unit" if UIHandler.account_boundary else "ui"], cwd=app, check=True)
    test = ("AnnualTimetableUITests/testBackgroundRemindersAndPrivacyCleanup" if reminders else
            "AnnualTimetableUITests/testPersonalPlanCanSwitchBetweenRotationAndWeekday" if planner_rotation else
            "AnnualTimetableUITests/testSavedYearDrivesTodayAndPlannerWhileLiveRecordsRefresh" if UIHandler.annual else
            "SchoolNavigationUITests/testListsAreWarmedTermsAreOnDemandAndSlowIdentityCanRetry" if UIHandler.navigation else
            "AccountBoundaryTests" if UIHandler.account_boundary else
            "SettingsUITests/testShippingSettingsIgnoreLegacySourceAndNeverOfferFixtures" if settings else
            "LessonActivityUITests/testStartsFromTheLoadedSchoolDayAndCanBeStopped" if UIHandler.lesson_activity else
            "GradeEntryUITests/testNativeAttendanceAndExplicitGPARefresh" if UIHandler.native_reads else
            "GradeEntryUITests/testExplicitlyEnrolledPasswordStartsANewSession" if UIHandler.delegated else
            "GradeEntryUITests/testOpeningGradesRenewsOnceWithoutPresentingAWebsite")
    result = subprocess.run(["xcodebuild", "-quiet", "-project", "Xiaobao.xcodeproj", "-scheme", "GradeEntryFixture",
                    "-configuration", "Debug" if UIHandler.account_boundary else "Release", "-destination", "id="+device, "-parallel-testing-enabled", "NO",
                    "-only-testing:GradeEntryUITests/"+test, "-collect-test-diagnostics", "never",
                    "-derivedDataPath", str(space/"DerivedData"), "COMPILER_INDEX_STORE_ENABLE=NO",
                    "ONLY_ACTIVE_ARCH=YES", "CODE_SIGN_IDENTITY=-", "test"], cwd=app, timeout=390)
    if result.returncode:
        if reminders: print("Synthetic notification transitions:", UIHandler.annual.transitions[-18:])
        print("Fixture counters: homes, login pages, grade generations, attendance reads, submission results:",
              UIHandler.homes, UIHandler.login_pages, UIHandler.grade_generations, UIHandler.attendance_reads, UIHandler.submissions)
        for report in (space/"DerivedData/Logs/Test").glob("*.xcresult"):
            if dest := os.environ.get("TSCHEDULE_FIXTURE_RESULTS"):
                shutil.copytree(report, Path(dest)/report.name)
            summary = subprocess.run(["xcrun","xcresulttool","get","test-results","summary","--path",str(report)],
                                     capture_output=True, text=True)
            if summary.returncode == 0:
                for failure in json.loads(summary.stdout).get("testFailures",[]):
                    print(failure.get("testName"), str(failure.get("failureText","UI assertion failed"))[:500])
        result.check_returncode()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device", help="UUID of an available, dedicated iPad QA simulator")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--delegated",action="store_true",help="Exercise opt-in, real simulator Keychain and synthetic password sign-in")
    mode.add_argument("--settings",action="store_true",help="Check school-only settings and legacy-source upgrade, enrollment disclosure and large text")
    mode.add_argument("--native-reads",action="store_true",help="Verify native attendance, current-course detail and deliberate GPA refresh")
    mode.add_argument("--lesson-activity",action="store_true",help="Start and stop a local Live Activity from the loaded synthetic school day")
    mode.add_argument("--annual", action="store_true", help="Verify offline cold launch, shared rotation, live data and failed manual replacement")
    mode.add_argument("--planner-rotation", action="store_true", help="Create, change and stop a personal plan with the cached teaching calendar")
    mode.add_argument("--navigation", action="store_true", help="Check the verified cache, terms, prefetched lists and bounded identity recovery")
    mode.add_argument("--account-boundary", action="store_true", help="Verify fixture logout, expiry and cold restart against isolated native stores")
    mode.add_argument("--reminders", action="store_true", help="Test real pending and delivered notifications in the isolated iPad app")
    args = parser.parse_args()
    if args.reminders:
        from reminder_fixture import ReminderFixture
        UIHandler.annual = ReminderFixture(); UIHandler.release_home.set()
    elif args.annual or args.planner_rotation:
        from annual_fixture import AnnualFixture
        UIHandler.annual = AnnualFixture(); UIHandler.release_home.set()
    UIHandler.navigation = args.navigation
    UIHandler.account_boundary = args.account_boundary
    UIHandler.delegated = args.delegated
    if args.delegated:
        UIHandler.home_body = b'<html><body>Fixture<iframe hidden src="/fixture/home-note"></iframe></body></html>'
    UIHandler.native_reads = args.native_reads
    UIHandler.lesson_activity = args.lesson_activity
    if args.navigation or args.account_boundary or args.settings or args.native_reads or args.lesson_activity: UIHandler.release_home.set()
    if args.lesson_activity: UIHandler.release_activity.set()
    with tempfile.TemporaryDirectory(prefix="tschedule-grade-ui-") as d, ThreadingHTTPServer(("127.0.0.1", 0), UIHandler) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            run(args.device, Path(d), "http://127.0.0.1:" + str(server.server_port), settings=args.settings,
                planner_rotation=args.planner_rotation, reminders=args.reminders)
        finally:
            server.shutdown()
        if args.reminders:
            assert UIHandler.annual.count == UIHandler.annual.baseline and not UIHandler.submissions
            print("PASS: system delivered both alerts in background; class opt-out preserved personal alerts; logout cleared both.")
        elif args.planner_rotation:
            assert UIHandler.annual.baseline > 0 and UIHandler.annual.count == UIHandler.annual.baseline and not UIHandler.submissions
            print("PASS: recurrence editor saved a rotation Day, switched to weekday, stopped the series, no additional schedule reads")
        elif args.annual:
            assert UIHandler.annual.count == UIHandler.annual.baseline+1 and not UIHandler.submissions
            print("PASS: annual import, zero browsing reads, live summaries, failed replacement and offline cold relaunch")
        elif args.navigation:
            assert UIHandler.archive_reads >= 1 and not UIHandler.unexpected_posts
            print("PASS: overview prefetch, task/GPA term switch, preserved cache, stalled identity and retry")
        elif args.account_boundary:
            print("PASS: account isolation and reminder cleanup; one unanswered sign-in timed out, and a framed login did not claim a password")
        elif args.lesson_activity:
            assert UIHandler.activity_started.is_set() and UIHandler.login_pages == 0
            assert not UIHandler.grade_generations and not UIHandler.submissions and not UIHandler.unexpected_posts
            print("PASS: started and stopped a local Live Activity from the loaded schedule; no grades or re-login")
        elif args.native_reads:
            assert UIHandler.grade_generations == [1,1] and UIHandler.homes == 1 and UIHandler.login_pages == 0
            # A newly mounted attendance tab refreshes live data. Prefetch can be joined
            # if still in flight; the return to Attendance must read the classroom summary again.
            summary = ["GetAttendanceStatistic","GetSubjectAttendanceStatistic"]
            tail = ["GetSubjectAttendanceDetail", *summary, "GetAttendanceStatistic","GetAttendanceStatistic","GetAttendanceStatisticDetail"]
            assert UIHandler.attendance_reads in (summary+tail, summary+summary+tail), UIHandler.attendance_reads
            assert not UIHandler.submissions and not UIHandler.unexpected_posts
            print("PASS: GPA on entry, fresh on refresh and reused on return; native attendance, course detail, refused read and empty retry; no web sheet or password")
        elif args.settings:
            assert not UIHandler.grade_generations and not UIHandler.submissions and not UIHandler.unexpected_posts
            print("PASS: shipping school-only settings, legacy-source upgrade, native disclosure and large-text portrait; no grade reads or sign-in submissions")
        elif args.delegated:
            assert (UIHandler.login_pages, UIHandler.grade_generations, UIHandler.submissions, UIHandler.unexpected_posts) == (3,[1,2,3],[True,True,False],0)
            print("PASS: one foreground submission through busy form and framed Home, verified cold launch without grades, preserved refusal and no repeat")
        else:
            assert (UIHandler.homes, UIHandler.login_pages, UIHandler.grade_generations, UIHandler.unexpected_posts) == (3, 1, [1, 2], 0)
            print("PASS: actual iPad GPA taps displayed a fresh mark without a web sheet, then stopped on forced reauthentication")
