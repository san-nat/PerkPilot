#!/usr/bin/env python3
"""Generate PerkPilot/PerkPilot.xcodeproj/project.pbxproj deterministically.

Usage: python3 tools/generate_project.py
Writes: PerkPilot/PerkPilot.xcodeproj/project.pbxproj

UUIDs are derived from object keys (uuid5), so re-running produces an
identical file. The generated pbxproj is checked in; regenerate after
adding/removing source files.
"""
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]          # ~/workspace/perkpilot
OUT = ROOT / "PerkPilot" / "PerkPilot.xcodeproj" / "project.pbxproj"


def uid(key: str) -> str:
    return uuid.uuid5(uuid.NAMESPACE_URL, f"perkpilot:{key}").hex[:24].upper()


APP_SOURCES = [
    "PerkPilot/PerkPilotApp.swift",
    "PerkPilot/Models/Cadence.swift",
    "PerkPilot/Models/CardItem.swift",
    "PerkPilot/Models/BenefitItem.swift",
    "PerkPilot/Models/TipItem.swift",
    "PerkPilot/Models/CompletionRecord.swift",
    "PerkPilot/Models/MutedReward.swift",
    "PerkPilot/Models/StatementModels.swift",
    "PerkPilot/Services/RecurrenceEngine.swift",
    "PerkPilot/Services/SeedLoader.swift",
    "PerkPilot/Services/AskParser.swift",
    "PerkPilot/Services/AskAnswerer.swift",
    "PerkPilot/Services/SpeechService.swift",
    "PerkPilot/Services/DiscoveryService.swift",
    "PerkPilot/Services/NotificationService.swift",
    "PerkPilot/Services/StatementParser.swift",
    "PerkPilot/Services/PDFStatementParser.swift",
    "PerkPilot/Services/CategoryEngine.swift",
    "PerkPilot/Services/RewardMatcher.swift",
    "PerkPilot/Services/TransactionStore.swift",
    "PerkPilot/Services/RewardsAdvisor.swift",
    "PerkPilot/Services/PortfolioAnalyzer.swift",
    "PerkPilot/Design/Theme.swift",
    "PerkPilot/Views/ContentView.swift",
    "PerkPilot/Views/TodayView.swift",
    "PerkPilot/Views/ChecklistDetailView.swift",
    "PerkPilot/Views/CardsView.swift",
    "PerkPilot/Views/CardDetailView.swift",
    "PerkPilot/Views/AddCardView.swift",
    "PerkPilot/Views/BenefitsLibraryView.swift",
    "PerkPilot/Views/NewsView.swift",
    "PerkPilot/Views/SettingsView.swift",
    "PerkPilot/Views/StatementImportView.swift",
    "PerkPilot/Views/StatementsView.swift",
    "PerkPilot/Views/RewardsCheckView.swift",
    "PerkPilot/Views/AdvisorView.swift",
    "PerkPilot/Views/AskView.swift",
]
SEED_JSONS = [
    "PerkPilot/Resources/SeedData-A.json",
    "PerkPilot/Resources/SeedData-B.json",
]
INFO_PLIST = "PerkPilot/Info.plist"
TEST_SOURCES = ["PerkPilotTests/PerkPilotTests.swift", "PerkPilotTests/StatementTests.swift", "PerkPilotTests/AdvisorTests.swift", "PerkPilotTests/AskTests.swift"]

FILETYPE = {p: "sourcecode.swift" for p in APP_SOURCES + TEST_SOURCES}
for _p in SEED_JSONS:
    FILETYPE[_p] = "text.json"
FILETYPE[INFO_PLIST] = "text.plist"

ALL_FILES = APP_SOURCES + SEED_JSONS + [INFO_PLIST] + TEST_SOURCES

# Precompute every UUID so sections can be emitted in canonical order.
U = {}


def reg(key: str) -> str:
    u = uid(key)
    U[key] = u
    return u


