-- spell_group_stack_rules: Replace with WotLK stack rules (raw TDB343 group 1124 held Dragonflight spells).
-- Verified: applied to raw TDB343 this reproduces the 3.3.5a (world_335) set exactly.
-- Restore the WotLK-correct spell_group_stack_rules set (delta vs RAW TDB343 world_d).
-- Requires the sibling `spell_group` to also hold the WotLK group members (handled by that table's task);
-- rules whose group has no `spell_group` members are otherwise skipped by the loader with an sql.sql warning.
DELETE FROM `spell_group_stack_rules`;
INSERT INTO `spell_group_stack_rules` (`group_id`,`stack_rule`) VALUES
(1,1),(2,1),(1001,1),(1002,4),(1003,4),(1004,4),(1005,4),(1006,1),(1007,1),(1008,1),
(1009,1),(1010,2),(1011,2),(1015,3),(1016,4),(1019,3),(1022,4),(1023,4),(1024,4),(1025,3),
(1029,1),(1033,1),(1036,4),(1037,3),(1038,3),(1046,4),(1048,4),(1051,3),(1054,3),(1055,4),
(1056,3),(1058,3),(1059,3),(1060,3),(1061,4),(1062,4),(1083,4),(1084,4),(1085,4),(1086,4),
(1087,4),(1088,4),(1089,4),(1090,4),(1093,4),(1094,3),(1095,4),(1096,4),(1097,1),(1098,4),
(1099,2),(1100,1),(1101,3),(1104,1),(1105,3),(1106,1),(1107,4),(1108,4),(1109,1),(1110,1),
(1111,1),(1112,1),(1121,1),(1122,4),(1123,1),(1124,3),(1125,3);
