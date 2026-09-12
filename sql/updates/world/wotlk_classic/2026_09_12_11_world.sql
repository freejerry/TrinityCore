-- game_tele: Replace with 3.3.5a set (TDB343 carries MoP/WoD/BfA/SL/DF maps and Cata-revamp coords).
-- Verified: applied to raw TDB343 this reproduces the intended WotLK set (see docs/research/game_tele-wotlk.md).
-- Replace world_d.game_tele entirely with the 3.3.5a (WotLK) set from world_335.
-- game_tele is a self-contained GM `.tele` lookup table (no FKs), so a full replace is the exact, minimal delta.
DELETE FROM `game_tele`;
INSERT INTO `game_tele` (`id`,`position_x`,`position_y`,`position_z`,`orientation`,`map`,`name`)
SELECT `id`,`position_x`,`position_y`,`position_z`,`orientation`,`map`,`name`
FROM `world_335`.`game_tele`;
-- (world_335 here stands for the 3.3.5a reference world DB; in a real build ship these 1493 rows as literal INSERTs.)
