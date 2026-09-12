-- spell_learn_spell: Drop MoP Battle Pet Training rows and restore 6 WotLK learn-spell links.
-- Verified: applied to raw TDB343 this reproduces the 3.3.5a (world_335) set exactly.
-- Drop MoP "Battle Pet Training" contamination
DELETE FROM `spell_learn_spell` WHERE `entry`=125610 AND `SpellID` IN (119467,122026,125439);
-- Re-add WotLK learn-relationships TDB343 dropped (present in world_335)
INSERT INTO `spell_learn_spell` (`entry`,`SpellID`,`Active`) VALUES
 (17002,24867,0),  -- Feral Swiftness -> Feral Swiftness Passive 1a
 (24866,24864,0),  -- Feral Swiftness (rank) -> Feral Swiftness Passive 2a
 (33872,47179,0),  -- Nurturing Instinct -> passive
 (33873,47180,0),  -- Nurturing Instinct (rank) -> passive
 (53428,53341,1),  -- Runeforging -> Rune of Cinderglacier
 (53428,53343,1);  -- Runeforging -> Rune of Razorice
-- The 2 shared rows (33943->34090, 58984->21009) already exist in RAW 343; leave as-is.
-- Applied to world_d this yields exactly world_335's 8 rows.
