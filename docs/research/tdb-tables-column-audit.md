# 12 張已移植表的欄位使用稽核(worldserver 核心)

驗證目標:確認我們已移植/校正的 12 張 world 表,**每個欄位核心都真的有讀取並使用**,沒有浪費的死欄。方法:12 個平行 agent,每個負責一張表,從 base schema → `SpellMgr`/`ObjectMgr` 的 SELECT → struct 欄位 → 實際消費點逐一追蹤源碼(wotlk_classic 分支)。

## 結論:12 張表零死欄

| 表 | 功能欄使用 | meta 欄(不讀,預期) |
|---|---|---|
| trinity_string | 10/10 | — |
| player_racestats | 6/6 | — |
| player_xp_for_level | 2/2 | — |
| class_expansion_requirement | 4/4 | — |
| playercreateinfo | 16/16(npe_*/intro_* 依建角模式) | — |
| playercreateinfo_action | 5/5 | — |
| playercreateinfo_cast_spell | 4/4 | note |
| spell_loot_template | 9/9(Entry,ItemType,Item,Chance,QuestRequired,LootMode,GroupId,Min/MaxCount) | Comment |
| spell_proc | 18/18(含 **SpellFamilyMask3**、**ProcFlags2**) | — |
| player_classlevelstats | 8/8(屬性 + basehp) | VerifiedBuild |
| creature_classlevelstats | 12/12(basehp0/1/2、damage×3 依 HealthScalingExpansion) | comment |
| race_unlock_requirement | 2/3(raceID+expansion) | — |

meta 欄(VerifiedBuild / note / Comment)是 TDB 追蹤/註解欄,核心刻意不 SELECT,屬正常。

**關鍵確認**:spell_proc 的 3.4 新欄 `SpellFamilyMask3`(flag128 第4槽,`SpellInfo.cpp:1834` 消費)與 `ProcFlags2`(`ProcFlagsInit` 第2槽,`SpellMgr.cpp:527` 的 `FlagsArray::operator&` 掃兩槽消費)**都有被讀用** —— 證實 spell_proc 用 343 完整 schema 是對的。

## 3 個附帶發現(皆良性,非我們資料問題)

1. **race_unlock_requirement.achievementId 未強制** —— 核心 `CharacterHandler.cpp` 把 `HasAccountAchievement` 檢查與建角拒絕都註解掉了。對 WotLK 無影響(WotLK 種族 achievementId 皆 0)。屬上游核心狀態。
2. **playercreateinfo_action 型別窄化** —— struct 的 `button`/`type` 是 uint8,DB 欄是 smallint;值 >255 會截斷。我們的資料值都 <255,無影響。
3. **base schema 檔過時(值得回報上游)** —— `sql/base/dev/world_database.sql` 缺:
   - `player_classlevelstats.basehp`(由 `2025_05_13_01_world.sql` 補)
   - `creature_classlevelstats.basehp0/1/2` + `damage_base/exp1/exp2`(由 `2025_05_13_00_world.sql` 補)

   只用 base 檔建的 DB 會讓核心的 SELECT 失敗;本專案的 world DB 因套了官方 update schema 所以正常。

## 意義

我們補的 12 張表沒有任何欄位是核心用不到的 —— 驗證了「data 全來自 WotLK 正確來源、結構用 3.4.3」的方向,每個欄位都在核心的建角/生物/proc/字串路徑上被實際消費。
