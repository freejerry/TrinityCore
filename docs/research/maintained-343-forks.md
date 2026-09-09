# 還有沒有人在維護 3.4.3 這條線？—— fork 與衍生專案的一手盤點

> 撰寫日期：2026-09-04
> 相關筆記：[`cata_classic` 後端選項評估](./cata-classic-backend-option.md)（本篇是它 §5.3「先把 tag 建起來」之後的下一個問題）、[`wotlk_classic` 完工評估](./wotlk-classic-completion-assessment.md)、[RaGEZONE 論壇調查](./community-forum-findings.md)（本篇覆核並大幅擴充其 §2.2 / §2.3）、[開源模擬器全景調查](./classic-client-emulator-landscape.md)（本篇再次修正其 §7）
> **本篇只問一個問題：** 我們現在坐在一個 2024-08 的凍結 tag（`TDB343.24081`）上，**外面有沒有一條「還活著的 3.4.3 線」值得改基或追蹤？**
> 來源限定 primary sources：`gh api`（repo metadata / branches / commits / compare / forks / search）、`curl` 取得的 raw 原始碼與 README、以及本 repo 的**唯讀** git（未切換分支、未修改任何追蹤檔案、未 fetch 任何外部 remote）。第三方原始碼一律下載到 scratchpad 後**逐檔 diff**，不靠 README 自述。凡未實跑者標示「**未驗證**」。未使用瀏覽器自動化。
> **既定前提（本次不重新論證）：** 使用者手上有 **3.4.3.54261** client；現行 stack `3.4.3 client → Xian55/HermesProxy → TrinityCore 3.3.5` 已經玩得動且已 zhTW 化；平行實驗中 **`TDB343.24081`（`92796557f9`）在 2026 工具鏈上已成功建置並啟動**，`mapextractor` 實測回報 `Detected client build 54261`，四個資料庫 0 pending updates。唯一的建置阻礙是 `Spell.cpp` 缺一條 `Spell::SearchTargets` 的顯式實例化。

---

## 0. TL;DR —— 直說 Yes/No

**Yes，有——但不是「一個維護中的 3.4.3 core」，而是「一條由三個人接力、彼此不互通、全部從 `TDB343.24081` 分出去的小溪」。而且其中最重要的那一支（Wrathion）已經幫我們把包含 `SearchTargets` 在內的 2026 工具鏈建置修正做完了。**

七點裁決：

1. **上游 TrinityCore 對 3.4.x 完全沒有動作。** `TDB343` 這條 release 線最後一版就是 **`TDB343.24081`（2024-08-17）**，其後 30 個 TDB release 沒有任何一個是 343（§1.1）。`wotlk_classic` 分支 tip 仍是 **`12c81a6f86` / 2025-07-02**，且它打的是 3.4.4.61581。repo description 至今不提 `wotlk_classic`。**上游這條線是死的，這點沒有改變。**
2. **★ 最重要的單一發現：`lineagedr/3.4.3_Source`（Wrathion）確認是從 `TDB343.24081` 分出去的，而且它 `Spell.cpp:2192` 已經有我們今天手寫的那一行。** 實測：Wrathion 有 `template TC_GAME_API void Spell::SearchTargets<...WorldObjectSpellAreaTargetCheck>>(...)` 加上 `Spell.h:1016` 的 `extern template`；`TDB343.24081` 兩者皆無。它同時把 `Duration.h` / `UpdateFetcher.cpp` 的 `<chrono>` 補齊。**我們踩到的坑，它 2026-05 就填了。**（§3.4）
3. **Wrathion 相對 `TDB343.24081` 是實質領先，不是雜訊。** 逐檔 diff：1,878 個共同檔中 **601 個內容不同**、**25 個新增檔**、合計 **+57,994 / −53,384**。新增的東西包含 **DK 符文回復（`Player::RegenerateRunes`，`TDB343.24081` 明文 commit 說「disabled」）**、BattlePay 模組、`ArenaTeamHandler` + `ArenaPackets`、`WorldState` 子系統、ZG/ZA/Deadmines/Azuregos 腳本、飛艇 transport。（§3.2–§3.3）
4. **但 Wrathion 本身停在 2026-05-18，且 repo 內沒有 `sql/`。** 它是 code dump，不是專案。**接手的人是 `xHashii/3.4.3_Source`（★6，2026-08-12）——它補上了整個 `sql/` 樹、把 `build_info` 的 54261 那列寫成 update SQL（seed 與我們 tag 裡的完全一致）、`realmlist.gamebuild` 預設改 54261，並修了 LFG/RDF。這是目前**唯一**一個「3.4.3 + 有版控 SQL + 三週內還有 commit」的東西。**（§4）
5. **`RioMcBoo/CypherCoreClassicWOTLK` 是真的，但它反過來依賴我們的 tag。** README 明寫 `The current support game version is: 3.4.3.54261`，而它叫使用者**下載 `TDB_full_343.24081`** 當資料庫、**用 TrinityCore 的 extractor**。停在 2026-03-19。它不是我們的替代方案，它是我們的下游。（§5）
6. **`alseif0x/rustycore` 是最活躍的（2026-09-03），但它離「能用」最遠。** Rust 重寫，README 自陳 `World DB expectation: TDB 343.24081`，而它自己的 `honest-progress-audit.md` 寫「98.15% 是『被碰過的項目』，**沒有宣告缺口的只有 52.86%**，live-runtime 驗證『low / not globally quantified』」。**不是候選後端。**（§6）
7. **裁決：不要改基，但要追蹤。** `TDB343.24081` 仍是唯一有官方 world+hotfixes dump、schema 與 client 對齊、且我們已經實測建得起來跑得動的基底。**正確做法是留在 tag 上，選擇性 cherry-pick Wrathion 的建置修正與 DK 符文，並把 `xHashii/3.4.3_Source` 加進 watch list。**（§8）

---

## 1. 上游信號：TrinityCore 自己有沒有動 3.4.x？

### 1.1 沒有。releases 逐筆核對

```
gh api repos/TrinityCore/TrinityCore/releases --paginate --jq '.[]|"\(.tag_name) \(.published_at)"'
```

前 30 筆裡 **343 只出現兩次**：`TDB343.24081`（2024-08-17）與 `TDB343.23121`（2023-12-20）。`TDB343.24081` 之後發行的 17 個 TDB 全是 `442` / `335` / `11xx` / `12xx` 線（最新 `TDB442.26081` 2026-08-14）。**343 線在 2024-08-17 封存。**

### 1.2 分支與 issue

| 項目 | 實測值（2026-09-04） |
|---|---|
| 遠端分支總數 | **4**：`3.3.5`、`cata_classic`、`master`、`wotlk_classic` |
| `wotlk_classic` tip | `12c81a6f86` **2025-07-02T01:49:56Z** `Core/PacketIO: Fix FeatureSystemGlueScreen structure` |
| repo description | `master = 12.1.0.69497, 3.3.5 = 3.3.5a.12340, cata classic = 4.4.2.60895` —— **仍不含 3.4.x** |
| `base:wotlk_classic` 的 PR | **13 個，全部 closed**，最新 `#30946`（2025-05-14） |
| 2024-09 之後提到 `3.4.3` 的 issue/PR | **10 個，全部 closed，且全部是 3.3.5 的 DB 修正**（`Love is in the Air spawns` 之類），**沒有一個真的在講 3.4.3 client** |

**→ 上游對 3.4.3 的態度：不是「進行中」，是「不存在」。**

---

## 2. 方法與它的洞（先講清楚可信度）

**GitHub code search 有兩個會系統性漏檢的限制，本篇兩個都補了：**

1. **只索引 default branch。** 所以「放在非預設分支上的 3.4.3 工作」搜不到。
2. **完全不索引 fork。** 實測：`gh api "search/code?q=54261+repo:RioMcBoo/CypherCoreClassicWOTLK"` → **0 筆**，但該 repo 的 README 第三行就寫著 `3.4.3.54261`。**這一點比第 1 點更致命，而[全景調查](./classic-client-emulator-landscape.md)§1 只記了第 1 點。**

**補洞方式（實跑）：**

- **code search 抓 markers**（只對非 fork 有效）：`TDB_full_world_343`、`TDB_full_hotfixes_343`、`54261 filename:auth_database.sql`、`"54261,3,4,3"`、`TDB343`。
- **fork network 掃描**：`repos/TrinityCore/TrinityCore/forks` 取 **star 前 200 + 最新 300**，去重得 **496 個**；篩出 `pushed_at >= 2025-01-01` 的 **325 個**，**逐一列出其 branch 清單**（325/325 完成），再 grep `3.4|343|wotlk`。
- **對候選 repo 直接下載 tarball 逐檔 diff**，不採信 README。

**仍然沒掃到的（誠實記錄）**：TrinityCore 有 **6,387 個 fork**，本次只列舉了 496 個、只展開了 325 個的分支清單。**不能宣稱窮舉。** 非 GitHub 託管（GitLab / Codeberg / 自架 / 私有）者完全不在範圍內。

---

## 3. `lineagedr/3.4.3_Source`（Wrathion）—— 覆核與深挖

### 3.1 現況（覆核[論壇筆記](./community-forum-findings.md)§2.2，結論不變）

| 欄位 | 值（`gh api` 2026-09-04 實測） |
|---|---|
| default branch | `main`（**唯一分支**） |
| License | **GPL-2.0** |
| ★ / fork 數 | **35 / 32** |
| created / pushed | 2026-05-17 / **2026-05-18T19:20:11Z**（**四個月未動**） |
| 最後 commit | `b864f5d8c4 Remove tools exclusion from .gitignore.` |
| commit 總數 | **7**（`Initial commit` × 2 + README + 兩個編譯修正 + merge） |
| `sql/` 目錄 | **仍然沒有**。root 只有 `Patches / cmake / dep / src` + build 檔 |
| open issue | **1 個**：`#2 [Question] Any guide possible?`（2026-06-14，`kasperfriend` 卡在 `BLZ51901023` / bnetserver SSL handshake，**作者未回**） |

**→ 論壇筆記的判定「它是 code dump，不是進行中的專案」在 2026-09-04 仍然成立。**

### 3.2 ★ 它到底是從哪裡分出去的？——實測是 `TDB343.24081`

前一篇只能說它「與上游 `wotlk_classic` 同型」。本次做了決定性的量測：把 Wrathion 的 `src/` 與本 repo 的 tag 逐檔 `cmp`。

```
共同檔案 1,878 個
  與 TDB343.24081 逐位元組相同：1,279
  與 TDB343.23121 逐位元組相同：  977
```

**1279 > 977，且 `Opcodes.h` 與 `TDB343.24081` 只差 11 行、`WorldSocket.cpp` 只差 5 行。→ Wrathion 的 base 是 `TDB343.24081`，不是更早的 23121。**

> **一個必須記下的矛盾（未解）：** Wrathion 的 `revision_data.h.in.cmake` 卻寫著
> `_FULL_DATABASE "TDB_full_world_343.23121_2023_12_20.sql"` / `_HOTFIXES_DATABASE "TDB_full_hotfixes_343.23121_2023_12_20.sql"`。
> **也就是：程式碼是 24081 的，但它期望你灌 23121 的 world/hotfixes dump。** 這與 `Xian55` 的 `wotlk.md` 稱 Wrathion 為「build 23121」一致。**這是要注意的地雷——若拿 Wrathion 的碼配 24081 的 dump，updater 的 `_FULL_DATABASE` 檢查會不對。未驗證實際後果。**

DB2 版本哨兵（`DB2Stores.cpp`）與 `TDB343.24081` **完全相同**：`AreaTable 14483 / CharTitles 757 / GemProperties 1629 / Item 211851 / ItemExtendedCost 8328 / Map 2567 / SpellName 429548`，註解一律 `3.4.3 (51943)`。`CURRENT_EXPANSION = EXPANSION_WRATH_OF_THE_LICH_KING`（`SharedDefines.h:133`）、`CONF_Product = "wow_classic"`（`map_extractor/System.cpp:112`）。

**目標 build 無法從原始碼確認**：`54261` 在整個 repo 內 **0 命中**（code search + 本地 grep 皆然），因為 build 完全由缺席的 `sql/` 驅動。**「Wrathion 目標 build = 54261」只有作者與二手說法，本篇無法從碼證實。**

### 3.3 它領先了什麼？（逐檔 diff，非自述）

```
diff -rq  tc24081/src  wrathion/src
  → 內容不同 601 檔 ／ Wrathion 獨有 25 檔
diff -rN -u 全樹  → +57,994 / −53,384
```

