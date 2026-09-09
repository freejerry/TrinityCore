# RaGEZONE 論壇調查：社群到底對 3.4.x（WotLK Classic）做了什麼？

> 撰寫日期：2026-09-03
> 相關筆記：[在 TrinityCore 上跑「WotLK Classic」](./wotlk-classic-on-modern-client.md)、[開源模擬器全景調查](./classic-client-emulator-landscape.md)、[macOS client 取得與執行](./macos-client-options.md)
> 任務：讀 RaGEZONE 三個版面（`wow-releases.436` / `world-of-warcraft.114` / `wow-development.517`），找 3.4.x / 4.4.x / 1.14–1.15 / 5.5.x 模擬的一手開發者發言。
> **本篇的所有實質內容都不是來自論壇頁面本身**（論壇無法抓取，見第 1 節），而是來自**論壇線索指向的 GitHub repo**，全部以 `gh api` / `curl` 於 2026-09-03 實際取得並逐項驗證。
> 凡未實際驗證者一律標示「**未驗證**」。

---

## 0. 一句話結論（TL;DR）

**論壇本身抓不到（HTTP 403），但這趟仍然有重大收穫，而且它推翻了前兩篇筆記的一個核心結論。**

搜尋引擎索引到的 RaGEZONE 討論串標題，把線索指向兩個**前兩篇筆記完全沒有涵蓋**的東西：

1. **`Xian55/HermesProxy`（GPL-3.0，★54）—— 一條前面三篇筆記都沒考慮過的架構路線（本文稱 Path D）。**
   它不是伺服器，是**協定翻譯 proxy**：現代 3.4.3 Classic client ↔ proxy ↔ **既有的 3.3.5a 伺服器（TrinityCore / AzerothCore / cMaNGOS）**。
   `feature/wotlk-classic-v3.4.3` 分支**最後 commit 是 2026-09-02**（即昨天），分支內有一份 **156 KB、597 行的 `wotlk.md` 開發狀態文件**，逐一列出哪些子系統會動、哪些壞掉、壞在哪一個 opcode。**這正是任務要找的「開發者自己寫的、卡在哪」的一手材料，而且是全世界目前針對 3.4.x 最詳盡的公開技術文件。**
2. **`lineagedr/3.4.3_Source`（代號 Wrathion，GPL-2.0，★34）—— 一份原生講 3.4.3 協定的 TrinityCore 衍生伺服器原始碼**，作者於 2026-05-17/18 以「我不做了，公開出來」的方式釋出，README 自述「**around 70% playable**」。

**對前兩篇筆記的直接修正：**
[全景調查](./classic-client-emulator-landscape.md)第 7 節寫「**WotLK Classic 3.4.x：沒有**（只有兩個比上游更舊的殭屍 fork）」。**這句話現在不成立。** 至少有三個活的東西：`Xian55/HermesProxy` 的 3.4.3 分支（**昨天還在 commit**）、`lineagedr/3.4.3_Source`（Wrathion，2026-05）、`RioMcBoo/CypherCoreClassicWOTLK`（2026-03）。當時漏掉的原因很明確：**它們沒有一個是用「TrinityCore fork + `build_info` 有 61581」的形態存在**，前一次調查的搜尋手段（fork network 掃描、`build_info` code search）在方法上抓不到 proxy 與非 fork-network 的專案。

**但也要說清楚：這些全部是 3.4.3.54261，不是使用者要的 3.4.4.61581。** 而 3.4.3.54261 的 CDN build config 在[前一篇筆記](./macos-client-options.md)第 3.3 節已實測為 **HTTP 404**。**client 取得的問題一個都沒被解決。**

---

## 1. 論壇可及性（實測，這是誠實交代）

