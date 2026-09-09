# 在 TrinityCore 上跑「WotLK Classic」（3.3.5a 內容 + 現代架構 client）

> 撰寫日期：2026-09-03
> 相關筆記：[TrinityCore 專案總覽](./trinitycore-overview.md)
> 來源限定為 primary sources：本 repo 的 git 物件（`origin/*` remote-tracking refs，唯讀指令）、以及 first-party 上游（github.com/TrinityCore/TrinityCore、trinitycore.org / trinitycore.info）。
> 凡未經實際驗證者，本文一律明確標示「**未驗證**」。

---

## 0. 一句話結論（TL;DR）

上游**確實存在** `wotlk_classic` 分支，目標正是 WotLK Classic（client `3.4.4.61581`、CASC product `wow_classic`）——但它是一個 **31 個 commit 的實驗性 spike，2025-07-02 之後就停止開發**。**官方 wiki 直接寫明它 "abandoned"**，GitHub 把它列在 stale 分支頁，官方 repo 描述不提它，官方 issue 範本不接受它，連它自己的 README 標題都還寫著 `TrinityCore (cata_classic)`。**它不是一個可用的伺服器。**

官方 wiki 同時明確回答了你的核心問題：**「3.3.5 … wotlk 3.4 client is incompatible」**——3.4 的 WotLK Classic client **不能**連 `3.3.5` 分支。

**實際可行的答案是 `cata_classic`（client 4.4.2.60895）**：它是完整的現代架構（CASC / `bnetserver` / Battle.net protobuf / DB2 + hotfixes），官方積極維護（近 12 個月 818 個 `src/` commit），而且因為 **Cataclysm 沒有改動諾森德**，它內含**幾乎 100% 的 WotLK 副本與團隊本腳本**（ICC / Ulduar / Naxxramas / ToC …）。這是目前唯一真實可用的「現代架構 client 跑 WotLK 內容」。

若你要的是完整 3.3.5a 內容而非現代 client，則走 **`3.3.5` 分支 + 原版 12340 client**（MPQ + SRP6 舊架構）。

---

## 1. 上游到底有哪些分支（已驗證）

`git ls-remote --heads origin`（2026-09-03 實測）只有四個分支：

| 分支 | 最後 commit 日期 | 最後 commit |
|---|---|---|
| `master` | 2026-08-31 | `04fbee1334` Core/AreaTriggers: Rename ScaleCurve… |
| `cata_classic` | 2026-08-31 | `3bc146f58a` DB/Spells: fix feign death scriptname |
| `3.3.5` | 2026-08-30 | `65f4f04650` Core/DynamicObjects: Fix duration underflow |
| `wotlk_classic` | **2025-07-02** | `12c81a6f86` Core/PacketIO: Fix FeatureSystemGlueScreen structure |

驗證指令（唯讀）：

```
git ls-remote --heads origin
git log -1 --format='%ci %h %s' origin/<branch>
```

`3.3.5` / `cata_classic` / `master` 都在**最近三天內**有 commit；`wotlk_classic` **已停滯約 14 個月**。

---

## 2. 各分支的架構定位（已驗證）

這是最關鍵的一張表。所有欄位皆由 repo 內實際檔案驗證。

