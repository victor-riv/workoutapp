#!/usr/bin/env python3
"""Generates WorkoutTracker.xcodeproj + Info.plists from the Swift sources.

XcodeGen can't run on this Linux box and the Mac has no shell runner, so we
emit the .pbxproj directly. The project is simple (2 targets, no resources,
no external packages), which keeps this safe.

Paste-first v1: no GoogleSignIn SPM package, no OAuth client IDs. The
GoogleSignIn-guarded code compiles out via #if canImport; auto-import can
be re-added later as a 30-second Xcode GUI step.

Usage:
    generate_xcodeproj.py [--out DIR]
"""

import os
import sys

APP_SOURCES = [
    "WorkoutApp/App/ContentView.swift",
    "WorkoutApp/App/WorkoutTrackerApp.swift",
    "WorkoutApp/Logic/EmailWorkoutParser.swift",
    "WorkoutApp/Logic/PlateCalculator.swift",
    "WorkoutApp/Logic/SetRepParser.swift",
    "WorkoutApp/Models/Exercise.swift",
    "WorkoutApp/Models/GymProfile.swift",
    "WorkoutApp/Models/WorkoutDay.swift",
    "WorkoutApp/Models/WorkoutExercise.swift",
    "WorkoutApp/Models/WorkoutSet.swift",
    "WorkoutApp/Services/Email/EmailWorkoutSource.swift",
    "WorkoutApp/Services/Email/GmailService.swift",
    "WorkoutApp/Services/Email/GoogleAuthProvider.swift",
    "WorkoutApp/Services/Import/MockWorkoutSource.swift",
    "WorkoutApp/Services/Import/WorkoutImporter.swift",
    "WorkoutApp/Services/Import/WorkoutSource.swift",
    "WorkoutApp/Services/ServiceFactory.swift",
    "WorkoutApp/Services/TrueCoach/KeychainHelper.swift",
    "WorkoutApp/Services/TrueCoach/TrueCoachAPIClient.swift",
    "WorkoutApp/Services/TrueCoach/TrueCoachDTO.swift",
    "WorkoutApp/Services/WeightSuggestionService.swift",
    "WorkoutApp/Views/Calculator/PlateCalculatorView.swift",
    "WorkoutApp/Views/Exercise/ExerciseDetailView.swift",
    "WorkoutApp/Views/Settings/SettingsView.swift",
    "WorkoutApp/Views/Today/TodayWorkoutView.swift",
    "WorkoutApp/Views/Today/PasteWorkoutView.swift",
]

TEST_SOURCES = [
    "WorkoutAppTests/EmailWorkoutParserTests.swift",
    "WorkoutAppTests/PlateCalculatorTests.swift",
    "WorkoutAppTests/SetRepParserTests.swift",
]

BUNDLE_ID = "com.victor.workouttracker"
DEPLOYMENT_TARGET = "17.0"


class IDGen:
    def __init__(self):
        self.n = 0

    def new(self, hint=""):
        self.n += 1
        # 24-char uppercase hex, deterministic
        return ("%024X" % self.n)