| 目標 | 方法 | 結果 |
|---|---|---|
| `forum.ragezone.com/community/wow-releases.436/` | WebFetch | **HTTP 403** |
| `forum.ragezone.com/community/world-of-warcraft.114/` | WebFetch | **HTTP 403** |
| `forum.ragezone.com/community/wow-development.517/` | WebFetch | **HTTP 403** |
| 同上 | `curl -A "Mozilla/5.0"` | **HTTP 403** |
| `forum.ragezone.com/robots.txt` | `curl` | **HTTP 200** |

**沒有任何一個討論串頁面被實際讀取過。** 依任務界線，未使用瀏覽器自動化、未註冊帳號、未嘗試繞過 Cloudflare。

`robots.txt` 本身值得記一筆（Cloudflare Managed content 區塊）：

```
User-agent: *
Content-Signal: search=yes,ai-train=no,use=reference
Allow: /
```

也就是**站方允許搜尋索引、允許作為 reference 使用，但不允許用於 AI 訓練**——與實測的 403 一致（擋的是自動抓取，不是擋搜尋引擎）。因此**唯一可用的管道是搜尋引擎索引**，本文據此只取得**討論串標題與 URL**，再回頭去追它們指向的 repo。

### 1.1 實際確認存在的討論串（僅標題與 URL，內文未讀取）

以下標題與 URL 來自搜尋結果，**內文一律未取得，因此本文不引用任何論壇貼文文字、使用者名稱或日期**：

- `https://forum.ragezone.com/threads/wow-wotlk-3-4-3-classic-working-client-for-any-server-with-new-hermesproxy.1263743/`（另有 page-2、page-3）
- `https://forum.ragezone.com/threads/native-open-source-3-4-3-wrath-classic-server.1270109/`
- `https://forum.ragezone.com/threads/wow-tbc-2-5-2-classic-working-client-any-legacy-server-setup-guide.1264224/`
- `https://forum.ragezone.com/threads/3-3-5a-4-3-4-emulator-character-transfer-migration-tool.916489/`

> **未驗證：** 上述討論串的**發文日期、作者、內文**全部未取得。搜尋引擎摘要中出現的日期（如「2026-08-07」）與人名（如「Hashi」）**不是我實際讀到的內容，本文不採用**。

### 1.2 只作為「類別」記錄、不追的東西

`wow-releases.436` 版面的大宗是 **repack / client 檔案散布**（例如若干 Cataclysm 4.3.4 repack 討論串）。依任務界線：**確認這類討論串存在，不記錄、不追蹤任何下載連結**，到此為止。

---

## 2. 從論壇線索追到的一手 repo（全部實際驗證）

### 2.1 HermesProxy 家族 —— 這是本次最重要的發現

**架構定位（引自 `WowLegacyCore/HermesProxy` README 原文）：**

> "This project enables play on existing legacy WoW emulation cores using the modern clients. It serves as a translation layer, converting all network traffic to the appropriate format each side can understand."
>
> "There are 4 major components to the application:
> - The modern BNetServer to which the client initially logs into.
> - The legacy AuthClient which will in turn login to the remote authentication server (realmd).
> - The modern WorldServer to which the game client will connect once a realm has been selected.
> - The legacy WorldClient which communicates with the remote world server (mangosd)."

**這是與前三篇筆記所有路徑都不同的第四條路。** 前面的假設一直是「要嘛把 core 升級到現代協定（Path C），要嘛換內容（Path B）」。HermesProxy 的答案是：**core 一行都不改，在中間放一個雙向協定翻譯層。** 它同時解掉了 Path C 最大的兩個成本項——opcode 表重寫與 world DB 重建——因為後端仍是成熟的 3.3.5a TrinityCore/AzerothCore，**world database 原封不動**。

