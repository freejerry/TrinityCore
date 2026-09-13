# access_requirement: WotLK data mapped to the 3.4 schema

**Verdict:** TDB335 (confidence: high). See update sql/updates/world/wotlk_classic/2026_09_13_*_world.sql.

- **Rows:** world_d(343)=236, world_335=121
- **Target (3.4) schema:** mapId int unsigned, difficulty tinyint unsigned, level_min tinyint unsigned, level_max tinyint unsigned, item int unsigned, item2 int unsigned, quest_done_A int unsigned, quest_done_H int unsigned, completed_achievement int unsigned, quest_failed_text mediumtext, comment mediumtext (11 columns; PK mapId+difficulty)
- **3.3.5a schema:** mapId int unsigned, difficulty tinyint unsigned, level_min tinyint unsigned, level_max tinyint unsigned, item_level smallint unsigned, item int unsigned, item2 int unsigned, quest_done_A int unsigned, quest_done_H int unsigned, completed_achievement int unsigned, quest_failed_text mediumtext, comment mediumtext (12 columns)

## Column mapping (target 3.4 <= source)

- `mapId` <= 335.mapId direct (present in both, int unsigned) — loader SELECTs it as `mapid`; MySQL column names case-insensitive
- `difficulty` <= 335.difficulty direct — loader validates via sDB2Manager.GetMapDifficultyData(mapid,difficulty); values 0/1/2/3 used
- `level_min` <= 335.level_min direct — ObjectMgr.cpp:7021 ar->levelMin
- `level_max` <= 335.level_max direct — ObjectMgr.cpp:7022 ar->levelMax (all WotLK rows = 0)
- `item` <= 335.item direct — ObjectMgr.cpp:7023; existence checked vs ItemTemplate -> DBErrors pass
- `item2` <= 335.item2 direct — ObjectMgr.cpp:7024; existence checked vs ItemTemplate -> DBErrors pass
- `quest_done_A` <= 335.quest_done_A direct — ObjectMgr.cpp:7025 ar->quest_A; existence checked vs GetQuestTemplate
- `quest_done_H` <= 335.quest_done_H direct — ObjectMgr.cpp:7026 ar->quest_H
- `completed_achievement` <= 335.completed_achievement direct — ObjectMgr.cpp:7027 ar->achievement (ICC heroic uses 4530/4597)
- `quest_failed_text` <= 335.quest_failed_text direct — ObjectMgr.cpp:7028 ar->questFailedText
- `comment` <= 335.comment direct — documentation only; NOT in loader SELECT list, purely descriptive

**Dropped 3.3.5a columns:** item_level (smallint unsigned, 335 ordinal 5): removed in the 3.4 schema and has NO target column. It was never read by the wotlk_classic loader (ObjectMgr.cpp:6990 SELECT omits it) and is a legacy/unused field — its data is simply dropped. It was NOT moved into a client DB2; no equivalent is needed on the 3.4.3 client. In 335 it is 0 for all but a handful of WotLK dungeon/raid rows (e.g. mapId 574/575/576/... = 180, 632/650 = 200, 668 = 219), none of which affect access logic.

## Correct WotLK dataset

All 121 rows from world_335, projected onto the 11-column 3.4 target schema by dropping item_level. These cover Classic/TBC/WotLK dungeons and raids only (mapIds 33..724, up to Ruby Sanctum) — the correct WotLK 3.3.5a content set. No column value needs widening (335 int types already fit the identical 3.4 types). No 3.4-added column exists, so no defaults are introduced. The raw TDB343 (world_d, 236 rows) is REJECTED because it adds ~45 post-WotLK maps (Cataclysm+ e.g. 643 Blackrock Caverns, 725 Deadmines-Cata, 859 ZG-Cata, and Legion/BFA/SL maps 938,959,1001,2450,2481,2569) that must not exist on a WotLK content server.

## Dead values / contamination

In the 335 source: none — all 121 rows are genuine WotLK-era content, no post-WotLK contamination. Two rows (mapId 289 Scholomance, 309 Zul'Gurub — classic versions) exist in 335 but are absent from raw TDB343 (which carries only their Cata-revamped map entries); on the 3.4.3 WotLK Classic client the classic map ids 289/309 exist, so they are kept and FLAGGED for the DBErrors.log pass to confirm the map + difficulty (GetMapDifficultyData) resolve. Referenced items/quests/achievements (e.g. items 30622/30623/30633/30634/30635/30637, quests 10277/10285/11492/24499/24511/24710/24712, achievements 4530/4597) are also left to the DBErrors pass — the loader nulls out any missing item/quest and skips rows for missing map/difficulty.

## Evidence

- **3.4 target schema has 11 columns and lacks item_level; 335 has 12 columns with item_level at ordinal 5**  
  — information_schema.columns world_d vs world_335 (docker tdb343-db-1)
- **Loader SELECT list is mapid,difficulty,level_min,level_max,item,item2,quest_done_A,quest_done_H,completed_achievement,quest_failed_text (item_level and comment NOT selected)**  
  — src/server/game/Globals/ObjectMgr.cpp:6990 (branch wotlk_classic)
- **Column meanings: levelMin/Max, item/item2 (existence-checked), quest_A/quest_H, achievement, questFailedText**  
  — src/server/game/Globals/ObjectMgr.cpp:7021-7048
- **Map + difficulty validated at load; unknown map or missing MapDifficulty row is skipped**  
  — src/server/game/Globals/ObjectMgr.cpp:7005-7016
- **335 has 121 rows, all Classic/TBC/WotLK maps (max 724 Ruby Sanctum); no post-WotLK maps present**  
  — world_335.access_requirement DISTINCT mapId (docker)
- **raw TDB343 (world_d, 236 rows) adds ~45 Cataclysm+/Legion/BFA/SL maps (643,725,859,938,959,1001,2450,2481,2569,...) not valid for WotLK content**  
  — LEFT JOIN world_d vs world_335 on mapId (docker)
- **mapId 289 (Scholomance) and 309 (Zul'Gurub) present in 335 but absent from raw TDB343 (Cata-revamped there); classic map ids exist on WotLK Classic client**  
  — LEFT JOIN world_335 vs world_d on mapId (docker)
- **item_level nonzero only for a few WotLK rows (180/200/219); unused legacy field**  
  — world_335 SELECT WHERE item_level<>0 (docker)

---
_schema-map research workflow, run wf_0984d327-80b. Validated via world_c reload + DBErrors.log._

## Update -- final decision

CORRECTION to the agent's TDB335 recommendation: 335's difficulty enum differs from 3.4 (335: 0=normal/1=heroic; 3.4: 1=normal 5man / 2=heroic / 3-6=raid), so copying 335 verbatim broke MapDifficulty validation (85/121 skipped). Used TDB343 instead (already the correct 3.4 difficulty enum + 3.4 item/quest refs), trimmed to client-valid: dropped 44 post-WotLK maps + 5 Cata (map,difficulty) combos via DBErrors.log. Final 117 rows; source reclassified Mixed.