def info_plist_app():
    return """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>CFBundleDevelopmentRegion</key>
\t<string>$(DEVELOPMENT_LANGUAGE)</string>
\t<key>CFBundleDisplayName</key>
\t<string>WorkoutTracker</string>
\t<key>CFBundleExecutable</key>
\t<string>$(EXECUTABLE_NAME)</string>
\t<key>CFBundleIdentifier</key>
\t<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
\t<key>CFBundleInfoDictionaryVersion</key>
\t<string>6.0</string>
\t<key>CFBundleName</key>
\t<string>$(PRODUCT_NAME)</string>
\t<key>CFBundlePackageType</key>
\t<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
\t<key>CFBundleShortVersionString</key>
\t<string>$(MARKETING_VERSION)</string>
\t<key>CFBundleVersion</key>
\t<string>$(CURRENT_PROJECT_VERSION)</string>
\t<key>LSRequiresIPhoneOS</key>
\t<true/>
\t<key>UILaunchScreen</key>
\t<dict/>
\t<key>UIRequiredDeviceCapabilities</key>
\t<array>
\t\t<string>armv7</string>
\t</array>
\t<key>UISupportedInterfaceOrientations</key>
\t<array>
\t\t<string>UIInterfaceOrientationPortrait</string>
\t\t<string>UIInterfaceOrientationLandscapeLeft</string>
\t\t<string>UIInterfaceOrientationLandscapeRight</string>
\t</array>
\t<key>UISupportedInterfaceOrientations~ipad</key>
\t<array>
\t\t<string>UIInterfaceOrientationPortrait</string>
\t\t<string>UIInterfaceOrientationPortraitUpsideDown</string>
\t\t<string>UIInterfaceOrientationLandscapeLeft</string>
\t\t<string>UIInterfaceOrientationLandscapeRight</string>
\t</array>
</dict>
</plist>
"""


def info_plist_tests():
    return """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>CFBundleDevelopmentRegion</key>
\t<string>$(DEVELOPMENT_LANGUAGE)</string>
\t<key>CFBundleExecutable</key>
\t<string>$(EXECUTABLE_NAME)</string>
\t<key>CFBundleIdentifier</key>
\t<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
\t<key>CFBundleInfoDictionaryVersion</key>
\t<string>6.0</string>
\t<key>CFBundleName</key>
\t<string>$(PRODUCT_NAME)</string>
\t<key>CFBundlePackageType</key>
\t<string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>
\t<key>CFBundleShortVersionString</key>
\t<string>1.0</string>
\t<key>CFBundleVersion</key>
\t<string>1</string>
</dict>
</plist>
"""


