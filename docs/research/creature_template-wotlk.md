# creature_template — WotLK 3.3.5a content on the 3.4.3.54261 client (wotlk_classic)

Deep verification of `creature_template` (+ its 3.4 split children) for adopting the
official TDB 3.4.3 companion world DB as the base for a 3.3.5a-content WotLK server.

- **`world_d`** = RAW TDB343 (3.4.3 official companion world DB) — the intended base for `world_c`.
- **`world_335`** = hand-curated 3.3.5a TrinityCore world DB (OLD monolithic schema).
- **`world_c`** = target server DB (empty for content; not written by this research).
- Core: repo `/Users/shinichi/Works/side-project/TrinityCore`, branch **wotlk_classic** (3.4.x).

## TL;DR verdict

**Adopt 343's `creature_template` (+ `_difficulty`/`_model`/`_gossip`/`_movement`) as the base. It is a strict superset of the 3.3.5a set with ZERO WotLK coverage loss.** Two corrective actions:

1. **Trim 95 post-WotLK rows** (all `entry > 43282`) — 3.4.x WotLK-Classic re-release additions (store mounts/pets, retail infra), none spawned, none referenced. Self-contained SQL below.
2. **Reconcile a schema drift** the raw TDB343 has vs. the wotlk_classic core HEAD: `mechanic_immune_mask` + `spell_school_immune_mask` were refactored into `CreatureImmunitiesId` + a `creature_immunities` table. The raw `world_d` still has the old mask columns; the core's loader/prepared statement selects `CreatureImmunitiesId`. The core DB migrations must be applied before load. (Flag for orchestrator; not a content defect.)

Everything else — the monolithic→split migration of the 29,923 shared rows — is semantically correct.

---

## Q1. Definitive column-split map (3.3.5 monolithic → 3.4 location)

Sources: `world_335`/`world_d` `SHOW COLUMNS`; core loaders in
`src/server/game/Globals/ObjectMgr.cpp` — `LoadCreatureTemplate` (L399-469),
`LoadCreatureTemplateModels` (L607-658), `LoadCreatureTemplateDifficulty` (L927+),
`LoadCreatureTemplateGossip` (L471-515); prepared statement
`WORLD_SEL_CREATURE_TEMPLATE` in `src/server/database/Database/Implementation/WorldDatabase.cpp:65`.

### Stays in `creature_template` (per-creature, difficulty-independent)
| 3.3.5 column | 3.4 column | note |
|---|---|---|
| entry | entry (PK) | |
| KillCredit1/2 | KillCredit1/2 | |
| name | name | `char(100)`→`mediumtext` |
| subname | subname | |
| IconName | IconName | |
| faction | faction | |
| npcflag | npcflag | widened `int`→`bigint` |
| speed_walk / speed_run / scale | same | |
| **rank** | **Classification** | renamed; same value domain (0 normal…3 world boss) |
| dmgschool | dmgschool | |
| BaseAttackTime / RangeAttackTime | same | |
| BaseVariance / RangeVariance | same | |
| unit_class | unit_class | |
| unit_flags / unit_flags2 | same | |
| family | family | widened `tinyint`→`int` |
| type | type | |
| PetSpellDataId | PetSpellDataId | |
| VehicleId | VehicleId | |
| AIName | AIName | |
| MovementType | MovementType | |
| ExperienceModifier | ExperienceModifier | |
| RacialLeader | RacialLeader | |
| movementId | movementId | |
| RegenHealth | RegenHealth | |
| flags_extra | flags_extra | |
| ScriptName | ScriptName | |
| StringId | StringId | |
| VerifiedBuild | VerifiedBuild | |

### Moved to `creature_template_difficulty` (per-DifficultyID row; key = Entry+DifficultyID)
| 3.3.5 column | 3.4 column |
|---|---|
| minlevel | MinLevel |
| maxlevel | MaxLevel |
| exp | HealthScalingExpansion *(loose — semantics changed, see note)* |
| mingold / maxgold | GoldMin / GoldMax |
| HealthModifier / ManaModifier / ArmorModifier / DamageModifier | same names |
| lootid | LootID |
| pickpocketloot | PickPocketLootID |
| skinloot | SkinLootID |
| type_flags | TypeFlags (+ new TypeFlags2) |

