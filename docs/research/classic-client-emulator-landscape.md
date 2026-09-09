# 開源模擬器全景調查：有沒有人在做「現代 Classic client」？

> 撰寫日期：2026-09-03
> 相關筆記：[TrinityCore 專案總覽](./trinitycore-overview.md)、[在 TrinityCore 上跑 WotLK Classic](./wotlk-classic-on-modern-client.md)
> 本篇處理的是前一篇沒回答的問題：**TrinityCore 以外的世界呢？** 涵蓋 TrinityCore 系、MaNGOS 系，以及**完全獨立血統**（Ascent 系、Ember、Rust/Go/Java 等）。
> 來源限定 primary sources：各專案自己的 GitHub repo metadata、README、原始碼檔案、commit 紀錄（全部透過 GitHub REST API 於 2026-09-03 實際取得）。**不引用部落格、reddit、模擬器清單站。**
> 凡未實際驗證者一律標示「**未驗證**」。所有日期皆為實際 API 回傳值。

---

## 0. 一句話結論（TL;DR）

**沒有。** 目前**沒有任何**開源專案在「現代 Classic client（CASC + Battle.net + DB2/hotfixes）」這件事上做得比 TrinityCore `cata_classic` 更好。

具體地說，經本次調查：

1. **完全沒有任何專案以 3.4.x（WotLK Classic）為現行目標。** 唯二找到的 3.4.x 程式碼都比上游那條已停滯的 `wotlk_classic` 分支**更舊**：`haphert/...` 停在 **3.4.3.54261 / 2024-11-11**、`mdX7/TrinityCore:wotlk_classic` 停在 **3.4.0.45942 / 2022-10-26**。另一個 `BRUC3L1U/wotlk_classic` 經 compare API 驗證與上游**完全相同（identical, ahead 0 / behind 0）**，只是鏡像。
2. **整個 MaNGOS 血統（CMaNGOS / getMaNGOS / VMaNGOS）與 AzerothCore，全部只做原版舊 client**：1.12.1(5875) / 2.4.3(8606) / 3.3.5a(12340) / 4.3.4(15595) / 5.4.8(18414)。**沒有任何一個碰現代 Classic client。**
3. **獨立血統（非 MaNGOS、非 TrinityCore）確實存在且有活躍專案**——AscEmu（Ascent 系）、Ember（從零寫）、Rust/Go 生態——但**除了一個 ★0 的實驗性專案外，全部都在舊 client 上**。
4. 那個例外是 **`raewow/oxcore`**（Rust，1.12 + **Classic Era 1.14.x**），它**自己的 README 就寫明**：1.14 登入流程「**未曾對真實 client 驗證過**」、且 1.14 進世界的握手「**還沒做**」。不是可用的伺服器。
5. **CypherCore 是 TrinityCore 血統（C#），且目標是 retail 12.1.0.69497，只有一條 `master` 分支，沒有任何 Classic 分支。**
6. 唯一在「現代 Classic client」上真正成熟的東西，仍然只有 **TrinityCore `cata_classic`（4.4.2.60895）**。

---

## 1. 方法與限制（先講清楚可信度）

- 所有 repo 事實（last commit、license、star、branch、default_branch）皆以 `gh api repos/<owner>/<repo>` 與 `gh api repos/<owner>/<repo>/commits?per_page=1` 實際取得。
- client build 盡量**從原始碼**確認（例：AscEmu 的 `src/shared/AEVersion.hpp.in`、fork 的 `sql/base/auth_database.sql` 之 `build_info` 最後一列），無法從碼取得時才引用**專案自己的 README / repo description**（仍屬 primary source，並於文中註明出處）。
- **GitHub code search 的重大限制（必須知道）**：它**只索引各 repo 的 default branch**。因此上游 TrinityCore `wotlk_classic` 分支的內容**在 code search 中根本看不到**，任何以「搜尋 3.4.4 字串」為手段的調查都會系統性漏掉「放在非預設分支上的工作」。本文因此另外用 fork network 掃描補足（見 2.4）。
- **明確的空結果（找不到就是找不到，不編造）**：
  - `61581 filename:auth_database.sql` → 僅 5 筆，全部是 `0xB64283161581FFC8...` 這種**巧合的 hex 片段**，**沒有任何 repo 的 `build_info` 有 3.4.4.61581 這一列**。
  - `build_auth_key 61581` → **0 筆**。
  - `wow_classic CascOpenStorage` → **0 筆**。
  - `wow_classic_era` → 有結果，但**全部是 client 端工具**（noclip.website、lutris、simulationcraft、WoWUp、WoWAnalyzer、mdX7/ngdp_data），**沒有任何伺服器實作**。
  - repo search `"wotlk classic emulator"` / `"classic era emulator wow"` / `"4.4.2 wow"` / 各語言別的 emulator 搜尋 → 幾乎全為 addon 或無關專案。
