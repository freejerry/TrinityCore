-- creature child tables: drop orphan rows referencing post-WotLK creatures that no longer
-- exist in creature_template after the WotLK trim (2026_09_13_16). Self-contained: the
-- subqueries reference creature_template in the same world DB (which by this point holds only
-- the WotLK creature set). The core skips such orphan rows at load anyway; this removes the
-- post-WotLK vendor/spellclick/onkill/equip data outright. Verified against world_c.
DELETE FROM `npc_vendor`                 WHERE `entry`       NOT IN (SELECT `entry` FROM `creature_template`);
DELETE FROM `npc_spellclick_spells`      WHERE `npc_entry`   NOT IN (SELECT `entry` FROM `creature_template`);
DELETE FROM `creature_onkill_reputation` WHERE `creature_id` NOT IN (SELECT `entry` FROM `creature_template`);
DELETE FROM `creature_equip_template`    WHERE `CreatureID`  NOT IN (SELECT `entry` FROM `creature_template`);
