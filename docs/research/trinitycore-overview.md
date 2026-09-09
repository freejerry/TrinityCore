# TrinityCore 專案總覽（研究筆記）

> 撰寫日期：2026-09-01
> 來源限定為 primary sources：本 repo 內檔案，以及 first-party 上游（github.com/TrinityCore/TrinityCore、trinitycore.org / trinitycore.info）。
> 所有引用皆標示檔案路徑（含行號）。

---

## 1. 專案是什麼、目的與範圍

- TrinityCore 是一個以 C++ 為主的 **MMORPG 伺服器框架**（server emulator），衍生自 *MaNGOS*（Massive Network Game Object Server），長期對原始碼進行最佳化、清理，並改善遊戲內機制與功能。來源：`README.md:33-40`（"TrinityCore is a *MMORPG* Framework based mostly in C++. It is derived from *MaNGOS*..."）。
- 完全開源，鼓勵社群參與；程式修正以 GitHub Pull Request 提交。來源：`README.md:41-45`。
- 官方站點：Website https://www.trinitycore.org、Wiki https://www.trinitycore.info、Forums https://talk.trinitycore.org/、Discord https://discord.trinitycore.org/。來源：`README.md` "Links" 段落。
- 範圍不只伺服器程式：還包含 **資料庫 schema 與 SQL 更新**（`sql/`）、**客戶端資料抽取工具**（`src/tools/`）、以及大量 **腳本**（`src/server/scripts/`，依遊戲大陸/資料片分目錄）。

## 2. 授權與實務影響

- 授權為 **GPL 2.0**。來源：`README.md`（"## Copyright / License: GPL 2.0 / Read file [COPYING]"）、`COPYING:1-2`（"GNU GENERAL PUBLIC LICENSE Version 2, June 1991"）、另附 `doc/GPL-2.0.txt`。
- 每個原始碼檔案的標準檔頭寫明 "either version 2 of the License, or (at your option) any later version"，即 **GPL-2.0-or-later**。來源：`doc/FileHeaders.txt`（樣板全文）、實例 `src/server/database/Database/DatabaseLoader.h:1-16`。
- 實務影響：
  - 任何以此為基礎的 **散布版本（distribution）** 必須同樣以 GPL 授權並提供原始碼；私自修改自用（自架、不散布）不觸發散布義務。
  - 靜態/動態連結進 core 的自製模組（例如自訂 script library）在散布時通常被視為衍生作品，需一併 GPL 開源。
  - 不得移除或改寫檔頭授權聲明；新增檔案必須套用 `doc/FileHeaders.txt` 的檔頭。
  - CMake 檔案採用另一段較寬鬆的「special exception」聲明（允許自由複製/散布並保留聲明），見 `CMakeLists.txt:1-9`。
  - 注意：本專案僅提供伺服器端程式，**不含 Blizzard 的客戶端資料**；地圖/模型資料必須由使用者自有的遊戲客戶端以 `src/tools/` 抽取。

## 3. 高階架構：獨立執行檔與彼此通訊方式

建置產物由 `cmake/options.cmake:11`（`option(SERVERS "Build worldserver and bnetserver" 1)`）與 `cmake/options.cmake:36`（`option(TOOLS ...)`）控制。

### 3.1 `bnetserver`（登入 / Battle.net 服務）
- 原始碼：`src/server/bnetserver/`（`Main.cpp`、`Server/`、`Services/`、`REST/`）。
- 職責：Battle.net 帳號驗證、realm 列表、產生 realm join ticket。
  - `src/server/bnetserver/Services/GameUtilitiesService.cpp:88-89` 處理 `Command_RealmListTicketRequest_v1` → `GetRealmListTicket`。
  - 同檔 `:251-259` 的 `JoinRealm` 呼叫 `sRealmList->JoinRealm(...)`。
- 監聽埠：Battle.net TCP `1119`（`src/server/bnetserver/bnetserver.conf.dist:56` `BattlenetPort = 1119`）、登入 REST/HTTPS `8081`（`bnetserver.conf.dist:77` `LoginREST.Port = 8081`）。
- 只連 **auth 資料庫**：`src/server/bnetserver/bnetserver.conf.dist:248` `LoginDatabaseInfo = "127.0.0.1;3306;trinity;trinity;auth"`。
- 附帶自簽憑證檔 `bnetserver.cert.pem` / `bnetserver.key.pem`（同目錄），供 HTTPS 登入流程使用。