for p in ALL_FILES:
    reg("fileref:" + p)
    reg("buildfile:app:" + p)
    reg("buildfile:test:" + p)
reg("product:app")
reg("product:test")
reg("proxy:test->app")
reg("dep:test->app")
for g in ("main", "app", "models", "services", "views", "design", "resources", "tests", "products"):
    reg("group:" + g)
for ph in ("app-sources", "app-frameworks", "app-resources",
           "test-sources", "test-frameworks", "test-resources"):
    reg("phase:" + ph)
for t in ("app", "test"):
    reg("target:" + t)
reg("project")
for cl in ("project", "app", "test"):
    reg("cfglist:" + cl)
    for cfg in ("Debug", "Release"):
        reg(f"config:{cl}:{cfg}")


def section(lines: list, name: str) -> None:
    lines.append("")
    lines.append(f"/* Begin {name} section */")


def end_section(lines: list, name: str) -> None:
    lines.append(f"/* End {name} section */")


def gen() -> str:
    L: list[str] = []
    L.append("// !$*UTF8*$!")
    L.append("{")
    L.append("\tarchiveVersion = 1;")
    L.append("\tclasses = {")
    L.append("\t};")
    L.append("\tobjectVersion = 56;")
    L.append("\tobjects = {")

    # ---- PBXBuildFile ----
    section(L, "PBXBuildFile")
    for p in APP_SOURCES:
        L.append(f"\t\t{U['buildfile:app:' + p]} = {{isa = PBXBuildFile; fileRef = {U['fileref:' + p]}; }};")
    for _p in SEED_JSONS:
        L.append(f"\t\t{U['buildfile:app:' + _p]} = {{isa = PBXBuildFile; fileRef = {U['fileref:' + _p]}; }};")
    for p in TEST_SOURCES:
        L.append(f"\t\t{U['buildfile:test:' + p]} = {{isa = PBXBuildFile; fileRef = {U['fileref:' + p]}; }};")
    for _p in SEED_JSONS:
        L.append(f"\t\t{U['buildfile:test:' + _p]} = {{isa = PBXBuildFile; fileRef = {U['fileref:' + _p]}; }};")
    end_section(L, "PBXBuildFile")

    # ---- PBXContainerItemProxy ----
    section(L, "PBXContainerItemProxy")
    L.append(
        f"\t\t{U['proxy:test->app']} = {{isa = PBXContainerItemProxy; "
        f"containerPortal = {U['project']}; proxyType = 1; "
        f"remoteGlobalIDString = {U['target:app']}; remoteInfo = PerkPilot; }};"
    )
    end_section(L, "PBXContainerItemProxy")

    # ---- PBXFileReference ----
    section(L, "PBXFileReference")
    for p in ALL_FILES:
        name = Path(p).name
        L.append(
            f"\t\t{U['fileref:' + p]} = {{isa = PBXFileReference; "
            f"lastKnownFileType = {FILETYPE[p]}; name = {name}; path = {p}; sourceTree = SOURCE_ROOT; }};"
        )
    L.append(
        f"\t\t{U['product:app']} = {{isa = PBXFileReference; explicitFileType = wrapper.application; "
        f"includeInIndex = 0; path = PerkPilot.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    L.append(
        f"\t\t{U['product:test']} = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; "
        f"includeInIndex = 0; path = PerkPilotTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    end_section(L, "PBXFileReference")

    # ---- Phases ----
    def emit_phase(key: str, isa: str, members: list) -> None:
        L.append(f"\t\t{U['phase:' + key]} = {{")
        L.append(f"\t\t\tisa = {isa};")
        L.append("\t\t\tbuildActionMask = 2147483647;")
        L.append("\t\t\tfiles = (")
        for m in members:
            L.append(f"\t\t\t\t{m},")
        L.append("\t\t\t);")
        L.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        L.append("\t\t};")

    section(L, "PBXFrameworksBuildPhase")
    emit_phase("app-frameworks", "PBXFrameworksBuildPhase", [])
    emit_phase("test-frameworks", "PBXFrameworksBuildPhase", [])
    end_section(L, "PBXFrameworksBuildPhase")

    section(L, "PBXGroup")

    def emit_group(key: str, children: list, name=None, path=None) -> None:
        L.append(f"\t\t{U['group:' + key]} = {{")
        L.append("\t\t\tisa = PBXGroup;")
        L.append("\t\t\tchildren = (")
        for c in children:
            L.append(f"\t\t\t\t{c},")
        L.append("\t\t\t);")
        if name is not None:
            L.append(f"\t\t\tname = {name};")
        if path is not None:
            L.append(f"\t\t\tpath = {path};")
        L.append('\t\t\tsourceTree = "<group>";')
        L.append("\t\t};")

    def fr(p: str) -> str:
        return U["fileref:" + p]

    emit_group("models", [fr(p) for p in APP_SOURCES if "/Models/" in p], name="Models")
    emit_group("services", [fr(p) for p in APP_SOURCES if "/Services/" in p], name="Services")
    emit_group("views", [fr(p) for p in APP_SOURCES if "/Views/" in p], name="Views")
    emit_group("design", [fr(p) for p in APP_SOURCES if "/Design/" in p], name="Design")
    emit_group("resources", [fr(_p) for _p in SEED_JSONS], name="Resources")
    emit_group(
        "app",
        [fr("PerkPilot/PerkPilotApp.swift"), fr(INFO_PLIST),
         U["group:models"], U["group:services"], U["group:views"], U["group:design"], U["group:resources"]],
        name="PerkPilot", path="PerkPilot",
    )
    emit_group("tests", [fr(p) for p in TEST_SOURCES], name="PerkPilotTests", path="PerkPilotTests")
    emit_group("products", [U["product:app"], U["product:test"]], name="Products")
    emit_group("main", [U["group:app"], U["group:tests"], U["group:products"]])
    end_section(L, "PBXGroup")

    section(L, "PBXNativeTarget")

    def emit_target(key: str, name: str, product_type: str, phases: list, has_dep: bool) -> None:
        L.append(f"\t\t{U['target:' + key]} = {{")
        L.append("\t\t\tisa = PBXNativeTarget;")
        L.append(f"\t\t\tbuildConfigurationList = {U['cfglist:' + key]};")
        L.append("\t\t\tbuildPhases = (")
        for ph in phases:
            L.append(f"\t\t\t\t{ph},")
        L.append("\t\t\t);")
        L.append("\t\t\tbuildRules = (")
        L.append("\t\t\t);")
        L.append("\t\t\tdependencies = (")
        if has_dep:
            L.append(f"\t\t\t\t{U['dep:test->app']},")
        L.append("\t\t\t);")
        L.append(f"\t\t\tname = {name};")
        L.append(f"\t\t\tproductName = {name};")
        L.append(f"\t\t\tproductReference = {U['product:' + key]};")
        L.append(f'\t\t\tproductType = "{product_type}";')
        L.append("\t\t};")

    # (sources/resources phases emitted just below; UUIDs already fixed)
    emit_target("app", "PerkPilot", "com.apple.product-type.application",
                [U["phase:app-sources"], U["phase:app-frameworks"], U["phase:app-resources"]], False)
    emit_target("test", "PerkPilotTests", "com.apple.product-type.bundle.unit-test",
                [U["phase:test-sources"], U["phase:test-frameworks"], U["phase:test-resources"]], True)
    end_section(L, "PBXNativeTarget")

    section(L, "PBXProject")
    L.append(f"\t\t{U['project']} = {{")
    L.append("\t\t\tisa = PBXProject;")
    L.append("\t\t\tattributes = {")
    L.append("\t\t\t\tLastUpgradeCheck = 1500;")
    L.append("\t\t\t\tTargetAttributes = {")
    L.append(f"\t\t\t\t\t{U['target:app']} = {{")
    L.append("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    L.append("\t\t\t\t\t};")
    L.append(f"\t\t\t\t\t{U['target:test']} = {{")
    L.append("\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;")
    L.append(f"\t\t\t\t\t\tTestTargetID = {U['target:app']};")
    L.append("\t\t\t\t\t};")
    L.append("\t\t\t\t};")
    L.append("\t\t\t};")
    L.append(f"\t\t\tbuildConfigurationList = {U['cfglist:project']};")
    L.append("\t\t\tcompatibilityVersion = \"Xcode 15.0\";")
    L.append("\t\t\tdevelopmentRegion = en;")
    L.append("\t\t\thasScannedForEncodings = 0;")
    L.append("\t\t\tknownRegions = (")
    L.append("\t\t\t\ten,")
    L.append("\t\t\t);")
    L.append(f"\t\t\tmainGroup = {U['group:main']};")
    L.append("\t\t\tproductRefGroup = " + U["group:products"] + ";")
    L.append("\t\t\tprojectDirPath = \"\";")
    L.append("\t\t\tprojectRoot = \"\";")
    L.append("\t\t\ttargets = (")
    L.append(f"\t\t\t\t{U['target:app']},")
    L.append(f"\t\t\t\t{U['target:test']},")
    L.append("\t\t\t);")
    L.append("\t\t};")
    end_section(L, "PBXProject")

    section(L, "PBXResourcesBuildPhase")
    emit_phase("app-resources", "PBXResourcesBuildPhase", [U["buildfile:app:" + _p] for _p in SEED_JSONS])
    emit_phase("test-resources", "PBXResourcesBuildPhase", [U["buildfile:test:" + _p] for _p in SEED_JSONS])
    end_section(L, "PBXResourcesBuildPhase")

    section(L, "PBXSourcesBuildPhase")
    emit_phase("app-sources", "PBXSourcesBuildPhase",
               [U["buildfile:app:" + p] for p in APP_SOURCES])
    emit_phase("test-sources", "PBXSourcesBuildPhase",
               [U["buildfile:test:" + p] for p in TEST_SOURCES])
    end_section(L, "PBXSourcesBuildPhase")

    section(L, "PBXTargetDependency")
    L.append(f"\t\t{U['dep:test->app']} = {{isa = PBXTargetDependency; "
             f"target = {U['target:app']}; targetProxy = {U['proxy:test->app']}; }};")
    end_section(L, "PBXTargetDependency")

    # ---- Build configurations ----
    section(L, "XCBuildConfiguration")

    PROJECT_BASE = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION": "YES_AGGRESSIVE",
        "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_CONSTANT_CONVERSION": "YES",
        "CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS": "YES",
        "CLANG_WARN_DIRECT_OBJC_ISA_USAGE": "YES_ERROR",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_NON_LITERAL_NULL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_LITERAL_CONVERSION": "YES",
        "CLANG_WARN_OBJC_ROOT_CLASS": "YES_ERROR",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES",
        "CLANG_WARN_RANGE_LOOP_ANALYSIS": "YES",
        "CLANG_WARN_STRICT_PROTOTYPES": "YES",
        "CLANG_WARN_SUSPICIOUS_MOVE": "YES",
        "CLANG_WARN_UNGUARDED_AVAILABILITY": "YES_AGGRESSIVE",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "MTL_FAST_MATH": "YES",
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "5.9",
    }
    PROJECT_DEBUG = {
        "COPY_PHASE_STRIP": "NO",
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_DYNAMIC_NO_PIC": "NO",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": ("DEBUG=1", "$(inherited)"),
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    }
    PROJECT_RELEASE = {
        "COPY_PHASE_STRIP": "NO",
        "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
        "ENABLE_NS_ASSERTIONS": "NO",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": "-O",
    }

    APP_BASE = {
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": '""',
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": '"PerkPilot/Info.plist"',
        "LD_RUNPATH_SEARCH_PATHS": ("$(inherited)", "@executable_path/Frameworks"),
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.sannat.perkpilot",
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "TARGETED_DEVICE_FAMILY": "1",
    }
    APP_DEBUG = {
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_PREPROCESSOR_DEFINITIONS": ("DEBUG=1", "$(inherited)"),
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    }
    APP_RELEASE = {
        "COPY_PHASE_STRIP": "NO",
        "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": "-O",
    }

    TEST_BASE = {
        "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES": "YES",
        "BUNDLE_LOADER": '"$(TEST_HOST)"',
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "DEVELOPMENT_TEAM": '""',
        "GENERATE_INFOPLIST_FILE": "YES",
        "LD_RUNPATH_SEARCH_PATHS": ("$(inherited)", "@executable_path/Frameworks", "@loader_path/Frameworks"),
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.sannat.perkpilot.tests",
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "TARGETED_DEVICE_FAMILY": "1",
        "TEST_HOST": '"$(BUILT_PRODUCTS_DIR)/PerkPilot.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/PerkPilot"',
    }
    TEST_DEBUG = dict(APP_DEBUG)
    TEST_RELEASE = dict(APP_RELEASE)

    def emit_config(listname: str, cfg: str, settings: dict) -> None:
        L.append(f"\t\t{U[f'config:{listname}:{cfg}']} = {{")
        L.append("\t\t\tisa = XCBuildConfiguration;")
        L.append("\t\t\tbuildSettings = {")
        for k in sorted(settings):
            v = settings[k]
            if isinstance(v, tuple):
                inner = ", ".join(v)
                L.append(f"\t\t\t\t{k} = ({inner});")
            else:
                L.append(f"\t\t\t\t{k} = {v};")
        L.append("\t\t\t};")
        L.append(f"\t\t\tname = {cfg};")
        L.append("\t\t};")

    for cfg in ("Debug", "Release"):
        extra = PROJECT_DEBUG if cfg == "Debug" else PROJECT_RELEASE
        emit_config("project", cfg, {**PROJECT_BASE, **extra})
    for cfg in ("Debug", "Release"):
        extra = APP_DEBUG if cfg == "Debug" else APP_RELEASE
        emit_config("app", cfg, {**APP_BASE, **extra})
    for cfg in ("Debug", "Release"):
        extra = TEST_DEBUG if cfg == "Debug" else TEST_RELEASE
        emit_config("test", cfg, {**TEST_BASE, **extra})
    end_section(L, "XCBuildConfiguration")

    section(L, "XCConfigurationList")
    for cl in ("project", "app", "test"):
        L.append(f"\t\t{U['cfglist:' + cl]} = {{")
        L.append("\t\t\tisa = XCConfigurationList;")
        L.append("\t\t\tbuildConfigurations = (")
        L.append(f"\t\t\t\t{U[f'config:{cl}:Debug']},")
        L.append(f"\t\t\t\t{U[f'config:{cl}:Release']},")
        L.append("\t\t\t);")
        L.append("\t\t\tdefaultConfigurationIsVisible = 0;")
        L.append("\t\t\tdefaultConfigurationName = Release;")
        L.append("\t\t};")
    end_section(L, "XCConfigurationList")

    L.append("\t};")
    L.append(f"\trootObject = {U['project']};")
    L.append("}")
    L.append("")
    return "\n".join(L)


def main() -> None:
    # Sanity: every referenced source file must exist.
    missing = [p for p in ALL_FILES if not (ROOT / "PerkPilot" / p).exists()]
    if missing:
        raise SystemExit(f"missing source files: {missing}")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    text = gen()
    assert text.count("{") == text.count("}"), "unbalanced braces"
    OUT.write_text(text)
    print(f"Wrote {OUT} ({len(text)} bytes)")


if __name__ == "__main__":
    main()
