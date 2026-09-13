-- skinning_loot_template: TDB343 (0 gap), drop client-absent-item rows.
DELETE FROM `skinning_loot_template` WHERE `Item` IN (1,11800,52976,52977,52982,67495);