### 3.2 `worldserver`（遊戲世界伺服器）
- 原始碼：`src/server/worldserver/`（`Main.cpp`、`CommandLine/`、`RemoteAccess/`、`TCSoap/`），遊戲邏輯本體在 `src/server/game/`。
- 監聽埠：世界連線 `8085`（`src/server/worldserver/worldserver.conf.dist:166` `WorldServerPort = 8085`）、遠端主控台 RA `3443`（`:3195`）、SOAP `7878`（`:3224`）。
- 連四個資料庫（見第 6 節）：`worldserver.conf.dist:115-118` 等。

### 3.3 兩者如何通訊
- **沒有直接的 server↔server socket**：兩支 daemon 透過 **共享的 auth 資料庫** 與 **client 攜帶的 ticket** 間接協作。
  - bnetserver 認證後把帳號/session 狀態寫入 auth DB，並把 realm 位址與 ticket 交給 client。
  - client 改連 worldserver 的 8085；worldserver 於 `src/server/game/Server/WorldSocket.cpp:640`（`LOGIN_SEL_ACCOUNT_INFO_BY_NAME`）、`:897`（`LOGIN_SEL_ACCOUNT_INFO_CONTINUED_SESSION`）向 auth DB 查驗帳號/續連 session，並在 `:762` 檢查 client 要求的 realm id 是否與本 realm 設定相符。
- realm 清單資料存於 auth DB 的 `realmlist` 表（`sql/base/auth_database.sql`，見第 7 節 diff）。
- 額外對外介面：worldserver 的 **SOAP**（`src/server/worldserver/TCSoap/`，依賴 gSOAP）與 **RA/遠端主控台**（`src/server/worldserver/RemoteAccess/`）。

### 3.4 離線工具（`src/tools/`）
`src/tools/CMakeLists.txt:11-15` 列出五個子專案：
- `extractor_common` — 共用抽取程式碼（CASC 讀取等）。
- `map_extractor` — 從客戶端抽出地圖與 DB2 資料。
- `vmap4_extractor` / `vmap4_assembler` — 抽出並組裝碰撞（vmap）資料。
- `mmaps_generator` — 產生 Recast/Detour 導航網格（mmaps）。
輔助腳本：`contrib/extractor.sh`、`contrib/extractor.bat`。

## 4. `src/` 目錄配置

`src/` 頂層：`CMakeLists.txt`、`common`、`genrev`、`server`、`tools`（來自 `ls src`）。

- **`src/common/`** — 不依賴遊戲邏輯的基礎設施：`Asio`（網路 I/O）、`Collision`、`Configuration`、`Containers`、`Cryptography`、`DataStores`（DB2 metadata，見 `src/common/DataStores/DB2Meta.h`）、`Debugging`、`Encoding`、`Logging`、`Metric`、`Threading`、`Time`、`Utilities`、`PrecompiledHeaders`、`GitRevision.cpp/.h`、`Banner.cpp/.h`。
- **`src/genrev/`** — 產生 git revision 資訊（配合 `cmake/genrev.cmake` 與 `revision_data.h.in.cmake`）。
- **`src/server/game/`** — 遊戲邏輯核心，依領域分子目錄：`Accounts`、`Achievements`、`AI`、`AuctionHouse`、`AuctionHouseBot`、`Battlefield`、`Battlegrounds`、`BattlePets`、`BlackMarket`、`Calendar`、`Chat`、`Combat`、`Conditions`、`DataStores`、`DungeonFinding`、`Entities`、`Garrison`、`Globals`、`Grids`、`Groups`、`Guilds`、`Handlers`、`Instances`、`Loot`、`Mails`、`Maps`、`Movement`、`OutdoorPvP`、`Petitions`、`Phasing`、`Pools`、`Quests`、`Reputation`、`Scenarios`、`Scripting`、`Server`、`Services`、`Skills`、`Spells`、`Storages`、`Support`、`Texts`、`Transmog`、`Weather`、`World` 等。
- **`src/server/shared/`** — worldserver 與 bnetserver 共用：`DataStores`、`Dynamic`、`IpLocation`、`JSON`、`Networking`、`Packets`、`Realm`（含 `ClientBuildInfo.h`）、`Secrets`。
- **`src/server/database/`** — MySQL 存取層：`Database/`（`DatabaseWorkerPool`、`MySQLConnection`、`PreparedStatement`、`QueryCallback`、`Transaction`、`Field*` 等）、`Logging/`、`Updater/`（`DBUpdater`、`UpdateFetcher`）。
- **`src/server/proto/`** — Protocol Buffers 服務定義：`Client/`、`Login/`、`RealmList/`、`ServiceBase.cpp/.h`、`BattlenetRpcErrorCodes.h`（Battle.net RPC 用；產生器腳本見 `contrib/protoc-bnet`）。
- **`src/server/scripts/`** — 依地區/資料片分的內容腳本：`EasternKingdoms`、`Kalimdor`、`Outland`、`Northrend`、`Pandaria`、`Draenor`、`BrokenIsles`、`Argus`、`KulTiras`、`Zandalar`、`Shadowlands`、`DragonIsles`、`KhazAlgar`、`QuelThalas`、`Karesh`、`ExilesReach`、`Maelstrom` 以及 `Battlegrounds`、`Battlefield`、`OutdoorPvP`、`Commands`、`Events`、`Pet`、`Spells`、`World`、`Custom`；載入器由 `ScriptLoader.cpp.in.cmake` 產生。
- **`src/server/bnetserver/`、`src/server/worldserver/`** — 兩支 daemon 的進入點與設定範本（見第 3 節）。
- **`src/tools/`** — 見 3.4。

