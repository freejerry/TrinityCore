# guild_rewards_req_achievements: WotLK-correctness (TDB343-only table)

**Verdict:** Empty (confidence: high). This table exists in TDB343 but not in 3.3.5a. Update under sql/updates/world/wotlk_classic/2026_09_13_*_world.sql.

- **Rows in raw TDB343:** 54
- **Is a WotLK feature?** no
- **Purpose:** Maps a guild-vendor reward ItemID to the guild AchievementRequired(s) a player must have earned to purchase it. Loaded as a sub-query of GuildMgr::LoadGuildRewards (src/server/game/Guilds/GuildMgr.cpp:494), executed via WORLD_SEL_GUILD_REWARDS_REQ_ACHIEVEMENTS prepared statement (src/server/database/Database/Implementation/WorldDatabase.cpp:80) for each row of the guild_rewards table; each requiredAchievementId is validated against sAchievementStore and pushed into GuildReward.AchievementsRequired (GuildMgr.cpp:529-548).

## Correct state for C

Empty. The guild-reward-vendor system this table feeds (guild reputation, guild achievements, guild rewards purchasable from a guild vendor) is a Cataclysm 4.0.1 feature that does not exist in WotLK 3.3.5a. A 3.3.5a-content server has no guild reputation/rewards/guild-achievement system, so both guild_rewards and guild_rewards_req_achievements must remain empty.

## Dead values / contamination

All 54 rows are post-WotLK. Item IDs are Cataclysm+ guild-reward items (62023-71033 = Cataclysm; 85508-89195 = Mists of Pandaria; 114968/116666/120352 = Warlords of Draenor) and the AchievementRequired values are guild achievements (e.g. 6626, 9651, 9669, 9388) which are themselves a Cataclysm+ feature absent from the WotLK client. The entire table is dead for 3.3.5a content.

## Evidence

- **Table has 54 rows; PK (ItemID, AchievementRequired); item IDs range 62023-120352 and achievement IDs are guild achievements like 6626/9651/9669/9388**  
  — docker exec tdb343-db-1 mariadb world_d -e SELECT * FROM guild_rewards_req_achievements (dump above)
- **Table backs the guild-reward vendor: read per guild_rewards row and required achievement validated against sAchievementStore, feeding GuildReward.AchievementsRequired**  
  — src/server/game/Guilds/GuildMgr.cpp:494-556
- **Prepared statement selects AchievementRequired FROM guild_rewards_req_achievements WHERE ItemID = ?**  
  — src/server/database/Database/Implementation/WorldDatabase.cpp:80
- **Guild reputation, guild achievements, guild levels/perks and guild rewards (vendor items requiring guild reputation + guild achievements) were introduced in Cataclysm patch 4.0.1 (2010-10-12); they do not exist in WotLK 3.3.5a**  
  — https://wowpedia.fandom.com/wiki/Guild_rewards and https://warcraft.wiki.gg/wiki/Guild_reputation

---
_343-only research workflow, run wf_18cbaa1a-47d. Trims validated via world_c reload + DBErrors.log._
