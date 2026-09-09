import re
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
IDA_OBJC_EXPORT = REPO_ROOT.parent / "SolarlandClient-aug26OBJC.h"
IDA_HEADER_EXPORT = REPO_ROOT.parent / "SolarlandClient-aug26.h"
IDA_C_EXPORT = REPO_ROOT.parent / "SolarlandClient-aug26.c"
CLASS_MANIFEST = REPO_ROOT / "JiguangClassNames.inc"
JIGUANG_PREFIXES = ("JPUSH", "JPush", "JCORE", "JCore", "JCommon", "JG")


def ida_defined_class_names(source: str) -> set[str]:
    definitions = re.findall(
        r"/\*\s*\d+\s*\*/\s*struct\s+([A-Za-z_][A-Za-z0-9_]*)\s*\n\{",
        source,
    )
    return {name for name in definitions if name.startswith(JIGUANG_PREFIXES)}


def ida_method_owner_names(source: str) -> set[str]:
    owners = re.findall(r"[-+]\[([A-Za-z_][A-Za-z0-9_]*)\s+[^]]+\]", source)
    return {name for name in owners if name.startswith(JIGUANG_PREFIXES)}


def manifest_class_names(source: str) -> set[str]:
    return set(re.findall(r'JPD_JIGUANG_CLASS\("([A-Za-z_][A-Za-z0-9_]*)"\)', source))


class JiguangCoverageTests(unittest.TestCase):
    def test_manifest_matches_the_ida_class_inventory(self) -> None:
        ida_classes = ida_defined_class_names(IDA_OBJC_EXPORT.read_text())
        ida_classes |= ida_defined_class_names(IDA_HEADER_EXPORT.read_text())
        ida_classes |= ida_method_owner_names(IDA_C_EXPORT.read_text())
        manifest_classes = manifest_class_names(CLASS_MANIFEST.read_text())

        self.assertEqual(275, len(ida_classes))
        self.assertEqual(ida_classes, manifest_classes)

    def test_tweak_uses_the_exact_class_manifest(self) -> None:
        tweak_source = (REPO_ROOT / "Tweak.xm").read_text()

        self.assertIn('#include "JiguangClassNames.inc"', tweak_source)
        self.assertNotIn("strncmp(className, prefix", tweak_source)

    def test_every_declared_method_has_a_safe_neutralization_path(self) -> None:
        neutralizer_source = (REPO_ROOT / "JPDMethodNeutralizer.mm").read_text()

        self.assertIn("JPDShouldPreserveSelector", neutralizer_source)
        self.assertIn("JPDShouldNeutralizeSelector", neutralizer_source)
        self.assertIn('"registerDevice"', neutralizer_source)
        self.assertIn('strcmp(name, "init")', neutralizer_source)
        self.assertIn("_objc_msgForward", neutralizer_source)
        for return_encoding in ("f", "d", "D", ":", "*"):
            self.assertIn(f"case '{return_encoding}':", neutralizer_source)

    def test_class_discovery_is_race_safe_and_repeats_after_image_loads(self) -> None:
        tweak_source = (REPO_ROOT / "Tweak.xm").read_text()
        neutralizer_source = (REPO_ROOT / "JPDMethodNeutralizer.mm").read_text()

        self.assertIn("objc_copyClassList", tweak_source)
        self.assertIn("_dyld_register_func_for_add_image", tweak_source)
        self.assertIn("JPDLastMethodCounts", tweak_source)
        self.assertIn("JPDClassNeedsScan", tweak_source)
        self.assertIn("objc_getClassList(NULL, 0)", tweak_source)
        self.assertIn("JPDCompletedInitialScan", tweak_source)
        self.assertNotIn("hookedClassNames", tweak_source + neutralizer_source)
        self.assertIn(
            "method_getImplementation(method) == replacement", neutralizer_source
        )

    def test_readme_names_the_packaged_injection_target(self) -> None:
        filter_source = (REPO_ROOT / "JPushDisable.plist").read_text()
        target_bundle = re.search(r"<string>(com\.[^<]+)</string>", filter_source).group(1)

        self.assertIn(f"`{target_bundle}`", (REPO_ROOT / "README.md").read_text())

    def test_neutralizer_zeroes_each_return_abi_without_running_sdk_methods(self) -> None:
        with tempfile.TemporaryDirectory() as build_directory:
            executable = Path(build_directory) / "neutralizer-runtime"
            subprocess.run(
                [
                    "xcrun",
                    "clang++",
                    "-std=c++17",
                    "-fobjc-arc",
                    "-framework",
                    "Foundation",
                    "-I",
                    str(REPO_ROOT),
                    str(REPO_ROOT / "JPDMethodNeutralizer.mm"),
                    str(REPO_ROOT / "tests" / "neutralizer_runtime.mm"),
                    "-o",
                    str(executable),
                ],
                check=True,
            )
            subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    unittest.main()