| Repo | 定位 | License | ★ | 最後 commit | 狀態 |
|---|---|---|---|---|---|
| `WowLegacyCore/HermesProxy` | 原始專案（1.14↔1.12、2.5↔2.4.3） | GPL-3.0 | 358 | 2023-10-19 | **已 archived**（2024-07-03 push） |
| `advocaite/HermesProxy-WOTLK` | 加上 **3.4.3 ↔ 3.3.5a** 的 fork（獨立 repo，非 GitHub fork） | GPL-3.0 | 43 | 2026-05-20 | 活著 |
| **`Xian55/HermesProxy`** | 原始專案的 fork，**主線 + 3.4.3 分支都在動** | GPL-3.0 | 54 | master 2026-06-11；**3.4.3 分支 2026-09-02** | **最活躍** |
| `qq234071/HermesProxyMe` | 鏡像 | GPL-3.0 | 1 | 2022-06-12 | 死 |

`advocaite/HermesProxy-WOTLK` 的 README 支援表（實際取得）明列第三列：

```
| Modern Versions | Legacy Versions |
| 1.14.2          | 1.12.1          |
| 2.5.3           | 2.4.3           |
| 3.4.3           | 3.3.5a          |
```

`Xian55/HermesProxy` 的分支清單（實測）：

```
master, feature/wotlk-classic-v3.4.3, perf/v343-minimise-login-hotfixes,
feature/fix/73, feature/fix/73-2, perf/union-*（4 條）
```

- `master...feature/wotlk-classic-v3.4.3` → **ahead 338 / behind 0，300 個檔案**（compare API 實測）。
- 該分支最後 commit：**2026-09-02 `e495721c85 docs(wotlk): record the 2026-09-02/03 playtest pass`**。
- 有對應的 pre-release：`v4.3.0-feature-wotlk-classic-v3-4-3-e495721`（2026-09-02）。
- `Xian55/HermesProxy` 相對 upstream `WowLegacyCore/HermesProxy` **ahead 243**（compare API）。
- 開放中的 issue：**30 個**。

> ⚠️ **這是第三方專案，本文不背書、未評估品質／安全性／授權合規性。** 注意 GPL-3.0 與 TrinityCore 的 GPL-2.0-or-later 之間的單向相容性（見全景調查第 5 節同樣的提醒）。

### 2.2 `lineagedr/3.4.3_Source`（Wrathion）—— 原生 3.4.3 伺服器原始碼

| 欄位 | 值（`gh api` 實測） |
|---|---|
| License | **GPL-2.0** |
| ★ | 34 |
| 建立 / 最後 push | **2026-05-17 / 2026-05-18** |
| 最後 commit | `b864f5d8c4 Remove tools exclusion from .gitignore.`（2026-05-18） |
| 分支 | 只有 `main` |

README 全文（實際取得，這是作者自己的話）：

> "# World of Warcraft 3.4.3 Source Source code.
> This used to be a project of mine in 2025 called **Wrathion**.
> Since I'm **not using it nor developing it anymore** I decided to share it.
> I'd say it's around **70% playable**"

**架構驗證（直接讀原始碼，比 README 可靠）：**

```
src/server/ → bnetserver  database  game  proto  scripts  shared  worldserver   ← 有 proto/，現代架構
src/server/game/Miscellaneous/SharedDefines.h:133
  #define CURRENT_EXPANSION EXPANSION_WRATH_OF_THE_LICH_KING
src/tools/map_extractor/System.cpp:112
  char const* CONF_Product = "wow_classic";
```

→ **與上游 `wotlk_classic` 分支同型**：現代架構 core（CASC / bnetserver / Battle.net protobuf / DB2），讀 `wow_classic` product，目標資料片是 WotLK。

**但有兩個必須記下的缺口：**

1. **repo 內沒有 `sql/` 目錄**（root tree 只有 `Patches / cmake / dep / src` + 幾個 build 檔）。**資料庫不在原始碼裡。** 依 `Xian55` 的 `wotlk.md` 描述，Wrathion 的資料庫是 4 個 SQL dump（auth / characters / world / hotfixes，約 315 MB）**另行散布**——也就是說，這個專案的 world DB **不在版本控制內、不可從 GitHub 取得**。這正是上一篇筆記反覆強調的病灶（core 撞得通、內容庫沒跟上）的另一種形態：這次內容庫存在，但**不公開在 repo 裡**。
2. **開發已停止**（作者自述 + 只有兩天的 commit 歷史）。它是一份 **code dump**，不是一個進行中的專案。

