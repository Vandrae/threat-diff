# ThreatDiff test suite

Runs the **real, unmodified addon files** (read from the WoW AddOns folder, in TOC order) against a fake
World of Warcraft API, on a real Lua 5.1 interpreter (the version WoW uses), with no game client needed.

```
.venv\Scripts\python -m pytest -q -rx            # everything (about 3 seconds)
.venv\Scripts\python -m pytest -q -k "meter"     # a subset
set THREATDIFF_DIR=C:/path/to/another/ThreatDiff  # test a different copy
```

Setup (already done): `py -3.14 -m venv .venv` then `.venv\Scripts\pip install lupa pytest`.

## Layout
| File | What it is |
|---|---|
| `harness.lua` | The fake WoW: frames/textures/fontstrings/sliders/editboxes, events, timers, units, nameplates, threat tables, secret values. Deliberately strict (see below). |
| `runner.lua` | Mini test framework plus scenario helpers (`t:party`, `t:raid`, `t:engage`, `t:set`, `t:tick`, `t:plate`). Each test gets a fresh Lua state. |
| `test_threatdiff.py` | pytest driver. Tests with `meta.bug` run as strict expected-failures. |
| `tests/test_*.lua` | The tests, grouped by feature. |

## What the fake client is strict about
* A widget method the real client doesn't have raises an error (`SetBackdrop` only with `BackdropTemplate`, etc.).
* Lua errors inside event, script or timer callbacks are collected and **fail the test** even if the test body passed.
* The addon printing its own `... error:` report to chat fails the test.
* "Secret values" are objects that raise on comparison or arithmetic, like the Midnight-era client.
* `SetPoint` rejects bad anchor names, non-number offsets, self/cyclic anchors; `SetText` needs a font first.

## Known bugs
A test whose Lua call has `{ bug = "..." }` documents a confirmed defect. pytest shows it as `XFAIL`
with the reason (`-rx`). When the addon is fixed the test turns into `XPASS(strict)` = red, which tells you to
delete the marker.

## Limits
This proves the addon's logic and UI wiring. It cannot prove what the live Forever client does with its real
threat API (which values are hidden, exact frame layout/pixels, fonts). Use `/tdiff probe` in game for that.