**Wrathion 獨有的新檔（全部實測，非推測）：**

| 類別 | 檔案 |
|---|---|
| **競技場隊伍** | `Handlers/ArenaTeamHandler.cpp`、`Server/Packets/ArenaPackets.{h,cpp}` |
| **BattlePay** | `src/server/game/BattlePay/`（整個目錄） |
| **WorldState 子系統** | `World/WorldStates/WorldState.{h,cpp}` |
| **移動** | `Movement/AbstractPursuer.{h,cpp}`、`Spline/enuminfo_MoveSplineFlag.cpp` |
| **共用** | `src/common/Nav/`、`Utilities/MathUtil.h`、`Utilities/StringFormat.cpp` |
| **腳本（明顯是 3.3.5 內容回填）** | ZulGurub 全套（Hakkar / Jindo / Thekal / Marli / Arlokk / Jeklik / Gahzranka + `zulgurub.cpp`）、ZulAman `boss_zuljin`、Deadmines `boss_vancleef`、Kalimdor `boss_azuregos`、`World/transport_zeppelins.cpp` |
| 自訂 | `scripts/Custom/custom_wrathion.cpp` |

**改動最大的既有檔（diff 行數）：** `Player.cpp` 6,453、`Unit.cpp` 4,449、`spell_priest.cpp` 2,679、`spell_dk.cpp` 2,666、`SpellAuraEffects.cpp` 2,523、`spell_druid.cpp` 2,361、`SpellMgr.cpp` 2,192 …… **這是一整輪 WotLK 職業法術與屬性系統的降級工作，不是零星修補。**

通訊/資料層也有實質改動：`DB2LoadInfo.h` 1,189、`DB2Metadata.h` 1,080、`DB2Structure.h` 818、`DB2Stores.cpp` 467、`WorldSession.h` 202、`Opcodes.cpp` 196、`PacketUtilities.h` 160，另有 `AuctionHousePackets` / `InspectPackets` / `TalentPackets` / `LFGPackets` / `BattlegroundPackets` / `InstancePackets` 等十餘個封包類別的欄位調整。

**DB2 metadata 被瘦身**：`*Meta` 結構數 **788 → 718**，砍掉的 70 個全部是 retail 殘留（`Artifact*` 13、`Azerite*` 11、`Garr*` 30+、`AdventureJournal`…）。**這正是 [`cata_classic` 筆記](./cata-classic-backend-option.md)§3.2 指出 `TDB343.24081` hotfixes schema 帶了 100 張 retail 殘表的那個問題，Wrathion 做了清理。**

**DK 符文回復——`TDB343.24081` 明文停用的那一項，Wrathion 做了：**

```
本 repo：git log e72bde5236..TDB343.24081 --grep=rune
  → 1df708e085 Core/Units: downgraded power types enum and
                disabled Death Knight rune regeneration mechanics for the time being

TDB343.24081/Player.cpp  → 全檔只剩一處 RUNE_BASE_COOLDOWN，無 RegenerateRunes
Wrathion/Player.cpp:8680 → void Player::RegenerateRunes(uint32 diff)
              :1614      → RegenerateRunes(m_regenTimer);
              :25833     → RuneType::Blood/Frost/Unholy → POWER_RUNE_*
```

**→ [`cata_classic` 筆記](./cata-classic-backend-option.md)§5.2 第 1 點列的「已知未完成項：DK 符文回復被停用」，在 Wrathion 上不成立。**

### 3.4 ★ 它已經有我們今天手寫的那一行

```
grep -n "template void Spell::SearchTargets" <ref>/src/server/game/Spells/Spell.cpp
  TDB343.24081 → 無
  Wrathion     → Spell.cpp:2192
    template TC_GAME_API void Spell::SearchTargets<
        Trinity::WorldObjectListSearcher<Trinity::WorldObjectSpellAreaTargetCheck>>(...);
  Wrathion     → Spell.h:1016
    extern template void Spell::SearchTargets<
        Trinity::WorldObjectListSearcher<Trinity::WorldObjectSpellAreaTargetCheck>>(...);
```

另外兩處同類的 2026 工具鏈修正：

| 檔案 | `TDB343.24081` | Wrathion |
|---|---|---|
| `src/common/Utilities/Duration.h` | `#include <__msvc_chrono.hpp>` + `<chrono>`（MSVC 專用私有標頭） | 只有 `#include <chrono>` |
| `src/server/database/Updater/UpdateFetcher.cpp` | 無 `<chrono>` | `:29 #include <chrono>` |

**這兩項與社群那兩份 3.4.3 架設指南（`IzomSoftware` / `SyNdicateFoundation`，見 §7.2）列的「Common Errors」逐字對應**：

> `invalid literal suffix 'h'` or `std::chrono::high_resolution_clock` not found →
> `Duration.h`: add `<chrono>`；`UpdateFetcher.cpp`: add `<chrono>`

**→ 結論：「2023-11 的原始碼在 2026 工具鏈上編不編得過」這個問題，社群已經獨立回答過至少三次，答案是「編得過，需要三到四處已知的小修」。我們的 `SearchTargets` 修正是同一類，而且 Wrathion 的版本是可直接對照的參考解。**

### 3.5 world DB 在哪裡

**repo 內沒有。** 依 `Xian55/HermesProxy` 的 `wotlk.md`（[論壇筆記](./community-forum-findings.md)§2.2 已引），Wrathion 的資料庫是 4 個 SQL dump（auth / characters / world / hotfixes，約 315 MB）**在 repo 之外散布**；README 只附一段 YouTube 展示影片，沒有 DB 連結。
**依任務界線：確認「repo 外另有 dump 存在」到此為止，本篇不蒐集、不記錄任何下載途徑。**
**而且對我們而言這件事不重要**——我們已經有官方 `TDB_full_343.24081`，且 `worldserver` 實測 0 pending updates。

---

## 4. ★ `xHashii/3.4.3_Source` —— 真正還在動的那一支

**這是本次調查最有價值的新發現，前四篇筆記都沒有涵蓋。** 它是 Wrathion 的 GitHub fork（`parent = lineagedr/3.4.3_Source`，非鏡像）。

| 欄位 | 值（實測） |
|---|---|
| default branch | `main`（唯一分支） |
| License | **GPL-2.0**（承 Wrathion） |
| ★ / fork | **6 / 1** |
| 最後 push | **2026-08-12T18:38:42Z**（本篇撰寫日前 **23 天**） |
| 相對 `lineagedr:main` | `gh api compare` → **status=ahead，ahead 7 / behind 0，27 檔** |
| open issue | 0（但有 `.github/ISSUE_TEMPLATE/game-bug-report.md`） |

**7 個 commit（`gh api commits`）：**

```
2026-08-12 8982d917 Possible fix for dungeon teleport locations and mobs/npcs having 1HP
2026-08-10 5fba5c86 Fixed RDF completely and setup the SQL structure
2026-08-08 74b3761b Fix LFG Dungeon Finder for 3.4.3
2026-08-06 46486b27 Update issue templates
2026-08-05 56895c9f Add download link for 3.4.3 Client
2026-08-05 650de9d0 Reformat prerequisites section in README.md
2026-08-05 af6e04b5 Revise README to include prerequisites for setup
```

> README 內含一個 client 下載連結。**依任務界線不記錄，僅記其存在。**

### 4.1 ★ 目標 build 從原始碼驗證：54261，且 auth seed 與我們的 tag 一字不差

`sql/updates/auth/3.4.3/2026_08_10_00_auth.sql`（實際取得全文）：

```sql
-- Register client build 54261 (Wrath Classic 3.4.3) as a supported build.
INSERT IGNORE INTO `build_info`
    (`build`,`majorVersion`,`minorVersion`,`bugfixVersion`,`hotfixVersion`,
     `winAuthSeed`,`win64AuthSeed`,`mac64AuthSeed`,`winChecksumSeed`,`macChecksumSeed`)
VALUES
    (54261, 3, 4, 3, NULL, NULL, '25FD812475DCF26F9F1383AED37FC99E', NULL, NULL, NULL);

ALTER TABLE `realmlist` ALTER COLUMN `gamebuild` SET DEFAULT 54261;
```

`win64AuthSeed` = **`25FD812475DCF26F9F1383AED37FC99E`** —— **與 [`cata_classic` 筆記](./cata-classic-backend-option.md)§1.3 從 `TDB343.24081:sql/base/auth_database.sql` 讀到的完全相同**。`sql/base/auth_database.sql:385` 的 `realmlist.gamebuild` 預設也直接是 `54261`（我們的 tag 是 `53788`）。

**→ 這是本篇第一個「從第三方原始碼獨立驗證 54261 + 同一把金鑰」的證據，等於交叉確認了我們那條路是對的。**

### 4.2 它補上了 Wrathion 最大的缺口：`sql/`

`gh api compare` 的 27 個檔案，**20 個是新增的 SQL 樹**：

```
sql/README.md（40 行，說明版面設計）
sql/create/create_mysql.sql
sql/base/{auth_database.sql 471行, characters_database.sql 1634行, hotfixes_database.sql 7383行/376表}
sql/updates/{auth,characters,world,hotfixes}/3.4.3/
   auth/       2026_08_10_00_auth.sql (18)   2026_08_10_01_auth.sql (505)
   characters/ 2026_08_10_00_characters.sql (25,135)
   world/      2026_08_09_00_world.sql (32)  2026_08_12_00_world.sql (1,825)  2026_08_12_01_world.sql (161)
   hotfixes/   （空，只有 .gitkeep）
```

`sql/README.md` 的設計說明（原文摘）：

> "Unlike auth and characters (which start essentially empty on a fresh install), world and hotfixes ship as one full data dump - this mirrors how upstream TrinityCore distributes the 'TDB' (TrinityCore Database) release … Our `world.sql` / `hotfixes.sql` fill that same role."

`revision_data.h.in.cmake` 也被改成自家 dump：
`_FULL_DATABASE "world_full_2026_08_10.sql"` / `_HOTFIXES_DATABASE "hotfixes_full_2026_08_10.sql"`。

**→ 意義：它把 Wrathion 從 code dump 變回一個「可重現安裝」的專案，但代價是 world/hotfixes 的 full dump 同樣在 repo 外。對我們而言這是退步而非進步——我們用的是官方 `TDB_full_343.24081`，來源可驗證。**

### 4.3 它的 C++ 改動只有一塊：LFG / RDF

`gh api compare` 的其餘 7 個檔案全部在 `src/server/game/DungeonFinding/`：

```
LFGMgr.cpp        +1773 / −1672
LFGQueue.cpp       +529 /  −528
LFGQueue.h          +64 /   −62
LFGPlayerData.cpp   +21 /   −10
LFGGroupData.cpp    +14 /   −10
LFGScripts.cpp      +27 /    −5
```

commit 訊息自述 `Fix LFG Dungeon Finder for 3.4.3` / `Fixed RDF completely`。**未驗證正確性。** 但值得注意：LFG 在 [HermesProxy 的 `wotlk.md`](./community-forum-findings.md)§3.3 是列為「已驗證會動」的項目，所以這一塊我們現行 stack 沒有痛點；**它的價值在原生路徑上才會顯現。**

### 4.4 裁決

**`xHashii/3.4.3_Source` 是目前唯一符合「活著的 3.4.3 線」定義的東西**（三週內有 commit、有版控 SQL、build 從碼可驗證）。**但它只有 6 顆星、1 個 fork、7 個 commit、一個貢獻者，且沒有任何 issue 討論。這是「一個人的週末專案」，不是一個社群。把它當成 watch list 上的一列，不是當成 upstream。**

---

## 5. `RioMcBoo/CypherCoreClassicWOTLK` —— C# 線，且它依賴我們的 tag

| 欄位 | 值（實測 2026-09-04） |
|---|---|
| 血統 | **`CypherCore/CypherCore` 的 GitHub fork**（`parent` 欄位確認，非鏡像） |
| default branch | **`WOTLK_CLASSIC`**（另有 `master`、`working_on_pets_dump`） |
| License | GPL-3.0 ／ ★ **23** ／ fork **7** ／ open issue **4** |
| created / pushed | 2023-01-02 / **2026-03-19T17:03:36Z**（**停滯 5.5 個月**） |
| 最後 commit | `d3b86cdb Core/Stats: Downgrading stats system to WOTLK (continuation) #17` |
| 相對 `CypherCore:master` | `gh api compare` → **diverged，ahead 705 / behind 1362**（300 檔上限） |
| 上游 `CypherCore/CypherCore` | retail，★438，2026-09-02 極活躍 |

