"""Test archive contents and file operations in an isolated directory."""
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import build


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / "source"
        shutil.copytree(ROOT, self.root, ignore=shutil.ignore_patterns(".git", "dist", ".venv", "__pycache__"))

    def archive(self, folder="out"):
        return build.build_archive(self.root, self.base / folder, check_report=False)

    def report(self):
        (self.root / "dist").mkdir(exist_ok=True)
        (self.root / "dist/test-results.json").write_text(json.dumps({
            "passed": True, "source_sha256": build.validation_inputs(self.root)}), encoding="utf-8")

    def test_archive_is_allowlisted_utf8_mod_only(self):
        with zipfile.ZipFile(self.archive()) as z:
            self.assertIsNone(z.testzip())
            self.assertEqual(len(z.namelist()), 16)
            for name in z.namelist():
                self.assertTrue(name.startswith("ZhanFX/"))
                self.assertNotIn("..", name)
                self.assertNotIn("mods.txt", name)
                self.assertNotIn("tests/", name)
                z.read(name).decode("utf-8")
            self.assertEqual(z.read("ZhanFX/enabled.txt").strip(), b"")
            manifest = json.loads(z.read("ZhanFX/FILES.sha256.json"))
            self.assertEqual(set(manifest), set(z.namelist()) - {"ZhanFX/FILES.sha256.json"})
            for name, expected in manifest.items():
                self.assertEqual(build.digest(z.read(name)), expected)

    def test_deterministic_and_checksum_correct(self):
        one, two = self.archive("one"), self.archive("two")
        self.assertEqual(one.read_bytes(), two.read_bytes())
        self.assertEqual(one.with_suffix(".zip.sha256").read_text(encoding="utf-8").split()[0], build.digest(one.read_bytes()))

    def test_unexpected_runtime_file_is_rejected(self):
        (self.root / "ZhanFX/local-secret.txt").write_text("fixture", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "allowlist"):
            self.archive()

    def test_missing_runtime_file_is_rejected(self):
        (self.root / "ZhanFX/Scripts/zhanfx/i18n.lua").unlink()
        with self.assertRaisesRegex(ValueError, "allowlist"):
            self.archive()

    def test_version_mismatch_is_rejected(self):
        path = self.root / "compatibility.json"
        meta = json.loads(path.read_text(encoding="utf-8")); meta["version"] = "9.0.0"
        path.write_text(json.dumps(meta), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "versions differ"):
            self.archive()

    def test_fresh_report_required_and_source_changes_invalidate_it(self):
        with self.assertRaises(FileNotFoundError):
            build.require_fresh_report(self.root)
        self.report(); build.require_fresh_report(self.root)
        path = self.root / "ZhanFX/Scripts/config.lua"
        path.write_text(path.read_text(encoding="utf-8") + "\n-- changed\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "stale"):
            build.require_fresh_report(self.root)

    def test_failed_report_cannot_build(self):
        self.report(); path = self.root / "dist/test-results.json"
        report = json.loads(path.read_text(encoding="utf-8")); report["passed"] = False
        path.write_text(json.dumps(report), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "failed"):
            build.build_archive(self.root, self.base / "out")

    def test_extraction_replace_and_remove_preserve_shared_files(self):
        # Exercise the documented MANUAL file layout in an isolated temp directory.
        game = self.base / "game"
        mods = game / "platform/steam/ue4ss/Mods"; mods.mkdir(parents=True)
        shared = {mods / "mods.txt": b"Other : 1\n", mods / "Other/Scripts/main.lua": b"-- other",
                  game / "platform/steam/ue4ss/UE4SS.dll": b"fake shared loader"}
        for path, data in shared.items():
            path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
        archive = self.archive()
        with zipfile.ZipFile(archive) as z:
            z.extractall(mods); z.extractall(mods)  # identical repeated installation
        owned = mods / "ZhanFX"
        self.assertTrue((owned / "Scripts/main.lua").is_file())
        (owned / "obsolete.lua").write_text("-- old", encoding="utf-8")
        config = self.root / "ZhanFX/Scripts/config.lua"
        config.write_text(config.read_text(encoding="utf-8").replace('Language = "auto"', 'Language = "en"'), encoding="utf-8")
        replacement = self.archive("replacement")
        shutil.rmtree(owned)  # only this known temp-directory Mod is replaced
        with zipfile.ZipFile(replacement) as z:
            z.extractall(mods)
        self.assertFalse((owned / "obsolete.lua").exists())
        self.assertIn('Language = "en"', (owned / "Scripts/config.lua").read_text(encoding="utf-8"))
        (owned / "enabled.txt").unlink()  # manual persistent disable (no mods.txt entry)
        self.assertNotIn("ZhanFX", (mods / "mods.txt").read_text(encoding="utf-8"))
        shutil.rmtree(owned)
        self.assertFalse(owned.exists())
        for path, data in shared.items():
            self.assertEqual(path.read_bytes(), data)


if __name__ == "__main__":
    unittest.main()