- **未驗證**：本文**不是窮舉**。GitHub 搜尋 API 的排序與索引不保證完整，私有 repo、非 GitHub 託管（GitLab / Codeberg / 自架）者不在範圍內。已知 gtker 的多個專案已遷往 **codeberg.org**（見其 repo description 自述），這類遷移可能造成漏檢。

---

## 2. TrinityCore 血統（forks / 衍生 core）

### 2.1 沒有任何一個以 3.4.x 為目標

| 專案 | 血統 | 目標 client build | 證據來源 | 最後 commit |
|---|---|---|---|---|
| `haphert/TrinityCore_wotlk_classic_continued` | TC fork | **3.4.3.54261** | `sql/base/auth_database.sql` 的 `build_info` 最後一列 `(54261,3,4,3,...)`（實際 curl 取得） | **2024-11-11** |
| `mdX7/TrinityCore`（`wotlk_classic` 分支） | TC fork | **3.4.0.45942** | 同上，該分支 `build_info` 最後一列 `(45942,3,4,0,...)` | **2022-10-26** |
| `BRUC3L1U/wotlk_classic` | TC fork | 同上游 | compare API：`TrinityCore:wotlk_classic...BRUC3L1U:wotlk_classic` → **status: identical, ahead 0, behind 0** | 2025-07-02（＝上游那顆） |

**三個都比上游那條「已被官方 wiki 標為 abandoned」的分支更舊或完全相同。** 前一篇筆記的結論（第 5 節）在這次更系統的掃描後**維持不變並被強化**。

### 2.2 `cata_classic` 的 fork（有，但都不是更好的選擇）

| 專案 | 狀態 | 最後 commit |
|---|---|---|
| `wowemulation-dev/wooly-beast` | TC fork，**default branch 就是 `cata_classic`**，README 自述 "An emulation server for World of Warcraft 4.4.2 (build 60895). Based on TrinityCore."（repo description）；README 宣稱加了 PostgreSQL 後端 | **2026-04-29**（落後上游約 4 個月） |
| `leewheel/TrinityCoreCataClassic` | compare API：相對上游 `cata_classic` **ahead 11 / behind 0**，★0，個人客製 | 2026-09-01 |
| `cedricdufour3-droid/TrinityCore`（分支 `cata-4.4.2`）、`WorldOfAzeroth/TrinityCore`、`siriusty1/TrinityCore` | ★0 個人 fork | 2026-07-08 / 2025-11-27 / 2025-10-25 |

**沒有一個是「比上游更完整的 cata_classic」。** 最像獨立產品的 `wooly-beast` 反而落後上游。

### 2.3 其他知名 TC 衍生 core（全部是舊 client，與 Classic 無關）

| 專案 | 目標 | License | 最後 commit |
|---|---|---|---|
| `CypherCore/CypherCore`（C#） | **retail 12.1.0.69497** | GPL-3.0 | 2026-09-02 |
| `The-Cataclysm-Preservation-Project/TrinityCore` | **4.3.4.15595**（2010 原版 Cata，非 Cata Classic） | GPL-2.0 | 2026-07-25 |
| `ProjectSkyfire/SkyFire_548` | **5.4.8 (18414)**（2013 原版 MoP，非 MoP Classic） | GPL-3.0 | 2026-09-02 |
| `Titans-Project/LegionCore-Reforged` | Legion **7.3.5 (26972)** | GPL-2.0 | 2026-08-29 |
| AshamaneCore 家族 | Legion **7.3.5.26972** | 見下 | 見下 |
| 「WowCore」 | **查無此物**：搜尋僅得 `exceptionptr/WoWCore`（1.12，2018-06-27）與 `sergio-ivanuzzo/idewave-core`（Python 2.4.3，2022-07-14），皆與 Classic 無關 | — | — |

