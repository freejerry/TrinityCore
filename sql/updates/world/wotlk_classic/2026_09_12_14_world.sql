-- vehicle_template_accessory: Drop 229 post-WotLK accessory rows, restore 4 WotLK rows.
-- Verified: applied to raw TDB343 this reproduces the intended WotLK set (see docs/research/vehicle_template_accessory-wotlk.md).
-- Remove the 229 post-WotLK accessory rows 343 added (keys not present in the WotLK reference),
-- then re-add the 4 WotLK rows 343 dropped. Result == world_335's 202-row set.
DELETE `d` FROM `vehicle_template_accessory` `d`
LEFT JOIN `world_335`.`vehicle_template_accessory` `s`
  ON `d`.`entry` = `s`.`entry` AND `d`.`seat_id` = `s`.`seat_id`
WHERE `s`.`entry` IS NULL;

INSERT INTO `vehicle_template_accessory`
  (`entry`,`accessory_entry`,`seat_id`,`minion`,`description`,`summontype`,`summontimer`)
VALUES
  (36794,36658,0,1,'Scourgelord Tyrannus on Scourgelord Tyrannus',6,300),
  (39759,39755,0,1,'Tankbuster Cannon - Irradiated Infantry',7,0),
  (39819,39755,0,1,'Irradiated Mechano-Tank - Irradiated Infantry',7,0),
  (39860,39264,0,1,'Gnomeregan Mechano-Tank - Gnomeregan Mechano-Tank Pilot',7,0);
