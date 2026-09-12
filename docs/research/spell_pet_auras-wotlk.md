# spell_pet_auras: WotLK-correct data (TDB343 vs 3.3.5a vs 3.4.3 client)

**Verdict:** import as **TDB335** (confidence: high). Delta update under sql/updates/world/wotlk_classic/2026_09_12_*_world.sql, verified to reproduce the 3.3.5a (world_335) set when applied to raw TDB343.

- **Rows:** world_d (raw TDB343) = 2, world_335 (3.3.5a) = 47
- **Difference pattern:** 335_superset
- **Structure:** Schema byte-identical in world_d (343) and world_335 (335): columns `spell` INT UNSIGNED, `effectId` TINYINT UNSIGNED DEFAULT 0, `pet` INT UNSIGNED DEFAULT 0 ('0 = all'), `aura` INT UNSIGNED, PRIMARY KEY(`spell`,`effectId`,`pet`), InnoDB/utf8mb4. No column-semantics difference. Column meaning: `spell` is a player dummy spell whose dummy effect at `effectId` grants pet aura `aura` (SpellMgr.cpp:2085-2148).

## Difference

world_335 is a strict superset of world_d. The 2 rows in world_d — (20895,0,0,24529) and (28757,0,0,28758) — are both present verbatim in world_335. world_335 adds 45 more rows (hunter/warlock pet dummy-aura mechanics): Fel Intelligence/Fel Domination-era (19028->25228, 19578->19579), the hunter pet-ability training families 23785/23822/23823/23824/23825 (per-pet-family entries keyed by pet ids 416/417/1860/1863/17252), Ferocious Inspiration & Cobra Reflexes (34455->75593, 34459->75446, 34460->75447), Improved talents (35029->35060, 35030->35061, 35691/35692/35693->35696), and the 56314-56318 family with effectId 0 and 1 (auras 57447/57485/57452/57484/57453/57483/57457/57482/57458/57475). No value differs on the shared rows; the only difference is 45 rows missing from 343.

## Correct WotLK dataset

The full 47-row 3.3.5a set (world_335 verbatim). Every one of the 47 rows references a `spell` and an `aura` that exist as real WotLK spells in the 3.3.5a client Spell.dbc, and world_335 is TrinityCore's authoritative WotLK reference. 343's 2-row table is retail-era data loss (hunter/warlock pet dummy-aura mechanics were removed in post-WotLK expansions), not a legitimate client-based prune. The two rows 343 kept are already the correct WotLK values, so the correct set is obtained by re-adding the 45 dropped WotLK rows from 335.

## Dead values / contamination

None. No post-WotLK (Cata/MoP/WoD) contamination in either side: all 47 spell/aura ids in the 335 set are WotLK-era ids (all <= 80864) and every one was confirmed present in the 3.3.5a client Spell.dbc (49839 records). 343's defect is missing data (45 WotLK rows dropped), not dead/contaminated values. The loader skips (continue) any row whose spell or aura is absent from the running client (SpellMgr.cpp:2115-2139), so landing the full 335 set is safe even if a few rows reference spells not in the partial 3.4.3 client.

## Proposed delta (vs raw TDB343)

```sql
-- Delta vs RAW TDB343 (world_d): the 2 existing rows already match 335; re-add the 45 dropped WotLK rows.
INSERT INTO `spell_pet_auras` (`spell`,`effectId`,`pet`,`aura`) VALUES
(19028,0,0,25228),
(19578,0,0,19579),
(23785,0,416,23759),(23785,0,417,23762),(23785,0,1860,23760),(23785,0,1863,23761),(23785,0,17252,35702),
(23822,0,416,23826),(23822,0,417,23837),(23822,0,1860,23841),(23822,0,1863,23833),(23822,0,17252,35703),
(23823,0,416,23827),(23823,0,417,23838),(23823,0,1860,23842),(23823,0,1863,23834),(23823,0,17252,35704),
(23824,0,416,23828),(23824,0,417,23839),(23824,0,1860,23843),(23824,0,1863,23835),(23824,0,17252,35705),
(23825,0,416,23829),(23825,0,417,23840),(23825,0,1860,23844),(23825,0,1863,23836),(23825,0,17252,35706),
(34455,0,0,75593),
(34459,0,0,75446),
(34460,0,0,75447),
(35029,0,0,35060),
(35030,0,0,35061),
(35691,0,0,35696),(35692,0,0,35696),(35693,0,0,35696),
(56314,0,0,57447),(56314,1,0,57485),
(56315,0,0,57452),(56315,1,0,57484),
(56316,0,0,57453),(56316,1,0,57483),
(56317,0,0,57457),(56317,1,0,57482),
(56318,0,0,57458),(56318,1,0,57475);
```

## Evidence

- **Schema identical in 343 and 335 (same columns, PK, engine, charset)**  
  — docker exec tdb343-db-1 mariadb world_d/world_335 -e 'SHOW CREATE TABLE spell_pet_auras' — identical output
- **world_d has 2 rows, world_335 has 47 rows; the 2 d-rows are a subset of the 47**  
  — SELECT COUNT(*) and full dump of both tables: d={(20895,0,0,24529),(28757,0,0,28758)}, both appear in the 335 dump
- **All 47 spell ids and all 47 aura ids in the 335 set exist as real WotLK spells in the 3.3.5a client Spell.dbc**  
  — DBFilesClient/Spell.dbc extracted from /Users/shinichi/World of Warcraft 3.3.5a/Data/enTW/*.MPQ (WDBC, 49839 records, max id 80864); all target ids (19028,19578,20895,23785,23822-23825,28757,34455,34459,34460,35029,35030,35691-35693,56314-56318 and auras 25228,19579,24529,23759-23762,35702-35706,75593,75446,75447,35060,35061,35696,57447-57485) reported IN335dbc
- **The table maps a player dummy spell's dummy effect to a pet aura; consumed in SpellEffects/AuraEffects via GetPetAura+AddPetAura**  
  — src/server/game/Spells/SpellMgr.cpp:2085-2148 (LoadSpellPetAuras), :615-620 (GetPetAura); src/server/game/Spells/SpellEffects.cpp:550-552; src/server/game/Spells/Auras/SpellAuraEffects.cpp:4762-4767
- **Loader skips (continue), never aborts, when the dummy spell or the aura spell is absent from the running client — so landing rows for spells not in the 3.4.3 client is harmless**  
  — src/server/game/Spells/SpellMgr.cpp:2115-2118 (missing spell -> continue) and :2135-2139 (missing aura -> continue)
- **3.4.3 client CASC is only partially populated: Spell.db2 and SpellName.db2 resolve to stub WDC4 fragments (Spell.db2 rec_count=38 min918/max955; SpellName.db2 rec_count=8 min5/max12), so the full 3.4.3 client spell list could not be enumerated from it**  
  — root(56b585719f...)->encoding->archive extraction of FDID 1140089/1990283 from ~/WoW 3.4.3 Test/Data; parsed WDC4 headers = tiny record counts

---
_Generated from C-layer research workflow (batch 1), run wf_36e31f1e-3e1._
