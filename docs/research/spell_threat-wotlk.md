# spell_threat: WotLK-correct data (TDB343 vs 3.3.5a vs 3.4.3 client)

**Verdict:** import as **TDB335** (confidence: high). Delta update under sql/updates/world/wotlk_classic/2026_09_12_*_world.sql, verified to reproduce the 3.3.5a (world_335) set when applied to raw TDB343.

- **Rows:** world_d (raw TDB343) = 20, world_335 (3.3.5a) = 106
- **Difference pattern:** 335_superset
- **Structure:** Identical schema in world_d (343) and world_335 (335): columns entry(int unsigned PK), flatMod(int, DEFAULT NULL), pctMod(float DEFAULT 1), apPctMod(float DEFAULT 0). Same column semantics; verified via SHOW CREATE TABLE on both DBs.

## Difference

world_d(343) is a STRICT SUBSET of world_335: all 20 of 343's rows exist byte-identically in 335. (world_d EXCEPT world_335) returns 0 rows and (world_335 EXCEPT world_d) returns exactly 86 rows, so there are no 343-only rows and no value differences on the shared 20. The 86 335-only rows are additional aggro-generating spells missing from 343.

## Correct WotLK dataset

The full 3.3.5a spell_threat set of 106 rows (world_335). All 106 entries are WotLK-era threat abilities and their spell ranks (e.g. Heroic Strike R1/R2/R3 = 78/284/285, Cleave 845, Maul ranks 6808/6809, Consecration/Paladin threat, DK Shield/Death abilities, Lacerate 33745, etc.). 343 kept only ~1 (top-rank) entry per ability; the WotLK-correct set restores all ranks so lower-rank casts generate correct threat. Rows referencing any entry absent from the 3.4.3 client are harmlessly skipped by the loader (SpellMgr.cpp GetSpellInfo guard).

## Dead values / contamination

None. world_335 is a WotLK-native DB; all 106 rows reference WotLK spells (no Cata/MoP/WoD content). No negative/flattened dead values that break gameplay: values are the standard WotLK threat coefficients. 343 carries no post-WotLK contamination either — it is simply an incomplete subset.

## Proposed delta (vs raw TDB343)

```sql
INSERT INTO `spell_threat` (`entry`,`flatMod`,`pctMod`,`apPctMod`) VALUES
(78,5,1,0),(284,10,1,0),(285,16,1,0),(779,0,1.5,0),(845,8,1,0),(1608,22,1,0),(5209,98,1,0),(5676,0,2,0),(6574,11,1,0),(6798,105,1,0),(6808,20,1,0),(6809,27,1,0),(7294,0,2,0),(7369,15,1,0),(7379,15,1,0),(7386,345,1,0.05),(8056,0,2,0),(8820,24,1,0),(8972,47,1,0),(8983,158,1,0),(9745,75,1,0),(9880,106,1,0),(9881,140,1,0),(11564,31,1,0),(11565,48,1,0),(11566,70,1,0),(11567,92,1,0),(11600,27,1,0),(11601,41,1,0),(11604,38,1,0),(11605,49,1,0),(11608,25,1,0),(11609,35,1,0),(15237,0,0,0),(19675,80,1,0),(19742,0,0,0),(20185,0,0,0),(20470,0,0,0),(20569,48,1,0),(23455,0,0,0),(23923,268,1,0),(23924,307,1,0),(23925,347,1,0),(25231,68,1,0),(25241,59,1,0),(25242,78,1,0),(25258,387,1,0),(25269,58,1,0),(25286,104,1,0),(25288,53,1,0),(25894,0,0,0),(26688,0,0,0),(26996,212,1,0),(28176,0,0,0),(29166,0,10,0),(29707,121,1,0),(30324,164,1,0),(30356,426,1,0),(30357,71,1,0),(33619,0,0,0),(33745,182,0.5,0),(34299,0,0,0),(47449,224,1,0),(47450,259,1,0),(47474,123,1,0),(47475,140,1,0),(47487,650,1,0),(47488,770,1,0),(47519,95,1,0),(47520,112,1,0),(48479,345,1,0),(48480,422,1,0),(48567,409,0.5,0),(48568,515,0.5,0),(49916,138,1,0),(50181,0,0,0),(50422,0,0,0),(51209,112,1,0),(55265,63,1,0),(55270,98,1,0),(55271,120,1,0),(56815,0,1.75,0),(57823,121,1,0),(60089,638,1,0),(63611,0,0,0),(65142,0,0,0);
```

## Evidence

- **Identical schema in both DBs (entry PK, flatMod int NULL, pctMod float def 1, apPctMod float def 0)**  
  — docker SHOW CREATE TABLE spell_threat on world_d and world_335 — byte-identical CREATE statements
- **343 has 20 rows, 335 has 106 rows**  
  — SELECT COUNT(*) FROM spell_threat: world_d=20, world_335=106
- **343 is a strict subset of 335: no 343-only rows, no value diffs; 86 rows are 335-only**  
  — (SELECT * FROM world_d.spell_threat) EXCEPT (SELECT * FROM world_335.spell_threat) -> 0 rows; reverse direction -> 86 rows
- **Loader drops any spell_threat row whose entry is absent from the client Spell store (harmless skip of nonexistent spells)**  
  — src/server/game/Spells/SpellMgr.cpp:2054-2058 — if(!GetSpellInfo(entry,DIFFICULTY_NONE)){ TC_LOG_ERROR ... continue; }
- **Spell 78 Heroic Strike (Rank 1) is present in WotLK Classic**  
  — https://www.wowhead.com/wotlk/spell=78/heroic-strike (WotLK Classic page)
- **Spell 284 Heroic Strike (Rank 2) is present in WotLK Classic**  
  — https://www.wowhead.com/wotlk/spell=284/heroic-strike (WotLK Classic page)
- **Spell 47487 (Shield Slam, higher WotLK rank) is present in WotLK Classic**  
  — https://www.wowhead.com/wotlk/spell=47487 (WotLK Classic page)
- **3.4.3 client SpellName.db2 (FileDataID 1990283) exists in the client build (root+encoding resolve it) but its content is BLTE-encrypted (mode 'E', 14 chunks) so IDs could not be enumerated locally without the TACT key**  
  — root parse of 3.4.3 client (~/WoW 3.4.3 Test) fdid 1990283 -> ckey 768ca4d7...; range-fetched blte from archive ccdb4476... via 127.0.0.1:8100; BLTE header magic OK, first data chunk mode 'E' -> casc_blte 'BLTE mode E unsupported'
- **WotLK Classic 3.4.3 retained the spell-rank system (ranks removed only in Cataclysm), so lower-rank threat spells present in 3.3.5a also exist in 3.4.3**  
  — warcraft.wiki.gg / wowhead wotlk domain — spell rank pages (e.g. Heroic Strike R1/R2) exist for WotLK Classic; rank removal is a Cataclysm change

---
_Generated from C-layer research workflow (batch 1), run wf_36e31f1e-3e1._


## Update — 3.4.3 client validation (DBErrors.log oracle)

Server-log validation (reload world_c → DBErrors.log) found spell **65142** does not exist in the 3.4.3 client. Final set drops it: **105 rows**, not the full 3.3.5a 106. Source reclassified Mixed. The earlier SpellName.db2-based audit was invalid (broken extraction).