### Moved to `creature_template_model` (per-model row; key = CreatureID+Idx)
| 3.3.5 column | 3.4 column |
|---|---|
| modelid1..4 | one row each: CreatureDisplayID (+ DisplayScale, Probability) |

### Moved to `creature_template_gossip` (multi-valued; key = CreatureID+MenuID)
| 3.3.5 column | 3.4 |
|---|---|
| gossip_menu_id | MenuID (a creature may now list several) |

### Moved to `creature_template_movement`
| 3.3.5 column | 3.4 |
|---|---|
| **HoverHeight** (float) | **replaced** by `HoverInitiallyEnabled` (bool) — semantic change, old float value has no home |

### 3.3.5 columns with NO 3.4 home (dropped / refactored)
| 3.3.5 column | why |
|---|---|
| **difficulty_entry_1/2/3** | No direct column. In 3.4 a creature's per-difficulty variant is modeled as **extra `DifficultyID` rows on the same base entry** in `creature_template_difficulty` (e.g. Lich King 36597 carries DifficultyID 3/4/5/6). The old separate heroic-mode entries (39166 "The Lich King (1)", etc.) still exist as their own templates but are no longer pointed to by a link column. The 335 pointer semantics are superseded, not migrated 1:1. |
| **dynamicflags** | Removed from the template; handled at spawn/runtime (no template column in 3.4). |
| **mechanic_immune_mask** | Refactored **in core HEAD** into `CreatureImmunitiesId` (FK) + `creature_immunities` table. RAW TDB343 still carries the old mask columns — see Q5 schema-drift note. |
| **spell_school_immune_mask** | same refactor as above. |

### 3.4-only additions (no 335 source)
`creature_template`: femaleName, TitleAlt, RequiredExpansion, VignetteID, **unit_flags3**, trainer_class, Civilian, WidgetSetID, WidgetSetUnitConditionID, CreatureImmunitiesId.
`creature_template_difficulty`: HealthScalingExpansion, CreatureDifficultyID, TypeFlags2, StaticFlags1..8.
`creature_template_model`: DisplayScale, Probability.
`creature_template_movement`: Ground/Swim/Flight/Rooted/Chase/Random/InteractionPauseTimer/HoverInitiallyEnabled.

> **`exp` → `HealthScalingExpansion` caveat.** Not a clean rename. 335 `exp` is the content
> expansion (0/1/2). 343 `HealthScalingExpansion` is a health-scaling selector and diverges: e.g.
> Headless Horseman (23682) 335 `exp=2` → 343 `HealthScalingExpansion=9`; Lich King 335 `exp=2` →
> 343 `hse=2`. Treat as re-derived by TDB, not copied.

---

## Q2. Scope / post-WotLK leakage

**Row counts:** `world_d.creature_template` = 30,018; `world_335.creature_template` = 29,923.

### Bucket by entry range (world_d)
| bucket | rows | min | max |
|---|---|---|---|
| ≤ 43282 (WotLK range) | **29,923** | 1 | 43282 |
| 44k–99k | 1 | 91914 | 91914 |
| 100k–199k | 66 | 162539 | 199649 |
| 200k+ | 28 | 200848 | 213605 |

The WotLK-range bucket is **exactly 29,923** — identical to the entire 335 table (see Q3). The
leakage is precisely the **95 rows with `entry > 43282`**.

### RequiredExpansion AND VerifiedBuild are both useless as discriminators here
`SELECT RequiredExpansion, COUNT(*)` → **all 30,018 rows have RequiredExpansion = 0**. TDB343 does
not populate this field, so it cannot date rows.

VerifiedBuild is the WoWPacketParser sniff-build origin, so the "Cata+ build = contamination"
heuristic is worth testing — **and it fails here**, with evidence:
- All **95 leaked rows carry VerifiedBuild 52237** — the *same* build as the bulk of confirmed WotLK
  rows (27,314 of the ≤43282 rows are also 52237). 52237 is a **WotLK-Classic 3.4.x sniff build**
  (the 3.4.3 client is build 54261), not a retail Dragonflight build. The leakage entered via the
  3.4.x re-release sniffs, indistinguishable by build from legit WotLK rows.
