-- WotLK Classic zhTW rebuild: `playercreateinfo_cast_spell`
-- Source: TDB335 (+createMode=0)
DELETE FROM `playercreateinfo_cast_spell`;
/*M!999999\- enable the sandbox mode */ 
SET @OLD_AUTOCOMMIT=@@AUTOCOMMIT, @@AUTOCOMMIT=0;
INSERT INTO `playercreateinfo_cast_spell` VALUES
(0,1,0,2457,'Warrior - Battle Stance'),
(0,32,0,48266,'Death Knight - Blood Presence');
COMMIT;
SET AUTOCOMMIT=@OLD_AUTOCOMMIT;