其他頂層目錄：`dep/`（打包/尋找的第三方相依）、`sql/`、`doc/`、`contrib/`、`cmake/`、`tests/`（Catch2 測試：`tests/common/`、`tests/game/`）。

## 5. 建置系統、語言標準與主要相依

- **建置系統**：CMake，最低版本 **3.24**（`CMakeLists.txt:11`）。禁止 in-source build（`CMakeLists.txt:14-15`）。預設建置型別 `RelWithDebInfo`（`CMakeLists.txt:40,43`）。
- **語言標準**：**C++20**，且關閉編譯器擴充（`cmake/macros/ConfigureBaseTargets.cmake:15-16`：`set(CMAKE_CXX_EXTENSIONS OFF)` / `set(CMAKE_CXX_STANDARD 20)`）。
- **最低編譯器版本**：
  - GCC **11.1.0**（`cmake/compiler/gcc/settings.cmake:1`）
  - Clang **11.0.0**；AppleClang 則為 **12.0.5**（`cmake/compiler/clang/settings.cmake:3,7`）
  - MSVC **19.32**（Visual Studio 2022 17.2）（`cmake/compiler/msvc/settings.cmake:1-2`）
- **主要外部相依**：
  - **Boost**：MSVC 需 **1.78**，其他平台 **1.74**（`dep/boost/CMakeLists.txt:42,44`）；使用元件 `filesystem`、`program_options`、`regex`、`locale`（`dep/boost/CMakeLists.txt:68-71`）。（`dep/PackageList.txt:3-5` 仍寫 1.55，已過時，以 CMake 為準。）
  - **OpenSSL 3**（`dep/openssl/CMakeLists.txt:14`：`find_package(OpenSSL 3 REQUIRED COMPONENTS Crypto SSL)`）。
  - **MySQL client**（`CMakeLists.txt:72` `find_package(MySQL OPTIONAL_COMPONENTS binary)`；尋找邏輯 `cmake/macros/FindMySQL.cmake`，支援 MySQL 與 MariaDB）。