**AshamaneCore 補充（狀態混亂，如實記錄）**：原始的 `AshamaneTeam/AshamaneCore` 與 `ShinDarth/AshamaneCore` 兩個路徑 **API 皆回 404（不存在）**。現存的只有二手 fork：`conan513/SingleCore_TC`（★203，default branch 名稱直接叫 **`AshamaneCore-dmca`**，pushed 2024-08-21）、`The-Legion-Preservation-Project/AshamaneCore-Old`（2024-11-27）、`Longee-G/AshamaneCoreN`（description 自述 `main = 7.3.5.26972`，2024-04-02）、`n0social/project_legion`（★0，2026-08-24）、`openlcoreteam/OpenLCore`（自述基於 AshamaneCore/TrinityCore，7.3.5.26972，2022-12-09）。**全部是 Legion 7.3.5，與 Classic client 完全無關。** 分支名裡的 "dmca" 暗示原 repo 曾遭下架——**未驗證**（本文未取得任何 DMCA 通知原件）。

### 2.4 fork network 掃描（補 code search 的洞）

掃描 TrinityCore repo 的 **最新 300 個 fork** 以及 **star 數最高的 100 個 fork**，篩出 default branch 含 `cata` / `wotlk` / `classic` / `3.4` / `4.4` 者，結果就是 2.1 + 2.2 那幾個，**沒有任何遺漏的「活躍 3.4.x 專案」**。

star 最高的 fork 群（`trickerer/TrinityCore-3.3.5-with-NPCBots`、`Rochet2/TrinityCore`、`TrinityCoreLegacy/TrinityCore`、`KamiliaBlow/RoleplayCore` 等）**全部是 3.3.5 或 retail**。

> **未驗證**：只掃了 300 個最新 fork（TrinityCore 的 fork 數遠大於此），不能宣稱窮舉。

---

## 3. MaNGOS 血統 + AzerothCore：整條線都在舊 client

| 專案 | 目標 client（出處為專案自己的 description / README） | License | 最後 commit / push |
|---|---|---|---|
| `azerothcore/azerothcore-wotlk` | README 自述 "recreate the gameplay experience of the original game from **patch 3.3.5a**" | GPL-2.0 | **2026-09-02**（極活躍，★8865） |
| `cmangos/mangos-classic` | **1.12**（其 DB repo `cmangos/classic-db` description：「World of Warcraft Client Patch 1.12」） | GPL-2.0 | 2026-08-31 |
| `cmangos/mangos-tbc` | **2.4.3**（`cmangos/tbc-db` description） | GPL-2.0 | 2026-09-02 |
| `cmangos/mangos-wotlk` | **3.3.5**（`cmangos/wotlk-db` description） | GPL-2.0 | 2026-09-01 |
| `cmangos/mangos-cata` | 4.x（原版） | GPL-2.0 | **2018-12-12（已死）** |
| `mangos/MaNGOS`（getMaNGOS 總站） | README：「We supports 5 WoW versions: Vanilla, TBC, WOTLK, CATA and MOP (although the CATA and MOP branches are in need of work)」 | — | 2026-03-06 |
| `mangoszero/server` | description：「clients **1.12.1-1.12.3**」 | GPL-3.0 | 2026-09-02 |
| `mangosone/server` | 「client **2.4.3(8606)**」 | GPL-3.0 | 2026-09-02 |
| `mangostwo/server` | 「client **3.3.5a(12340)**」 | GPL-3.0 | 2026-09-02 |
| `mangosthree/server` | 「client **4.3.4 (Build 15595)**」 | GPL-3.0 | 2026-09-02 |
| `mangosfour/server` | 「client **5.4.8 (Build 18414)**」，自述 Early Alpha、"IN ACTIVE DEVELOPMENT 2026" | GPL-3.0 | 2026-09-02 |
| `vmangos/core` | description：「Progressive Vanilla Core aimed at all versions **from 1.2 to 1.12**」 | GPL-2.0 | 2026-09-02 |