### 5.1 目標 build：從 README 驗證（code search 對 fork 無效）

```
curl -s .../RioMcBoo/CypherCoreClassicWOTLK/WOTLK_CLASSIC/README.md
```

> "The current support game version is: **3.4.3.54261**"
> "### Installing the database — Download the full Trinity Core database **(TDB_full_343.24081_2024_08_17)**"
> "Use TrinityCore extractors for now: **TrinityCoreLegacy/TrinityCore/tree/3.4.3**"
> "Must use Arctium WoW Client Launcher … `--version=Classic`"

**★ 這三行是本節的全部重點：這個專案的 world/hotfixes DB 就是 `TDB343.24081`、extractor 就是 `TDB343.24081`（`TrinityCoreLegacy` 的 `3.4.3` 分支，見 §7.1 實測 = 同一顆 commit）。**

**→ 它不是「`TDB343.24081` 的替代品」，它是「`TDB343.24081` 的消費者」。**

### 5.2 是不是現實的替代方案？——不是

| 理由 | 依據 |
|---|---|
| **停滯** | 最後 commit 2026-03-19，上游 CypherCore 同期跑了 1,362 個 commit |
| **落後上游 1,362** | 與 [`wotlk_classic` 落後 `cata_classic` 1,264](./wotlk-classic-completion-assessment.md)§1.1 是同一種病 |
| **語言 / 生態換掉** | C# / .NET 10。我們在 HermesProxy（C#）與 TrinityCore（C++）都已投入，再開第三條線沒有理由 |
| **本地化管線未驗證** | 未檢查它是否有 `*_locale` 表與 `PREPARE_LOCALE_STMT` 的對應物。**未驗證** |
| **DB 仍是我們手上這一份** | 內容成熟度不會比較好，只會一樣 |

其 7 個 fork 全部 `default_branch = WOTLK_CLASSIC`，最新一個 `leewheel/RioMcBooCoreClassicWOTLK`（2025-11-13，★0）——**沒有任何一個比 parent 新。**

---

## 6. `alseif0x/rustycore` —— 最活躍，也最不能用

| 欄位 | 值 |
|---|---|
| default branch | **`3.4.3`** |
| License | repo API 回 `NOASSERTION`，但 **`LICENSE` 檔實測是 GPL-3.0**（`Copyright (C) 2026 alseif0x`）——**metadata 與檔案不一致，散布前要自己確認** |
| ★ / fork / open issue | **21 / 9 / 45** |
| created / pushed | 2026-03-02 / **2026-09-03T12:39:34Z**（**昨天**） |
| 最後 commit | `505c9a01 Complete SQLx-free persistence ownership boundary (#577)` |

README 的 Target 段（原文）：

> - **Client:** WotLK Classic `3.4.3.54261`
> - **Tested game build:** `51943`
> - **World DB expectation:** **`TDB 343.24081`, `cache_id = 24081`**
> - **Reference implementation:** TrinityCore/WotLK-style C++ source

**→ 又一個獨立確認：`TDB343.24081` 是這個生態的事實標準資料庫。**

**但它自己的 `docs/migration/honest-progress-audit.md`（2026-06-20）寫得非常誠實，直接引用：**

> "This document exists to prevent the headline `98.15%` from being read as 'almost a finished, gap-free server.'"

| 指標 | 值 |
|---|---|
| 項目「被處理過」（非 pending） | **98.15%**（1168/1190） |
| **沒有宣告缺口** | **52.86%**（629/1190） |
| **Live-runtime / manual-test 驗證** | **"low / not globally quantified"** |

> "**539 of the 1168 'addressed' rows (46.15%) are partial-boundary rows** … each has open boundaries by definition."
> "The bulk of the game logic is ported and contrasted against C++ in a per-session 'represented' model … it is not the same thing as a complete running server."

**裁決：技術品質與文件誠實度都很高，值得長期追蹤，但它是一個進行中的 Rust 移植，不是我們能拿來當後端的東西。與 [`wotlk_classic` 評估](./wotlk-classic-completion-assessment.md)§6.2 的邏輯相同：「完成它不會讓你得到現在沒有的東西」。**

---

## 7. 其他全部查到的東西（含死的、鏡像的，一併記錄以免下次重查）

### 7.1 TrinityCore fork 網路（496 個列舉 / 325 個展開分支）

**325 個分支清單裡，「有非上游 3.4.x 分支」的只有兩個：**

| repo | 分支 | 實測 |
|---|---|---|
| **`TrinityCoreLegacy/TrinityCore`** | `3.4.3` = **`92796557`** | ★62、fork 32、GPL-2.0、default `3.3.5`、pushed 2026-08-06。**`3.4.3` 分支的 tip 就是 `TDB343.24081` 那顆 commit，一個 commit 都沒加。** 它是**多資料片的分支保存庫**（`2.4.3`/`3.3.5`/`3.4.3`/`4.3.4_new_TCPP`/`6.x`/`7.3.5`/`8.3.7`/`9.2.7`/`10.2.7`）。**價值不在程式碼，在它是社群公認的「3.4.3 從這裡 clone」入口**（§7.2 兩份指南都指向它） |
| `0xf4b1/TrinityCore` | `3.4.3`、**`3.4.3npcbots`** | `compare 92796557...0xf4b1:3.4.3` → **identical, ahead 0 / behind 0**；`3.4.3npcbots` → **ahead 2**（`3ff43637 wip npcbots patch apply`、`038dd95f wip fix sql queries`，2026-07-02）。★0。**一個人在 tag 上試貼 NPCBots，WIP。** |

其餘 300+ 個 fork 的 `wotlk_classic` 全部是上游那顆 `12c81a6f86` 的鏡像。`BRUC3L1U/wotlk_classic`（2026-06-10 pushed）已由[全景調查](./classic-client-emulator-landscape.md)§2.1 驗證為 `identical`，本次未變。

### 7.2 非 fork、從 code search 抓到的 3.4.3 markers

| repo | 實測 | 裁決 |
|---|---|---|
| **`haphert/TrinityCore_wotlk_classic_continued`** | ★5、GPL-2.0、**pushed 2024-11-11**（死）。**逐檔 diff：`src/` 與 `TDB343.24081` 內容差異 0 檔**（僅有 `placeholder.txt` 與大小寫重複目錄之類的上傳痕跡）。`sql/base` 有 4 個檔不同：`realmlist.gamebuild` 預設 **54261**（vs tag 的 53788）、world schema **235 表**（vs 236）、`updates` 表少三列 → **它是 24081 之前一點的快照 + gamebuild 預設微調**。`revision_data` 反而指 `TDB_full_world_343.23121` | **兩份社群指南稱它為「some helpful patches」，實測那個 patch 就是 `gamebuild` 預設值一行。沒有任何 3.4.3 修正。** |
| `d23monkey/TrinityCore343` | ★0、GPL-2.0、default `wotlk_classic`、**pushed 2024-11-29**（死）。`build_info` 有 `(54261,3,4,3,...)`、`revision_data` 指 `TDB_full_world_343.23121` | 同 lineage 的個人快照，無價值 |
| `IzomSoftware/wotlk-classic-343-guide`（2026-02-05，★1）／`SyNdicateFoundation/wotlk-classic-343-guide`（2025-12-17，★0） | **內容逐字相同的兩份架設指南。** Requirements 明列：`TrinityCoreLegacy/TrinityCore/tree/3.4.3` + `TrinityCore/releases` 的 TDB + `haphert` 的 patch | **★ 這是「社群共識基底 = `TDB343.24081`」的獨立佐證**，而且它們列的 `Common Errors` 與我們踩的建置坑同類（§3.4） |

### 7.3 明確的空結果（找不到就是找不到）

- **AzerothCore** `azerothcore/azerothcore-wotlk` 的分支清單：`master`、`custom`、兩個 `copilot/research-*`、兩個 `revert-*`。**沒有任何 3.4.x 分支。**
- **CypherCore** fork 網路中 `default_branch != master` 的**只有 `RioMcBoo` 那一條**（§5）。
- `search/code?q=EXPANSION_WRATH_OF_THE_LICH_KING+CURRENT_EXPANSION+wow_classic` → **0 筆**（fork 不被索引所致，見 §2）。
- repo search `wrath classic emulator` → **0 筆**。
- **沒有找到任何 3.4.4.61581 的第三方實作。** 與[論壇筆記](./community-forum-findings.md)§4 一致。

### 7.4 順帶覆核：HermesProxy 家族（現行 stack，非本篇主題）

| repo | ★ | 最後動作 |
|---|---|---|
| **`Xian55/HermesProxy`** | 54 | pushed **2026-09-03T22:47:57Z**；`feature/wotlk-classic-v3.4.3` tip **`8b48138ea6` 2026-09-03T22:44:09Z** `Merge pull request #236 from Xian55/fix/v343-pet-stable` |
| `advocaite/HermesProxy-WOTLK` | 43 | pushed 2026-05-20 |
| **`Xian55/3.4.3_Source`** | 2 | Wrathion 的 fork，**diverged ahead 5 / behind 1**，pushed **2026-08-28**。2 個實質 commit：`30b05406 Core/Player: Fix XP gain when account expansion has no level cap`（2026-08-03）、`82decce9 Core/Battlefield: Init battlefields before preloading continents`（2026-08-28）。**這是 HermesProxy 作者拿 Wrathion 當 wire-format oracle 時順手修的**（呼應[論壇筆記](./community-forum-findings.md)§3.6） |

**→ 現行 stack 的維護者比任何一條 3.4.3 原生線都活躍。這件事本身就是一個裁決依據。**

---

## 8. 裁決：三個問題，直接回答

### Q1. 有沒有一條「還在積極維護的 3.4.3 線」？

**有，但很薄。** 完整清單如下（全部從一手驗證）：

| 專案 | 語言 | 最後 commit | ★ | License | 目標 build 的驗證方式 | 相對 `TDB343.24081` |
|---|---|---|---|---|---|---|
| **`xHashii/3.4.3_Source`** | C++ | **2026-08-12** | 6 | GPL-2.0 | **`sql/updates/auth/.../2026_08_10_00_auth.sql` 的 `build_info` (54261,3,4,3) + 同一把 `win64AuthSeed`** | Wrathion + 7 commit（LFG/RDF + 整套 SQL 樹） |
| `Xian55/3.4.3_Source` | C++ | 2026-08-28 | 2 | GPL-2.0 | 無法從碼驗證（承 Wrathion，無 `sql/`） | Wrathion + 2 個修正 |
| `lineagedr/3.4.3_Source`（Wrathion） | C++ | 2026-05-18 | 35 | GPL-2.0 | **無法從碼驗證**（`54261` 0 命中；哨兵 `3.4.3 (51943)`） | **+57,994 / −53,384，601 檔** |
| `alseif0x/rustycore` | Rust | **2026-09-03** | 21 | LICENSE=GPL-3.0（metadata `NOASSERTION`） | README `Client: 3.4.3.54261` / `World DB expectation: TDB 343.24081` | **重寫，不可比** |
| `RioMcBoo/CypherCoreClassicWOTLK` | C# | 2026-03-19 | 23 | GPL-3.0 | README `3.4.3.54261` + 指定灌 `TDB_full_343.24081` | **重寫（CypherCore 血統），且消費我們的 DB** |
| `0xf4b1/TrinityCore:3.4.3npcbots` | C++ | 2026-07-02 | 0 | GPL-2.0 | 承 tag | **ahead 2（WIP）** |
| ~~`TrinityCoreLegacy:3.4.3`~~ | — | — | 62 | GPL-2.0 | — | **identical（ahead 0）** |
| ~~`haphert` / `d23monkey`~~ | — | 2024-11 | 5 / 0 | GPL-2.0 | `build_info` 54261 | **≈ 相同或更舊，已死** |

**但要看清楚形狀**：**沒有任何一個是「社群」。** 最活躍的兩個（`xHashii`、`rustycore`）各只有一位貢獻者；星數最高的（Wrathion 35★）作者已公開退出；`RioMcBoo` 停了半年。**這不是一條 upstream，這是三四個人各自的實驗。**

### Q2. 它們比 `TDB343.24081` + 我們自己那一行修正更值得當 base 嗎？

**不值得。逐條說明：**

