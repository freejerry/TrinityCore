-- player_factionchange_spells: Drop 3 Cataclysm faction-change spell pairs and add 1 WotLK pair.
-- Verified: applied to raw TDB343 this reproduces the 3.3.5a (world_335) set exactly.
DELETE FROM `player_factionchange_spells` WHERE (`alliance_id`,`horde_id`) IN ((92231,92232),(95786,95909),(107516,107517));
INSERT INTO `player_factionchange_spells` (`alliance_id`,`horde_id`) VALUES (31801,53736);