**關鍵觀察**：注意 `mangosthree` 是 **4.3.4**、`mangosfour` 是 **5.4.8**——這是 2010/2013 的**原版** Cataclysm / MoP client（MPQ 架構），**不是** Blizzard 2024/2025 的 Cata Classic 4.4.x / MoP Classic 5.5.x。這兩者極易混淆，但架構完全不同（見上一篇筆記第 2 節的 MPQ vs CASC 對照）。

`cmangos/mangos-classic` 的分支列表只有 `master` 與一個 bugfix 分支——**沒有任何 classic-era（1.14/1.15）分支**。

授權提醒：MaNGOS 系與 AzerothCore 為 GPL（2.0 或 3.0），衍生散布須開源；與 TrinityCore 的義務相同（見總覽筆記第 2 節）。

---

## 4. 完全獨立血統（既非 MaNGOS 也非 TrinityCore）

這是本次調查最有價值的一節：**獨立血統確實存在、而且有活躍專案，但沒有一個解決「現代 Classic client」。**

### 4.1 Ascent 血統：Antrix → Ascent → ArcEmu → AscEmu

| 專案 | 血統自述 | 目標 client | License | 最後 commit |
|---|---|---|---|---|
| `AscEmu/AscEmu` | README：「AscEmu is derived from **ArcEmu** to keep up the **Antrix-Ascent-Arcemu** way of Framework.」→ **與 MaNGOS/TC 無關的獨立血統** | 見下表 | **AGPL-3.0** | **2026-09-02（活躍）** |
| `arcemu/arcemu` | description：「World Of Warcraft **3.3.5a** server」 | 3.3.5a | AGPL-3.0 | **2024-03-05（停滯）** |

**AscEmu 的 client build 直接寫在原始碼** `src/shared/AEVersion.hpp.in`（實際取得的檔案內容）：

```c
#define Classic 5875
#define TBC     8606
#define WotLK   12340
#define Cata    15595
#define Mop     18414
```

搭配 `#define VERSION 1,12,1` / `2,4,3` / `3,3,5` / `4,3,4` / `5,4,8`。它用 CMake 的 `ASCEMU_VERSION` 下拉選項在**同一份 repo 內多版本編譯**（README「Multiversion」段），README 的支援矩陣顯示五個版本都只做到 Authentication / Worldsocket / Char Enum / Log into world。

**決定性證據：它的 client 資料相依是 `dep/mpqlib/`（MPQ 讀取器）**，且 `dep/mpqlib/include/mpqlib/ClientVersion.hpp` 的 enum 就是 `Vanilla = 5875 … MistsOfPandaria = 18414`。→ **AscEmu 是純 MPQ 架構，完全沒有 CASC / DB2 / Battle.net 那一層。**

**授權注意：AscEmu / ArcEmu 是 AGPL-3.0**，比 GPL 更嚴格（網路服務也觸發提供原始碼義務）。若你打算自架對外服務，這一點與 TrinityCore(GPL-2.0) 有實質差異。

### 4.2 Ember（從零寫、C++）

- `EmberEmu/Ember`，**MPL-2.0**，★73，**最後 commit 2026-09-01（活躍）**。
- 血統：README 直接回答「No. Ember has been written **from the ground up with zero code reuse from other cores**.」→ **確認為完全獨立血統**。
- 目標：README 標題「High-performance, distributed emulator for **WoW 1.12**」。
- **而且它明講不打算追新 client**：「Our primary goal isn't to produce a feature-complete, up-to-date emulator to use with **newer clients**. The 1.12.1 protocol was chosen as a fixed target…」
- → 技術上最有意思的獨立專案之一，但**方向上明確排除**你要的東西。

### 4.3 Rust 生態

以 `arlyon/awesome-wow-rust`（該社群自己維護的索引）為起點，逐一回原始 repo 驗證：