| 候選 | 為什麼不改基 |
|---|---|
| **Wrathion / xHashii** | ① **它們期望的 world/hotfixes dump 不在 repo 內、來源不可驗證**——而我們已經有官方 84 MB `TDB_full_343.24081`，且 `worldserver` 實測 **0 pending updates**，改基就是把「可驗證的官方 DB」換成「不可驗證的私人 dump」。② Wrathion 的 `_FULL_DATABASE` 還指著更舊的 **23121**，與其自身程式碼（24081 base）不一致（§3.2 的矛盾）。③ 那 601 個檔的 diff **沒有任何測試、沒有 CI、沒有 issue 討論、沒有第三方驗證**；`lineagedr` 唯一的 issue 是使用者卡在登入而作者未回。**把 5.8 萬行未驗證的改動一次吃下去，等於把我們已經實測「建得起來、跑得動、DB 一致」的狀態換成未知。** ④ 授權相容（同為 GPL-2.0），**這不是障礙**——真正的障礙是可驗證性。 |
| `RioMcBoo` | 換語言、換生態、停滯半年、落後上游 1,362，且 DB 還是同一份 |
| `rustycore` | 作者自陳 live-runtime 驗證 "low"，52.86% 無缺口 |
| `TrinityCoreLegacy` / `haphert` / `d23monkey` / `0xf4b1` | 與我們的 tag 相同或更舊 |

**→ 但「不改基」不等於「不拿東西」。應該做的是 cherry-pick，而不是 rebase：**

| 優先度 | 從哪裡拿 | 拿什麼 | 為什麼安全 |
|---|---|---|---|
| **高** | Wrathion `Spell.cpp:2192` + `Spell.h:1016` | `SearchTargets` 顯式實例化 | **我們已經自己寫了一份。拿它來比對寫法（`TC_GAME_API` + `extern template` 的配對）即可**，屬純建置修正，零行為風險 |
| **高** | Wrathion `Duration.h` / `UpdateFetcher.cpp` | `<chrono>`、移除 `<__msvc_chrono.hpp>` | 純建置修正；兩份社群指南獨立列為必要 |
| **中** | Wrathion `Player::RegenerateRunes` 一組 | DK 符文回復 | **上游明文停用的功能**，是[`cata_classic` 筆記](./cata-classic-backend-option.md)§5.2 列的已知缺口第 1 項。**但這是行為改動，必須自己驗證** |
| **低／觀望** | `xHashii` 的 `DungeonFinding/` 6 檔 | LFG/RDF 修正 | 只有在原生路徑真的撞到 LFG 才需要 |
| **不要拿** | Wrathion 的 `DB2Metadata.h` 瘦身（788→718） | 砍掉 70 個 retail store | **會連動 `DB2LoadInfo.h` / `DB2Structure.h` / hotfixes schema 四份必須一致**（[完工評估](./wotlk-classic-completion-assessment.md)§5 Stage 2 已論證）。我們的 hotfixes DB 已經 0 pending updates，動它等於自找 `TC_LOG_FATAL` |
| **不要拿** | BattlePay / WorldState / ArenaTeam / ZG 腳本 | — | 與 zhTW 化目標無關，且是最大的未驗證面 |

### Q3. 如果沒有更好的，凍結的 tag 意味著什麼？

**`TDB343.24081` 就是最好的可得基底，而且我們現在有三個獨立證據支持這個判斷**（社群兩份指南、`RioMcBoo` 的 README、`rustycore` 的 Target 段，全部指名 `TDB343.24081` 或 `TrinityCoreLegacy:3.4.3`＝同一顆 commit）。

**但要接受它的三個後果：**

1. **我們是自己的維護者。** 不會有上游修正流過來——不是「上游慢」，是**上游對 3.4.x 沒有 upstream**。所有 patch（含今天那一行）都要自己保存、自己 rebase-proof、自己記錄理由。**建議：把每一項本地修正做成獨立 commit，訊息裡註明「vs TDB343.24081」，將來要與 Wrathion / xHashii 對照時才有 diff 可比。**
2. **不會有新的 TDB343。** world DB 的內容永遠是 2024-08-17 的狀態。[`cata_classic` 筆記](./cata-classic-backend-option.md)§5.1 已證明往前遷移是 297 萬行，**這個結論不變且被本篇強化**——連社群裡最投入的三個人都沒有一個嘗試過往前遷移，全部選擇留在 tag 上加 patch。
3. **這條路的天花板是「我們自己願意投入多少」，不是「上游做到哪」。** 相對地，[HermesProxy 現行 stack](./hermesproxy-evaluation.md) 的後端 `origin/3.3.5` 上游活躍（2026-08-30 有 commit）、proxy 本身昨天還在 commit。**兩條路的維護風險輪廓完全相反：原生路徑沒有上游但沒有翻譯層長尾；proxy 路徑有上游但有結構性天花板。**

**具體建議（不動現行 stack）：**

- **留在 `TDB343.24081`，把本地 patch 集整理成一個可 replay 的序列。**
- **把 `xHashii/3.4.3_Source` 與 `alseif0x/rustycore` 加進 watch**（兩者都是單人專案，隨時可能停；也隨時可能出現我們需要的修正）。
- **把 Wrathion 的 tarball 留在本地當「參考解答庫」**——它是目前公開可得、與我們 base 最近、且已通過 2026 工具鏈的唯一一份 3.4.3 程式碼。**不 merge，只查閱。**
- **不要碰 `wotlk_classic`、不要碰 `cata_classic`、不要 rebase。** 三篇筆記的結論在此完全一致。

---

## 9. 驗證指令（全部唯讀；未 fetch 外部 remote、未切換分支、未修改任何追蹤檔案）

```bash
# --- §1 上游信號 ---
gh api repos/TrinityCore/TrinityCore --jq '{description,pushed_at,forks_count,stargazers_count}'
gh api repos/TrinityCore/TrinityCore/branches --paginate --jq '.[].name'          # 只有 4 條
gh api repos/TrinityCore/TrinityCore/releases --paginate --jq '.[]|"\(.tag_name) \(.published_at)"' | head -30
gh api repos/TrinityCore/TrinityCore/branches/wotlk_classic \
  --jq '{sha:.commit.sha[0:10],date:.commit.commit.committer.date,msg:.commit.commit.message}'
gh api "search/issues?q=repo:TrinityCore/TrinityCore+3.4.3+created:>2024-09-01&per_page=30" \
  --jq '.total_count,(.items[]|"\(.created_at[0:10]) \(.state) #\(.number) \(.title)")'

# --- §2 fork network 掃描（code search 不索引 fork，必須這樣補）---
for p in 1 2; do gh api "repos/TrinityCore/TrinityCore/forks?sort=stargazers&per_page=100&page=$p" \
  --jq '.[]|"\(.full_name)\t\(.pushed_at)\t\(.stargazers_count)\t\(.default_branch)"'; done >  forkcands.txt
for p in 1 2 3; do gh api "repos/TrinityCore/TrinityCore/forks?sort=newest&per_page=100&page=$p" \
  --jq '.[]|"\(.full_name)\t\(.pushed_at)\t\(.stargazers_count)\t\(.default_branch)"'; done >> forkcands.txt
sort -u forkcands.txt -o forkcands.txt                       # 496
awk -F'\t' '$2 >= "2025-01-01"' forkcands.txt | cut -f1 > recentforks.txt      # 325
cat recentforks.txt | xargs -P 12 -I{} sh -c \
  'b=$(gh api "repos/{}/branches?per_page=100" --jq "[.[].name]|join(\",\")" 2>/dev/null); printf "%s\t%s\n" "{}" "$b"' \
  > forkbranches.txt
grep -iE '3\.4|343|wotlk' forkbranches.txt
# code search markers（只對非 fork 的 default branch 有效）
for q in TDB_full_world_343 TDB_full_hotfixes_343 "54261+filename:auth_database.sql" "%2254261%2C3%2C4%2C3%22"; do
  gh api "search/code?q=$q&per_page=30" --jq '.total_count,(.items[]|"\(.repository.full_name)  \(.path)")'; done
# 證明 code search 不索引 fork：
gh api "search/code?q=54261+repo:RioMcBoo/CypherCoreClassicWOTLK" --jq '.total_count'    # → 0（但 README 有）

# --- §3 Wrathion：下載後逐檔 diff（不採信 README）---
curl -sL -o wrathion.tar.gz https://codeload.github.com/lineagedr/3.4.3_Source/tar.gz/refs/heads/main
tar xzf wrathion.tar.gz
mkdir tc24081 && git -C <repo> archive TDB343.24081 src | tar x -C tc24081
mkdir tc23121 && git -C <repo> archive TDB343.23121 src | tar x -C tc23121
# base 判定（1279 vs 977 → base 是 24081）
a=0;b=0; while IFS= read -r f; do rel=${f#3.4.3_Source-main/}
  [ -f "tc24081/$rel" ] && [ -f "tc23121/$rel" ] || continue
  cmp -s "$f" "tc24081/$rel" && a=$((a+1)); cmp -s "$f" "tc23121/$rel" && b=$((b+1))
done < <(find 3.4.3_Source-main/src -type f); echo "24081=$a 23121=$b"
diff -rq tc24081/src 3.4.3_Source-main/src            # 601 differ / 25 new
diff -rN -u tc24081/src 3.4.3_Source-main/src | awk '/^\+/&&!/^\+\+\+/{a++}/^-/&&!/^---/{d++}END{print a,d}'
# ★ SearchTargets（本篇最重要的一項）
grep -n "template void Spell::SearchTargets" \
  tc24081/src/server/game/Spells/Spell.cpp 3.4.3_Source-main/src/server/game/Spells/Spell.cpp
grep -n "SearchTargets" 3.4.3_Source-main/src/server/game/Spells/Spell.h | tail -1   # :1016 extern template
# 其他建置修正
grep -n "#include" tc24081/src/common/Utilities/Duration.h 3.4.3_Source-main/src/common/Utilities/Duration.h
grep -n "include <chrono>" 3.4.3_Source-main/src/server/database/Updater/UpdateFetcher.cpp
# DK 符文
grep -n "RegenerateRunes" 3.4.3_Source-main/src/server/game/Entities/Player/Player.cpp
git -C <repo> log --oneline e72bde5236..TDB343.24081 --grep=rune -i
# DB2 metadata 瘦身 788 → 718
grep -c '^struct .*Meta$' tc24081/src/server/game/DataStores/DB2Metadata.h \
                         3.4.3_Source-main/src/server/game/DataStores/DB2Metadata.h
# revision_data 的矛盾
curl -s https://raw.githubusercontent.com/lineagedr/3.4.3_Source/main/revision_data.h.in.cmake | grep -i DATABASE
gh api repos/lineagedr/3.4.3_Source/contents --jq '.[].name'          # 沒有 sql
gh api "repos/lineagedr/3.4.3_Source/issues?state=all" --jq '.[]|"#\(.number) \(.state) \(.title)"'
gh api repos/lineagedr/3.4.3_Source/forks --paginate \
  --jq '.[]|"\(.pushed_at) \(.full_name) ★\(.stargazers_count)"' | sort -r

# --- §4 xHashii ---
gh api "repos/lineagedr/3.4.3_Source/compare/main...xHashii:main" \
  --jq '"\(.status) ahead=\(.ahead_by) behind=\(.behind_by)", (.files[]|"\(.status) +\(.additions)/-\(.deletions) \(.filename)")'
curl -s https://raw.githubusercontent.com/xHashii/3.4.3_Source/main/sql/updates/auth/3.4.3/2026_08_10_00_auth.sql
curl -s https://raw.githubusercontent.com/xHashii/3.4.3_Source/main/sql/README.md
curl -s https://raw.githubusercontent.com/xHashii/3.4.3_Source/main/revision_data.h.in.cmake | grep -i DATABASE

# --- §5 CypherCore 線 ---
gh api repos/RioMcBoo/CypherCoreClassicWOTLK \
  --jq '{default_branch,parent:.parent.full_name,stars:.stargazers_count,pushed_at,license:.license.spdx_id}'
gh api "repos/CypherCore/CypherCore/compare/master...RioMcBoo:WOTLK_CLASSIC" \
  --jq '"\(.status) ahead=\(.ahead_by) behind=\(.behind_by)"'
curl -s https://raw.githubusercontent.com/RioMcBoo/CypherCoreClassicWOTLK/WOTLK_CLASSIC/README.md | head -25

# --- §6 rustycore ---
gh api repos/alseif0x/rustycore --jq '{default_branch,stars:.stargazers_count,pushed_at,open_issues:.open_issues_count,license:.license.spdx_id}'
curl -sL https://raw.githubusercontent.com/alseif0x/rustycore/3.4.3/LICENSE | head -5
curl -sL https://raw.githubusercontent.com/alseif0x/rustycore/3.4.3/docs/migration/honest-progress-audit.md | head -50

# --- §7 其他 ---
gh api repos/TrinityCoreLegacy/TrinityCore/branches --paginate --jq '.[]|"\(.name) \(.commit.sha[0:8])"'
gh api "repos/TrinityCore/TrinityCore/compare/92796557f9b0ba3d2d1c7c770f535153154cf83e...0xf4b1:3.4.3" \
  --jq '"\(.status) ahead=\(.ahead_by)"'                                    # identical
curl -sL -o hap.tar.gz https://codeload.github.com/haphert/TrinityCore_wotlk_classic_continued/tar.gz/refs/heads/main
tar xzf hap.tar.gz && diff -rq tc24081/src TrinityCore_wotlk_classic_continued-main/src | grep -c '^Files'   # 0
gh api repos/azerothcore/azerothcore-wotlk/branches --paginate --jq '[.[].name]|join(", ")'
gh api repos/IzomSoftware/wotlk-classic-343-guide/readme --jq '.content' | base64 -d | head -20
```

