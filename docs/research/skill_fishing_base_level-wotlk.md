# `skill_fishing_base_level`: WotLK 3.3.5a correctness vs TDB343

Research date: 2026-09-12. Question: for a WotLK 3.3.5a-content world DB, which
dataset is correct — the all-positive `world_335` values (115 rows) or the
lower/negative TDB343 values (104 rows, e.g. entry 1 → -70)?

## TL;DR recommendation

Import the **all-positive 3.3.5a dataset (`world_335`, 115 rows)**. Do **not**
use TDB343's values as-is. The negative/lowered TDB343 numbers are **not**
WotLK-authentic; every authoritative source for the WotLK-era table gives
**positive** per-zone thresholds in the ~25–575 range. A delta update replacing
the TDB343 `skill_fishing_base_level` contents with the 335 dataset **is
warranted**.

---

## 1. What the column means and how the core consumes it

`skill_fishing_base_level(entry = area id, skill = base fishing skill for that
zone)`. Schema: `skill` is `SMALLINT` **signed**, so negatives are storable but
not necessarily meaningful.
[[base schema]](../../sql/base/dev/world_database.sql) (lines ~4055–4059:
`skill smallint NOT NULL ... COMMENT 'Base skill level requirement'`).

The value is consumed by the fishing-catch roll in
`GameObject::Use` (fishing node), this repo (wotlk_classic / 3.4.3 branch):

```
int32 areaFishingLevel = sObjectMgr->GetFishingBaseSkillLevel(areaEntry);
int32 playerFishingLevel = player->GetSkillValue(playerFishingSkill);
int32 chance = 100;
if (playerFishingLevel < areaFishingLevel)
    chance = int32(pow((double)playerFishingLevel / areaFishingLevel, 2) * 100);
    // clamped to >= 1
// if (chance >= roll) -> real fish loot; else -> junk / "got away"
```
[src/server/game/Entities/GameObject/GameObject.cpp:2925-2946]

