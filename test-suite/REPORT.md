# ThreatDiff 1.4.0 - test report

Tested: the installed copy at `World of Warcraft\_classic_beta_\Interface\AddOns\ThreatDiff` (version 1.4.0,
identical to the only file published on CurseForge, uploaded 2026-09-28).
Method: 239 automated tests running the real addon files on Lua 5.1 against a strict fake WoW API
(see README.md). Result: **234 pass, 5 confirmed defects** (3 functional, 2 hardening).
A mutation check (8 deliberate breakages of the addon) was caught by the suite 8 out of 8 times.

## Status after fixes: ALL FIXED - 239 / 239 tests pass
All four problems below were fixed in the installed copy (`Config.lua`, `UI.lua`, `Core.lua`). The version number was not bumped: repackage and upload
to CurseForge yourself. Fix 3 is a behaviour choice: a solo player with a pet now follows the "Solo" chip.

## What was NOT working (as originally found)

| # | Severity | Problem | Where | Effect for players |
|---|---|---|---|---|
| 1 | Medium | `/tdiff meter` can only show the meter, never hide it | `Config.lua` MeterCmd: `m.enabled = (sub ~= "hide")` is always true when `sub == ""` | The in-game help says "show/hide". Typing it on a visible meter does nothing. `/tdiff meter hide`, `/tdiff meter toggle`, the minimap right-click and the meter's X all still work. |
| 2 | Low | Typed X/Y offsets round differently from `/tdiff pos` | `UI.lua` NumberBox/Slider Commit use `floor(v*100+0.5)` without the epsilon `TD.Round2` uses | Typing `1.005` in the Exact offset box stores `1.00`, but `/tdiff pos 1.005 0` stores `1.01`. Same for `2.345`. |
| 3 | Low | Solo player with a pet is only governed by the "With pet" chip | `Core.lua` RebuildRoster `allowed` logic | Solo hunter/warlock with Solo ticked and With pet unticked sees no numbers at all (a party or raid member with a pet is not treated this way). |
| 4 | Low (hardening) | One damaged saved value breaks every nameplate | `Core.lua` never validates saved `point`/`relPoint`/`x`/`y`/`fontSize` | A hand-edited or corrupted SavedVariables entry (bad anchor name, number saved as text) makes the client throw on every nameplate until the profile is reset. Normal use cannot produce it. |

Suggested fixes (not applied; I did not touch the addon):
1. `MeterCmd`: `if sub == "" or sub == "toggle" then m.enabled = not m.enabled elseif sub == "show" then m.enabled = true elseif sub == "hide" then m.enabled = false`.
2. Round with `TD.Round2` (or add `+ 1e-7`) in the NumberBox and Slider `Commit`.
3. Use `(not inGroup and DB.showSolo)` without the `not hasPet` condition, or document that "With pet" overrides "Solo".
4. After `CopyDefaults`, reset any key whose type differs from `DEFAULTS`, and any `point`/`relPoint` not in the nine valid anchors.

## The behaviour users have reported (CurseForge comment, multi-target tanking)

Reproduced as designed, not an addon bug. When the game hides a mob's threat for nameplate units, the addon can only
read a mob that is also reachable as target, focus, mouseover, soft target, boss frame, your pet's target or any
group member's target. Tanking two mobs solo means only the one you target is live; the other keeps its last number,
dimmed, for "Keep the last number" seconds (default 10), then clears. Targeting or mousing over it refreshes it
instantly. This matches the author's reply on the page. Tests: `multi-target: ...` (4 tests). Raising "Keep the last
number" (Advanced page, up to 60s) is the only lever.

## What WAS verified working

| Area | Tests | Highlights |
|---|---|---|
| Number formatting | 6 | k/m abbreviation, decimals, rounding, sign switches, `!!!` tie |
| Nameplate engine | 48 | All 10 states (tank secure/thin/overtaken/other tank/pet/loose, DPS safe/warn/danger/aggro), "until pull" mode, hide-while-safe, only in combat, friendly/forbidden plates, plate recycling, update throttle and event coalescing, no OnUpdate scripts, secret/hidden values, group-member/pet/focus/boss routes, GUID fallback, 20- and 40-player raids (smart scan; simulated 40 players x 12 mobs x 1,200 events/s = about 904 threat calls/s, README claims about 1,300), role detection (LFG role, main tank, bear/defensive stance, Righteous Fury, solo, pet, manual), Classic divisor |
| Slash commands | 21 | `/tdiff` + `/threatdiff`, pos (every documented spelling), x, y, point, edit, test, role, on/off/toggle, stats, probe, minimap, meter lock/unlock/collapse/expand/reset/show/hide/toggle, profile *, reset, help |
| Profiles | 16 | create/duplicate/rename/copy/delete/reset/switch, case-insensitive names, per-character memory, old flat-save migration, corrupt save fallback, profile switch re-applies everything live |
| Threat meter | 30 | ranking, 110%/130% pull rows (all 5 modes), % / threat / gap formats, highlight, aggro marker, class colours/icons/pet row, healer view, rows-that-fit, collapse, close, options and right-click, drag-to-move and save, resize grip with clamps, lock, only-in-combat, preview, all bar styles + LibSharedMedia, fonts, transparency, no row leaks |
| Minimap button | 7 | placement, left/right/shift click, drag, square minimaps, account-wide hide, tooltip |
| Settings window | 42 | all 5 pages, nav, every toggle (18), chips, segmented controls (7), sliders (11, drag/type/clamp/wheel/units), dropdowns incl. fonts and LibSharedMedia, X/Y boxes with +/-/Shift/Ctrl, colour pickers + reset, tank safe-lead modes, Profiles page prompts (new/duplicate/rename/reset/copy/delete incl. error messages), Advanced buttons, Blizzard Settings entry, addon compartment, live stats ticker |
| Position editor | 12 | readout, nudge arrows, step/zoom, drag (Shift = fine), wheel/Alt-wheel, sample cycling, test button, re-measure, secret geometry |
| Robustness | 20 | TOC complete and every file listed, silent load, missing events/APIs, legacy options API, no frames created in combat, no leaks on re-entering the world, roster-event coalescing, nameplates-off hint |

## Not covered (needs the real client)
Pixel layout/fonts and what the live Forever client actually returns from its threat API. The fake client mirrors the
documented behaviour (hidden values on nameplate tokens), but in game use `/tdiff probe` mid-fight to confirm.