---

## 10. 對既有筆記的修正／補充

| 位置 | 原文 | 本篇的修正 |
|---|---|---|
| [全景調查](./classic-client-emulator-landscape.md)§1「方法與限制」 | 只記「GitHub code search 只索引 default branch」 | **漏了更致命的一條：code search 完全不索引 fork。** 實測 `54261 repo:RioMcBoo/CypherCoreClassicWOTLK` → 0 筆，但其 README 第三行就是 `3.4.3.54261`。**這解釋了為何前兩次調查都漏掉 `RioMcBoo`。** 補救手段：fork network 逐 repo 列 branch（本篇做了 325 個） |
| [全景調查](./classic-client-emulator-landscape.md)§2.1 | 「`haphert/...` 停在 3.4.3.54261 / 2024-11-11」，語意上暗示它是一條獨立的 3.4.x 工作 | **實測它與 `TDB343.24081` 的 `src/` 內容差異為 0 檔。** 它是逐字重上傳，唯一實質差別是 `realmlist.gamebuild` 預設 54261。兩份社群指南稱它「some helpful patches」是誤導 |
| [論壇筆記](./community-forum-findings.md)§2.2 | Wrathion「與上游 `wotlk_classic` 分支同型」、「未驗證是否 70% playable」 | **補上決定性血緣量測：Wrathion 的 base 是 `TDB343.24081`（1,279/1,878 檔逐位元組相同，vs 23121 的 977），不是 `wotlk_classic`（那是 3.4.4）。** 並補上規模：**601 檔差異 / +57,994 −53,384 / 25 個新檔**，含 DK 符文回復、BattlePay、ArenaTeam、WorldState、ZG/ZA 腳本 |
| [論壇筆記](./community-forum-findings.md)§2.2 | 未提 Wrathion 的 fork 生態 | **補：32 個 fork 中有兩個是活的——`xHashii/3.4.3_Source`（ahead 7，2026-08-12，補上整個 `sql/` 樹 + LFG 修正）與 `Xian55/3.4.3_Source`（ahead 5，2026-08-28）。前者是目前唯一符合「活著的 3.4.3 線」定義的東西。** |
| [論壇筆記](./community-forum-findings.md)§2.3 | `RioMcBoo` 只記了 default branch 與最後 commit | **補上目標 build 的一手驗證與一個關鍵事實：它的 README 指定使用者下載 `TDB_full_343.24081` 並用 TrinityCore 的 extractor。它是我們這條路的下游，不是替代品。** 另補 `compare` 數字：ahead 705 / behind 1362 |
| [論壇筆記](./community-forum-findings.md)§2.4 | `rustycore` 只記 description 與活躍度 | **補：README 明列 `World DB expectation: TDB 343.24081, cache_id = 24081`；且其 `honest-progress-audit.md` 自陳「沒有宣告缺口」只有 **52.86%**、live-runtime 驗證 "low"。** License 也澄清：metadata `NOASSERTION`，但 `LICENSE` 檔是 GPL-3.0 |
| [`cata_classic` 筆記](./cata-classic-backend-option.md)§5.2 第 4 點 | 「2023-11 的原始碼在 2026 工具鏈上能不能編——**完全未驗證，是這條路的第一道閘門**」 | **閘門已通過（我們自己實測建置成功），且本篇找到社群的獨立佐證**：Wrathion 早在 2026-05 就帶了 `SearchTargets` 顯式實例化 + `<chrono>` 修正；兩份社群指南把同一批錯誤列成 `Common Errors`。**「2026 工具鏈」不再是未知風險，是一份已知的小 patch 清單。** |
| [`cata_classic` 筆記](./cata-classic-backend-option.md)§5.2 第 1 點 | 「DK 符文回復被停用——lineage 自述」列為 `TDB343.24081` 的已知未完成項 | **仍成立，但已有現成參考解**：Wrathion `Player.cpp:8680 RegenerateRunes` + `:1614` 的呼叫 + `:25833` 的 `RuneType→POWER_RUNE_*` 對映。**未驗證正確性，但不必從零寫。** |
| [`cata_classic` 筆記](./cata-classic-backend-option.md)§6.5 | 「無論如何，不要 rebase `TDB343.24081`」 | **維持並強化。** 新證據：社群裡最投入的三個獨立專案（Wrathion、xHashii、`0xf4b1`）**沒有一個嘗試往前遷移**，全部選擇「留在 tag 上加 patch」。**這是三次獨立的同一判斷。** |
| [完工評估](./wotlk-classic-completion-assessment.md)§6.2 對照表 | 「上游支援」欄只比較 `3.3.5` 與 `wotlk_classic` | **補第三欄的實況：`TDB343.24081` 路徑的「上游」不是停滯，是不存在；但存在一個由三個單人專案組成的、彼此不互通的參考解答庫（Wrathion / xHashii / rustycore），可查閱不可依賴。** |

---

## 11. 明確記錄「沒做／未驗證」

- **未驗證**：Wrathion 那 601 檔 / 5.8 萬行改動的**正確性**。本篇只做了存在性與規模量測，**未編譯、未執行、未測試任何第三方原始碼**。
- **未驗證**：Wrathion 的目標 build 是否真的是 54261。**從碼無法確認**（`54261` 0 命中，DB2 哨兵註解是 `3.4.3 (51943)`，`sql/` 缺席）。作者未在任何一手文字裡寫出 build 號。
- **未驗證**：Wrathion 的 `revision_data` 指向 `TDB343.23121` 但程式碼 base 是 24081，這個不一致的實際後果。
- **未驗證**：`xHashii` 的 LFG/RDF 修正是否正確；其 world/hotfixes full dump 的內容與來源（repo 外）。
- **未驗證**：`RioMcBoo` 是否有等價的 `*_locale` hotfix 在地化管線（本次未檢查其 C# 對應物）。
- **未驗證**：`rustycore` 的任何執行狀態（僅引用其自陳文件）。
- **未窮舉**：TrinityCore 有 **6,387 個 fork**，本次列舉 496 / 展開 325。非 GitHub 託管者完全未涵蓋。
- **未做**：任何 client / repack / DB dump 下載連結的蒐集或記錄。`xHashii` README 內有 client 連結、Wrathion 的 4 個 SQL dump 在 repo 外——**兩者都只記錄「存在」，不記錄途徑**。
- **未做**：瀏覽器自動化；論壇存取；對本 repo 的任何寫入（未 fetch 外部 remote、未新增 ref、未切換分支、未修改任何追蹤檔案）。所有第三方原始碼下載到 scratchpad，未進入本 repo。
- **推估未驗證**：§8 的所有 cherry-pick 優先度排序是判斷，不是量測。

---

## 12. 實際取用過的來源

**本 repo（唯讀）**
- tag `TDB343.24081`（`92796557f9`）、`TDB343.23121`；`git archive` 出 `src/` 與 `sql/` 到 scratchpad 做 diff
- `git log e72bde5236..TDB343.24081 --grep=rune`
- `origin/cata_classic`（`git grep` 確認其無 `SearchTargets` 顯式實例化）

**GitHub（`gh api` / `curl`，2026-09-04 實際取得）**
- `TrinityCore/TrinityCore`：repo、branches、releases（`--paginate`）、`branches/wotlk_classic`、`search/issues`（3.4.3 / `base:wotlk_classic`）、`forks`（stargazers ×2 頁、newest ×3 頁）、`compare/92796557...0xf4b1:3.4.3`
- 325 個 fork 的 `branches?per_page=100`
- `search/code`：`TDB_full_world_343`、`TDB_full_hotfixes_343`、`54261 filename:auth_database.sql`、`"54261,3,4,3"`、`TDB343`、`EXPANSION_WRATH_OF_THE_LICH_KING CURRENT_EXPANSION wow_classic`
- `search/repositories`：`wotlk classic 3.4.3`、`3.4.3.54261 in:readme`、`wrath classic emulator`
- `lineagedr/3.4.3_Source`：repo、branches、commits、contents、issues、forks、README、`revision_data.h.in.cmake`、**完整 tarball**
- `xHashii/3.4.3_Source`：repo、branches、commits、contents（含 `sql/` 全樹）、README、`compare` vs parent、`sql/base/auth_database.sql`、`sql/updates/auth/3.4.3/*.sql`、`sql/README.md`、`revision_data.h.in.cmake`
- `Xian55/3.4.3_Source`：repo、branches、commits、compare vs parent
- `RioMcBoo/CypherCoreClassicWOTLK`：repo、branches、commits、contents、README、`compare` vs `CypherCore:master`、forks
- `CypherCore/CypherCore`：repo、forks（`--paginate`）
- `alseif0x/rustycore`：repo、README、`LICENSE`、`docs/migration/honest-progress-audit.md`
- `TrinityCoreLegacy/TrinityCore`：repo、branches
- `0xf4b1/TrinityCore`：repo、`commits?sha=3.4.3` / `3.4.3npcbots`
- `haphert/TrinityCore_wotlk_classic_continued`：repo、commits、contents、`revision_data.h.in.cmake`、**完整 tarball**
- `d23monkey/TrinityCore343`：repo、branches、commits
- `IzomSoftware/wotlk-classic-343-guide`、`SyNdicateFoundation/wotlk-classic-343-guide`：repo、README
- `azerothcore/azerothcore-wotlk`：branches
- `Xian55/HermesProxy`、`advocaite/HermesProxy-WOTLK`：repo、分支 tip（覆核用）

**取用失敗**：無。

---
---

# 第二輪深查（2026-09-05）—— 二代 fork、quest 層、GitHub 以外、以及「commit 以外的生命跡象」

> 撰寫日期：2026-09-05（第一輪為 2026-09-04，見本檔上半部）
> **本輪不重述第一輪的結論。** 以下每一節都是第一輪沒查的角度，或是對第一輪的**修正**。
> **本輪新增的既定前提（不重新論證）：** `TDB343.24081` 已用**真實 3.4.3.54261 client 直連跑通**（bnetserver + worldserver，無 proxy）：登入、建角、進世界皆正常。隨後發現並修好了**三個位於官方 TDB343.24081 dump 本身**的資料缺陷（已對 413 MB 原始 SQL 檔核對，且 `updates` 表證明我們的 server 沒有套用過任何東西）：
> **(D1)** `playercreateinfo` 是 retail lineage 的直接沿用（含 race 52 Dracthyr、class 13 Evoker），gnome 與 troll 帶的是**災變後**起始座標 → 角色生在空中／空白地形。
> **(D2)** 四張 quest relation 表是**災變期**的，而 `quest_template` 是 WotLK → `creature_queststarter` 有 **25.6%** 的列指向不存在的任務；**8,543 個任務中有 4,596 個（53.8%）根本沒有任何任務給予者**。5,142 列裡只有 522 列帶 `VerifiedBuild`，而那些 build 全是 retail（45745 / 45338 / 42979 / 42698 / 45114 / 43340），**54261 一個都沒有**。
> **(D3)（決定性）** `disables` 表停用了 **5,242 個任務**（`sourceType=1`），註解寫著 `Deprecated quest` / `Removed in 4.0.3a` / `removed in patch 7.0.3` / `Obsolete quest`——**把「WotLK 之後才移除」套用到一個災變前的世界**。`Player::CanSeeStartQuest` 第一件事就是查 `DisableMgr::IsDisabledFor`，所以在刪掉這些列之前，**沒有任何 NPC 頭上會出現驚嘆號**。
> 來源與規則同第一輪：primary sources、唯讀 git、未使用瀏覽器自動化、不記錄任何 client 或資料庫 dump 的下載途徑。

---

## 13. 二代與三代 fork —— 只多出一個人，而且沒有第三代