| 專案 | 內容 | 目標 client | 最後 commit |
|---|---|---|---|
| `Victov/wrath-rs` | README：「educational project to create a server emulator for WoW patch **3.3.5 (12340)** in Rust」「nowhere near playable」 | 3.3.5 | 2026-01-28 |
| `arlyon/azerust` | README：「experimental WoW server emulator for patch **3.3.5**」，且自述建構於 **TrinityCore database** 之上（→ 資料面沾 TC 血統，程式碼獨立） | 3.3.5 | 2025-06-12（commit message 為 "wip"） |
| `gtker/wow_messages` | 協定訊息產生器，README：examples「will work with **1.12, 2.4.3 and 3.3.5** clients」 | 1.12/2.4.3/3.3.5 | 2026-09-02（活躍） |
| `gtker/wow_vanilla_server` | description：「WIP Rust server for **WoW 1.12**」 | 1.12 | 2025-09-17 |
| `gtker/warthog-wow` | description：「WIP auth server for **WoW 1.2-3.3.5**」 | ≤3.3.5 | 2024-05-10 |
| `gtker/wow_dbc` | 「1.12, 2.4.3 and 3.3.5 **DBC**」→ 注意是 DBC 不是 DB2 | ≤3.3.5 | 2026-05-24 |
| **`raewow/oxcore`** | **唯一觸及現代 Classic client 者**，見 4.4 | 1.12 + **1.14.x** | **2026-08-06** |

（gtker 多個 repo 的 description 自述已遷往 codeberg.org，GitHub 上為存檔——**這代表 GitHub 端資料可能非最新，未驗證 codeberg 端狀態。**）

### 4.4 `raewow/oxcore` —— 唯一一個真的在打 Classic Era client 的獨立專案

這是本次調查最接近「你要的東西」的專案，所以完整記錄，**同時完整記錄它自己承認的缺陷**。

- Rust，**★0**，License 欄位為 none（**未宣告授權——實務上等於保留全部權利，不可安全地散布或衍生**），**最後 commit 2026-08-06**。
- README 第一句：「A World of Warcraft (**Vanilla 1.12.x, Classic 1.14.x**) private server implementation written in Rust.」
- repo 內確實有 **`crates/bnet/`**（含 `proto/bgs.proto`、`certs.rs`、`gen_certs.rs`）與 **`crates/patcher/`**——也就是**現代 Battle.net 登入那一整套**（HTTPS REST + TLS protobuf RPC + client 憑證修補），架構方向與 TrinityCore `bnetserver` 一致。
- **但它自己的 `crates/bnet/README.md` 白紙黑字寫著**：

  > **Status.** The login pipeline is implemented end to end — login → logon → realm list → realm join — and every layer is unit-tested for internal correctness. It has **not been verified against a live retail client**, and the world-side handshake a 1.14 client performs *after* realm join **is not built yet**. Expect the client to **reach the realm screen and then fail at world-connect**.

- 另一個結構性限制：它的資料層是 **`crates/dbc/`（DBC，非 DB2）**，README 明說遊戲資料要「use vmangos versions of the following: DBC Files / VMap Files」——**也就是說即使 1.14 client 能連上，餵給它的仍是 1.12 的資料集**。這和 `wotlk_classic` 的病灶完全同型（見上一篇筆記 3.2）：**core 撞得通、內容資料庫沒有跟上。**
- **定性：一個很有想法、但極早期、單人、未授權宣告的實驗。不是可用的伺服器，也不比 `cata_classic` 好。**

### 4.5 其他語言

