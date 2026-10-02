# ThreatDiff — WoW Forever

Puts the exact threat differential on every enemy nameplate you're in combat with, and lets you place that number to the hundredth of a unit (`x 2.34, y 10.25`).

Built for World of Warcraft: Forever (interface 16001, game version 1.60.1). The idea comes from the *Threat Meter: Nameplates* WeakAura, rebuilt as a standalone addon. The "threat left before pull" mode uses the same 110% melee / 130% ranged rule as Threat Meter Forever.

## Install
Copy the `ThreatDiff` folder into:

```
World of Warcraft\_classic_beta_\Interface\AddOns\
```

(The Forever beta installs to `_classic_beta_`. If the retail launch uses a different folder, use that folder's `Interface\AddOns` instead.) Enemy nameplates must be on, which you can toggle with **V**.

## Settings and the minimap button
Click the **minimap button** or type `/tdiff` to open settings. Everything is in plain words, with a short explanation under each option:

- **Home:** quick switches (nameplate numbers, threat meter, minimap button), "I usually play as" (Auto / Tank / Damage & Heal), a Preview button, and a colour guide showing what each colour means.
- **Nameplate numbers:** when to show them, what they measure, font and size, where the number sits ("Left of the nameplate", "Above", and so on, plus exact X/Y), colours and warning levels.
- **Threat meter:** the window itself, rows, size, look and see-through settings.
- **Profiles:** switch, create, duplicate, rename, copy, delete or reset.
- **Advanced:** refresh speed, custom anchor points and troubleshooting tools.

The minimap button: **left-click** opens settings, **right-click** shows or hides the threat meter, **shift-click** starts a preview, and **dragging** moves it around the minimap. Turn it off on the Home page or with `/tdiff minimap`. Its position and on/off setting apply to all your characters.

## What the number means
The number is **your threat minus the highest threat from anyone else** on that mob.

| You are… | Number | Colour |
|---|---|---|
| Tanking, big lead (default: next person ≤ 75% of you) | `+4.2k` | green |
| Tanking, thin lead | `+812` | yellow |
| Tanking but someone passed you / dead even | `-154` / `!!!` | orange |
| Tank, another tank has it | `-2.4k` | blue |
| Your pet has it | `-540` | teal |
| Tank, a non-tank has it (taunt!) | `-1.9k` | red |
| DPS/heal, safe / getting close / about to pull | `-3.1k` | pale green / yellow / orange |
| DPS/heal, you pulled it | `+305` | red |

It's always a raw threat number, never a percentage. It only appears on mobs you're actually fighting (you're in combat and on that mob's threat table with real threat), and everything disappears when combat ends.

Role is detected automatically. Tank = LFG tank role, main-tank assignment, Defensive Stance, Bear Form, Righteous Fury, or playing solo. You can force it with `/tdiff role tank|dps`.

DPS can switch to **"Threat left before pull"**. It shows exactly how much more threat you can do before you pull aggro, using the game's own melee/ranged pull thresholds.

## Placing the text exactly
- **Type it:** `/tdiff pos 2.34 10.25` or `/tdiff pos x, 2.34 y, 10.25`. `/tdiff x 2.34` and `/tdiff y 10.25` set one axis. `/tdiff pos` prints the current position.
- **Settings → Nameplate numbers → Position**: X/Y boxes with 2 decimals. The +/- buttons step 1; hold Shift for 0.1 or Ctrl for 0.01.
- **Drag it:** `/tdiff edit` opens a zoomable mock nameplate. Drag the number (hold Shift for fine control), use the mouse wheel for Y and Alt+wheel for X, or click the arrow buttons. The live readout shows `x …, y …`.
- `/tdiff test` puts sample numbers on every visible plate so you can see the result in the world.

Offsets are in nameplate units. By default the text's RIGHT edge is attached to the plate's LEFT edge. Change that with `/tdiff point RIGHT LEFT` or in the options window.

## Threat meter window
A damage-meter-style window for your target's threat. It lists everyone in your group who is on the mob's threat table, highest first:

```
Ranged pull at        116 (130.0%)
Melee pull at          98 (110.0%)
1. Bellucci Walkers    89 (100.0%)   <- you (highlighted); red edge = has aggro
2. Sheirok Koriehs     16 (18.0%)
3. Juk'zazt             0 (0.0%)
```

- **Pull rows:** "Melee pull at" and "Ranged pull at" are the aggro holder's threat ×1.1 and ×1.3 (the game's pull rule). They're sorted in with everyone else, so anyone above a pull row is about to take aggro. You can also switch to **Your exact pull point**, which comes straight from the game for your range, or turn them off.
- **Numbers:** threat with % of the tank (the default), threat only, or threat with each row's gap to *you* (your own row shows your lead over the next person).
- **Rows:** ranks, class icons, class colours, and a highlight on your own row. Each can be turned off.
- **Healers:** if you target a friendly player, the meter follows *their* target.
- **Title bar:** the mob's name, your own difference (same as your nameplate), and **-/+** collapse, options and close buttons. Drag the title bar to move the meter and the corner grip to resize it (width and height). You can lock it. The window keeps the size you give it and shows only the top rows that fit, so a window sized for 10 shows the top 10 even if 12 are on the threat table.
- **Style:** bar style (Blizzard, Flat, Glossy, Raid, Thin line, or any LibSharedMedia bar), font, outline, size, see-through settings for the background, bars and bar backdrop, border, width, height, bar height and spacing. **Test meter** fills it with sample data.

