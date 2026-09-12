-- skill_tiers: mirror the WotLK 3.3.5a client SkillTiers.dbc exactly.
-- Raw TDB343 ships 58 rows; 32 of them are Cataclysm+ profession/secondary tiers
-- that do not exist in 3.3.5a, and 8 WotLK tiers carry post-WotLK skill steps
-- (525-1000 for professions, Master Riding 375 for tier 223). None are reachable
-- by WotLK content (the step is content-spell-driven, capped at 6/4), but drop them
-- so the table literally matches the 3.3.5a SkillTiers.dbc. All 11 SkillTierIDs the
-- 3.4.3 client's SkillRaceClassInfo.db2 references are among the 26 WotLK tiers kept.
DELETE FROM `skill_tiers` WHERE `ID` NOT IN
  (2,21,22,23,24,41,61,62,63,81,121,122,123,124,125,126,127,141,142,143,161,181,182,221,222,223);
UPDATE `skill_tiers` SET `Value7`=0,`Value8`=0,`Value9`=0,`Value10`=0,`Value11`=0,`Value12`=0
  WHERE `ID` IN (2,23,41,61,62,63,161);
UPDATE `skill_tiers` SET `Value5`=0 WHERE `ID`=223;
