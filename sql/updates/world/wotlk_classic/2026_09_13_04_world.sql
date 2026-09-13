-- guild_rewards_req_achievements: empty on a WotLK 3.3.5a-content server (Cataclysm guild-reward achievement gating; absent in WotLK).
-- Raw TDB343 ships post-WotLK rows; remove them so the table is empty.
DELETE FROM `guild_rewards_req_achievements`;