| 項目 | `3.3.5` | `cata_classic` | `wotlk_classic` | `master` |
|---|---|---|---|---|
| 目標資料片<br>（`SharedDefines.h` 的 `CURRENT_EXPANSION`） | WotLK (3.3.5a) | `EXPANSION_CATACLYSM` | `EXPANSION_WRATH_OF_THE_LICH_KING` | `EXPANSION_MIDNIGHT` |
| Client build | 12340（原版） | **4.4.2.60895** | **3.4.4.61581** | 12.1.0.69497 |
| Client 資料格式 | **MPQ** | CASC | CASC | CASC |
| 登入 daemon | **`authserver`**（SRP6） | `bnetserver` | `bnetserver` | `bnetserver` |
| Battle.net protobuf（`src/server/proto/`） | ✗ 無 | ✓ | ✓ | ✓ |
| Client 驗證方式 | `build_executable_hash` | **`build_auth_key`** | `build_auth_key` | `build_auth_key` |
| 資料表格式 | **DBC**（`src/server/shared/DataStores/DBCStructure.h`） | DB2 | DB2 | DB2 |
| hotfixes 資料庫 | ✗ 無 | ✓ | ✓ | ✓ |
| 載入的資料表數 | 234 個 DBC | 266 個 DB2 | 266 個 DB2 | 371 個 DB2 |
| `Opcodes.h` 行數 | 1433 | 2067 | 2072 | 2690 |
| 官方 issue 範本可選 | ✓ | ✓ | **✗** | ✓ |
| README 分支表列出 | ✓ | ✓ | **✗** | ✓ |

### 2.1 「現代架構」的具體分界線

用 `git ls-tree` 直接看目錄就能看出架構斷層：

```
git ls-tree --name-only origin/3.3.5:src/tools/extractor_common
  → CMakeLists.txt  mpq_libmpq.cpp  mpq_libmpq.h        ← MPQ

git ls-tree --name-only origin/cata_classic:src/tools/extractor_common
  → CascHandles.cpp  CascHandles.h  DB2CascFileSource.cpp
    DB2CascFileSource.h  ExtractorDB2LoadInfo.h          ← CASC
```

```
git ls-tree --name-only origin/3.3.5:src/server
  → authserver  database  game  scripts  shared  worldserver     ← 無 proto/

git ls-tree --name-only origin/master:src/server
  → bnetserver  database  game  proto  scripts  shared  worldserver
```

CASC product 字串（`src/tools/map_extractor/System.cpp`、`vmap4_extractor`）：

- `cata_classic` / `wotlk_classic`：`char const* CONF_Product = "wow_classic";`
- `master`：`char const* CONF_Product = "wow";`

也就是說 **`cata_classic` 與 `wotlk_classic` 都是「現代架構 core，讀 Classic 的 CASC product」**——正是你要的那個模式。差別只在成熟度。

### 2.2 如何確認分支的目標 client build

`sql/base/auth_database.sql` 的 `build_info` INSERT 是一張歷史總表（從 5875 一路排到現在），**前面數千列在四個分支都一樣**——所以只看開頭會誤判。**要看最後一列**，那才是該分支的目標 build：

```
git show origin/<branch>:sql/base/auth_database.sql | awk '/INSERT INTO `build_info`/,/;$/' | tail -1
```

實測結果：

| 分支 | `build_info` 最後一列 | 解讀 |
|---|---|---|
| `3.3.5` | `(56313,11,0,2,NULL);` | 表本身跟到 11.0.2，但分支實際跑 12340 client |
| `cata_classic` | `(60895,4,4,2,NULL);` | **4.4.2.60895** |
| `wotlk_classic` | `(61581,3,4,4,NULL);` | **3.4.4.61581** |
| `master` | `(69497,12,1,0,NULL);` | 12.1.0.69497 |

這與上游 repo 自己的描述一致（`https://github.com/TrinityCore/TrinityCore`）：

> TrinityCore Open Source MMO Framework (master = 12.1.0.69497, 3.3.5 = 3.3.5a.12340, cata classic = 4.4.2.60895)

**注意這行官方描述裡完全沒有 `wotlk_classic`。**

---

## 3. `wotlk_classic` 分支的真實狀態（已驗證，這是本題核心）

### 3.1 它是什麼