- **內附/列管相依版本**（`dep/PackageList.txt`）：fmt **12.0.0**（:13）、zlib **1.3.1**（:41）、jemalloc **5.3.1**（:21）、gSOAP **2.8.141**（:45）、utf8-cpp **4.0.8**（:37）、Catch2 **v3.15.2**（:58）、protobuf **v2.6.1**（:70）、efsw **1.5.0+**（:9）、G3D 9.0 r4036（:17）、SFMT、recastnavigation（TrinityCore fork，:47-50）、argon2（:52-53）、CascLib（:60-62）、rapidjson（:64-66）、short_alloc（:72-73）。
- **重要 CMake 選項**（`cmake/options.cmake`）：`SERVERS`(:11)、`TOOLS`(:36)、`USE_SCRIPTPCH`/`USE_COREPCH`(:37-38)、`WITH_DYNAMIC_LINKING`(:39)、`WITH_FILESYSTEM_WATCHER`(:40)、`WITH_WARNINGS`(:53)、`WITH_WARNINGS_AS_ERRORS`(:54)、`WITH_COREDEBUG`(:55)、`WITHOUT_METRICS`(:56)、`WITH_DETAILED_METRICS`(:57)、`COPY_CONF`(:58)、`WITHOUT_GIT`(:61)、`BUILD_TESTING`(:62)、`USE_LD_GOLD`(:65)。
- **測試**：Catch2；由 `CMakeLists.txt:86-92` 的 `include(CTest)` + `add_subdirectory(tests)` 掛入，預設關閉（`BUILD_TESTING` 預設 0）。

## 6. 使用的資料庫與各自角色

四個 MySQL schema，型別旗標定義於 `src/server/database/Database/DatabaseLoader.h:45-55`（`DATABASE_LOGIN=1`、`DATABASE_CHARACTER=2`、`DATABASE_WORLD=4`、`DATABASE_HOTFIX=8`、`DATABASE_MASK_ALL=15`）：

| DB | 設定鍵 | 角色 |
|---|---|---|
| `auth` | `LoginDatabaseInfo`（`worldserver.conf.dist:115`；`bnetserver.conf.dist:248`） | 帳號、Battle.net 帳號、realmlist、允許的 client build（`build_info`、`build_auth_key`）、封鎖/停權。**唯一同時被兩支 daemon 使用的 DB** |
| `world` | `WorldDatabaseInfo`（`worldserver.conf.dist:116`） | 靜態遊戲內容：生物/物件 spawn、任務、掉落、腳本資料等（由官方 TDB 匯入） |
| `characters` | `CharacterDatabaseInfo`（`worldserver.conf.dist:93,104`） | 玩家持久化資料：角色、物品、公會、郵件、拍賣等 |
| `hotfixes` | `HotfixDatabaseInfo`（`worldserver.conf.dist:94,105`） | DB2/client hotfix 資料，用於覆寫送給 client 的 DB2 內容 |

- 預設連線字串格式為 `host;port;user;password;database`（`worldserver.conf.dist:102-105`）。
- 完整 DB dump 檔名寫死在 revision header 樣板：`revision_data.h.in.cmake:43-44` → `TDB_full_world_1200.26021_2026_02_06.sql`、`TDB_full_hotfixes_1200.26021_2026_02_06.sql`（即 TDB 1200.26021）。

## 7. 這份 checkout 針對的客戶端版本 / 分支

- **分支：`master`**，追蹤 `origin/master`，remote 為 `https://github.com/TrinityCore/TrinityCore`（`git branch -vv` / `git remote -v`）。
- 上游同時維護 `master`、`3.3.5`、`cata_classic` 三條分支（`README.md` Build Status 表格）。
- **目標 client build：`12.1.0.69497`**。證據：
  - commit `b619858a03` "Core: Updated allowed build to 12.1.0.69497"（2026-08-26, Shauren），修改 `sql/base/auth_database.sql` 的 `build_info` 加入 `(69497,12,1,0,NULL)`、`build_auth_key` 加入該 build 的金鑰，並把 `realmlist.gamebuild` 預設值由 `69465` 改為 `69497`；同時新增 `sql/updates/auth/master/2026_08_26_00_auth.sql`。
  - 近期 commits `d9e37e04cd` 等一系列 "DB/Hotfixes: Updated ... hotfixes to 12.1.0.69497"（含 zhTW/zhCN/koKR/ruRU/deDE/frFR/esES/esMX/itIT/ptBR 各語系）。
  - `f182d82d34` "Core/PacketIO: Fix more packet structures for 12.1.0"。