This matches the documented canonical formula
`chance = MAX(1, (playerSkill / areaSkill)^2 * 100)` — "minimum skill required
to fish an area with 100% success."
[[TrinityCore DB wiki, skill_fishing_base_level]](https://trinitycore.info/database/335/world/skill_fishing_base_level)

**Consequence of a negative base level:** `playerFishingLevel` is a real skill
value (>= 1, always non-negative). If `areaFishingLevel` is negative, the guard
`playerFishingLevel < areaFishingLevel` is **always false**, so `chance` stays
at 100 → **guaranteed real-fish loot, no junk, at any skill**. A negative base
level therefore means "this zone has no skill gate at all." That is post-WotLK
"fish anything" behaviour, not WotLK's graded junk-vs-fish curve. It is not a
crash/validation error (`LoadFishingBaseSkillLevel` accepts it via
`GetInt16`), just a silently degenerate gate.
[src/server/game/Globals/ObjectMgr.cpp:8724-8758,
src/server/game/Globals/ObjectMgr.cpp:7763-7780]

## 2. What the canonical WotLK 3.3.5a data is

All authoritative WotLK-era sources give **positive** values only:

- TrinityCore's own 3.3.5 DB documentation describes the table as the
  "minimum skill level required to fish an area with 100% success," with
  example rows such as `entry=1 → 25`, `entry=17 → 75`, `entry=40 → 75` — all
  positive. [[trinitycore.info 335]](https://trinitycore.info/database/335/world/skill_fishing_base_level)
  [[AzerothCore (a 3.3.5a fork) wiki]](https://www.azerothcore.org/wiki/skill_fishing_base_level)
- TrinityCore issue #23139 ("fishing too easy?") proposes a full corrected
  3.3.5 dataset with values "ranging from 25 to 575" (all positive), sourced
  from WoWWiki fishing tables and archived El's fishing data. The complaint is
  that TC's stock values are the *old minimum-to-cast* numbers instead of the
  higher *"no-junk"* numbers — i.e. the debate is entirely within the positive
  range; negatives are never in scope.
  [[Issue #23139]](https://github.com/TrinityCore/TrinityCore/issues/23139)
- The user's `world_335` sample values (entry 1 → 25, entry 8 → 225, entry
  16 → 300) sit squarely in this canonical positive band and match the
  WoWWiki-derived zone thresholds. TDB343's entry 1 → -70, entry 16 → 205 do
  not.

**Verdict Q1:** the all-positive `world_335` values are the WotLK-correct data.
TDB343's lowered/negative values are not.

## 3. Are the TDB343 negatives a bug or an intentional post-WotLK rescale?

Fishing history (primary/wiki):

- **Patch 3.1.0 (2009-04-14)** removed the *minimum skill to cast* in a zone:
  "There is no longer a minimum skill requirement to fish in any zone." After
  3.1.0 every cast catches *something*; if your skill is too low for the zone
  you catch "mostly vendor trash," and the skill at which you stop catching
  junk is the old "no getaway" threshold.
  [[Warcraft Wiki – Fishing]](https://warcraft.wiki.gg/wiki/Fishing)
- This is exactly the 3.3.5a model TrinityCore implements: a **positive**
  per-zone `skill` still governs the junk-vs-fish ratio via the `(skill/base)^2`
  curve. So within WotLK the per-zone thresholds remain meaningful and positive.
- Blizzard continued flattening fishing after WotLK (Cataclysm-era changes tied
  fishing to the pole and progressively removed the low-skill junk penalty),
  moving the game toward "catch anything anywhere."

TDB343 is the **3.4.x "WotLK Classic" TrinityCore world DB, machine-regenerated
from modern (post-WotLK Classic-client) game data**, not hand-curated 3.3.5a
data. Its systematically-lower, sometimes-negative base levels reflect that
later, flattened fishing model — not the WotLK 3.3.5a graded model. There is no
authoritative WotLK source that lists negative base levels, and TrinityCore's
own 3.3.5 data debates never leave the positive range. The negatives are best
read as a **post-WotLK/regeneration artifact** (a de-facto "no skill gate"),
not an intentional WotLK value and not a hard bug in the loader.

**Verdict Q2:** the negatives are a post-WotLK rescale/regeneration artifact.
They produce Cataclysm-style "always catch real fish" behaviour, which is wrong
for a 3.3.5a-content server.

## 4. Is the ~11-row difference (115 vs 104) meaningful?

Yes — it is coverage lost, not noise. The 335 dataset is the hand-maintained
3.3.5a set (TrinityCore has a long history of DB commits adding per-zone fishing
base levels: Zul'Gurub, Gundrak, Underbog, Violet Hold runtime-error fix, Molten
Core / Blackrock, Veiled Sea, Obsidian Sanctum, etc.).
[git log -S skill_fishing_base_level: e.g. "DB/Fishing: Fishing level
requirement for Zul'Gurub", "DB/Misc: Kill runtime error when someone fishes on
Violet Hold", "DB/Loot: Add fishing base level to Underbog"]

The machine-regenerated TDB343 set drops ~11 of these WotLK areas. For any area
that is fishable in 3.3.5a but missing from the table, `GetFishingBaseSkillLevel`
falls back to the parent area and, failing that, logs
`Fishable areaId {} is not properly defined in 'skill_fishing_base_level'` and
returns 0. [src/server/game/Globals/ObjectMgr.cpp:7773-7779] So the missing rows
mean lost per-zone tuning and/or console spam on those zones.

**Verdict Q3:** the extra ~11 rows in 335 are meaningful WotLK coverage; 343
simply omits them.

---

## Recommendation for the WotLK 3.3.5a world DB

1. **Use the `world_335` `skill_fishing_base_level` (all 115 positive rows).**
   It matches the WotLK 3.3.5a gameplay model and TrinityCore's own catch
   formula.
2. **Apply a delta update against raw TDB343**: `TRUNCATE skill_fishing_base_level;`
   then re-insert the 335 rows (or, per-row, overwrite every TDB343 value with
   the 335 value and add the ~11 missing entries). Keeping raw TDB343 values —
   especially the negatives — gives Cataclysm-style "no skill gate" fishing and
   risks "not properly defined" errors on the dropped zones.
3. Optional upgrade (not required for authenticity): if you want the stricter,
   more Blizzlike WotLK *"no-junk"* thresholds rather than the older
   minimum-to-cast numbers, adopt the corrected dataset proposed in
   TrinityCore issue #23139 (25–575, all positive). This is a refinement on top
   of the 335 data, orthogonal to the 335-vs-343 decision.

## Sources

- [TrinityCore DB wiki – skill_fishing_base_level (335)](https://trinitycore.info/database/335/world/skill_fishing_base_level)
- [AzerothCore wiki – skill_fishing_base_level (3.3.5a fork)](https://www.azerothcore.org/wiki/skill_fishing_base_level)
- [TrinityCore Issue #23139 – "fishing too easy?"](https://github.com/TrinityCore/TrinityCore/issues/23139)
- [TrinityCore Issue #17502 – required fishing skill for Wintergrasp](https://github.com/TrinityCore/TrinityCore/issues/17502)
- [Warcraft Wiki – Fishing (skill history, Patch 3.1.0 removal of zone minimums)](https://warcraft.wiki.gg/wiki/Fishing)
- Local source (wotlk_classic / 3.4.3 branch): `GameObject.cpp:2925-2946`,
  `ObjectMgr.cpp:7763-7780` & `8724-8758`, `Player.cpp:5111-5136`,
  `sql/base/dev/world_database.sql:4055-4059`.
