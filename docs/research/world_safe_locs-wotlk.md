# world_safe_locs: WotLK-correctness (TDB343-only table)

**Verdict:** Trim (confidence: high). This table exists in TDB343 but not in 3.3.5a. Update under sql/updates/world/wotlk_classic/2026_09_13_*_world.sql.

- **Rows in raw TDB343:** 4154
- **Is a WotLK feature?** yes
- **Purpose:** Holds graveyard / safe-resurrection locations (ID, MapID, X/Y/Z, Facing, optional TransportSpawnId). Loaded by ObjectMgr::LoadWorldSafeLocs (src/server/game/Globals/ObjectMgr.cpp:6785-6826), which validates each MapCoord and stores entries in _worldSafeLocs; GetWorldSafeLoc/GetWorldSafeLocs feed the graveyard system (game_graveyard) and battleground/arena/instance entrance & resurrection points. In 3.3.5a cores this data lived in the client DBC WorldSafeLocs.dbc; modern (3.4/Legion+) cores moved it to this DB table (skill_tiers-style DBC->DB migration).

## Correct state for C

The 685 safe-loc rows present in the authoritative 3.3.5a client WorldSafeLocs.dbc (max ID 1720, 19 maps, max MapID 628 — all Classic/TBC/WotLK maps that exist on the 3.4.3 WotLK-Classic client). Coordinates must come from the WotLK DBC, NOT from TDB343, because TDB343 carries Cataclysm-era relocations for old-world graveyards. Facing = 0 (the WotLK DBC has no Facing field; recordSize 88 = 22 fields = ID+MapID+X+Y+Z + 17-field localized AreaName, no facing). Schema for clean TDB343 has no TransportSpawnId column, so it is omitted from the INSERT.

## Dead values / contamination

~3485 of 4154 TDB343 rows are post-WotLK: entries for maps that do not exist in WotLK 3.3.5a content — e.g. MapID 870 (MoP Pandaria, 135 rows), 1116 (WoD Draenor, 169), 1220 (Legion Broken Isles, 265), 1642/1643 (BfA Zandalar/Kul Tiras, 155+152), 1669 (Legion Argus, 107), 2444/2569 (Dragonflight Dragon Isles). Additionally, of the 669 WotLK IDs that DO overlap TDB343, 46 have Cataclysm-relocated coordinates (e.g. ID 35 Darkshore, ID 369 Azshara moved ~2800yd, ID 329 Thousand Needles) and ID 937 was reassigned from WotLK map 559 (Nagrand Arena) to a later-expansion map (939) — so even the overlapping IDs must take WotLK DBC coords, not TDB343 coords. 16 WotLK DBC IDs (49,269,529,549,589,669,670,671,931,932,996,997,1295,1296,1297,1374) are missing from TDB343 entirely and are re-added from the DBC.

## Evidence

- **Core loader ObjectMgr::LoadWorldSafeLocs reads world_safe_locs (ID,MapID,LocX,LocY,LocZ,Facing,TransportSpawnId) and validates each MapCoord via MapManager::IsValidMapCoord, storing into _worldSafeLocs used by the graveyard/BG resurrection system.**  
  — src/server/game/Globals/ObjectMgr.cpp:6785-6826 (branch wotlk_classic)
- **Authoritative WotLK 3.3.5a WorldSafeLocs.dbc extracted from the 3.3.5a client (patch-zhTW-3.MPQ / patch-enTW-3.MPQ, WDBC) contains exactly 685 records, min ID 1 / max ID 1720, 19 distinct maps, max MapID 628 — all Classic/TBC/WotLK maps. recordSize=88, fieldCount=22 (ID+MapID+X+Y+Z + 17-field localized AreaName), i.e. NO Facing field in WotLK.**  
  — /Users/shinichi/World of Warcraft 3.3.5a/Data/zhTW/patch-zhTW-3.MPQ -> DBFilesClient\WorldSafeLocs.dbc (WDBC header parsed)
- **TDB343 world_d.world_safe_locs has 4154 rows spanning MapID 0..2569 across 451 maps — including post-WotLK maps 870 (MoP Pandaria, 135 rows), 1116 (WoD Draenor, 169), 1220 (Legion Broken Isles, 265), 1642/1643 (BfA, 155+152), 1669 (Legion Argus, 107), 2444/2569 (Dragonflight). Only 669 of the 685 WotLK IDs exist in TDB343.**  
  — docker exec tdb343-db-1 mariadb world_d: COUNT(*)=4154, GROUP BY MapID, and intersection with 685 DBC IDs = 669
- **For the shared IDs, TDB343 stores Cataclysm-relocated coordinates: 46 IDs diverge >5yd from the WotLK DBC (e.g. ID 35 Darkshore, ID 369 Azshara ~2800yd, ID 329 Thousand Needles), and ID 937 was reassigned from WotLK map 559 (Nagrand Arena) to map 939 — proving TDB343 coords cannot be trusted for a WotLK server; DBC coords are used instead.**  
  — Programmatic diff of extracted WorldSafeLocs.dbc coords vs world_d.world_safe_locs rows for the 669 shared IDs
- **Repo base schema (wotlk_classic) defines world_safe_locs with both TransportSpawnId (bigint) and Comment columns; raw TDB343 world_d schema has only Comment (no TransportSpawnId), so the self-contained INSERT targets the 7-column TDB343 layout ID,MapID,LocX,LocY,LocZ,Facing,Comment.**  
  — sql/base/dev/world_database.sql:4882 (CREATE TABLE world_safe_locs) vs SHOW CREATE TABLE world_d.world_safe_locs
- **Graveyards / safe-resurrection locations are a Classic-era feature present throughout WotLK (WorldSafeLocs.dbc shipped in the 3.3.5a client), so the feature itself is WotLK-valid; only the DBC->DB table location and the extra rows are modern.**  
  — 3.3.5a client DBFilesClient\WorldSafeLocs.dbc existence + warcraft.wiki.gg WorldSafeLocs.dbc history

## Verification notes

Coordinates were taken from the authoritative 3.3.5a WorldSafeLocs.dbc (not TDB343) precisely because TDB343 carries Cataclysm relocations. Two low-risk notes for the orchestrator's DBErrors/QA pass: (1) Facing is set to 0 for every row because the WotLK DBC has no Facing field (recordSize 88); if any WotLK BG/arena resurrection needs a specific facing it would come from core hardcode, not this table. (2) Comment for the 16 IDs re-added from the DBC (49,269,529,549,589,669,670,671,931,932,996,997,1295,1296,1297,1374) is NULL and a few carried-over TDB343 comments read '(MOVED)'/'(OLD)'; comments are cosmetic only and do not affect gameplay. All 19 referenced MapIDs (0,1,30,37,451,489,529,530,559,562,566,571,572,580,607,609,617,618,628) are Classic/TBC/WotLK maps present on the 3.4.3 client, so no invalid-map skips are expected.

---
_343-only research workflow, run wf_18cbaa1a-47d. Trims validated via world_c reload + DBErrors.log._
