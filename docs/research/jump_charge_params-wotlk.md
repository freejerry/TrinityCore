# jump_charge_params: WotLK-correctness (TDB343-only table)

**Verdict:** Empty (confidence: high). This table exists in TDB343 but not in 3.3.5a. Update under sql/updates/world/wotlk_classic/2026_09_13_*_world.sql.

- **Rows in raw TDB343:** 4
- **Is a WotLK feature?** no
- **Purpose:** Holds jump/leap movement parameters (speed, gravity, spell visual, progress/parabolic Curve ids) keyed by an int32 id. It is loaded by ObjectMgr::LoadJumpChargeParams (src/server/game/Globals/ObjectMgr.cpp:11322, registered at World.cpp:2128) and consumed ONLY by Spell::EffectJumpCharge for SPELL_EFFECT_JUMP_CHARGE (effect 254), which looks up a row by the effect's MiscValue (src/server/game/Spells/SpellEffects.cpp:5727).

## Correct state for C

Empty table. On a WotLK 3.3.5a-content server no spell uses SPELL_EFFECT_JUMP_CHARGE (effect 254), so nothing ever queries GetJumpChargeParams; the loader returns immediately on an empty result set (ObjectMgr.cpp:11331-11334) with no error. WotLK charge/leap movement is implemented by the classic effects (SPELL_EFFECT_CHARGE=3, SPELL_EFFECT_CHARGE_DEST, SPELL_EFFECT_JUMP, SPELL_EFFECT_LEAP), none of which read this table.

## Dead values / contamination

All 4 rows are post-WotLK. They exist to feed SPELL_EFFECT_JUMP_CHARGE (254), a Legion (7.0) spell effect that does not exist in WotLK. They also reference entities absent from WotLK content: Curve db2 ids (1636, 1717 in progressCurveId) — the Curve store was introduced in WoD (6.0) and has no WotLK equivalent — and a Legion-range SpellVisual (spellVisualId 47819, far above WotLK's low-thousands range).

## Evidence

- **Table is read only by ObjectMgr::LoadJumpChargeParams and its data is consumed solely by SPELL_EFFECT_JUMP_CHARGE via GetJumpChargeParams(effectInfo->MiscValue).**  
  — src/server/game/Globals/ObjectMgr.cpp:11322,11330; src/server/game/Spells/SpellEffects.cpp:5715-5729
- **SPELL_EFFECT_JUMP_CHARGE is spell effect number 254, far beyond WotLK 3.3.5a's spell-effect range (~0-164), identifying it as a post-WotLK (Legion 7.0) effect.**  
  — src/server/game/Miscellaneous/SharedDefines.h:1575 (SPELL_EFFECT_JUMP_CHARGE = 254); SpellEffects.cpp:341
- **The effect handler resolves progress/parabolic curves through sCurveStore (the Curve db2), a data store introduced in Warlords of Draenor (6.0) that does not exist in WotLK; loader validates progressCurveId/parabolicCurveId against sCurveStore.**  
  — src/server/game/Globals/ObjectMgr.cpp:11373,11382
- **Loader returns immediately with no rows and no error when the table is empty, so leaving it empty is safe on a WotLK-content server.**  
  — src/server/game/Globals/ObjectMgr.cpp:11331-11334
- **world_d TDB343 contains 4 rows (ids 2,9,18,626) referencing Curve ids 1636/1717 and SpellVisual 47819 — Legion-era ids with no WotLK counterpart.**  
  — docker exec tdb343-db-1 mariadb world_d -e 'SELECT * FROM jump_charge_params'

---
_343-only research workflow, run wf_18cbaa1a-47d. Trims validated via world_c reload + DBErrors.log._
