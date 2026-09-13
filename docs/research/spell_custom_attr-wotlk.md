# spell_custom_attr: WotLK-correct data (TDB343 vs 3.3.5a vs 3.4.3 client)

**Verdict:** TDB335 (confidence: high). Final update: sql/updates/world/wotlk_classic/2026_09_13_*_world.sql (self-contained literal), verified to reproduce world_c on raw TDB343 and to load with 0 DBErrors on the 3.4.3 client.

- **Rows:** world_d (raw TDB343) = 137, world_335 = 276
- **Difference pattern:** partial_overlap
- **Structure:** Schema byte-identical in world_d (TDB343) and world_335: (entry INT UNSIGNED PK 'spell id', attributes INT UNSIGNED 'SpellCustomAttributes'), InnoDB/utf8mb4. `attributes` is a bitmask into enum SpellCustomAttributes. Verified the 3.3.5 branch enum (github TrinityCore/3.3.5 SpellInfo.h) vs the wotlk_classic core enum (src/server/game/Spells/SpellInfo.h:143-170): every bit used by the DB (0x2 CONE_BACK, 0x8 SHARE_DAMAGE, 0x40 DONT_BREAK_STEALTH, 0x8000 IGNORE_ARMOR, 0x10000 REQ_TARGET_FACING_CASTER, 0x20000 REQ_CASTER_BEHIND_TARGET, 0x40000 ALLOW_INFLIGHT, 0x1000000 AURA_CANNOT_BE_SAVED) has identical value in both, so numeric values are portable. Only difference: 3.3.5 live bits 0x800 ROLLING_PERIODIC / 0x1000-0x4000 NEGATIVE_EFF0-2 are marked DEPRECATED/DO NOT REUSE in the modern enum (auto-computed now), and modern adds 0x2000000 (not used by any DB row).

## Difference

128 rows byte-identical (same entry+attributes; zero value-diffs on shared entries). 148 rows are 335-only; 9 rows are 343-only. 335-only rows by value: 131072/BEHIND x51 (Backstab 53/2589/2590/2591/8721/25300/26839/48656/48657, Garrote 703, Ambush ranks, boss versions), 64/DONT_BREAK_STEALTH x29 (rogue/druid stealth abilities incl. Shred 5221 line, Sap), 32768/IGNORE_ARMOR x16, 2048/ROLLING_PERIODIC x15 (deprecated bit), 4/CONE_LINE x10 (auto-computed now), 16/NO_INITIAL_THREAT x7 (auto-computed now), 65536/FACING x6, 8/SHARE_DAMAGE x5, 16777216 x3, 2/CONE_BACK x1, plus 8192/12288/28672 NEGATIVE_EFF combos x5 (deprecated bits). 343-only 9 rows: 1066/33943/40120/48517/48518/165961=16777216, 184689/244761=8, 244410=4096.

## Correct WotLK dataset

The authentic 3.3.5a TrinityCore spell_custom_attr set (world_335, 276 rows). It restores the ~148 WotLK rows TDB343 dropped — most importantly the player positional/stealth requirements (REQ_CASTER_BEHIND_TARGET for Backstab/Ambush/boss abilities, DONT_BREAK_STEALTH for stealth openers, REQ_TARGET_FACING_CASTER) which the wotlk_classic core enforces ONLY through these CU-attr rows (no auto-compute, no client-attribute fallback), so their absence silently breaks WotLK combat mechanics. All 148 335-only rows reference WotLK-range spells (ids <= 74117) present in the 3.4.3 WotLK-Classic client (e.g. 48657 Backstab confirmed live on wowhead WotLK Classic). The 9 343-only rows are dropped: they are either post-WotLK spells (Legion/WoD ids) or modern-refinement/auto-computed AURA_CANNOT_BE_SAVED rows that authentic WotLK TDB335 does not carry.

## Dead values / contamination

Post-WotLK contamination in TDB343 (world_d), removed by the delta: entry 244761 = "Annihilation" (Antorus the Burning Throne, Legion 7.3) confirmed via wowhead; 244410 (same 244xxx Legion/BfA id range, attr 4096); 165961 (WoD/Legion ~160k-190k range); 184689 (Legion range) — none of these spells exist in WotLK 3.3.5a. Also dropped: 1066 (Aquatic Form), 33943 (Flight Form), 40120 (Swift Flight Form), 48517/48518 (Eclipse) all carrying 16777216/AURA_CANNOT_BE_SAVED — WotLK-valid spell ids but modern refinements TDB335 omits (and AURA_CANNOT_BE_SAVED is auto-computed for possess/charm cases anyway). Separately, ~20 of the re-added 335 rows use bits deprecated in the modern engine (2048 ROLLING_PERIODIC; 8192/12288/28672 NEGATIVE_EFF combos) which the wotlk_classic core no longer reads (marked DO NOT REUSE) and now auto-computes — they are inert but harmless and kept for TDB335 fidelity.

## Evidence

- **Schema is byte-identical between world_d (TDB343) and world_335; both are (entry INT UNSIGNED PK, attributes INT UNSIGNED) InnoDB utf8mb4.**  
  — docker exec tdb343-db-1 mariadb SHOW CREATE TABLE spell_custom_attr on world_d and world_335 (identical output)
