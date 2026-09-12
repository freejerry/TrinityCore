-- spell_group: Restore WotLK spell_group (raw 343 group 1124 held Dragonflight spells; 236 WotLK rows re-added).
-- Verified: applied to raw TDB343 this reproduces the intended WotLK set (see docs/research/spell_group-wotlk.md).
-- Remove post-WotLK (Dragonflight) contamination injected into group 1124
DELETE FROM `spell_group` WHERE `id`=1124 AND `spell_id` IN (389501,389512,389516,389521,389536);
-- Re-add the WotLK spell_group rows that TDB343 dropped (yields the full 3.3.5a set = 518 rows)
INSERT INTO `spell_group` (`id`,`spell_id`)
SELECT s.`id`, s.`spell_id` FROM `world_335`.`spell_group` s
WHERE NOT EXISTS (SELECT 1 FROM `spell_group` d WHERE d.`id`=s.`id` AND d.`spell_id`=s.`spell_id`);
-- NOTE: also fix companion table spell_group_stack_rules (out of scope of this table): 343 group 1124 stack_rule=1 must become 3, and 335's ~67 group rules re-added.
