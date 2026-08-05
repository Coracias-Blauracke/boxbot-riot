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
# tests — 344 assertions across three suites, no editor, no game window
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
  --capture-shots=8 --capture-interval=0.2 --capture-delay=5.0 [--capture-players=N] \
  [--capture-still | --capture-circle | --capture-scatter | --capture-downed]
```

Create the output directory first or `save_png` fails with error 7.

`--capture-players=N` overrides `main.tscn`'s player count, so a co-op state can
be photographed without editing the scene and remembering to put it back.

The scripted modes exist because the interesting states are hard to reach by
accident:

| mode | what it is for |
|---|---|
| `--capture-still` | the only way to observe contact damage — enemies never catch a running player |
| `--capture-circle` | a tight circle keeps the player inside the swarm, which is what exposes missing separation |
| `--capture-scatter` | drives players to opposite corners to check the camera holds all of them |
| `--capture-downed` | player 0 stands and dies while the rest kite in a WIDE circle and live — the only way to photograph one player down while the run continues |

`--capture-zoom=N` and `--capture-margin=N` override `ArenaCamera` so framing
can be A/B'd with one variable changed. Note `group_margin` caps how far
`default_zoom` can actually go: a solo player cannot exceed
`viewport_height / (group_margin * 2)`, which is ~2.08 at the authored 260.

`--capture-downed` turns at 0.55 rad/s rather than 1.6 on purpose: speed divided
by turn rate is the radius, and at 1.6 the survivors trace a ~137-unit circle,
stay inside the horde and die before the wave can end. Nothing is then observed.

---

## Architecture

```
core/        pure logic — RefCounted, ZERO Node/SceneTree/autoload dependencies
  enums/     StatTypes, CounterTypes, Hooks, WorldTypes, RunTypes (APPEND-ONLY)
  data/      .tres schemas: EntityData, CharacterData, EnemyData, WeaponData, ...
  effects/   DynamicEffect base, EffectInstance, StatusEffect, library/
  events/    EventPayload and its subclasses
  managers/  StatsManager, CounterManager, EffectDispatcher, StatusManager,
             ItemsManager, WaveDirector, RunRandom, WorldOverrides,
             ShopManager (+ ShopOffer)
  models/    EntityModel, WorldModel, WeaponModel, RunModel
  weapons/   FiringPattern*, SpreadPattern*, TargetSelector*, SwingPattern
  waves/     WaveTable, WaveEntry, WaveModifier, SpawnPattern* + SpawnGroup
  behaviors/ MovementBehavior, ChaseBehavior
scenes/      the view — nodes, physics, rendering
  ui/        Hud, PlayerPanel, PlayerPalette, ShopScreen, ShopPanel, ShopLayout
  input/     PlayerInput (device binding, movement + menus)
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
and stat-based shop pricing are *not expressible* without pipelines. **28 of the
29 hooks fire**; only `ON_STEP` waits on step detection.

(This line previously read "23 of 31", which was wrong in both numbers. Count
the entries in `Hooks.KINDS` — it has to cover every hook — rather than trusting
the figure written here.)

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

**The shop UI cannot use Godot's focus system.** Focus is ONE per viewport, so
four panels cannot each hold their own. Every ShopPanel drives its own cursor
from its own PlayerInput instead, and nothing about the shop is global state.
That is also why device assignment had to stop being derived from the player
index first: a panel needs to know which pad is its own.

**Shop panels use the HUD's corner map.** 1 player takes the screen, 2 split it
left and right, 3 and 4 take quadrants — P1 top-left, P2 top-right, P3
bottom-left, P4 bottom-right, exactly as in combat, so a player learns where
they are once. Three deliberately does not give somebody a full-width strip:
that makes one panel a different SHAPE from the others, so it would have to work
at three aspect ratios instead of two, and a visibly bigger panel for one person
on a shared couch reads as unfair. The free quadrant is where the shared wave
line goes.

