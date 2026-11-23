"""Scripts/set-version: the one place a release version enters the project."""
import importlib.machinery
import importlib.util
import io
import json
import plistlib
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load():
    loader = importlib.machinery.SourceFileLoader("set_version", str(ROOT / "Scripts" / "set-version"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


set_version = load()

# Two build configurations, as in Captalo.xcodeproj, plus a test target that
# carries no version.
LEGACY = """\
\t\tA /* Debug */ = {
\t\t\tbuildSettings = {
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.thecreativetoken.captalo;
\t\t\t};
\t\t};
\t\tB /* Release */ = {
\t\t\tbuildSettings = {
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.thecreativetoken.captalo;
\t\t\t};
\t\t};
\t\tC /* Other */ = {
\t\t\tbuildSettings = {
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t};
\t\t};
"""


class ParseTests(unittest.TestCase):
    def test_release_and_beta_versions_parse(self):
        self.assertEqual(set_version.parse("1.2.3"), set_version.Version(1, 2, 3, None))
        self.assertEqual(set_version.parse("1.0.0-beta.3"), set_version.Version(1, 0, 0, 3))

    def test_other_shapes_are_rejected(self):
        for text in ["1.0", "v1.0.0", "1.0.0-beta", "1.0.0-rc.1", "1.0.0-beta.0", "01.0.0", "1.0.0 "]:
            with self.subTest(text=text), self.assertRaises(set_version.VersionError):
                set_version.parse(text)

    def test_a_beta_sorts_before_its_release(self):
        order = ["1.0.0-beta.2", "1.0.0-beta.10", "1.0.0", "1.0.1-beta.1", "1.0.1", "1.1.0"]
        parsed = [set_version.parse(v) for v in order]
        self.assertEqual(sorted(parsed, key=set_version.Version.order), parsed)

    def test_text_round_trips(self):
        for text in ["1.0.0", "2.3.4-beta.5"]:
            self.assertEqual(str(set_version.parse(text)), text)


class ApplyTests(unittest.TestCase):
    def test_first_adoption_writes_every_configuration(self):
        text, state = set_version.apply(LEGACY, set_version.parse("1.0.0-beta.2"))
        self.assertEqual(text.count("MARKETING_VERSION = 1.0.0;"), 2)
        self.assertEqual(text.count('CAPTALO_PRERELEASE = "beta.2";'), 2)
        self.assertEqual(text.count("CURRENT_PROJECT_VERSION = 2;"), 2)
        self.assertEqual(state, set_version.State(set_version.parse("1.0.0-beta.2"), 2))
        self.assertNotIn("SWIFT_VERSION = 6.0;\n\t\t\t\tCAPTALO", text)

    def test_next_version_increments_the_build_number(self):
        beta2, _ = set_version.apply(LEGACY, set_version.parse("1.0.0-beta.2"))
        release, state = set_version.apply(beta2, set_version.parse("1.0.0"))
        self.assertEqual(release.count('CAPTALO_PRERELEASE = "";'), 2)
        self.assertEqual(release.count("MARKETING_VERSION = 1.0.0;"), 2)
        self.assertEqual(state.build, 3)
        self.assertEqual(set_version.read(release), state)

    def test_same_version_changes_nothing(self):
        beta2, _ = set_version.apply(LEGACY, set_version.parse("1.0.0-beta.2"))
        again, state = set_version.apply(beta2, set_version.parse("1.0.0-beta.2"))
        self.assertEqual(again, beta2)
        self.assertEqual(state.build, 2)

    def test_an_older_version_is_refused(self):
        release, _ = set_version.apply(LEGACY, set_version.parse("1.0.0"))
        with self.assertRaisesRegex(set_version.VersionError, "older than the project's 1.0.0"):
            set_version.apply(release, set_version.parse("1.0.0-beta.3"))

    def test_configurations_that_disagree_are_refused(self):
        broken = LEGACY.replace("MARKETING_VERSION = 1.0;", "MARKETING_VERSION = 1.1;", 1)
        with self.assertRaisesRegex(set_version.VersionError, "MARKETING_VERSION"):
            set_version.apply(broken, set_version.parse("1.0.0"))

    def test_a_project_without_a_version_is_refused(self):
        with self.assertRaisesRegex(set_version.VersionError, "no MARKETING_VERSION"):
            set_version.apply("buildSettings = {\n};\n", set_version.parse("1.0.0"))


class CommandTests(unittest.TestCase):
    def run_main(self, project, *args):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = set_version.main([*args, "--project", str(project)])
        return code, out.getvalue(), err.getvalue()

    def test_set_then_show_then_check(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "project.pbxproj"
            project.write_text(LEGACY, encoding="utf-8")
            self.assertEqual(self.run_main(project, "1.0.0-beta.3")[:2], (0, "1.0.0-beta.3 (build 2)\n"))
            self.assertEqual(self.run_main(project, "--show")[:2], (0, "1.0.0-beta.3 (build 2)\n"))
            self.assertEqual(self.run_main(project, "--check", "1.0.0-beta.3")[0], 0)
            code, _, err = self.run_main(project, "--check", "1.0.0")
            self.assertEqual(code, 1)
            self.assertIn("project carries 1.0.0-beta.3, expected 1.0.0", err)

    def test_refusal_leaves_the_file_untouched(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "project.pbxproj"
            project.write_text(LEGACY, encoding="utf-8")
            code, _, err = self.run_main(project, "1.0")
            self.assertEqual(code, 2)
            self.assertIn("X.Y.Z or X.Y.Z-beta.N", err)
            self.assertEqual(project.read_text(encoding="utf-8"), LEGACY)

    def make_app(self, root, short, build, prerelease):
        app = Path(root) / "Captalo.app"
        (app / "Contents" / "Resources").mkdir(parents=True)
        with open(app / "Contents" / "Info.plist", "wb") as handle:
            plistlib.dump({"CFBundleShortVersionString": short, "CFBundleVersion": build}, handle)
        (app / "Contents" / "Resources" / "build-info.json").write_text(
            json.dumps({"commit": "abc", "prerelease": prerelease}), encoding="utf-8")
        return app

    def test_check_with_an_app_compares_the_built_bundle(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "project.pbxproj"
            project.write_text(LEGACY, encoding="utf-8")
            self.run_main(project, "1.0.0-beta.3")
            good = self.make_app(Path(tmp) / "good", "1.0.0", "2", "beta.3")
            self.assertEqual(self.run_main(project, "--check", "1.0.0-beta.3", "--app", str(good))[0], 0)
            stale = self.make_app(Path(tmp) / "stale", "1.0.0", "2", "beta.2")
            code, _, err = self.run_main(project, "--check", "1.0.0-beta.3", "--app", str(stale))
            self.assertEqual(code, 1)
            self.assertIn("bundle carries 1.0.0-beta.2 (build 2)", err)
            old_build = self.make_app(Path(tmp) / "old", "1.0.0", "1", "beta.3")
            self.assertEqual(self.run_main(project, "--check", "1.0.0-beta.3", "--app", str(old_build))[0], 1)

    def test_check_with_a_missing_app_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            project = Path(tmp) / "project.pbxproj"
            project.write_text(LEGACY, encoding="utf-8")
            self.run_main(project, "1.0.0")
            code, _, err = self.run_main(project, "--check", "1.0.0", "--app", str(Path(tmp) / "none.app"))
            self.assertEqual(code, 2)
            self.assertIn("cannot read", err)

    def test_the_real_project_has_a_readable_version(self):
        state = set_version.read((ROOT / "Captalo.xcodeproj" / "project.pbxproj").read_text(encoding="utf-8"))
        self.assertGreaterEqual(state.build, 1)


if __name__ == "__main__":
    unittest.main()