### 2.3 `RioMcBoo/CypherCoreClassicWOTLK` —— C# 的原生 3.4.3 分支

| 欄位 | 值 |
|---|---|
| 血統 | `CypherCore/CypherCore` 的 fork（C#，TrinityCore 血統） |
| default branch | **`WOTLK_CLASSIC`** |
| License | GPL-3.0 |
| ★ | 23 |
| 最後 commit | **2026-03-19** `d3b86cdb91 Core/Stats: Downgrading stats system to WOTLK (continuation) #17` |

**這直接修正了全景調查第 5 節的一句話**：那裡寫「CypherCore … 只有一條 `master` 分支，沒有任何 Classic 分支」。**對 CypherCore 上游本身仍然正確，但它的 fork 生態裡有一條做 WotLK Classic 的線，而且做到 2026-03。** commit 訊息「Downgrading stats system to WOTLK」點出這條路的性質：**把 retail core 往回降級到 WotLK**，方向與 TrinityCore `wotlk_classic`（從 `cata_classic` 往回降）相同。

### 2.4 順帶驗證：`alseif0x/rustycore`

[macOS 筆記](./macos-client-options.md)第 5 節已提及。本次複驗（2026-09-03）：description 自述 `wotlk classic = 3.4.3.54261`，**default branch 就叫 `3.4.3`**，★21，最後 commit **2026-09-01**，License 欄位 `NOASSERTION`（**授權未明確宣告，散布/衍生有風險**）。**它是活的**，且與本節其他專案同樣釘在 3.4.3.54261。

---

## 3. `wotlk.md` 的技術實質 —— 「做到哪、卡在哪」

檔案：`Xian55/HermesProxy` 分支 `feature/wotlk-classic-v3.4.3` 的根目錄 `wotlk.md`（597 行 / 156 KB，實際取得全文）。以下皆為原文引用或逐項摘錄。

### 3.1 它自己怎麼定位

> "The **WotLK Classic retail client (build 3.4.3.54261)** connects through HermesProxy to a legacy **WotLK 3.3.5a server emulator** (TrinityCore / CMaNGOS / AzerothCore). Auth, character-select, world-enter, and most gameplay work end-to-end on both backends. Support is still **experimental**."

後端策略（原文）：

> "**TrinityCore 3.3.5a is the primary backend and AzerothCore is the secondary.**"

### 3.2 為什麼 3.4.3 是硬骨頭 —— 這是本次調查最有價值的單一技術事實

原文小節標題就叫「Why 3.4.3 was a large effort: new ObjectUpdate descriptor format」：

| Client | `ObjectUpdateBuilder` LOC | Update format |
|---|---|---|
| V1_14_1_40688（Classic Era） | ~1,720 | Legacy DWORD-indexed UpdateFields + update-mask bitmap |
| V2_5_3_41750（TBC Classic） | ~1,720 | 同上 |
| **V3_4_3_54261（WotLK Classic）** | **~3,419** | **Descriptor-based change-set system（matches retail Legion+）** |

> "Blizzard modernized the object-update protocol for WotLK Classic to match current retail rather than ship 2008's `updatemask`-over-DWORD-array format. … Off-by-one errors in any `WriteBits(mask, N)` corrupt the entire object stream, so **capture-based byte-level validation … is the only reliable check**."

**這解釋了一件前面三篇筆記都只能猜的事：為什麼 1.14 / 2.5 的 proxy 早在 2021 就能動，3.4.3 卻拖到 2026。** 因為 Blizzard 在 WotLK Classic 這一版把物件更新協定整個換成 retail Legion+ 的 descriptor 制，**與 3.3.5a 的 updatemask 之間沒有欄位對應關係，必須手寫整棵欄位樹**。這也回頭佐證了上游 `wotlk_classic` 分支那一串 `Core/PacketIO: Update <X> to 3.4.4` commit 為什麼做不完。