**Zero tier weight means "not yet", not "last resort".** Avoiding duplicate
offers must never fall through to a tier the wave curve has switched off — it
put a tier 4 item on wave 1 as soon as every other item had been drawn. Repeats
are the correct fallback for a pool smaller than the shop; breaking the curve is
not.

**One shop per PLAYER, never one shop shared.** `RunModel.shops` is
index-aligned with `players`, and each `ShopManager` draws from its own
`RunRandom` sub-stream so the order in which four people hit reroll cannot shift
what the others are offered. Nothing about that was added for the shop: currency
was already a per-entity counter, `CALCULATE_PRICE` was already evaluated per
buyer, and `ItemsManager` already took `host` as an argument precisely so two
player models could not trigger each other's effects. A single shared shop would
have been the odd one out.

**The shop never decides what a stat is worth.** `PriceEvent` carries
`uses_stat_payment` and `pay_with_stat` out of `CALCULATE_PRICE`, and
`ShopManager` simply spends whichever was named. The EXCHANGE RATE lives in the
effect that switches the buyer onto stat payment, because a character paying in
blood and one paying in max HP want completely different numbers. A stat can
never be paid down to its `StatTypes.FLOORS` value — that would let a purchase
kill the buyer, or divide by zero further along.

**A refund is not earnings.** `ShopManager.sell` adds to `CURRENCY` directly
rather than calling `add_currency()`, which also credits `CURRENCY_EARNED`.
Otherwise a buy-then-sell loop farms every "for each 500 earned" effect for the
price of the spread. Sell value is a fraction of the item's AUTHORED price, not
of what it would cost today, or buying early and selling late would print money.

**Waves decompose the same way weapons do.** `WaveTable` says what MAY appear,
the budget says how much, `WaveDirector` says when, and `SpawnPattern` says
WHERE. Placement was the missing fourth axis — a single hardcoded policy in the
scene layer — so an ambush or an arrival from the arena rim was not expressible.
`SpawnPattern` is deliberately the same shape as `SpreadPattern`: plain data in,
plain data out, no nodes, testable headless. `SpawnContext` is what makes that
possible — it hands the camera rectangle and the player positions over as bare
`Vector2`, at which point they stop being scene facts and become numbers.

The pattern lives on `WaveEntry`, not on the wave, because it is a property of
the ENEMY: a lurker should ambush and a chaser should walk in from off screen,
whichever wave they turn up in. Four exist: `SpawnRing` (walked in from off
screen), `SpawnInView` (already here), `SpawnNearPlayer` (ambush) and
`SpawnEdge` (from the arena wall, a long slow approach).

**Every pattern that can place near a player enforces a clearance, on every
member, against every player.** Both halves of that were got wrong here first. A
distance enforced on the group's ANCHOR says nothing about its members — a
cluster of radius 40 around an anchor 190 away leaves its nearest member at 150.
And a floor measured only against the TARGETED player still drops a group in a
second player's lap, which in co-op is the same unfairness with an extra step.
Hence `SpawnPattern._push_clear_of_players`, shared rather than reimplemented.
A group appearing on top of somebody is not difficulty; the player had no
information and no move that would have helped.

**A spawn decision is a GROUP, not an enemy.** `WaveDirector` emits
`Array[SpawnGroup]`. It used to return a flat `Array[EnemyData]` with the same
enemy appended `group_size` times, and the spawner rolled an independent
position for each — so `WaveEntry.group_size`, which documents itself as a
cluster, arrived as that many unrelated points on the ring. `default_waves.tres`
had been authoring `group_size = 3` the whole time. One group, one anchor.

**Co-op scales the RHYTHM, not the batch size.** `budget_per_extra_player` and
`events_per_extra_player` are both 1.0, so two players get twice the budget AND
twice the arrivals. Scaling the budget alone would keep twelve arrivals and make
each one twice the size, which reads as long quiet stretches punctuated by a
wall. Scaling is linear, not compounding: four players face four times the wave,
not eight — the budget curve already compounds across waves on its own.