第一輪只抽查了 `lineagedr/3.4.3_Source` 的 6 個 fork。**本輪對全部 32 個做了 `compare` 全掃**，並往下再掃一層。

```
gh api repos/lineagedr/3.4.3_Source/forks --paginate --jq '.[]|"\(.full_name)\t\(.default_branch)"' \
| while IFS=$'\t' read -r r db; do
    gh api "repos/lineagedr/3.4.3_Source/compare/main...${r%%/*}:$db" \
      --jq '"\(.status) ahead=\(.ahead_by) behind=\(.behind_by)"'
  done | grep -v 'ahead=0'
```

**32 個 fork 中，`ahead > 0` 的只有 3 個：**

| fork | status | ahead / behind | 最後 push |
|---|---|---|---|
| **`RosemyneH/3.4.3_Source`** | ahead | **12 / 0** | 2026-05-25 |
| `xHashii/3.4.3_Source` | ahead | 7 / 0 | 2026-08-12 |
| `Xian55/3.4.3_Source` | diverged | 5 / 1 | 2026-08-28 |

其餘 **29 個全是 `ahead=0`** 的鏡像。

**再往下一層（三代）：**

| 母體 | fork 數 | 結果 |
|---|---|---|
| `xHashii/3.4.3_Source` | **1** | `DealsBeam/3.4.3_Source`（★0，pushed 2026-08-11）→ `compare` = **behind 1 / ahead 0**。純鏡像，且比母體舊 |
| `Xian55/3.4.3_Source` | **0** | — |
| `RosemyneH/3.4.3_Source` | **0** | — |
| `RioMcBoo/CypherCoreClassicWOTLK` | **7** | **全部 `ahead=0`**，behind 7 / 17 / 17 / 36 / 52 / 973（`DeKaDeNcE` 的 default-branch compare 回 404，其 branch 清單為 `WOTLK_CLASSIC,master`） |

**→ 整個 3.4.3 生態的 fork 樹到二代就停了。沒有任何三代分支帶著新工作。**

### 13.1 ★ 新發現：`RosemyneH/3.4.3_Source`（第一輪漏掉）

| 欄位 | 值（實測） |
|---|---|
| default branch | `main`（唯一分支） |
| License | GPL-2.0 ／ ★ **0** ／ fork **0** ／ open issue **0** ／ description 空白 |
| push | **2026-05-25T11:35:04Z**（**12 個 commit 全部在同一天**） |
| 相對 Wrathion | ahead **12** / behind 0，**69 個檔案** |

**第一輪為什麼漏掉：** 它 pushed 2026-05-25，星數 0、無 description，第一輪只抽查了 6 個 fork 就下判斷。**這是第一輪方法上的實際缺陷，本輪已用全掃補上。**

**12 個 commit 的內容（`gh api compare` 的 `.commits[]`）：**

```
e6faa298 Add local development scripts and configuration for Arch.
c18b1d9e Fix Arch builds against Boost 1.89+ and missing Process headers.
a996a840 Align instance lock loading with characters DB schema.
6477e3cb Register dungeon encounter data on classic instance scripts.
06caca60 Verify characters instance lock schema during local database setup.
a5d886d6 Document verify-instance-db.sh in the local setup README.
cc59a0c0 Fix GCC 16 and Boost 1.89 build failures on Arch.
60966a1a Improve local dev scripts for daemon startup and realm health.
c4651dc4 Add LFG solo queue to match party-only dungeon finder groups.
63d3ae8f Disable heirlooms and Joyous Journeys for alpha login cleanup.
c9d20dc4 Add AIO addon bridge for server-client addon messaging.
0f8ed050 Ignore local SQL database dumps under sql/Databases/.
```

**★ 對我們最有價值的是那兩個建置修正——它是「下一代工具鏈會壞在哪」的預習單。**

`c18b1d9e` 的 commit body（原文）：

> "Skip deprecated Boost.System on Unix, force-include `directory.hpp` for filesystem, fetch Boost.Process into `local/.cache`, and disable jemalloc on Arch."

實作（實際取得檔案內容）：

```cpp
// cmake/boost_filesystem_fix.h  ——  全檔就這兩行
#include <boost/filesystem/directory.hpp>
#include <boost/filesystem/exception.hpp>
```

```cmake
# cmake/macros/ConfigureBaseTargets.cmake:66-72
if(UNIX)
  set(_boost_fs_fix "-include${CMAKE_SOURCE_DIR}/cmake/boost_filesystem_fix.h")
  target_compile_options(trinity-core-interface       INTERFACE "$<$<COMPILE_LANGUAGE:CXX>:${_boost_fs_fix}>")
  target_compile_options(trinity-dependency-interface INTERFACE "$<$<COMPILE_LANGUAGE:CXX>:${_boost_fs_fix}>")
endif()
```

`cc59a0c0` 的 commit body（原文）：

> "Rename BattlePay packet members that shadowed struct types, and load appearances via the **dynamic_bitset constructor instead of the now-private `init_from_block_range`**. Limit the Boost filesystem fix to CXX and tighten local extract/build scripts."

觸及 `BattlePay*`（4 檔）與 **`src/server/game/Entities/Player/CollectionMgr.cpp`（+1/−1）**。

**→ 判讀：這與我們踩到的 `Spell::SearchTargets` 是同一類東西——2023-11 的原始碼 × 2026 的依賴。三個不同的人（我們、Wrathion、RosemyneH）各自獨立撞到不同的一組，合起來就是這條路的完整工具鏈清單：**

| 症狀 | 誰修的 | 對我們的意義 |
|---|---|---|
| `Spell::SearchTargets` 缺顯式實例化 | **我們** + Wrathion（§3.4） | 已解決 |
| `Duration.h` / `UpdateFetcher.cpp` 缺 `<chrono>` | Wrathion + 兩份社群指南（§3.4、§7.2） | 已知 |
| **Boost 1.89 拆分 `boost/filesystem` 標頭** | **RosemyneH（新）** | **若升級 Boost 會撞到；修法是 force-include 兩行** |
| **`dynamic_bitset::init_from_block_range` 變 private** | **RosemyneH（新）** | **同上，落點在 `CollectionMgr.cpp`** |
| Unix 上棄用的 Boost.System / jemalloc on Arch | RosemyneH（新） | 平台相依，macOS 未必適用。**未驗證** |

其餘 commit 對我們**沒有價值或不該拿**：AIO addon bridge（`client-addons/AIO/` + `src/server/game/AIO/` + `custom_aio.cpp`，是自訂 Lua 橋接）、LFG solo queue、`Disable heirlooms and Joyous Journeys`（alpha 期的臨時關閉）、15 支 Arch 專用的 shell script（`scripts/build.sh`、`extract-client.sh`、`fetch-tdb.sh` …）。**唯一可能有旁證價值的是 `6477e3cb` 在 9 個經典副本腳本上補註 dungeon encounter 資料**（Deadmines / Gnomeregan / SunkenTemple / TheStockade / ZulAman / BlackfathomDeeps / RagefireChasm / RazorfenDowns / TheUnderbog）。

**★ 但要說清楚：`RosemyneH` 完全沒有碰 `playercreateinfo`、`disables`、任何 quest relation 表。** 69 個檔案裡沒有一個 `.sql` 資料修正（唯一的 SQL 相關改動是 `.gitignore` 把 `sql/Databases/` 排除）。

---

## 14. ★ quest 層：真的沒有人做過 —— 這是本輪最重要的結論

我們的三個修正（D1/D2/D3）在公開資源裡**找不到任何對應物**。以下是實際跑過的每一種搜法與其結果。

### 14.1 code search（只索引非 fork 的 default branch）

| query | total | 命中內容 |
|---|---|---|
| `creature_queststarter 3.4.3` | **2** | 全部是 `alseif0x/rustycore` 的 `docs/migration/quests.md`、`globals.md` |
| `playercreateinfo 3.4.3` | **12** | **全部 12 筆都是 `alseif0x/rustycore`**（docs 4 筆 + `crates/` 原始碼 8 筆） |
| `"Deprecated quest" disables` | **253** | **一筆 3.4.3 都沒有。** 全是 3.3.5a / 5.4.8 / retail 世代的舊 TDB update：`ProjectSkyfire/SkyFire_548:sql/old/3.3.5a/TDB48_to_TDB49_updates/...`、`LORDofDOOM/MMOCore:sql/old/3.3.5a/2012_08_04_*_world_disables.sql`、`TrinityCore/TrinityCore:sql/old/10.x/world/24021_2024_05_11/...`、`TrinityCore/TDB_4.3.4_NLU` |
| `disables sourceType quest wotlk classic` | 34 | 全是 5.4.8 / pandaria 系的 `Player.h`、aowow、AzerothCore module，**無 3.4.3 資料修正** |
| `playercreateinfo Dracthyr delete` | 14 | 全是 retail `worldserver.conf.dist` 與 `sql/old/10.x/world/22121_2023_02_03/2023_01_02_00_world.sql`（**那正是 Dracthyr 進入 `playercreateinfo` 的那一筆 retail update，也就是 D1 的來源**） |

### 14.2 commit search（`Accept: application/vnd.github.cloak-preview+json`）

| query | total | 命中 |
|---|---|---|
| `disables quest 3.4.3` | 16 | **零筆與 WoW 有關**（wp4nix、dotskel、ScreenDrafts…） |
| `playercreateinfo wotlk classic` | **0** | — |
| `queststarter 3.4.3` | **0** | — |

### 14.3 issue search

| query | total | 命中 |
|---|---|---|
| `TDB343.24081` | **2** | 皆為 `alseif0x/rustycore` 的基礎建設 issue（#255 DB bootstrap、#256 移出啟動時 migration） |
| `3.4.3 quest giver missing` | 4 | 2 筆 HermesProxy（proxy 側的任務 UI 修正）、2 筆 rustycore（架構議題），**沒有一筆在講資料** |
| `wotlk classic playercreateinfo` | 11 | AzerothCore / AscEmu / cMaNGOS 的 3.3.5 舊議題，最新一筆 2026-08-31 與 3.4.3 無關 |

### 14.4 唯一碰到這些表的專案（rustycore）——它只是「讀」，沒有「修」

- `docs/migration/quests.md:164` 把 `SELECT * FROM disables WHERE sourceType = 1` 列為 quest 載入來源之一，**僅此一行，沒有任何關於資料正確性的討論**。
- `docs/migration/EXISTING-CODE-DEFECTS.md` 提到 `DisableMgr::IsDisabledFor` 只有一處（issue #159），談的是**法術**在 arena/BG 情境下的 scope 判定，**與 quest 無關**。
- 它的 `database/migrations/manifest.toml`（實際取得全文，86 行）：

  ```toml
  [[baselines]]
  database = "world"
  marker_table = "version"
  content_version = "TDB 343.24081"
  cache_id = 24081
  ```

  **底下所有 `[[migrations]]` 全部是 `database = "auth"` 或 `"characters"` 的 battle-pet schema（`battle_pet_guid_sequence`、`battle_pet_capacity_locks`、`battle_pet_add_requests`、`battle_pet_account_fences`）。`database = "world"` 的 migration 是零筆。**
- `repos/alseif0x/rustycore/contents/sql/updates/world/wotlk_classic` → **HTTP 404，該路徑不存在。**

### 14.5 覆核 `xHashii` 的三個 world update（本輪確認）

`sql/updates/world/3.4.3/` 三個檔（`2026_08_09_00`、`2026_08_12_00`、`2026_08_12_01`）依 commit 訊息與檔名對應到 `lfg_dungeon_template`、`creature_template_difficulty`（`mobs/npcs having 1HP`）、`areatrigger_teleport`（`dungeon teleport locations`）。**這三張表與 D1/D2/D3 完全不相交。**

### 14.6 結論

> **在所有可被 GitHub 的 code / commit / issue search 觸及的範圍內，沒有任何人公開修正過 `TDB343.24081` 的 `playercreateinfo`、四張 quest relation 表、或 `disables` 的任務列。**
>
> 這不是「我們沒找到」，而是「用三種正交的搜法、九組 query，全部落空，而且每一次落空都能解釋」——`"Deprecated quest"` 的 253 筆命中全部指向舊世代 TDB，正說明**那些列是從舊 TDB 一路繼承下來的歷史沉積，而不是有人針對 3.4.3 加的**。

