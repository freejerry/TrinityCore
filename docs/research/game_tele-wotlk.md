# game_tele: WotLK-correct data (TDB343 vs 3.3.5a vs 3.4.3 client)

**Verdict:** import as **TDB335** (confidence: high). Delta update under sql/updates/world/wotlk_classic/2026_09_12_*_world.sql, verified to reproduce the intended WotLK set when applied to raw TDB343.

- **Rows:** world_d (raw TDB343) = 2123, world_335 (3.3.5a) = 1493
- **Difference pattern:** value_shift
- **Structure:** Identical schema in 343 and 335 (id, position_x/y/z, orientation float; map smallint; name varchar(100); PK id). Only cosmetic difference: world_d declares id AUTO_INCREMENT (=2151) while world_335 does not. Column semantics unchanged; game_tele is purely the GM `.tele` command lookup table.

## Difference

Row diff: 741 rows present in 343 but not 335; 111 rows present in 335 but not 343. By id: 632 ids exist only in 343, 2 ids only in 335 (id 67 AzsharaCrater map 37, id 1371 ZG map 309 — both valid WotLK), 1491 ids common. Among common ids, 109 rows have differing values. The 632 343-only ids are overwhelmingly on post-WotLK maps: 870 (MoP Pandaria, 163 rows), 2222 (Shadowlands/The Maw, 92), 1643/1642 (BfA Kul Tiras/Zandalar), 1116 (WoD Draenor, 31 — names Draenor/DraenorShattrath/DraenorAuchindoun), 1669 (Legion Argus), 2374 (Dragonflight Dragon Isles), etc. The 109 value-diff common ids are Cataclysm world revamps/repurposing: ids 1423-1447 are WotLK dungeon/raid teleports in 335 (TrialOfTheChampion, TheStockade, AhnKahet, TheCullingOfStratholme, HallsOfLightning/Stone/Reflection, PitOfSaron, RubySanctum, EyeOfEternity, ForgeOfSouls, ObsidianSanctum, Oculus, TrialOfTheCrusader, UlduarRaid) but were repurposed in 343 to Cata zones (TheMendersStead, VictorsPoint, Highbank, NewTinkertown, etc.); Azshara (id 66), Uldum (1259), Southshore->RuinsOfSouthshore (913) moved/renamed by the Cataclysm revamp.

## Correct WotLK dataset

The 3.3.5a TrinityCore game_tele table verbatim (world_335): 1493 rows of GM teleport shortcuts whose coordinates, map ids and names reflect pre-Cataclysm (WotLK) world geography and WotLK-era dungeon/raid entrances. This includes WotLK instance teleports (Ulduar, Trial of the Crusader/Champion, Halls of Lightning/Stone/Reflection, Pit of Saron, Forge of Souls, Obsidian/Ruby Sanctum, Eye of Eternity, Oculus, Ahn'kahet, Culling of Stratholme) and pre-revamp Azshara/Southshore/Uldum coordinates, plus AzsharaCrater (map 37) and ZG (map 309).

## Dead values / contamination

Heavy post-WotLK contamination in world_d (TDB343). 632 343-only ids sit on maps that never existed in 3.3.5a: 870 (MoP Pandaria), 1116 (WoD Draenor — id 1524 'Draenor', 1532 'DraenorShattrath', 1533 'DraenorAuchindoun'), 1642/1643 (BfA), 1669 (Legion Argus), 2222/2070/2096 (Shadowlands), 2374/2444/2454 (Dragonflight), 1718/1779/2164/2374 etc. Additionally 109 common-id rows were rewritten for the Cataclysm world: ids 1423-1447 repurposed away from their WotLK dungeon meanings, and Azshara/Uldum/Southshore coordinates changed to their post-Cata versions. 335 has no dead/negative values.

## Proposed delta (vs raw TDB343)

```sql
-- Replace world_d.game_tele entirely with the 3.3.5a (WotLK) set from world_335.
-- game_tele is a self-contained GM `.tele` lookup table (no FKs), so a full replace is the exact, minimal delta.
DELETE FROM `game_tele`;
INSERT INTO `game_tele` (`id`,`position_x`,`position_y`,`position_z`,`orientation`,`map`,`name`)
SELECT `id`,`position_x`,`position_y`,`position_z`,`orientation`,`map`,`name`
FROM `world_335`.`game_tele`;
-- (world_335 here stands for the 3.3.5a reference world DB; in a real build ship these 1493 rows as literal INSERTs.)
```

## Evidence

- **Schema is byte-identical between 343 and 335 except a cosmetic AUTO_INCREMENT on id in world_d.**  
  — docker SHOW CREATE TABLE game_tele on world_d vs world_335
- **world_d has 2123 rows, world_335 has 1493; 741 rows are 343-only, 111 are 335-only; by id 632 ids are 343-only, 2 are 335-only, 109 common ids differ in value.**  
  — docker COUNT(*) and EXCEPT queries both directions, plus id-membership counts
- **632 343-only ids reference post-WotLK maps: map 1116 rows are literally named 'Draenor','DraenorShattrath','DraenorAuchindoun' (Warlords of Draenor); map 870=MoP Pandaria (163 rows), 2222=Shadowlands, 1643/1642=BfA, 1669=Legion Argus, 2374=Dragonflight.**  
  — docker SELECT id,name,map FROM world_d.game_tele WHERE map IN (870,2222,1116,...) — returned Draenor* names on map 1116
- **109 common-id value diffs are Cataclysm-era rewrites: ids 1423-1447 are WotLK dungeon/raid teleports in 335 (TrialOfTheChampion, HallsOfLightning, PitOfSaron, UlduarRaid, EyeOfEternity, Oculus, etc.) repurposed to Cata zone names (TheMendersStead, VictorsPoint, NewTinkertown...) in 343; Azshara(66)/Uldum(1259)/Southshore(913, renamed RuinsOfSouthshore) coordinates shifted per the Cataclysm world revamp.**  
  — docker JOIN value-diff query on game_tele.id comparing world_d vs world_335 (40-row sample)
- **world_335 is the designated 3.3.5a WotLK reference world DB for this task; game_tele has no foreign-key dependencies (standalone GM .tele command table).**  
  — task environment definition (world_335 = 3.3.5a TrinityCore world DB) + schema shows PK id only, no FK columns

---
_Generated from C-layer research workflow (batch 2), run wf_f9c949d0-e24._


## Update — 3.4.3 client validation (DBErrors.log oracle)

Server-log validation dropped 5 entries the 3.4.3 client rejects ("Wrong position, ignoring"): id 67 AzsharaCrater (map 37, absent in 3.4.3) and test points 1512-1515 (ExteriorTest/ScottTest/Testing/QA_DVD). Final set **1488 rows**, not 1493. Update rewritten as self-contained literal INSERTs (no world_335 reference). Source reclassified Mixed.