**Crit is rolled ONCE per shot** into a shared `ShotSnapshot`, so all shotgun
pellets crit together and a piercing shot keeps critting through every enemy.

**One scene per ROLE, not per variant.** `character.tscn` serves every playable
character; `enemy.tscn` every enemy and boss. Identity comes from `.tres`. Scene
inheritance per variant was rejected as fragile and combinatorially useless;
script inheritance by responsibility (`Actor` → `Character`/`Enemy`) is fine.

**A downed player is not freed; an enemy is.** `Actor._on_model_died()` calls
`queue_free()`, and `Character` overrides it to go down instead. The model stays
in `RunModel.players` holding its currency, its items and its HUD panel, because
`RunTypes.DeathRule` may yet stand it back up — freeing the node would make that
impossible. Two bugs became reachable the moment corpses started persisting, and
both are now guarded in `EntityModel`: damage on a corpse awarded a second kill
(the credit only checked `not is_alive`), and `heal()` raised `current_hp` above
zero while `is_alive` stayed false.

**Death is a run rule, not a constant.** `RunModel.death_rule` switches between
revive-next-wave, permadeath and shared-fate, and the wave loop is identical for
all three. A challenge mode is meant to be that dropdown and nothing else; if a
future mode needs a second copy of the loop, the rule was modelled wrong.
Revived players stand up when the SHOP OPENS, not when the next wave starts —
a player who cannot spend the currency they died holding falls further behind
every wave, which is the spiral the forgiving rule exists to prevent.

**HUD layout is driven by player count.** One panel per player, one corner each
(P1 top-left, P2 top-right, P3 bottom-left, P4 bottom-right), right-hand panels
mirrored so their contents hug the edge they are anchored to. Deliberately not a
bar along one screen edge: this is a top-down game where the edges are where
enemies arrive from, and chrome there costs reaction time. Only what players
genuinely share — wave number and clock — sits in the middle. `PlayerPalette` is
ONE table used by both the blob on the floor and the corner describing it; a
panel whose colour does not match its character is worse than no colour at all.

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
access, `get_script()` or **`weakref()`** — all return `Variant`, and the
resulting warning is treated as an error, which skips the entire suite rather
than failing one assertion; lambdas capture by **value**, so assigning to an
outer local inside one is silently lost (capture a one-element `Array` instead —
the array is a reference, so mutating its contents survives).

**Watch the import log, not just test results.** Parse errors can leave tests
passing while silently skipping assertions.

**Never put comments in `project.godot`.** The editor rewrites the whole file
on save and drops them, along with any setting that happens to equal its
default. Explanations for project settings belong here instead.

---

## Current state

Playable vertical slice with a closed loop, win and lose included. Arena with
bounds from the model, character and enemies from `.tres`, chasing AI with
separation, contact damage, projectile and melee weapons, waves with
budget-driven escalation, currency from kills, following camera, 1–4 local
players, per-player HUD, downed players with a configurable death rule, a run
that ends in victory or defeat, a spawn system with swappable placement
patterns, group arrivals, co-op scaling and authored per-wave modifiers, and a
per-player shop MODEL — rolling by tier weight, pipeline pricing, buying,
selling, rerolling, stat payment and ready-up — with eight authored items.

The shop UI is playable: per-player panels laid out by player count, a cursor
per player driven by that player's own device, offers, reroll, sell from the
owned strip, a stat sheet that enumerates `StatSheet` rather than the enum, and
ready-up. `auto_intermission` still runs as a fallback because nothing forces a
player to press ready.

**Still missing from the shop UI:** the character tile (its innate effects and
starting stats — `DynamicEffect.describe()` is the source), item icons, and any
text at all. `display_key` renders as the raw key through `tr()` until a
translation is loaded, which is by design but looks like a placeholder.