**→ 我們那三個修正，就目前的公開證據而言，是這條線上的第一份。** 這同時解釋了 §7.2 兩份社群指南的一個空白：它們把「編譯」「建 DB」「TLS 憑證」「REST/SRP 登入」寫得很細，**卻完全沒有提到進了世界之後沒有任務可接**——因為指南作者的驗收點停在登入，和上游 `wotlk_classic` 停在角色選單是同一種天花板。

---

## 15. GitHub 以外的託管 —— 兩個清空、兩個是誠實的盲區

| 平台 | 方法（皆為公開 API，非瀏覽器自動化） | 結果 |
|---|---|---|
| **GitLab** | `GET gitlab.com/api/v4/projects?search=<q>&order_by=last_activity_at`，5 組 query：`wotlk_classic` / `3.4.3 wow` / `trinitycore 3.4.3` / `wrath classic emulator` / `54261` | **只有 `NumboWoW/TrinityCore`**（last_activity **2024-01-14**，description `master = 10.2.0.52808`）。其 `repository/branches` 端點回**空陣列（0 條分支）**→ 是個空殼／未同步的鏡像。`54261` 的 5 筆全是被排程刪除的無關專案。**GitLab：無** |
| **Codeberg / Gitea** | `GET codeberg.org/api/v1/repos/search?q=<q>`，5 組：`wotlk` / `trinitycore` / `wow emulator` / `3.4.3` / `azeroth` | 有一個 **`TrinityCore/TrinityCore` 鏡像**（updated **2026-02-23**，description `master = 12.0.1.66044`），分支 = `master, 3.3.5, wotlk_classic, cata_classic`；其 `wotlk_classic` tip 實測 = **`12c81a6f86` 2025-07-02T03:49:56+02:00** —— **與 GitHub 同一顆 commit**。另有 `Ovahlord/TrinityCore-4.3.4`（2025-07-29）。`3.4.3` query → **0 筆**。**Codeberg：無** |
| **Gitee**（陸港台社群常用） | `GET gitee.com/api/v5/search/repositories?q=<q>`，5 組含中文（`魔兽世界服务端` / `wow服务端`） | 全部回 **HTTP 200 + `[]`**。**對照測試：`q=vue` 同樣回 `[]`** → **這個端點在無 token 時一律回空，不是「沒有結果」。Gitee 本輪未能覆蓋，標示「未驗證」** |
| **Bitbucket** | `GET api.bitbucket.org/2.0/repositories?q=name~"trinitycore"` | **HTTP 410**：`{"message":"CHANGE-2770 - Functionality has been deprecated"}` → **公開 repo 搜尋 API 已下架，無法以 API 覆蓋。標示「未驗證」** |

**→ 誠實的形狀：GitLab 與 Codeberg 已清空（各只剩一個與 GitHub 同步或更舊的鏡像）；Gitee 與 Bitbucket 是本輪打不開的兩扇門。** 俄語圈常用的自架 forge（以及 RaGEZONE 的附件區）同樣不在覆蓋範圍內。

---

## 16. 3.4.4.61581：一年過去，依然是零 —— 而且這次每個 false positive 都有解釋

第一輪說「沒有任何人在做 3.4.4」。本輪重驗，**結論不變，但證據強度提高了**：

| query | total | 逐筆判定 |
|---|---|---|
| `61581 filename:auth_database.sql` | **5** | `TrinityCore/TrinityCore`、`CypherCore/CypherCore`、`Krigsgaldrnet/TrinityCore-Master`、`Olcadoom/DoomCore-dev`、`NetherwingCore/NetherwingCore` —— **全部是 retail core，且命中的是同一段巧合十六進位**。實測本 repo：`origin/master:sql/base/auth_database.sql:1098` = `(59888,'Mac','A64','WoW',0xB64283161581FFC8D5FA9D5EF2689C1D)` ← `61581` 夾在 build **59888** 的金鑰中間。`origin/cata_classic` 的 `grep -c 61581` → **0** |
| `build_auth_key 61581` | **9** | 同上五個 repo 的 `sql/base/auth_database.sql` 與 `sql/old/11.x/auth/24121_2025_03_29/2025_03_26_00_auth.sql`，同一段巧合 |
| `"61581,3,4,4"` | **1** | `lbenz730/ncaahoopR_data` 的一個 NCAA 籃球逐球 CSV |
| repo search `3.4.4.61581 in:readme,description` | 1454 | 排序前 20 筆全是無關的腳本農場／SEO 垃圾 repo |

**唯一真實存在的 3.4.4 產物仍然只有 `TrinityCore/WowPacketParser` 的 `WowPacketParserModule.V3_4_0_45166/UpdateFields/V3_4_4_59817/*`（124 筆命中）與 `wowdev/WoWDBDefs` 的 `.dbd` 定義。兩者都是解析／定義資料，不是伺服器。**

順帶（本輪唯讀 git 實測，佐證 coordinator 的觀察）：

```
git ls-tree -r --name-only origin/wotlk_classic -- sql/updates/world
  sql/updates/world/cata_classic/2025_05_11_01_world.sql
  sql/updates/world/wotlk_classic/2025_05_13_00_world.sql
  sql/updates/world/wotlk_classic/2025_05_13_01_world.sql

第一個檔案內：UPDATE `version` SET `db_version`='TDB 442.25051', `cache_id`=25051 LIMIT 1;
另外兩個 wotlk_classic/ 檔案：無任何 db_version / cache_id 設定
```

**→ `origin/wotlk_classic` 的 world 基線是 Cataclysm 的 TDB 442.25051，不是 TDB343。這條分支從來沒有過 3.4.3 的世界資料。**「有沒有人在 3.4.4 上」與「`wotlk_classic` 能不能給我們東西」是同一個答案：**沒有／不能。**

**這一年變了什麼？——什麼都沒變。** 唯一的差別是：第一輪只說「0 筆」，本輪能對每一個 false positive 指出它為什麼是巧合。

---

## 17. World-DB 專案 —— 沒有人做修正版，但有兩個 DB **release**（★修正第一輪）

### 17.1 沒有任何「修正版 TDB343」專案

| query | total | 結果 |
|---|---|---|
| `TDB_full_world_343 in:name` | **0** | — |
| `TDB343 in:name,description,readme` | 3 | 兩份設定指南（§7.2）+ 一個腳本下載器 |
| `wotlk classic database 3.4.3 in:name,description,readme` | 5 | rustycore、兩份指南，其餘無關 |
| code `"TDB 343"` | 13 | rustycore 的 5 筆 + `haphert` / `d23monkey` 的 **2023-12-20 舊 update 檔**（即 TDB343.**23121** 世代），**無任何修正工作** |

**沒有第三方發行過 TDB343 的 world DB release。**

### 17.2 ★ 修正第一輪 §3.5：Wrathion 的資料庫其實**就在 GitHub 上**

第一輪（承 [論壇筆記](./community-forum-findings.md)§2.2）寫「Wrathion 的資料庫在 repo 之外散布」「不可從 GitHub 取得」。**這句話不正確。** 本輪查 releases 端點：

| repo | tag / name | 發佈 | asset | 大小 | 下載數 | release body |
|---|---|---|---|---|---|---|
| **`lineagedr/3.4.3_Source`** | `databases` / "Databases" | **2026-05-17** | `Databases.7z` | **48,140,818 B** | **114** | "Auth, Characters, Hotfixes, World databases." |
| **`xHashii/3.4.3_Source`** | `DB.2608` / "DB Files" | **2026-08-10** | `world_full_2026_08_10.sql` | **208,414,405 B** | **5** | "Here are the DB Files that need to be manually imported." |
| 〃 | 〃 | 〃 | `hotfixes_full_2026_08_10.sql` | **105,530,958 B** | **6** | 〃 |

（**依任務界線：只記錄其存在與 metadata，不記錄任何下載途徑。**）

其餘 3.4.3 相關 repo 的 releases：`Xian55/3.4.3_Source`、`RosemyneH/3.4.3_Source`、`alseif0x/rustycore`、`RioMcBoo/CypherCoreClassicWOTLK` **全部沒有任何 release**；`TrinityCoreLegacy/TrinityCore` 的 release 最新一筆是 **2019-07-15 的 `434.19071`**（Cataclysm 4.3.4 世代），**與 3.4.3 無關**。

### 17.3 判讀：這兩個 release **不是**我們要的東西

1. **它們不是「修正版 TDB343」，是私人 dump。** 兩者都沒有版本說明、沒有 changelog、沒有 `db_version` 對應，`xHashii` 的 `revision_data.h.in.cmake` 直接把 `_FULL_DATABASE` 改成自家檔名（§4.2）——**等於脫離官方 TDB 的版本鏈。**
2. **`xHashii` 的 `world_full_2026_08_10.sql` 是 208 MB，而我們手上官方 `TDB343.24081` 解開後的 world SQL 是 413 MB。** 差了約一半。**這代表什麼——未驗證**（可能是不同的 dump 選項、可能是刪過內容、可能是不含某些表）。**但無論原因為何，這都是「用來源不明、體積對不上的資料換掉來源可驗證的官方 dump」，方向是錯的。**
3. **下載數說明了規模**：Wrathion 的 DB 114 次、`xHashii` 的 5–6 次。**這不是一個有人在校對的資料集。**

**→ 對我們的意義：D1/D2/D3 三個修正沒有現成的上游可以取代，也沒有更好的 world DB 可以換。留在官方 `TDB_full_343.24081` + 自己的 patch，是唯一來源可驗證的組合。**

---

## 18. commit 以外的生命跡象 —— 用數字說話

任務問「Discord、論壇、2026 年的 release artifact」。以下全部是實跑的公開 API 或 HTTP 狀態碼，**沒有讀取任何論壇內文，也沒有加入任何 Discord**。

### 18.1 Discord（`discord.com/api/v10/invites/<code>?with_counts=true`，公開端點）

| 邀請碼出處 | 解析出的 guild 名稱 | approx_member_count | 線上 |
|---|---|---|---|
| `alseif0x/rustycore` README | **RustyCore** | **8** | **1** |
| `RioMcBoo/CypherCoreClassicWOTLK` README | **Fractal Core (WoW Emulator)** | **43** | **8** |

`lineagedr/3.4.3_Source`、`xHashii/3.4.3_Source`、`RosemyneH/3.4.3_Source` 的 README **完全沒有 Discord 連結**。

**兩點判讀：**

1. **最活躍的 3.4.3 專案（rustycore，昨天還在 commit）的 Discord 只有 8 個人、1 個在線。** 這把「活躍」放回了正確的比例尺——它是一個人的專案加上七個旁觀者。
2. **`RioMcBoo` 的邀請指向一個叫 "Fractal Core (WoW Emulator)" 的社群（43 人 / 8 在線），而這個名字在 GitHub 上查無此物**（`fractalcore` / `FractalCore in:name` 的 11 筆命中全是無關的 ML orchestrator、FPGA 碎形視覺化、AI bot）。**這正是任務說的「只有公告、沒有程式碼」的典型：社群存在，產出不存在。** 它也可能是私有 repo——**未驗證**。

### 18.2 論壇（只取狀態碼，未讀任何內文）

| 站點 | 結果 |
|---|---|
| `forum.ragezone.com/community/wow-development.517/` | **403**（與[論壇筆記](./community-forum-findings.md)§1 一致，未變） |
| `www.ownedcore.com/forums/` | **403** |
| **`emudevs.com`** | **302 → `https://www.hugedomains.com/domain_profile.cfm?d=emudevs.com`（最終 200）** |

**★ EmuDevs 已經不存在了——網域被停放在 HugeDomains 待售。** 這是一個硬事實：任務點名的三個論壇，兩個擋抓取、一個已經死亡。**本輪同樣沒有讀到任何論壇貼文，因此不引用任何論壇文字。**

### 18.3 2026 年的 release artifact

**整條 3.4.3 線在 2026 年只有 §17.2 那兩個 DB release，沒有任何伺服器二進位檔或原始碼 release。**

### 18.4 一個「公告但無程式碼」的樣本：`wowemulation-dev/tavern`

| 欄位 | 值 |
|---|---|
| description | "A Rust replacement for Blizzard Battle.net account services for **digital preservation of retired WoW Classic client builds**" |
| created / pushed | **2026-06-20 / 2026-06-23**（三天） |
| License / ★ | AGPL-3.0 / **0** |
| commit | **3 個**：`ce2277dd chore: initialize project with tooling and README`、`d1735907 docs: rewrite README, rename LICENSE, add protocol docs`、`57479fad chore: fix image` |
| root tree | `.editorconfig .gitattributes .gitignore .markdownlint.jsonc .markdownlintignore .mise.toml CHANGELOG.md LICENSE.md README.md docs/` |

