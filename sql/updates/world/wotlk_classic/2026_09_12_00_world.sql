-- player_factionchange_reputations: remove post-WotLK faction-change pairs.
-- Raw TDB343 ships 30 rows; the 14 rows with alliance_id >= 1134 are Cataclysm
-- (Gilneas/Bilgewater/Wildhammer/Dragonmaw/Baradin/Hellscream), MoP and WoD
-- factions that do not exist in WotLK 3.3.5a. Keep only the 16 WotLK pairs.
DELETE FROM `player_factionchange_reputations` WHERE `alliance_id` >= 1134;