- **從 `cata_classic` 分出**，merge-base 為 `af8de3493f`（2025-05-11）。
- 分支後只有 **31 個 commit**，共動到 **57 個檔案**。
- 作者只有兩人：`funjoker`（23）、`Shauren`（8）。Shauren 是專案首席維護者，代表這是**官方的**實驗，不是外部 fork。
- 起手 commit 是 `Core: Basic update to 3.4.4`（2025-05-12），之後一路 `Core: Updated allowed build to 3.4.4.60430 → 60842 → 60892 → 61075 → 61187 → 61256 → 61581`（最後一次 2025-06-23，由 Shauren 提交）。
- 它確實把 `CURRENT_EXPANSION` 改成 `EXPANSION_WRATH_OF_THE_LICH_KING`（commit `Core/Misc: Update CURRENT_EXPANSION`），並移除不支援的職業（`Core/Misc: Remove unsupported classes`）、把 3.3.5 的 base HP / stamina 資料 port 回來（`Core/GameTables: … port 335 data`）。

### 3.2 為什麼它不能用

1. **已停止開發 14 個月。** 最後 commit 2025-07-02。同期 `cata_classic` 已前進 **1264 個 commit**；`wotlk_classic` 落後的部分永遠沒被 merge 回來。
2. **world DB 還是 Cataclysm 的內容。** 分支後 `sql/` 只新增了 12 個檔案：7 個 auth（純粹是 `build_auth_key` 加新 build）、2 個 hotfixes（其中 `2025_05_13_00_hotfixes.sql` 是 11759 行的一次性 DB2 dump）、**2 個 world**（`2025_05_13_00_world.sql` 419 行 + `2025_05_13_01_world.sql` 802 行）。相對於 world DB 的規模，1221 行等同於零。也就是說：**client 是 3.4.4 的 WotLK Classic，但伺服器餵給它的 quest / creature / loot 全是 4.4.2 Cataclysm 的資料。**
3. **沒有官方 TDB release。** `sql/updates/world/wotlk_classic/` 只有那 2 個檔，代表沒有對應的 world database 發行版可下載。（是否真的沒有 TDB release——**未驗證**，需查 GitHub Releases 頁。）
4. **不被官方支援。** `.github/ISSUE_TEMPLATE/issue.yml:36-42` 與 `.github/ISSUE_TEMPLATE/sql_fix.yml:49-55` 的 `Branch` 下拉選單只有：

   ```
   - 3.3.5
   - master
   - cata_classic
   ```

   `wotlk_classic` **不在其中**——你連 bug 都無處可報。README 的 Build Status 表同樣只有 `master | 3.3.5 | cata_classic`。
5. **README 都沒改。** `git show origin/wotlk_classic:README.md` 第一行仍是 `# … TrinityCore (cata_classic)`——連分支名都沒換掉，說明它從未被當成一個要發布的產品。

**定性：這是一次「把 core 撞到 3.4.4 client 能連上登入畫面並進世界」的技術驗證 spike，不是一個遊戲伺服器。**

### 3.3 上游官方文件怎麼說（決定性證據）

**官方 wiki `https://trinitycore.info/` 首頁原文：**

> At the moment, TrinityCore supports 2 main branches:
> - **3.3.5** targeting original 2010 wow 3.3.5a, you need wow 3.3.5a.12340 client for it to run, wotlk 3.4 client is incompatible. *best for starters*
> - **master** usually targeting current retail version. *a lot of missing content*
>
> **There are also 2 classic branches, but they are abandoned.**
> - **cata_classic** targeting 2024 wow 4.4 retail cata classic, you need wow 4.4.x client for it to run, cata 4.3.4 client is incompatible.
> - **wotlk_classic** targeting **3.4.4.61581 chinese client**.

三個重點：

1. 官方明說「supports **2** main branches」＝ `3.3.5` 與 `master`。
2. 官方明說兩個 classic 分支 **"are abandoned"**。
3. **「wotlk 3.4 client is incompatible」**——官方直接告訴你：3.4 client 不能連 `3.3.5` 分支。這正是你問題的核心，答案是明確的「不行」。
4. `wotlk_classic` 的目標被註明是 **chinese client**。WotLK Classic 在西方伺服器結束後，3.4.4 只在中國版 client 繼續存在——這解釋了為什麼分支凍結在這裡。

