-- spell_learn_spell: drop MoP Battle Pet Training rows and restore WotLK learn-spell links.
-- The 4 Feral Swiftness / Nurturing Instinct links (17002/24866/33872/33873) are talent
-- spells the 3.4.3 core refuses to teach via this table ("attempts learning talent spell,
-- skipped" in DBErrors.log), so they are omitted; only the 2 Death Knight Runeforging links
-- are added. Applied to raw TDB343 this yields the 4 rows that actually load on the 3.4.3 client.
-- Drop MoP "Battle Pet Training" contamination
DELETE FROM `spell_learn_spell` WHERE `entry`=125610 AND `SpellID` IN (119467,122026,125439);
-- Re-add the WotLK Runeforging learn links TDB343 dropped
INSERT INTO `spell_learn_spell` (`entry`,`SpellID`,`Active`) VALUES
 (53428,53341,1),  -- Runeforging -> Rune of Cinderglacier
 (53428,53343,1);  -- Runeforging -> Rune of Razorice