**沒有 `src/`。這是一個 README 加一份協定文件，不是一個專案。** 依任務要求**直說：這只是公告，沒有程式碼。**

**但要公平地記一筆：它所屬的 `wowemulation-dev` 組織在周邊工具上是真的有產出的**（皆為 2026-07～08 的 push）：`warcraft-rs` ★54、`rilua` ★42（WoW client 內 Lua 5.1.1 的零相依 Rust port）、`cascette-rs` ★23（NGDP 工具）、`wow-patcher` ★20、`cascette-py` ★7、`recast-rs` ★8、`protobuf-decompiler` ★2，以及第一輪提過的 `wooly-beast`（4.4.2，★4，2026-05-06）。**這個組織是 client 側／格式側的，不是伺服器側的。**

---

## 19. 第二輪的裁決

**沒有任何東西值得改基。有兩件事值得拿，一件事值得記錄。**

| 行動 | 對象 | 理由 |
|---|---|---|
| **拿（低風險，純建置）** | `RosemyneH/3.4.3_Source` 的 `c18b1d9e` + `cc59a0c0` | Boost 1.89 拆標頭、`dynamic_bitset::init_from_block_range` 變 private。**現在不一定會撞到，但升級 Boost 就會。先把修法記在案，比事後查快。** 落點：`cmake/` 兩個檔 + `CollectionMgr.cpp` |
| **觀望（可能可乾淨合併）** | `xHashii` 的三個 world update | 它們動的是 `lfg_dungeon_template` / `creature_template_difficulty` / `areatrigger_teleport`，**與 D1/D2/D3 零重疊**。但它的 DB 基線是私人 208 MB dump 而非官方 TDB，**要拿只能拿 SQL 的語意、不能拿它的 dump** |
| **不要拿** | 兩個 DB release（Wrathion 48 MB / xHashii 208+105 MB） | 來源不可驗證、體積與官方對不上、下載數 5–114。**換掉官方 TDB 是純粹的退步** |
| **不要拿** | `RosemyneH` 的 AIO bridge / LFG solo queue / heirloom 關閉 / Arch 腳本 | 與目標無關，且是單人一天內寫成、零審閱 |
| **記錄** | 我們的 D1/D2/D3 | §14 顯示這三項在公開資源裡沒有任何對應物。**若要回饋社群，這是這條線上目前唯一有人做過的 world-data 修正。** |

**一句話：第二輪把「有沒有人在維護 3.4.x」這個問題的答案從「有，但很薄」收斂成「有三個人在改程式碼，零個人在改資料」。而我們卡住的地方恰好在資料端——所以外面沒有救兵，也沒有更好的起點。**

---

## 20. 第二輪對第一輪（與更早筆記）的修正

| 位置 | 原文 | 修正 |
|---|---|---|
| **本檔 §3.5**、[論壇筆記](./community-forum-findings.md)§2.2 | Wrathion 的 4 個 SQL dump「**在 repo 之外散布**」「**不在版本控制內、不可從 GitHub 取得**」 | **不正確。** `lineagedr/3.4.3_Source` 有 GitHub **release** `databases`（2026-05-17），asset `Databases.7z` **48,140,818 B、114 次下載**，body 寫明 "Auth, Characters, Hotfixes, World databases."。**它在 GitHub 上，只是不在 git 樹裡。**（不記錄連結） |
| **本檔 §3.1 / §8** | 只抽查了 `lineagedr` 的 6 個 fork 就斷言「活的只有 `xHashii` 與 `Xian55`」 | **漏了 `RosemyneH/3.4.3_Source`（ahead 12，2026-05-25）。** 本輪對全部 32 個 fork 做了 `compare` 全掃，`ahead>0` 的是 **3** 個不是 2 個。**這是第一輪的方法缺陷（以 star / description 做預篩），已修正。** |
| **本檔 §8 的 cherry-pick 表** | 「高優先」只列 Wrathion 的 `SearchTargets` 與 `<chrono>` | **補兩項工具鏈修正（來自 `RosemyneH`）：Boost 1.89 的 `boost/filesystem` force-include、`dynamic_bitset` 改用建構子。** 兩者都是純建置、零行為風險 |
| **本檔 §4.4** | `xHashii` 是「目前唯一符合『活著的 3.4.3 線』定義的東西」 | **維持，但要補上規模**：它的 DB release 下載數是 **5 / 6 次**；它唯一的 fork（`DealsBeam`）是 `behind 1 / ahead 0` 的死鏡像。**「唯一」是對的，「線」這個字則太重了。** |
| **本檔 §6** | rustycore「值得長期追蹤」 | **補上一個把規模放回比例尺的數字：其官方 Discord approx_member_count = 8、線上 1。** 另補：其 `database/migrations/manifest.toml` 以 `TDB 343.24081 / cache_id 24081` 為 baseline，但 **world migration 為零筆**——**它接受了那個有缺陷的 dump，沒有修它。** |
| **本檔 §5** | `RioMcBoo` 只記了 repo 事實 | **補一個 commit 以外的跡象**：其 README 的 Discord 邀請解析為 **"Fractal Core (WoW Emulator)"（43 人 / 8 在線）**，而該名稱在 GitHub 上**查無對應 repo**。社群存在、產出不存在 |
| [全景調查](./classic-client-emulator-landscape.md)§1「未驗證」段 | 提到「已知 gtker 的多個專案已遷往 codeberg.org，這類遷移可能造成漏檢」 | **本輪實查 Codeberg：只有 `TrinityCore/TrinityCore` 鏡像（2026-02-23，`wotlk_classic` tip 與 GitHub 同為 `12c81a6f86`）與 `Ovahlord/TrinityCore-4.3.4`。`3.4.3` query 回 0 筆。GitLab 同樣清空。這個漏檢疑慮對 3.4.3 而言可以關閉；Gitee / Bitbucket 仍是盲區** |
| [論壇筆記](./community-forum-findings.md)§1 | 記錄 RaGEZONE 403 | **補：OwnedCore 亦為 403；EmuDevs 已死——`emudevs.com` 302 導向 `hugedomains.com` 的待售頁面。** 任務點名的三個論壇，兩個擋抓取、一個網域已出售 |
| **本檔 §16（新）** | 第一輪：「沒有找到任何 3.4.4.61581 的第三方實作」 | **維持，並強化**：`61581 filename:auth_database.sql` 的 5 筆全部是同一段巧合十六進位，**本輪在本 repo 內定位到原句**：`origin/master:sql/base/auth_database.sql:1098` `(59888,'Mac','A64','WoW',0xB64283161581FFC8D5FA9D5EF2689C1D)`。`origin/cata_classic` 的 `61581` 命中數為 **0** |

---

## 21. 第二輪的「沒做／未驗證」

- **未驗證（新的盲區）**：**Gitee** —— `api/v5/search/repositories` 在無 token 時對任何 query（含對照組 `vue`）都回 `[]`，**本輪未能覆蓋中文社群的託管**。
- **未驗證（新的盲區）**：**Bitbucket** —— 公開 repo 搜尋 API 回 **HTTP 410（CHANGE-2770 已下架）**，無法以 API 覆蓋。
- **未涵蓋**：俄語圈常見的自架 forge、私有 repo、以及 RaGEZONE / OwnedCore 的附件區（三個論壇本輪一頁內文都沒讀）。
- **未驗證**：`xHashii` 的 `world_full_2026_08_10.sql`（208 MB）為何只有官方 `TDB343.24081` world SQL（413 MB）的一半。**未下載、未開啟、未比對。**
- **未驗證**："Fractal Core (WoW Emulator)" 是否有非公開的程式碼產出（只確認公開 GitHub 上查無對應）。
- **未驗證**：`RosemyneH` 那 12 個 commit 的正確性（包含建置修正在 macOS 上是否同樣適用——它們明文針對 Arch Linux + GCC 16）。**未編譯、未套用。**
- **未驗證**：Discord 的 `approximate_member_count` 是邀請端點回報的近似值，非精確人數。
- **未做**：加入任何 Discord、註冊任何論壇、瀏覽器自動化、下載任何 DB release 或 client。
- **未做**：對本 repo 的任何寫入——本輪僅執行 `git ls-tree` / `git show` / `git grep`（`origin/wotlk_classic`、`origin/master`、`origin/cata_classic`），**未 fetch、未切換分支、未修改任何追蹤檔案**。第三方內容一律留在 scratchpad。

---

## 22. 第二輪實際取用過的來源

**GitHub API（`gh api`）**
- `repos/lineagedr/3.4.3_Source/forks --paginate` 全 32 個 + 對每一個做 `compare/main...<owner>:<branch>`
- `repos/xHashii/3.4.3_Source/forks`、`repos/Xian55/3.4.3_Source/forks`、`repos/RioMcBoo/CypherCoreClassicWOTLK/forks` 及各自的 `compare`
- `repos/RosemyneH/3.4.3_Source`：repo、branches、`compare` 的 `.commits[]` 與 `.files[]`、`commits/c18b1d9e`、`commits/cc59a0c0`
- raw：`RosemyneH` 的 `cmake/boost_filesystem_fix.h`、`cmake/macros/ConfigureBaseTargets.cmake`
- `search/code`：`creature_queststarter 3.4.3`、`playercreateinfo 3.4.3`、`"Deprecated quest" disables`、`disables sourceType quest wotlk classic`、`playercreateinfo Dracthyr delete`、`61581 filename:auth_database.sql`、`build_auth_key 61581`、`"61581,3,4,4"`、`3.4.4.61581`、`V3_4_4_59817`、`"TDB 343"`、`IsDisabledFor repo:alseif0x/rustycore`、`CanSeeStartQuest repo:alseif0x/rustycore`、`"Deprecated quest" repo:alseif0x/rustycore`
- `search/commits`（cloak-preview）：`disables quest 3.4.3`、`playercreateinfo wotlk classic`、`queststarter 3.4.3`
- `search/issues`：`TDB343.24081`、`3.4.3 quest giver missing`、`wotlk classic playercreateinfo`、`repo:alseif0x/rustycore quest`
- `search/repositories`：`TDB_full_world_343 in:name`、`TDB343 in:name,description,readme`、`wotlk classic database 3.4.3`、`343.24081 in:readme`、`3.4.4.61581 in:readme,description`、`fractalcore`、`FractalCore in:name`、`fractal core wow`
- `releases`：`lineagedr/3.4.3_Source`、`xHashii/3.4.3_Source`、`Xian55/3.4.3_Source`、`RosemyneH/3.4.3_Source`、`alseif0x/rustycore`、`RioMcBoo/CypherCoreClassicWOTLK`、`TrinityCoreLegacy/TrinityCore`
- `repos/NetherwingCore/NetherwingCore`、`repos/wowemulation-dev/tavern`（repo/contents/commits）、`orgs/wowemulation-dev/repos --paginate`、`users/RioMcBoo/repos --paginate`
- raw / contents：`alseif0x/rustycore` 的 `docs/migration/quests.md`、`docs/migration/EXISTING-CODE-DEFECTS.md`、`docs/operations/db-bootstrap.md`、`database/manifest` 路徑、`database/migrations/manifest.toml`

**GitHub 以外（公開 API / HTTP，非瀏覽器自動化）**
- `gitlab.com/api/v4/projects?search=…`（5 組）+ `projects/NumboWoW%2FTrinityCore/repository/branches`
- `codeberg.org/api/v1/repos/search?q=…`（5 組）+ `repos/TrinityCore/TrinityCore/branches` 與 `/branches/wotlk_classic`
- `gitee.com/api/v5/search/repositories?q=…`（5 組 + 對照組 `vue`）
- `api.bitbucket.org/2.0/repositories?q=…`（回 410）
- `discord.com/api/v10/invites/mH6ACpGPb2?with_counts=true`、`…/3skVwCay7z?with_counts=true`
- HTTP 狀態碼：`forum.ragezone.com`（403）、`www.ownedcore.com/forums/`（403）、`emudevs.com`（302 → hugedomains.com）

**本 repo（唯讀 git）**
- `git ls-tree -r --name-only origin/wotlk_classic -- sql/updates/world`（3 檔）＋ `git show` 各檔的 `db_version` / `cache_id`
- `git show origin/master:sql/base/auth_database.sql | grep 61581`（第 1098 行）
- `git show origin/cata_classic:sql/base/auth_database.sql | grep -c 61581`（0）

**取用失敗（明確記錄）**：Gitee 搜尋 API（無 token 回空）、Bitbucket 倉庫搜尋 API（HTTP 410 已下架）、RaGEZONE／OwnedCore（403）、EmuDevs（網域已出售）。