> **誠實的但書：** wiki 把 `cata_classic` 也列為 "abandoned"，但這與 git 事實矛盾——`cata_classic` 過去 12 個月有 818 個 `src/` commit、最後 commit 是 2026-08-31。**判斷：wiki 這句對 `wotlk_classic` 準確，對 `cata_classic` 已過時。** 遇到衝突時以 git 紀錄為準。

**官方 wiki Client Setup 頁 `https://trinitycore.info/en/install/Client-Setup`** 只有兩節：「3.3.5a」與「Master, cata_classic (wow 4.4.x)」——**沒有 `wotlk_classic`**。並註明：

> Note: you will need a custom client launcher to connect to master, cata_classic branches servers, i.e. https://arctium.io/wow

（即現代架構分支需要第三方 launcher 才能把 client 導向自架伺服器——這是 Path B 的一個實務前提。）

**GitHub 自己把它標為 stale：** `https://github.com/TrinityCore/TrinityCore/branches/stale` 的**唯一**條目就是 `wotlk_classic`（"Updated Jul 2, 2025"）；`https://github.com/TrinityCore/TrinityCore/branches` 的 Active 區只有 `master` / `cata_classic` / `3.3.5`。

**官方 issue 範本**（`https://github.com/TrinityCore/TrinityCore/blob/master/.github/ISSUE_TEMPLATE/issue.yml`、`.../sql_fix.yml`）的 `Branch` 下拉是 **required**，選項只有 `3.3.5` / `master` / `cata_classic`；且 `config.yml` 設定 `blank_issues_enabled: false`，代表**沒有其他管道**。→ 你在制度上無法對 `wotlk_classic` 開 issue。
（附註：`CONTRIBUTING.md` 位於 **repo 根目錄**而非 `.github/`，且它要求填寫 Branch 但未列舉支援分支。）

### 3.4 維護者的公開說法

沒有找到「wotlk_classic 已死」的正式宣告 issue；官方立場寫在上述 wiki。已實際取得的相關發言：

- `https://github.com/TrinityCore/TrinityCore/discussions/28324`（"Will we update to 3.4.0?"）
  - **funjoker**：「feel free to help :) Currently we are working on a fork …」
  - **Aokromes**（staff）：「**3.4.0 is not real wotlk, is a mix between 3.0 and 2.4.3**」——這是最接近「為何不優先做」的官方理由，且它同時點出一個關鍵事實：**Blizzard 的 WotLK Classic 本身就不是純 3.3.5a**。
  - **funjoker**（較晚）：「supports 3.4.3.52237. **It's very raw and DB is no updated yet (crashes)**」——維護者自己承認 DB 沒更新、會 crash，與第 3.2 節的 git 證據完全吻合。
- `https://github.com/TrinityCore/TrinityCore/issues/28822` — **mdX7**：「Wotlk_classic is not yet updated for patch 3.4.1」
- `https://github.com/TrinityCore/TrinityCore/issues/29572` — 使用者抗議自動標籤：「Why is this labeled invalid as a 3rd party core? wotlk_classic is literally one of the major branches of Trinity」→ 佐證其二等公民地位。
- PR 統計（GitHub search API）：`base:wotlk_classic` 共 **13 個 PR，全部 closed**，最新 #30946（2025-05-14 關閉）。

**未驗證：** 未找到 Shauren / jackpoz / DDuarte 針對 `wotlk_classic` 的公開表態（GitHub search API 無法搜尋留言內文，不排除存在未被開啟的討論串）。
**未驗證：** `community.trinitycore.org` 在本次調查中回傳 **HTTP 500**，無法第一手驗證任何論壇發言，因此本文不引用任何論壇內容。

---

## 4. 三條實際路徑

### Path A — `3.3.5` 分支 + 原版 12340 client

