# TDB343.24081 資料缺陷分析與修正

**日期**：2026-09-05
**環境**：`~/Works/side-project/tdb343-test`，TrinityCore tag `TDB343.24081`（commit `92796557f9b0`），客戶端 3.4.3.54261
**相關筆記**：[[maintained-343-forks]]、[[cata-classic-backend-option]]、[[wotlk-classic-completion-assessment]]

## 結論

TDB343.24081 是**正確的官方 dump**，世界內容確實是 WotLK，但**若干資料表沒有從正式服血統回移乾淨**。
症狀是新角色生在半空墜落、全世界沒有任何 NPC 給任務。三個修正之後任務系統恢復正常。

## 一、排除的假設

| 假設 | 驗證方式 | 結果 |
|---|---|---|
| 抓錯／匯錯 dump | `version` 表：`TDB 343.24081`、revision `92796557f9b0`、2024-08-17 | 檔案正確 |
| 伺服器啟動時被 update 覆蓋 | `updates` 表 7,477 筆全為 2024-08-17；2025 年後套用 **0 筆** | 非更新器所致 |
| 其實是大災變資料包 | 生怪最多為 571 北裂境 35,732、530 外域 30,783；大災變地圖 **0 筆**；137,622 生物 / 88,700 物件 / 8,543 任務（3.3.5 為 151,815 / 94,992 / 9,464） | 世界內容確為 WotLK |
| 角色資料損壞 | `characters` 列乾淨，`at_login=0`、`extra_flags=4`（僅接受密語） | 角色無異常 |
| gossip 資料損壞 | 3,750 個 NPC 有對話（3.3.5 為 3,782）；npc_text 對應 96.0% 正確 | 大致完好 |

缺陷確認存在於**上游原始 SQL 檔本身**：直接從 413 MB 的 dump 撈出 `(658,24471,0)` 與 `(52,13,2570,...)`。

## 二、三個缺陷與修正

### patch 001 — `playercreateinfo` 出生座標

該表原封繼承自正式服，含種族 52（龍希爾）、職業 13（喚能師），出生點在地圖 2570 禁忌之島。
地精與食人妖因此帶著大災變後的座標：

```
地精    3.3.5 (-6240, 331, 383)  →  343 (-4983, 878, 274)   差 ~1400
食人妖  3.3.5 (-618, -4252, 39)  →  343 (-1171, -5264, 1)   差 ~1150
```

佐證：343 的地精出生點 200 碼內僅 **2 隻** NPC、地面 Z≈300（出生 Z=274，在地面下）；
寒脊山谷 200 碼內 **93 隻** NPC、地面 Z≈391。就算不墜落，該處也沒有新手村內容。

修正：race 7 / 8 的非死亡騎士列改回 TDB335 座標（死亡騎士維持黑鋒要塞）。

### patch 002 — 任務關聯表

四張關聯表是大災變改版後的版本，但 `quest_template` 是 WotLK。

```
creature_queststarter    5,142 筆，25.6% 指向不存在的任務
creature_questender     10,015 筆，22.8%
gameobject_queststarter    922 筆，81.0%

8,543 個任務中 4,596 個完全接不到（53.8%）；3.3.5 的基準是 1,802（19.0%）
```

來歷佐證：5,142 筆中只有 522 筆有 `VerifiedBuild`，且那些 build 是 45745 / 45338 / 42979 / 42698 / 45114 / 43340（皆為正式服），**54261 一筆都沒有**。
且有驗證標記的列反而更容易是死的（522 筆中 398 筆指向不存在的任務）——因為它們是拿正式服驗的。

移植可行性實測（TDB335 → TDB343）：

```
creature_queststarter   7,430 筆中 7,135 可用（96.0%）   缺 NPC: 0
creature_questender     7,859 筆中 7,495 可用（95.4%）   缺 NPC: 0
gameobject_queststarter   449 筆中   405 可用（90.2%）   缺物件: 0
```

修正：刪除指向不存在任務的死列，併入 TDB335 中任務與 NPC 皆存在的關聯。
結果：無起始點的任務 4,596 → **1,177（13.8%）**，優於 TDB335 自身的 19.0%。
開機載入數 5,142 → 7,228，任務關聯錯誤 29,223 → 0。

### patch 003 — `disables` 停用清單（**決定性的一關**）

修完 002 之後 NPC 頭上仍無驚嘆號。原因在 `Player::CanSeeStartQuest` 的第一行：

```cpp
if (!DisableMgr::IsDisabledFor(DISABLE_TYPE_QUEST, quest->GetQuestId(), this) && ...
```

```
disables 表 sourceType=1（DISABLE_TYPE_QUEST）共 5,242 筆

5,107  "Deprecated quest: ..."
   47  "Removed in 4.0.3a"              ← 4.0.3a 即大災變
    6  "removed in patch 7.0.3"
   其餘 "Obsolete quest: ..."（後續資料片移除的職業技能任務）

170  Deprecated quest: A New Threat
179  Deprecated quest: Dwarven Outfitters
233  Deprecated quest: Coldridge Valley Mail Delivery
```

