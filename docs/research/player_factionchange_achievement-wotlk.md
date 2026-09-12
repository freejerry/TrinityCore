# player_factionchange_achievement: WotLK-correct data (TDB343 vs 3.3.5a vs 3.4.3 client)

**Verdict:** import as **TDB335** (confidence: high). Delta update under sql/updates/world/wotlk_classic/2026_09_12_*_world.sql, verified to reproduce the 3.3.5a (world_335) set when applied to raw TDB343.

- **Rows:** world_d (raw TDB343) = 103, world_335 (3.3.5a) = 125
- **Difference pattern:** 335_superset
- **Structure:** Identical schema in both DBs: CREATE TABLE `player_factionchange_achievement` (`alliance_id` int unsigned, `horde_id` int unsigned, PRIMARY KEY(`alliance_id`,`horde_id`)). Two-column A<->H achievement equivalency map used only during faction change. No column-semantics difference.

## Difference

world_d (TDB343) is a strict SUBSET of world_335: (world_d EXCEPT world_335) is EMPTY; (world_335 EXCEPT world_d) returns exactly 22 rows present only in 335. No value shifts, no 343-only rows. The 22 missing pairs (alliance->horde): 41->1360, 58->593, 970->971, 1167->1168, 1169->1170, 1172->1173, 1262->1274, 1466->926, 1563->1784, 1656->1657, 1676->1677, 1678->1680, 1681->1682, 1684->1683, 1692->1691, 1707->1693, 1752->2776, 2144->2145, 2194->2195, 2797->2798, 3478->3656, 4784->4785.

## Correct WotLK dataset

The full 125-row 3.3.5a set (world_335). All 125 rows map an Alliance WotLK achievement to its Horde equivalent (and are consumed only during a faction-change transfer). Every alliance_id and horde_id across all 125 rows is a genuine WotLK achievement present in the 3.3.5a Achievement.dbc. The 22 rows TDB343 dropped are authentic WotLK faction-change equivalencies that were removed by RETAIL-era TrinityCore master maintenance, which does not apply to a WotLK-content server.

## Dead values / contamination

TDB343 is missing 22 authentic WotLK rows (data loss, not contamination). These were stripped by post-WotLK RETAIL master-branch updates: sql/old/10.x/world/23101_2023_11_15/2023_10_15_00_world.sql explicitly runs `DELETE FROM player_factionchange_achievement WHERE alliance_id IN (58, 1466)` and in the same file reworks achievement_reward/titles for IDs 1657,1684,1692,1707,1784,2145,2797,3656 and 1563,1656,1683,1691,1693,2798,3478 — every one of those IDs is in the 22-row 335-only set, tying the removals to a retail achievement rework. No Cata/MoP/WoD ROWS present in either table (all referenced achievement IDs <= 4785, all valid WotLK). world_335 is clean: all 125 rows reference achievements that exist in the 3.3.5a Achievement.dbc.

## Proposed delta (vs raw TDB343)

```sql
-- Re-add the 22 authentic WotLK faction-change achievement pairs that TDB343 (world_d) lost to retail-era master maintenance. Result = the full 3.3.5a (world_335) 125-row set.
INSERT INTO `player_factionchange_achievement` (`alliance_id`, `horde_id`) VALUES
(41, 1360),
(58, 593),
(970, 971),
(1167, 1168),
(1169, 1170),
(1172, 1173),
(1262, 1274),
(1466, 926),
(1563, 1784),
(1656, 1657),
(1676, 1677),
(1678, 1680),
(1681, 1682),
(1684, 1683),
(1692, 1691),
(1707, 1693),
(1752, 2776),
(2144, 2145),
(2194, 2195),
(2797, 2798),
(3478, 3656),
(4784, 4785);
```

## Evidence

- **Identical schema (alliance_id, horde_id; PK on both) in world_d and world_335.**  
  — SHOW CREATE TABLE player_factionchange_achievement in both DBs (docker exec tdb343-db-1 mariadb)
- **world_d has 103 rows, world_335 has 125; world_d is a strict subset (world_d EXCEPT world_335 = empty; world_335 EXCEPT world_d = 22 rows).**  
  — COUNT(*) + bidirectional (SELECT * FROM a) EXCEPT (SELECT * FROM b) queries on both DBs
- **Loader validates every alliance_id and horde_id against sAchievementStore (the client's Achievement store); rows referencing a non-existent achievement are skipped with only a log error (no gameplay harm), so keeping WotLK-valid extra rows is safe/correct.**  
  — src/server/game/Globals/ObjectMgr.cpp:9932-9964 (LoadFactionChangeAchievements)
- **The 22 missing rows were removed by RETAIL-era (post-WotLK) master updates, not WotLK corrections.**  
  — sql/old/10.x/world/23101_2023_11_15/2023_10_15_00_world.sql:10-20 (DELETE ... alliance_id IN (58,1466) plus achievement_reward/title rework for IDs 1657,1684,1692,1707,1784,2145,2797,3656 / 1563,1656,1683,1691,1693,2798,3478 — all in the 22-row 335-only set)
- **All 44 achievement IDs (both sides of the 22 extra pairs) are genuine WotLK achievements present in the 3.3.5a client.**  
  — 3.3.5a Achievement.dbc from patch-enTW-3.MPQ (WDBC, 1817 records); custom parse: 44/44 target IDs present, 0 missing
- **All 125 rows in world_335 reference only achievements that exist in the 3.3.5a Achievement.dbc (335 set is clean, no phantom refs).**  
  — cross-check of all 125 world_335 pairs against the 1817-id 3.3.5a DBC set: NONE absent
- **At least 10 of the WotLK achievements in the missing set are confirmed present in the 3.4.3-client-keyed data (achievement_reward IDs the core also validates against the client store): 1563,1656,1681,1682,1683,1691,1693,2144,2798,3478.**  
  — SELECT ID FROM world_d.achievement_reward WHERE ID IN (<targets>)
- **3.4.3 client Achievement.db2 (FileDataID 1260179) could NOT be byte-verified: located ckey ccaf39.. -> ekey b08d75.. in CDN archive 682d108b.. and fetched, but its BLTE stream uses mode 'E' (encrypted) with no local TACT key available. world_d.achievement_dbc (416 rows) is a sparse hotfix/override table, not the full client mirror, so it cannot disprove client presence.**  
  — casc root parse (/tmp/root343.bin, interleaved classic format, 596 blocks to exact EOF) -> encoding -> archive index (~/WoW 3.4.3 Test/Data/indices) -> CDN range fetch -> casc_blte raises 'BLTE mode E unsupported'

---
_Generated from C-layer research workflow (batch 1), run wf_36e31f1e-3e1._
