# lfg_dungeon_template: WotLK data mapped to the 3.4 schema

**Verdict:** TDB343 (confidence: high). See update sql/updates/world/wotlk_classic/2026_09_13_*_world.sql.

- **Rows:** world_d(343)=36, world_335=20
- **Target (3.4) schema:** dungeonId int(10) unsigned, name varchar(255), position_x float, position_y float, position_z float, orientation float, requiredItemLevel smallint(6), VerifiedBuild int(11)
- **3.3.5a schema:** dungeonId int(10) unsigned, name varchar(255), position_x float, position_y float, position_z float, orientation float, VerifiedBuild int(11)

## Column mapping (target 3.4 <= source)

- `dungeonId` <= present in both; identical type int(10) unsigned. LFG dungeon id (matches LFGDungeons DB2 entry). Loader fields[0]. — key column
- `name` <= present in both; identical varchar(255). Human-readable label only. — NOT read by the core loader (LFGMgr.cpp:218 SELECT omits it); the real name comes from the LFGDungeons DB2. Kept for readability.
- `position_x` <= present in both; float. Loader fields[1] -> data.x. Teleport-in X. — 0 means 'load from map entrance areatrigger'
- `position_y` <= present in both; float. Loader fields[2] -> data.y.
- `position_z` <= present in both; float. Loader fields[3] -> data.z.
- `orientation` <= present in both; float. Loader fields[4] -> data.o.
- `requiredItemLevel` <= default handled by TDB343 values (3.4-new column; 335 has no data). Loader fields[5].GetUInt16() -> data.requiredItemLevel. — ADDED in 3.4 schema. This is the WotLK patch-3.3 LFD minimum avg item-level gate, NOT a post-WotLK feature. 335 core simply never stored it in this table, so 335 offers no value. Do NOT blanket-default to 0: use the genuine WotLK values TDB343 supplies (180 for early WotLK heroics, 200 for ToC/ICC 5-mans FoS/PoS, 219 for Halls of Reflection; 0 for old-world/holiday dungeons).
- `VerifiedBuild` <= present in both; identical int(11). Sniff-verification marker, not gameplay data. Loader ignores it.

**Dropped 3.3.5a columns:** none — every world_335 column (dungeonId, name, position_x/y/z, orientation, VerifiedBuild) also exists in the 3.4 target schema. 3.4 is a pure superset (adds requiredItemLevel).

## Correct WotLK dataset

Use world_d (TDB343) verbatim as the WotLK-correct rowset — all 36 rows. TDB343 for 3.4.3.54261 is itself a WotLK-era database: every row is Classic/TBC/WotLK content (Scarlet Monastery/Maraudon/Dire Maul/Stratholme/BRD old-world entries, the WotLK heroic 5-mans 205-256, and the holiday bosses Headless Horseman/Ahune/Coren Direbrew/Crown Chemical Co.), with zero post-WotLK (Cataclysm+) dungeons. Crucially it carries the WotLK LFD item-level requirements (180/200/219) in the new requiredItemLevel column, which world_335 cannot supply because 3.3.5a TrinityCore lacked that column. Migrating 335 data instead would REGRESS: it would drop every heroic-5man ilvl gate and omit the heroic LFD entries entirely. Only difference in 335's favor: it has explicit teleport coords for BRD entries 30 (Prison) and 276 (Upper City) that world_d omits — but the core loads those coords from the map entrance areatrigger when the row is absent, so they are not required.

## Dead values / contamination

No post-WotLK contamination in world_d — all 36 dungeons are WotLK-or-earlier LFD entries; requiredItemLevel values (max 219, Halls of Reflection) are WotLK-era, no Cataclysm 226+ gates. Rows to flag for the DBErrors pass (existence of the LFGDungeons entry on the running 3.4.3.54261 client cannot be confirmed from a db2 dump): every dungeonId inserts only if present in LfgDungeonStore (LGFMgr.cpp:231), which is filled from the client LFGDungeons DB2 — any id absent there is logged and skipped. Additionally, world_335-only ids 30 and 276 (Blackrock Depths Prison / Upper City) are absent from world_d; if the DBErrors pass shows those LFD entries exist on the client and want explicit coords, add them from 335 (see needs_human_reason).

## Evidence

- **Only schema difference is requiredItemLevel smallint(6) added at ordinal 7 in 343; all other 7 columns identical; no 335 column dropped.**  
  — information_schema.columns diff: world_d (8 cols, requiredItemLevel at pos 7) vs world_335 (7 cols, no requiredItemLevel)
- **Core loader SELECT is exactly dungeonId, position_x, position_y, position_z, orientation, requiredItemLevel (name and VerifiedBuild not read); requiredItemLevel maps to data.requiredItemLevel via fields[5].GetUInt16().**  
  — src/server/game/DungeonFinding/LFGMgr.cpp:218 and :244
- **Rows insert only if the dungeonId already exists in LfgDungeonStore (loaded from the client LFGDungeons DB2); missing ids are logged and skipped.**  
  — src/server/game/DungeonFinding/LFGMgr.cpp:231-236
- **world_d contains WotLK heroic-5man LFD entries with real ilvl gates that world_335 lacks entirely (205/210/211/212/213/215/217/219/221/226/241/242 =180; 245/249/251-254=200; 255/256=219), coords 0 (areatrigger teleport).**  
  — SELECT dungeonId,requiredItemLevel FROM world_d.lfg_dungeon_template
- **world_335 has 20 rows incl. BRD 30 & 276 absent from world_d; world_d has 36 rows all WotLK/earlier, no Cataclysm content.**  
  — SELECT * FROM world_335.lfg_dungeon_template (20 rows); SELECT ... FROM world_d.lfg_dungeon_template (36 rows)
- **LFD minimum average item level is a WotLK feature (patch 3.3 Dungeon Finder), so requiredItemLevel values are WotLK-correct, not post-WotLK.**  
  — warcraft.wiki.gg / wowhead(wotlk) Dungeon Finder patch 3.3 documentation

## Verification notes

Two decisions warrant the orchestrator's DBErrors pass / a human call: (1) world_335-only rows 30 (Blackrock Depths - Prison) and 276 (Blackrock Depths - Upper City, VerifiedBuild 11159, coords 456.929/34.0923/-68.0896 o=4.71239) are absent from world_d — if the 3.4.3.54261 LFGDungeons DB2 defines these LFD entries and they lack a map entrance areatrigger, add them (requiredItemLevel 0, old-world dungeon); otherwise the core falls back to the areatrigger and no row is needed. (2) Confirm via DBErrors.log that all 36 world_d dungeonIds resolve in the client LFGDungeons store (any missing id is silently skipped by LFGMgr.cpp:231, not fatal).

---
_schema-map research workflow, run wf_0984d327-80b. Validated via world_c reload + DBErrors.log._