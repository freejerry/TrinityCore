# world_state: WotLK-correctness (TDB343-only table)

**Verdict:** Trim (confidence: high). This table exists in TDB343 but not in 3.3.5a. Update under sql/updates/world/wotlk_classic/2026_09_13_*_world.sql.

- **Rows in raw TDB343:** 1504
- **Is a WotLK feature?** yes
- **Purpose:** WorldStateMgr template table. Loaded by WorldStateMgr::LoadFromDB via "SELECT ID, DefaultValue, MapIDs, AreaIDs, ScriptName FROM world_state" (src/server/game/World/WorldStates/WorldStateMgr.cpp:44), called from World::SetInitialWorldSettings (src/server/game/World/World.cpp:2249, "must be loaded before battleground, outdoor PvP and conditions"). Each row defines the default value of a world state, scoped realm-wide (empty MapIDs -> _realmWorldStateValues) or per map/area (_worldStatesByMap). Consumed via WorldStateMgr::GetWorldStateTemplate / GetInitialWorldStatesForMap (Map.cpp:449) and used by battlegrounds, instance scripts, outdoor PvP, conditions, achievements. The loader validates MapIDs against sMapStore (client Map.db2) and AreaIDs against sAreaTableStore, ignoring invalid tokens and skipping any row whose nonempty MapIDs yield no valid map (WorldStateMgr.cpp:68-127).

## Correct state for C

The 912 WotLK-valid world-state templates: every row that references at least one map present in the 3.4.3 WotLK-content client Map.db2 (130 maps, max content map 724 = The Ruby Sanctum, the last WotLK patch content), plus 14 realm-wide (NULL-map) WotLK globals — BG Call to Arms for AV/WSG/AB/EotS/SotA/IoC (1941,1942,1943,2851,3695,4273), the Scourge Invasion zone flags (2259-2264), and PvP season current/previous (3191,3901). Client-absent map tokens (e.g. AV's 2197, WSG's 726 Twin Peaks, EotS's 968) and client-absent area tokens co-listed on kept rows are stripped so the loader logs no "invalid MapID/AreaID" errors. Content spans classic dungeons/raids, TBC, and all WotLK dungeons/raids/BGs/Wintergrasp/outdoor-PvP.

## Dead values / contamination

592 rows dropped as post-WotLK contamination: 560 reference no map present in the WotLK client (Cata/MoP/WoD/Legion/BfA/SL/DF raids, dungeons and zones, on maps confirmed absent from the 3.4.3 client Map.db2 such as 643,644,645,669,670,671,720,755,757 and all 858+); 30 realm-wide (NULL-map) globals are post-WotLK features (Cata BGs Twin Peaks/Gilneas 5360-5361, MoP BGs Kotmogu/Silvershard/Deepwind 6306/6436/7671, BfA War Mode buffs 17042-17043, Shadowlands Covenant Renown/Torghast/Sanctum of Domination/Sepulcher 19735-21302, Dragonflight currency trackers 22869-23970); and 2 Dragonflight Solo Shuffle rows (21322,21427) that referenced WotLK arena maps were also dropped. Within the kept set, 319 client-absent map tokens and 52 client-absent area tokens were stripped from otherwise-valid rows. FLAGGED harmless residue kept because it sits on WotLK-valid classic maps (dead data, no WotLK trigger): Cataclysm dungeon-revamp encounters — Stormwind Stockade/Hogger 5509-5511 (map 34), Cata Deadmines 5538-5613 (map 36), Worgen-era Shadowfang Keep 5551-5553 (map 33), Cata Ragefire Chasm 6580-6592 (map 389).

## Evidence

- **world_state is loaded by WorldStateMgr::LoadFromDB via SELECT ID, DefaultValue, MapIDs, AreaIDs, ScriptName FROM world_state; MapIDs validated against sMapStore, AreaIDs against sAreaTableStore, invalid tokens ignored and rows with no valid map skipped**  
  — src/server/game/World/WorldStates/WorldStateMgr.cpp:44-137
- **LoadFromDB is called during server startup, before battlegrounds/outdoor PvP/conditions; world states are a core WotLK-era system (feature exists in 3.3.5)**  
  — src/server/game/World/World.cpp:2249
- **Templates are consumed per-map/area via GetWorldStateTemplate and GetInitialWorldStatesForMap (battlegrounds, instance scripts, outdoor PvP, conditions, achievements)**  
  — src/server/game/Maps/Map.cpp:449,168
- **world_d.world_state has 1504 rows spanning IDs 121-23970; 717 reference maps > 724; comments include Sepulcher of the First Ones, Dragonflight currencies, Solo Shuffle (post-WotLK)**  
  — docker exec tdb343-db-1 mariadb world_d -e 'SELECT COUNT(*),MIN(ID),MAX(ID) FROM world_state' and ORDER BY ID DESC sample
- **The 3.4.3 WotLK-content client Map.db2 contains 130 maps, max content map 724 (The Ruby Sanctum, last WotLK patch); Cataclysm-introduced maps 643,644,645,669,670,671,720,755,757 are ABSENT**  
  — tools/wdc4_ids.py parse of /Users/shinichi/Works/side-project/tdb343-test/data/dbc/enUS/Map.db2
- **The 3.4.3 client AreaTable.db2 contains 2373 areas; used to strip client-absent area tokens from kept rows**  
  — tools/wdc4_ids.py parse of /Users/shinichi/Works/side-project/tdb343-test/data/dbc/enUS/AreaTable.db2
- **Filtering to rows with >=1 client-present map plus 14 WotLK realm-wide globals yields 912 rows; the generated literal INSERT loads cleanly into a fresh table (912 rows, 14 globals) with 0 rows losing all their areas**  
  — validated import into ws_scratch DB via docker exec ... < ws_trim2.sql
- **Solo Shuffle is a Dragonflight (10.x) feature; War Mode is Battle for Azeroth (8.0); Twin Peaks/The Battle for Gilneas BGs and the Deadmines/Shadowfang Keep/Ragefire Chasm boss revamps are Cataclysm (4.0) — all post-WotLK**  
  — warcraft.wiki.gg / wowpedia patch history for these features

## Verification notes

Two verification points for the orchestrator's DBErrors/creature pass (neither blocks the decision): (1) ~18 kept rows are Cataclysm dungeon-revamp encounters (Hogger/Stockade 5509-5511, Cata Deadmines 5538-5613, Worgen SFK 5551-5553, Cata Ragefire 6580-6592) that live on WotLK-valid classic maps (34/36/33/389) — they load as harmless dead world states because no WotLK creature/instance script triggers them; drop them only if strict WotLK encounter purity is desired. (2) Map/area filtering used the actual 3.4.3 runtime client files at /Users/shinichi/Works/side-project/tdb343-test/data/dbc/enUS/{Map.db2,AreaTable.db2} (130 maps max 724, 2373 areas) — confirm the running core loads these same DBCs so no kept row logs an invalid-map/area error.

---
_343-only research workflow, run wf_18cbaa1a-47d. Trims validated via world_c reload + DBErrors.log._
