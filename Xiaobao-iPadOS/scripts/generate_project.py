#!/usr/bin/env python3
"""Generate the checked-in, dependency-free Xcode project from Swift and Metal sources."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = {}


def uid(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()


def add(key, **fields):
    identifier = uid(key)
    assert identifier not in objects
    objects[identifier] = fields
    return identifier


def encode(value, indent=0):
    tabs = "\t" * indent
    if isinstance(value, dict):
        lines = ["{"]
        for key, item in value.items():
            lines.append(f'{tabs}\t{json.dumps(key)} = {encode(item, indent + 1)};')
        return "\n".join(lines + [tabs + "}"])
    if isinstance(value, list):
        return "(\n" + "".join(tabs + "\t" + encode(item, indent + 1) + ",\n" for item in value) + tabs + ")"
    if isinstance(value, int):
        return str(value)
    return json.dumps(value, ensure_ascii=False)


source_builds = []
widget_builds = []
source_groups = []
source_types = {".swift": "sourcecode.swift", ".metal": "sourcecode.metal", ".h": "sourcecode.c.h"}
shared_activity_sources = {
    "Sources/ActivityWidget/LessonActivityAttributes.swift",
    "Sources/ActivityWidget/LessonActivityCard.swift",
    "Sources/Core/Personalization/LocalPersonalization.swift",
}
for folder in ["Core", "Native", "ActivityWidget"]:
    files = []
    source_root = ROOT / "Sources" / folder
    for path in sorted(source_root.rglob("*")):
        if not path.is_file() or path.suffix not in source_types:
            continue
        relative = path.relative_to(ROOT).as_posix()
        ref = add(relative, isa="PBXFileReference", lastKnownFileType=source_types[path.suffix],
                  name=path.name, path=path.relative_to(source_root).as_posix(), sourceTree="<group>")
        files.append(ref)
        if path.suffix != ".h" and (folder != "ActivityWidget" or relative in shared_activity_sources):
            source_builds.append(add(relative + ":build", isa="PBXBuildFile", fileRef=ref))
        if path.suffix == ".swift" and (folder == "ActivityWidget" or relative in shared_activity_sources):
            widget_builds.append(add(relative + ":widget-build", isa="PBXBuildFile", fileRef=ref))
    source_groups.append(add(folder, isa="PBXGroup", children=files, path=folder, sourceTree="<group>"))
sources = add("Sources", isa="PBXGroup", children=source_groups, path="Sources", sourceTree="<group>")
assets = add("Assets", isa="PBXFileReference", lastKnownFileType="folder.assetcatalog", path="Resources/Assets.xcassets", sourceTree="<group>")
asset_build = add("Assets:build", isa="PBXBuildFile", fileRef=assets)
calendar = add("HSCalendar", isa="PBXFileReference", lastKnownFileType="text.json",
               path="../xiaobao-backend/src/provider/academic-calendar-hs-2026-2027.json", sourceTree="SOURCE_ROOT")
calendar_build = add("HSCalendar:build", isa="PBXBuildFile", fileRef=calendar)
policy = add("PolicyCopy", isa="PBXFileReference", lastKnownFileType="text.json",
             path="Resources/PolicyCopy.json", sourceTree="SOURCE_ROOT")
policy_build = add("PolicyCopy:build", isa="PBXBuildFile", fileRef=policy)
privacy = add("PrivacyManifest", isa="PBXFileReference", lastKnownFileType="text.xml",
              path="Config/PrivacyInfo.xcprivacy", sourceTree="<group>")
privacy_build = add("PrivacyManifest:build", isa="PBXBuildFile", fileRef=privacy)
portal_refs = [add(path, isa="PBXFileReference", lastKnownFileType="sourcecode.javascript",
                   path=path, sourceTree="SOURCE_ROOT") for path in [
    "Sources/Native/SchoolPortalSync/PortalProjection.js", "Sources/Native/SchoolPortalSync/PortalRead.js",
    "Sources/Native/SchoolPortalLogin/PortalLogin.js"]]
portal_builds = [add(ref + ":resource", isa="PBXBuildFile", fileRef=ref) for ref in portal_refs]
info = add("Info", isa="PBXFileReference", lastKnownFileType="text.plist.xml", path="Config/Info.plist", sourceTree="<group>")
widget_info = add("LessonActivityInfo", isa="PBXFileReference", lastKnownFileType="text.plist.xml",
                  path="Config/LessonActivity-Info.plist", sourceTree="<group>")
readme = add("README", isa="PBXFileReference", lastKnownFileType="net.daringfireball.markdown", path="README.md", sourceTree="<group>")
product = add("Product", isa="PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="Xiaobao.app", sourceTree="BUILT_PRODUCTS_DIR")
widget_product = add("LessonActivityProduct", isa="PBXFileReference", explicitFileType="wrapper.app-extension",
                     includeInIndex=0, path="LessonActivityWidget.appex", sourceTree="BUILT_PRODUCTS_DIR")
products = add("Products", isa="PBXGroup", children=[product, widget_product], name="Products", sourceTree="<group>")
main = add("Main", isa="PBXGroup", children=[sources, assets, calendar, policy, privacy, *portal_refs, info, widget_info, readme, products], sourceTree="<group>")
source_phase = add("Compile", isa="PBXSourcesBuildPhase", buildActionMask=2147483647, files=source_builds, runOnlyForDeploymentPostprocessing=0)
resource_phase = add("Resources", isa="PBXResourcesBuildPhase", buildActionMask=2147483647, files=[asset_build, calendar_build, policy_build, privacy_build, *portal_builds], runOnlyForDeploymentPostprocessing=0)
framework_phase = add("Frameworks", isa="PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
widget_source_phase = add("LessonActivityCompile", isa="PBXSourcesBuildPhase", buildActionMask=2147483647,
                          files=widget_builds, runOnlyForDeploymentPostprocessing=0)
widget_asset = add("LessonActivityAssets:build", isa="PBXBuildFile", fileRef=assets)
widget_resources = add("LessonActivityResources", isa="PBXResourcesBuildPhase", buildActionMask=2147483647,
                       files=[widget_asset], runOnlyForDeploymentPostprocessing=0)
embedded = add("LessonActivityEmbed:build", isa="PBXBuildFile", fileRef=widget_product,
               settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
embed_phase = add("EmbedFoundationExtensions", isa="PBXCopyFilesBuildPhase", buildActionMask=2147483647,
                  dstPath="", dstSubfolderSpec=13, files=[embedded], name="Embed Foundation Extensions",
                  runOnlyForDeploymentPostprocessing=0)

project_configs = []
target_configs = []
widget_configs = []
for configuration in ["Debug", "Release"]:
    debug = configuration == "Debug"
    project_configs.append(add("Project:" + configuration, isa="XCBuildConfiguration", name=configuration, buildSettings={
        "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "SDKROOT": "iphoneos",
        "IPHONEOS_DEPLOYMENT_TARGET": "26.0", "SWIFT_VERSION": "5.0",
        "TSCHEDULE_APP_BUNDLE_IDENTIFIER": "cn.xiaobao.ipados.prototype",
        "MARKETING_VERSION": "0.3", "CURRENT_PROJECT_VERSION": "3",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if debug else "-O",
        "DEBUG_INFORMATION_FORMAT": "dwarf" if debug else "dwarf-with-dsym",
        "ENABLE_TESTABILITY": "YES" if debug else "NO",
        "ONLY_ACTIVE_ARCH": "YES" if debug else "NO",
    }))
    target_configs.append(add("Target:" + configuration, isa="XCBuildConfiguration", name=configuration, buildSettings={
        "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "$(TSCHEDULE_APP_BUNDLE_IDENTIFIER)",
        "INFOPLIST_FILE": "Config/Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "CODE_SIGN_STYLE": "Automatic", "TARGETED_DEVICE_FAMILY": "2",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO",
        "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO", "ENABLE_PREVIEWS": "YES",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES": "AppIconLight AppIconDark",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) DEBUG" if debug else "$(inherited)",
        "SWIFT_STRICT_CONCURRENCY": "targeted",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    }))
    widget_configs.append(add("LessonActivity:" + configuration, isa="XCBuildConfiguration", name=configuration, buildSettings={
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "PRODUCT_BUNDLE_IDENTIFIER": "$(TSCHEDULE_APP_BUNDLE_IDENTIFIER).lesson-activity",
        "INFOPLIST_FILE": "Config/LessonActivity-Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
        "CODE_SIGN_STYLE": "Automatic", "TARGETED_DEVICE_FAMILY": "2",
        "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator", "SUPPORTS_MACCATALYST": "NO",
        "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO", "SKIP_INSTALL": "YES",
        "APPLICATION_EXTENSION_API_ONLY": "YES",
        "SWIFT_STRICT_CONCURRENCY": "targeted",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
    }))

project_config_list = add("ProjectConfigurations", isa="XCConfigurationList", buildConfigurations=project_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
target_config_list = add("TargetConfigurations", isa="XCConfigurationList", buildConfigurations=target_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
widget_config_list = add("LessonActivityConfigurations", isa="XCConfigurationList", buildConfigurations=widget_configs,
                        defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
widget = add("LessonActivityWidget", isa="PBXNativeTarget", buildConfigurationList=widget_config_list,
             buildPhases=[widget_source_phase, widget_resources], buildRules=[], dependencies=[],
             name="LessonActivityWidget", productName="LessonActivityWidget", productReference=widget_product,
             productType="com.apple.product-type.app-extension")
proxy = add("LessonActivityProxy", isa="PBXContainerItemProxy", containerPortal=uid("Project"), proxyType=1,
            remoteGlobalIDString=widget, remoteInfo="LessonActivityWidget")
dependency = add("LessonActivityDependency", isa="PBXTargetDependency", target=widget, targetProxy=proxy)
target = add("Xiaobao", isa="PBXNativeTarget", buildConfigurationList=target_config_list,
             buildPhases=[source_phase, framework_phase, resource_phase, embed_phase], buildRules=[], dependencies=[dependency],
             name="Xiaobao", productName="Xiaobao", productReference=product, productType="com.apple.product-type.application")
project = add("Project", isa="PBXProject", attributes={"LastSwiftUpdateCheck": "2600", "LastUpgradeCheck": "2600",
              "TargetAttributes": {target: {"CreatedOnToolsVersion": "26.0"}, widget: {"CreatedOnToolsVersion": "26.0"}}},
              buildConfigurationList=project_config_list, compatibilityVersion="Xcode 14.0", developmentRegion="zh-Hans",
              hasScannedForEncodings=0, knownRegions=["zh-Hans", "en", "Base"], mainGroup=main,
              productRefGroup=products, projectDirPath="", projectRoot="", targets=[target, widget])
document = {"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project}

destination = ROOT / "Xiaobao.xcodeproj"
destination.mkdir(exist_ok=True)
(destination / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode(document) + "\n")
scheme_directory = destination / "xcshareddata" / "xcschemes"
scheme_directory.mkdir(parents=True, exist_ok=True)
buildable = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Xiaobao.app" BlueprintName="Xiaobao" ReferencedContainer="container:Xiaobao.xcodeproj"/>'
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable}</BuildActionEntry></BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables/></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(scheme_directory / "Xiaobao.xcscheme").write_text(scheme)
workspace = destination / "project.xcworkspace"
workspace.mkdir(exist_ok=True)
(workspace / "contents.xcworkspacedata").write_text('<?xml version="1.0" encoding="UTF-8"?><Workspace version="1.0"><FileRef location="self:"/></Workspace>\n')
assert len(source_builds) + len(widget_builds) == len(shared_activity_sources) + sum(
    len(list((ROOT / "Sources").rglob(ext))) for ext in ["*.swift", "*.metal"])
print(f"Generated Xcode project: {len(source_builds)} app sources, {len(widget_builds)} activity extension sources, iPadOS 26.")
