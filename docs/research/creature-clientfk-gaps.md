# Creature client-FK gaps (TDB343 on 3.4.3.54261 WotLK client)

Investigation of five clusters of client-side foreign-key mismatches in TDB343 (`world_d`)
creature data, restricted to WotLK-range creatures (`entry <= 43282`, i.e. NOT the 95 known
contamination rows). For each cluster: the TRUTH, the root cause, cross-checks, core impact,
and a self-contained corrective SQL (no reference to `world_335`/`world_d`/`world_c`).

## Method / sources

- **TDB343 (`world_d`)** and **3.3.5a gold-standard (`world_335`)** queried via
  `docker exec tdb343-db-1 mariadb -uroot -ptrinity <db>`.
- **3.4.3.54261 client reference sets** read from
  `/Users/shinichi/Works/side-project/wow343-archive/tools/refcache.sqlite`
  (`db2_FactionTemplate`, `db2_CreatureFamily`, `db2_Vehicle`, `db2_CreatureDisplayInfo`,
  `db2_SpellName`). NOTE: the `ID` columns are stored as TEXT — cast with `CAST(ID AS INTEGER)`
  or comparisons silently fail (max looks like 996 instead of 3152).
- **Core handling** grepped in `src/server/game/Globals/ObjectMgr.cpp` (branch `wotlk_classic`).
- wowhead/wotlk, wowhead retail, AzerothCore (github/wiki).

Overarching finding: TDB343 is the **modern retail TrinityCore database**. Every "bad" value in
these clusters is a **post-WotLK (Cataclysm+) retail value** that landed on a classic creature
whose zone/model/faction was revamped after WotLK. `world_335` holds the correct WotLK value in
almost every case. The 3.4.3 client is Wrath-Classic and does not ship these later entities.

---

## Cluster 1 — creature_template.faction — VERDICT: 343 post-WotLK data error. FIX.

**Truth:** All 24 distinct FactionTemplate IDs (2153, 2154, 2159, 2160, 2161, 2167, 2183, 2184,
2200, 2201, 2205, 2213, 2240, 2252, 2263, 2266, 2273, 2313, 2358, 2363, 2364, 2375, 2468, 2663)
are **absent from the 3.4.3 client `db2_FactionTemplate`** (845 rows, real max ID 3152). They are
**not** WotLK templates the client dropped — they are the post-Cataclysm faction templates that
the retail sniff assigned to these revamped old-world creatures. 82 rows affected.

**Cross-check (`world_335`):** every affected creature has a *different, small, valid* WotLK
faction template — and all of those DO exist in the 3.4.3 client. The 343 values also collapse
several distinct WotLK factions into one (e.g. 343 `2468` covers creatures that in WotLK are
1354/1355/71/35), which is the signature of a later-expansion faction consolidation, not a remap.

| Creatures (examples) | 343 faction (bad) | WotLK faction (world_335) |
|---|---|---|
| Moonstalker Runt/Matriarch/Sire (2070,2071,2237) | 2153 | 14 |
| Bonechewer Savage/War Wolf (16909,16926) | 2159 | 1663 |
| Gelkis centaur (4646–4661) | 2183 | 132 |
| Magram centaur (4638–4645) | 2184 | 133 |
| Marshal expedition NPCs, Gibbert… (3000,9117,9270…) | 2263 | 35 / 474 |
| Grimtotem (11858–11913) | 2266 | 16 |
| Dragonmaw (1034–1057) | 2273 | 62 |
| Ravasaur/Frostsaber/Lashtail (1016,6505,7431…) | 2358 | 48 / 16 |
| Argent Dawn (11194,16378,28247) | 2363 | 814 / 1625 / 2073 |
| Shen'dralar (14355–16032) | 2468 | 1354 / 1355 / 71 / 35 |

**AzerothCore agreement:** AzerothCore (WotLK) issue #7339 and its Gelkis/Magram reputation code
confirm the Gelkis/Magram hostile clans use reputation Faction 92/93, whose FactionTemplates are
**132 / 133** — exactly the `world_335` values, not 2183/2184.

**Core impact:** `ObjectMgr::CheckCreatureTemplate` (ObjectMgr.cpp:1053-1057):
```
FactionTemplateEntry const* factionTemplate = sFactionTemplateStore.LookupEntry(cInfo->faction);
if (!factionTemplate) { TC_LOG_ERROR(... "set to faction 35."); cInfo->faction = 35; }
```
No crash — but the creature is **forcibly reset to faction 35 (friendly-to-all)**. This is a real
gameplay bug: hostile Gelkis/Magram/Dragonmaw/Grimtotem become non-attackable neutral mobs.