- 版本/修訂資訊如何進入二進位檔：`cmake/genrev.cmake` 以 `git rev-parse --short=12 HEAD`、`git show -s --format=%ci`、`git symbolic-ref --short HEAD` 取得 hash/日期/分支（若工作區 dirty 會在 hash 後加 `+`，見 `cmake/genrev.cmake:37-49`），填入 `revision_data.h.in.cmake:22-24` 的 `TRINITY_GIT_COMMIT_HASH` / `_DATE` / `_BRANCH`。`WITHOUT_GIT=1` 時會退化為 `unknown` / `Archived` 分支（`cmake/genrev.cmake:19-24`），這正是 CONTRIBUTING 中提到「rev. unknown 1970-01-01 (Archived branch)」問題的成因。
- client build 中繼資料的執行期存取介面：`src/server/shared/Realm/ClientBuildInfo.h:117-118`（`LoadBuildInfo()` / `GetBuildInfo(uint32 build)`），資料來源即 auth DB 的 `build_info` / `build_auth_key`。

## 8. 開發流程

### 分支
- 上游三條長期分支：`master`（現行零售版本）、`3.3.5`（WotLK）、`cata_classic`（`README.md` Build Status 表）。
- Issue 依分支貼標籤（`README.md` 的 issue tracker 連結 `labels/Branch-master`）；GitHub Actions 有自動 labeler：`.github/workflows/issue-labeler.yml`、`.github/workflows/pr-labeler.yml`（皆使用 `TrinityCore/GitHub-Actions` action）。

### 貢獻規則（`CONTRIBUTING.md`）
- 回報 bug 前必須使用最新 core 與 database revision。
- Ticket 必填：分支、commit hash、受影響的 creature/item/quest entry 加 wowhead 連結、清楚的英文標題與描述。
- 回報 crash **必須以 debug mode 編譯**（release dump 資訊不足）。
- PR 流程：fork → 開分支 → commit → push → 開 PR；建議「每個 C++ 修正一條分支」。
- **純 SQL 修正不走 PR**，改為開 issue（`.github/ISSUE_TEMPLATE/sql_fix.yml`）。
- 撰寫 patch 前應閱讀官方 *TrinityCore Development Standards*（`CONTRIBUTING.md` 連結至 trinitycore.atlassian.net wiki 的 "C++ Development Standards"）與 "WDB Fields"。

### 程式碼風格
- `.editorconfig`：UTF-8、**4 空格縮排、不用 tab**、行尾自動去空白、檔尾換行、`max_line_length = 160`；C/C++ 原始檔（`*.{c,h,cpp,hpp,inl}`）charset 為 **latin1**。
- CI 自動檢查（`contrib/check_codestyle.sh`，由 `.circleci/config.yml` 的 `codestyle_and_sql` job 執行）：
  - 禁止行尾空白、禁止 tab（須為 4 空格）
  - 禁止連續多個空行（只留一個）
  - 禁止在 `TC_LOG_*` 中使用 `ObjectGuid::GetCounter()`，應用 `ObjectGuid::ToString().c_str()`
- 新檔案必須套用 `doc/FileHeaders.txt` 的 GPL 檔頭。

### DB 更新機制（`sql/updates`）
- 目錄結構：`sql/base/`（基準 schema，`auth_database.sql`、`characters_database.sql`、`dev/`）、`sql/updates/{auth,characters,world,hotfixes}/master/`、`sql/custom/`（自訂）、`sql/create/`、`sql/old/`（歷代版本歸檔：`2.4.3` … `12.x`）。
- 檔名規範（`CONTRIBUTING.md`）：`YYYY_MM_DD_i_database.sql`，`i` 為當天該 DB 的第 i 個檔案。修改 `auth` / `characters` 時**必須同步更新 `sql/base/*` 基準檔**。為避免尚未合併的 PR 互相衝突，建議先用不可能的日期命名（例：`2015_13_32_00_world.sql`）。
- 執行期自動套用：`src/server/database/Updater/`（`DBUpdater`、`UpdateFetcher`）在啟動時比對 DB 內 `updates` 表已套用檔案的 SHA1 並套用新檔；`UpdateResult` 區分 `updated` / `recent` / `archived`（`src/server/database/Updater/UpdateFetcher.h:31-47`）。
- 設定開關（`src/server/worldserver/worldserver.conf.dist`）：`Updates.EnableDatabases = 15`（:1505，對應 `DATABASE_MASK_ALL`）、`Updates.AutoSetup = 1`（:1513）、`Updates.Redundancy = 1`（:1522）、`Updates.ArchivedRedundancy = 0`（:1530）、`Updates.AllowRehash = 1`（:1539）、`Updates.CleanDeadRefMaxCount = 3`（:1551）。
- CI 對 SQL 也做驗證：`.circleci/config.yml` 匯入 `sql/create/create_mysql.sql`、`sql/base/*`、`sql/base/dev/world_database.sql`、`sql/base/dev/hotfixes_database.sql`，再以 `contrib/check_updates.sh` 逐一套用各 DB 的 update 檔。
- 合併 update 檔的輔助腳本：`contrib/merge_updates_unix.sh`、`contrib/merge_updates_windows.bat`。