全部是 WotLK 之後才移除的內容，但本庫跑的是災變前的世界，這些任務在 `quest_template` 裡都還在（3,927 筆）。

修正：刪除任務確實存在於本庫的那 3,927 筆，其餘 1,315 筆（指向不存在的任務）保留。
驗證：`Checked 1315 quest disables`，Sten Stoutarm 恢復提供 179 / 233 / 3106-3115。

## 三、已知未修

`npc_text` 的 `BroadcastTextID` 錯位 **264 筆（4.0%）**。例：

```
TDB343  npc_text 4937 → BroadcastText 7589 = "Once ye've seen one trogg, ye've seen 'em all."
3.3.5   npc_text 4937 = "Ah, well aren't you a sturdy-looking one? ..."     ← 正確的 Sten 問候語
```

無法自動修復：正確原文在 hotfixes 庫中不存在（大災變時被改掉），文字比對只能還原 25 筆。
正確字串應在客戶端自身的 `BroadcastText.db2`，但需要 WDC 解析器才能反查 ID。
影響僅限問候語風味文字，不影響接／交任務、商店、訓練師。

附帶確認：`hotfixes.broadcast_text` 73,035 筆全為 build 53040 / 53262，**零筆 54261**；
但 `hotfix_data` 中 BroadcastText（TableHash `0x4CCDE707`）推送數為 0，故客戶端使用自身 DB2，此表無害。

## 四、上游沒有東西可用

- `origin/wotlk_classic`（tip `12c81a6f86`，2025-07-02，重新 fetch 確認未更新）的 `sql/updates/world/` 只有三個檔案，
  且第一個把 `db_version` 設為 **TDB 442.25051（大災變）**——該分支的世界庫基底根本不是 TDB343。
  對 `disables` / 任務關聯 / `playercreateinfo` / `npc_text` **零提及**。
- `xHashii/3.4.3_Source`（fork 自 Wrathion，2026-08-12 仍在動）是唯一帶版本化 SQL 樹的 fork，
  三個 world 更新分別處理 `lfg_dungeon_template`、`creature_template_difficulty`（怪物 1 HP）、
  `areatrigger_teleport`（副本傳送點）——對本文的四張表同樣**零提及**。
  那三個修正值得日後取用，但與任務層無關。

結論不變：**這條線沒有上游，我們自己就是維護者**。修正全部留在 `~/Works/side-project/tdb343-test/patches/`，
標註「vs TDB343.24081」，以便日後與 Wrathion / xHashii 對照。

---

## 五、已發現待研究（pending，暫不處理）

### 5-1 客戶端棄用怪顯示內部名 "Unused [4.x] ..."（335 spawn ↔ 343 client 血統落差）

**發現**：2026-09-06，重建死亡礦坑（map 36）過程中。玩家在副本內看到怪物名為
**「Unused [4.x] 礦工強森」**（entry `3586` Miner Johnson）。

**查證**：
- 3586 是正牌經典死亡礦坑稀有精英，`world_335` 與 `world` 的 `creature_template.name` 皆為 `Miner Johnson`（enUS 正常）。
- 343 `creature_template_locale` 對 3586 **無任何列**（zhTW 缺）；server 端沒有 "Unused" 字串。
- 客戶端仍顯示中文 "Unused [4.x] 礦工強森" → 名字來自 **3.4.3 客戶端自身的 zhTW 生物名 db2 / `Cache/WDB/zhTW/creaturecache.wdb`**，
  是暴雪在 Cata(4.x)改版死亡礦坑後把該怪標記棄用、經典版客戶端沿用了此開發名。

**本質**：這是「**data 全來自 335 + 結構/客戶端用 343**」策略的血統縫隙——
少數在原版 WotLK(3.3.5)真實存在的怪，到 3.4.x 客戶端資料裡被暴雪標記棄用/改名。
我們忠實從 335 刷出來（政策正確），但客戶端顯示其棄用內部名。

**live 對照**：暴雪 live WotLK Classic 用配套的單一資料集，玩家幾乎不會看到此內部名
（要嘛 live 未 spawn 該怪、要嘛送正確名字）。此現象是私服混搭資料才會浮現。

**待研究**：
1. 這類「客戶端標記 Unused」的怪在死亡礦坑/全世界共有多少隻？（需比對客戶端 db2 的名稱前綴 "Unused"）
2. server 端加 `creature_template_locale`(zhTW) 覆蓋，客戶端會採用 server 名還是仍用自身 db2？（可實測）
3. 若要貼近 live：是否該剔除客戶端標記棄用的 spawn，或建立「棄用怪對照表」逐一決定保留/替換。

**現行決定**：**留著不管**。3586 本身是合法經典怪，對「原版 WotLK 還原」反而更忠實；名字醜但無功能影響。日後再處理。

**相關**：死亡礦坑重建流程（spawn + creature_template_difficulty 等級/掉落/金錢 + waypoint 335→343 結構轉換）見本次 map36 遷移；映射表：
`spawnMask→spawnDifficulties`、`phaseMask→PhaseId/PhaseGroup`、`creature_addon.path_id→PathId`、
`waypoint_data(每節點 move_type)→waypoint_path(每路徑 MoveType)+waypoint_path_node`。