**Recommended action: FIX** to the WotLK faction. Self-contained SQL:

```sql
UPDATE creature_template SET faction=14   WHERE entry IN (428,2070,2071,2237);
UPDATE creature_template SET faction=16   WHERE entry IN (7431,7432,11858,11910,11911,11912,11913);
UPDATE creature_template SET faction=22   WHERE entry IN (2349);
UPDATE creature_template SET faction=24   WHERE entry IN (206,920);
UPDATE creature_template SET faction=35   WHERE entry IN (3000,7013,9117,9270,9271,9997,10977,12959,15774,23211,32870,35085,35086,35088,35091);
UPDATE creature_template SET faction=44   WHERE entry IN (2165);
UPDATE creature_template SET faction=48   WHERE entry IN (1016,1019,6505,6506);
UPDATE creature_template SET faction=62   WHERE entry IN (1034,1035,1036,1038,1057);
UPDATE creature_template SET faction=69   WHERE entry IN (3442);
UPDATE creature_template SET faction=71   WHERE entry IN (14364);
UPDATE creature_template SET faction=74   WHERE entry IN (6190,6195);
UPDATE creature_template SET faction=126  WHERE entry IN (3188);
UPDATE creature_template SET faction=132  WHERE entry IN (4646,4647,4648,4649,4651,4652,4653,4661);
UPDATE creature_template SET faction=133  WHERE entry IN (4638,4639,4640,4641,4642,4643,4644,4645);
UPDATE creature_template SET faction=474  WHERE entry IN (10302,10583);
UPDATE creature_template SET faction=475  WHERE entry IN (9460);
UPDATE creature_template SET faction=814  WHERE entry IN (11194);
UPDATE creature_template SET faction=994  WHERE entry IN (15187,15188);
UPDATE creature_template SET faction=1194 WHERE entry IN (16134);
UPDATE creature_template SET faction=1354 WHERE entry IN (14355,14358,14361,16032);
UPDATE creature_template SET faction=1355 WHERE entry IN (14368,14369,14371,14381,14382,14383);
UPDATE creature_template SET faction=1475 WHERE entry IN (14622);
UPDATE creature_template SET faction=1625 WHERE entry IN (16378);
UPDATE creature_template SET faction=1663 WHERE entry IN (16909,16926);
UPDATE creature_template SET faction=2073 WHERE entry IN (28247);
```
All 25 target FactionTemplate IDs were verified present in the 3.4.3 client `db2_FactionTemplate`.

---

## Cluster 2 — creature_template.family — VERDICT: post-WotLK, benign. Optional cleanup to 0.

**Truth:** the client `db2_CreatureFamily` holds IDs 1–46 (sparse) plus 302. Families **52, 53,
68, 126, 160** are all above that WotLK range — **post-WotLK creature families** (Cataclysm+ added
families and assigned families to many non-pet beasts). 29 rows affected.

**Cross-check (`world_335`):** every one of these creatures has `family = 0` in WotLK. None is a
tameable hunter pet — they are dungeon/vehicle/boss beasts (Durnholde Tracking Hound, Mage Slayer,
Corpse Scarab, Ghaz'an, The Black Stalker, Spore Strider, and the Alterac Valley
Gryphon/War-Rider mounts 22525–37466). CreatureFamily only affects hunter-pet diet/talents, so it
is irrelevant for these entries.

**Core impact:** `CheckCreatureTemplate` (ObjectMgr.cpp:1111-1114): invalid family → logs error
and sets `family = CREATURE_FAMILY_NONE (0)`. Self-healing at load; no crash, no gameplay effect.

**Recommended action: BENIGN.** Optional cleanup to silence the load error and match WotLK:
```sql
UPDATE creature_template SET family=0
WHERE entry<=43282 AND family IN (52,53,68,126,160);
-- entries: 20528,30473,31497,31498,31499,29267,20168,20184,22300,22525,22556,22563,22564,
-- 22566,22570,22593,22594,31917,32002,32010,32023,32136,32138,37233,37321,37329,37343,37464,37466
```

---

## Cluster 3 — creature_template.VehicleId — VERDICT: post-WotLK data error. FIX to 0.

**Truth:** Vehicle IDs **584, 665, 921, 954, 973, 1262, 3133** are absent from the 3.4.3 client
`db2_Vehicle` (412 rows, max 774). All seven are **> 774 or otherwise post-WotLK** vehicle kits
that the Cataclysm revamp attached to these classic non-vehicle creatures. 11 rows affected.

**Cross-check (`world_335`):** all eleven creatures have `VehicleId = 0` in WotLK — they were
never vehicles:

