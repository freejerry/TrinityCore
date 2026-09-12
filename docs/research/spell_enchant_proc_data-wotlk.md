# spell_enchant_proc_data: WotLK-correct data (TDB343 vs 3.3.5a vs 3.4.3 client)

**Verdict:** import as **TDB335** (confidence: high). Delta update under sql/updates/world/wotlk_classic/2026_09_12_*_world.sql, verified to reproduce the 3.3.5a (world_335) set when applied to raw TDB343.

- **Rows:** world_d (raw TDB343) = 16, world_335 (3.3.5a) = 42
- **Difference pattern:** 335_superset
- **Structure:** Identical schema in world_d (343) and world_335: columns EnchantID (PK), Chance, ProcsPerMinute, HitMask, AttributesMask; same engine/charset/collation. No column-semantics difference. EnchantID references SpellItemEnchantment.db2 IDs (validated at load time by the core).

## Difference

335 is a strict superset of 343. All 16 rows in world_d are byte-identical to their counterparts in world_335 (EXCEPT world_d minus world_335 = empty; no value diffs). world_335 has 26 additional EnchantIDs absent from 343: 2, 12, 323, 324, 325, 524, 623, 624, 625, 703, 704, 705, 706, 1667, 1668, 2635, 2641, 2644, 3369, 3768, 3769, 3772, 3773, 3782, 3783, 3784 (weapon proc enchants with PPM values 8.8 / 8.53 / 21.43 / 1). No 335-only rows in 343.

## Correct WotLK dataset

The full 42-row TrinityCore 3.3.5a set. This is TrinityCore-invented server-side proc data (PPM/chance/hit/attribute masks) for weapon proc enchantments whose proc behavior is not carried in the client DBC. All 42 EnchantIDs exist in the 3.4.3 client SpellItemEnchantment.db2, so all 42 enchants can appear on WotLK-content items and need their proc definitions to function. Correct set = world_335 verbatim (which contains all 16 world_d rows unchanged plus the 26 dropped ones).

## Dead values / contamination

None. No negative or dead values (all Chance/ProcsPerMinute >= 0, masks 0). No post-WotLK (Cata/MoP/WoD) contamination: all rows are low-ID legacy weapon proc enchants that exist in both the 3.3.5a and 3.4.3 clients. The difference is pure omission in 343, not corruption.

## Proposed delta (vs raw TDB343)

```sql
-- Re-add the 26 WotLK proc-enchant rows dropped by TDB343. The 16 existing world_d rows are byte-identical to 335, so no UPDATE/DELETE is needed.
INSERT INTO `spell_enchant_proc_data` (`EnchantID`,`Chance`,`ProcsPerMinute`,`HitMask`,`AttributesMask`) VALUES
(2,0,8.8,0,0),
(12,0,8.8,0,0),
(323,0,8.53,0,0),
(324,0,8.53,0,0),
(325,0,8.53,0,0),
(524,0,8.8,0,0),
(623,0,8.53,0,0),
(624,0,8.53,0,0),
(625,0,8.53,0,0),
(703,0,21.43,0,0),
(704,0,21.43,0,0),
(705,0,21.43,0,0),
(706,0,21.43,0,0),
(1667,0,8.8,0,0),
(1668,0,8.8,0,0),
(2635,0,8.8,0,0),
(2641,0,8.53,0,0),
(2644,0,21.43,0,0),
(3369,0,1,0,0),
(3768,0,8.53,0,0),
(3769,0,8.53,0,0),
(3772,0,21.43,0,0),
(3773,0,21.43,0,0),
(3782,0,8.8,0,0),
(3783,0,8.8,0,0),
(3784,0,8.8,0,0);
```

## Evidence

- **Identical schema; world_d has 16 rows, world_335 has 42 rows**  
  — docker mariadb: SHOW CREATE TABLE + COUNT(*) on world_d/world_335.spell_enchant_proc_data
- **335 is a strict superset: 26 rows in 335 not in 343, and 0 rows in 343 not in 335 (16 common rows byte-identical, no value shifts)**  
  — docker mariadb: (world_335.spell_enchant_proc_data) EXCEPT (world_d...) returned 26 rows; reverse direction returned empty
- **The core loader validates each EnchantID against sSpellItemEnchantmentStore and skips (logs error) any enchant absent from the client DB2; a missing row simply means that enchant has no proc definition**  
  — src/server/game/Spells/SpellMgr.cpp:2151-2192 (LoadSpellEnchantProcData, LookupEntry check at line 2172-2177)
- **All 26 dropped EnchantIDs (and all 16 kept) exist in the 3.4.3 client SpellItemEnchantment.db2 id list, so 343's omission is data loss, not client-driven pruning**  
  — WDC4 id-list parse of /Users/shinichi/Works/side-project/tdb343-test/data/dbc/enUS/SpellItemEnchantment.db2 (rec 2378, min_id 1 max_id 3883, id_list_size 9512): all 26 dropped + 16 kept IDs present, none absent
- **Table is server-side proc data consumed via GetSpellEnchantProcEvent for enchant proc chance/PPM; not a client table**  
  — src/server/game/Spells/SpellMgr.cpp:624 (GetSpellEnchantProcEvent) and World.cpp:1905 (LoadSpellEnchantProcData)

---
_Generated from C-layer research workflow (batch 1), run wf_36e31f1e-3e1._
