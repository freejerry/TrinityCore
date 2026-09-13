# spell_target_position: WotLK-correct data (TDB343 vs 3.3.5a vs 3.4.3 client)

**Verdict:** TDB335 (confidence: high). Final update: sql/updates/world/wotlk_classic/2026_09_13_*_world.sql (self-contained literal), verified to reproduce world_c on raw TDB343 and to load with 0 DBErrors on the 3.4.3 client.

- **Rows:** world_d (raw TDB343) = 2252, world_335 = 619
- **Difference pattern:** 343_superset
- **Structure:** Same 8 columns in both DBs (ID, EffectIndex, MapID, PositionX/Y/Z, Orientation, VerifiedBuild), PK (ID,EffectIndex). Minor DDL nullability differences only: world_d has Orientation nullable / VerifiedBuild NOT NULL; world_335 has Orientation NOT NULL / VerifiedBuild nullable — no semantic impact. NOTE (out of scope, schema not data): the wotlk_classic core loader SpellMgr::LoadSpellTargetPositions() at src/server/game/Spells/SpellMgr.cpp:1290 selects an `OrderIndex` column that NEITHER world_d NOR world_335 has — a schema migration the orchestrator must handle separately; it does not affect the WotLK-correct data decided here.

## Difference

343 is a large superset: 1702 spell IDs exist only in 343, 84 IDs only in 335, 534 IDs common. Content EXCEPT (6 pos cols): 1828 rows 343-only, 195 rows 335-only. 343 max ID = 393590 with 1459 distinct IDs > 80000 and VerifiedBuild values up to 51886 (retail Dragonflight builds); 335 max ID = 73655, zero IDs > 80000. On the 534 common IDs many coordinates differ (some drastically, e.g. spell 9268 PosY 967 vs 9664, spell 23446 PosZ 10.1 vs 137, spell 11012 MapID 1 vs 70) — 343 carries later-expansion retuned geometry/map assignments.

## Correct WotLK dataset

The 619-row world_335 set: every WotLK teleport-target coordinate keyed by (spell ID, EffectIndex), all spell IDs within the WotLK range (<=73655), with 3.3.5a coordinates/map assignments. This drops the ~1702 post-WotLK spell IDs (Cata/MoP/WoD/retail, IDs >80000, VerifiedBuild up to 51886) that TDB343 accumulated, restores the 84 WotLK spell IDs TDB343 pruned, and uses 3.3.5a coordinate values on the 534 common IDs (reverting later-expansion retuning). Consumed by SpellMgr::LoadSpellTargetPositions for SPELL_EFFECT_TELEPORT_UNITS with TARGET_DEST_DB targets; rows for spells the 3.4.3 core cannot resolve are logged to DBErrors.log and skipped, so re-adding WotLK rows is safe.

## Dead values / contamination

Heavy post-WotLK contamination in raw TDB343: 1459 distinct spell IDs > 80000 (Cata/MoP/WoD/retail, e.g. ID up to 393590) that 3.3.5a never had, and VerifiedBuild stamps up to 51886 (Dragonflight-era). These must be dropped. world_335's set is clean (all IDs <=73655); a handful of 335 rows carry later VerifiedBuild stamps (15354/26365/26899/56313) but on genuine WotLK spell IDs (e.g. 70746 map580 Sunwell, 66899 map628 Isle of Conquest, 42953 map571) — those are re-verification stamps, not data contamination.

## Evidence

- **world_d (raw TDB343) has 2252 rows / world_335 has 619 rows for spell_target_position; 1702 IDs 343-only, 84 IDs 335-only, 534 common; 1828 vs 195 rows differ on the 6 position columns.**  
  — docker exec tdb343-db-1 mariadb: COUNT(*) and EXCEPT / NOT IN diffs on world_d vs world_335 spell_target_position
- **343 carries post-WotLK contamination: max ID 393590, 1459 distinct IDs > 80000 (WotLK spell IDs max ~74000), VerifiedBuild values up to 51886 (Dragonflight retail); world_335 max ID 73655, zero IDs > 80000.**  
  — docker exec tdb343-db-1 mariadb: SELECT MIN/MAX(ID), COUNT(DISTINCT ID) WHERE ID>80000, DISTINCT VerifiedBuild on both DBs
- **Table is consumed by SpellMgr::LoadSpellTargetPositions; rows for spells that don't exist or lack a TARGET_DEST_DB/TARGET_DEST_NEARBY_DB target are logged to sql.sql error log and skipped, so extra WotLK rows added for spells the 3.4.3 core cannot resolve are safely dropped rather than fatal.**  
  — src/server/game/Spells/SpellMgr.cpp:1290,1322,1328,1353
- **Core loader on wotlk_classic selects an OrderIndex column that is absent from both world_d and world_335 schemas — flagged as an out-of-scope schema migration.**  
  — src/server/game/Spells/SpellMgr.cpp:1290 vs SHOW CREATE TABLE spell_target_position (world_d/world_335)
- **world_335 rows with late VerifiedBuild stamps (15354,26365,26899,56313,20779,18414) are on genuine WotLK spell/map IDs (70746 map580 Sunwell, 66899 map628 Isle of Conquest, 61790 map575 Utgarde Pinnacle, 42953 map571) — re-verification stamps, not post-WotLK data.**  
  — docker exec tdb343-db-1 mariadb: SELECT ID,MapID,VerifiedBuild FROM world_335.spell_target_position WHERE VerifiedBuild IN (...)

## Verification notes (pre-DBErrors)

The 84 spell IDs present in 335 but pruned by TDB343 are the prime candidates for being invalid on the 3.4.3 client (TDB343's set is largely restricted to 3.4.x-client spells; these were dropped). Orchestrator should confirm via DBErrors.log which, if any, are skipped at load: 31 33 34 35 428 443 444 445 447 1936 3721 4996 4997 4998 4999 6348 6349 6483 6714 6719 6766 8606 8996 8997 9055 11362 11409 12241 12510 12520 12885 13044 13461 17159 17160 17334 17608 17609 17610 17611 20682 22951 23442 24325 24593 24730 25004 25708 25709 25825 25826 25827 25828 26448 26450 26452 26453 26454 26455 26456 26538 26539 26630 26631 26632 31528 31529 31530 32268 32270 33068 33728 35718 36902 39871 42200 42826 44089 49362 49363 52056 53141 58421 59448. Low IDs 31/33/34/35 are old internal/serverside teleports and are the most likely to be absent from the 3.4.3 client. Per task rules these are proposed (WotLK-authentic) and NOT hard-deleted; the load-time validation pass will confirm and skip any genuinely 3.4.3-invalid rows.

---
_C-layer research workflow (deferred batch), run wf_e38612bd-12c._


## Update — 3.4.3 DBErrors.log validation

Reloaded world_c on the 3.4.3 core: 14 spell IDs (25708,26538-26539,26630-26632,31528-31530,33558,33567,33614-33616) reference spells absent from the 3.4.3 client and were dropped (15 rows). Final **604 rows**, loads with 0 DBErrors. NOTE: the current wotlk_classic core (SpellMgr.cpp:1290) SELECTs an `OrderIndex` column absent from the TDB343 base schema — a separate schema migration is required before running a freshly-built core; see memory core-todo-spell_target_position-orderindex.


## Update -- re-verified against TDB335.26091 (2026-09-14)

Re-based on TDB335.26091 (authority refreshed from 25101; +84/-58 row drift). After client-trim (wago SpellName): 604 rows. Update 2026_09_13_00 regenerated.