### 3.3 進度矩陣（文件自述日期：2026-09-03）

文件維護一張 `Subsystem | TC 3.3.5a | cMangos 3.3.5a | AzerothCore 3.3.5a | Notes` 的表，逐列標 ✅/⚠️/❌/❓。實際狀況摘要：

**已驗證會動（✅，多數三個後端都通）**：auth + char-select、world-enter + 走路 + 鏡頭、角色與裝備 render、自動攻擊、特殊技能、引導法術（cast bar / 動畫）、飛行投射物、**死亡騎士建角 + 符文 / 符能**、雕文（套用 / 移除 / 雙天賦切換）、聊天 / 隊伍 / 團隊 / 團隊警告、交易、郵件（收 + 附件 + COD + 寄件）、成就面板 + criteria 進度、傳家寶收藏、玩具箱、法術書登入動畫、寵物法術書、修理、靈魂醫者復活、爐石綁定、**戰場（列表 / 排隊 / 傳送 / 計分板）**、**冬擁湖**、**競技場 skirmish 2v2/3v3/5v5**、頭銜、**Master Looter**、**Dungeon Finder（排隊 / proposal / 進入 / 傳送 / 離開）**、**拍賣場（搜尋 / 出價 / 一口價 / 上架 / 取消 / 售出郵件）**、運輸工具（電梯 / 地鐵 / 飛艇 / 船）、準備確認、團隊標記、洗天賦、聲望面板、榮譽 / 貨幣面板、副本鎖定 + 英雄難度切換。

**明確未橋接（❌，三個後端皆是）**：
- **理髮店（Barber shop）** — 「`CMSG_ALTER_APPEARANCE` is mapped on both sides (modern 13557, legacy 0x426) but has **no handler**」
- **行事曆（Calendar）** — 「The modern enum contains exactly one calendar opcode (`CMSG_CALENDAR_GET_NUM_PENDING` = 13948) with no handler and no packet class」

**從未被測過（❓，2026-09-01 稽核 opcode enum 時新增）**：教學提示（Tutorials）、餵寵物 / 快樂度、釣魚（施放 / 浮標 / 上鉤）、開鎖 / 開啟上鎖容器 等。文件明說這些是「nobody has ever driven them, **not because they are known broken**」。

**cMaNGOS 是明顯落後的後端**：`Combat — special abilities` 在 cMaNGOS 上是 ❌（"invalid target" on e.g. Heroic Strike）、`Raid kick` 會解散整個團隊、飛艇 / 船 ❌。

### 3.4 開發者自己列的「卡住的地方」（Open issues）

這是任務指名要的內容，逐項摘錄（原文為英文，以下為摘要，關鍵句保留原文）：

1. **職業技能的兩個系統性 pattern**（承接 fork issue `advocaite/HermesProxy-WOTLK#14`，由 `kasperfriend` 於 **2026-04-18** 提交的全職業測試矩陣——該 issue 經 API 驗證存在、標題 "ALL classes tested - results"、**至今仍 open**）：
   - **Pattern A**：自身施放的驅散 / 淨化被拒絕，錯誤訊息卻是「can't mount here」，影響 5+ 職業（聖騎士 Cleanse/Purify、牧師 Dispel Magic/Cure Disease、薩滿 Purge/Cleanse Spirit/Cure Toxins、法師 Remove Curse、德魯伊 Cure Poison/Remove Curse）。研判是 `CMSG_CAST_SPELL` 自我目標編碼缺口，或 `SMSG_CAST_FAILED` 原因碼翻譯錯誤。
   - **Pattern B**：地面指定 AOE 被拒絕，訊息是「item is not ready yet」，影響 4+ 職業。研判是 V3_4_3 的 `CMSG_CAST_SPELL` **ground-target position vector 版面**缺口。
