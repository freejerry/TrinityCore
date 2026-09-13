# guild_rewards: WotLK-correctness (TDB343-only table)

**Verdict:** Empty (confidence: high). This table exists in TDB343 but not in 3.3.5a. Update under sql/updates/world/wotlk_classic/2026_09_13_*_world.sql.

- **Rows in raw TDB343:** 62
- **Is a WotLK feature?** no
- **Purpose:** Defines items purchasable from a guild reward vendor, gated by guild reputation standing (MinGuildRep), race mask, gold cost, and (via guild_rewards_req_achievements) required guild achievements. Loaded by GuildMgr::LoadGuildRewards into the GuildReward store. Loader: src/server/game/Guilds/GuildMgr.cpp:494-499 (query at :499); prepared stmt for required achievements at src/server/database/Database/Implementation/WorldDatabase.cpp:80.

## Correct state for C

The guild-reward vendor feature (guild reputation + purchasable guild rewards) is a Cataclysm Guild Advancement feature and does not exist in WotLK 3.3.5a content. The correct state for a 3.3.5a-content server is an empty guild_rewards table; the core handles this gracefully by logging ">> Loaded 0 guild reward definitions. DB table `guild_rewards` is empty." (GuildMgr.cpp:503).

## Dead values / contamination

All 62 rows are post-WotLK (Cataclysm). The feature itself (guild reputation standings consumed by MinGuildRep, guild reward vendors) was introduced in Cataclysm patch 4.0.1 (2010-10-12), after WotLK. Item IDs (61931, 62023, 63125, ... 85508) are Cataclysm-era guild vendor items not present in 3.3.5a content.

## Evidence

- **guild_rewards is loaded by GuildMgr::LoadGuildRewards via 'SELECT ItemID, MinGuildRep, RaceMask, Cost FROM guild_rewards' and populates guild-vendor reward definitions; an empty table is valid (logs 'Loaded 0 guild reward definitions').**  
  — src/server/game/Guilds/GuildMgr.cpp:494-503
- **Required-achievement sub-table query confirms the guild-reward vendor feature (achievement/reputation gated purchasable items).**  
  — src/server/database/Database/Implementation/WorldDatabase.cpp:80
- **Guild reputation and guild rewards (purchased from guild vendors after gaining guild reputation/achievements) were added in Cataclysm patch 4.0.1 (2010-10-12) as part of Guild Advancement; the feature does not exist in WotLK.**  
  — https://warcraft.wiki.gg/wiki/Guild_reputation
- **Cataclysm added guild levels, perks, achievements, reputation, and rewards vendors in capital cities; guild rewards include guild cloaks, heirlooms, pets, guild mounts, bank tabs.**  
  — https://www.wowhead.com/guide/guild-guide-reputation-rewards-and-more-1070
- **world_d.guild_rewards has 62 rows, all Cataclysm item IDs (min 61931, e.g. 85508); MinGuildRep encodes guild reputation standing which is a Cataclysm mechanic.**  
  — docker exec tdb343-db-1 mariadb world_d -e 'SELECT * FROM guild_rewards' (62 rows)

---
_343-only research workflow, run wf_18cbaa1a-47d. Trims validated via world_c reload + DBErrors.log._
