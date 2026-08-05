# boxbot-riot

Local co-op horde survivor in the vein of Brotato. Godot 4.7.1, 2D, targeting
Steam. Up to 4 players share one screen (Steam Remote Play Together handles
"online"), so there is **no networking** — one process, one game state.

**Language: all code, comments, identifiers and content keys in ENGLISH.**
The user converses in Polish; the codebase does not.

---

## How to run things

Godot lives at `C:\Godot\Godot_v4.7.1-stable_win64_console.exe`.

```bash
# tests — 210 assertions across three suites, no editor, no game window
"C:\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --script res://tests/core_test.gd
"C:\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --script res://tests/run_test.gd
"C:\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --script res://tests/weapon_test.gd

# content validator — catches broken .tres references, exits non-zero
"C:\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --script res://tools/validate_content.gd

# import after adding scripts (builds the global class cache; .godot/ is gitignored)
"C:\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --import

# play it
"C:\Godot\Godot_v4.7.1-stable_win64_console.exe" --path .
```

### Verifying visual behaviour without eyes

The scene layer cannot be unit tested, so it is verified by **instrumented
capture runs**: the game screenshots itself and prints the model state from the
same frame. Read the PNGs directly — a picture alone cannot say whether a wrong
position came from logic or drawing, and numbers alone cannot show a sprite
behind the floor.

```bash
"C:\Godot\Godot_v4.7.1-stable_win64_console.exe" --path . -- --capture --capture-dir=<abs path> \
  --capture-shots=8 --capture-interval=0.2 --capture-delay=5.0 \
  [--capture-still | --capture-circle | --capture-scatter]
```

Create the output directory first or `save_png` fails with error 7.

---

## Architecture

```
core/        pure logic — RefCounted, ZERO Node/SceneTree/autoload dependencies
  enums/     StatTypes, CounterTypes, Hooks, WorldTypes  (all APPEND-ONLY)
  data/      .tres schemas: EntityData, CharacterData, EnemyData, WeaponData, ...
  effects/   DynamicEffect base, EffectInstance, StatusEffect, library/
  events/    EventPayload and its subclasses
  managers/  StatsManager, CounterManager, EffectDispatcher, StatusManager,
             ItemsManager, WaveDirector, RunRandom, WorldOverrides
  models/    EntityModel, WorldModel, WeaponModel, RunModel
  weapons/   FiringPattern*, SpreadPattern*, TargetSelector*, SwingPattern
  behaviors/ MovementBehavior, ChaseBehavior
scenes/      the view — nodes, physics, rendering
content/     authored .tres: characters, enemies, weapons, items, waves, worlds
tests/       headless suites
tools/       validate_content.gd, debug_capture.gd
```

**`core/` must never import a Node or touch an autoload.** That constraint is
the entire reason the logic can be tested headless, and every hour of test
coverage depends on it. `Vector2` and other built-in types are fine.

---

## Load-bearing decisions (do not casually undo these)

**One `EntityModel` for everything** — player, enemy, boss, weapon, projectile
owner, arena, run. There is deliberately no `PlayerModel`/`EnemyModel`: once
currency moved into counters, nothing distinguished them except input vs AI,
which is a scene concern. `WeaponModel` exists because it has real state (heat,
spin, burst progress).

**Hooks split into NOTIFICATION and PIPELINE.** Notifications say "this
happened" (read-only payload, order irrelevant). Pipelines say "this is about to
happen, change it" (mutable payload, ordered by `priority`). Armor, resistances
and stat-based shop pricing are *not expressible* without pipelines. 23 of 31
hooks currently fire; the rest wait on the shop and on step detection.

**Events are objects, not signal argument lists.** Adding a field must not break
two hundred existing effects.

**`StatsManager` records the SOURCE of every modifier.** Without it there is no
way to remove exactly what an expiring status contributed when several overlap
on one stat. Not optional — the status system depends on it.

**Effect runtime state lives in `EffectInstance.state`, never on the resource.**
Godot caches `.tres` globally, so state on the resource leaks between every
holder of the same item.

**Counters are separate from stats.** They must be persisted (stats are
rebuildable from items) and must never be multiplied by a percent modifier.
Currency is a counter: `CURRENCY` is the balance, `CURRENCY_EARNED` the lifetime
tally that "every 500 earned" effects hang on.

**Weapons decompose into four independent axes**, not a class hierarchy:
`FiringPattern` (when) × delivery kind (what) × `SpreadPattern` (how many) ×
`TargetSelector` (at whom). A pistol and a shotgun differ only by swapping
`SpreadSingle` for `SpreadCone(8)`. Heat is an orthogonal layer on
`WeaponModel`, available to every weapon; `heat_per_shot = 0` disables it.

**Crit is rolled ONCE per shot** into a shared `ShotSnapshot`, so all shotgun
pellets crit together and a piercing shot keeps critting through every enemy.

**One scene per ROLE, not per variant.** `character.tscn` serves every playable
character; `enemy.tscn` every enemy and boss. Identity comes from `.tres`. Scene
inheritance per variant was rejected as fragile and combinatorially useless;
script inheritance by responsibility (`Actor` → `Character`/`Enemy`) is fine.

