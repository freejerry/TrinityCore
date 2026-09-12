# spell_required: WotLK-correct data (TDB343 vs 3.3.5a vs 3.4.3 client)

**Verdict:** import as **TDB335** (confidence: high). Delta update under sql/updates/world/wotlk_classic/2026_09_12_*_world.sql, verified to reproduce the 3.3.5a (world_335) set when applied to raw TDB343.

- **Rows:** world_d (raw TDB343) = 21, world_335 (3.3.5a) = 41
- **Difference pattern:** 335_superset
- **Structure:** Identical schema in both DBs: CREATE TABLE `spell_required` (`spell_id` int(11) NOT NULL DEFAULT 0, `req_spell` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`spell_id`,`req_spell`)) — same columns, same PK, same collation. Semantics: spell_id learn/unlearn depends on req_spell being known (dependency chains).

## Difference

world_335 is a strict superset of world_d. All 21 world_d rows are present in world_335 (0 rows are 343-only). world_335 has 20 additional rows absent from world_d. No value diffs possible (both columns form the PK). The 20 335-only rows: (16689,339),(16810,1062),(16811,5195),(16812,5196),(16813,9852),(17329,9853),(25782,19838),(25894,19854),(25899,20911),(25916,25291),(25918,25290),(27009,26989),(27141,27140),(27143,27142),(27681,14752),(48933,48931),(48934,48932),(48937,48935),(48938,48936),(53312,53308).

## Correct WotLK dataset

The full 41-row world_335 set. The 20 rows missing from TDB343 are canonical WotLK dependency chains — Nature's Grasp ranks requiring Entangling Roots ranks (16689/16810-16813/17329/27009/53312 -> 339/1062/5195/5196/9852/9853/26989/53308), Greater Blessing of Might/Wisdom/Sanctuary requiring their base Blessings (25782/25894/25899/25916/25918/27141/27143/48933/48934/48937/48938), and Prayer of Spirit requiring Divine Spirit (27681->14752). Every one of these 40 referenced spell ids exists in the 3.4.3.54261 client's SpellName DB2, so they are valid on this WotLK-content / 3.4.3-client server and TDB343 dropped live data. Re-adding the 20 rows yields world_d == world_335 (41 rows).

## Dead values / contamination

None. No post-WotLK (Cata/MoP/WoD) rows or columns; no dead/negative values (both fields are the composite PK). All 41 world_335 rows reference spells that exist in the 3.4.3.54261 client. The contamination here is the reverse of the usual case: TDB343 is missing 20 legitimate WotLK rows, not carrying extra post-WotLK ones.

## Proposed delta (vs raw TDB343)

```sql
INSERT INTO `spell_required` (`spell_id`,`req_spell`) VALUES
(16689,339),(16810,1062),(16811,5195),(16812,5196),(16813,9852),(17329,9853),
(25782,19838),(25894,19854),(25899,20911),(25916,25291),(25918,25290),(27009,26989),
(27141,27140),(27143,27142),(27681,14752),(48933,48931),(48934,48932),(48937,48935),
(48938,48936),(53312,53308);
```

## Evidence

- **Identical schema (spell_id, req_spell, composite PK) in both world_d and world_335**  
  — docker exec tdb343-db-1 mariadb world_d/world_335 -e 'SHOW CREATE TABLE spell_required' (both identical)
- **world_d=21 rows, world_335=41 rows; world_335 is a strict superset (343-only diff = empty, 335-only diff = 20 rows)**  
  — (SELECT * FROM world_335.spell_required) EXCEPT (SELECT * FROM world_d.spell_required) => 20 rows; reverse direction => 0 rows
- **spell_required drives learn/unlearn dependency: removing a req_spell unlearns dependents; loader skips any row whose spell_id or req_spell is absent from the client DB2**  
  — src/server/game/Spells/SpellMgr.cpp:972-1019 (loader, skips-if-not-in-dbc); src/server/game/Entities/Player/Player.cpp:2888-2894,2917-2919 (GetSpellsRequiringSpellBounds consumers)
- **All 20 335-only rows reference spell ids and req ids that exist in the 3.4.3.54261 client SpellName DB2 (all present)**  
  — wago.tools/db2/SpellName/csv?build=3.4.3.54261 (49357 rows); local check: every spell_id and req_spell in client id set
- **The 20 missing rows are canonical WotLK chains (Nature's Grasp<-Entangling Roots, Greater Blessings<-Blessings, Prayer of Spirit<-Divine Spirit)**  
  — SpellName build 3.4.3.54261: 16689/53312/17329/27009='Nature's Grasp', 339/26989='Entangling Roots', 25782/25916/27141/48933='Greater Blessing of Might', 25894/25918/27143/48937='Greater Blessing of Wisdom', 25899='Greater Blessing of Sanctuary', 27681='Prayer of Spirit', 14752='Divine Spirit'
- **All 41 world_335 rows are valid for our client (no row references a spell absent from 3.4.3.54261), so TDB335 verbatim is correct**  
  — world_335 spell_required dumped and cross-checked vs wago SpellName 3.4.3.54261: 0 rows with an absent spell

---
_Generated from C-layer research workflow (batch 1), run wf_36e31f1e-3e1._