- **給你什麼：** 最成熟、內容最完整的 3.3.5a 體驗。分支至今仍在維護（最後 commit 2026-08-30），有官方 TDB world database，issue 範本接受回報，是社群絕大多數 WotLK 私服的基礎。
- **為什麼不是「現代架構」：** 如第 2 節表格，它是 **MPQ 抽資料、DBC 而非 DB2、`authserver` 走 SRP6 而非 `bnetserver` 走 Battle.net protobuf、沒有 hotfixes DB**。玩家要用 2010 年的 12340 執行檔，不能用 Battle.net App 啟動，也拿不到現代 client 的畫面/UI/效能改進。
- **不能用 WotLK Classic client 混搭。** 官方 wiki 首頁明文：「3.3.5 targeting original 2010 wow 3.3.5a, you need wow 3.3.5a.12340 client for it to run, **wotlk 3.4 client is incompatible**」。這一條直接封死了「用 3.4 client 連 3.3.5 伺服器」的想法。
- **適合：** 你要的是「WotLK 內容」而非「現代 client」。

### Path B — `cata_classic` 分支 + Cataclysm Classic client 4.4.2（**推薦**）

- **給你什麼：** 這是**唯一**「現代架構 client + 舊時代內容 + 官方積極維護」的組合，也是你問題的最佳現成答案。
  - 現代架構全套：CASC、`bnetserver`、Battle.net protobuf 登入、DB2 + hotfixes DB。
  - 官方支援：README 分支表有它、issue 範本有它、CI 有它。
  - **極度活躍**：過去 12 個月 `src/` 有 818 個 commit、`sql/` 有 509 個。近期 commit 包含 `Core/PacketIO: implement CMSG_ARENA_TEAM_*`、`DB/Areatrigger: added entrance data for Scholomance and Blackrock Spire`、`Scripts/Misc: updated dungeon encounter Ids for WotLK dungeons`。
- **重要但誠實的但書：**
  1. 內容是 **Cataclysm（4.4.2）**，不是 3.3.5a。地圖是災變後的東部王國/卡林多，職業設計是 Cata 的，等級上限是 Cata 的。**這不等於 WotLK Classic。**
  2. `Core: Updated allowed build to …` 系列在 `cata_classic` 上的最後一次是 **2025-05-21 的 4.4.2.60895**。之後一年多沒有再 bump build——與 Blizzard 的 Cataclysm Classic 已進入 MoP Classic 一致。意思是：**這個分支現在鎖在 4.4.2.60895，你必須弄到那個特定版本的 client 資料**。之後的 commit 都是內容/core 修正，不是 client 版本追隨。（Blizzard 官方現在是否還能下載到 4.4.2 client——**未驗證**。）
  3. **需要第三方 launcher。** 現代架構分支的 client 走 Battle.net 登入，官方 wiki（`https://trinitycore.info/en/install/Client-Setup`）註明：「you will need a custom client launcher to connect to master, cata_classic branches servers, i.e. https://arctium.io/wow」。這是 Path B 的實務前提，也是 Path A 沒有的額外步驟（12340 client 只要改 `realmlist.wtf`）。
  4. 官方 wiki 把 `cata_classic` 也寫成 "abandoned"（見 3.3 節），但 git 事實不支持這個說法。**若你在論壇/wiki 看到這句，請以 commit 紀錄為準。**
  3. **好消息，而且比預期大得多**：`cata_classic` 的 `src/server/scripts/Northrend/`（WotLK 內容）有 **191 個檔案**，而 `3.3.5` 分支同目錄是 **193 個**——幾乎是**完整的 WotLK 副本 / 團隊本腳本套件**（Icecrown Citadel、Ulduar、Naxxramas、Trial of the Crusader…）都已經在現代架構的分支上跑。

     ```
     git ls-tree -r --name-only origin/cata_classic -- src/server/scripts/Northrend | wc -l   # 191
     git ls-tree -r --name-only origin/3.3.5        -- src/server/scripts/Northrend | wc -l   # 193
     ```

     逐檔比對後，`3.3.5` 有而 `cata_classic` 沒有的**只有兩個檔**：`isle_of_conquest.cpp` 與 `boss_ioc_horde_alliance.cpp`（征服之島戰場，在 `cata_classic` 上已移到 `Battlegrounds/`）。反向沒有任何檔案缺少。**換言之 WotLK 的 PvE 副本腳本覆蓋率實質上是 100%。**

     而且維護者**現在仍在修**：`2026-08-28 Scripts/Misc: updated dungeon encounter Ids for WotLK dungeons`。

     `cata_classic` 的 `Northrend/` 子目錄實際內容：

     ```
     AzjolNerub  ChamberOfAspects  CrusadersColiseum  DraktharonKeep  FrozenHalls
     Gundrak  IcecrownCitadel  Naxxramas  Nexus  Ulduar  UtgardeKeep
     VaultOfArchavon  VioletHold
     zone_borean_tundra.cpp  zone_dalaran.cpp  zone_dragonblight.cpp
     zone_grizzly_hills.cpp  zone_howling_fjord.cpp  zone_icecrown.cpp
     zone_sholazar_basin.cpp  zone_storm_peaks.cpp  zone_wintergrasp.cpp
     zone_zuldrak.cpp
     ```

     **關鍵洞察：Cataclysm 重畫的是東部王國與卡林多，它沒有動諾森德，也沒有動外域。** 所以 4.4.2 client + `cata_classic` 上的**諾森德開放世界（68–80 級）、全部 WotLK 5 人本與團隊本（ICC / Ulduar / Naxxramas / ToC / VoA / 冬擁湖）都是原汁原味的 WotLK 內容**，而且不只是地圖存在——連 zone 腳本都在。**這是「現代架構 client 跑 WotLK 內容」目前唯一真實可用的答案。** 妥協點是 1–60 級的舊世界是災變後版本、職業/天賦是 Cata 的設計。

