# item_script_names: WotLK-correctness (TDB343-only table)

**Verdict:** Trim (confidence: medium). This table exists in TDB343 but not in 3.3.5a. Update under sql/updates/world/wotlk_classic/2026_09_13_*_world.sql.

- **Rows in raw TDB343:** 10
- **Is a WotLK feature?** yes
- **Purpose:** Maps an item entry to a C++ ItemScript name so the core assigns ItemTemplate::ScriptId (fires ItemScript::OnUse etc.). Loaded by ObjectMgr::LoadItemScriptNames (src/server/game/Globals/ObjectMgr.cpp:3164-3189), which SELECTs Id,ScriptName and resolves ScriptName via GetScriptId. In 3.3.5a cores this binding lived in the item_template.ScriptName column (DBC/DB-driven item template); 3.4 removed ScriptName from item_template (item stats now come from client db2) and relocated the script binding to this dedicated table. Loader skips any Id whose ItemTemplate is absent (logs "Item {} specified in `item_script_names` does not exist, skipped.").

## Correct state for C

The 9 TBC/WotLK item-script bindings whose scripts are all registered in the wotlk_classic core (item_scripts.cpp / boss_lady_vashj.cpp): 19169 Nightfall, 24538/34475/34489 item_only_for_flight, 30175 Gor'drek's Ointment (q10488), 31088 Tainted Core (SSC), 33098 Petrov Cluster Bombs, 39878 Mysterious Egg (Oracles), 44717 Disgusting Jar (Oracles). Drop the one contamination row (53510).

## Dead values / contamination

Row Id=53510 (item_captured_frog). Its only purpose is quest 25444 "Da Perfect Spies" (QUEST_THE_PERFECT_SPIES in item_scripts.cpp), part of the Cataclysm 4.0.3 Durotar/Sen'jin 1-60 world revamp. Quest 25444 is ABSENT from world_d.quest_template (confirmed by direct query), i.e. not part of this server's 3.3.5a content, so the binding is dead on a 3.3.5a-content server.

## Evidence

- **Loader reads Id,ScriptName and binds ItemTemplate::ScriptId; skips items that don't exist**  
  — src/server/game/Globals/ObjectMgr.cpp:3164-3189 (branch wotlk_classic)
- **All 10 script names are registered ItemScripts in the wotlk_classic core**  
  — src/server/scripts/World/item_scripts.cpp:232-238 and src/server/scripts/Outland/CoilfangReservoir/SerpentShrine/boss_lady_vashj.cpp:814-888 (item_tainted_core)
- **item_scripts.cpp exists in wotlk_classic branch (blob c37baad0)**  
  — git ls-tree wotlk_classic -- src/server/scripts/World/item_scripts.cpp
- **Table has 10 rows with schema (Id int unsigned PK, ScriptName varchar(64))**  
  — docker exec tdb343-db-1 mariadb world_d SHOW CREATE TABLE + SELECT *
- **item_captured_frog (53510) exists only to service quest 25444 The Perfect Spies / Da Perfect Spies**  
  — src/server/scripts/World/item_scripts.cpp:180-204 (QUEST_THE_PERFECT_SPIES=25444)
- **Quest 25444 is absent from TDB343 quest_template (query returned no row for ID=25444)**  
  — docker exec tdb343-db-1 mariadb world_d SELECT ... quest_template WHERE ID=25444
- **Quest 25444 'Da Perfect Spies' is the Cataclysm-revamped Durotar/Sen'jin questline (Cataclysm Classic page exists); ID in the 25000+ Cataclysm range**  
  — https://www.wowhead.com/cata/quest=25444/da-perfect-spies
- **item_template no longer exists in TDB343 (item data moved to client db2), unlike 3.3.5a which had item_template.ScriptName**  
  — docker exec tdb343-db-1 mariadb world_d SHOW TABLES LIKE 'item%' (no item_template)

## Verification notes

DBErrors pass should confirm item 53510 (Captured Frog) and its quest 25444 do not resolve on the 3.4.3.54261 client; if the orchestrator decides the Sen'jin frog questline is intentionally shipped, row 53510->item_captured_frog can be re-added verbatim. Loader skips absent items harmlessly, so this is a content-correctness trim, not a crash risk.

---
_343-only research workflow, run wf_18cbaa1a-47d. Trims validated via world_c reload + DBErrors.log._
