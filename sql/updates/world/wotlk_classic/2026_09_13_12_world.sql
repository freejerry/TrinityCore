-- access_requirement: keep TDB343 rows (correct 3.4 difficulty enum + item/quest refs), drop post-WotLK maps + Cata difficulty additions.
-- 44 maps absent from the 3.4.3 client + 5 (map,difficulty) combos the client lacks (Cata heroic SFK/Deadmines, AQ diff3, Cata Zul'Aman). Net 117. Validated via DBErrors.log.
DELETE FROM `access_requirement` WHERE `mapId` IN (643,644,645,657,669,670,671,720,725,754,755,757,859,938,939,940,959,960,961,962,967,994,996,1001,1004,1007,1008,1009,1011,1098,1136,1175,1176,1182,1195,1205,1208,1209,1228,1279,1358,2450,2481,2569);
DELETE FROM `access_requirement` WHERE (`mapId`,`difficulty`) IN ((33,2),(36,2),(509,3),(568,1),(568,2));