## Profiles
Settings live in profiles and save automatically. Each character remembers which profile it uses. In options → Profiles you can create, duplicate, rename, copy from, delete and reset profiles. From chat: `/tdiff profile` lists them; `/tdiff profile use Tank`, `new <name>`, `copy <name>`, `delete <name>` and `reset` do the rest (profile names aren't case-sensitive). Your existing settings were moved into the **Default** profile automatically.

## Commands
`/tdiff` options · `/tdiff edit` drag editor · `/tdiff test` sample numbers · `/tdiff pos …` exact position · `/tdiff point A B` anchors · `/tdiff role auto|tank|dps` · `/tdiff on|off` · `/tdiff meter [lock|unlock|collapse|reset]` · `/tdiff minimap` · `/tdiff profile …` · `/tdiff stats` · `/tdiff probe` · `/tdiff reset` (this profile) · `/tdiff help`

## Why it's light
- There are no per-frame scripts. Threat events only mark a plate dirty, and a single timer updates the dirty plates at most 10 times a second (you can change the rate).
- Each nameplate frame gets one text object, created once and reused for good. Nothing is created in combat.
- The group roster is cached. Text and colour only change when the rounded number changes.
- In raids, a smart scan re-checks only the top threat and the aggro holder, with a full roster scan every 0.5s.
- Stress test (simulated 40-player raid, 12 mobs, 1,200 threat events a second): about 1,300 threat API calls a second and about 0.6 ms of Lua per second of combat. A WeakAura-style "scan the whole raid on every event" handled the same load with about 64,000 calls a second, roughly 70× the CPU, and several MB a second of garbage. Check the numbers live with `/tdiff stats`.

## Notes
- Forever uses the modern API, which can hide ("secret") combat values, and addons can't do math on hidden values. Only the raw threat number has to be readable; if the aggro flag or status is hidden, ThreatDiff works them out from the numbers.
- **Live numbers on hidden nameplates:** Forever hides threat when it's asked through a nameplate, but not (so far) when the same mob is reached another way. ThreatDiff reads each mob through anything that points at it: your target, focus, mouseover, soft target, boss frames, your pet's target, and **whatever each group member or their pet is targeting**. In a group, that keeps nearly every mob that's being fought live. A mob nobody is targeting can't be read at all; it keeps its last real number, dimmed, for a few seconds (**Keep last** in options), and updates again as soon as anyone targets it or you mouse over it. It never shows a percentage.
- Not seeing numbers? Type `/tdiff probe`, start a fight with an enemy targeted, and the chat shows exactly which threat values the game let the addon read, including a **routes** line listing which targets are readable and how many plates are live or dimmed.
- The addon can only query your group and your pets. If the mob's aggro holder is outside your group, their threat is worked out from your threat percentage.