### Commit 訊息慣例（觀察自 `git log`，非明文規則）
格式為 `區域/子系統: 描述`，例如：
- `Core/AreaTriggers: Implement new curve field`
- `Core/Players: unlock the item appearance of unselected quest rewards as well when rewarding quests`
- `DB/Hotfixes: Updated zhTW hotfixes to 12.1.0.69497`
- `DB/Creature: added missing vendor data to Jahi`
常見前綴：`Core/*`（AreaTriggers、Players、Creatures、Units、Spells、PacketIO、LFG…）與 `DB/*`（Hotfixes、Creature、GameObjects…）。

### CI 矩陣
- CircleCI：`codestyle_and_sql`（Debian 13 builder + MySQL 8.0）— `.circleci/config.yml`。
- GitHub Actions：
  - `.github/workflows/linux-build.yml` — Ubuntu 24.04，矩陣含 gcc-13 與 clang-17（PCH 開/關、ccache）。
  - `.github/workflows/macos-arm-build.yml` — macOS 14 (arm64)，透過 Homebrew 安裝相依（會先移除 `openssl@1.1`）。
  - `.github/workflows/win-x64-build.yml` — Windows x64。
  - AppVeyor（`appveyor.yml`）與 Coverity Scan 亦見於 `README.md` 徽章。

## 9. 這份 checkout 的特殊之處

- **工作區乾淨、無在地修改**：`git status --porcelain` 無輸出；`git branch -vv` 顯示 `master` 與 `origin/master` 同步於 `04fbee1334`，且 `git log origin/master..HEAD` 為空 → **純粹的上游鏡像，沒有 fork 客製**。
- HEAD：`04fbee13343768c56834a8776bd140bc3b7c6024`，日期 `2026-08-31 13:53:42 +0200`；歷史共 45,891 個 commit。
- **近期主題明顯集中在 AreaTriggers**（最新 5 個 commit）：
  - `04fbee1334` 將 `ScaleCurve` 結構更名為 `OverrideCurve`（已不只用於 scale）
  - `314a13083e` 實作新的 curve 欄位（改動 `src/server/game/Entities/AreaTrigger/AreaTrigger.cpp/.h` 與 `src/server/game/Entities/Object/Updates/UpdateFields.cpp/.h`）
  - `a560a25db5` 移除錯誤的 `AreaTriggerCreatePropertiesFlag::HasFaceMovementDir` 實作
  - `48153a77a8` 停止從資料庫載入 `AreaTriggerCreatePropertiesFlag::HasDynamicShape`
  - `252767981e` 清理重複的 `m_values.ModifyValue(&AreaTrigger::m_areaTriggerData)` 並修正格式
- 其他近期主題：12.1.0.69497 的全語系 hotfix 更新、`Core/PacketIO` 封包結構修正、`Core/Creatures`（游泳 / 仇恨半徑）、`Core/Players`（任務獎勵外觀解鎖）。
- 尚未存在建置目錄或設定檔（repo 根目錄僅有原始樹；`CMAKE_DISABLE_IN_SOURCE_BUILD ON`，必須另建 out-of-source build dir）。
- **本筆記位置說明**：repo 內既有的是 `doc/`（純上游追蹤的 `.txt` 說明檔：`COMPILATION_HELP.TXT`、`FileHeaders.txt`、`HowToScript.txt`、`LoggingHOWTO.txt`、`UnixInstall.txt`、`CharacterDBCleanup.txt`、`GPL-2.0.txt`），**並無研究筆記或 Markdown 筆記的既有慣例**，也沒有 `docs/` 或 `.notes/`。因此本檔案新建於 `docs/research/trinitycore-overview.md`（新目錄、未追蹤檔案），**未修改任何既有已追蹤檔案**。
