# creature_template column audit — world_c (migrated TDB343 → WotLK-clean)

Certifies every audited column of `world_c.creature_template` (29923 rows, TDB343 minus 95
post-WotLK rows, faction/family/VehicleId already fixed by `2026_09_13_16_world.sql`) against
the **core-allowed domain** and against **world_335** (hand-curated 3.3.5a WotLK truth).

## Sources for the allowed domain

- Core validation: `src/server/game/Globals/ObjectMgr.cpp` — `LoadCreatureTemplate` (field map,
  lines 399-469) and `CheckCreatureTemplate` (per-field strip/clamp, lines 1029-1184).
- Bit masks: `src/server/game/Entities/Unit/UnitDefines.h` (UnitFlags / UnitFlags2 / UnitFlags3
  `*_ALLOWED`, npcflag enum) and `src/server/game/Entities/Creature/CreatureData.h`
  (`CREATURE_FLAG_EXTRA_DB_ALLOWED`, line 381).
- Enums / ranges: `SharedDefines.h` — `MAX_EXPANSIONS`=10 (l.102), `MAX_SPELL_SCHOOL`=7 (l.357),
  `CLASSMASK_ALL_CREATURES` (l.220, classes 1/2/4/8), `CreatureClassifications` 0-6 (l.4929),
  `MAX_MECHANIC`=37 (l.2769); `MovementDefines.h` `MAX_DB_MOTION_TYPE`=3 (l.37).
- Client (3.4.3.54261) refcache: `db2_FactionTemplate` (845), `db2_CreatureFamily`,
  `db2_CreatureType` (IDs 1-13), `db2_Vehicle` (412).

### Computed allowed masks (from the enums above)

| column       | ALLOWED mask (hex) | derivation |
|--------------|--------------------|------------|
| unit_flags   | `0x02000340` | `0xFFFFFFFF & ~UNIT_FLAG_DISALLOWED` |
| unit_flags2  | `0x04034823` | `0xFFFFFFFF & ~UNIT_FLAG2_DISALLOWED` |
| unit_flags3  | `0x014DE0B6` | `0xFFFFFFFF & ~UNIT_FLAG3_DISALLOWED` |
| flags_extra  | `0x603FFFFF` | `0xFFFFFFFF & ~(CREATURE_FLAG_EXTRA_UNUSED \| DUNGEON_BOSS)` |
| npcflag      | `0x07FFFFFF` | WotLK npcflag = low-32, bits GOSSIP(0x1)…MAILBOX(0x04000000); npcflag2 (high 32) and ARTIFACT_RESPEC(0x08000000)+ are post-WotLK |

## Per-column verdict

Domain key: **core** = validated/stripped by `CheckCreatureTemplate`; **enum/range**; **bitmask**;
**FK** = foreign key checked by core; **free**; **meta** = passed through, not validated.