**No debug settings are currently active.**

**Working but temporary:**
- `RunModel.auto_intermission = 4.0` closes the shop phase on a timer, because
  nothing can press ready yet. Set to 0 once the shop UI exists — the HUD's
  "next in Ns" countdown then becomes "waiting for P2, P4" instead.
- `player_count` in `main.tscn` defaults to 1; raise it to test co-op, or pass
  `--capture-players=N` for a capture run.
- `death_rule` is an export on `main.tscn`. When challenge modes arrive it wants
  to live in a `RunRulesData.tres` alongside `revive_hp_fraction` and whatever
  else a challenge varies, so a mode is one authored resource.

**Known gaps:** no shop UI, no menus or pause (the HUD is the only UI), no join
flow for co-op, no `BEAM` delivery, no explosion/puddle effects on `ON_IMPACT`,
no save system, no localisation (`display_key` fields exist but nothing consumes
them — including the HUD, which prints "P1" and raw numbers), no art (everything
is drawn as placeholder circles, ellipses and lines).

**Settled: the base resolution is 1920×1080 and stays there.** `stretch/aspect`
is `"keep"` (16:9 fills, 21:9 letterboxes). **Pixel art is ruled out** — the user
does not want it, so the low base with integer scaling that pixel art would have
demanded is not on the table, and with it goes the whole reason the base was ever
in question.

This matters mainly for what it UNBLOCKS. Every spatial number in `content/` —
collider radii, reach, `base_extents`, speeds, knockback — is denominated in
these units, and the fear of having to rescale all of them was the one argument
against authoring content at volume early. That argument is gone.

An earlier version of this file listed the art style as *Undecided* and framed it
as gating the base resolution via pixel art. That was never a decision anybody
had made; it was a hypothesis written down as though it were a live option, and a
later session duly treated it as one. **A guess recorded here reads exactly like a
decision.** If something is genuinely open, say who has to settle it and what
depends on it — or leave it out.

**Settled: simple, low-detail sprites in the spirit of Brotato — but NOT pixel
art.** Plain readable shapes and flat colour, authored as ordinary rasters and
scaled smoothly. No integer scaling, no retro pixel grid, no `scale_mode`
change. The reason is production cost rather than taste: a few hundred item
icons is the dominant art expense in this genre, and simple sprites are what
makes that volume tractable.

Sprites are authored for the LARGEST they will ever appear. `stretch/mode` is
`canvas_items`, so a 4K monitor scales the whole 1920 canvas by 2×, and
`ArenaCamera.default_zoom = 1.35` is the CLOSEST framing (`min_zoom = 0.5` only
pulls further back). Maximum on-screen size is therefore
`collider_radius × 2 × 1.35 × 2`:

| entity | `collider_radius` | largest on 1920 | largest on 4K |
|---|---|---|---|
| brute | 15 | 41 px | 81 px |
| character | 12 | 32 px | 65 px |
| chaser | 9 | 24 px | 49 px |
| weapons | 6–7 | 16–19 px | 32–38 px |
| bullet | 4 | 11 px | 22 px |

**128×128 covers everything on the arena with headroom.** Item icons are a
separate case: they are HUD-space, not world-space, so their size follows
whatever the shop grid ends up being rather than any of the above.

Art swaps in without touching gameplay: `EntityData` keeps `icon` and `sprite`
in a different group from `collider_radius`.

**On-screen scale is a CAMERA setting, not a content one.** The actors are small
— a 12-radius character is 32 px on a 1920-wide screen, about 60 player-widths
across the view — and that reads as dots in capture screenshots. If everything
should simply be bigger, that is `default_zoom` alone, one number, no content
touched. Only the ratio of actor size to `base_extents` lives in content, and a
ratio is what gets tuned by feel anyway. Do not "fix" apparent scale by
rescaling `.tres` files.

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
