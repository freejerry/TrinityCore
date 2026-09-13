# item_template_addon: WotLK-correctness (TDB343-only table)

**Verdict:** TDB343_verbatim (confidence: high). This table exists in TDB343 but not in 3.3.5a. Update under sql/updates/world/wotlk_classic/2026_09_13_*_world.sql.

- **Rows in raw TDB343:** 625
- **Is a WotLK feature?** yes
- **Purpose:** Holds TrinityCore server-side per-item data that has no client DBC source: FlagsCu (custom flags), FoodType (hunter-pet feeding category), MinMoneyLoot/MaxMoneyLoot (money loot ranges for lootable items), SpellPPMChance (weapon proc-per-minute rate), RandomBonusListTemplateId, QuestLogItemId. Loaded by ObjectMgr::LoadItemTemplateAddon and written back onto each ItemTemplate at src/server/game/Globals/ObjectMgr.cpp:3125-3162 (SELECT at :3130, applied FlagsCu/FoodType/MinMoneyLoot/MaxMoneyLoot/SpellPPMRate/RandomBonusListTemplateId/QuestLogItemId at :3151-3157).

## Correct state for C

Import all 625 rows verbatim. Every field maps to a mechanic that existed in 3.3.5a: hunter-pet food types (FoodType), weapon enchant proc-per-minute (SpellPPMChance, e.g. Crusader/Mongoose enchants), money-loot ranges on lootable items, and custom server flags. In older 3.3.5 TrinityCore these were literal columns on item_template (FoodType, spellppmRate, minMoneyLoot, maxMoneyLoot, flagsCustom); 3.4 moved item_template to be db2-driven and relocated this server-only data into item_template_addon. The 343-only status is purely a schema-layout change, not a feature change. All referenced item IDs (117-50709) are classic/TBC/WotLK items well within the 3.3.5a range; none is Cataclysm+ (Cata items start ~52000+, and there are 0 rows >=54000).

## Dead values / contamination

none — max Id 50709, 0 rows with Id>=54000; all rows reference pre-Cataclysm items. FlagsCu and QuestLogItemId are 0 across all rows; only FoodType, SpellPPMChance and money-loot fields carry data, all WotLK-valid.

## Evidence

- **Core loader ObjectMgr::LoadItemTemplateAddon reads item_template_addon and applies FlagsCu/FoodType/MinMoneyLoot/MaxMoneyLoot/SpellPPMRate/RandomBonusListTemplateId/QuestLogItemId onto ItemTemplate; missing items are only warned+skipped, not fatal.**  
  — src/server/game/Globals/ObjectMgr.cpp:3125-3162 (SELECT :3130, apply :3151-3157)
- **world_d.item_template_addon has 625 rows; columns Id,FlagsCu,FoodType,MinMoneyLoot,MaxMoneyLoot,SpellPPMChance,QuestLogItemId; Id range 117..50709.**  
  — docker exec tdb343-db-1 mariadb world_d SHOW CREATE TABLE + SELECT COUNT/MIN/MAX
- **No post-WotLK contamination: 0 rows with Id>=54000, all FlagsCu=0 and all QuestLogItemId=0; only FoodType/SpellPPMChance/money-loot populated (232 rows have SpellPPMChance>0).**  
  — docker exec tdb343-db-1 mariadb world_d SELECT SUM(Id>=54000),SUM(FlagsCu>0),SUM(QuestLogItemId>0),SUM(SpellPPMChance>0)
- **FoodType (hunter-pet feeding), weapon proc-per-minute (SpellPPMRate) and money-loot fields were columns on item_template in 3.3.5a TrinityCore and are WotLK mechanics; 3.4 relocated them to item_template_addon (analogous to db2 migration split).**  
  — ObjectMgr writes these fields onto the same ItemTemplate struct fields (FoodType/SpellPPMRate/MinMoneyLoot/MaxMoneyLoot) at ObjectMgr.cpp:3151-3157

---
_343-only research workflow, run wf_18cbaa1a-47d. Trims validated via world_c reload + DBErrors.log._