| Entry | Name | 343 VehicleId | WotLK |
|---|---|---|---|
| 5856 | Glassweb Spider | 584 | 0 |
| 1538/1539/1540/1660/1665 | Scarlet Friar/Neophyte/Vanguard/Bodyguard, Capt. Melrache | 665 | 0 |
| 1061 | Gan'zulah | 921 | 0 |
| 6370 | Makrinni Scrabbler | 954 | 0 |
| 309 | Rolf's corpse | 973 | 0 |
| 5840 | Dark Iron Steamsmith | 1262 | 0 |
| 4421 | Charlga Razorflank | 3133 | 0 |

(The Scarlet Monastery NPCs and Charlga/RFK are exactly the mobs Cataclysm turned into
vehicle-riders — the value is genuine retail data, wrong for Wrath.)

**Core impact:** `CheckCreatureTemplate` (ObjectMgr.cpp:1119-1125): missing Vehicle →
`TC_LOG_ERROR("... This *WILL* cause the client to freeze!")` then `VehicleId = 0`. Self-healed at
load; the alarming message never fires at runtime once reset.

**Recommended action: FIX to 0** (silences the load error, matches WotLK):
```sql
UPDATE creature_template SET VehicleId=0
WHERE entry IN (5856,1538,1539,1540,1660,1665,1061,6370,309,5840,4421);
```

---

## Cluster 4 — creature_template_model.CreatureDisplayID — VERDICT: mostly benign; 5 rows FIX.

**Truth:** 175 rows / 73 creatures reference display IDs absent from the client
`db2_CreatureDisplayInfo`. They split cleanly:
- **High IDs (59357, 62196, 65269, 77915, 85277/85280/85292/85293, 88847, 89419–89803,
  98676, 99389–99951, 101348, 104729, 110479):** Cataclysm/MoP+ **updated model art** —
  the new human "peasant/laborer/guard" models (85280/85292/85293), reworked Blood Elf
  guardian models (89419+), stormwind guard models (99xxx), etc.
- **Low IDs (28480–46057):** extra display variants added post-WotLK; `world_335` does not use
  any of them either.

**Cross-check (`world_335`):** for every affected creature the WotLK `modelid1` is the SAME
display carried at `Idx 0` (or another idx) in the 343 `creature_template_model`, and that display
**IS present in the 3.4.3 client** (e.g. Water Elemental idx0=525✓ + bad 38373✗; Barrens Giraffe
idx0=4473✓ + bad 29316✗; Forsaken Herbalist idx0/1=4129/4130✓ + bad 28490/28491✗). The bad rows
are purely extra post-WotLK variants.

**Core impact:** `LoadCreatureTemplateModels` (ObjectMgr.cpp:637-642): a missing CreatureDisplayID
is logged (`"... this can crash the client"`) and the row is **skipped**; the creature keeps its
remaining valid model(s). So 68 of the 73 creatures are fully **benign** (correct appearance,
noisy load log only).

**The 5 exceptions have NO valid display row at all** (all their model rows are absent), which
hits ObjectMgr.cpp:1073 "does not have any existing display id" and leaves the creature with a
broken/fallback model. These need fixing to the WotLK display (all verified present in the 3.4.3
client):

| Entry | Name | bad display | WotLK display (world_335) |
|---|---|---|---|
| 20189 | Underbog Mushroom | 39552 | 11686 |
| 20528 | Durnholde Tracking Hound | 30210 | 780 |
| 35410 | Alliance Gunship Cannon | 37369 | 29488 |
| 37525 | Morgan Test (1) | 31498 | 19410 |
| 37526 | Morgan Test (2) | 31498 | 19410 |

**Recommended action:**
- **68 creatures: BENIGN.** Optionally delete the invalid variant rows to silence the load log:
```sql
-- optional, cosmetic (removes model rows whose display is not in the 3.4.3 client)
DELETE ctm FROM creature_template_model ctm
WHERE ctm.CreatureID<=43282
  AND ctm.CreatureDisplayID IN (28480,28481,28490,28491,29316,30210,31232,31498,32135,32211,
      32212,32213,33397,34004,34005,37290,37291,37292,37369,37373,37374,38373,38418,38419,39552,
      43157,45446,45948,46057,59357,59358,59359,62196,62716,65269,65270,77915,85277,85280,85292,
      85293,88847,89419,89420,89421,89800,89801,89802,89803,98676,99389,99391,99452,99453,99826,
      99827,99828,99829,99830,99831,99832,99833,99834,99835,99836,99837,99838,99949,99950,99951,
      101348,104729,110479);
```
- **5 creatures: FIX** (do this BEFORE the optional delete above, or it removes their only row):
```sql
UPDATE creature_template_model SET CreatureDisplayID=11686 WHERE CreatureID=20189 AND CreatureDisplayID=39552;
UPDATE creature_template_model SET CreatureDisplayID=780   WHERE CreatureID=20528 AND CreatureDisplayID=30210;
UPDATE creature_template_model SET CreatureDisplayID=29488 WHERE CreatureID=35410 AND CreatureDisplayID=37369;
UPDATE creature_template_model SET CreatureDisplayID=19410 WHERE CreatureID IN (37525,37526) AND CreatureDisplayID=31498;
```
(20528 Durnholde Tracking Hound is a real Old Hillsbrad mob; 20189 Underbog Mushroom is a real
Underbog mob; 35410 is the Alliance gunship cannon; 37525/37526 are internal "Morgan Test" NPCs
and could equally be ignored/dropped.)

