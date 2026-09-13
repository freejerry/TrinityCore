# spell_area: WotLK data mapped to the 3.4 schema

**Verdict:** TDB335 (confidence: high). See update sql/updates/world/wotlk_classic/2026_09_13_*_world.sql.

- **Rows:** world_d(343)=933, world_335=786
- **Target (3.4) schema:** spell int unsigned, area int unsigned, quest_start int unsigned, quest_end int unsigned, aura_spell int(11), racemask bigint(20) unsigned, gender tinyint unsigned, flags tinyint unsigned, quest_start_status int(11), quest_end_status int(11)
- **3.3.5a schema:** spell int unsigned, area int unsigned, quest_start int unsigned, quest_end int unsigned, aura_spell int(11), racemask int(10) unsigned, gender tinyint unsigned, autocast tinyint unsigned, quest_start_status int(11), quest_end_status int(11)

## Column mapping (target 3.4 <= source)

- `spell` <= 335.spell direct — PK spell id; same type both schemas
- `area` <= 335.area direct — area/zone id; same type
- `quest_start` <= 335.quest_start direct — same type
- `quest_end` <= 335.quest_end direct — same type
- `aura_spell` <= 335.aura_spell direct — signed int, same type; negative = requires absence of aura
- `racemask` <= 335.racemask direct (type widened int unsigned -> bigint unsigned) — 3.4 widened for 64-bit race masks; all WotLK values (max 65527) fit unchanged
- `gender` <= 335.gender direct — same type; 0=male,1=female,2=both/none
- `flags` <= 335.autocast RENAMED/REPURPOSED (value copies directly) — 335 autocast tinyint (0/1) became 343 flags bitmask; loader reads fields[9]=flags and tests spellArea.flags & SPELL_AREA_FLAG_AUTOCAST where SPELL_AREA_FLAG_AUTOCAST=0x1 (SpellMgr.h:481, SpellMgr.cpp:2451,2455). Since autocast==1 maps exactly onto bit 0x1, the 335 0/1 value is a correct flags value. Bits AUTOREMOVE(0x2)/IGNORE_AUTOCAST_ON_QUEST_STATUS_CHANGE(0x4) did not exist in WotLK data and stay 0. Verified 335.autocast has only values {0,1}.
- `quest_start_status` <= 335.quest_start_status direct — same type
- `quest_end_status` <= 335.quest_end_status direct — same type

**Dropped 3.3.5a columns:** none — all 10 columns of the 335 schema have a 1:1 positional target column in the 3.4 schema. The only structural change is racemask widened int->bigint (position 6) and autocast renamed to flags (position 8). No data is dropped.

## Correct WotLK dataset

The 786 rows of world_335.spell_area, remapped into the 3.4 column order (spell, area, quest_start, quest_end, aura_spell, racemask, gender, flags, quest_start_status, quest_end_status). racemask copies unchanged into the widened bigint column; the old `autocast` value copies directly into the new `flags` column because SPELL_AREA_FLAG_AUTOCAST == 0x1 and autocast is strictly 0/1 (verified). This is the authoritative WotLK set. TDB343's world_d has 933 rows — the 223 rows present in world_d but absent from world_335 are post-WotLK (Cataclysm+) content and are correctly excluded by sourcing from 335.

## Dead values / contamination

None within the 335 rowset: max spell id 75434 (Icecrown ICC-era, patch 3.3 WotLK), max area 4910, max quest 25480 — all within WotLK bounds. The post-WotLK contamination lives only in the extra 223 world_d rows, which are dropped by using 335 as the source. Area/spell existence on the 3.4.3.54261 client is confirmed only by the running core's DBErrors.log pass (orchestrator), not here — see needs_human_reason.

## Evidence

- **world_d (TDB343, = C target schema) column order/types: spell,area,quest_start,quest_end,aura_spell,racemask(bigint unsigned),gender,flags(tinyint unsigned),quest_start_status,quest_end_status**  
  — information_schema.columns WHERE table_schema='world_d' AND table_name='spell_area' (docker exec tdb343-db-1 mariadb)
- **world_335 schema differs at position 6 (racemask int unsigned, not bigint) and position 8 (autocast tinyint, not flags)**  
  — information_schema.columns WHERE table_schema='world_335' AND table_name='spell_area'
- **Core loader SELECT list and column meaning: reads spell,area,quest_start,quest_start_status,quest_end_status,quest_end,aura_spell,racemask,gender,flags; fields[9]=flags**  
  — src/server/game/Spells/SpellMgr.cpp:2427,2451 (branch wotlk_classic)
- **flags is a bitmask; SPELL_AREA_FLAG_AUTOCAST=0x1 (auto-apply on enter), AUTOREMOVE=0x2, IGNORE_AUTOCAST_ON_QUEST_STATUS_CHANGE=0x4**  
  — src/server/game/Spells/SpellMgr.h:479-483,497; used at SpellMgr.cpp:2455,2531,2537,2553
- **335 autocast has only values 0 (124 rows) and 1 (662 rows), so it maps cleanly to flags bit 0x1 with no data loss**  
  — SELECT autocast,COUNT(*) FROM world_335.spell_area GROUP BY autocast
- **world_335.spell_area has 786 rows; max spell=75434, max area=4910, max quest=25480 — all WotLK-era**  
  — SELECT COUNT(*),MAX(spell),MAX(area),MAX(quest_start) FROM world_335.spell_area
- **world_d has 933 rows; 223 rows exist in world_d but not world_335 (post-WotLK Cata+ additions), correctly excluded**  
  — SELECT COUNT(*) FROM world_d.spell_area d WHERE NOT EXISTS (SELECT 1 FROM world_335.spell_area s WHERE s.spell=d.spell AND s.area=d.area)

## Verification notes

Row content is WotLK-correct and structurally validated. Remaining check belongs to the orchestrator's DBErrors.log pass on the running 3.4.3.54261 core: confirm every referenced spell (fields checked at SpellMgr.cpp:2458-2460), area (2494-2496), quest_start/quest_end (2500-2510) and aura_spell (2516-2526) exists on the client; the loader logs and skips any row that fails. No row is expected to fail (all ids are WotLK), but existence cannot be asserted from a db2 dump here.

---
_schema-map research workflow, run wf_0984d327-80b. Validated via world_c reload + DBErrors.log._

## Update -- final decision

flags<-autocast mapping verified against core: SPELL_AREA_FLAG_AUTOCAST=0x1 (SpellMgr.h:481), so 335 autocast 0/1 equals the flags low bit -- direct copy is correct. DBErrors: dropped 6 spells absent from the 3.4.3 client -> 780 rows. The 218+16 'wrong quest requirement' warnings are quest_template-not-yet-migrated dependency noise (resolve when quests migrate), not data errors.