2. **復活虛弱不顯示紅字 / `*75%`**（2026-05-31 起未解，**這一項最能說明 proxy 路線的架構天花板**）：
   > "The native 3.4.3 *server* computes **derived display fields that a legacy 3.3.5a server never populates** … and the red text keys off those. … Closing it properly means **synthesizing the derived fields** from the aura's `MOD_PERCENT_STAT` / `MOD_DAMAGE_PERCENT_DONE` effects — a real feature, deferred."

   → 也就是說：**有些現代 client 期待的欄位，3.3.5a 伺服器根本不存在**，proxy 必須自己合成。翻譯層不是萬能的，這類「後端沒有的資訊」是 Path D 的結構性成本。
3. **仍無 handler 的封包（靜默掉狀態）**：`SMSG_INSTANCE_DIFFICULTY`（legacy 0x33B）、`SMSG_LEARNED_DANCE_MOVES`。
4. **2306 筆 `ItemSparse` 資料列被丟棄** —— `sbyte→short` 欄寬 loader bug，「Raid-tier WotLK gear with stats > 127 is silently dropped」。（目前靠 legacy `SMSG_ITEM_QUERY_SINGLE_RESPONSE` 這條舊路徑補救 tooltip。）
5. **Flat/Pct spell modifier 陣列形狀未定**：原生 TC 3.4.3 一律送 40 列（~204 B），proxy 只送有值的（~14 B）；文件老實寫「**the symptom is speculative** — no user-visible failure has been tied to it」。

### 3.5 它的資料策略（對比 `wotlk_classic` 的病灶）

- 現代側的 DB2 資料是 **18 張 hotfix CSV，從 `wago.tools` 以 `?build=3.4.3.54261` 產生，約 70 萬筆記錄**。
- 驗證程序寫得很具體：比對 wago 匯出的欄位順序與 `World/GameData.cs` 中 `Load*` 方法期待的順序（「column-order mismatch … is the common failure mode」），並抽驗 3–5 筆已知 WotLK 資料列（例：ItemID 49426 *Emblem of Frost*）確認 build filter 正確。

**關鍵對照：這正是 TrinityCore `wotlk_classic` 沒做完的那一半，而 HermesProxy 用「後端 world DB 完全不動 + 現代側只補 DB2/hotfix」的方式繞開了。**

### 3.6 ground-truth 方法論（技術上值得學的一段）

文件描述了一套**用原生伺服器當「wire format 神諭」**的流程：
- 用 **Wrathion**（`Xian55/3.4.3_Source`，build 23121）或 **`RioMcBoo/CypherCoreClassicWOTLK`** 跑原生 3.4.3，client 直連、**不經 proxy**，在 `worldserver.conf` 設 `PacketLogFile = "World.pkt"` 產生封包側錄。
- 用 **`RioMcBoo/WowPacketParser`** fork 解析（`V3_4_3_54261` 由 PKT 3.1 header 自動偵測）。
- 拿解析結果與 proxy 的輸出逐 byte diff。
- 文件自己加的但書：「**The native server is an oracle for wire format, not for game logic.** Wrathion is TrinityCore-derived and carries its own bugs; where one exists, a capture of it is a capture of the bug.」
- 安全提醒（原文）：「Captures contain SRP6 session keys + account hashes — **do not commit or share**.」

**這套方法論本身是可移植的**：任何人要做 3.4.x 協定工作，「原生伺服器側錄 → WPP 解析 → byte diff」就是目前公開可見的最佳實務。

---

## 4. 這趟對前三篇筆記的具體修正