| # | column | domain | violations in world_c | verdict |
|---|--------|--------|-----------------------|---------|
| 1 | entry | PK | 0 (1:1 with 335) | CLEAN |
| 2 | KillCredit1 | FK creature→0 | 0 dangling | CLEAN |
| 3 | KillCredit2 | FK creature→0 | 0 dangling | CLEAN |
| 4 | name | free | 1 empty (30618, 335 also empty); 53 differ 335 (curation, in-sanity) | CLEAN |
| 5 | femaleName | meta (335 lacks) | — | CLEAN (meta) |
| 6 | subname | free | 89 differ 335 (curation) | CLEAN |
| 7 | TitleAlt | meta | — | CLEAN (meta) |
| 8 | IconName | free | 19 distinct standard icons | CLEAN |
| 9 | RequiredExpansion | core `<10` | **all rows = 0** | CLEAN (WotLK) |
| 10 | VignetteID | core (Vignette store)→0 | **all = 0** | CLEAN (no WotLK vignettes) |
| 11 | faction | FK FactionTemplate→35 | 0 invalid vs 845-row client set | CLEAN (migration) |
| 12 | npcflag | bitmask `0x07FFFFFF` | **7** carry post-WotLK bits | NEEDS-FIX → fixed |
| 13 | speed_walk | core `!=0` | 0 zero | CLEAN |
| 14 | speed_run | core `!=0` | 0 zero | CLEAN |
| 15 | scale | float `>0` | 0 ≤0 | CLEAN |
| 16 | Classification | enum 0-6 | 0 out of range (diffs vs 335.rank all within 0-6) | CLEAN |
| 17 | dmgschool | core `<7` | 0 | CLEAN |
| 18 | BaseAttackTime | core `!=0` | 0 zero | CLEAN |
| 19 | RangeAttackTime | core `!=0` | 0 zero | CLEAN |
| 20 | BaseVariance | float, meta | — | CLEAN |
| 21 | RangeVariance | float, meta | — | CLEAN |
| 22 | unit_class | 1/2/4/8 | 0 | CLEAN |
| 23 | unit_flags | bitmask `0x02000340` | **9114** disallowed bits | NEEDS-FIX → masked |
| 24 | unit_flags2 | bitmask `0x04034823` | **2244** disallowed bits | NEEDS-FIX → masked |
| 25 | unit_flags3 | bitmask `0x014DE0B6` (3.4-new) | **599** disallowed bits | NEEDS-FIX → masked |
| 26 | family | FK CreatureFamily→0 | 0 invalid vs client | CLEAN (migration) |
| 27 | trainer_class | used (class-trainer) | values {1-9,11}; no Monk10/DH12/Evoker13 | CLEAN |
| 28 | type | core (CreatureType 1-13; 0 ok) | **29** rows type=15 (335=10); 24 type=0 (335=0) | NEEDS-FIX → set 10 |
| 29 | PetSpellDataId | meta (client) | 857 nonzero; 32 differ 335 (both WotLK-era) | CLEAN (not core-constrained) |
| 30 | VehicleId | FK Vehicle→0 | 0 invalid vs 412-row client set | CLEAN (migration) |
| 31 | AIName | core registry+DBPermit | only Null/Passive/Smart/TurretAI — all registered | CLEAN |
| 32 | MovementType | core `<3` | 0 | CLEAN |
| 33 | ExperienceModifier | float, meta | — | CLEAN |
| 34 | Civilian | bool | 0 not-in-(0,1) | CLEAN |
| 35 | RacialLeader | bool | 0 not-in-(0,1) | CLEAN |
| 36 | movementId | meta (CreatureMovementInfo) | =raw TDB343 (client-matched); differs 335 (renumbering) | CLEAN (client-valid) |
| 37 | WidgetSetID | meta (post-WotLK) | **all = 0** | CLEAN |
| 38 | WidgetSetUnitConditionID | meta | **all = 0** | CLEAN |
| 39 | RegenHealth | bool | 0 not-in-(0,1) | CLEAN |
| 40 | mechanic_immune_mask | mask, not core-checked | max `0x7FFFFF7F` (≤ mech31 ENRAGED); no bit31 | CLEAN |
| 41 | spell_school_immune_mask | 7 schools | all ≤ 127 | CLEAN |
| 42 | flags_extra | bitmask `0x603FFFFF` | **403** disallowed bits | NEEDS-FIX → masked |
| 43 | ScriptName | core-registered or empty | 5 names lack C++ in this branch (see Flags) | FLAGGED (not DB data) |
| 44 | StringId | meta | — | CLEAN (meta) |
| 45 | VerifiedBuild | meta | — | CLEAN (meta) |

### npcflag detail (the 7 fixed rows)

| entry | before | offending bit(s) | after (= WotLK) | 335 |
|-------|--------|------------------|-----------------|-----|
| 7554 | `0x40000000` | WILD_BATTLE_PET (Legion) | 0 | 0 |
| 28708,29139,29141,29143,29145 | `0x4000000000001` | npcflag2 bit 50 | 1 (GOSSIP) | 1 |
| 29142 | `0x4000000000003` | npcflag2 bit 50 | 3 (GOSSIP+QUESTGIVER) | 1 |

Masking with `0x07FFFFFF` strips the post-WotLK bit while keeping the WotLK-valid low bits
(both `1` and `3` are within the WotLK npcflag domain, so 29142 is certifiable either way).

### Why mask (not copy 335) for unit_flags / unit_flags2

The disallowed bits (SERVER_CONTROLLED, IN_COMBAT, STUNNED, LOOTING, …) are **runtime state
flags**, not post-WotLK content — they existed in 3.3.5 and world_335 itself carries them
(7658 rows on unit_flags, 27 on unit_flags2). The core strips them at load in every version, so
they are *dead* regardless of origin. Copying 335 would not clean them. `AND`-masking with the
core `*_ALLOWED` mask removes exactly the bits the core removes at runtime and nothing else — zero
behavioural information lost, result provably inside the allowed domain. After masking, the only
remaining differences vs 335 are in bits that are valid in WotLK (UNK_6 0x40, IMMUNE_TO_PC 0x100,
IMMUNE_TO_NPC 0x200, UNINTERACTIBLE 0x2000000) — in-domain data revisions, not contamination.
`unit_flags3` is a 3.4-only column (335 has none), so it can only be mask-stripped per the core.

## Corrective SQL — run AFTER `2026_09_13_16_world.sql`

Self-contained; references no other DB. Idempotent (each `WHERE` re-selects only dirty rows).