| 專案 | 語言 | 血統 | 目標 | 最後 commit |
|---|---|---|---|---|
| `paalgyula/summit` | Go | README：「writing the emulator **from scratch**」，僅參考 AzerothCore 的 opcodes 與 TrinityCore 的 DBC enums → **實質獨立** | **3.3.5a** | 2026-04-16 |
| `walkline/ToCloud9` | Go | **非獨立 core**：README 自述是「microservices that operate **alongside** AzerothCore/TrinityCore」的叢集化層 | 3.3.5（隨 AC/TC） | 2026-08-15 |
| `Warkdev/JaNGOSAuth` | Java | 獨立 | 「WoW **1.12.x**」 | 2021-07-30（停滯） |
| `sergio-ivanuzzo/idewave-core` | Python | 獨立 | 「Python wowcore **2.4.3**」 | 2022-07-14（停滯） |
| **Shadowburn（Elixir）** | — | — | **在 GitHub 搜尋中查無此專案**（`gh search repos shadowburn` 只回傳同名個人帳號、addon 與無關 repo）。**未驗證**其是否存在於他處或已刪除。 | — |

**沒有找到任何 C# 的獨立血統 core**（CypherCore 是 TrinityCore 血統，見 5 節）。也**沒有找到任何 TypeScript 的 WoW server core**。

---

## 5. CypherCore 專章

問題問得具體，所以答得具體。**全部來自 repo 自身**：

- 血統：**TrinityCore 血統**（C# 移植），非獨立。佐證來自它自己的 README：安裝步驟要求「Use **TrinityCore extractors** for now」、「Download the full **Trinity Core database (TDB 1120.25081)**」、「Check out **Trinity Core Wiki** as a few steps are the same」。
- **目標 client build：README 明文「The current support game version is: `12.1.0.69497`」** ——與 TrinityCore `master` 完全相同的 retail build。
- **分支：`gh api repos/CypherCore/CypherCore/branches` 只回傳一條 → `master`。沒有任何 Classic 分支、沒有 3.4.x、沒有 4.4.x。**
- 最後 commit：**2026-09-02**（`a3cd9d9281 Misc fixes`）——非常活躍。
- License：**GPL-3.0**（注意：比 TrinityCore 的 GPL-2.0-or-later 更嚴，兩者程式碼**不能雙向自由搬運**：TC 的 "or later" 可單向升級到 GPL-3，反向不行）。
- 執行需求：README 要求「Must use **Arctium WoW Client Launcher**」——與 TrinityCore 現代分支相同的第三方 launcher 前提。

**結論：CypherCore 對你的需求毫無幫助。它是「另一種語言寫的 retail TrinityCore」。**

---

## 6. 現代 Classic client 的**周邊生態**（有東西，但不是伺服器）

值得單獨記錄：`wowemulation-dev` 這個 org 是目前對「現代 Classic client」投入最多的地方，但它做的是**工具**，不是 core。

| 專案 | 是什麼 | 涵蓋的 Classic client | License | 最後 commit |
|---|---|---|---|---|
| `wowemulation-dev/wow-patcher` | Rust 寫的 client patcher，README：「for **modern Classic client**」。支援矩陣自述 **1.14.x / 2.5.x–2.5.4 / 3.4.x–3.4.4 / 4.4.x–4.4.2 皆為 "Verified"** | 1.14 / 2.5 / **3.4** / 4.4 | Apache-2.0 | 2026-07-15 |
| `wowemulation-dev/tavern` | 「Rust replacement for Blizzard Battle.net account services」。build cutoff 表：1.13→39692、1.14→51535、2.5.4→44833、**3.4.4→61581**、4.4.2→60895 | 同左 | AGPL-3.0 | 2026-06-23 |
| `wowemulation-dev/cascette-rs` | Blizzard NGDP / Ribbit 工具（CDN、build 鏡像） | 通用 | Apache-2.0 | 2026-02-27 |
| `wowemulation-dev/wooly-beast` | TrinityCore `cata_classic` 的 fork（見 2.2） | 4.4.2.60895 | GPL-2.0 | 2026-04-29 |

**但 `tavern` 的 README 自己就寫了**：

> There is **no runnable implementation yet**. Functionality described below is planned, not available.

**這一節的意義**：client 端（把 3.4.4 client 指向自架伺服器）**技術上是通的、而且有人做了並宣稱 verified**。卡住的從來不是 client patching，**卡住的是伺服器端的 core + world database**——這與上一篇筆記 Path C 的結論完全一致：瓶頸在內容資料庫，不在能不能連上。

（另外，`tavern` 的 build cutoff 表也**間接佐證**了上一篇的一個推論：3.4.4.61581 就是 WotLK Classic 的**終點 build**。）