| 前文結論 | 出處 | 修正後 |
|---|---|---|
| 「WotLK Classic 3.4.x：**沒有**任何專案」 | 全景調查 §7 | **不成立。** `Xian55/HermesProxy`（3.4.3 分支，2026-09-02）、`lineagedr/3.4.3_Source`（2026-05）、`RioMcBoo/CypherCoreClassicWOTLK`（2026-03）、`alseif0x/rustycore`（2026-09-01）皆為 3.4.3.54261 目標且皆非死亡 |
| 「CypherCore 只有一條 master，沒有 Classic 分支」 | 全景調查 §5 | 對**上游**仍正確；但其 fork `RioMcBoo/CypherCoreClassicWOTLK` 的 default branch 就是 `WOTLK_CLASSIC` |
| 「Classic Era 1.14 唯一觸及者是 `raewow/oxcore`」 | 全景調查 §7 | **不完整。** HermesProxy 家族做 1.14↔1.12 已多年（原專案 ★358），而且是**可用的**（有 release） |
| 三條路徑 A / B / C | WotLK 筆記 §4 | **應增列 Path D：協定翻譯 proxy**（現代 client + 既有 3.3.5a 伺服器 + 中間翻譯層）。它避開了 Path C 兩個最大成本項：opcode 表重寫、world DB 重建 |
| 「卡住的是伺服器端 core + world database，不是 client patching」 | 全景調查 §6 | **仍然正確，但 Path D 證明這個瓶頸可以繞過**——不重建內容庫，改在協定層翻譯 |

**沒有被推翻的部分（很重要）：**

- **client 取得問題原封不動。** 上述全部釘在 **3.4.3.54261**；[macOS 筆記](./macos-client-options.md)§3.3 實測該 build 的 CDN build config 為 **HTTP 404**，Battle.net 的 `wow_classic` 現在只給 5.5.4.69585。**沒有 3.4.3 client 就沒有這條路。** 這些專案都預設你**已經**有一份 3.4.3 安裝。
- **3.4.4.61581 仍然沒有任何人在做。** 使用者指定的目標 build 依舊是零。
- **官方上游 `wotlk_classic` 依然是死的**（2025-07-02）。

---

## 5. 明確記錄「拿不到 / 沒做」的部分

- **三個 RaGEZONE 版面與所有討論串內文：完全未讀取（HTTP 403）。** 因此本文**沒有引用任何論壇貼文的文字、使用者名稱、發文日期**——任務要求「引用必須來自實際取得的頁面」，論壇一頁都沒取得。
- **未做**：註冊 / 登入 / 繞過 Cloudflare / 瀏覽器自動化。
- **未做**：任何 client / repack / 種子 / 檔案空間連結的蒐集或記錄。
- **未驗證**：`lineagedr/3.4.3_Source` 是否真的「70% playable」——這是作者自述，未實測。
- **未驗證**：`Xian55/HermesProxy` 的 `wotlk.md` 所述進度矩陣的正確性——這是開發者自述，未實測。（但它自我標註的誠實度異常高：明確區分「已驗證通過」「從未測過」「已知未橋接」，甚至寫下「the symptom is speculative」「the AzerothCore column is deliberately not re-ticked」。這種寫法本身是可信度的正向訊號。）
- **未驗證**：Wrathion 的 4 個 SQL dump（auth/characters/world/hotfixes）從何取得、內容為何。它們不在 repo 內。
- **本文不是窮舉。** 只追了搜尋引擎索引到的少數討論串所指向的 repo。RaGEZONE 版面內可能有大量未被索引、或索引不到的技術討論。
- **未找到**：任何 RaGEZONE 上關於 **TACT / NGDP / CASC build 存檔**的技術討論（任務第 4 點）。本次搜尋沒有命中任何這類討論串；相關的一手材料仍然只有 [macOS 筆記](./macos-client-options.md)§3 的 wowdev.wiki + 實測 CDN。
- **未找到**：任何 **MoP Classic 5.5.x** 或 **Classic Era 1.15** 伺服器端實作的線索。

---

## 6. 驗證方式（可重跑，全部唯讀）