---

## Cluster 5 — creature_template_spell.Spell — VERDICT: 2 post-WotLK (FIX), 2 client-dropped (benign).

**Truth (per row):**

| Creature | 343 Spell | In 3.4.3 client? | world_335 | Verdict |
|---|---|---|---|---|
| 27894 Antipersonnel Cannon | 96212 | no | **49872 "Rocket Blast"** (present) | **post-WotLK error → FIX to 49872** |
| 1860 Voidwalker | 112042 "Threatening Presence" | no | (no row) | **post-WotLK (MoP demonology aura) → DROP row** |
| 19897 Tainted Earthgrab Totem | 31982 | no | 31982 (identical) | client-dropped WotLK spell → benign |
| 19899 Corrupted Nova Totem | 33134 | no | 33134 (identical) | client-dropped WotLK spell → benign |

- **96212** returns 404 on wowhead/wotlk — a Cataclysm+ spell ID; `world_335` uses **49872
  "Rocket Blast"** for this cannon, which IS in the 3.4.3 client `db2_SpellName`. Clear 343 error.
- **112042 "Threatening Presence"** (wowhead retail) is an obsolete MoP-era Demonology-warlock pet
  aura; `world_335` has no `creature_template_spell` row for the base Voidwalker. Post-WotLK
  addition.
- **31982 / 33134** are used *identically* by `world_335` (the WotLK gold standard, which validates
  creature spells against the 3.3.5a client on load), so they were genuine 3.3.5a spells. They 404
  on both wowhead/wotlk (which mirrors the 3.4.x client) and wowhead retail — i.e. Blizzard dropped
  these old totem spells from the client data in the 3.4.x re-derivation. The **value is
  WotLK-truthful**, not a data error.

**Core impact:** `LoadCreatureTemplateSpells` (ObjectMgr.cpp:562-605) does no existence check; but
`CheckCreatureTemplate` (ObjectMgr.cpp:1129-1135) does: any `spells[]` not in `sSpellMgr` is logged
(`"... set to 0."`) and zeroed. No crash. For 31982/33134 the reference is simply nulled at runtime
(the totems' effect can't fire on 3.4.3 because the spell no longer exists anywhere — that is a
content-porting concern separate from FK hygiene).

**Recommended action:**
```sql
-- post-WotLK data errors
UPDATE creature_template_spell SET Spell=49872 WHERE CreatureID=27894 AND Spell=96212;
DELETE FROM creature_template_spell WHERE CreatureID=1860 AND Spell=112042;
-- client-dropped WotLK totem spells: value is WotLK-correct but the spell is gone from 3.4.3.
-- Leave as-is (core zeroes it harmlessly), OR delete the dead rows to silence the load error:
DELETE FROM creature_template_spell WHERE (CreatureID=19897 AND Spell=31982)
                                       OR (CreatureID=19899 AND Spell=33134);
```

---

## Summary

| # | Cluster | Verdict | Action |
|---|---|---|---|
| 1 | faction (82 rows / 24 IDs) | 343 post-WotLK values; core resets to faction 35 (breaks hostility) | **FIX** to world_335 faction (SQL above) |
| 2 | family (29 rows) | post-WotLK families on non-pets; core resets to 0 | benign; optional `family=0` |
| 3 | VehicleId (11 rows) | post-WotLK vehicle kits; core resets to 0 | **FIX to 0** |
| 4 | display (175 rows / 73 creatures) | post-WotLK model variants; core skips invalid rows | benign for 68; **FIX 5** creatures with no valid display |
| 5 | spell (4 rows) | 2 post-WotLK / 2 client-dropped WotLK; core zeroes invalid | **FIX** 27894→49872, drop 1860; 19897/19899 benign (optional drop) |

No cluster causes a crash on load — the core validates and self-heals every one of these
references. The material gameplay bugs are Cluster 1 (hostile mobs turned neutral) and the 5
display-less creatures in Cluster 4.
