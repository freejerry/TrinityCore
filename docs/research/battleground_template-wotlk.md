# battleground_template: WotLK data mapped to the 3.4 schema

**Verdict:** TDB335 (confidence: high). See update sql/updates/world/wotlk_classic/2026_09_13_*_world.sql.

- **Rows:** world_d(343)=17, world_335=13
- **Target (3.4) schema:** ID int unsigned, AllianceStartLoc int unsigned, HordeStartLoc int unsigned, StartMaxDist float, Weight tinyint unsigned, ScriptName varchar(64), Comment varchar(32)
- **3.3.5a schema:** ID int unsigned, MinPlayersPerTeam smallint unsigned, MaxPlayersPerTeam smallint unsigned, MinLvl tinyint unsigned, MaxLvl tinyint unsigned, AllianceStartLoc int unsigned, AllianceStartO float, HordeStartLoc int unsigned, HordeStartO float, StartMaxDist float, Weight tinyint unsigned, ScriptName char(64), Comment char(32)

## Column mapping (target 3.4 <= source)

- `ID` <= 335.ID direct — BattlegroundTypeId / BattlemasterList.dbc id. Present both. fields[0].
- `AllianceStartLoc` <= 335.AllianceStartLoc direct — world_safe_locs.ID (NOT WorldSafeLocs.dbc — GetWorldSafeLoc reads world DB table, ObjectMgr.cpp:6790). fields[1]. Must exist in rebuilt world_safe_locs; DBErrors pass validates.
- `HordeStartLoc` <= 335.HordeStartLoc direct — world_safe_locs.ID. fields[2]. Same validation caveat.
- `StartMaxDist` <= 335.StartMaxDist direct — fields[3]; core stores dist*dist as MaxStartDistSq (BattlegroundMgr.cpp:405-406). 335 AV=100 (world_d TDB343 uses 150 — kept 335 WotLK value per copy rule).
- `Weight` <= 335.Weight direct — fields[4], GetUInt8. All WotLK rows =1.
- `ScriptName` <= 335.ScriptName direct — fields[5], GetScriptId(). All WotLK rows empty string ''. Type widened char(64)->varchar(64), no data impact.
- `Comment` <= 335.Comment direct — Cosmetic only — NOT in the loader SELECT (BattlegroundMgr.cpp:372), core never reads it. char(32)->varchar(32).

**Dropped 3.3.5a columns:** MinPlayersPerTeam, MaxPlayersPerTeam: removed in 3.4 — now sourced from BattlemasterList.dbc (client). BattlegroundTemplate::GetMinPlayersPerTeam/GetMaxPlayersPerTeam return BattlemasterEntry->MinPlayers/MaxPlayers (BattlegroundMgr.cpp:40-48). | MinLvl, MaxLvl: removed — now from BattlemasterList.dbc. GetMinLevel/GetMaxLevel return BattlemasterEntry->MinLevel/MaxLevel (BattlegroundMgr.cpp:50-58). | AllianceStartO, HordeStartO (orientation floats): removed — orientation now lives in world_safe_locs.Facing (world_safe_locs SELECT includes Facing, ObjectMgr.cpp:6790); the start-location entry carries its own facing, so per-team orientation moved out of battleground_template into the referenced world_safe_locs row.

## Correct WotLK dataset

The 13 WotLK battlegrounds/arenas from world_335 (IDs 1-11, 30, 32) fitted to the 7-column 3.4 target schema: keep ID, AllianceStartLoc, HordeStartLoc, StartMaxDist, Weight, ScriptName, Comment directly from 335; drop the 6 removed columns (min/max players, min/max level -> BattlemasterList.dbc; alliance/horde orientation -> world_safe_locs.Facing). ScriptName is empty and Weight=1 for every row, matching what the core expects. Comment is cosmetic (never read by the loader).

## Dead values / contamination

world_d (TDB343) contains 4 post-WotLK rows absent from the WotLK rowset: ID 108 (Twin Peaks) and ID 120 (The Battle for Gilneas) are Cataclysm battlegrounds; ID 1014 (Warsong Gulch) and ID 1018 (Arathi Basin) are the retail post-WotLK duplicate ("Classic"-split) BattlemasterList ids. All 4 dropped. Also note world_d ID 30 (Isle of Conquest) uses start locs 1299/1245 whereas the WotLK-correct 335 uses 1485/1486 — the 335 pair is kept and flagged for the DBErrors world_safe_locs check.

## Evidence

- **Loader SELECT is exactly ID, AllianceStartLoc, HordeStartLoc, StartMaxDist, Weight, ScriptName — Comment and all 335-only columns are NOT read**  
  — src/server/game/Battlegrounds/BattlegroundMgr.cpp:372
- **MinPlayers/MaxPlayers/MinLevel/MaxLevel now come from BattlemasterList.dbc, not the DB table**  
  — src/server/game/Battlegrounds/BattlegroundMgr.cpp:40-58 (return BattlemasterEntry->...)
- **AllianceStartLoc/HordeStartLoc reference world_safe_locs (DB table, has Facing column), so orientation moved there**  
  — src/server/game/Globals/ObjectMgr.cpp:6790 (SELECT ID,MapID,LocX,LocY,LocZ,Facing,TransportSpawnId FROM world_safe_locs)
- **Missing start loc id => BG not created / ignored (DBErrors pass must validate world_safe_locs)**  
  — src/server/game/Battlegrounds/BattlegroundMgr.cpp:414-436
- **335 WotLK rows = IDs 1-11,30,32; world_d adds Cataclysm+ 108/120/1014/1018**  
  — docker world_335 vs world_d battleground_template dumps
- **Twin Peaks and Battle for Gilneas are Cataclysm battlegrounds (post-WotLK)**  
  — warcraft.wiki.gg — Twin Peaks / Battle for Gilneas (patch 4.0)

## Verification notes

Confirm during the DBErrors pass that world_safe_locs contains the start-location ids referenced here — especially ID 30 (Isle of Conquest) where the WotLK-correct pair 1485/1486 was kept over world_d's 1299/1245; if world_safe_locs is rebuilt from a source that only has the 1299/1245 pair, IoC will fail to create and the ids must be reconciled.

---
_schema-map research workflow, run wf_0984d327-80b. Validated via world_c reload + DBErrors.log._