-- creature_template: eliminate remaining dead/post-WotLK values (flag bits + type) so every
-- column sits inside its core-allowed domain (ObjectMgr::CheckCreatureTemplate) and matches WotLK.
-- Per-column audit + masks: docs/research/creature_template-column-audit.md. Runs after 2026_09_13_16.

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
