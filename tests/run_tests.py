"""Execute the actual Lua 5.4 sources plus packaging checks; reports stay in dist/."""
from __future__ import annotations

from datetime import datetime, timezone
import io
import json
import platform
from pathlib import Path
import sys
import unittest

from lupa.lua54 import LuaRuntime
import lupa

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from build import validation_inputs  # noqa: E402


def convert(value):
    if hasattr(value, "items"):
        pairs = list(value.items())
        if pairs and all(isinstance(k, int) for k, _ in pairs):
            return [convert(value[i]) for i in range(1, len(pairs) + 1)]
        return {str(k): convert(v) for k, v in pairs}
    return value


def main() -> int:
    suites = []
    sources = sorted((ROOT / "ZhanFX/Scripts").rglob("*.lua"))
    for name in ("core_spec.lua", "runtime_spec.lua", "i18n_spec.lua"):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute('package.path = ... .. ";" .. package.path',
                    (ROOT / "ZhanFX/Scripts/?.lua").as_posix() + ";" + (ROOT / "tests/?.lua").as_posix())
        for path in sources:
            lua.execute("assert(load(...))", path.read_text(encoding="utf-8"))
        suite = convert(lua.execute((ROOT / "tests" / name).read_text(encoding="utf-8")))
        suites.append(suite)
        print(f"{suite['suite']}: {suite['passed']}/{suite['total']}")
        for case in suite["results"]:
            if not case["passed"]:
                print(f"FAIL {case['name']}: {case.get('error')}")
    stream = io.StringIO()
    checks = unittest.defaultTestLoader.discover(str(ROOT / "tests"), pattern="test_*.py")
    result = unittest.TextTestRunner(stream=stream, verbosity=1).run(checks)
    print(stream.getvalue().strip())
    passed = all(s["passed"] == s["total"] for s in suites) and result.wasSuccessful()
    report = {"runtime": "Lua 5.4 via lupa", "lupa_version": lupa.__version__,
              "python_version": platform.python_version(), "date_utc": datetime.now(timezone.utc).isoformat(),
              "passed": passed, "suites": suites,
              "python_tests": {"total": result.testsRun, "failures": len(result.failures),
                               "errors": len(result.errors), "skipped": len(result.skipped)},
              "source_sha256": validation_inputs(), "live_game_tested": False}
    (ROOT / "dist").mkdir(exist_ok=True)
    (ROOT / "dist/test-results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Report: dist/test-results.json")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