### Path C — 自己把 3.3.5 內容 port 到現代 client core

**結論先講：這是多人年級（multi-person-year）的工程，且 `wotlk_classic` 已經證明「起步很快、收尾無望」。** 官方兩位核心開發者花了 7 週做到 31 個 commit 就停了。

具體要做的事，依已驗證的差異列舉：

1. **Opcode / 協定表**：`src/server/game/Server/Protocol/Opcodes.h` 從 1433 行（3.3.5）變成 2072 行（wotlk_classic）。每一個 opcode 的**封包結構**都要重寫——`wotlk_classic` 的 commit 記錄就是一連串 `Core/PacketIO: Update <X> to 3.4.4`（`QueryCreatureResponse`、`AuraDataInfo`、`FeatureSystemStatus`、`SMSG_ENUM_CHARACTERS_RESULT`、`SMSG_ENTER_ENCRYPTED_MODE`、`BuildMovementUpdate`…），而它只做完了極少數。
2. **DBC → DB2**：3.3.5 有 234 個 DBC store（`DBCStores.cpp`），現代 core 是 266～371 個 DB2 store（`DB2Stores.cpp`）。結構定義從 `src/server/shared/DataStores/DBCStructure.h` 換到 `src/server/game/DataStores/DB2Structure.h`（4142～5153 行）。外加 `src/common/DataStores/DB2Meta.h` 的 metadata、`src/tools/extractor_common/ExtractorDB2LoadInfo.h`（`wotlk_classic` 光這一個檔就改了 204 行）。
3. **CASC 抽取管線**：`map_extractor` / `vmap4_extractor` / `mmaps_generator` 全部要對準新 client 的檔案佈局與 product 名稱。
4. **登入流程**：從 `authserver` + SRP6 換成 `bnetserver` + Battle.net protobuf（`src/server/proto/Client/`、`Login/`、`RealmList/`）、REST/HTTPS 登入、`build_auth_key`、以及 `SMSG_ENTER_ENCRYPTED_MODE` 的封包加密。
5. **hotfixes 資料庫**：3.3.5 完全沒有這一層。要新增 `sql/base/dev/hotfixes_database.sql`、`HotfixDatabase.cpp/.h`、以及全套 `PrepareStatements`。
6. **world DB schema 幾乎不相容**（這是最被低估的一項）。實測 `sql/base/dev/world_database.sql`：3.3.5 有 186 張表、`master` 有 247 張。
   - **只在 master**（87 張）：`areatrigger*`、`conversation_*`、`playerchoice*`（12 張）、`quest_objectives*`、`creature_template_difficulty`、`creature_template_model`、`spawn_tracking_*`、`waypoint_path` / `waypoint_path_node`、`scenario*`、`serverside_spell*`、`phase_area`、`world_safe_locs`…
   - **只在 3.3.5**（26 張）：`item_template`、`item_template_locale`、`broadcast_text`、`spell_bonus_data`、`spell_ranks`、`spell_dbc`、`spelldifficulty_dbc`、`player_levelstats`、`waypoint_data`、`instance_encounters`、`achievement_criteria_data`、`warden_checks`…
   - 注意 **`item_template` 在現代 core 根本不存在**（物品資料移到 DB2/hotfixes），**`spell_ranks` / `spell_bonus_data` 也消失了**（法術系統重寫）。這代表 3.3.5 的 TDB **不能**匯入現代 core，而要「轉換」等於要重建整個 WotLK 內容資料庫。
