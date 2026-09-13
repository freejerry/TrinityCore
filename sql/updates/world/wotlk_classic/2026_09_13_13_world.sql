-- battleground_template: 13 WotLK BGs/arenas fitted to the 7-column 3.4 schema (player-count/level/orientation now from client BattlemasterList.dbc).
-- See docs/research/battleground_template-wotlk.md.
DELETE FROM `battleground_template`;
INSERT INTO `battleground_template` (`ID`,`AllianceStartLoc`,`HordeStartLoc`,`StartMaxDist`,`Weight`,`ScriptName`,`Comment`) VALUES
(1,611,610,100,1,'','Alterac Valley'),
(2,769,770,75,1,'','Warsong Gulch'),
(3,890,889,75,1,'','Arathi Basin'),
(4,929,936,0,1,'','Nagrand Arena'),
(5,939,940,0,1,'','Blades''s Edge Arena'),
(6,0,0,0,1,'','All Arena'),
(7,1103,1104,75,1,'','Eye of The Storm'),
(8,1258,1259,0,1,'','Ruins of Lordaeron'),
(9,1367,1368,0,1,'','Strand of the Ancients'),
(10,1362,1363,0,1,'','Dalaran Sewers'),
(11,1364,1365,0,1,'','The Ring of Valor'),
(30,1485,1486,200,1,'','Isle of Conquest'),
(32,0,0,0,1,'','Random battleground');