**The arena is larger than the screen.** `ArenaCamera` follows the players and
widens to hold all of them; scattering to opposite corners pulls the whole map
into frame, which is intended. Enemies spawn just beyond the view, not at the
arena rim.

---

## Rules that break things when violated

**Enums are APPEND-ONLY.** `StatTypes.Stat`, `Modifier`, `CounterTypes.Counter`,
`Hooks.Hook`, `WorldTypes.*` are serialized into `.tres` as bare integers.
Inserting a value in the middle silently reinterprets every content file.

**No manager holds a reference back to its owner.** `host` is passed as a call
argument. `RefCounted` has no cycle collector — a mutual reference never frees.
This was a measured leak, not a theory.

**No effect may store an `EventPayload` in a field.** Payloads reference
entities, entities own the dispatcher, the dispatcher owns the effect. Caching
one closes a cycle. Measured at 33 leaked objects. Copy out what you need, or
hold a `WeakRef`.

**Writing project files from PowerShell:** use
`[System.IO.File]::WriteAllText(path, text, (New-Object System.Text.UTF8Encoding($false)))`.
`Set-Content -Encoding utf8` adds a BOM in PS 5.1, which the `.tres` parser
rejects — and the tests still pass because Godot falls back to cached imports,
so the failure only shows in the import log.

**GDScript gotchas hit in this repo:** `_get` is a reserved `Object` virtual and
shadowing it breaks the whole script; `:=` cannot infer a type from `Dictionary`
access or `get_script()`; lambdas capture by **value**, so assigning to an outer
local inside one is silently lost.

**Watch the import log, not just test results.** Parse errors can leave tests
passing while silently skipping assertions.

**Never put comments in `project.godot`.** The editor rewrites the whole file
on save and drops them, along with any setting that happens to equal its
default. Explanations for project settings belong here instead.

---

## Current state

Playable vertical slice. Arena with bounds from the model, character and enemies
from `.tres`, chasing AI with separation, contact damage, projectile and melee
weapons, waves with budget-driven escalation, currency from kills, following
camera, 1–4 local players.

**Working but temporary:**
- `RunModel.auto_intermission = 4.0` closes the shop phase on a timer, because
  there is no shop UI. Set to 0 once the shop exists.
- `player_count` in `main.tscn` defaults to 1; raise it to test co-op.

**DEBUG SETTINGS CURRENTLY ACTIVE — revert for normal play:**
- `scenes/actors/character.tscn` → `WeaponMount.weapon_time_scale = 0.25`
  (4× slow motion, added to evaluate melee by eye; normal is `1.0`)
- `content/characters/test_character.tres` → `MAX_HP = 3000`
  (a consequence of the slowdown; normal is `100`)

**Known gaps:** no shop, no UI at all, player death does nothing (the run
carries on with a corpse), no join flow for co-op, no `BEAM` delivery, no
explosion/puddle effects on `ON_IMPACT`, no save system, no localisation
(`display_key` fields exist but nothing consumes them), no art (everything is
drawn as placeholder circles and lines).

**Undecided:** art style. This gates the base resolution — pixel art wants a low
base (e.g. 640×360) with integer scaling, and changing it after hundreds of
items are authored means reworking every collider radius, reach and speed.
Currently 1920×1080 with `stretch/aspect = "keep"` (16:9 fills, 21:9
letterboxes).

---

## Keeping this file and the tests honest

**This document is part of the work, not a report about it.** A stale
`CLAUDE.md` is worse than none, because a fresh session trusts it. Update it in
the SAME commit as the change, never as a follow-up.

What goes stale fastest, and what to do about it:

| when you… | update |
|---|---|
| add a `Hooks.Hook` value | the count in *Architecture* and whether it fires |
| finish a system | move it out of *Known gaps* into *Current state* |
| add a debug knob | the **DEBUG SETTINGS ACTIVE** block — and delete it when reverted |
| lose time to a non-obvious trap | *Rules that break things when violated* |
| settle something in *Undecided* | replace it with the decision and its reason |
| add or remove tests | the assertion count in *How to run things* |

**Tests ship with the change, not after it.**

- Anything in `core/` is testable headless, so it comes with assertions in the
  same commit. No exceptions — that layer is Node-free precisely to make this
  cheap, and skipping it wastes the constraint everything else pays for.
- A **bug fix** gets a regression test that fails without the fix. Several bugs
  here recurred in a second place (the cooldown debt lived in four firing
  patterns) and only a test in the shared base caught that.
- `scenes/` cannot be unit tested. It ships with a **capture run in the commit
  message** instead: the numbers before and after, or an A/B with one variable
  changed. "Looks right" is not a result.
- New content types get a check in `tools/validate_content.gd`. At the target
  scale a broken `.tres` loads as null and fails silently mid-wave.

**Run all three suites plus the validator before committing.** They take a few
seconds and have caught regressions in layers that seemed unrelated to the
change.

## Working style that has worked here

Verify by **running and measuring**, not by asserting. Several real bugs were
found only by instrumented runs: cooldown debt firing a weapon every frame after
an idle gap, a melee weapon swinging at air because it targeted further than it
could reach, enemies merging into one dot without separation, and a parse error
that silently skipped 11 assertions while the suite still reported green.

Commit messages in this repo are deliberately long and explain **why**, not
what. `git log` is a genuine knowledge base — read it when a decision looks
arbitrary.
