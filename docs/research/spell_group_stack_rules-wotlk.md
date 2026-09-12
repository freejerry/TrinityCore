# spell_group_stack_rules: WotLK-correct data (TDB343 vs 3.3.5a vs 3.4.3 client)

**Verdict:** import as **TDB335** (confidence: high). Delta update under sql/updates/world/wotlk_classic/2026_09_12_*_world.sql, verified to reproduce the 3.3.5a (world_335) set when applied to raw TDB343.

- **Rows:** world_d (raw TDB343) = 10, world_335 (3.3.5a) = 67
- **Difference pattern:** 335_superset
- **Structure:** Identical schema in both DBs: `group_id` int unsigned PK, `stack_rule` tinyint. No column-semantics difference. Table is a sibling of `spell_group` (group_id -> stacking behavior); loader requires each group_id to have members in `spell_group` or the rule is skipped with an sql.sql error.

## Difference

world_335 is a near-superset (67 rows) of world_d (10 rows). 335 EXCEPT 343 = 58 rows (all the WotLK group stacking rules 1002..1125 that 343 dropped). 343 EXCEPT 335 = a single row 1124=1 (value shift: 335 has 1124=3). All 343 group_ids except 1124 are a subset of 335 with identical stack_rule. No 343-unique group ids other than the repurposed 1124.

## Correct WotLK dataset

The full 67-row WotLK TrinityCore set from world_335: group_ids {1,2,1001,1002,1003,1004,1005,1006,1007,1008,1009,1010,1011,1015,1016,1019,1022,1023,1024,1025,1029,1033,1036,1037,1038,1046,1048,1051,1054,1056,1058,1059,1060,1061,1062,1083,1084,1085,1086,1087,1088,1089,1090,1093,1094,1095,1096,1097,1098,1099,1100,1101,1104,1105,1106,1107,1108,1109,1110,1111,1112,1121,1122,1123,1124,1125} with their WotLK stack_rule values (notably 1124=3, not 343's 1). These are server-side WotLK spell-stacking group behaviors (elixir/food/scroll/aura exclusivity), independent of the rendering client. To take effect, sibling table `spell_group` must also carry the matching WotLK group members (world_d.spell_group was trimmed to 12 distinct ids / retail members; world_335 has 113).

## Dead values / contamination

Post-WotLK (Dragonflight/retail) contamination in world_d: group_id 1124 is repurposed. world_d.spell_group id 1124 contains retail spell ids 389501/389512/389516/389521/389536 (390xxx range = Dragonflight-era, far above WotLK's ~80k ceiling), and its stack_rule is 1; the WotLK 335 group 1124 instead references sub-groups (-1085,-1073) with stack_rule 3. world_d dropped 57 legitimate WotLK stacking rules because TDB343's `spell_group` was trimmed to retail content. So the 343 row set is a retail-flavored fragment, not a WotLK subset.

## Proposed delta (vs raw TDB343)

```sql
-- Restore the WotLK-correct spell_group_stack_rules set (delta vs RAW TDB343 world_d).
-- Requires the sibling `spell_group` to also hold the WotLK group members (handled by that table's task);
-- rules whose group has no `spell_group` members are otherwise skipped by the loader with an sql.sql warning.
DELETE FROM `spell_group_stack_rules`;
INSERT INTO `spell_group_stack_rules` (`group_id`,`stack_rule`) VALUES
(1,1),(2,1),(1001,1),(1002,4),(1003,4),(1004,4),(1005,4),(1006,1),(1007,1),(1008,1),
(1009,1),(1010,2),(1011,2),(1015,3),(1016,4),(1019,3),(1022,4),(1023,4),(1024,4),(1025,3),
(1029,1),(1033,1),(1036,4),(1037,3),(1038,3),(1046,4),(1048,4),(1051,3),(1054,3),(1055,4),
(1056,3),(1058,3),(1059,3),(1060,3),(1061,4),(1062,4),(1083,4),(1084,4),(1085,4),(1086,4),
(1087,4),(1088,4),(1089,4),(1090,4),(1093,4),(1094,3),(1095,4),(1096,4),(1097,1),(1098,4),
(1099,2),(1100,1),(1101,3),(1104,1),(1105,3),(1106,1),(1107,4),(1108,4),(1109,1),(1110,1),
(1111,1),(1112,1),(1121,1),(1122,4),(1123,1),(1124,3),(1125,3);
```

## Evidence

- **Both DBs share identical schema (group_id PK, stack_rule tinyint).**  
  — docker SHOW CREATE TABLE spell_group_stack_rules on world_d and world_335 — identical DDL
- **world_d has 10 rows; world_335 has 67 rows; 335 is a superset except a single value shift on 1124.**  
  — COUNT(*) = 10 vs 67; (world_d EXCEPT world_335)=only {1124,1}; (world_335 EXCEPT world_d)=58 rows
- **The stack rule for a group is only applied if the group has members in spell_group; otherwise it is skipped with an sql.sql error.**  
  — src/server/game/Spells/SpellMgr.cpp:1499-1504 (GetSpellGroupSpellMapBounds check in LoadSpellGroupStackRules)
- **Valid stack_rule values are 0..4 (SPELL_GROUP_STACK_RULE_MAX=5); all 335 values (1,2,3,4) are valid.**  
  — src/server/game/Spells/SpellMgr.h:341-348
- **world_d group 1124 is repurposed to retail/Dragonflight spells (389501,389512,389516,389521,389536) with stack_rule 1, whereas WotLK 335 group 1124 references sub-groups (-1085,-1073) with stack_rule 3.**  
  — SELECT * FROM spell_group WHERE id=1124 on world_d vs world_335; spell ids 389xxx are Dragonflight-range, above WotLK's spell-id ceiling
- **world_d.spell_group was trimmed to 12 distinct group ids (retail set) vs world_335's 113, explaining why 57 WotLK stack rules were dropped from world_d.**  
  — SELECT COUNT(DISTINCT id) FROM spell_group = 12 (world_d) vs 113 (world_335); DISTINCT id list on world_d shows only 1,2,3,4,1001,1106,1109,1110,1111,1112,1121,1124
- **world_335 is the TrinityCore 3.3.5a WotLK reference DB, so its 67-row set is the authoritative WotLK content; stacking is server-side aura logic and does not depend on the 3.4.3 client.**  
  — task environment definition of world_335; LoadSpellGroupStackRules consumes only server DB, no client DBC/DB2 reference in src/server/game/Spells/SpellMgr.cpp:1469-1515

---
_Generated from C-layer research workflow (batch 1), run wf_36e31f1e-3e1._
