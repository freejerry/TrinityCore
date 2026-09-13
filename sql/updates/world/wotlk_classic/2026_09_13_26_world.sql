-- creature_template_difficulty: zero LootIDs whose entire loot group was removed as client-absent
-- items by 2026_09_13_23 (55 groups, all items absent from the 3.4.3 client -> group empty -> the
-- creature drops nothing from it). Clears the ~325 'creature_loot_template Entry does not exist' warnings.
UPDATE `creature_template_difficulty` SET `LootID`=0 WHERE `LootID` IN (62,1260,18728,18733,31722,33118,33186,33515,33994,34496,34497,34564,34780,34797,35347,35349,35351,35360,36476,36502,36597,36612,36626,36627,36658,36678,36855,37025,37126,37214,37627,37917,37955,37970,37984,38006,38016,38023,38030,38032,38064,38112,38113,38462,38599,38603,39863,39864,39944,39945,100000,100001,100002,100003,100005);
