-- pickpocketing_loot_template: TDB343 (0 gap vs difficulty refs), drop client-absent-item rows.
DELETE FROM `pickpocketing_loot_template` WHERE `Item` IN (1,2,58262,63299,63300,63314,63337,63343,63349);
