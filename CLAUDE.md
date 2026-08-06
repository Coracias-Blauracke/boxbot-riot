# boxbot-riot

Local co-op horde survivor in the vein of Brotato. Godot 4.7.1, 2D, targeting
Steam. Up to 4 players share one screen (Steam Remote Play Together handles
"online"), so there is **no networking** — one process, one game state.

**Language: all code, comments, identifiers, UI strings and content keys in
ENGLISH.** The user converses in Polish; the codebase does not. This was broken
once by eight shop UI strings, so `validate_content.gd` now fails on any
non-ASCII character in `core/`, `scenes/`, `tools/` or `tests/`. That guard is
half of the rule - it catches accented words and misses unaccented ones - but it
is the half that also breaks fonts and encodings.

---

## How to run things

Godot lives at `C:\Godot\Godot_v4.7.1-stable_win64_console.exe`.

```bash
# tests — 570 assertions across three suites, no editor, no game window
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

**The game starts on `lobby.tscn` now, and `--capture` starts the run from
there.** A scripted run has nobody to press SPACE, so without that every capture
command in this file would sit in the lobby for ever. `--capture-players=N`
fills the roster (keyboard first, then pads in order) and the run begins at
once. `--capture-lobby` fills it and STAYS, which is the only way the join
screen gets photographed.

`main.tscn` is still directly launchable and nothing here requires a lobby:

```bash
"C:\Godot\Godot_v4.7.1-stable_win64_console.exe" --path . res://scenes/main.tscn -- --capture ...
```

Launched that way it falls back to its own `player_count` export and restarts
with `reload_current_scene()`. Both paths are verified; if one of them breaks,
the difference is whether anything is connected to `main.gd`'s
`restart_requested`.

The scripted modes exist because the interesting states are hard to reach by
accident:

| mode | what it is for |
|---|---|
| `--capture-still` | the only way to observe contact damage — enemies never catch a running player |
| `--capture-circle` | a tight circle keeps the player inside the swarm, which is what exposes missing separation |
| `--capture-scatter` | drives players to opposite corners to check the camera holds all of them |
| `--capture-downed` | player 0 stands and dies while the rest kite in a WIDE circle and live — the only way to photograph one player down while the run continues |
| `--capture-pause=N` | toggles the pause menu, which no scripted player can press START for; repeat it to resume |
| `--capture-restart=N` | restarts the run, and photographs the result into `after_restart/` |
| `--capture-lobby` | holds the lobby open with the roster filled, instead of starting the run |

`--capture-intermission=N` holds the shop phase open (four seconds is not long
enough to photograph) and `--capture-shop-owned` parks every shop cursor on the
owned strip. The second one exists because **a UI state that needs input cannot
otherwise be photographed at all**, which is a real hole in how this repo
verifies the scene layer — every selected, hovered or focused state is invisible
to a capture run until something can put the cursor there.

`--capture-pause=N` asks for the pause menu N seconds in, and `--capture-restart=N`
restarts the run at N seconds. Both close that same hole for the pause screen.
Two things about them are load-bearing rather than incidental:

- `--capture-pause` calls `PauseScreen.request_toggle()`, **not `open()`**, so it
  goes through the same gate the button does. Pointed at the shop phase it
  photographs a shop, because that is what the button would do there. A
  verification path that skips the gate verifies nothing.
- It TOGGLES and may be repeated: `--capture-pause=5 --capture-pause=8.2` pauses
  and then resumes. One entry alone freezes the run and every later shot reads
  the same numbers, which proves nothing about getting going again.
- The restarted pass writes into `<capture-dir>/after_restart/` rather than over
  the first pass. The two sets of PNGs ARE the evidence, so one overwriting the
  other destroys the measurement it was taken for. The restart also fires once
  per process — the reloaded scene reads the same command line, and without a
  static guard it reloads for ever.

Reaching the shop at all needs players who survive wave one, so a shop capture
is `--capture-players=2 --capture-downed --capture-intermission=N`. The default
scripted walk pins the player in a corner and dies at about wave second 16.

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
  data/      .tres schemas: ShopEntryData (the base every purchasable shares),
             EntityData, CharacterData, EnemyData, WeaponData, ItemData,
             StatScaling (which stat feeds a weapon, and how much),
             WeaponClassData/Tier/Set (tags and what holding several is worth)
  effects/   DynamicEffect base, EffectInstance, StatusEffect, library/
             (statuses carry StatusScaling: which stat feeds which axis)
  events/    EventPayload and its subclasses
  managers/  StatsManager, CounterManager, EffectDispatcher, StatusManager,
             ItemsManager, WaveDirector, RunRandom, WorldOverrides,
             ShopManager (+ ShopOffer), WorldCensus
  models/    EntityModel, WorldModel, WeaponModel, RunModel, PlayerRoster
  weapons/   FiringPattern*, SpreadPattern*, TargetSelector*, SwingPattern
  waves/     WaveTable, WaveEntry, WaveModifier, SpawnPattern* + SpawnGroup
  behaviors/ MovementBehavior, ChaseBehavior
scenes/      the view — nodes, physics, rendering
  lobby.gd   the scene the game STARTS on; owns the roster and builds the run
  ui/        Hud, PlayerPanel, PlayerPalette, ShopScreen, ShopPanel, ShopLayout,
             PauseScreen, JoinView
  input/     PlayerInput (device binding, movement + menus),
             DeviceJoiner (watches devices that have NOT joined)
content/     authored .tres: characters, enemies, weapons (+ classes/), items,
             projectiles,
             waves, worlds, spawn/ (patterns), shop/ (pool and rules),
             stats/ (StatMetadata + the StatSheet reading order),
             statuses/ (bleed, poison, burn, slow)
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
and stat-based shop pricing are *not expressible* without pipelines. **30 of the
31 hooks fire**; only `ON_STEP` waits on step detection.

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

**A player OWNS a device; it is not derived from their index.** The old rule
gave player 0 the keyboard plus pad 0 and player N pad N, which cannot express
three pads and one keyboard — the keyboard player and the first pad player
collide on the same slot and move together. `PlayerInput` carries the binding
and answers for BOTH walking and menus, because splitting those produces a
player who can walk but cannot buy. `main.tscn`'s `player_devices` array is now
what the LOBBY injects, and only an authored fallback when the scene is launched
on its own.

**A DEVICE JOINS ONCE, and "only one player on the keyboard" falls out of it.**
`PlayerRoster` has no rule about keyboards, because the keyboard is one device;
the old arrangement needed a special case only because it let player 0 hold the
keyboard AND pad 0 at the same time. Join ORDER is player order, so whoever
presses first is P1 in the lobby, in the corner map, in the shop and in the
palette. Leaving CLOSES THE GAP rather than leaving a hole — every layout
downstream is driven by the player count, and a hole would mean an empty corner
and a shop panel nobody drives.

The rules live in `core/` with no Input and no nodes, which is what lets them be
tested headless; `DeviceJoiner` only watches buttons, and `JoinView` only draws.
`PlayerInput.KEYBOARD` is taken from `PlayerRoster.KEYBOARD_DEVICE` rather than
declared twice, because `scenes/` may depend on `core/` and never the reverse.

**The LOBBY owns the run, not the other way round.** `main.tscn` is instantiated
as a child with `player_count` and `player_devices` injected before
`add_child()` — the same shape `main.gd` already uses to hand a `Character` its
model. A run is never instantiated half-described, which is what makes the
lobby the right home for everything that is decided BEFORE a run and re-decided
between runs: a solo/co-op toggle, character select, run rules.

Solo is deliberately NOT a second code path. It is one entry in the roster, and
the run cannot tell the difference — which is why the toggle, when it arrives,
is a branch in the lobby and nowhere else.

**A device is polled ONCE per frame, guarded inside `PlayerInput`.** Two screens
hold the same binding now — the pause menu reads every device in every phase, a
shop panel reads its own — and a second `poll()` in one frame DESTROYS the edges
the first produced: `triggered()` is true only on the frame a button goes down,
so the second caller sees "already held" and reports nothing. The guard makes
the first poller of the frame win and everybody read the same answer. The
alternative was a rule saying exactly one screen may poll at a time, which is
the kind of invariant that holds right up until a third screen exists.

**The pause menu is ONE menu for the whole couch, driven by every device.**
Deliberately the opposite of the shop, and for the same reason the shop is the
way it is: a shop panel gets its own cursor because each player is deciding
something different, whereas here there is a single decision that applies to
everybody. Binding it to whichever device opened it would mean a pad going flat
can strand the run. Who reaches for the stick is a couch problem.

**Pause shares READY's physical button, and the PHASE says which it is.** START
on a pad, ESC on the keyboard. The shop has no clock and closes only when every
player declares ready, so it is already a stopped state with nothing to pause,
and `PauseScreen` refuses to open during it. Giving pause a button of its own
would have spent the one button every player already knows. Polling continuously
in every phase is what keeps this honest: a menu that only started polling once
the shop closed would see START still held and open itself the instant somebody
readied up.

**The pause menu is also the run-over screen.** When the run ends it opens
itself with RESUME dropped, because "the run is over and there is no way to
start another" was the same dead end as having no pause at all. A second screen
saying the same three things would be two things to keep in step. The HUD's
outcome banner still owns the middle of the screen, so the menu moves below it
and draws no shade of its own — two stacked shades read as 0.92 alpha and
blacked out the arena entirely.

**Restarting rebuilds the RUN, not the tree.** `PauseScreen` emits
`restart_requested`, `main.gd` passes it up, and the lobby throws the run node
away and instantiates a fresh one with the roster it still holds — so the people
who were playing stay who they were and nobody re-joins after every death.

`main.gd` falls back to `reload_current_scene()` when nothing is connected,
which is what keeps `main.tscn` independently launchable. That fallback is only
honest because nothing stateful outlives the scene: every model hangs off the
`RunModel` built in `_ready`, and the single autoload (`EventBus`) holds signals
and no state — nothing emits or connects to it today.

(An earlier version of this section said "no autoloads". There is one. It has
been declared since before the run model existed and three files mention it only
to say they deliberately do not use it, so the conclusion held while the reason
given for it did not.)

`get_tree().paused` is the one flag that survives either path, because it lives
on the TREE rather than the scene, so a restart clears it first or the fresh run
comes up frozen with nothing on screen to say why.

**Restart obeys `run_seed` and does not work around it.** A fixed seed replays
the same run, which is what a fixed seed is FOR: dying on wave 4 and immediately
trying that exact wave 4 again. A restart that quietly reseeded would take away
the only tool for retrying one situation, and the way to get a different run is
already the authored 0.

**A weapon and an item are the SAME transaction.** Both roll by tier, price
through `CALCULATE_PRICE` per buyer, pay in currency or in a stat, appear in the
owned strip and sell back. `ShopEntryData` is the base that says so, and the
only thing subclasses override is what happens at the instant of acquisition -
an item pushes modifiers into `StatsManager`, a weapon takes a slot. The
alternative was a `kind` enum and a branch at every one of those sites, which
costs a branch per KIND per SITE for ever; at a hundred weapons it is the sites
that get expensive, never the content.

`modifiers()` and `effects()` live there because the two shapes were ALREADY
identical under different names, and `ShopPanel` was already flattening them by
hand to put the character in the owned strip. Naming it means the detail block
derives a weapon's description with no new code at all - a captured shop shows
`WEAPON_PISTOL` listing `STAT_RANGED_DAMAGE +12` and `STAT_SPREAD_ANGLE +3` in
red, because spread is a stat where lower is better and that was already known.

`EntityData extends ShopEntryData`, so an enemy carries a `tier` and a
`base_price` it never uses. That is the same trade as an arena carrying
MELEE_DAMAGE and is made for the same reason: one shape every consumer can read
beats a narrower one half of them special-case.

**Weapon CLASSES are tags plus authored thresholds.** A weapon carries
`tags`, PLURAL, and counts toward every class it names - a bayonet is a blade
and a gun, and both counts rise, because forcing a choice the fiction does not
have is how a tag system starts fighting its own content. `WeaponClassData`
holds the tiers; `WeaponClassSet` says which classes a run knows about, for the
same reason `ShopData` holds its pools rather than the shop scanning a folder.

Set bonuses are the main build engine in this genre: they are why a player keeps
a matching weapon over a stronger one, which is the most interesting decision
the shop offers.

**Tiers are CUMULATIVE, not highest-only.** Holding four of a class whose tiers
are 2 and 4 grants both. Cumulative is strictly the more expressible rule - one
big bonus at four is a single tier, while a class where each weapon feels like
progress needs several, and "highest only" can only express the second by
repeating the earlier numbers in every later tier, which drifts the moment
somebody retunes one.

**The bonus is RECOMPUTED, never adjusted.** `EntityModel._refresh_class_bonuses`
strips every class's contribution by SOURCE and reapplies from the current
count, because the count goes DOWN as well as up: selling the third blade has to
take the third blade's bonus with it. An incremental version breaks permanently
and silently the first time an event is missed - the same argument `WorldCensus`
is built on. The source is the class RESOURCE, so one class's contribution can
be stripped without touching another's.

A tag naming no authored class is INERT rather than an error, so a weapon can be
tagged before its class exists. The validator collects tags across the whole
tree and warns about the ones nothing declares, because `&"blades"` for
`&"blade"` loads fine, validates fine per file, and counts toward nothing.

**The shop's KIND MIX is authored, never emergent.** `ShopData` holds two pools
and a `weapon_offer_chance` rolled per slot, rather than one merged pool. A
merged pool would let the mix be decided by how much content happens to exist -
authoring thirty weapons would silently make items rarer and invalidate every
balance judgement made before it. That is the same argument already written into
`ShopManager._draw` for weighting TIERS rather than items, and the suite asserts
it directly: with five weapons against one item, chance 0 offers no weapons and
chance 1 offers no items.

A slot whose rolled kind has nothing left falls back to the other kind rather
than coming back empty, so an empty weapon pool or an effect that filtered them
all out still fills the shop.

**Weapons live on `EntityModel`; `WeaponMount` is a VIEW of that list.** It used
to own the list, which is exactly why a weapon could not be bought, sold, saved
or authored on a character: the only caller that could add one was `main.gd`,
and nothing outside the scene layer could see what was carried. `WeaponMount.sync()`
diffs rather than rebuilding, because a `Weapon` node holds live state - heat,
burst progress, a swing halfway through its arc - and dropping it because a
different weapon was sold is a bug that can only surface mid-combat.

Capacity is answered by the MODEL alone. The shop has to ask "is there room"
before it takes any money, so both must ask the same place; `add_weapon` refuses
rather than overflowing, and a refusal there means a caller went around
`can_be_acquired_by`.

**Hooks are shared between purchase kinds; COUNTERS are not.** `ON_ITEM_BOUGHT`
fires for a weapon too, because a hook hands the entry over and an effect can
look at what it was. `WEAPONS_BOUGHT` is a separate counter because a counter is
a NUMBER effects do arithmetic on, and "for every 5 items bought" cannot un-mix
a weapon folded into the same tally.

**Shop slot count is a STAT, not a shop setting.** `SHOP_SLOTS` works exactly as
`WEAPON_SLOTS` does, so "this character sees 8 items", "this item grants a slot"
and "this curse takes one away" are ordinary modifiers and `ShopManager` never
learns any of them exist. 0 means the buyer has no opinion and
`ShopData.offer_count` stands.

**Item text is DERIVED, never authored per item.** A shop offer describes itself
from its own `static_stats` and `dynamic_effects`: `StatMetadata` supplies the
name and the format, `DynamicEffect.describe()` supplies the prose. A
hand-written description drifts from the numbers it describes the moment
somebody retunes one, and at a few hundred items it drifts SILENTLY — the text
still reads fine, it is simply no longer true.

Good and bad come from `StatMetadata.higher_is_better`, NOT from the sign. Less
spread and less recoil are improvements, so `-20%` on `SPREAD_ANGLE` draws
green. Colouring by sign tells the player a good item is a bad one.

Rendering a MODIFIER is not rendering a value: a `PERCENT` modifier of 0.5 is
"+50%" whatever the stat's own format says, because it is a proportion rather
than a quantity of the stat, while a `FLAT` one is in the stat's unit so +0.08
to `CRIT_CHANCE` reads "+8%".

**The character is a TILE, not a panel.** It sits last in the owned strip and
describes itself through the same block as any item, because from the player's
side "what am I carrying" and "what did I start with" are one question.
`EntityData` and `ItemData` carry the same shape under different names —
`base_stats`/`innate_effects` against `static_stats`/`dynamic_effects` — so the
strip flattens both into one entry type. The only real difference is that you
cannot sell yourself, and that falls out of the entry having no item rather than
out of a branch in the renderer.

**The stat sheet enumerates `StatSheet`, never the enum.** A stat authored later
appears without any screen being touched, and the validator asserts every value
in `StatTypes.Stat` is in the sheet exactly once — so forgetting metadata fails
validation instead of the stat silently never appearing. Values come from
`get_stat()`, which already includes every modifier-based effect; pipeline
effects deliberately get no row, because their value depends on the event and a
number would be fiction.

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

**The chance to apply a status belongs to the HIT, not to the status.**
`StatusEvent.chance` starts at 1.0, so an application site that does not set its
own base makes the status certain and turns "+10% chance to cause bleeding" into
"always, minus ten". `EffectApplyStatusOnHit.base_chance` therefore defaults to
0.0: an item grants nothing on its own and every point comes from stats. Fire
spreading off a corpse passes nothing and stays deliberate.

Note the corollary: a chance stat only reaches a status the status LISTS on its
CHANCE axis. `BLEED_CHANCE` does nothing for a bleed that never names it.

**A status snapshots its parameters from the APPLIER when it lands.** Damage,
tick rate, max stacks and duration are resolved onto the `ActiveStatus` and
never read live off the `.tres`, which is globally cached and therefore cannot
hold a per-player value. `StatusScaling` names which stat feeds which axis, and
generic composes with specific - bleed can read both `STATUS_CHANCE` and
`BLEED_CHANCE`, and an item raising either works with no branch anywhere. Same
reasoning as rolling crit once per shot: the applier may die long before the
poison wears off, and a buff expiring mid-duration must not retroactively weaken
something already ticking.

**A ticking status lives for a COUNT of ticks, not a span of seconds.**
`tick_count` defaults to 5 and a fresh application refreshes it. Seconds would
have been the same arithmetic right up until somebody modified the rate - at
+10% faster a 2.5-second bleed delivers five and a half ticks, which quietly
turns `BLEED_RATE` into a damage stat wearing a pacing stat's name. A faster
status delivers its five ticks SOONER and no more of them, and the suite asserts
the total is unchanged.

`base_duration` governs only statuses that never tick, such as slow.

**`WorldCensus` is DERIVED, never maintained by signals.** "For each burning
enemy" needs a live count, and an incremental counter that goes up on apply and
down on expiry breaks permanently and silently the first time an event is missed
- a target cleared by `clear_all()`, an enemy freed mid-burn - and afterwards
reports three burning enemies to an empty screen. Nothing detects that.
Recomputing cannot drift. The cost is one walk, cached per generation, so twenty
items asking the same question in a frame pay once.

It holds `WeakRef`s, so a freed enemy prunes itself and there is no
`unregister()` to forget. And it deliberately does NOT answer what `RunModel`
already answers - duplicating `living_player_count()` would create two counts
that eventually disagree, which is the same silent-drift bug through another
door.

**`ON_OUTGOING_DAMAGE` is the attacker's say WITH the target known.**
`CALCULATE_DAMAGE` cannot serve: it fires once per SHOT, before any target
exists, which is exactly what lets one `ShotSnapshot` feed eight pellets.
"+10% damage to burning enemies" has to see who is being hit. Offence runs
first, then `TAKE_DAMAGE` for defence - the same two-phase shape statuses use.

**`ON_TICK` is the only hook that fires on a SCHEDULE.** Everything else hangs
on an event. "+1% attack speed for each burning enemy" and health regeneration
both have answers that change with nothing to hang on, so they need a heartbeat;
`RunModel.advance_wave` fires it on every player once per frame with the census
in the payload.

An effect driven by it must be IDEMPOTENT - strip its whole contribution and
reapply - because a live count goes DOWN as well as up. `EffectStatPerCounter`
can be additive since a tally only grows; `EffectStatPerWorldCount` cannot.

**`EntityModel.world_position` is written by the view, read by core.** A bare
`Vector2` handed down once per frame from `Actor`, which is what lets `core/`
answer "what is within 90 units of this corpse" without ever seeing a Node -
the same trick `SpawnContext` uses. `core/` never writes it.

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

**Readiness goes through `RunModel.set_player_ready()`, never through
`ShopManager.set_ready()`.** The manager's flag is not what the run watches, so
calling it directly flips a boolean nobody reads and the shop never closes. The
UI did exactly that and the bug survived a full test suite.

**A test that follows the correct path cannot catch a caller taking a different
one.** That is the general lesson from the above, and it is worth more than the
bug: every readiness test called the run's function — precisely the step the UI
was skipping. When a bug is "the caller went around the API", the test has to
assert the difference between the two paths, not the behaviour of the right one.

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
per-player shop — rolling by tier weight, pipeline pricing, buying, selling,
rerolling, stat payment and ready-up — and a status system whose four statuses
differ only by authored numbers. Twenty-four items authored.

A run can be PAUSED and RESTARTED: any device opens one shared menu with resume,
restart and quit, and the same menu opens itself when the run ends, so a wipe no
longer means closing the executable.

The game starts in a LOBBY: up to four players join by pressing SPACE or A on
the device they intend to play with, one player per device, and any joined
player begins the run with START. It is deliberately a bare join screen - the
solo/co-op toggle, character select and run rules it will grow are decisions
taken before a run exists, and this is the place that has them.

Weapons carry CLASS TAGS, and holding several of a class grants authored stat
bonuses at authored thresholds - two classes exist so far, blade and gun, which
is what the four authored weapons divide into naturally.

WEAPONS ARE BOUGHT AND SOLD like items. They roll from their own pool at an
authored chance, take a WEAPON_SLOTS slot, appear in the hands the moment the
model changes, sit in the owned strip ahead of the items, and describe
themselves through the same derived block — a weapon needed no description code
of its own, because its damage and range were already StatModifiers. A character
now carries its own `starting_weapons`; `main.tscn` no longer holds a loadout.

The shop UI is playable end to end: per-player panels laid out by player count,
a cursor per player driven by that player's own device, offers, reroll, buying,
selling from the owned strip, the character as the last tile, a derived detail
block for whatever is highlighted, a stat sheet, on-screen control hints and
ready-up. The cursor returns to the first offer on every entry.

**Deliberately NOT polished yet.** Colours, borders, spacing and the shape of
the detail block wait for the art pass, because the layout constraints come from
content that does not exist — how long names get, how many stat lines a complex
item has. Tuning proportions against eight items means tuning them again at
fifty.

**Overflow is deferred with it, and that is a considered decision rather than an
omission.** The detail block will become a floating tooltip near the cursor with
its own maximum size and a stick-scroll for long descriptions, as the genre
does. The overflow rule belongs to THAT window; writing one for the current
inline block would be designing it twice. Nothing overflows today because no
authored item has more than two stat lines - though a weapon scaling off many
stats now can, which is the first content that will force the issue — which is exactly the sample size
that makes polishing now a mistake.

**No debug settings are currently active.**

**Working but temporary:**
- `RunModel.auto_intermission` is now **0**: the shop waits for every living
  player to declare ready and does not close itself. Capture runs set it back,
  because a scripted player never presses anything and would sit in the shop
  forever — any `--capture` gets 3 seconds unless `--capture-intermission=N`
  says otherwise.
- `player_count` and `player_devices` on `main.tscn` are now INJECTED by the
  lobby and matter only when that scene is launched on its own. To test co-op,
  join in the lobby or pass `--capture-players=N`.
- The test character carries eight `starting_items` purely to exercise bleed:
  two barbed edges and six serrated rounds, which is +90% bleed chance on top of
  each item's own base and therefore certain on every ranged hit. Strip them
  before judging anything about balance.
- `death_rule` is an export on `main.tscn`. When challenge modes arrive it wants
  to live in a `RunRulesData.tres` alongside `revive_hp_fraction` and whatever
  else a challenge varies, so a mode is one authored resource.

**Known gaps, worst first:** only FOUR WEAPONS are authored, which is now a
content gap rather than an engine one — the acquisition path exists and the
four axes cover most of what a weapon is, so the next ones are `.tres` files.
Then: no `BEAM` delivery,
no explosion/puddle effects on `ON_IMPACT`, no save system, no item icons, no
art (everything is drawn as placeholder circles, ellipses and lines), and no
buffs authored — the status machinery is valence-neutral and ready for them,
but nothing positive exists yet.

The effect library is **twelve classes**. It was four when the item list was
written, and the eight added since each cover a FAMILY rather than an item:
apply-a-status-on-hit, damage-versus-status, heal-when-hitting-status,
double-status-stacks, stat-per-world-count, and the three status kinds. That
ratio is the point - sixteen of the twenty-four authored items needed no new
code at all.

**Localisation is DEFERRED ON PURPOSE, and is not a gap.** `tr()` is already
wrapped around every `display_key` and `description_key`, so the door is open
and no content file will need touching. Until a translation is loaded, `tr()`
returns the key unchanged, which is why the shop reads `ITEM_WHETSTONE` rather
than a name. That looks like a placeholder and is not one.

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

## Authoring content: the order matters

**The item and weapon list comes FIRST, in prose, before any `.tres`. Effect
classes are derived from it, never invented ahead of it.** Ten effects thought
up in advance are ten solutions looking for a problem; a hundred items written
down first group themselves, and the repeats are the classes worth writing.

For each item, note the name, tier, rough price and then EITHER its stat lines
OR its behaviour in one sentence. That split is the whole point:

| kind | cost |
|---|---|
| a bundle of stat modifiers | **zero code** — a `.tres` and nothing else |
| a behaviour | one effect class, which usually covers a whole family |

In this genre most items are the first kind, so the majority of a list lands
without a line of GDScript. `EffectStatPerCounter` already covers every "for
every N of something, gain X" — when writing the list, mark which behaviours are
that same pattern with different numbers.

### Ten of the 45 stats do nothing, ON PURPOSE - and eleven more do nothing from a PLAYER

| state | stats |
|---|---|
| **read by something** | 35 of 45 |
| **cheap to wire** | ARMOR, LIFESTEAL, DODGE, HP_REGEN, CURRENCY_GAIN — one small effect class each, the mechanism already exists |
| **needs a whole system** | PICKUP_RANGE, LUCK, HARVESTING, ENGINEERING, ELEMENTAL_DAMAGE — no pickups, no luck rolls, no harvesting, no turrets, no elemental delivery |

**Do not measure this with `grep "Stat.<NAME>"` alone.** That was the method
here and it is now wrong: the eleven per-status axes plus `STATUS_CHANCE` and
the three status damage stats are reached by a `.tres` naming them through
`StatusScaling`, so no code ever mentions them and the grep reports them dead.
Count the content too, or the number will be off by fifteen.

The status stats used to be a third row waiting on authored content. That
content exists now, which is why the row is gone.

### The holder's stats reach their weapons through ONE method

`WeaponModel.combined_stat()` is how a weapon reads any stat, and every one of
the eleven sites that used to read `stats.get_stat()` directly now goes through
it. Before that, only MELEE_DAMAGE and RANGED_DAMAGE ever crossed from a holder
to their weapon: an ITEM granting attack speed, crit, range or spread moved a
number in the stat sheet and changed nothing about a shot, which made four
authored items decorative.

Three rules live in that one method, and each was a bug before it existed:

**`StatTypes.NEUTRALS` doubles as the COMBINATION RULE.** A stat's neutral is
the value at which it contributes nothing - 0 for a quantity, 1.0 for a
multiplier - so an additive identity means the two are added and a
multiplicative identity means they are multiplied. One table rather than two,
because the two facts must never disagree: adding a holder's 1.0 attack speed to
a weapon's 1.0 doubles every weapon's rate of fire out of nowhere.

*(This file previously predicted the rule would live on `StatMetadata`. It could
not: `StatMetadata` describes a stat for the UI and is loaded from `content/`,
which `core/` models cannot reach. `FLOORS` - a genuine gameplay property of a
stat - was already a const on `StatTypes`, and that is where this belongs too.)*

**Only the DEVIATION from neutral is shared.** Half of a 1.4 attack speed is
1.2, not 0.7. Halving the value would hand a well-equipped player a slower
weapon than an empty-handed one.

**Every entity is seeded with its multiplicative neutrals** (`EntityModel._seed_neutrals`).
A player's ATTACK_SPEED used to read its FLOOR of 0.05 because nothing ever set
a base, and the moment weapons started inheriting it that would have slowed
every gun to a twentieth. A floor is not a default.

**A holder's PERCENT scales the WEAPON, not their own copy of the stat.** This
was the second bug, found while testing the first: `machined_sights` grants -20%
SPREAD_ANGLE, the holder's own spread is zero, and a fifth of nothing is
nothing. What the player means by -20% spread is a fifth off the gun they are
holding, so `_combine_additive` reads the holder's POOLS apart - flat adds,
percent scales, and a share applies to both alike.

### A weapon's damage can come from any stat

`WeaponData.damage_scaling` is a list of (stat, coefficient): empty means "all
of my own damage type", which is what every weapon did implicitly before.

That one table covers two things at once. `(RANGED_DAMAGE, 0.5)` is the balance
lever for fast weapons - a flat bonus applies PER HIT, so without it the fastest
weapon in the game converts every damage item into more DPS than a slow one, and
wins by more the longer a run goes on. `(MAX_HP, 0.1)` and
`(MOVEMENT_SPEED, -0.03)` are weapons built for a build, and they cost no code.

An entry naming the weapon's OWN damage type is a share of the holder's bonuses;
one naming a FOREIGN stat contributes that stat's VALUE. Different operations,
deliberately, because "half my ranged damage" and "a tenth of my max HP" are
different sentences.

Only STATS can appear there. "The lower your health, the harder you hit" reads
`current_hp`, which is state rather than a stat and changes between shots -
that belongs in a `CALCULATE_DAMAGE` effect, which already exists. The table for
stats, the hook for state.

**There is no cap on how many stats one weapon reads, and signs may be mixed.**
Thirty entries with alternating signs are asserted in `weapon_test`, and a shot
scaled below zero deals NOTHING rather than healing what it hits, because
`DamageEvent.final_amount()` floors at zero. Two practical limits rather than
rules: `inheritance_share` scans its list per read, so a very long table is
linear work on a hot path, and the shop's detail block still has NO OVERFLOW
handling - a weapon with thirty scaling lines draws thirty of them straight off
the panel.

`WeaponData.stat_inheritance` is the same shape for the other question: how much
of the holder's attack speed, crit or range reaches this weapon at all. Unlisted
stats transfer in FULL, so a weapon says only what it withholds.

Both are DERIVED into the shop's detail block by `detail_notes()`, because a
mechanic the player cannot see reads as a bug - buy +50% ranged damage, watch
half of it vanish, conclude the item is broken.

**DO NOT wire these one at a time as they come up.** They are not independent:
ARMOR, DODGE and MAX_HP are one defensive system, and whether dodge is checked
before armor, whether armor scales with max HP, and whether either has
diminishing returns is a SINGLE decision. Wiring them piecemeal produces five
ad-hoc formulas that do not compose. LIFESTEAL and HP_REGEN have the same
problem through `CALCULATE_HEAL`. The plan is to settle them together once the
item list shows what the stats are actually for.

Armor is the instructive case: `EffectArmorFromMaxHp` already reduces damage
through `DamageEvent.absorbed`, so the pipeline plumbing works. What is missing
is only the bridge from the `ARMOR` STAT into it.

Two of the twenty-four authored items are decorative because of this and are known
to be: `riot_shield` grants ARMOR and `bloodstone` grants LIFESTEAL. They
display correctly and change nothing. Two is the count again: the four that were
decorative because their stat never crossed from holder to weapon now work,
which was a bug rather than a deferral and is fixed above.

**Weapons are cheaper than items.** They decompose onto four axes that already
exist — `FiringPattern` × delivery × `SpreadPattern` × `TargetSelector` — so
most new weapons are a new combination rather than new code. Naming those four
per weapon immediately exposes what the engine is missing. One hole is already
known: **`BEAM` delivery is not implemented**, so anything laser-shaped is
blocked.

**The list wants a SCALING COLUMN** beside the four axes: which stats feed each
weapon's damage and at what share, and how much attack speed or crit it
withholds. Both are authored tables now, so that column costs nothing but a
decision - and a fast weapon without one is the balance hole the whole mechanism
exists to close.

Authoring one is a single `.tres` and three lines of bookkeeping: give it `tier`
and `base_price` (they come from `ShopEntryData` now), list its `tags`, then add
it to `default_shop.tres`'s `weapon_pool`. A new CLASS is its own `.tres` plus
an entry in `default_classes.tres`. Nothing else — its stat lines are already
`StatModifier`s, so the shop describes it, prices it, sells it and buys it back
with no code. The validator fails a weapon in the pool priced at 0, warns when
the pool and `weapon_offer_chance` disagree, and warns about a tier whose weight
is zero at every wave, which is content that loads fine and is never seen.

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
| add a debug knob | say so under *Current state* — and delete the note when reverted |
| add a capture flag | the table and notes in *Verifying visual behaviour* |
| lose time to a non-obvious trap | *Rules that break things when violated* |
| settle something open | replace it with the decision AND its reason |
| add or remove tests | the assertion count in *How to run things* |
| author a new content type | a check in `validate_content.gd`, then the tree |

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
