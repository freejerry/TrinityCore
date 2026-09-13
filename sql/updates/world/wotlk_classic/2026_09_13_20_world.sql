-- creature (spawns): adopt TDB343 verbatim (sniff-verified 3.4.3 WotLK Classic spawn placement)
-- with two minimal fixes for values invalid on the 3.4.3 client:
--   - modelid override 1 (not a valid CreatureDisplayInfo) -> 0 (fall back to template model)
--   - drop the single spawn on map 451 (GM/Dev land, absent from the 3.4.3 client Map.db2)
-- zoneId/areaId are cached position hints (core recomputes at load); left as-is.
UPDATE `creature` SET `modelid`=0 WHERE `modelid`=1;
DELETE FROM `creature` WHERE `map`=451;
