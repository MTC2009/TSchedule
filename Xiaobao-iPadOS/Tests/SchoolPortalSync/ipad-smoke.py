"""Run a real sidebar tap in an isolated iPad simulator bundle, without a school account."""
import argparse
import importlib
import hmac
import json
from datetime import datetime, timedelta
from http.server import ThreadingHTTPServer
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
from zoneinfo import ZoneInfo

sys.dont_write_bytecode = True
Handler = importlib.import_module("webkit-smoke").Handler
tests = Path(__file__).resolve().parent
root = tests.parents[1]
school = "https://tsinglanstudent.schoolis.cn"


class UIHandler(Handler):
    release_home = threading.Event()
    delegated = False
    native_reads = False
    lesson_activity = False
    activity_started = threading.Event()
    release_activity = threading.Event()
    activity_clock = None
    refuse_first_daily = True
    expected = None
    submissions = []

    def do_GET(self):
        if self.path == "/":
            self.send_response(302); self.send_header("Location", "/Home"); self.end_headers()
        elif self.delegated and self.path == "/Account/Login":
            type(self).login_pages += 1
            self.send_response(200); self.send_header("Content-Type","text/html; charset=utf-8")
            self.send_header("Cache-Control","no-store"); self.end_headers()
            # The fixture page owns its ordinary click handler; these credentials are local to QA.
            page = """<!doctype html><meta charset=utf-8><title>Fixture</title>
<input type=text placeholder="请输入用户名"><input type=password placeholder="请输入密码"><button>登录</button><p></p>
<script>document.querySelector('button').onclick=async()=>{
const [n,p]=document.querySelectorAll('input');
const r=await fetch('/fixture/session',{method:'POST',body:JSON.stringify([n.value,p.value])});
if(r.ok){location.replace('/Home')}else{document.querySelector('p').textContent='密码错误'}
}</script>"""
            self.wfile.write(page.encode())
        elif self.delegated and self.path == "/api/MemberShip/GetCurrentStudentInfo" and self.current_session():
            self.respond({"orgId":4,"userId":3,"loginName":"fixture-portrait"})
        elif self.delegated and self.path.split("?")[0] == "/api/DynamicScore/GetGpa" and self.generation == 3 and self.current_session():
            self.respond(3.75)
        elif self.native_reads and self.path.split("?")[0] == "/api/DynamicScore/GetGpa" and self.current_session():
            self.respond(2.75 if len(self.grade_generations) == 1 else 3.25)
        else:
            if self.path == "/Home" and self.homes == 0 and not self.release_home.wait(timeout=45):
                return self.respond(None, 503)
            super().do_GET()

    def do_POST(self):
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
        if self.delegated and self.path == "/control/one-submission":
            return self.respond(None,200 if self.submissions == [True] else 409)
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
def run(device, space, base, *, settings=False):
    app = space/"app"
    shutil.copytree(root/"Xiaobao.xcodeproj", app/"Xiaobao.xcodeproj",
                    ignore=shutil.ignore_patterns("xcuserdata"))
    shutil.copytree(root/"Sources", app/"Sources")
    shutil.copytree(root/"Config", app/"Config")
    (app/"Resources").symlink_to(root/"Resources", target_is_directory=True)
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
    if UIHandler.lesson_activity:
        shutil.copy2(tests/"LessonActivityUITests.swift", app/"LessonActivityUITests.swift")
        replace(app/"LessonActivityUITests.swift", "__ACTIVITY_FIXTURE_ORIGIN__", base)
        # Multiple fixture apps can be installed on the same QA device.
        replace(app/"Config/Info.plist", "<string>tschedule</string>", "<string>tschedule-activity-qa</string>")
        replace(app/"Sources/ActivityWidget/LessonActivityAttributes.swift",
                "tschedule://lesson-activity", "tschedule-activity-qa://lesson-activity")
    if settings:
        shutil.copy2(tests/"SettingsUITests.swift", app/"SettingsUITests.swift")
        # Constrain the parent pane in the simulator copy, not the view under test. No QA flags ship.
        replace(app/"Sources/Native/XiaobaoApp.swift", "case .settings: SettingsView()",
                'case .settings: SettingsView().frame(maxWidth: ProcessInfo.processInfo.arguments.contains("-SettingsFixtureNarrow") ? 420 : .infinity)')
    replace(app/"GradeEntryUITests.swift", "__FIXTURE_ORIGIN__", base)
    replace(app/"GradeEntryUITests.swift", "__FIXTURE_STUDENT_ORIGIN__", base)
    # The test-only runner uses Xcodeproj if installed, not a dependency of TSchedule.
    spec = """
require 'xcodeproj'
p = Xcodeproj::Project.open('Xiaobao.xcodeproj')
host = p.targets.find { |t| t.name == 'Xiaobao' }
fixture_id = ARGV.fetch(0)
p.build_configurations.each { |c| c.build_settings['TSCHEDULE_APP_BUNDLE_IDENTIFIER'] = fixture_id }
t = p.new_target(:ui_test_bundle, 'GradeEntryUITests', :ios, '26.0')
t.add_dependency(host)
t.add_file_references(Dir.glob('*UITests.swift').sort.map { |path| p.main_group.new_file(path) })
t.build_configurations.each { |c| c.build_settings.merge!('GENERATE_INFOPLIST_FILE'=>'YES','TEST_TARGET_NAME'=>'Xiaobao','PRODUCT_NAME'=>'GradeEntryUITests',
 'PRODUCT_BUNDLE_IDENTIFIER'=>fixture_id+'.tests','SWIFT_VERSION'=>'5.0','TARGETED_DEVICE_FAMILY'=>'2',
 'SUPPORTED_PLATFORMS'=>'iphonesimulator','CODE_SIGN_STYLE'=>'Automatic') }
p.save
s = Xcodeproj::XCScheme.new
s.configure_with_targets(host, t)
s.save_as('Xiaobao.xcodeproj', 'GradeEntryFixture')
"""
    fixture_id = ("cn.xiaobao.fixture.settings" if settings else
                  "cn.xiaobao.fixture.lesson-activity" if UIHandler.lesson_activity else "cn.xiaobao.fixture.grade-entry")
    subprocess.run(["ruby", "-e", spec, fixture_id], cwd=app, check=True)
    test = ("SettingsUITests/testSettingsFollowTheSelectedDataSource" if settings else
            "LessonActivityUITests/testStartsFromTheLoadedSchoolDayAndCanBeStopped" if UIHandler.lesson_activity else
            "GradeEntryUITests/testNativeAttendanceAndExplicitGPARefresh" if UIHandler.native_reads else
            "GradeEntryUITests/testExplicitlyEnrolledPasswordStartsANewSession" if UIHandler.delegated else
            "GradeEntryUITests/testOpeningGradesRenewsOnceWithoutPresentingAWebsite")
    result = subprocess.run(["xcodebuild", "-quiet", "-project", "Xiaobao.xcodeproj", "-scheme", "GradeEntryFixture",
                    "-configuration", "Release", "-destination", "id="+device, "-parallel-testing-enabled", "NO",
                    "-only-testing:GradeEntryUITests/"+test, "-collect-test-diagnostics", "never",
                    "-derivedDataPath", str(space/"DerivedData"), "COMPILER_INDEX_STORE_ENABLE=NO",
                    "ONLY_ACTIVE_ARCH=YES", "CODE_SIGN_IDENTITY=-", "test"], cwd=app, timeout=390)
    if result.returncode:
        print("Fixture counters: homes, login pages, grade generations, attendance reads, submission results:",
              UIHandler.homes, UIHandler.login_pages, UIHandler.grade_generations, UIHandler.attendance_reads, UIHandler.submissions)
        for report in (space/"DerivedData/Logs/Test").glob("*.xcresult"):
            summary = subprocess.run(["xcrun","xcresulttool","get","test-results","summary","--path",str(report)],
                                     capture_output=True, text=True)
            if summary.returncode == 0:
                for failure in json.loads(summary.stdout).get("testFailures",[]):
                    print(str(failure.get("failureText","UI assertion failed")).splitlines()[0][:400])
        result.check_returncode()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device", help="UUID of an available, dedicated iPad QA simulator")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--delegated",action="store_true",help="Exercise opt-in, real simulator Keychain and synthetic password sign-in")
    mode.add_argument("--settings",action="store_true",help="Check school and demo settings, enrollment disclosure and large text")
    mode.add_argument("--native-reads",action="store_true",help="Verify native attendance, current-course detail and deliberate GPA refresh")
    mode.add_argument("--lesson-activity",action="store_true",help="Start and stop a local Live Activity from the loaded synthetic school day")
    args = parser.parse_args()
    UIHandler.delegated = args.delegated
    UIHandler.native_reads = args.native_reads
    UIHandler.lesson_activity = args.lesson_activity
    if args.settings or args.native_reads or args.lesson_activity: UIHandler.release_home.set()
    if args.lesson_activity: UIHandler.release_activity.set()
    with tempfile.TemporaryDirectory(prefix="tschedule-grade-ui-") as d, ThreadingHTTPServer(("127.0.0.1", 0), UIHandler) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            run(args.device, Path(d), "http://127.0.0.1:" + str(server.server_port), settings=args.settings)
        finally:
            server.shutdown()
        if args.lesson_activity:
            assert UIHandler.activity_started.is_set() and UIHandler.login_pages == 0
            assert not UIHandler.grade_generations and not UIHandler.submissions and not UIHandler.unexpected_posts
            print("PASS: started and stopped a local Live Activity from the loaded schedule; no grades or re-login")
        elif args.native_reads:
            assert UIHandler.grade_generations == [1,1,1] and UIHandler.homes == 1 and UIHandler.login_pages == 0
            assert UIHandler.attendance_reads == ["GetAttendanceStatistic","GetSubjectAttendanceStatistic","GetSubjectAttendanceDetail",
                                                  "GetAttendanceStatistic","GetAttendanceStatistic","GetAttendanceStatisticDetail"]
            assert not UIHandler.submissions and not UIHandler.unexpected_posts
            print("PASS: fresh GPA on entry, refresh and return; native attendance, course detail, refused read and empty retry; no web sheet or password")
        elif args.settings:
            assert not UIHandler.grade_generations and not UIHandler.submissions and not UIHandler.unexpected_posts
            print("PASS: school and demo settings, native disclosure and large-text portrait; no grade reads or sign-in submissions")
        elif args.delegated:
            assert (UIHandler.login_pages, UIHandler.grade_generations, UIHandler.submissions, UIHandler.unexpected_posts) == (3,[1,2,3],[True,True,False],0)
            print("PASS: iPad opt-in, real simulator Keychain, new login after full expiry, fresh GPA, rejection with no repeat")
        else:
            assert (UIHandler.homes, UIHandler.login_pages, UIHandler.grade_generations, UIHandler.unexpected_posts) == (3, 1, [1, 2], 0)
            print("PASS: actual iPad GPA taps displayed a fresh mark without a web sheet, then stopped on forced reauthentication")