```bash
# 論壇可及性（預期 403 / 200）
curl -sS -o /dev/null -w "%{http_code}\n" -A "Mozilla/5.0" \
  https://forum.ragezone.com/community/wow-releases.436/
curl -sS https://forum.ragezone.com/robots.txt

# HermesProxy 家族
for r in WowLegacyCore/HermesProxy advocaite/HermesProxy-WOTLK Xian55/HermesProxy; do
  gh api repos/$r --jq '{full_name,license:.license.spdx_id,stars:.stargazers_count,archived,pushed_at}'
  gh api repos/$r/branches --jq '[.[].name]|join(", ")'
done

# 3.4.3 分支的活躍度與規模
gh api "repos/Xian55/HermesProxy/commits?sha=feature/wotlk-classic-v3.4.3&per_page=1" \
  --jq '.[0]|"\(.commit.author.date) \(.sha[0:10]) \(.commit.message|split("\n")[0])"'
gh api "repos/Xian55/HermesProxy/compare/master...feature/wotlk-classic-v3.4.3" \
  --jq '"\(.status) ahead:\(.ahead_by) files:\(.files|length)"'

# 本文第 3 節的全部內容來源
gh api "repos/Xian55/HermesProxy/contents/wotlk.md?ref=feature/wotlk-classic-v3.4.3" \
  --jq '.content' | base64 -d

# Wrathion 的架構驗證（不是讀 README，是讀原始碼）
gh api repos/lineagedr/3.4.3_Source/readme --jq '.content' | base64 -d
gh api "repos/lineagedr/3.4.3_Source/contents/src/server" --jq '.[].name'   # 含 proto/
curl -s https://raw.githubusercontent.com/lineagedr/3.4.3_Source/main/src/server/game/Miscellaneous/SharedDefines.h \
  | grep CURRENT_EXPANSION
curl -s https://raw.githubusercontent.com/lineagedr/3.4.3_Source/main/src/tools/map_extractor/System.cpp \
  | grep CONF_Product

# CypherCore 的 WotLK Classic fork
gh api repos/RioMcBoo/CypherCoreClassicWOTLK \
  --jq '{default_branch,parent:.parent.full_name,stars:.stargazers_count}'

# fork issue（3.4.3 職業測試矩陣的原始出處）
gh api repos/advocaite/HermesProxy-WOTLK/issues/14 --jq '"\(.title) \(.state) \(.created_at) \(.user.login)"'
```

---

## 7. 實際取用過的來源

**論壇（僅取得標題與 URL，內文 403 未取得）**
- `https://forum.ragezone.com/robots.txt`（唯一實際取得內容的 ragezone 頁面）
- `https://forum.ragezone.com/threads/wow-wotlk-3-4-3-classic-working-client-for-any-server-with-new-hermesproxy.1263743/`
- `https://forum.ragezone.com/threads/native-open-source-3-4-3-wrath-classic-server.1270109/`
- `https://forum.ragezone.com/threads/wow-tbc-2-5-2-classic-working-client-any-legacy-server-setup-guide.1264224/`

**GitHub（一手，全部實際取得並驗證）**
- `https://github.com/Xian55/HermesProxy` — repo metadata、branches、compare、releases、README、`wotlk.md`（分支 `feature/wotlk-classic-v3.4.3`）
- `https://github.com/WowLegacyCore/HermesProxy` — README、archived 狀態
- `https://github.com/advocaite/HermesProxy-WOTLK` — README 支援表、issue #14
- `https://github.com/lineagedr/3.4.3_Source` — README、root tree、`src/server/` 內容、`SharedDefines.h`、`map_extractor/System.cpp`
- `https://github.com/Xian55/3.4.3_Source` — Wrathion 的 fork（parent 驗證）
- `https://github.com/RioMcBoo/CypherCoreClassicWOTLK` — default branch `WOTLK_CLASSIC`
- `https://github.com/RioMcBoo/WowPacketParser`
- `https://github.com/alseif0x/rustycore` — default branch `3.4.3`，複驗

**取用失敗（明確記錄）**：RaGEZONE 三個版面與所有討論串頁面（HTTP 403，WebFetch 與 curl 皆然）。
