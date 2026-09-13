-- guild_rewards: empty on a WotLK 3.3.5a-content server (Cataclysm guild-reward vendor feature (Guild Advancement 4.0.1); absent in WotLK).
-- Raw TDB343 ships post-WotLK rows; remove them so the table is empty.
DELETE FROM `guild_rewards`;
