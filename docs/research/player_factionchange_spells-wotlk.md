# player_factionchange_spells: WotLK-correct data (TDB343 vs 3.3.5a vs 3.4.3 client)

**Verdict:** import as **TDB335** (confidence: high). Delta update under sql/updates/world/wotlk_classic/2026_09_12_*_world.sql, verified to reproduce the 3.3.5a (world_335) set when applied to raw TDB343.

- **Rows:** world_d (raw TDB343) = 113, world_335 (3.3.5a) = 111
- **Difference pattern:** partial_overlap
- **Structure:** Schema byte-identical in world_d (343) and world_335: two columns `alliance_id` int unsigned, `horde_id` int unsigned, PRIMARY KEY(`alliance_id`,`horde_id`), InnoDB/utf8mb4. No column-semantics change. Each row maps an Alliance-side spell to its Horde-side equivalent, swapped by the core on faction change.

## Difference

110 rows identical. 343 (world_d) has 3 rows NOT in 335: (92231,92232), (95786,95909), (107516,107517). 335 has 1 row NOT in 343: (31801,53736). No value-only diffs (both columns form the PK, so any change is a whole-row add/drop). Net 113 = 110 shared + 3 extra; 111 = 110 shared + 1.

## Correct WotLK dataset

The full world_335 set of 111 pairs. These are all valid 3.3.5a spells. Concretely, the WotLK-correct set = RAW TDB343 minus the 3 post-WotLK pairs (92231/92232, 95786/95909, 107516/107517) plus the WotLK paladin-seal pair 31801 (Seal of Vengeance, Alliance) / 53736 (Seal of Corruption, Horde) that TDB343 dropped.

## Dead values / contamination

Contaminated: the 3 343-only pairs reference post-WotLK (Cataclysm-era) faction-swap spells that never existed in 3.3.5a. Verified absent from the 3.3.5a client Spell.dbc AND from the 3.4.3 client SpellName.db2 (id-list parse, 27272 ids). 92231=Spectral Steed / 95786=Moonkin Hatchling (faction-specific mount/companion spells, wowhead). Because these spell IDs exist in neither client, LoadFactionChangeSpells() (ObjectMgr.cpp:10080-10083) would log \"Spell X ... does not exist, pair skipped!\" for all 3 on this server — they are dead rows even before the WotLK-content argument. The 335-only pair 31801/53736 exists in both clients and is genuine WotLK data.

## Proposed delta (vs raw TDB343)

```sql
DELETE FROM `player_factionchange_spells` WHERE (`alliance_id`,`horde_id`) IN ((92231,92232),(95786,95909),(107516,107517));
INSERT INTO `player_factionchange_spells` (`alliance_id`,`horde_id`) VALUES (31801,53736);
```

## Evidence

- **Schema identical in both DBs (alliance_id,horde_id, composite PK).**  
  — docker SHOW CREATE TABLE world_d.player_factionchange_spells and world_335 — identical output
- **world_d=113 rows, world_335=111 rows.**  
  — SELECT COUNT(*) on both DBs
- **343-only pairs: (92231,92232),(95786,95909),(107516,107517); 335-only pair: (31801,53736).**  
  — (world_d EXCEPT world_335) UNION (world_335 EXCEPT world_d) via docker mariadb
- **31801 and 53736 exist in 3.3.5a; 92231/92232/95786/95909/107516/107517 do NOT exist in 3.3.5a.**  
  — 3.3.5a Spell.dbc extracted from patch-enTW-3.MPQ (DBFilesClient\Spell.dbc), id-column scan: 31801=True,53736=True, others=False
- **Same six IDs (92231.. etc) also absent from the 3.4.3 client; 31801/53736 present there.**  
  — /Users/shinichi/Works/side-project/tdb343-test/data/dbc/enUS/SpellName.db2 (WDC4), parsed all 10 sections' id-lists = 27272 ids: 31801=True,53736=True, six post-WotLK ids=False
- **A pair whose spell IDs are not in the loaded Spell store is skipped at load with an sql.sql error, so the 3 dead pairs never take effect.**  
  — src/server/game/Globals/ObjectMgr.cpp:10080-10085 (GetSpellInfo guard) and consumption at CharacterHandler.cpp:2326
- **92231 = 'Spectral Steed' (faction-specific mount), 95786 = 'Moonkin Hatchling' (companion) — post-WotLK faction-change spells.**  
  — wowhead.com/spell=92231 and wowhead.com/spell=95786
- **31801/53736 are the WotLK paladin Seal of Vengeance (Alliance) / Seal of Corruption (Horde) faction-swap pair, present in world_335.**  
  — world_335.player_factionchange_spells row (31801,53736); IDs resolve in 3.3.5a Spell.dbc

---
_Generated from C-layer research workflow (batch 1), run wf_36e31f1e-3e1._