- **world_d has 137 rows, world_335 has 276; 128 identical, 148 are 335-only, 9 are 343-only; zero value-diffs on the 128 shared entries.**  
  — COUNT(*) + (SELECT * EXCEPT ...) both directions + JOIN ON entry WHERE attributes<>attributes (empty result)
- **The behind/facing requirement and stealth-preserve are enforced SOLELY through the CU attribute bits, with no auto-compute and no client-attribute fallback.**  
  — src/server/game/Spells/Spell.cpp:5959 (REQ_CASTER_BEHIND_TARGET) and :5963 (REQ_TARGET_FACING_CASTER); src/server/game/Entities/Unit/Unit.cpp:2625 (behind => no parry); src/server/game/Spells/Auras/SpellAuras.cpp:1859 (DONT_BREAK_STEALTH)
- **The loader ORs the DB `attributes` value directly into SpellInfo::AttributesCu; no bit remapping is applied, so numeric values must match the running enum.**  
  — src/server/game/Spells/SpellMgr.cpp:3092-3124 (SELECT entry, attributes ... AttributesCu |= attributes)
- **None of the DB-only bits (CONE_BACK 0x2, SHARE_DAMAGE 0x8, DONT_BREAK_STEALTH 0x40, REQ_TARGET_FACING 0x10000, REQ_CASTER_BEHIND 0x20000, ALLOW_INFLIGHT 0x40000) are auto-set by the core; only IGNORE_ARMOR(bleed), AURA_CC, AURA_CANNOT_BE_SAVED, CAN_CRIT, DIRECT_DAMAGE, NO_INITIAL_THREAT, CHARGE, PICKPOCKET, ENCHANT_PROC, BINARY, SCHOOLMASK_NORMAL_WITH_MAGIC, IS_TALENT, CONE_LINE, NEEDS_AMMO are.**  
  — grep 'AttributesCu |=' src/server/game/Spells/SpellMgr.cpp:3145-3464 (full list of auto-set bits)
- **The wotlk_classic core enum and the 3.3.5 TrinityCore branch enum have identical bit values for every DB-used bit; 3.3.5's live ROLLING_PERIODIC(0x800)/NEGATIVE_EFF0-2(0x1000-0x4000) are the DEPRECATED/DO NOT REUSE bits in the modern enum.**  
  — src/server/game/Spells/SpellInfo.h:143-170 vs github raw TrinityCore/TrinityCore@3.3.5 src/server/game/Spells/SpellInfo.h enum SpellCustomAttributes
- **48657 (a 335-only 131072/behind row dropped by TDB343) is WotLK Rogue Backstab, present in the 3.4.3 WotLK-Classic client.**  
  — wowhead.com/wotlk/spell=48657 (title 'Backstab - Spell - WotLK Classic')
- **244761 (a TDB343-only row) is 'Annihilation' from Antorus the Burning Throne, a Legion (7.3) raid spell that does not exist in WotLK.**  
  — wowhead.com/spell=244761 (Annihilation, Garothi Worldbreaker / Antorus)
- **All 148 335-only rows reference WotLK-range spell ids (max 74117, ICC/Ruby-Sanctum era); the 343-only rows include Legion/WoD id ranges (244761,244410,184689,165961).**  
  — world_335 EXCEPT world_d row dump (ids 53..74117) and world_d EXCEPT world_335 dump (9 rows)

## Verification notes (pre-DBErrors)

All 148 re-added rows reference WotLK-range spell ids expected in the 3.4.3 WotLK-Classic client, so I expect no load rejections, but the orchestrator should confirm against DBErrors.log: any 335 row whose spell id the 3.4.3 client cannot resolve will be logged ("Table `spell_custom_attr` has wrong spell") and skipped. Rows to watch specifically: (a) the deprecated-bit rows 12654,12721,27813,27817,27818,50536,54203,61840,63468,64891,64930,70772,70809,71023,71824 (2048 ROLLING_PERIODIC), 38065,53468 (8192), 51121,59376 (12288), 24690 (28672) — these bits are DO-NOT-REUSE/no-op in the modern engine (functionality auto-computed), so they are inert-but-harmless; keeping them preserves TDB335 fidelity but the orchestrator may prefer to strip them. (b) I chose to DROP 4 WotLK-valid 343-only rows (1066 Aquatic Form, 33943 Flight Form, 40120 Swift Flight Form, 48517/48518 Eclipse) that carry AURA_CANNOT_BE_SAVED because authentic TDB335 omits them; if the orchestrator wants to retain these modern refinements they can be preserved by not deleting those specific entries.

---
_C-layer research workflow (deferred batch), run wf_e38612bd-12c._


## Update — 3.4.3 DBErrors.log validation

Reloaded world_c: 28 rows referenced spells absent from the 3.4.3 client ("has wrong spell"), plus 2 SHARE_DAMAGE rows (66765/66809) whose attribute the core ignores (no SCHOOL_DAMAGE effect); all dropped. Final **246 rows**, loads with 0 DBErrors.
