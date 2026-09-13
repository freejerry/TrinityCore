# mount_definitions: WotLK-correctness (TDB343-only table)

**Verdict:** Trim (confidence: high). This table exists in TDB343 but not in 3.3.5a. Update under sql/updates/world/wotlk_classic/2026_09_13_*_world.sql.

- **Rows in raw TDB343:** 50
- **Is a WotLK feature?** partial
- **Purpose:** Maps a mount spell to its opposite-faction equivalent mount spell (spellId -> otherFactionSpellId), so the account-wide mount collection shows the faction-appropriate variant. Loaded by CollectionMgr::LoadMountDefinitions into the FactionSpecificMounts map; each entry is validated against Mount.db2 (sDB2Manager.GetMount) — a missing spell is logged and skipped. Loader: src/server/game/Entities/Player/CollectionMgr.cpp:36-71 (query at line 40).

## Correct state for C

Only the 28 rows whose spellId <= 66091 — genuine WotLK/earlier faction-specific mount pairs: Mekgineer's Chopper/Mechano-hog (55531/60424), Black/Grand Black War Mammoth, Traveler's Tundra Mammoth, kodo/elekk vendor mounts (59785-60119), Silver Covenant/Sunreaver hippogryphs (66087/66090), Black Wolf/frostsaber pair (17229/64658), and 23509/23510. Drop all 22 post-WotLK rows (spellId >= 90621).

## Dead values / contamination

22 post-WotLK rows (spellId >= 90621): Cataclysm (e.g. 90621 "Golden King", 93644), MoP (107516/107517, 118737/130985, 135416+), WoD (136163/136164, 140249/140250, 142266/142478, 171625/171842, 171626/171839), Legion (179244/179245). All reference mounts that do not exist in WotLK 3.3.5a content and are absent from the 3.4.3 (WotLK Classic) client's Mount.db2.

## Evidence

- **Table is read by CollectionMgr::LoadMountDefinitions and each spell is validated against Mount.db2; missing ones are skipped.**  
  — src/server/game/Entities/Player/CollectionMgr.cpp:40,55-67
- **world_d.mount_definitions has 50 rows, schema (spellId PK, otherFactionSpellId); table absent from 3.3.5a world_335.**  
  — docker exec tdb343-db-1 mariadb world_d SHOW CREATE TABLE / SELECT COUNT(*)
- **Collections interface / Mount Journal (the UI this table serves) was introduced in patch 5.0.4 (MoP), 2012-08-28 — post-WotLK.**  
  — WebSearch: Wowpedia 'Collections'/'Mounts tab'; Blizzard 5.0.4 Survival Guide
- **spellId 64658 = Black Wolf (Horde-specific) and 66087 = Silver Covenant Hippogryph, both WotLK.**  
  — wowhead.com/wotlk/spell=64658 ; wowhead.com/wotlk/spell=66087
- **spellId 59785 = Black War Mammoth, WotLK.**  
  — wowhead.com/wotlk/spell=59785
- **spellId 90621 = Golden King (Alliance-specific), a Cataclysm Tol Barad mount — first dropped post-WotLK row.**  
  — wowhead.com/spell=90621

## Verification notes

DBErrors pass should confirm each kept spellId (17229, 23509/23510, 55531/60424, 59785-60119, 61229-61997, 64658, 66087-66091) exists in the 3.4.3 client's Mount.db2; any that error there should be dropped too. The 22 post-WotLK rows would already be auto-skipped by CollectionMgr (missing from Mount.db2) but are removed to keep content WotLK-accurate and avoid sql.sql error spam.

---
_343-only research workflow, run wf_18cbaa1a-47d. Trims validated via world_c reload + DBErrors.log._
