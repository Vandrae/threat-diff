# ThreatDiff Forever

**See how much threat you have on every enemy you're fighting, and how close you are to pulling aggro.**
Built for World of Warcraft: Forever (interface 16001, game version 1.60.1).

Download: [CurseForge](https://www.curseforge.com/wow/addons/threatdiff)

## Quick start
1. Install it, log in, and turn on **enemy nameplates** (default key: **V**).
2. Type **/tdiff** or click the minimap button to open settings.
3. Click **Preview** on the Home page to see sample numbers without a fight.
4. Set **"I usually play as"** to Auto, Tank, or Damage / Heal. Done.

## Reading the numbers
- **+1.2k** means you're ahead of everyone else by that much threat.
- **-850** means someone is ahead of you by that much.
- Colours show where you stand. Tanks see safe lead, thin lead, losing it, or a taunt warning. Damage and healers see safe, getting close, about to pull, or you pulled it. Pets get their own colour.
- Damage and healers can switch to **"Threat until pull"** to see how much more threat they can do before taking aggro.

## Threat meter
- A Details-style window ranking your group by threat, with class colours and icons.
- **Melee / Ranged pull** rows show where aggro would flip.
- Healers: target your tank and the meter follows their target.
- Resizable, collapsible, lockable, and can hide outside combat.

## Make it yours
- Place the number left, right, above or below the nameplate, with exact offsets or by dragging.
- Fonts, bar styles, colours and transparency. Works with SharedMedia.
- Profiles per role or activity, saved automatically for each character.
- Minimap button: left-click settings, right-click meter, shift-click preview.
- Very light: nothing updates every frame.

## Not seeing numbers?
- Numbers show only on enemies you're **in combat with**, and clear when combat ends.
- Make sure **enemy nameplates are on** (**V**).
- WoW Forever hides threat on enemies you're **not targeting**. ThreatDiff keeps their last number, **dimmed**, for a few seconds. Target or mouse over them to refresh.
- Still stuck? Run **/tdiff probe** in a fight and include the output in your bug report.

## Commands
`/tdiff` settings · `/tdiff help` all commands · `/tdiff test` preview · `/tdiff edit` position editor · `/tdiff pos 2.34 10.25` exact position · `/tdiff role auto|tank|dps` · `/tdiff on|off` · `/tdiff meter` show/hide the meter (also lock, unlock, collapse, reset) · `/tdiff minimap` · `/tdiff profile` · `/tdiff reset` · `/tdiff probe`

## Install from source
Copy the `ThreatDiff` folder into `World of Warcraft\_classic_beta_\Interface\AddOns\`.
More detail on the original design notes is in [ThreatDiff/README.md](ThreatDiff/README.md).

## Tests
`test-suite/` runs the real addon files against a fake WoW API on Lua 5.1 (no game needed):

```
cd test-suite
py -3 -m venv .venv
.venv\Scripts\pip install lupa pytest
.venv\Scripts\python -m pytest -q
```
See [test-suite/README.md](test-suite/README.md).
