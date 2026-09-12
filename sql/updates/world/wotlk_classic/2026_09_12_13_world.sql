-- battlemaster_entry: WotLK battlemasters only (drop Cata Twin Peaks/Gilneas, fix Random-BG mapping, re-add 5).
-- Verified: applied to raw TDB343 this reproduces the intended WotLK set (see docs/research/battlemaster_entry-wotlk.md).
-- Reassign WotLK Random Battleground masters from AV(1) to Random(32)
UPDATE `battlemaster_entry` SET `bg_template`=32
 WHERE `entry` IN (34986,34988,34989,34991,34997,34998,34999,35000,35001,35002,35007) AND `bg_template`=1;
-- Drop Cataclysm battlegrounds Twin Peaks(108) and Battle for Gilneas(120) (dead rows, creatures absent)
DELETE FROM `battlemaster_entry` WHERE `bg_template` IN (108,120);
-- Re-add Random Battleground masters missing from 343
INSERT INTO `battlemaster_entry` (`entry`,`bg_template`) VALUES
 (34895,32),(34971,32),(34972,32),(34976,32),(34993,32);
-- Result: 172 - 20 (delete) + 5 (insert) = 157 rows = world_335 set
