# battlemaster_entry: WotLK-correct data (TDB343 vs 3.3.5a vs 3.4.3 client)

**Verdict:** import as **TDB335** (confidence: high). Delta update under sql/updates/world/wotlk_classic/2026_09_12_*_world.sql, verified to reproduce the intended WotLK set when applied to raw TDB343.

- **Rows:** world_d (raw TDB343) = 172, world_335 (3.3.5a) = 157
- **Difference pattern:** partial_overlap
- **Structure:** Schema identical in 343 (world_d) and 335 (world_335): two columns `entry` (creature entry, PK) and `bg_template` (BattlegroundTypeId / BattlemasterList id). No column-semantics change. bg_template is validated at load against sBattlemasterListStore (client BattlemasterList db2) and the creature must exist in creature_template with UNIT_NPC_FLAG_BATTLEMASTER.

## Difference

Three kinds of difference. (1) 343 carries 20 rows for Cataclysm battlegrounds Twin Peaks (bg_template=108, 10 rows) and Battle for Gilneas (bg_template=120, 10 rows) that 335 lacks entirely; all 20 referenced creatures are ABSENT from world_d.creature_template, so they are dead rows the loader skips anyway. (2) 11 Random-Battleground capital-city battlemasters (34986,34988,34989,34991,34997,34998,34999,35000,35001,35002,35007) are assigned to bg_template=1 (Alterac Valley) in 343 but to bg_template=32 (Random Battleground) in 335 — a value shift. (3) 335 additionally lists 5 battlemasters under bg 32 that 343 omits from the table (34895 'Jend Jow (Test)',34971,34972,34976,34993 — all present in world_d.creature_template as Battlemasters). bg_templates present in 335: 1,2,3,6,7,9,30,32 (all valid WotLK BGs); 343 adds 108,120.

## Correct WotLK dataset

The 157-row world_335 set: all WotLK battlegrounds only — AV(1),WSG(2),AB(3),All Arenas(6),EotS(7),SotA(9),IoC(30) unchanged, plus the Random Battleground(32) roster of 24 capital-city battlemasters. No Cataclysm battlegrounds (Twin Peaks 108 / Battle for Gilneas 120). The Random-BG masters must map to bg_template=32, not 1.

## Dead values / contamination

Post-WotLK contamination: 20 rows for bg_template 108 (Twin Peaks) and 120 (Battle for Gilneas) — both Cataclysm battlegrounds, confirmed by SharedDefines.h:6541-6542. These are also dead rows: all 20 creatures (44012,44013,44059,50546,50548-50553,44000,44004,44060,50668,50670,50674,50676,50678,50683,50684) are absent from world_d.creature_template, so BattlegroundMgr.cpp:611 skips them at load. Additional value contamination: 11 random-BG battlemasters mis-pointed to bg 1 instead of 32.

## Proposed delta (vs raw TDB343)

```sql
-- Reassign WotLK Random Battleground masters from AV(1) to Random(32)
UPDATE `battlemaster_entry` SET `bg_template`=32
 WHERE `entry` IN (34986,34988,34989,34991,34997,34998,34999,35000,35001,35002,35007) AND `bg_template`=1;
-- Drop Cataclysm battlegrounds Twin Peaks(108) and Battle for Gilneas(120) (dead rows, creatures absent)
DELETE FROM `battlemaster_entry` WHERE `bg_template` IN (108,120);
-- Re-add Random Battleground masters missing from 343
INSERT INTO `battlemaster_entry` (`entry`,`bg_template`) VALUES
 (34895,32),(34971,32),(34972,32),(34976,32),(34993,32);
-- Result: 172 - 20 (delete) + 5 (insert) = 157 rows = world_335 set
```

## Evidence

- **Schemas byte-identical (entry int unsigned PK, bg_template int unsigned); world_d=172 rows, world_335=157 rows**  
  — docker SHOW CREATE TABLE + COUNT(*) on world_d and world_335
- **343-only rows: bg 1 gains 11 entries (34986..35007), bg 108 (10 rows) and bg 120 (10 rows); 335-only rows: 16 entries all under bg 32**  
  — EXCEPT both directions: (world_d) EXCEPT (world_335) and reverse
- **bg_template 108 = Twin Peaks, 120 = Battle For Gilneas (Cataclysm BGs); 32 = Random Battleground; 1 = Alterac Valley**  
  — src/server/game/Miscellaneous/SharedDefines.h:6525,6537,6541,6542
- **Loader validates bg_template against BattlemasterList store and skips rows whose creature does not exist in creature_template**  
  — src/server/game/Battlegrounds/BattlegroundMgr.cpp:604-622
- **All 20 Twin Peaks/BfG creatures are absent from world_d.creature_template (query returned 0 rows), so those battlemaster_entry rows are dead**  
  — SELECT ... FROM world_d.creature_template WHERE entry IN (44012,...,50684) -> empty
- **The 11 reassigned and 5 missing creatures are genuine WotLK battlemasters (e.g. 34986 Liedel the Just, 34971 Hotoro), present in both DBs' creature_template with Battlemaster subname**  
  — SELECT entry,name,subname FROM world_335/world_d.creature_template for the affected entries
- **34986 'Liedel the Just' is a WotLK Battlemaster located in The Exodar (a capital-city battlemaster => Random Battleground queue, added patch 3.3.0), consistent with bg_template=32 in 335**  
  — https://www.wowhead.com/wotlk/npc=34986/liedel-the-just

---
_Generated from C-layer research workflow (batch 2), run wf_f9c949d0-e24._
