# spell_group: WotLK-correct data (TDB343 vs 3.3.5a vs 3.4.3 client)

**Verdict:** import as **TDB335** (confidence: high). Delta update under sql/updates/world/wotlk_classic/2026_09_12_*_world.sql, verified to reproduce the intended WotLK set when applied to raw TDB343.

- **Rows:** world_d (raw TDB343) = 287, world_335 (3.3.5a) = 518
- **Difference pattern:** 335_superset
- **Structure:** Identical schema in both DBs: CREATE TABLE `spell_group` (`id` int unsigned, `spell_id` int, PRIMARY KEY(`id`,`spell_id`)). Same column semantics: `id` = spell group id (core range 1-4 defined in enum SpellGroup; DB range >=1000), `spell_id` = a spell in the group, or a NEGATIVE value = reference to another group id (abs value). Loader: SpellMgr.cpp:1398-1466. Related table `spell_group_stack_rules` (out of scope) also differs and 343's group 1124 there is stack_rule=1 vs 335's stack_rule=3 — the group was fully repurposed in 343.

## Difference

335 is a near-superset (518 vs 287 rows). 236 rows are in 335 but absent from 343: 343 kept only group ids 1,2,3,4,1001,1106,1109,1110,1111,1112,1121,1124 while 335 has the full WotLK stacking definitions across groups 1002-1125. Additionally group 1 (+spell 60345) and group 1001 (+40323,+66624) have WotLK members that 343 dropped. Conversely, 5 rows are in 343 but not 335 — all in group 1124 with spell_ids 389501,389512,389516,389521,389536. 335 group 1124 instead holds 2 negative references (-1085,-1073).

## Correct WotLK dataset

The full 335 spell_group set (518 rows): authentic WotLK spell-stacking group definitions (elixir/battle-elixir/guardian-elixir groups 1-4, flask/food/well-fed and other stacking groups 1001-1125, including negative cross-group references). This is the correct set for a WotLK-content server. The loader (SpellMgr.cpp:1424-1452) auto-prunes any row whose spell_id has no SpellInfo in the client-derived spell store, so 335 rows referencing spells absent from the 3.4.3 client degrade gracefully (logged + dropped) rather than breaking loading; keeping the full WotLK set is therefore both correct and safe.

## Dead values / contamination

Post-WotLK contamination in 343: group 1124 was repurposed with 5 Dragonflight/modern spell_ids — 389501 ("Red Dragonflight Pledge Pin", a 10.x+/PTR-12.x spell per wowhead), 389512, 389516, 389521, 389536. These do not exist in WotLK. 335 has zero spell_id > 200000 (verified). Beyond that, 343 is a lossy subset that discarded 231 net WotLK stacking rows.

## Proposed delta (vs raw TDB343)

```sql
-- Remove post-WotLK (Dragonflight) contamination injected into group 1124
DELETE FROM `spell_group` WHERE `id`=1124 AND `spell_id` IN (389501,389512,389516,389521,389536);
-- Re-add the WotLK spell_group rows that TDB343 dropped (yields the full 3.3.5a set = 518 rows)
INSERT INTO `spell_group` (`id`,`spell_id`)
SELECT s.`id`, s.`spell_id` FROM `world_335`.`spell_group` s
WHERE NOT EXISTS (SELECT 1 FROM `spell_group` d WHERE d.`id`=s.`id` AND d.`spell_id`=s.`spell_id`);
-- NOTE: also fix companion table spell_group_stack_rules (out of scope of this table): 343 group 1124 stack_rule=1 must become 3, and 335's ~67 group rules re-added.
```

## Evidence

- **Identical schema (id,spell_id, PK on both).**  
  — docker SHOW CREATE TABLE spell_group in world_d and world_335 — byte-identical DDL
- **Row counts: 343=287, 335=518; 236 rows in 335 not in d; 5 rows in d not in 335.**  
  — SELECT COUNT(*) and EXCEPT both directions across world_d/world_335
- **The 5 d-only rows are all group 1124 = 389501,389512,389516,389521,389536.**  
  — (world_d.spell_group EXCEPT world_335.spell_group)
- **335 group 1124 instead = negative refs -1085,-1073 (stack_rule=3), so 343 fully repurposed the group.**  
  — SELECT * FROM world_335.spell_group WHERE id=1124; SELECT * FROM world_335.spell_group_stack_rules WHERE group_id=1124
- **spell_id 389501 is 'Red Dragonflight Pledge Pin', a modern/Dragonflight-era spell (PTR 12.x) — post-WotLK.**  
  — https://www.wowhead.com/spell=389501
- **spell_id 60345 ('Armor Piercing') is a genuine WotLK spell, present in 335 group 1 but dropped in 343.**  
  — https://www.wowhead.com/wotlk/spell=60345
- **335 contains no spell_id > 200000; only 343 group 1124 does.**  
  — SELECT COUNT(*) FROM world_335.spell_group WHERE spell_id>200000 (=0); SELECT DISTINCT id FROM world_d.spell_group WHERE spell_id>200000 (=1124)
- **Negative spell_id = reference to another group; rows with missing spell/group are pruned at load (logged), so extra WotLK rows are safe.**  
  — src/server/game/Spells/SpellMgr.cpp:1417-1452

---
_Generated from C-layer research workflow (batch 2), run wf_f9c949d0-e24._
