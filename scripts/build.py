"""Build a deterministic, Mod-only ZIP. Never inspect or deploy to a game install."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LUA_FILES = (
    "Scripts/main.lua", "Scripts/config.lua",
    *(f"Scripts/zhanfx/{name}.lua" for name in
      ("adapter", "constants", "core", "i18n", "notice", "presenter", "runtime", "ue")),
)
MOD_FILES = (*LUA_FILES, "enabled.txt")
DOC_FILES = {"README.md": "ZhanFX/README.md", "LICENSE": "ZhanFX/LICENSE",
             "THIRD_PARTY_NOTICES.md": "ZhanFX/THIRD_PARTY_NOTICES.md",
             "compatibility.json": "ZhanFX/compatibility.json"}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def validation_inputs(root: Path = ROOT) -> dict[str, str]:
    paths = [root / "ZhanFX" / name for name in MOD_FILES]
    paths += [root / name for name in DOC_FILES]
    paths += sorted((root / "tests").glob("*.lua")) + sorted((root / "tests").glob("*.py"))
    paths += [root / "scripts/build.py", root / "requirements-dev.txt"]
    return {p.relative_to(root).as_posix(): digest(p.read_bytes()) for p in sorted(paths)}


def player_files(root: Path = ROOT) -> tuple[dict[str, bytes], dict]:
    mod = root / "ZhanFX"
    # Reject unexpected files rather than accidentally distributing a DLL, dump or local config.
    actual = {p.relative_to(mod).as_posix() for p in mod.rglob("*") if p.is_file()}
    if actual != set(MOD_FILES) or any(p.is_symlink() for p in mod.rglob("*")):
        raise ValueError("ZhanFX source tree differs from the player-file allowlist")
    meta = json.loads((root / "compatibility.json").read_text(encoding="utf-8"))
    version = meta["version"]
    if meta["name"] != "ZhanFX" or not re.fullmatch(r"\d+\.\d+\.\d+(?:-[a-z0-9.]+)?", version):
        raise ValueError("Invalid product/version metadata")
    constants = (mod / "Scripts/zhanfx/constants.lua").read_text(encoding="utf-8")
    if f'Version = "{version}"' not in constants:
        raise ValueError("Lua and metadata versions differ")
    if (mod / "enabled.txt").read_bytes().strip():
        raise ValueError("enabled.txt must be empty")
    files = {"ZhanFX/" + name: (mod / name).read_bytes() for name in MOD_FILES}
    files.update({target: (root / source).read_bytes() for source, target in DOC_FILES.items()})
    for name, data in files.items():
        data.decode("utf-8", errors="strict")
        if b"\xef\xbf\xbd" in data:
            raise ValueError("Replacement character in " + name)
    return files, meta


def require_fresh_report(root: Path = ROOT) -> None:
    report = json.loads((root / "dist/test-results.json").read_text(encoding="utf-8"))
    if report.get("passed") is not True or report.get("source_sha256") != validation_inputs(root):
        raise ValueError("Tests failed or are stale; run tests/run_tests.py first")


def build_archive(root: Path, output: Path, *, check_report: bool = True) -> Path:
    files, meta = player_files(root)
    if check_report:
        require_fresh_report(root)
    manifest = {name: digest(data) for name, data in sorted(files.items())}
    files["ZhanFX/FILES.sha256.json"] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
    output.mkdir(parents=True, exist_ok=True)
    archive = output / f"ZhanFX-{meta['version']}-manual.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for name, data in sorted(files.items()):
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            z.writestr(info, data)
    with zipfile.ZipFile(archive) as z:
        if z.testzip() is not None or set(z.namelist()) != set(files):
            raise ValueError("ZIP integrity check failed")
        for name, expected in manifest.items():
            if digest(z.read(name)) != expected:
                raise ValueError("ZIP file hash mismatch: " + name)
    archive.with_suffix(".zip.sha256").write_text(
        digest(archive.read_bytes()) + "  " + archive.name + "\n", encoding="ascii")
    return archive


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    try:
        archive = build_archive(ROOT, args.output.resolve())
    except (ValueError, OSError, KeyError) as exc:
        parser.exit(1, str(exc) + "\n")
    print(json.dumps({"archive": str(archive), "sha256": digest(archive.read_bytes()),
                      "game_directory_modified": False}))


if __name__ == "__main__":
    main()
