#!/usr/bin/env python3
"""Deterministically bind existing sources to the macOS application and unit tests."""
from pathlib import Path
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "apps/macos"

def identifier(name):
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

def main():
    objects = {}
    def obj(identity, isa, **fields):
        key = identifier(identity); objects[key] = {"isa": isa, **fields}; return key
    source_refs, source_builds = [], []
    for path in sorted((APP / "Sources").rglob("*.swift")):
        relative = str(path.relative_to(APP))
        reference = obj(relative, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=relative, sourceTree="SOURCE_ROOT")
        source_refs.append(reference); source_builds.append(obj("build:" + relative, "PBXBuildFile", fileRef=reference))
    test_refs, test_builds = [], []
    for path in sorted((APP / "Tests/Unit").glob("*.swift")):
        relative = str(path.relative_to(APP))
        reference = obj(relative, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=relative, sourceTree="SOURCE_ROOT")
        test_refs.append(reference); test_builds.append(obj("build:" + relative, "PBXBuildFile", fileRef=reference))
    info = obj("info", "PBXFileReference", lastKnownFileType="text.plist.xml", path="Configuration/Info.plist", sourceTree="SOURCE_ROOT")
    app_product = obj("app-product", "PBXFileReference", explicitFileType="wrapper.application", path="Aqmino.app", sourceTree="BUILT_PRODUCTS_DIR")
    test_product = obj("test-product", "PBXFileReference", explicitFileType="wrapper.cfbundle", path="AqminoMacTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
    sources = obj("sources", "PBXGroup", children=source_refs, name="Sources", sourceTree="<group>")
    tests = obj("tests", "PBXGroup", children=test_refs, name="Tests", sourceTree="<group>")
    products = obj("products", "PBXGroup", children=[app_product, test_product], name="Products", sourceTree="<group>")
    group = obj("root-group", "PBXGroup", children=[sources, tests, info, products], sourceTree="<group>")
    package = obj("package", "XCLocalSwiftPackageReference", relativePath="../../packages/AqminoCore")
    app_core = obj("app-core", "XCSwiftPackageProductDependency", package=package, productName="AqminoCore")
    test_core = obj("test-core", "XCSwiftPackageProductDependency", package=package, productName="AqminoCore")
    app_core_build = obj("app-core-build", "PBXBuildFile", productRef=app_core)
    test_core_build = obj("test-core-build", "PBXBuildFile", productRef=test_core)
    app_source_phase = obj("app-source-phase", "PBXSourcesBuildPhase", buildActionMask="2147483647", files=source_builds, runOnlyForDeploymentPostprocessing="0")
    test_source_phase = obj("test-source-phase", "PBXSourcesBuildPhase", buildActionMask="2147483647", files=test_builds, runOnlyForDeploymentPostprocessing="0")
    app_frameworks = obj("app-frameworks", "PBXFrameworksBuildPhase", buildActionMask="2147483647", files=[app_core_build], runOnlyForDeploymentPostprocessing="0")
    test_frameworks = obj("test-frameworks", "PBXFrameworksBuildPhase", buildActionMask="2147483647", files=[test_core_build], runOnlyForDeploymentPostprocessing="0")
    localization_refs = []
    for language in ["en", "zh-Hans"]:
        localization_refs.append(obj("info-localization-" + language, "PBXFileReference", lastKnownFileType="text.plist.strings", name=language, path="Resources/" + language + ".lproj/InfoPlist.strings", sourceTree="SOURCE_ROOT"))
    strings = obj("info-localizations", "PBXVariantGroup", children=localization_refs, name="InfoPlist.strings", sourceTree="<group>")
    objects[group]["children"].insert(-1, strings)
    localized_build = obj("info-localizations-build", "PBXBuildFile", fileRef=strings)
    icon = obj("app-icon", "PBXFileReference", lastKnownFileType="image.icns", path="Resources/Aqmino.icns", sourceTree="SOURCE_ROOT")
    objects[group]["children"].insert(-1, icon)
    icon_build = obj("app-icon-build", "PBXBuildFile", fileRef=icon)
    support = obj("support-assets", "PBXFileReference", lastKnownFileType="folder", path="Resources/Support", sourceTree="SOURCE_ROOT")
    objects[group]["children"].insert(-1, support)
    support_build = obj("support-assets-build", "PBXBuildFile", fileRef=support)
    resources = obj("app-resources", "PBXResourcesBuildPhase", buildActionMask="2147483647", files=[localized_build, icon_build, support_build], runOnlyForDeploymentPostprocessing="0")
    common = {"SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "13.0", "SWIFT_VERSION": "5.0", "CODE_SIGN_STYLE": "Manual", "CODE_SIGN_IDENTITY": "-", "CLANG_ENABLE_MODULES": "YES"}
    def configurations(prefix, settings):
        configs = []
        for name in ["Debug", "Release"]:
            values = dict(common, **settings)
            values["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone" if name == "Debug" else "-O"
            if name == "Debug": values.update({"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)", "ENABLE_TESTABILITY": "YES"})
            configs.append(obj(prefix + name, "XCBuildConfiguration", name=name, buildSettings=values))
        return obj(prefix + "list", "XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible="0", defaultConfigurationName="Release")
    project_configs = configurations("project-config-", {})
    app_configs = configurations("app-config-", {"PRODUCT_NAME": "Aqmino", "PRODUCT_BUNDLE_IDENTIFIER": "local.aqmino.macos", "INFOPLIST_FILE": "Configuration/Info.plist", "GENERATE_INFOPLIST_FILE": "NO", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"], "ENABLE_APP_SANDBOX": "NO"})
    test_configs = configurations("test-config-", {"PRODUCT_NAME": "AqminoMacTests", "PRODUCT_BUNDLE_IDENTIFIER": "local.aqmino.macos.tests", "GENERATE_INFOPLIST_FILE": "YES", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Aqmino.app/Contents/MacOS/Aqmino", "BUNDLE_LOADER": "$(TEST_HOST)", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@loader_path/../Frameworks", "@executable_path/../Frameworks"]})
    app_target = obj("app-target", "PBXNativeTarget", name="Aqmino", productName="Aqmino", productReference=app_product, productType="com.apple.product-type.application", buildConfigurationList=app_configs, buildPhases=[app_source_phase, app_frameworks, resources], buildRules=[], dependencies=[], packageProductDependencies=[app_core])
    project_id = identifier("project")
    proxy = obj("app-proxy", "PBXContainerItemProxy", containerPortal=project_id, proxyType="1", remoteGlobalIDString=app_target, remoteInfo="Aqmino")
    dependency = obj("test-dependency", "PBXTargetDependency", target=app_target, targetProxy=proxy)
    test_target = obj("test-target", "PBXNativeTarget", name="AqminoMacTests", productName="AqminoMacTests", productReference=test_product, productType="com.apple.product-type.bundle.unit-test", buildConfigurationList=test_configs, buildPhases=[test_source_phase, test_frameworks], buildRules=[], dependencies=[dependency], packageProductDependencies=[test_core])
    obj("project", "PBXProject", attributes={"LastUpgradeCheck": "1600", "TargetAttributes": {test_target: {"TestTargetID": app_target}}}, buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings="0", knownRegions=["en", "zh-Hans", "Base"], mainGroup=group, productRefGroup=products, projectDirPath="", projectRoot="", targets=[app_target, test_target], packageReferences=[package])
    def encode(value, depth=0):
        indent = "\t" * depth
        if isinstance(value, dict):
            return "{\n" + "\n".join(indent + "\t" + json.dumps(str(k)) + " = " + encode(v, depth + 1) + ";" for k, v in value.items()) + "\n" + indent + "}"
        if isinstance(value, list):
            return "(\n" + "\n".join(indent + "\t" + encode(v, depth + 1) + "," for v in value) + "\n" + indent + ")"
        return json.dumps(str(value), ensure_ascii=False)
    project = APP / "Aqmino.xcodeproj"; project.mkdir(exist_ok=True)
    payload = {"archiveVersion": "1", "classes": {}, "objectVersion": "56", "objects": objects, "rootObject": project_id}
    (project / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode(payload) + "\n")
    scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")
    build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(build, "BuildActionEntries")
    entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES", buildForProfiling="YES", buildForArchiving="YES", buildForAnalyzing="YES")
    def reference(parent, target, name, product):
        ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=target, BuildableName=product, BlueprintName=name, ReferencedContainer="container:Aqmino.xcodeproj")
    reference(entry, app_target, "Aqmino", "Aqmino.app")
    test_action = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="NO")
    variables = ET.SubElement(test_action, "EnvironmentVariables")
    ET.SubElement(variables, "EnvironmentVariable", key="AQMINO_TEST_HOST", value="1", isEnabled="YES")
    testable = ET.SubElement(ET.SubElement(test_action, "Testables"), "TestableReference", skipped="NO")
    reference(testable, test_target, "AqminoMacTests", "AqminoMacTests.xctest")
    launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", debugServiceExtension="internal", allowLocationSimulation="YES")
    reference(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), app_target, "Aqmino", "Aqmino.app")
    ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    ET.indent(scheme)
    scheme_dir = project / "xcshareddata/xcschemes"; scheme_dir.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(scheme).write(scheme_dir / "Aqmino.xcscheme", encoding="utf-8", xml_declaration=True)
    print(f"Generated {project}: {len(source_refs)} application sources, {len(test_refs)} unit test files")

if __name__ == "__main__":
    main()