---

## 7. 回答「有沒有任何成熟的現代 Classic client core」

逐一檢視五條現代 Classic client 線：

| Client 線 | 有沒有成熟開源 core？ | 證據 |
|---|---|---|
| **Classic Era 1.14 / 1.15** | **沒有。** 唯一觸及者是 `raewow/oxcore`（★0、1.14 世界握手未實作、未宣告授權）。`wow_classic_era` 字串的 code search 只命中 client 端工具。 | 4.4 節 |
| **TBC Classic 2.5.x** | **完全沒有。** 本次調查未找到任何專案。 | 空結果 |
| **WotLK Classic 3.4.x** | **沒有。** 只有兩個比上游更舊的殭屍 fork + 一個 identical 鏡像。 | 2.1 節 |
| **Cataclysm Classic 4.4.x** | **有一個，就是 TrinityCore `cata_classic`。** 其餘皆為其 fork，且無一更完整。 | 2.2 節 + 上一篇筆記 |
| **MoP Classic 5.5.x** | **完全沒有。**（注意 `mangosfour` 與 `SkyFire_548` 是 **5.4.8 原版 MoP**，不是 MoP Classic。） | 3 節 |

**也就是說：「舊內容跑在新架構 client 上」這個問題，全世界的開源界只被解決過一次，就是 TrinityCore `cata_classic`。**

---

## 8. 關於閉源私服（僅作為「技術上可行」的旁證）

**本文不背書、不推薦任何閉源私服，且其宣稱一律無法驗證。** 僅記錄一項與判斷相關的事實：

- 從 `wow-patcher` 對 3.4.x「Verified」的自述，可知**把 3.4.4 client 指向非官方伺服器在技術上是可行的**。
- 至於是否有閉源專案已完成 3.4.x 的伺服器端——**無法驗證，本文不做任何宣稱**。閉源專案不提供原始碼，其功能宣稱在方法論上不可查核，因此不構成本文任何結論的依據。

---

## 9. 底線（直接回答）

> **問：有沒有任何專案在「WotLK Classic / 現代 Classic client」這件事上，做得比 TrinityCore `cata_classic` 更好？**
>
> **答：沒有。一個都沒有。**

排序後的現實：

1. **TrinityCore `cata_classic`（4.4.2.60895）** ——唯一成熟的現代架構 Classic core，且已含近乎完整的 WotLK 副本腳本（見上一篇筆記 Path B）。**這仍然是最佳解。**
2. 上游 `wotlk_classic`（3.4.4.61581，停滯於 2025-07-02）——**第二名，而且是個死人。**
3. 其餘一切（`haphert`、`mdX7`、`oxcore`、`wooly-beast`…）都排在第三名之後。

**如果你的目標是「現在就能玩」，這份調查沒有改變上一篇的建議：走 `cata_classic`。**
**如果你的目標是「參與一個正在攻這個問題的專案」，那麼誠實的答案是：這樣的專案目前不存在**——最接近的是 `wowemulation-dev` 那組工具（client patcher / Battle.net 服務替代品），它們把「client 側」鋪好了，但**沒有人在做伺服器側**。

---

## 10. 驗證方式（可重跑）

