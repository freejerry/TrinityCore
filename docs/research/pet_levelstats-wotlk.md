# pet_levelstats: WotLK data mapped to the 3.4 schema

**Verdict:** TDB335 (confidence: high). See update sql/updates/world/wotlk_classic/2026_09_13_*_world.sql.

- **Rows:** world_d(343)=2715, world_335=2560
- **Target (3.4) schema:** world_d / world_c (3.4 TARGET), 10 cols in ordinal order: creature_entry INT UNSIGNED, level TINYINT UNSIGNED, hp SMALLINT UNSIGNED, mana SMALLINT UNSIGNED, armor INT UNSIGNED, str SMALLINT UNSIGNED, agi SMALLINT UNSIGNED, sta SMALLINT UNSIGNED, inte SMALLINT UNSIGNED, spi SMALLINT UNSIGNED
- **3.3.5a schema:** world_335 (3.3.5a OLD), 12 cols in ordinal order: creature_entry INT UNSIGNED, level TINYINT UNSIGNED, hp SMALLINT UNSIGNED, mana SMALLINT UNSIGNED, armor INT UNSIGNED, str SMALLINT UNSIGNED, agi SMALLINT UNSIGNED, sta SMALLINT UNSIGNED, inte SMALLINT UNSIGNED, spi SMALLINT UNSIGNED, min_dmg SMALLINT UNSIGNED, max_dmg SMALLINT UNSIGNED. First 10 columns are IDENTICAL name/type/order to the 3.4 target; only trailing min_dmg,max_dmg differ.

## Column mapping (target 3.4 <= source)

- `creature_entry` <= 335.creature_entry direct — Present in both, same type (int unsigned). WotLK-correct copy.
- `level` <= 335.level direct — Present in both, same type (tinyint unsigned).
- `hp` <= 335.hp direct — Present in both, same type (smallint unsigned).
- `mana` <= 335.mana direct — Present in both, same type (smallint unsigned).
- `armor` <= 335.armor direct — Present in both, same type (int unsigned). Note ordinal position 5 (before str) in BOTH schemas.
- `str` <= 335.str direct — Present in both, same type (smallint unsigned).
- `agi` <= 335.agi direct — Present in both, same type (smallint unsigned).
- `sta` <= 335.sta direct — Present in both, same type (smallint unsigned).
- `inte` <= 335.inte direct — Present in both, same type (smallint unsigned).
- `spi` <= 335.spi direct — Present in both, same type (smallint unsigned).

**Dropped 3.3.5a columns:** min_dmg, max_dmg (335 ordinal 11,12). These have NO target column in 3.4. They did NOT move to a client DB2 — the TrinityCore core NEVER loaded them: LoadPetLevelInfo() in src/server/game/Globals/ObjectMgr.cpp:3414 selects only "creature_entry, level, hp, mana, str, agi, sta, inte, spi, armor" (10 cols) and PetLevelInfo (ObjectMgr.h) stores only health/mana/armor/stats[]. Pet base melee damage is computed in core code (Guardian::UpdateDamagePhysical / pet stat scaling), not sourced from this table. min_dmg/max_dmg were long-vestigial and were simply removed from the 3.4 TDB schema; dropping them loses no data the server uses.

## Correct WotLK dataset

The WotLK-correct rowset is world_335's data (32 distinct creature_entry x 80 levels = 2560 rows, levels 1-80), projected onto the 3.4 target's 10 columns by dropping min_dmg,max_dmg. The first 10 columns are name/type/order-identical between the two schemas, so every value copies directly with no transformation. No values are widened/altered. This is NOT 343-verbatim: world_d (raw TDB343) carries post-WotLK contamination (levels 1-85, i.e. 81-85 rows) and retuned stat values, which are discarded. All 32 creature_entry values (1,329,416,417,510,575,1860,1863,3450,3939,5058,5766,6250,8477,8996,10928,10979,12922,14385,15214,15352,15438,17252,19668,22362,24476,24656,24815,25553,25566,26101,26125) are the same set in both DBs and all resolve in world_335.creature_template.

## Dead values / contamination

In the recommended 335 source: none (levels 1-80 only, all 32 creatures WotLK-era pet entries, all present in creature_template). For reference, world_d (TDB343) rows at level 81-85 and its retuned stat values are post-WotLK (MoP-era cap) contamination and are excluded. Creature existence on the 3.4.3.54261 client must be confirmed by the orchestrator's DBErrors.log pass (LoadPetLevelInfo logs "Wrong creature id {} ... ignoring" for any creature_entry missing from creature_template); all 32 entries are classic/TBC/WotLK hunter/warlock/mage/DK pet creatures and are expected present.

## Evidence

- **world_d (3.4 target) has 10 columns: creature_entry,level,hp,mana,armor,str,agi,sta,inte,spi; world_335 has those 10 in identical order PLUS min_dmg,max_dmg**  
  — information_schema.columns query on tdb343-db-1 (world_d: 10 cols ordinal 1-10; world_335: 12 cols ordinal 1-12)
- **Core loader selects only 10 columns and never reads min_dmg/max_dmg**  
  — src/server/game/Globals/ObjectMgr.cpp:3414 LoadPetLevelInfo() SELECT creature_entry, level, hp, mana, str, agi, sta, inte, spi, armor; fields[9]=armor, fields[2]=hp, fields[3]=mana, fields[4..8]=stats
- **335 source is clean WotLK data: 2560 rows = 32 creatures x 80 levels, levels 1-80, all creatures present in creature_template**  
  — world_335 aggregate queries: COUNT=2560, MIN(level)=1 MAX(level)=80, 32 distinct creature_entry; JOIN creature_template returns 32
- **world_d carries post-WotLK contamination: 2715 rows, levels 1-85, plus retuned stats**  
  — world_d aggregate query: COUNT=2715, MAX(level)=85; EXCEPT diff on 10 shared cols shows 414 world_d rows not matching 335
- **Both DBs share the same 32 creature_entry set (no creature only in world_d)**  
  — world_d.pet_levelstats WHERE creature_entry NOT IN world_335 -> empty result

---
_schema-map research workflow, run wf_0984d327-80b. Validated via world_c reload + DBErrors.log._

## Update -- final decision

DBErrors: all 2560 rows warn 'Wrong creature id' because creature_template is not yet migrated (empty in C) -- expected dependency noise that resolves once creature_template lands; NOT trimmed. The data (32 pet families x levels 1-80) is WotLK-correct.