- Conversely, **2,412 genuine WotLK-range creatures (≤43282) carry VerifiedBuild 15595 (Cata 4.3.4)**,
  121 carry 17658 (MoP 5.4), 12 carry 24330 (Legion) — because those WotLK creatures still existed in
  later clients and were re-sniffed there. Applying "Cata+ = contamination" would wrongly flag 2,545+
  real WotLK creatures.

So neither field distinguishes WotLK from post-WotLK. **Entry range + spawn presence are the only
reliable discriminators**, and they agree cleanly on the 95.

### The 95 leaked rows are real post-WotLK content, not renumbered WotLK creatures
- **0 of 95 are spawned** in `world_d.creature` (`spawned_high = 0 / 95`). All WotLK spawns are on WotLK maps and reference entries ≤ 43282.
- **0 of 95 are referenced** by `npc_vendor.entry`, `creature_queststarter/questender.id`, `creature_summon_groups.summonerId`, or any `KillCredit1/2`.
- Names date them unambiguously to post-WotLK / 3.4.x re-release additions. Adjudicated against wowhead (wotlk view) + warcraft.wiki.gg:
  - **200848 Celestial Steed** — first Blizzard **real-money store mount, April 2010** (Cata pre-patch era); item 54811. Folded into 3.4.x Classic via store/Trading Post. Wowhead's *wotlk* view lists it because that view reflects the **3.4.x WotLK Classic client**, which Blizzard seeded with retail store content — **not** original 3.3.5a. [wowhead](https://www.wowhead.com/wotlk/npc=200848/celestial-steed)
  - **213605 Arfus** — retail Blizzard-store corgi pet, backported to WotLK Classic. Shows in wowhead wotlk view for the same reason. [wowhead](https://www.wowhead.com/wotlk/npc=213605)
  - **162539 World Talent Master**, **91914 Auction House** — 3.4.x client infrastructure NPCs.
  - **211025 Lil' Wrathion** (MoP), **211011 Auspicious Arborwyrm** (Dragonflight mount), **198525 Festering Emerald Drake**, **176708 Reawakened Phase-Hunter** (WoD), plus a large tail of `[DNT]`/test/trigger dummies (Boss Dummy, QA Test Dummy 80, Leap Target, Invisible Bunny, etc.).

**Independent emu confirmation (AzerothCore, 3.3.5a).** Cross-checked 9 of the 95 leaked entries
(91914, 162539, 166359, 200848, 211011, 211025, 213605, 198525, 176708) against AzerothCore's
hand-curated 3.3.5a `creature_template` (fetched from
`github.com/azerothcore/azerothcore-wotlk .../db_world/creature_template.sql`): **all 9 are ABSENT**
from AzerothCore. All six WotLK control samples (36597/33288/448/25/23682/36855) are present. So two
independent 3.3.5a WotLK databases (TrinityCore 335 and AzerothCore) agree these entries are not
WotLK content — this is the strongest available verdict short of a Blizzard source.

> **Interpretation for a 3.3.5a-content server.** These 95 are content the *3.4.3 client* knows
> (so keeping them causes no client-side error) but that is **not part of 3.3.5a content**. They are
> inert (unspawned, unreferenced) — harmless if left, but out-of-scope clutter. Trimming them yields
> a clean 3.3.5a creature set (see Q5).

> **Orphan child row (unrelated to the 95):** `creature_template_difficulty` has rows for
> `Entry = 197830`, which has **no** parent in `creature_template`. On load the core logs
> *"Creature template (Entry: 197830) does not exist but has a record in creature_template_difficulty"*
> (`ObjectMgr.cpp:958`). The `entry > 43282` cleanup below removes it too.

> **Adjacent contamination, out of scope but worth flagging:** `world_d.npc_vendor` references vendor
> creature entries up to **205350** (47,635 rows, ~hundreds of distinct entries > 43282 that don't
> even exist in creature_template). That is a *different* table's contamination — note it for the
> npc_vendor verification pass; it does not affect creature_template.

---

## Q3. WotLK coverage gap — NONE

```
world_335 rows                                     = 29,923
world_d rows with entry ≤ 43282                    = 29,923
rows present in BOTH (join on entry)               = 29,923
world_335 entries NOT IN world_d                   =      0
```

**343 is a strict superset of 335: every one of the 29,923 hand-curated 3.3.5a entries exists in
TDB343, and TDB343 drops zero WotLK creatures.** The only difference is the 95 extra post-WotLK rows
343 adds on top. There is nothing to backport from 335 at the row/entry level.

**Three-way triangulation of the WotLK creature count** (independent sources converge):
| source | WotLK creature_template rows |
|---|---|
| TrinityCore 335 (world_335) | 29,923 |
| TDB343 world_d, entry ≤ 43282 | 29,923 |
| AzerothCore master (db_world/creature_template.sql) | ~29,947 |

All three land within ~0.1% of each other, and 335 ⊆ 343 exactly. The tiny AC delta is AzerothCore's
own custom/quest-helper NPCs, not a WotLK gap in 343. No independent source suggests 343 dropped
WotLK content.

(Field-level differences within shared rows are a separate question — 335 remains authoritative for
TrinityCore-specific/server fields like ScriptName, AIName, flags_extra, faction fixes; those are not
a *coverage* gap and are handled by the per-field source policy, not by adding rows.)

---

## Q4. Split-table population correctness (spot checks)

For each sample: 335 monolithic row vs. 343 split children. Verdict = semantically correct.

| entry | name | 335 modelid1 | 343 model (Idx0) | 335 gossip | 343 gossip | 335 rank | 343 Classification |
|---|---|---|---|---|---|---|---|
| 36597 | The Lich King | 30721 | 30721 ✓ | 0 | (none) ✓ | 3 | 1* |
| 33288 | Yogg-Saron | 28817 | 28817 ✓ | 0 | (none) ✓ | 3 | 1* |
| 36855 | Lady Deathwhisper | 30893 | 30893 ✓ | 0 | (none) ✓ | 1 | 1 ✓ |
| 448 | Hogger | 384 | 384 ✓ | 0 | (none) ✓ | 1 | 1 ✓ |
| 25 | Mithril Mechanical Dragonling | 4465 | 4465 ✓ | 0 | (none) ✓ | 0 | 0 ✓ |
| 23682 | Headless Horseman | 22351 | 22351 ✓ | 0 | (none) ✓ | 1 | 1 ✓ |

*Classification for world bosses (36597/33288) reads 1 in 343 vs rank 3 in 335 — this is TDB343's
own value (the 3.4 Classification enum differs from the 335 rank enum), not a split error.

**Difficulty split — Lich King 36597** (335 `difficulty_entry_1/2/3 = 39166/39167/39168`):
343 `creature_template_difficulty` holds 4 rows keyed by DifficultyID 3/4/5/6, with the base row
(DiffID 3) LootID 36597 and the heroic rows carrying LootID 39166/39167/39168 — i.e. the old
`difficulty_entry` targets are preserved as the per-difficulty loot/stat rows. 335 base stats
(HealthModifier 1250, ManaModifier 500, DamageModifier 139) are preserved exactly in the base
difficulty row; heroic rows add higher scaling. **Correct.**

**Gold nuance:** 343 refreshes some gold values (e.g. LK 335 min/max 1000000/1200000 → 343
1300000/1500000; Yogg 1800000/2000000 → 2020000/2220000). These are TDB343's own value updates, not
split corruption — semantically fine, verify against desired 3.3.5a economy if it matters.

**Verdict:** the monolithic→split migration preserved 335 values correctly (models, gossip absence,
level, modifiers, loot, difficulty structure). No split defects found in the sample.

### Model DisplayID validation — confirmed against the exact build via wago.tools
The 3.4.3 client's `CreatureDisplayInfo.db2` validates DisplayIDs, and the core validates every one
at load: `LoadCreatureTemplateModels` (ObjectMgr.cpp:637-640) logs *"lists non-existing
CreatureDisplayID id (X), this can crash the client"* per bad id.

**All six sample DisplayIDs exist in CreatureDisplayInfo for build 3.4.3.54261** (queried live from
[wago.tools](https://wago.tools) `db2/CreatureDisplayInfo/csv?build=3.4.3.54261`):

| DisplayID | creature | wago ModelID (build 54261) |
|---|---|---|
| 30721 | Lich King | 3232 ✓ |
| 28817 | Yogg-Saron | 3081 ✓ |
| 30893 | Lady Deathwhisper | 3257 ✓ |
| 384 | Hogger | 123 ✓ |
| 22351 | Headless Horseman | 2633 ✓ |
| 4465 | Mithril Mechanical Dragonling | 6 ✓ |

So `creature_template_model` DisplayIDs for the sampled WotLK creatures are client-valid for the exact
target build. (The local CASC mirror at `wow343-archive/casc-out` could **not** be used — only
`SpellName.db2` content was pre-fetched; `CreatureDisplayInfo.db2` FDID 1108759 reports its content
ckey "NOT in encoding" — so wago.tools was used as the build-specific oracle instead.) The only
untested DisplayIDs are the >43282 models, which the cleanup deletes. **A full pass over all 40,683
`_model` rows still belongs in the orchestrator's DBErrors.log run**, but the sample gives confidence
the extraction is sound.

---

## Q5. Verdict + corrective SQL

**Adopt 343's `creature_template` family as the base.** It contains 100% of the 3.3.5a WotLK creature
set (29,923/29,923), drops none, and the split into `_difficulty`/`_model`/`_gossip`/`_movement` is
semantically faithful. Two corrections:

### Correction A (content) — trim 95 post-WotLK rows
All post-WotLK leakage is exactly `entry > 43282` (335's max WotLK entry). Safe: none spawned, none
referenced. Self-contained (no cross-DB references), run against `world_c`:

```sql
-- Remove post-WotLK creature_template contamination (3.4.x re-release additions,
-- store mounts/pets, retail infra, test dummies). 95 rows; none spawned or referenced.
-- Also clears their split-table children and the orphan difficulty row (Entry 197830).
DELETE FROM creature_template_gossip     WHERE CreatureID > 43282;
DELETE FROM creature_template_model      WHERE CreatureID > 43282;
DELETE FROM creature_template_difficulty WHERE Entry      > 43282;
DELETE FROM creature_template_movement   WHERE CreatureId  > 43282;
DELETE FROM creature_template            WHERE entry       > 43282;
```

Expected effect: `creature_template` 30,018 → 29,923; `_model` −115; `_difficulty` −2 (incl. orphan
197830); `_gossip` −0; leaves a clean set whose entry domain equals 3.3.5a exactly.

*(Optional stricter variant if you want to keep any specific summon-only re-add: intersect the 95
list against your WotLK spell `SummonCreature` effects first. As analyzed, none of the 95 are the
WotLK-era versions — those already exist at low entries, e.g. WotLK Mirror Image is 31216, not the
high-id 198706 — so the blanket `> 43282` predicate is correct.)*

### Correction B (schema, not content) — reconcile immunity-mask refactor
The **raw TDB343 `world_d` schema predates the wotlk_classic core HEAD.** The core's prepared
statement selects `CreatureImmunitiesId` and joins `creature_template_movement`
(`WorldDatabase.cpp:65`), and the branch base schema (`sql/base/dev/world_database.sql`) defines
`creature_template.CreatureImmunitiesId` (line 1001) + a `creature_immunities` table (line 724) with
**no** `mechanic_immune_mask` / `spell_school_immune_mask` columns (grep count 0). Raw `world_d` still
has the two mask columns and lacks `CreatureImmunitiesId`. **The core will not load `world_d`'s
`creature_template` until the DB is brought to HEAD** (apply `sql/updates/world` migrations), which
converts the mask *values* into `creature_immunities` rows + `CreatureImmunitiesId` FKs. This is a
build-the-base step, not a content defect — but it must happen, and the mask data must be preserved
through it. **Flag for the orchestrator** (the same reload that produces DBErrors.log).

### What does NOT need doing
- **No backport of missing WotLK creatures** — coverage gap is zero.
- **No RequiredExpansion-based filtering** — the field is uniformly 0 in TDB343.
- No row-level surgery on the 29,923 shared entries; field-level source policy (335 vs 343) is a
  separate, per-column decision handled elsewhere.

---

## Appendix — the 95 leaked entries (all `entry > 43282`)

```
91914 Auction House · 162539 World Talent Master · 166359 Zulian Tiger · 168833 Nate Yurisist ·
168834 Phlas Kanfrost · 169106 Shea Dorrisist · 173338/174404/186207 Invisible Bunny ·
173754 Major Mattingly · 173758 Overlord Runthak · 176437 Heigan Aggro Trigger · 176443 Dummy ·
176490/176525 The Prophet Skeram · 176546/176547/176663 Call for Help Trigger · 176552 Orgrimmar ·
176553 Stormwind · 176708 Reawakened Phase-Hunter · 177064 Spellcaster Dummy ·
177297 Nexus-Lord Donjon Rade Jr. · 177659 Boss Dummy · 178420 Magister Astalor Bloodsworn ·
178449 Generic Hunter Pet · 178858 Captain Placeholder · 179017 Raid Buffer · 180757 Leap Target ·
180982 Atrejo's Test Creature · 181485 Flurky · 181670 Resistance Armor Vendor ·
181684 [DND] TAR Pedestal · 181760 Arena Bulletin Board · 184259-184263/184837 Night Lord/Wanton
Host/Zealous Consort (+transform visuals) · 185317/185335/185336 Incubus · 185331-185335 Avelina
Lilly / Isaac Pearson (+projections) · 185400-185404 Talarian/Elodrius/Cyriden/Relathor ·
185560 Satyr Vision · 185664 Razorsaw Transform · 189739 Kalu'ak Whalebone Glider ·
192218 QA Test Dummy 80 Spell Spammer 2 · 194795 Fishspeaker Irtusk · 194870 Pebble ·
196503 Hao-Yue · 196534 Hoplet · 198525 Festering Emerald Drake · 198706/205997-205999 Mirror Image ·
198875 Thassarian · 198901/205890 Zidormi · 198934 [DNT] Image of Thrall · 199387 D3-BA ·
199411 Dungeon Gearataur · 199649 Crafted Gearataur · 200848 Celestial Steed · 200900 Glub ·
201106 Plague Master · 202935 Elder Clearwater · 205838 Anub'ar Webweaver · 205958 Zombie Horror ·
206038 Immortal Crusher Tentacle · 206762 Nerub'ar Spiderling · 207128 Animated Constellation ·
207484/207489 [DNT] Light/Dark Essence · 208033 Nightmarish Emerald Drake ·
209070/209074 Northrend Daily Dungeon Roll Bunny · 211011 Auspicious Arborwyrm · 211012 Cypress ·
211025 Lil' Wrathion · 211026 Avatar of Flame · 211297 Silver Covenant Warden ·
211299 Sunreaver Warden · 211332 Korralin Hoperender · 211340 Kolara Dreamsmasher · 212241 Peletort ·
213605 Arfus
```

## Sources
- **Core (branch wotlk_classic):** `src/server/game/Globals/ObjectMgr.cpp` (LoadCreatureTemplate L399, Models L607, Difficulty L927, Gossip L471); `src/server/database/Database/Implementation/WorldDatabase.cpp:65` (WORLD_SEL_CREATURE_TEMPLATE prepared stmt); `sql/base/dev/world_database.sql` (L724 creature_immunities, L1001 CreatureImmunitiesId, L1044/1082/1116 split tables).
- **DBs:** `world_d` (RAW TDB343), `world_335`, via `docker exec tdb343-db-1 mariadb`.
- **Client / build-specific (wago.tools):** [CreatureDisplayInfo @ build 3.4.3.54261](https://wago.tools/db2/CreatureDisplayInfo?build=3.4.3.54261) — CSV endpoint used to confirm sample DisplayIDs (30721/28817/30893/384/22351/4465 all present). Local CASC extract tool `wow343-archive/tools/extract_db2_by_fdid.py` (CreatureDisplayInfo FDID 1108759) — content not in local mirror; wago.tools used instead.
- **Independent 3.3.5a emu (AzerothCore):** [azerothcore-wotlk .../db_world/creature_template.sql](https://github.com/azerothcore/azerothcore-wotlk/blob/master/data/sql/base/db_world/creature_template.sql) — ~29,947 WotLK rows; all 9 sampled leaked entries absent, all 6 WotLK samples present. (cmangos/mangos-wotlk available as a further tie-breaker; not needed — AC + 335 already agree.)
- **wowhead / wiki (expansion dating):** [Celestial Steed 200848](https://www.wowhead.com/wotlk/npc=200848/celestial-steed) (2010 store mount), [Arfus 213605](https://www.wowhead.com/wotlk/npc=213605) (retail store pet); warcraft.wiki.gg. Note: wowhead's *wotlk* view reflects the 3.4.x WotLK Classic client, which Blizzard seeded with retail store content — presence there ≠ 3.3.5a content.
