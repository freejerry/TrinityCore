-- WotLK Classic: restore Eastern Plaguelands world PvP row (authentic WotLK, active
-- through 3.3.5a; removed only in Cataclysm 4.0.3a). TDB343 dropped it. NOTE: the
-- wotlk_classic CORE still lacks the OutdoorPvPEP script, so this row is inert until
-- that script is ported/rewritten — the DB row itself is the correct WotLK data.
DELETE FROM `outdoorpvp_template` WHERE `TypeId`=6;
INSERT INTO `outdoorpvp_template` (`TypeId`,`ScriptName`,`comment`) VALUES (6,'outdoorpvp_ep','Eastern Plaguelands');
