#!/usr/bin/env python3
"""Headless logic tests for Beast Valley.

Bundles every pure module under src/shared (everything except Net, which
needs a live DataModel) together with tests/shims.luau (tiny Vector3 /
CFrame / Color3 / Random stand-ins) and tests/logic.spec.luau, then runs the
bundle with the standalone `luau` CLI.

Usage:  python3 tests/run.py            (expects `luau` on PATH or $LUAU)
"""
import glob
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHARED = os.path.join(ROOT, "src", "shared")
HERE = os.path.dirname(os.path.abspath(__file__))

LOADER = r'''
local cache = {}
function node(path)
	return setmetatable({ __path = path }, { __index = function(t, k)
		if k == "Parent" then
			return node(path:match("^(.*)/[^/]+$") or "")
		end
		return node(if path == "" then k else path .. "/" .. k)
	end })
end
require = function(n)
	local path = rawget(n, "__path")
	if cache[path] ~= nil then return cache[path] end
	local src = SOURCES[path] or error("no module " .. tostring(path))
	local chunk, err = loadstring("local script = ...\n" .. src, path)
	assert(chunk, err)
	local result = chunk(node(path))
	cache[path] = result
	return result
end
'''


def main() -> int:
    parts = [open(os.path.join(HERE, "shims.luau")).read(), "SOURCES = {}"]
    for path in sorted(glob.glob(os.path.join(SHARED, "**", "*.luau"), recursive=True)):
        rel = os.path.relpath(path, SHARED)[:-5].replace(os.sep, "/")
        if rel == "Net":
            continue
        parts.append("SOURCES[%r] = [=======[%s]=======]" % (rel, open(path).read()))
    parts.append(LOADER)
    parts.append(open(os.path.join(HERE, "logic.spec.luau")).read())
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False) as f:
        f.write("\n".join(parts))
        bundle = f.name
    luau = os.environ.get("LUAU", "luau")
    result = subprocess.run([luau, bundle], capture_output=True, text=True)
    os.unlink(bundle)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    if result.returncode != 0 or "ALL TESTS PASSED" not in result.stdout:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