7. **法術/移動系統**：3.3.5 有法術等級（`spell_ranks`）與 rank-based 設計，現代 core 沒有；移動封包（`BuildMovementUpdate`）、`auraSlot` 寬度（`wotlk_classic` 有一個 commit 專門把它改成 `uint16`）等都不同。

換句話說：**core 那一半（1~5、7）是 `wotlk_classic` 已示範「做得動但做不完」的部分；而第 6 項（world DB）連 `wotlk_classic` 都完全沒碰。** 那才是真正的工作量所在，而且它不是寫程式，是重建一整個內容資料庫。

---

## 5. 第三方 fork

> ⚠️ **以下並非 TrinityCore 官方來源，本文不背書、未評估其品質 / 安全性 / 授權合規性。** 僅為說明「外面有沒有人已經做到」而列出。

- `github.com/haphert/TrinityCore_wotlk_classic_continued` — 自述 `wotlk_classic = 3.4.3.54261`，最後 push **2024-11-11**。**比上游的 3.4.4.61581 還舊、build 還低。**
- `github.com/mdX7/TrinityCore`（`wotlk_classic` 分支）— funjoker 在 discussion 28324 提到當時工作在此進行；該成果後來已併入上游。

**關鍵結論：本次調查找到的第三方 fork，沒有任何一個比（已停滯的）上游 `wotlk_classic` 更新。** 也就是說「找個 fork 就能跑 WotLK Classic」這條路目前不存在。

（本節僅涵蓋調查中實際遇到的 fork，**非系統性窮舉**——可能有未被發現者。若要評估任何 fork，請檢查 commit 活躍度、是否附帶對應的 world DB，以及 GPL-2.0 合規性，見總覽筆記第 2 節。）

---

## 6. 建議

1. **想要「現代 client + 官方維護 + 現在就能跑」→ 走 Path B（`cata_classic`）**，接受開放世界是 Cataclysm 4.4.2 而非 3.3.5a。這是唯一成熟的「現代架構跑舊內容」路線，而且它**已經內含幾乎完整的 WotLK 副本腳本（191 vs 3.3.5 的 193 個檔案）**——如果你要的「WotLK Classic 體驗」重心在副本/團隊本，這條路現在就能給你八成。
2. **想要「真正的 3.3.5a 內容 + 完整度」→ 走 Path A（`3.3.5`）**，接受它是 MPQ/DBC/SRP6 舊架構、要用 12340 client。
3. **不要期待 `wotlk_classic`。** 它是官方的、但已冷凍 14 個月、被官方 wiki 明列為 abandoned、被 GitHub 標為 stale、沒有 world DB、不在 issue 範本、README 都沒改名，維護者自己說「very raw and DB is no updated yet (crashes)」。可以 `git log origin/cata_classic..origin/wotlk_classic` 當作「要做這件事需要動哪些地方」的優質參考清單，但僅止於此。
4. **也不要期待第三方 fork。** 調查中找到的 fork 沒有一個比上游 `wotlk_classic` 更新（見第 5 節）。
5. **Path C 只在你有團隊 + 多年時間時才成立**，且瓶頸不在 core 程式碼，在於重建 world database。
6. **順帶一提值得知道的事實：** staff 成員 Aokromes 指出「3.4.0 is not real wotlk, is a mix between 3.0 and 2.4.3」。**Blizzard 的 WotLK Classic 本身就不是純粹的 3.3.5a**，所以「用現代 client 重現 3.3.5a」這個目標，即使做出來也不會等於 3.3.5a 分支給你的體驗。這是評估投入前該先想清楚的。