```sql
-- creature_template: eliminate all remaining dead/post-WotLK values so every audited column
-- sits inside its core-allowed domain (ObjectMgr::CheckCreatureTemplate) and is WotLK-consistent.

-- 1) unit_flags: strip bits outside UNIT_FLAG_ALLOWED (runtime-only flags the core removes at load).
UPDATE `creature_template` SET `unit_flags`  = `unit_flags`  & 0x02000340 WHERE (`unit_flags`  & ~0x02000340) <> 0;

-- 2) unit_flags2: strip bits outside UNIT_FLAG2_ALLOWED.
UPDATE `creature_template` SET `unit_flags2` = `unit_flags2` & 0x04034823 WHERE (`unit_flags2` & ~0x04034823) <> 0;

-- 3) unit_flags3 (3.4-only column, no 335 truth): strip bits outside UNIT_FLAG3_ALLOWED.
UPDATE `creature_template` SET `unit_flags3` = `unit_flags3` & 0x014DE0B6 WHERE (`unit_flags3` & ~0x014DE0B6) <> 0;

-- 4) flags_extra: strip bits outside CREATURE_FLAG_EXTRA_DB_ALLOWED (UNUSED_22..27/31 + DUNGEON_BOSS).
UPDATE `creature_template` SET `flags_extra` = `flags_extra` & 0x603FFFFF WHERE (`flags_extra` & ~0x603FFFFF) <> 0;

-- 5) npcflag: strip post-WotLK bits (all npcflag2 high-32 bits + WILD_BATTLE_PET/TRANSMOG/… 0x08000000+).
--    WotLK npcflag domain = 0x07FFFFFF (GOSSIP..MAILBOX). Affects entries 7554,28708,29139,29141,29142,29143,29145.
UPDATE `creature_template` SET `npcflag` = `npcflag` & 0x07FFFFFF
  WHERE (`npcflag` >> 32) <> 0 OR (`npcflag` & 0xFFFFFFFF) >= 0x08000000;

-- 6) type: 29 rows carry client type 15 (absent from CreatureType 1-13); world_335 truth = 10 ("Not specified").
UPDATE `creature_template` SET `type` = 10 WHERE `type` > 13;
```

Rows touched: unit_flags 9114, unit_flags2 2244, unit_flags3 599, flags_extra 403, npcflag 7,
type 29 — **10673 distinct rows**.

## Post-fix confirmation (applied to world_c and re-queried)

Every violation class returns 0 after the block:

```
uf=0  uf2=0  uf3=0  flags_extra=0  type(not 0-13)=0  npcflag_post=0
unit_class=0  dmgschool=0  movementtype=0  reqexp>=10 =0  classification(not 0-6)=0
```

faction / family / VehicleId remain 0-invalid vs the 3.4.3 client (untouched by this block).
**Every audited column is now within its core-allowed domain and WotLK-consistent.**

## Flags (could not fully certify / out of this block's scope)

1. **ScriptName — 5 names have no compiled script in the `wotlk_classic` branch**
   (`grep src/server/scripts`): `npc_engineer_helice`, `npc_hearthglen_crusader`,
   `npc_pet_pri_shadowfiend_mindbender`, `npc_selina_dourman`, `npc_zm_field_scout`.
   All five are **WotLK-era** creature scripts (Borean Tundra / Hearthglen / shadowfiend /
   Ratchet / Zangarmarsh), not post-WotLK content. An unregistered ScriptName resolves to 0 with
   a startup "assigned in DB but has no code" warning — not a crash, not post-WotLK data. This is
   a **core script-porting gap**, not a DB dead value; deliberately NOT blanked (blanking would
   lose the binding once the script is ported). Left for the core side to port.

2. **Schema mismatch — immunity columns.** world_c still has the legacy `mechanic_immune_mask` +
   `spell_school_immune_mask` columns, but the `wotlk_classic` core reads `CreatureImmunitiesId`
   (`WorldDatabase.cpp` WORLD_SEL_CREATURE_TEMPLATE, field 43). Their **values are WotLK-valid**
   (mechanic mask ≤ bit30 / ENRAGED; school mask ≤ 0x7F), but the core will not load them until
   the table is migrated to the `CreatureImmunitiesId` representation. Data-clean; schema-migration
   item outside this audit.

3. **PetSpellDataId / movementId** are passed through to the client, not validated by the core, so
   they cannot hold a "dead" value by core rules. Both hold WotLK-era values; the client tables
   (`CreatureSpellData`, `CreatureMovementInfo`) were not in the refcache to FK-verify, but
   movementId is unchanged from raw TDB343 (client-matched by construction) and PetSpellDataId
   differences vs 335 are all within WotLK-era entries/IDs. Low risk; not certified against those
   two client DB2s.