def main():
    out = sys.argv[2] if len(sys.argv) > 2 and sys.argv[1] == "--out" else "."

    ids = IDGen()
    c = {}  # hint -> uuid

    def uid(hint):
        if hint not in c:
            c[hint] = ids.new(hint)
        return c[hint]

    # ---- file references ----
    filerefs = {}
    for src in APP_SOURCES + TEST_SOURCES:
        filerefs[src] = uid("fileref " + src)
    filerefs["WorkoutApp/Info.plist"] = uid("fileref app plist")
    filerefs["WorkoutAppTests/Info.plist"] = uid("fileref tests plist")
    app_product = uid("product app")
    tests_product = uid("product tests")

    # ---- build files ----
    buildfiles = {}
    for src in APP_SOURCES + TEST_SOURCES:
        buildfiles[src] = uid("buildfile " + src)

    # ---- groups ----
    # group path -> (uuid, [children hints])
    groups = {}

    def group(hint, path=None):
        g = uid("group " + hint)
        groups[hint] = (g, path)
        return g

    g_main = group("main")
    g_proj = group("WorkoutTracker")
    g_frameworks = group("Frameworks")
    g_products = group("Products")
    # source subgroups mirroring folders
    subgroups = {}
    for sub, path in [
        ("App", "WorkoutApp/App"),
        ("Logic", "WorkoutApp/Logic"),
        ("Models", "WorkoutApp/Models"),
        ("Services", "WorkoutApp/Services"),
        ("Services/Email", "WorkoutApp/Services/Email"),
        ("Services/Import", "WorkoutApp/Services/Import"),
        ("Services/TrueCoach", "WorkoutApp/Services/TrueCoach"),
        ("Views", "WorkoutApp/Views"),
        ("Views/Calculator", "WorkoutApp/Views/Calculator"),
        ("Views/Exercise", "WorkoutApp/Views/Exercise"),
        ("Views/Settings", "WorkoutApp/Views/Settings"),
        ("Views/Today", "WorkoutApp/Views/Today"),
        ("WorkoutAppTests", "WorkoutAppTests"),
    ]:
        subgroups[sub] = group(sub, path)

    # ---- phases / targets / configs ----
    app_src_phase = uid("sources app")
    app_fw_phase = uid("frameworks app")
    app_res_phase = uid("resources app")
    tests_src_phase = uid("sources tests")
    tests_fw_phase = uid("frameworks tests")
    tests_res_phase = uid("resources tests")
    app_target = uid("target app")
    tests_target = uid("target tests")
    dep_proxy = uid("container proxy")
    target_dep = uid("target dep tests->app")
    project = uid("project")
    cfg_project_debug = uid("cfg project debug")
    cfg_project_release = uid("cfg project release")
    cfg_app_debug = uid("cfg app debug")
    cfg_app_release = uid("cfg app release")
    cfg_tests_debug = uid("cfg tests debug")
    cfg_tests_release = uid("cfg tests release")
    cfglist_project = uid("cfglist project")
    cfglist_app = uid("cfglist app")
    cfglist_tests = uid("cfglist tests")

    def basename(p):
        return p.rsplit("/", 1)[-1]

    def parent_group(src):
        # map source path -> subgroup hint
        if src.startswith("WorkoutAppTests/"):
            return "WorkoutAppTests"
        rel = src[len("WorkoutApp/"):]
        parts = rel.split("/")[:-1]
        return "/".join(parts)

    lines = []
    A = lines.append

    A("// !$*UTF8*$!")
    A("{")
    A("\tarchiveVersion = 1;")
    A("\tclasses = {")
    A("\t};")
    A("\tobjectVersion = 56;")
    A("\tobjects = {")

    # PBXBuildFile
    A("")
    A("/* Begin PBXBuildFile section */")
    for src in APP_SOURCES + TEST_SOURCES:
        A(f"\t\t{buildfiles[src]} /* {basename(src)} in Sources */ = {{isa = PBXBuildFile; fileRef = {filerefs[src]} /* {basename(src)} */; }};")
    A("/* End PBXBuildFile section */")

    # PBXContainerItemProxy
    A("")
    A("/* Begin PBXContainerItemProxy section */")
    A(f"\t\t{dep_proxy} /* PBXContainerItemProxy */ = {{")
    A("\t\t\tisa = PBXContainerItemProxy;")
    A(f"\t\t\tcontainerPortal = {project} /* Project object */;")
    A("\t\t\tproxyType = 1;")
    A(f"\t\t\tremoteGlobalIDString = {app_target};")
    A(f"\t\t\tremoteInfo = WorkoutTracker;")
    A("\t\t};")
    A("/* End PBXContainerItemProxy section */")

    # PBXFileReference
    A("")
    A("/* Begin PBXFileReference section */")
    for src in APP_SOURCES + TEST_SOURCES:
        A(f"\t\t{filerefs[src]} /* {basename(src)} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {basename(src)}; path = {basename(src)}; sourceTree = \"<group>\"; }};")
    A(f"\t\t{filerefs['WorkoutApp/Info.plist']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; name = Info.plist; path = WorkoutApp/Info.plist; sourceTree = \"<group>\"; }};")
    A(f"\t\t{filerefs['WorkoutAppTests/Info.plist']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; name = Info.plist; path = WorkoutAppTests/Info.plist; sourceTree = \"<group>\"; }};")
    A(f"\t\t{app_product} /* WorkoutTracker.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = WorkoutTracker.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    A(f"\t\t{tests_product} /* WorkoutTrackerTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = WorkoutTrackerTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
    A("/* End PBXFileReference section */")

    # PBXFrameworksBuildPhase
    A("")
    A("/* Begin PBXFrameworksBuildPhase section */")
    A(f"\t\t{app_fw_phase} /* Frameworks */ = {{")
    A("\t\t\tisa = PBXFrameworksBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = (")
    A("\t\t\t);")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A(f"\t\t{tests_fw_phase} /* Frameworks */ = {{")
    A("\t\t\tisa = PBXFrameworksBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = (")
    A("\t\t\t);")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A("/* End PBXFrameworksBuildPhase section */")

    # PBXGroup
    A("")
    A("/* Begin PBXGroup section */")
    # main group children
    A(f"\t\t{g_main} = {{")
    A("\t\t\tisa = PBXGroup;")
    A("\t\t\tchildren = (")
    A(f"\t\t\t\t{groups['WorkoutTracker'][0]} /* WorkoutTracker */,")
    A(f"\t\t\t\t{g_frameworks} /* Frameworks */,")
    A(f"\t\t\t\t{g_products} /* Products */,")
    A("\t\t\t);")
    A("\t\t\tsourceTree = \"<group>\";")
    A("\t\t};")
    # project group children: subgroups + Info.plist
    proj_children = []
    for sub in ["App", "Logic", "Models", "Services", "Views"]:
        proj_children.append(f"\t\t\t\t{subgroups[sub]} /* {sub} */,")
    proj_children.append(f"\t\t\t\t{filerefs['WorkoutApp/Info.plist']} /* Info.plist */,")
    proj_children.append(f"\t\t\t\t{subgroups['WorkoutAppTests']} /* WorkoutAppTests */,")
    A(f"\t\t{groups['WorkoutTracker'][0]} /* WorkoutTracker */ = {{")
    A("\t\t\tisa = PBXGroup;")
    A("\t\t\tchildren = (")
    for ch in proj_children:
        A(ch)
    A("\t\t\t);")
    A("\t\t\tname = WorkoutTracker;")
    A("\t\t\tsourceTree = \"<group>\";")
    A("\t\t};")
    # Services + Views intermediate groups (real paths; also hold loose files
    # like ServiceFactory.swift that live directly in the folder)
    for parent, kids in [("Services", ["Services/Email", "Services/Import", "Services/TrueCoach"]),
                         ("Views", ["Views/Calculator", "Views/Exercise", "Views/Settings", "Views/Today"])]:
        _, ppath = groups[parent]
        A(f"\t\t{subgroups[parent]} /* {parent} */ = {{")
        A("\t\t\tisa = PBXGroup;")
        A("\t\t\tchildren = (")
        for k in kids:
            A(f"\t\t\t\t{subgroups[k]} /* {k.split('/')[-1]} */,")
        if ppath:
            for src in APP_SOURCES + TEST_SOURCES:
                if src.startswith(ppath + "/") and "/" not in src[len(ppath) + 1:]:
                    A(f"\t\t\t\t{filerefs[src]} /* {basename(src)} */,")
        A("\t\t\t);")
        A(f"\t\t\tname = {parent};")
        if ppath:
            A(f"\t\t\tpath = {ppath};")
        A("\t\t\tsourceTree = \"<group>\";")
        A("\t\t};")
    # leaf subgroups with paths
    for sub, g_uuid in subgroups.items():
        _, path = groups[sub]
        if "/" not in sub or sub in ("Services", "Views"):
            if sub in ("Services", "Views"):
                continue
        children = []
        if path:
            for src in APP_SOURCES + TEST_SOURCES:
                # direct children only: files in deeper folders belong to their own subgroup
                if src.startswith(path + "/") and "/" not in src[len(path) + 1:]:
                    children.append(f"\t\t\t\t{filerefs[src]} /* {basename(src)} */,")
        if sub == "WorkoutAppTests":
            children.append(f"\t\t\t\t{filerefs['WorkoutAppTests/Info.plist']} /* Info.plist */,")
        A(f"\t\t{g_uuid} /* {sub.split('/')[-1]} */ = {{")
        A("\t\t\tisa = PBXGroup;")
        A("\t\t\tchildren = (")
        for ch in children:
            A(ch)
        A("\t\t\t);")
        if path:
            A(f"\t\t\tname = \"{sub.split('/')[-1]}\";")
            # groups nested under Services/Views use paths relative to their parent
            # (a full path here would resolve against the parent's path and double up)
            ppath = path.rsplit("/", 1)[-1] if "/" in sub else path
            A(f"\t\t\tpath = {ppath};")
        else:
            A(f"\t\t\tname = {sub};")
        A("\t\t\tsourceTree = \"<group>\";")
        A("\t\t};")
    # Frameworks + Products groups
    A(f"\t\t{g_frameworks} /* Frameworks */ = {{")
    A("\t\t\tisa = PBXGroup;")
    A("\t\t\tchildren = (")
    A("\t\t\t);")
    A("\t\t\tname = Frameworks;")
    A("\t\t\tsourceTree = \"<group>\";")
    A("\t\t};")
    A(f"\t\t{g_products} /* Products */ = {{")
    A("\t\t\tisa = PBXGroup;")
    A("\t\t\tchildren = (")
    A(f"\t\t\t\t{app_product} /* WorkoutTracker.app */,")
    A(f"\t\t\t\t{tests_product} /* WorkoutTrackerTests.xctest */,")
    A("\t\t\t);")
    A("\t\t\tname = Products;")
    A("\t\t\tsourceTree = \"<group>\";")
    A("\t\t};")
    A("/* End PBXGroup section */")

    # PBXNativeTarget
    A("")
    A("/* Begin PBXNativeTarget section */")
    A(f"\t\t{app_target} /* WorkoutTracker */ = {{")
    A("\t\t\tisa = PBXNativeTarget;")
    A(f"\t\t\tbuildConfigurationList = {cfglist_app} /* Build configuration list for PBXNativeTarget \"WorkoutTracker\" */;")
    A("\t\t\tbuildPhases = (")
    A(f"\t\t\t\t{app_src_phase} /* Sources */,")
    A(f"\t\t\t\t{app_fw_phase} /* Frameworks */,")
    A(f"\t\t\t\t{app_res_phase} /* Resources */,")
    A("\t\t\t);")
    A("\t\t\tbuildRules = (")
    A("\t\t\t);")
    A("\t\t\tdependencies = (")
    A("\t\t\t);")
    A("\t\t\tname = WorkoutTracker;")
    A(f"\t\t\tproductName = WorkoutTracker;")
    A(f"\t\t\tproductReference = {app_product} /* WorkoutTracker.app */;")
    A("\t\t\tproductType = \"com.apple.product-type.application\";")
    A("\t\t};")
    A(f"\t\t{tests_target} /* WorkoutTrackerTests */ = {{")
    A("\t\t\tisa = PBXNativeTarget;")
    A(f"\t\t\tbuildConfigurationList = {cfglist_tests} /* Build configuration list for PBXNativeTarget \"WorkoutTrackerTests\" */;")
    A("\t\t\tbuildPhases = (")
    A(f"\t\t\t\t{tests_src_phase} /* Sources */,")
    A(f"\t\t\t\t{tests_fw_phase} /* Frameworks */,")
    A(f"\t\t\t\t{tests_res_phase} /* Resources */,")
    A("\t\t\t);")
    A("\t\t\tbuildRules = (")
    A("\t\t\t);")
    A("\t\t\tdependencies = (")
    A(f"\t\t\t\t{target_dep} /* PBXTargetDependency */,")
    A("\t\t\t);")
    A("\t\t\tname = WorkoutTrackerTests;")
    A(f"\t\t\tproductName = WorkoutTrackerTests;")
    A(f"\t\t\tproductReference = {tests_product} /* WorkoutTrackerTests.xctest */;")
    A("\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";")
    A("\t\t};")
    A("/* End PBXNativeTarget section */")

    # PBXProject
    A("")
    A("/* Begin PBXProject section */")
    A(f"\t\t{project} /* Project object */ = {{")
    A("\t\t\tisa = PBXProject;")
    A("\t\t\tattributes = {")
    A("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    A("\t\t\t\tLastUpgradeCheck = 1700;")
    A("\t\t\t\tTargetAttributes = {")
    A(f"\t\t\t\t\t{app_target} = {{")
    A("\t\t\t\t\t\tCreatedOnToolsVersion = 17.0;")
    A("\t\t\t\t\t};")
    A(f"\t\t\t\t\t{tests_target} = {{")
    A("\t\t\t\t\t\tCreatedOnToolsVersion = 17.0;")
    A("\t\t\t\t\t\tTestTargetID = WorkoutTracker;")
    A("\t\t\t\t\t};")
    A("\t\t\t\t};")
    A("\t\t\t};")
    A(f"\t\t\tbuildConfigurationList = {cfglist_project} /* Build configuration list for PBXProject \"WorkoutTracker\" */;")
    A("\t\t\tcompatibilityVersion = \"Xcode 15.0\";")
    A("\t\t\tdevelopmentRegion = en;")
    A("\t\t\thasScannedForEncodings = 0;")
    A("\t\t\tknownRegions = (")
    A("\t\t\t\ten,")
    A("\t\t\t\tBase,")
    A("\t\t\t);")
    A(f"\t\t\tmainGroup = {g_main};")
    A(f"\t\t\tproductRefGroup = {g_products} /* Products */;")
    A("\t\t\tprojectDirPath = \"\";")
    A("\t\t\tprojectRoot = \"\";")
    A("\t\t\ttargets = (")
    A(f"\t\t\t\t{app_target} /* WorkoutTracker */,")
    A(f"\t\t\t\t{tests_target} /* WorkoutTrackerTests */,")
    A("\t\t\t);")
    A("\t\t};")
    A("/* End PBXProject section */")

    # PBXResourcesBuildPhase
    A("")
    A("/* Begin PBXResourcesBuildPhase section */")
    for phase, name in [(app_res_phase, "app"), (tests_res_phase, "tests")]:
        A(f"\t\t{phase} /* Resources */ = {{")
        A("\t\t\tisa = PBXResourcesBuildPhase;")
        A("\t\t\tbuildActionMask = 2147483647;")
        A("\t\t\tfiles = (")
        A("\t\t\t);")
        A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        A("\t\t};")
    A("/* End PBXResourcesBuildPhase section */")

    # PBXSourcesBuildPhase
    A("")
    A("/* Begin PBXSourcesBuildPhase section */")
    A(f"\t\t{app_src_phase} /* Sources */ = {{")
    A("\t\t\tisa = PBXSourcesBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = (")
    for src in APP_SOURCES:
        A(f"\t\t\t\t{buildfiles[src]} /* {basename(src)} in Sources */,")
    A("\t\t\t);")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A(f"\t\t{tests_src_phase} /* Sources */ = {{")
    A("\t\t\tisa = PBXSourcesBuildPhase;")
    A("\t\t\tbuildActionMask = 2147483647;")
    A("\t\t\tfiles = (")
    for src in TEST_SOURCES:
        A(f"\t\t\t\t{buildfiles[src]} /* {basename(src)} in Sources */,")
    A("\t\t\t);")
    A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    A("\t\t};")
    A("/* End PBXSourcesBuildPhase section */")

    # PBXTargetDependency
    A("")
    A("/* Begin PBXTargetDependency section */")
    A(f"\t\t{target_dep} /* PBXTargetDependency */ = {{")
    A("\t\t\tisa = PBXTargetDependency;")
    A(f"\t\t\ttarget = {app_target} /* WorkoutTracker */;")
    A(f"\t\t\ttargetProxy = {dep_proxy} /* PBXContainerItemProxy */;")
    A("\t\t};")
    A("/* End PBXTargetDependency section */")

    # XCBuildConfiguration
    A("")
    A("/* Begin XCBuildConfiguration section */")

    def config(uuid, name, settings):
        A(f"\t\t{uuid} /* {name} */ = {{")
        A("\t\t\tisa = XCBuildConfiguration;")
        A("\t\t\tbuildSettings = {")
        for k, v in settings.items():
            A(f"\t\t\t\t{k} = {v};")
        A("\t\t\t};")
        A(f"\t\t\tname = {name};")
        A("\t\t};")

    proj_common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
        "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
        "ENABLE_NS_ASSERTIONS": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "MARKETING_VERSION": "0.1.0",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SDKROOT": "iphoneos",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
        "SWIFT_VERSION": "5.0",
    }
    proj_debug = dict(proj_common)
    proj_debug.update({
        "ENABLE_NS_ASSERTIONS": "YES",
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_COMPILATION_MODE": "singlefile",
        "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
    })
    config(cfg_project_debug, "Debug", proj_debug)
    config(cfg_project_release, "Release", proj_common)

    app_common = {
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "ENABLE_PREVIEWS": "YES",
        "INFOPLIST_FILE": "WorkoutApp/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks")',
        "MARKETING_VERSION": "0.1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": '"1,2"',
    }
    app_debug = dict(app_common)
    app_debug["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
    config(cfg_app_debug, "Debug", app_debug)
    config(cfg_app_release, "Release", app_common)

    tests_common = {
        "BUNDLE_LOADER": '"$(TEST_HOST)"',
        "CODE_SIGN_STYLE": "Automatic",
        "INFOPLIST_FILE": "WorkoutAppTests/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks")',
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + ".tests",
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": '"1,2"',
        "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/WorkoutTracker.app/WorkoutTracker"',
    }
    tests_debug = dict(tests_common)
    tests_debug["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
    config(cfg_tests_debug, "Debug", tests_debug)
    config(cfg_tests_release, "Release", tests_common)
    A("/* End XCBuildConfiguration section */")

    # XCConfigurationList
    A("")
    A("/* Begin XCConfigurationList section */")
    for lst, name, dbg, rel in [
        (cfglist_project, 'Build configuration list for PBXProject "WorkoutTracker"', cfg_project_debug, cfg_project_release),
        (cfglist_app, 'Build configuration list for PBXNativeTarget "WorkoutTracker"', cfg_app_debug, cfg_app_release),
        (cfglist_tests, 'Build configuration list for PBXNativeTarget "WorkoutTrackerTests"', cfg_tests_debug, cfg_tests_release),
    ]:
        A(f"\t\t{lst} /* {name} */ = {{")
        A("\t\t\tisa = XCConfigurationList;")
        A("\t\t\tbuildConfigurations = (")
        A(f"\t\t\t\t{dbg} /* Debug */,")
        A(f"\t\t\t\t{rel} /* Release */,")
        A("\t\t\t);")
        A("\t\t\tdefaultConfigurationIsVisible = 0;")
        A("\t\t\tdefaultConfigurationName = Release;")
        A("\t\t};")
    A("/* End XCConfigurationList section */")

    A("\t};")
    A(f"\trootObject = {project} /* Project object */;")
    A("}")

    # ---- write outputs ----
    proj_dir = os.path.join(out, "WorkoutTracker.xcodeproj")
    os.makedirs(proj_dir, exist_ok=True)
    with open(os.path.join(proj_dir, "project.pbxproj"), "w") as f:
        f.write("\n".join(lines) + "\n")
    with open(os.path.join(out, "WorkoutApp", "Info.plist"), "w") as f:
        f.write(info_plist_app())
    with open(os.path.join(out, "WorkoutAppTests", "Info.plist"), "w") as f:
        f.write(info_plist_tests())
    print("wrote", os.path.join(proj_dir, "project.pbxproj"))
    print("wrote", os.path.join(out, "WorkoutApp", "Info.plist"))
    print("wrote", os.path.join(out, "WorkoutAppTests", "Info.plist"))


if __name__ == "__main__":
    main()
