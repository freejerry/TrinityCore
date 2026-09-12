-- player_factionchange_achievement: Restore 22 WotLK faction-change achievement pairs dropped by TDB343.
-- Verified: applied to raw TDB343 this reproduces the 3.3.5a (world_335) set exactly.
-- Re-add the 22 authentic WotLK faction-change achievement pairs that TDB343 (world_d) lost to retail-era master maintenance. Result = the full 3.3.5a (world_335) 125-row set.
INSERT INTO `player_factionchange_achievement` (`alliance_id`, `horde_id`) VALUES
(41, 1360),
(58, 593),
(970, 971),
(1167, 1168),
(1169, 1170),
(1172, 1173),
(1262, 1274),
(1466, 926),
(1563, 1784),
(1656, 1657),
(1676, 1677),
(1678, 1680),
(1681, 1682),
(1684, 1683),
(1692, 1691),
(1707, 1693),
(1752, 2776),
(2144, 2145),
(2194, 2195),
(2797, 2798),
(3478, 3656),
(4784, 4785);
