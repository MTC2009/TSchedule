"""Run real XCTest taps/drags against the shipping Metal/picking code, with no school session."""
from pathlib import Path
import argparse
import plistlib
import subprocess

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('device',help='Dedicated booted QA iPad UUID')
p.add_argument('scratch',type=Path,help='A new or previous seasonal-fixture build folder')
args=p.parse_args()
here=Path(__file__).resolve().parent
root=here.parents[1]
out=args.scratch.resolve()
marker=out/'.seasonal-touch-fixture'
if out.exists() and any(out.iterdir()) and not marker.is_file():
    raise SystemExit('Use a dedicated empty folder, not an existing project or build')
project=out/'Xiaobao.xcodeproj'
project.mkdir(parents=True,exist_ok=True)
marker.touch(exist_ok=True)
entry=root/'Sources/Native/XiaobaoApp.swift'
s=entry.read_text()
if s.count('@main @MainActor')!=1:
    raise SystemExit('Review changed app entry before substituting the local fixture')
fixture=out/'FixtureEntry.swift'
fixture.write_text(s.replace('@main @MainActor','@MainActor')+'\n'+(here/'SeasonalTouchFixture.swift').read_text())
graph=plistlib.loads(subprocess.check_output(['plutil','-convert','xml1','-o','-',str(root/'Xiaobao.xcodeproj/project.pbxproj')]))
for obj in graph['objects'].values():
    path=obj.get('path','')
    if path=='XiaobaoApp.swift': obj.update(path=str(fixture),sourceTree='<absolute>')
    elif path in ('Sources','README.md') or path.startswith(('Sources/','Config/','Resources/','../xiaobao-backend/')):
        obj.update(path=str((root/path).resolve()),sourceTree='<absolute>')
    config=obj.get('buildSettings',{})
    if 'INFOPLIST_FILE' in config: config['INFOPLIST_FILE']=str((root/config['INFOPLIST_FILE']).resolve())
(project/'project.pbxproj').write_bytes(plistlib.dumps(graph))
bundle='cn.xiaobao.fixture.seasonal-touch'
spec="""
require 'xcodeproj'
p=Xcodeproj::Project.open('Xiaobao.xcodeproj')
h=p.targets.find{|x|x.name=='Xiaobao'}
p.build_configurations.each{|c|c.build_settings['TSCHEDULE_APP_BUNDLE_IDENTIFIER']=ARGV[0]}
t=p.new_target(:ui_test_bundle,'SeasonalTouchUITests',:ios,'26.0')
t.add_dependency(h)
t.add_file_references([p.main_group.new_file(ARGV[1])])
t.build_configurations.each{|c|c.build_settings.merge!('GENERATE_INFOPLIST_FILE'=>'YES','TEST_TARGET_NAME'=>'Xiaobao','PRODUCT_NAME'=>t.name,
    'PRODUCT_BUNDLE_IDENTIFIER'=>ARGV[0]+'.tests','SWIFT_VERSION'=>'5.0','TARGETED_DEVICE_FAMILY'=>'2','SUPPORTED_PLATFORMS'=>'iphonesimulator')}
p.save;s=Xcodeproj::XCScheme.new;s.configure_with_targets(h,t);s.save_as('Xiaobao.xcodeproj','SeasonalTouch')
"""
subprocess.run(['ruby','-e',spec,bundle,str(here/'SeasonalTouchUITests.swift')],cwd=out,check=True)
subprocess.run(['xcodebuild','-project',str(project),'-scheme','SeasonalTouch','-configuration','Release','-destination','id='+args.device,
                '-derivedDataPath',str(out/'DerivedData'),'-parallel-testing-enabled','NO','-collect-test-diagnostics','never','-jobs','4',
                'ONLY_ACTIVE_ARCH=YES','COMPILER_INDEX_STORE_ENABLE=NO','CODE_SIGN_IDENTITY=-','test'],check=True)
