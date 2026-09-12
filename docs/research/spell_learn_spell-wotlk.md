# spell_learn_spell: WotLK-correct data (TDB343 vs 3.3.5a vs 3.4.3 client)

**Verdict:** import as **TDB335** (confidence: high). Delta update under sql/updates/world/wotlk_classic/2026_09_12_*_world.sql, verified to reproduce the 3.3.5a (world_335) set when applied to raw TDB343.

- **Rows:** world_d (raw TDB343) = 5, world_335 (3.3.5a) = 8
- **Difference pattern:** partial_overlap
- **Structure:** Schema byte-identical in world_d and world_335: columns `entry` INT UNSIGNED, `SpellID` INT UNSIGNED, `Active` TINYINT UNSIGNED DEFAULT 1, PRIMARY KEY(entry,SpellID), InnoDB utf8mb4. Semantics: entry = source spell that, when learned, teaches SpellID; Active = whether the learned spell is shown/active. NOTE: this world-DB table is unrelated to the identically-named DB2/hotfix table (HotfixDatabase.cpp: ID/SpellID/LearnSpellID/OverridesSpellID) — the world loader is SpellMgr.cpp:1076 `SELECT entry, SpellID, Active`.

## Difference

2 rows shared by both: (33943->34090 Flight Form->Master Riding, Active1) and (58984->21009 Shadowmeld, Active1). 343-only (3 rows): all under entry 125610 = "Battle Pet Training" teaching 119467/122026/125439 — MoP pet-battle spells. 335-only (6 rows): (17002->24867,0),(24866->24864,0) = Feral Swiftness passives; (33872->47179,0),(33873->47180,0) = Nurturing Instinct passives; (53428->53341,1),(53428->53343,1) = Runeforging -> Rune of Cinderglacier/Razorice (Death Knight). No value shifts on the shared rows. So world_335 = 2 shared + 6 WotLK-only; world_d = 2 shared + 3 MoP-only.

## Correct WotLK dataset

The 8 rows of world_335 verbatim: the 2 baseline rows both DBs share plus the 6 WotLK learn-relationships TDB343 dropped (Feral Swiftness 17002/24866, Nurturing Instinct 33872/33873, Death Knight Runeforging 53428). The 3 MoP "Battle Pet Training" rows (entry 125610) must be removed. Result set is exactly world_335.

## Dead values / contamination

Post-WotLK contamination in RAW TDB343: entry 125610 = "Battle Pet Training" (Mists of Pandaria pet-battle system, patch 5.0) teaching SpellID 119467, 122026, 125439 — none of these four spell IDs exist in the 3.3.5a WotLK client (verified by parsing Spell.dbc: all four absent). These are MoP-era rows that WotLK never had. No dead/negative values on the shared rows.

## Proposed delta (vs raw TDB343)

```sql
-- Drop MoP "Battle Pet Training" contamination
DELETE FROM `spell_learn_spell` WHERE `entry`=125610 AND `SpellID` IN (119467,122026,125439);
-- Re-add WotLK learn-relationships TDB343 dropped (present in world_335)
INSERT INTO `spell_learn_spell` (`entry`,`SpellID`,`Active`) VALUES
 (17002,24867,0),  -- Feral Swiftness -> Feral Swiftness Passive 1a
 (24866,24864,0),  -- Feral Swiftness (rank) -> Feral Swiftness Passive 2a
 (33872,47179,0),  -- Nurturing Instinct -> passive
 (33873,47180,0),  -- Nurturing Instinct (rank) -> passive
 (53428,53341,1),  -- Runeforging -> Rune of Cinderglacier
 (53428,53343,1);  -- Runeforging -> Rune of Razorice
-- The 2 shared rows (33943->34090, 58984->21009) already exist in RAW 343; leave as-is.
-- Applied to world_d this yields exactly world_335's 8 rows.
```

## Evidence

- **Schema identical in 343 and 335; loader reads entry/SpellID/Active from the world DB.**  
  — SHOW CREATE TABLE (both DBs, identical); src/server/game/Spells/SpellMgr.cpp:1076
- **world_d has 5 rows, world_335 has 8; EXCEPT both ways gives 3 343-only rows (all entry 125610) and 6 335-only rows.**  
  — docker exec tdb343-db-1 mariadb: COUNT(*) and (SELECT*..)EXCEPT(SELECT*..) both directions
- **All 15 335-side spell IDs (17002,21009,24864,24866,24867,33872,33873,33943,34090,47179,47180,53341,53343,53428,58984) EXIST in the 3.3.5a WotLK client; the 4 343-only IDs (125610,119467,122026,125439) are ABSENT.**  
  — parsed DBFilesClient/Spell.dbc from patch-enTW-3.MPQ (WDBC, 49839 records); presence map printed
- **Spell 125610 = 'Battle Pet Training', a Mists of Pandaria+ pet-battle spell — post-WotLK.**  
  — https://www.wowhead.com/spell=125610
- **Spell 53341 = 'Rune of Cinderglacier' is a WotLK Classic spell (DK runeforging), i.e. present in the 3.4.x client family.**  
  — https://www.wowhead.com/wotlk/spell=53341
- **Spell 24867 = 'Feral Swiftness Passive 1a' is a WotLK Classic Druid feral-form passive.**  
  — https://www.wowhead.com/wotlk/spell=24867
- **3.4.3 client SpellLearnSpell.db2 (FileDataID 1001907) has 0 records, so the loader's sSpellLearnSpellStore auto-add path contributes nothing — these learn links must come from the world table (or SPELL_EFFECT_LEARN_SPELL).**  
  — extracted from ~/WoW 3.4.3 Test CASC (build c91609..., 3.4.3.54261) via casc pipeline; WDC4 header records=0
- **Loader validates source and learned spells via GetSpellInfo and skips (error-logs) any row whose spells are absent from the client store, so re-added rows are safe even if a spell were missing.**  
  — src/server/game/Spells/SpellMgr.cpp:1097-1108

## Residual uncertainty

Could not directly read the 3.4.3 client SpellName/SpellEffect/SpellMisc DB2s to confirm each 335-only spell ID is present and whether any of these learns is instead provided by a SPELL_EFFECT_LEARN_SPELL in the 3.4.3 Spell data (those local DB2 copies are BLTE mode 'E' encrypted and CDN standalone fetch 404s). Mitigation: identities and WotLK-Classic presence confirmed via wowhead (53341, 24867 are WotLK Classic spells) and 3.3.5a Spell.dbc; SpellLearnSpell.db2 is empty in 3.4.3; and the loader harmlessly skips any row whose spells are absent. Even if a re-added link were redundant with a spell effect, the only effect is a benign 'redundant record' log, not wrong data — so the 335 set remains WotLK-correct. Residual uncertainty is low.

---
_Generated from C-layer research workflow (batch 1), run wf_36e31f1e-3e1._