```bash
# repo 事實（license / star / archived / default_branch）
gh api repos/<owner>/<repo> --jq '{full_name,description,license:.license.spdx_id,default_branch,archived,fork}'

# 最後一顆 commit（本文所有日期的來源）
gh api "repos/<owner>/<repo>/commits?per_page=1" \
  --jq '.[0]|"\(.commit.author.date) \(.sha[0:10]) \(.commit.message|split("\n")[0])"'

# 特定分支的最後 commit
gh api "repos/mdX7/TrinityCore/commits?sha=wotlk_classic&per_page=1"

# fork 是否真的有做事（本文判定 BRUC3L1U 為 identical 的依據）
gh api "repos/TrinityCore/TrinityCore/compare/wotlk_classic...BRUC3L1U:wotlk_classic" \
  --jq '"\(.status) ahead:\(.ahead_by) behind:\(.behind_by)"'
gh api "repos/TrinityCore/TrinityCore/compare/cata_classic...leewheel:TrinityCoreCataClassic:cata_classic" \
  --jq '"\(.status) ahead:\(.ahead_by) behind:\(.behind_by)"'

# fork network 掃描（補 code search 只索引 default branch 的洞）
for p in 1 2 3; do
  gh api "repos/TrinityCore/TrinityCore/forks?sort=newest&per_page=100&page=$p" \
    --jq '.[]|select(.default_branch|test("cata|wotlk|classic|3\\.4|4\\.4"))|"\(.full_name) \(.default_branch) \(.pushed_at)"'
done

# fork 的實際目標 build（build_info 最後一列才算數）
curl -s https://raw.githubusercontent.com/mdX7/TrinityCore/wotlk_classic/sql/base/auth_database.sql \
  | awk '/INSERT INTO `build_info`/,/;$/' | tail -2

# 從原始碼確認 AscEmu 的 client build
gh api repos/AscEmu/AscEmu/contents/src/shared/AEVersion.hpp.in --jq '.content' | base64 -d

# 空結果可重現的搜尋
gh search code 'build_auth_key 61581'
gh search code 'wow_classic CascOpenStorage'
gh search code 'wow_classic_era'
```

---

## 11. 實際取用過的來源（全部為各專案自身）

**TrinityCore 血統**
- `https://github.com/CypherCore/CypherCore`（README、branches、commits）
- `https://github.com/The-Cataclysm-Preservation-Project/TrinityCore`
- `https://github.com/ProjectSkyfire/SkyFire_548`
- `https://github.com/Titans-Project/LegionCore-Reforged`
- `https://github.com/haphert/TrinityCore_wotlk_classic_continued`（含 `sql/base/auth_database.sql`）
- `https://github.com/mdX7/TrinityCore`（`wotlk_classic` 分支、其 `auth_database.sql`）
- `https://github.com/BRUC3L1U/wotlk_classic`、`https://github.com/leewheel/TrinityCoreCataClassic`
- `https://github.com/wowemulation-dev/wooly-beast`
- `https://github.com/conan513/SingleCore_TC`、`https://github.com/Longee-G/AshamaneCoreN`、`https://github.com/openlcoreteam/OpenLCore`

**MaNGOS 血統 / AzerothCore**
- `https://github.com/azerothcore/azerothcore-wotlk`（README、branches）
- `https://github.com/cmangos/{mangos-classic,mangos-tbc,mangos-wotlk,mangos-cata,classic-db,tbc-db,wotlk-db}`
- `https://github.com/mangos/MaNGOS`（README）、`https://github.com/mangos{zero,one,two,three,four}/server`
- `https://github.com/vmangos/core`

**獨立血統**
- `https://github.com/AscEmu/AscEmu`（README、`src/shared/AEVersion.hpp.in`、`dep/mpqlib/include/mpqlib/ClientVersion.hpp`）
- `https://github.com/arcemu/arcemu`
- `https://github.com/EmberEmu/Ember`（README）
- `https://github.com/raewow/oxcore`（README、`crates/bnet/README.md`、`crates/patcher/README.md`、repo tree）
- `https://github.com/Victov/wrath-rs`、`https://github.com/arlyon/azerust`、`https://github.com/arlyon/awesome-wow-rust`
- `https://github.com/gtker/*`（repo 清單與 description）
- `https://github.com/paalgyula/summit`、`https://github.com/walkline/ToCloud9`
- `https://github.com/Warkdev/JaNGOSAuth`、`https://github.com/sergio-ivanuzzo/idewave-core`

**現代 Classic client 周邊工具**
- `https://github.com/wowemulation-dev/wow-patcher`（README 支援矩陣）
- `https://github.com/wowemulation-dev/tavern`（README build cutoff 表與 "no runnable implementation yet"）
- `https://github.com/wowemulation-dev/cascette-rs`

**查無（明確記錄）**：Shadowburn（Elixir）、任何 2.5.x / 5.5.x 伺服器實作、任何 default branch 帶有 3.4.4.61581 `build_info` 的 repo。
