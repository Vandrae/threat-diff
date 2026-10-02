"""Runs every Lua test in ./tests/*.lua (each in a fresh Lua 5.1 state) under pytest.

    .venv\\Scripts\\python -m pytest -v -rx

Tests that document a confirmed addon bug carry meta.bug in the Lua file. They run as
strict expected-failures: the suite stays green while the bug exists, and goes RED
("XPASS(strict)") as soon as the bug is fixed, telling you to drop the marker.

Set THREATDIFF_DIR to test a different copy of the addon.
"""
import glob
import os

import pytest
from lupa.lua51 import LuaRuntime

ROOT = os.path.dirname(os.path.abspath(__file__)).replace("\\", "/")
ADDON_DIR = os.environ.get(
    "THREATDIFF_DIR", os.path.join(os.path.dirname(ROOT), "ThreatDiff")
).replace("\\", "/")
TEST_FILES = sorted(glob.glob(ROOT + "/tests/test_*.lua"))


def new_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.ROOT, g.ADDON_DIR = ROOT, ADDON_DIR
    g.TEST_FILES = lua.table_from([f for f in TEST_FILES])
    with open(ROOT + "/runner.lua", encoding="utf-8") as fh:
        lua.execute(fh.read())
    return lua


def _collect():
    lua = new_runtime()
    T = lua.globals().T
    params = []
    for name in list(T.names().values()):
        bug = T.bugOf(name)
        marks = []
        if bug:
            marks.append(pytest.mark.xfail(strict=True, reason=str(bug)))
        params.append(pytest.param(name, marks=marks, id=name))
    return params


@pytest.mark.parametrize("name", _collect())
def test_lua(name):
    lua = new_runtime()
    res = lua.globals().T.run(name)
    if not res["ok"]:
        pytest.fail(str(res["message"]), pytrace=False)