### 快速決策

| 你最在意的是 | 選 |
|---|---|
| WotLK 副本/團隊本 + 現代 client 畫質與效能 | **Path B `cata_classic`** |
| 完整正統 3.3.5a 世界、任務、職業手感 | **Path A `3.3.5`** |
| 一定要 3.3.5a 內容**且**現代 client | 現階段**無解**，除非投入 Path C 的多年工程 |

---

## 7. 驗證方式（全部唯讀，未切換 working tree）

```
git ls-remote --heads origin
git log -1 --format='%ci %h %s' origin/wotlk_classic
git merge-base origin/wotlk_classic origin/cata_classic
git rev-list --count origin/wotlk_classic..origin/cata_classic   # 1264
git rev-list --count origin/cata_classic..origin/wotlk_classic   # 31
git shortlog -sn origin/cata_classic..origin/wotlk_classic
git diff --stat origin/cata_classic...origin/wotlk_classic -- sql
git ls-tree --name-only origin/3.3.5:src/tools/extractor_common
git ls-tree --name-only origin/master:src/server
git show origin/wotlk_classic:src/server/game/Miscellaneous/SharedDefines.h | grep CURRENT_EXPANSION
git show origin/master:.github/ISSUE_TEMPLATE/issue.yml | sed -n '36,42p'
git show origin/<branch>:sql/base/auth_database.sql | awk '/INSERT INTO `build_info`/,/;$/' | tail -1
git ls-tree -r --name-only origin/cata_classic -- src/server/scripts/Northrend | wc -l
```

---

## 8. 實際取用過的 first-party 來源

- `https://github.com/TrinityCore/TrinityCore` — repo 描述列出三個分支的目標 build，不含 `wotlk_classic`
- `https://github.com/TrinityCore/TrinityCore/branches` — Active：`master` / `cata_classic` / `3.3.5`
- `https://github.com/TrinityCore/TrinityCore/branches/stale` — 唯一條目：`wotlk_classic`（Updated Jul 2, 2025）
- `https://github.com/TrinityCore/TrinityCore/blob/master/.github/ISSUE_TEMPLATE/issue.yml`
- `https://github.com/TrinityCore/TrinityCore/blob/master/.github/ISSUE_TEMPLATE/sql_fix.yml`
- `https://github.com/TrinityCore/TrinityCore/blob/master/.github/ISSUE_TEMPLATE/config.yml`（`blank_issues_enabled: false`）
- `https://github.com/TrinityCore/TrinityCore/blob/master/CONTRIBUTING.md`（位於根目錄，非 `.github/`）
- `https://github.com/TrinityCore/TrinityCore/discussions/28324` — funjoker、Aokromes 發言
- `https://github.com/TrinityCore/TrinityCore/issues/28822` — mdX7 發言
- `https://github.com/TrinityCore/TrinityCore/issues/29572`
- `https://trinitycore.info/` — 官方 wiki 首頁，"There are also 2 classic branches, but they are abandoned."
- `https://trinitycore.info/en/install/Client-Setup` — client 設定，含 custom launcher 說明

**取用失敗：** `community.trinitycore.org`（HTTP 500），故本文不含任何論壇引用。
