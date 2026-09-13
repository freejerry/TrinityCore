-- creature_template cluster: WotLK corrections to TDB343 (verified via wago 3.4.3.54261
-- client refcache + world_335 + AzerothCore; see docs/research/creature_template-wotlk.md
-- and docs/research/creature-clientfk-gaps.md). Self-contained delta vs raw TDB343.

-- 1) Drop 95 post-WotLK re-release rows (entry>43282; none spawned/referenced) + split children + orphan difficulty row.
DELETE FROM `creature_template_gossip`     WHERE `CreatureID` > 43282;
DELETE FROM `creature_template_model`      WHERE `CreatureID` > 43282;
DELETE FROM `creature_template_difficulty` WHERE `Entry`      > 43282;
DELETE FROM `creature_template_movement`   WHERE `CreatureId`  > 43282;
DELETE FROM `creature_template`            WHERE `entry`       > 43282;

-- 2) Faction: reset post-Cata faction templates (absent from 3.4.3 client; core would fall back
--    to 35=friendly-to-all, turning hostile mobs neutral) to the correct WotLK templates.
UPDATE `creature_template` SET `faction`=14   WHERE `entry` IN (428,2070,2071,2237);
UPDATE `creature_template` SET `faction`=16   WHERE `entry` IN (7431,7432,11858,11910,11911,11912,11913);
UPDATE `creature_template` SET `faction`=22   WHERE `entry` IN (2349);
UPDATE `creature_template` SET `faction`=24   WHERE `entry` IN (206,920);
UPDATE `creature_template` SET `faction`=35   WHERE `entry` IN (3000,7013,9117,9270,9271,9997,10977,12959,15774,23211,32870,35085,35086,35088,35091);
UPDATE `creature_template` SET `faction`=44   WHERE `entry` IN (2165);
UPDATE `creature_template` SET `faction`=48   WHERE `entry` IN (1016,1019,6505,6506);
UPDATE `creature_template` SET `faction`=62   WHERE `entry` IN (1034,1035,1036,1038,1057);
UPDATE `creature_template` SET `faction`=69   WHERE `entry` IN (3442);
UPDATE `creature_template` SET `faction`=71   WHERE `entry` IN (14364);
UPDATE `creature_template` SET `faction`=74   WHERE `entry` IN (6190,6195);
UPDATE `creature_template` SET `faction`=126  WHERE `entry` IN (3188);
UPDATE `creature_template` SET `faction`=132  WHERE `entry` IN (4646,4647,4648,4649,4651,4652,4653,4661);
UPDATE `creature_template` SET `faction`=133  WHERE `entry` IN (4638,4639,4640,4641,4642,4643,4644,4645);
UPDATE `creature_template` SET `faction`=474  WHERE `entry` IN (10302,10583);
UPDATE `creature_template` SET `faction`=475  WHERE `entry` IN (9460);
UPDATE `creature_template` SET `faction`=814  WHERE `entry` IN (11194);
UPDATE `creature_template` SET `faction`=994  WHERE `entry` IN (15187,15188);
UPDATE `creature_template` SET `faction`=1194 WHERE `entry` IN (16134);
UPDATE `creature_template` SET `faction`=1354 WHERE `entry` IN (14355,14358,14361,16032);
UPDATE `creature_template` SET `faction`=1355 WHERE `entry` IN (14368,14369,14371,14381,14382,14383);
UPDATE `creature_template` SET `faction`=1475 WHERE `entry` IN (14622);
UPDATE `creature_template` SET `faction`=1625 WHERE `entry` IN (16378);
UPDATE `creature_template` SET `faction`=1663 WHERE `entry` IN (16909,16926);
UPDATE `creature_template` SET `faction`=2073 WHERE `entry` IN (28247);

-- 3) Family: post-WotLK beast families on non-pet WotLK creatures -> 0 (WotLK value).
UPDATE `creature_template` SET `family`=0 WHERE `entry`<=43282 AND `family` IN (52,53,68,126,160);

-- 4) VehicleId: Cata made these WotLK creatures vehicle-riders; reset to WotLK 0.
UPDATE `creature_template` SET `VehicleId`=0
  WHERE `entry` IN (5856,1538,1539,1540,1660,1665,1061,6370,309,5840,4421);

-- 5) Model: fix the 5 creatures left with NO valid display (must run before the trim below).
UPDATE `creature_template_model` SET `CreatureDisplayID`=11686 WHERE `CreatureID`=20189 AND `CreatureDisplayID`=39552;
UPDATE `creature_template_model` SET `CreatureDisplayID`=780   WHERE `CreatureID`=20528 AND `CreatureDisplayID`=30210;
UPDATE `creature_template_model` SET `CreatureDisplayID`=29488 WHERE `CreatureID`=35410 AND `CreatureDisplayID`=37369;
UPDATE `creature_template_model` SET `CreatureDisplayID`=19410 WHERE `CreatureID` IN (37525,37526) AND `CreatureDisplayID`=31498;
--    Trim remaining model rows whose display is absent from the 3.4.3 client (creatures keep a valid idx-0).
DELETE `ctm` FROM `creature_template_model` `ctm`
WHERE `ctm`.`CreatureID`<=43282
  AND `ctm`.`CreatureDisplayID` IN (28480,28481,28490,28491,29316,30210,31232,31498,32135,32211,
      32212,32213,33397,34004,34005,37290,37291,37292,37369,37373,37374,38373,38418,38419,39552,
      43157,45446,45948,46057,59357,59358,59359,62196,62716,65269,65270,77915,85277,85280,85292,
      85293,88847,89419,89420,89421,89800,89801,89802,89803,98676,99389,99391,99452,99453,99826,
      99827,99828,99829,99830,99831,99832,99833,99834,99835,99836,99837,99838,99949,99950,99951,
      101348,104729,110479);

-- 6) Creature spell: fix Cata id, drop MoP row, drop 2 client-dropped WotLK totem-spell rows.
UPDATE `creature_template_spell` SET `Spell`=49872 WHERE `CreatureID`=27894 AND `Spell`=96212;
DELETE FROM `creature_template_spell` WHERE `CreatureID`=1860 AND `Spell`=112042;
DELETE FROM `creature_template_spell` WHERE (`CreatureID`=19897 AND `Spell`=31982)
                                         OR (`CreatureID`=19899 AND `Spell`=33134);
