# 把 3.4.3.54261 client 變成繁體中文（zhTW）：能做到哪裡

> ⚠️ **更正（2026-09-04）**
>
> 本篇 §2.5「MPQ 補丁在 CASC 上沒有等價物 / 無鬆散檔案覆蓋」**已被實測推翻**——客戶端在讀 CASC 前會先找磁碟檔案，`Fonts/` 與 `Interface/WorldMap/` 皆生效。本篇對「天花板」的估計因此偏低（美術與字型皆可覆蓋）。
>
> 詳見 [實作記錄與更正](./zhtw-implementation-and-corrections.md)。


> 撰寫日期：2026-09-03
> 相關筆記：[hotfix DB2 中文化深度評估](./hotfix-db2-localization.md)（**§4.3 的後續追查，結論改為「可行」，並修正本篇 §1.2 的兩個列數**）、[HermesProxy 決策級評估](./hermesproxy-evaluation.md)（本篇假設走這條 stack）、[macOS client 取得與執行](./macos-client-options.md)（§3 的 CDN 404 牆，本篇 §1.3 直接繼承）、[WotLK Classic 移植路線圖](./wotlk-classic-port-roadmap.md)、[用 addon 中文化 UI 框架字串](./ui-localization-addon.md)（§4.1 最後一列與 §6 天花板對 UI 的判斷已被推翻）
> 前提（本機實測，非假設）：使用者手上已有 **Windows 版 WoW Classic `3.4.3.54261`**，解壓在 `~/World of Warcraft 3.4.3.54261/`，`.build.info` 的 `Tags` 欄只有 **`enUS`** 與 **`ruRU`**（EU branch、`acct-UKR`、`geoip-UA`），在 Whisky / GPTK 的 Wine 下以 D3D12 → D3DMetal 可啟動並渲染。
> 來源限定 primary sources：本機 client 檔案（實際 `cat` / `xxd` / `ls`）、本 repo 原始碼與 `git show origin/3.3.5:<path>`（唯讀，未切換分支）、`Xian55/HermesProxy` 原始碼（`gh api` + 分支 tarball）、`dep/CascLib` 原始碼、Blizzard 自家 zh-tw 新聞與 `wow.blizzard.cn`、`us.version.battle.net`、`wago.tools` 的 DB2 匯出（實際 curl）。
> wowdev.wiki 為**社群維護的 wiki，非 Blizzard 官方**，凡引用皆已標明。
> 凡未實測者一律標示「**未驗證**」。本文不記錄任何 game client 或 repack 的取得途徑。

---

## 0. TL;DR

1. **zhTW 的 WotLK Classic 確實存在過。** Blizzard 自家的繁中新聞站有完整的 2022–2023 系列報導（launch、前夕改版、Ulduar…）。而更硬的證據是：`wago.tools` 至今能匯出 **build `3.4.3.54261` 的 zhTW DB2**（`SpellName` 49,357 列、`Spell` 53,071 列、`ItemSparse` 45,070 列，全部是中文）。**這正是使用者手上這一個 build 的繁中資料。**
2. **但拿不到「完整 zhTW client」。** zhTW 不是另一個 build，而是**同一個 build 上的 CASC install tag**。要補裝 zhTW 資料就得回 Blizzard CDN 抓，而 `3.4.3.54261` 的 build config 已實測 **404**（[macOS 筆記](./macos-client-options.md)§3.3）。**同一道牆，沒有第二扇門。**
3. **MPQ 時代的「漢化補丁」在 CASC 沒有對應物。** CascLib 是唯讀函式庫，wowdev.wiki 對 CASC/TACT 完全沒有記載任何第三方 override / patch 注入路徑。這條路是死的。
4. **真正可用的槓桿在伺服器端，而且比預期大得多。** HermesProxy 把 3.4.3 client 的所有 query 轉給 3.3.5a 後端：任務、生物、物件、書頁、NPC 對話、物品 —— **這六類全部走 TrinityCore 3.3.5 的 `*_locale` 表**。這些正好是玩家 90% 的閱讀時間所在。
5. **而且不用改一行資料庫就能切到 zhTW。** 本機追出的完整鏈路：client `textLocale` → BNet `LogonRequest.Locale` → `globalSession.Locale` → `AuthClient.ConnectToAuthServer(..., locale)` → 3.3.5a logon challenge 的 `country` 欄 → `AuthSession.cpp:308 GetLocaleByName()` → `UPDATE account SET locale = ?` → `WorldSocket.cpp:280` → `WorldSession::m_sessionDbLocaleIndex`。**在 HermesProxy 改一行（硬寫 `"zhTW"`）就能讓 3.3.5a 後端吐繁中，client 端完全不用動。**
6. **一個很重要的反直覺發現：把中文寫進 `locale='enUS'` 的列是沒用的** —— TrinityCore 的所有 `Load*Locales()` 都明確 `if (locale == LOCALE_enUS) continue;`。要走「不改 locale」的路，只能改**基礎表的英文欄位本身**。
7. **字型不是問題（本機實測）。** 這份 enUS+ruRU 安裝的 `_classic_/Fonts/` 裡已經有 **`615974.slug` = `fonts/arkai_t.ttf`，33,328,656 bytes** —— **ARKai_T 就是 zhTW WoW 的繁中字型**。另有 `615968` = `fonts/2002b.ttf`（韓文，5.9 MB）。字型不帶 locale tag，是全域安裝的。
8. **天花板很清楚**：法術名稱／描述、天賦、成就、地圖與區域名、UI 框架字串全部住在 client 自己的 DB2 / FrameXML 裡，伺服器碰不到。hotfix 機制**理論上**能覆寫其中一部分（`SpellName`、`Spell` 的 loader 已經存在、資料在 wago.tools 也拿得到），但 HermesProxy 對 3.4.3 的 `TableFilter` 目前只放行 `AreaTrigger` 一張表，而且維護者自己記錄過「~5 MB 的 `SMSG_AVAILABLE_HOTFIXES` 會讓 client 直接放棄解析」。**大規模 hotfix 漢化是有根據的推測，不是已驗證的路。** → **本結論已被 [hotfix DB2 中文化深度評估](./hotfix-db2-localization.md) 推翻：`TableFilter` 是效能修剪而非相容性限制，~5 MB 的失敗真因是壓縮 bug。改判「可行」。**

---

## 1. zhTW / zhCN 的 WotLK Classic 官方史實

### 1.1 zhTW：存在，且有 Blizzard 自家的完整報導（已驗證）

Blizzard 繁中新聞站 `news.blizzard.com/zh-tw/world-of-warcraft/` 有整條 2022–2023 的 WotLK Classic 內容線：

| 內容 | URL |
|---|---|
| 上市日公告《巫妖王之怒》經典版™ 將在 9 月 27 日登場 | `https://news.blizzard.com/zh-tw/world-of-warcraft/23833251/` |
| 前夕改版已經推出 | `https://news.blizzard.com/zh-tw/world-of-warcraft/23847495/` |
| 破冰而出：現已推出！ | `https://news.blizzard.com/zh-tw/world-of-warcraft/23850854/` |

**未驗證：** 找不到任何 Blizzard 第一方頁面明文列出「WoW Classic 支援哪 N 個語系」。`us.support.blizzard.com/en/article/11417`（Changing Your Text Language）只講怎麼改，不列清單。

### 1.2 更硬的證據：`3.4.3.54261` 的 zhTW DB2 今天還能匯出（實測）

比新聞稿更有決定性的一項。對 `wago.tools`（**第三方社群存檔，非 Blizzard 服務**）實測：

```
curl "https://wago.tools/db2/SpellName/csv?build=3.4.3.54261&locale=zhTW"
ID,Name_lang
1,"Word of Recall (OLD)"
3,"Word of Mass Recall (OLD)"
4,召回他人之語
```

同一組查詢的列數（實測）：

| DB2 表 | zhTW 列數 |
|---|---|
| `SpellName` | 49,357 |
| `Spell`（含 Description / AuraDescription） | 53,071 |
| `ItemSparse` | 45,070 |
| `AreaTable` | 2,373 |
| `Achievement` | 1,912 |
| `Talent` | 892 |
| `Faction` | 403 |
| `GlyphProperties` | 365 |
| `Map` | 177 |
| `SkillLine` | 152 |
| `ChrRaces` / `ChrClasses` | 21 / 10 |

**意義有兩層：**
1. **zhTW 的 WotLK Classic 資料是綁在使用者手上這個 build（`3.4.3.54261`）上的**，不是別的版本。§1.1 的新聞稿因此不是孤證。
2. **繁中「文字資料」本身是可取得的**，取不到的是「打包進 CASC 的那份 client 安裝」。這個區分是本篇後半段所有可能性的來源 —— 見 §4。

### 1.3 但這不代表能補裝 zhTW（承接 macOS 筆記）

zhTW **不是另一個 build**，是同一個 build 上的 **CASC install tag**（見 §2.1）。要補資料只能回 Blizzard CDN 取回該 build 的 build config → CDN config → 對應 locale 的 root/encoding 物件。而 [macOS 筆記](./macos-client-options.md)§3.3 已實測：

| build | build config | `us.cdn.blizzard.com` |
|---|---|---|
| `3.4.3.54261` | `c91609c6…` | **404** |

本機 `.build.info` 的 Build Key 正是 `c91609c69ed2ab39d44039390a1be969` —— **和該筆實測是同一個 hash**。所以：**取得「完整 zhTW client」與取得「這個 build 本身」是同一道牆，不是兩件事。**

### 1.4 zhCN：存在過、中斷過、回來過

| 事件 | 日期 | 來源與可信度 |
|---|---|---|
| 網易代理到期，暴雪遊戲在中國大陸停止服務 | 2023-01-24 | NetEase 自家公告〈网之易关于暴雪游戏产品运营到期的重要公告〉。**直接 fetch 失敗（`news.blizzardgames.cn` DNS 無法解析），日期由二手中文媒體佐證 → 標為未驗證** |
| 《巫妖王之怒》經典版在中國大陸正式回歸 | **2024-07-11** | **已驗證**：Blizzard 中國官網 `https://wow.blizzard.cn/news/23850855/`〈《魔兽世界》"巫妖王之怒"现已正式归来〉 |
| 2024 年新代理協議、正式服 8 月回歸、懷舊服 6/27 預熱 | 2024-04 / 2024-06 / 2024-08 | 僅有二手媒體，**未驗證** |

**對本題的意義：** zhCN 的 WotLK Classic 存在過、也仍在營運，但那條產品線走的是 `cn` region（`us.version.battle.net/v2/products/wow_classic/cdns` 實測：`cn` 的 CDN host 是 `blzdist-wow.necdn.leihuo.netease.com`，網易自營）。同一份 `cdns` 回應也確認 **`tw` region 存在**（與 `us` 共用 `level3.blizzard.com` / `us.cdn.blizzard.com`）。但這只是**當前（2026-09）狀態**，且不改變 §1.3 的結論 —— region 存在，`3.4.3.54261` 的物件仍然是 404。

---

## 2. CASC 的 locale 機制（技術）

> 本節的規格面主要來自 **wowdev.wiki（社群維護，非 Blizzard 官方）** 與本 repo `dep/CascLib` 的原始碼；原始碼部分為第一手可驗證。

### 2.1 locale 是 install tag，不是 build

`.build.info` 的 `Tags` 欄由 Battle.net Agent 寫入。本機這份的實際內容（實測）：

```
Windows x86_64 EU? acct-UKR? geoip-UA? enUS speech?
Windows x86_64 EU? acct-UKR? geoip-UA? enUS text?
Windows x86_64 EU? acct-UKR? geoip-UA? ruRU speech?
Windows x86_64 EU? acct-UKR? geoip-UA? ruRU text?
```

→ **只有 enUS 與 ruRU 的 text + speech。** CascLib 直接解析這一欄：`dep/CascLib/src/CascFiles.cpp:706` 呼叫 `GetDefaultLocaleMask(Csv[nSelected]["Tags!STRING:0"])`（實作在 `CascFiles.cpp:587-605`），把辨識到的四字母 locale code OR 成 mask；若呼叫端沒有指定 mask，就用這個當預設（`CascOpenStorage.cpp:1226`）。

wowdev.wiki 的 TACT 頁對 install manifest 的說明：

> "The install file lists files installed on disk. Since the install file is shared by architectures and OSs, there are also tags to select a subset of files."

tag 的型別（同頁，build ≥ 8.0.1.26604）：`platform=1, architecture=2, **locale=3**, region=4, category=5, alternate=0x4000`。

### 2.2 locale mask 的位元值（第一手，本 repo 原始碼）

`dep/CascLib/src/CascLib.h:100-119`：

```c
#define CASC_LOCALE_ALL_WOW         0x0001F3F6  // All except enCN and enTW
#define CASC_LOCALE_ENUS            0x00000002
#define CASC_LOCALE_ZHCN            0x00000040
#define CASC_LOCALE_ZHTW            0x00000100
#define CASC_LOCALE_RURU            0x00002000
```

wowdev.wiki 的 `locale_flags` enum 與這串**逐位元完全一致**。

TrinityCore 自己也有一份對照（`src/common/Common.h:70-89` 的 `enum class CascLocaleBit`，`zhTW = 8` 為 bit index，`1 << 8 = 0x100`，與上表相符）。

### 2.3 同一個 FileDataID 的多語系變體怎麼選

`dep/CascLib/src/CascRootFile_WoW.cpp` 的 `ParseWowRootFile_Level2`（約 445-451 行）：

```cpp
// WoW.exe (build 19116): Locales other than defined mask are skipped too
if(RootBlock.Header.LocaleFlags != 0 && (RootBlock.Header.LocaleFlags & dwLocaleMask) == 0)
    continue;
```

WoW root file 由多個 block 組成，每個 block 帶自己的 `LocaleFlags`。同一個 FileDataID 可以在不同 locale 的 block 各有一份 CKey。**mask 沒對上的 block 根本不會被插進 file tree** —— 不是「查得到但拿不到」，是「根本不存在」。

### 2.4 `SET textLocale` / `SET audioLocale`

本機 `WTF/Config.wtf` 實測（同一檔亦可見 `SET portal "127.0.0.1"`，證明已按 HermesProxy 的說明設定過）：

```
SET textLocale "enUS"
SET audioLocale "enUS"
```

Blizzard 官方文件（`https://us.support.blizzard.com/en/article/11417`）只描述用 Battle.net App 的 Game Settings 改 Text / Spoken Language —— **這同時也是決定哪些 locale tag 會被下載的機制**。直接編 `Config.wtf` 是社群作法（Blizzard 論壇上有使用者貼文，但那是使用者發言，不是規格）。

**把 `textLocale` 設成沒安裝的 locale 會怎樣？** 依 §2.3 的機制推論：該 locale 的 root block 全部被 skip，client 對那些 FileDataID 查不到任何檔案。**CascLib 本身沒有任何 locale fallback**；client 上層是否有 fallback、以及失敗時是崩潰／回退英文／空字串 —— **wowdev.wiki 與 CascLib 都沒有記載，標為未驗證推論。**

> **實務上這一格不重要。** §3.4 會說明：真正需要改的不是 client 的 `textLocale`，而是 **proxy 往 3.3.5a 後端報告的 locale**。這兩件事在 HermesProxy 的架構下是分開的。

### 2.5 MPQ 時代的漢化補丁，在 CASC 沒有對應物（結論明確）

- **MPQ 時代**：wowdev.wiki 的 MPQ 頁描述 patch archive 以 `PTCH` entry、同檔名覆寫 base archive，client 依優先序套用。這就是 `patch-X.MPQ` 漢化補丁的機制。
- **CASC 時代**：wowdev.wiki 的 CASC / TACT 兩頁**完全沒有**任何「override archive」「loose patch file」「第三方可寫入路徑」的描述。CASC 是 content-addressable，檔案以 encoding key（hash）定址。
- **CascLib 的公開 API（`dep/CascLib/src/CascLib.h:393-427`）全部是唯讀**：`CascOpenStorage` / `CascOpenFile` / `CascReadFile` / `CascFindFirstFile` / `CascGetFileInfo`…… **沒有 `CascWriteFile`、沒有 `CascCreateFile`。** repo 內 README 自述："An open-source implementation of library for reading CASC storage from Blizzard games since 2014."

**平白講：MPQ 時代的社群翻譯補丁，在現代 client 上沒有等價物。** 這是負面發現（找不到記載），不是「已證明不可能」；但兩個獨立來源（社群 wiki 的規格頁 + 業界標準實作的 API 面）都指向同一結論。

**唯一的例外是 loose 檔案的字型目錄**，見 §4.4 —— 而那正好是本篇最好的運氣。

---

## 3. 伺服器端能做什麼 —— 本篇最有價值的一節

### 3.1 `LocaleConstant`：zhTW 在兩條分支上都是一等公民（已驗證）

`src/common/Common.h:49-65`（master）與 `git show origin/3.3.5:src/common/Common.h:47-60`（3.3.5 分支）：

| | master | `origin/3.3.5` |
|---|---|---|
| `LOCALE_zhCN` | 4 | 4 |
| **`LOCALE_zhTW`** | **5** | **5** |
| `LOCALE_ruRU` | 8 | 8 |
| `LOCALE_none` | 9 | *（不存在）* |
| `LOCALE_ptBR` / `itIT` | 10 / 11 | *（不存在）* |
| `TOTAL_LOCALES` | 12 | 9 |

`src/common/Common.cpp:20-35` 的 `localeNames[]` 字串就是 `"zhTW"`，`GetLocaleByName()` 逐一比對。

**→ 使用者要走的 HermesProxy 路徑用的是 `3.3.5` 後端，而 `3.3.5` 分支的 `LOCALE_zhTW = 5` 完全存在、行為與 master 一致。這一項沒有任何缺口。**

### 3.2 `origin/3.3.5` 的 world DB 有哪些 `*_locale` 表（實測列舉）

以 `git show origin/3.3.5:sql/base/dev/world_database.sql` 全文掃描（該檔 4,074 行、186 張表），`_locale` 結尾的表共 **16 張**：

| 表 | 可翻譯欄位 | 玩家在哪看到 |
|---|---|---|
| **`quest_template_locale`** | `Title`, `Details`, `Objectives`, `EndText`, `CompletedText`, `ObjectiveText1-4` | **任務日誌、接任務視窗、交任務視窗** |
| `quest_offer_reward_locale` | 交任務對話 | 交任務視窗 |
| `quest_request_items_locale` | 未完成時的對話 | 交任務視窗 |
| `quest_greeting_locale` | NPC 開場問候 | 對話視窗 |
| **`creature_template_locale`** | `Name`, `Title` | **所有 NPC / 怪物名稱與頭銜** |
| **`item_template_locale`** | `Name`, `Description` | **所有物品名稱與敘述文字** |
| `gameobject_template_locale` | `name`, `castBarCaption` | 採集點、寶箱、門、施法條 |
| **`gossip_menu_option_locale`** | `OptionText`, `BoxText` | **所有 NPC 對話選項** |
| **`npc_text_locale`** | `Text0_0` … `Text7_1`（16 欄） | **NPC 對話本文** |
| `broadcast_text_locale` | `Text`, `Text1` | NPC 喊話 / 情緒動作文字 |
| `creature_text_locale` | `Text` | 副本 boss 台詞、怪物喊話 |
| `page_text_locale` | `Text` | 書、卷軸、告示牌 |
| `points_of_interest_locale` | `Name` | 地圖上的指路標記名稱 |
| `achievement_reward_locale` | `Subject`, `Body` | 成就獎勵信件 |
| `item_set_names_locale` | 套裝名稱 | 套裝 tooltip |
| `trainer_locale` | 訓練師問候語 | 訓練師視窗 |

另有 `trinity_string`（`content_default` + `content_loc1`…`content_loc8`）—— 伺服器自己的系統訊息與 GM 指令輸出，`content_loc5` 對應 zhTW。

**涵蓋率的誠實評估（本人判斷，非引用）：** 這 16 張表涵蓋的是「**由伺服器發送、client 只負責顯示**」的那一半文字 —— 任務全文、NPC 名字與對話、物品名稱與敘述、書頁、boss 台詞。以一個玩家在 WotLK 從 1 到 80 的閱讀時間分佈來說，**這一半佔絕大多數**。另一半（法術、天賦、成就、地圖、UI）住在 client，見 §4。

### 3.3 伺服器怎麼決定要送哪個 locale（`origin/3.3.5` 原始碼追蹤）

完整鏈路，四段全部實測：

```
① authserver：client 的 logon challenge 帶 country 欄（4 bytes，反序）
   src/server/authserver/Server/AuthSession.cpp:308
       _locale = GetLocaleByName(ClientBuild::ToCharArray(challenge->country).data());

② 認證成功時寫進 auth DB
   src/server/authserver/Server/AuthSession.cpp:521-524   stmt->setUInt32(2, _locale);
   src/server/database/.../LoginDatabase.cpp:39
       UPDATE account SET session_key_auth = ?, last_ip = ?, last_login = NOW(),
              locale = ?, failed_logins = 0, os = ?, timezone_offset = ? WHERE username = ?

③ worldserver 進世界時讀回來
   src/server/game/Server/WorldSocket.cpp:265,280,292-293
       // SELECT ... a.locale ...
       Locale = LocaleConstant(fields[7].GetUInt8());
       if (Locale >= TOTAL_LOCALES) Locale = LOCALE_enUS;

④ 存進 session，之後所有 *_locale 查詢都用它
   src/server/game/Server/WorldSession.cpp:133   m_sessionDbLocaleIndex(locale)
   WorldSession.h:1199                           GetSessionDbLocaleIndex()
```

`GetSessionDbLocaleIndex()` 在 `origin/3.3.5` 全樹有數十個呼叫點：`GossipDef.cpp`（對話）、`ItemHandler.cpp:304`（物品查詢）、`QuestDef.cpp:653-655`（每個 locale 各預先組一份 `QueryData` 封包）、`AuctionHouseMgr.cpp:710`（拍賣搜尋）、`AchievementMgr.cpp:1569`、`GridNotifiersImpl.h` 等。

> **關鍵可操作點：`account.locale` 每次登入都被 ②「覆寫」。** 所以手動 `UPDATE account SET locale = 5` **不會生效**（下次登入就被打回去）。要改必須改「送出 country 欄的那一端」—— 而在這條 stack 上，那一端是 HermesProxy，不是 client。見 §3.4。

另有一個獨立旋鈕：`worldserver.conf.dist:638-651` 的 **`DBC.Locale`**（`5` = Taiwanese）。但它控制的是**伺服器端讀取 `.dbc` 檔的語言**（`m_sessionDbcLocale`），需要一份從 zhTW 3.3.5a client 抽出來的 DBC —— 使用者沒有，且它與 `*_locale` 表無關。**列出僅為完整性，不是可用路徑。**

### 3.4 ★ HermesProxy 把整條鏈接起來了（原始碼實測）

這是本篇最有價值的發現。追 `Xian55/HermesProxy@feature/wotlk-classic-v3.4.3` 的原始碼：

```
① 現代 client 的 Battle.net LogonRequest 帶 Locale 字串
   HermesProxy/BnetServer/Services/Services/Authentication.cs:39
       if (!LocaleChecker.IsValidLocale(logonRequest.Locale.ToEnum<Locale>()))
           return BattlenetRpcErrorCode.BadLocale;
   → Framework/Constants/Locale.cs 的 enum 與 TrinityCore 完全一致：zhCN = 4, zhTW = 5

② 塞進 REST 登入 URL 的第 4 段，再取回來
   HermesProxy/BnetServer/Networking/BnetRestApiSession.cs:102
       globalSession.Locale = pathElements[3];

③ 直接當成 legacy 登入的 locale
   HermesProxy/BnetServer/Networking/BnetRestApiSession.cs:121
       AuthResult response = globalSession.AuthClient.ConnectToAuthServer(login, password, globalSession.Locale);

④ 寫進 3.3.5a logon challenge 的 country 欄（反序，protocol 要求）
   HermesProxy/Auth/AuthClient.cs:292
       buffer.WriteBytes(Encoding.ASCII.GetBytes(_locale.Reverse()));
```

→ **④ 的輸出正好接上 §3.3 的 ①。整條路是通的。**

**因此有兩個可操作的做法：**

| 做法 | 動作 | 代價 | 風險 |
|---|---|---|---|
| **A. 改 proxy 一行（建議）** | 把 `AuthClient.cs` 的 `_locale`（或 `BnetRestApiSession.cs:121` 的第三個參數）硬寫成 `"zhTW"`，重新 `dotnet publish` | HermesProxy 是 GPL-3.0、.NET 10、macOS universal binary，自建成本低 | **client 完全不用動**（`textLocale` 保持 `enUS`，UI 仍英文），後端 `account.locale` 被寫成 5，之後所有 `*_locale` 查詢自動回繁中 |
| **B. 改 client 的 `textLocale "zhTW"`** | 只改 `Config.wtf` | 零編譯 | **未驗證且風險高**：client 端 zhTW CASC 資料不存在（§2.3），client 自己會怎麼反應無法預測 |

**做法 A 幾乎沒有下行風險**：3.3.5a 後端若某列沒有 zhTW 翻譯，`ObjectMgr::GetLocaleString()` 會退回基礎表的英文欄位。**不是全有全無，是逐列 fallback。**

### 3.5 ★ 「把中文寫進 enUS 列」這個直覺是錯的（已驗證）

任務描述裡提到的「crude but workable trick」需要修正一項。`git show origin/3.3.5:src/server/game/Globals/ObjectMgr.cpp`，`LoadQuestLocales()`（5390 行起）：

```cpp
LocaleConstant locale = GetLocaleByName(localeName);
if (locale == LOCALE_enUS)
    continue;                       // ← enUS 的列被直接跳過
```

同樣的 `if (locale == LOCALE_enUS) continue;` 在該檔出現 **14 次**（273、305、336、2912、3475、5411、6019、6278、6592、6620、6648、7484、9300、9846 行），涵蓋所有 `Load*Locales()`。

**→ 把中文塞進 `locale='enUS'` 的 `*_locale` 列，伺服器根本不會載入。這個 trick 無效。**

真正「不碰 locale 機制」的粗暴做法只有一種：**直接改基礎表的英文欄位** —— `quest_template.LogTitle` / `.QuestDescription`、`item_template.name`、`creature_template.name`、`gossip_menu_option.OptionText`、`page_text.Text` 等。

| | 改基礎表 | 改 `locale='zhTW'` + proxy 一行 |
|---|---|---|
| 需不需要改程式 | **不用** | 改 HermesProxy 一行 + 重新 build |
| 英文原文 | **被破壞，無法還原** | **保留**（切回 enUS 即恢復） |
| 沒翻譯到的列 | 維持英文 | 維持英文（fallback） |
| 與社群 SQL 的相容性 | 要重寫每一句 SQL | **社群 zhTW SQL 可直接匯入**（見 §5） |
| 建議 | ❌ | ✅ |

**明確結論：做法 A（改 proxy 一行 + 匯入 `locale='zhTW'` 列）在每一格都贏。基礎表覆寫只在「完全不想碰 proxy 原始碼」時才考慮。**

### 3.6 這些伺服器端字串真的會到達 3.4.3 client 嗎？—— 會（原始碼實測）

`HermesProxy/World/Client/PacketHandlers/QueryHandler.cs` 註冊的 legacy handler：

| 行 | opcode | 對應的 `*_locale` 表 |
|---|---|---|
| 26 | `SMSG_QUERY_QUEST_INFO_RESPONSE` | `quest_template_locale` 等 4 張 |
| 302 | `SMSG_QUERY_CREATURE_RESPONSE` | `creature_template_locale` |
| 396 | `SMSG_QUERY_GAME_OBJECT_RESPONSE` | `gameobject_template_locale` |
| 461 | `SMSG_QUERY_PAGE_TEXT_RESPONSE` | `page_text_locale` |
| 474 | `SMSG_QUERY_NPC_TEXT_RESPONSE` | `npc_text_locale` |
| 516 | `SMSG_ITEM_QUERY_SINGLE_RESPONSE` | `item_template_locale` |

而 `HotfixHandler.cs` 顯示 proxy 對 `DB2Hash.Item` / `DB2Hash.ItemSparse` 的處理：若快取沒有該物品，**就往 legacy server 發 `CMSG_ITEM_QUERY_SINGLE`**，拿到回應後再包成現代 hotfix 送給 client：

```csharp
GetSession().GameState.RequestedItemSparseHotfixes.Add(id);
WorldPacket packet2 = new WorldPacket(Opcode.CMSG_ITEM_QUERY_SINGLE);
```

**→ 物品名稱與敘述在 3.4.3 client 上顯示的來源，就是 3.3.5a 的 `item_template` + `item_template_locale`。** 對話（`gossip_menu_option_locale`）與 boss 台詞（`creature_text_locale` / `broadcast_text_locale`）走 chat / gossip 封包，同理。

---

## 4. 留在 client 端、伺服器碰不到的部分

### 4.1 清單

| 內容 | 住在哪 | 伺服器能改嗎 |
|---|---|---|
| 法術／技能**名稱** | `SpellName.db2` | ❌（除非 hotfix，見 §4.3） |
| 法術**描述 / tooltip** | `Spell.db2`（`Description`, `AuxDescription`） | ❌（同上） |
| 天賦名稱與描述 | `Talent.db2` / `SpellName` + `Spell` | ❌ |
| 成就名稱與描述 | `Achievement.db2` | ❌ |
| 地圖名、區域名、副本名 | `Map.db2` / `AreaTable.db2` / `LFGDungeons.db2` | ❌ |
| 職業、種族、專精名稱 | `ChrClasses.db2` / `ChrRaces.db2` | ❌ |
| 陣營／聲望名稱 | `Faction.db2` | ❌ |
| 技能線（採礦、鍛造…） | `SkillLine.db2` | ❌ |
| **所有 UI 框架字串**（按鈕、面板標題、錯誤訊息、`GlobalStrings`） | `Interface/FrameXML/*.lua` / `Localization.lua`（CASC 內，locale-tagged） | ❌ |
| 雕紋描述 | `GlyphProperties.db2` | ❌ |
| 物品名稱 / 敘述 | `ItemSparse.db2` —— **但 proxy 用 legacy query 覆蓋**（§3.6） | ✅ **例外** |

### 4.2 hotfix 機制在這條路上確實會動（已驗證）

`SMSG_AVAILABLE_HOTFIXES` → client 回 `CMSG_HOTFIX_REQUEST` → proxy 回 `SMSG_HOTFIX_CONNECT`／`SMSG_DB_REPLY`。這條路在 `wotlk.md` 的矩陣裡「Hotfix data」是三個後端全 ✅。

HermesProxy 的 `CSV/Hotfix/` 目前有 **29 個檔**（`gh api` 實測，非 README 說的 18）。**檔名尾碼是 expansion version**（`GameData.cs`：`Path.Combine("CSV", "Hotfix", $"SpellName{ModernVersion.ExpansionVersion}.csv")`；1 = Vanilla、2 = TBC、3 = WotLK）：

| 尾碼 3（3.4.3 會載入） | 尾碼 1 / 2（3.4.3 **不載入**） |
|---|---|
| `AreaTrigger3`, `BattlePetSpecies3`, `GlyphProperties3`, `Heirloom3`, `ItemEffect3`, `Mount3`, `SpellVisualMissile3`, `SpellXSpellVisual3`, `Toy3` | `SpellName1`, `Spell1`, `SkillLine1`, `ItemSparse1`, `ItemDisplayInfo1`, `SpellEffect1` … |

loader 對缺檔的註解已經回答了「為什麼 3.4.3 沒有 `SpellName3.csv`」：

> "Not shipped for this expansion: **the client's own DB2 already carries these rows verbatim**, so there is nothing to override."

**但 loader 本身是版本無關的** —— 它只是讀 `SpellName{N}.csv`，格式 `SpellId,Name`（`SpellName1.csv` 的實際 header），然後：

```csharp
record.TableHash = DB2Hash.SpellName;
record.RecordId = id;
record.Status = HotfixStatus.Valid;
record.HotfixContent.WriteCString(name);
```

`Spell{N}.csv` 的 loader 更關鍵，它寫三個字串：`NameSubtext`、`Description`、`AuraDescription` —— **就是法術 tooltip 的全文**。

### 4.3 那大規模 hotfix 漢化到底可不可行？誠實評估

**有利的三項（全部已驗證）：**
1. **資料存在**：§1.2 已證明 `3.4.3.54261` 的 zhTW `SpellName`（49,357 列）與 `Spell`（53,071 列）可從 wago.tools 匯出，欄位就叫 `Name_lang`。
2. **loader 存在且格式相符**：只要放一個 `SpellName3.csv`（`SpellId,Name`）進 `CSV/Hotfix/`，`LoadSpellNameHotfixes()` 就會載入 —— **不需要改程式**。`Spell3.csv` 同理。
3. **機制在這個 client 上已驗證可用**（`wotlk.md` 的 Hotfix data ✅）。

**不利的兩項（同樣已驗證，而且很重）：**

1. **`TableFilter` 目前把 3.4.3 鎖死在一張表。** `HermesProxy/World/Server/WorldSocket.cs:1302-1307`：

   ```csharp
   if (ModernVersion.Build == ClientVersionBuild.V3_4_3_54261)
   {
       hotfixes.TableFilter = new HashSet<DB2Hash>
       {
           DB2Hash.AreaTrigger,
       };
   }
   ```

   → 要讓 `SpellName` / `Spell` 被廣播，**必須改這段**（加兩個 enum 值）。這是原始碼修改，不是丟檔案。

2. **維護者自己記錄過封包大小會炸。** `HotfixPackets.cs:77-81` 的註解：

   > "Shipping the full ~600k Item/Spell index produces a ~5 MB packet the client never even logs ('ClientAvailableHotfixes' line missing), **suggesting a parse-abort**."

   `WorldSocket.cs:1294-1301` 補了另一半：曾經廣播 `ChrCustomizationChoice`(1064) + `ChrCustomizationOption`(190) 共 1,254 筆，事後驗證與 client DB2 **逐位元相同**，於是移除。

   → 49,357 筆 `SpellName` + 53,071 筆 `Spell` 是 **10 萬筆等級**，離那個 ~5 MB 的已知失敗點很近。**會不會踩到同一個 parse-abort，未驗證。**

**裁決：**

> **（2026-09-03 更新：本節的裁決已由 [hotfix DB2 中文化深度評估](./hotfix-db2-localization.md) 取代，該篇追出 `TableFilter` 與封包大小兩項阻礙都不成立，並給出分階段實驗計畫。以下保留原文。）**
>
> **法術名稱的 hotfix 漢化是「有根據的推測」，不是「已知可行」。** 三項前提（資料、loader、機制）都已驗證存在；兩項阻礙（`TableFilter` 要改、封包大小可能致命）也都已驗證存在。這是一個**值得做的實驗**，不是一條可以照著走的路。
>
> **務實的做法是分批**：先只放 `SpellName3.csv` 且**只放玩家真正會看到的子集**（例如自己職業的技能 + 常見消耗品法術，數百到數千筆），驗證 client 有沒有吃下去、`Hotfix.log` 怎麼寫，再決定要不要往上加。**全表一次上是最不可能成功的做法。**
>
> **UI 框架字串（`GlobalStrings`）完全不在 hotfix 的射程內** —— 那是 Lua，不是 DB2。唯一的理論路徑是寫一個 addon 在 runtime 覆寫 `_G` 裡的 `GlobalStrings`（`AGILITY = "敏捷"` 之類）。這是行之有年的 addon 技巧，但**本文未驗證它在 3.4.3 上的行為，也沒找到現成的 zhTW 專案（§5）**。

### 4.4 ★ 字型：本機實測，已經在裡面了

這是本篇第二個好運氣。原本預期的最大阻礙是「enUS client 沒有 CJK 字型，中文會顯示成方塊」。實測 `~/World of Warcraft 3.4.3.54261/_classic_/Fonts/`：

| 檔名 | 大小 (bytes) | FileDataID 對應（wowdev 社群 listfile 查得） |
|---|---|---|
| `615960.slug` / `.slugo` | 123,072 / 311,684 | `fonts/frizqt__.ttf` |
| `615968.slug` | 5,932,496 | `fonts/2002b.ttf`（韓文） |
| `615971.slug` | 163,252 | `fonts/frizqt___cyr.ttf`（西里爾，來自 ruRU） |
| **`615974.slug`** | **33,328,656** | **`fonts/arkai_t.ttf`** |

`xxd` 顯示五個檔的 magic 都是 `guls`（"slug" 反序）—— Slug 字型渲染格式。

**`ARKai_T` 正是 zhTW WoW client 用的繁體中文字型，而它已經安裝在這份 enUS + ruRU 的 client 上。** 韓文的 `2002b` 也在。這兩個檔顯然**不帶 locale tag**，屬於全域安裝的一部分。

**推論（未驗證，但證據很強）：** 一個 enUS 安裝不會無緣無故裝 33 MB 的繁中字型和 5.9 MB 的韓文字型；最合理的解釋是 client 把它們當作 **CJK 字符的 fallback 字型**（跨區角色名、聊天訊息都需要）。

**使用者可以在 30 秒內自己驗證：進遊戲，在聊天輸入框打幾個中文字，看是顯示中文還是方塊。** 這一項一旦確認，§3 的整條路就沒有顯示層的疑慮了。

---

## 5. 社群既有成果（全部 `gh api` 實測）

### 5.1 上游本身沒有中文資料（已驗證）

TrinityCore 與 `azerothcore-wotlk` 兩個 repo 內都**沒有**任何 zhTW / zhCN 的 locale SQL。AzerothCore 的模組生態也沒有中文化模組。**所有中文資料都是第三方的。**

### 5.2 找到的 repo

| Repo | 目標 | 語系 | License | ★ | 建立 | 最後 push | 涵蓋 |
|---|---|---|---|---|---|---|---|
| **`yefq/wowdb-zh`** | TrinityCore 3.3.5 | **zhTW + zhCN（分資料夾）** | **無** | 94 | 2018-06-10 | 2021-06-20 | zhTW 10 張表：`creature_template`, `creature_text`, `gameobject_template`, `gossip_menu_option`, `item_set_names`, `item_template`, `npc_text`, `page_text`, `points_of_interest`, `quest_template`。zhCN 另多 `achievement_reward`, `broadcast_text`, `quest_offer_reward`, `quest_request_items`（共 13） |
| `gswxy/AC_db_chinese` | AzerothCore（`acore_world`） | zhCN | 無 | 44 | 2021-09-08 | 2021-09-08 | 任務／物品／生物／對話，資料夾以中文命名，另附 `.xlsx` |
| `amydomi/TrinityCore_Chinese_Locale` | TrinityCore 3.3.5 | zhCN | 無 | 13 | 2019-07-05 | 2019-07-05 | 20 個檔，另含 `trinity_string`、`game_tele` |
| `whosa/cndb` | TrinityCore 3.3.5 | zhCN | **GPL-2.0** | 8 | 2015-08-12 | 2020-04-21 | 12 張表 + `trinity_string` |

`yefq/wowdb-zh` 的 zhTW 樣本（實際抓取 raw 內容）：

```sql
replace into quest_template_locale set id=1,locale='zhTW',title='坎瑞薩德的任務',details='歡迎你從死亡的世界歸來...
```

**格式與 `origin/3.3.5` 的 `quest_template_locale` schema 完全相符**（`ID`, `locale`, `Title`, `Details`, …），可直接匯入。

### 5.3 必須講清楚的四個但書

1. **同源。** `amydomi`、`whosa/cndb`、`yefq/wowdb-zh` 的 zhCN 文字幾乎逐字相同（同一個 quest id 1 的措辭一致）。`amydomi` 的檔頭自己標了來源 `https://git.oschina.net/686500/Wow-ChineseDB`。**這不是三份獨立翻譯，是同一份社群翻譯的三個衍生。** 原始作者與品質無法追溯。
2. **zhTW 極少。** 四個 repo 裡**只有 `yefq/wowdb-zh` 有真正的 zhTW 資料夾**。沒有任何專做 zhTW 的獨立專案。
3. **授權。** 只有 `whosa/cndb` 有明示 License（GPL-2.0）。其餘三個**沒有 LICENSE 檔 = 預設保留所有權利**，公開可見不等於可自由再散布。個人本機使用與公開再發布是兩回事。
4. **陳舊。** 最新的一筆 push 是 2021-09。schema 可能與現在的 TDB 有落差（`quest_template_locale` 在 TC 歷史上做過欄位重整），匯入前要對過欄位。
5. **完整度未驗證。** 沒有比對過 row count 對整份 world DB 的覆蓋比例。**很可能只是子集。**

### 5.4 client 端漢化：沒找到

- 針對 3.3.5a 私服的 zhTW client 端翻譯 addon：**GitHub 上搜不到任何 repo**（多組關鍵字變體均為零結果）。
- 現代 Classic client 的社群漢化：**沒找到任何一例**，這與 §2.5 的機制結論一致。

> 這是「未找到」，不是「已證明不存在」。

---

## 6. 排序結論：實際能拿到多少中文，代價多少

### 排序（依「中文覆蓋 ÷ 代價」）

#### 第 1 名：改 HermesProxy 一行 + 匯入 zhTW `*_locale` SQL

- **做什麼**：(a) 把 `AuthClient.ConnectToAuthServer` 的 locale 硬寫成 `"zhTW"`，`dotnet publish` 重建（macOS universal binary，GPL-3.0，成本低）；(b) 把 `yefq/wowdb-zh/zhTW/` 的 10 個 `.sql` 匯進 3.3.5a world DB。
- **拿到什麼**：任務全文、NPC 名字與頭銜、物品名稱與敘述、對話選項、NPC 對話、書頁、指路標記 —— **玩家閱讀時間的絕大多數**。
- **代價**：一行程式碼 + 一次 `dotnet publish` + 幾個 `mysql <` 指令。**client 完全不動。**
- **風險**：低。沒翻到的列逐列 fallback 回英文，不會壞。授權是唯一要自己衡量的（§5.3.3）。
- **已知缺口**：`yefq` 的 zhTW 沒有 `quest_offer_reward` / `quest_request_items` / `broadcast_text` / `achievement_reward`（zhCN 有，zhTW 沒有）；完整度未驗證。

#### 第 2 名：先驗證字型（30 秒，應該最先做）

進遊戲在聊天框打中文。若顯示正常 → 第 1 名無顯示層疑慮。若顯示方塊 → 第 1 名的價值歸零，必須先解字型（唯一的理論路徑是 addon 用 `SetFont` 指向 `Fonts\ARKai_T.ttf`，**未驗證**）。
**這一步應該排在第 1 名之前執行，只是它不「產出」中文，所以列在第 2。**

#### 第 3 名：小批量 hotfix 實驗（法術名稱）

從 wago.tools 取 `SpellName?build=3.4.3.54261&locale=zhTW`，**只挑數百到數千筆**（自己職業的技能 + 常用消耗品），存成 `CSV/Hotfix/SpellName3.csv`（header 改成 `SpellId,Name`），並把 `DB2Hash.SpellName` 加進 `WorldSocket.cs:1304` 的 `TableFilter`。看 client 的 `Hotfix.log`。
- **成功機率未知**，但代價只有一個下午，而且失敗是可逆的（刪檔即可）。
- 成功後才考慮 `Spell3.csv`（tooltip 全文），以及要不要往上加量。

#### 第 4 名（不建議）：直接改基礎表的英文欄位

零程式碼修改，但**破壞英文原文且不可逆**，且社群的 `locale='zhTW'` SQL 全部要重寫。只有在完全拒絕碰 proxy 原始碼時才成立。

### 明確不可行

- **取得完整 zhTW client** —— zhTW 是同一個 build 的 install tag，補裝要回 CDN，而該 build config 實測 404（§1.3）。**這與取得 client 本身是同一道牆。**
- **MPQ 式漢化補丁** —— CASC 沒有等價機制，CascLib 唯讀（§2.5）。
- **`UPDATE account SET locale = 5`** —— 每次登入被 `LOGIN_UPD_LOGONPROOF` 覆寫（§3.3）。
- **把中文寫進 `locale='enUS'` 的列** —— 伺服器直接 `continue` 跳過（§3.5）。
- **`DBC.Locale = 5`** —— 需要 zhTW 的 3.3.5a DBC，使用者沒有，且與 `*_locale` 無關。

### 天花板，講白

> **能中文化的是「伺服器說的話」；不能中文化的是「client 自己知道的字」。**
>
> 走完第 1 名，你會得到一個**任務、NPC、物品、對話全繁中，但法術、天賦、成就、地圖名、所有 UI 按鈕仍是英文**的遊戲。以 WotLK 的實際遊玩體驗來說，這大約是「劇情與世界完全看得懂、系統介面仍是英文」的狀態 —— 對多數人而言是可玩的，甚至是不少人在原生 client 上會刻意選的組合。
>
> 第 3 名若成功，能把「法術名稱」也拉進來，那是 UI 這一半裡最有感的一塊。但那條路目前是**推測**，不是路線。
>
> **UI 框架字串（按鈕、面板、錯誤訊息）在這條 stack 上沒有任何已驗證的中文化路徑。** 這就是天花板。

---

## 7. 驗證方式

本機 client（唯讀）：

```
cat  ~/'World of Warcraft 3.4.3.54261/.build.info'                      # Tags 欄只有 enUS / ruRU
ls -la ~/'World of Warcraft 3.4.3.54261/_classic_/Fonts'                # 615974.slug = arkai_t，33 MB
xxd -l 16 ~/'World of Warcraft 3.4.3.54261/_classic_/Fonts/615974.slug' # magic "guls"
grep -E 'textLocale|audioLocale|portal' ~/'World of Warcraft 3.4.3.54261/_classic_/WTF/Config.wtf'
```

本 repo（唯讀，不切換分支）：

```
sed -n '49,90p' src/common/Common.h                                     # LocaleConstant + CascLocaleBit
sed -n '20,60p' src/common/Common.cpp                                   # localeNames[] / WowLocaleToCascLocaleBit
sed -n '100,119p' dep/CascLib/src/CascLib.h                             # CASC_LOCALE_* 位元值
sed -n '445,451p' dep/CascLib/src/CascRootFile_WoW.cpp                  # locale mask 比對
sed -n '587,605p' dep/CascLib/src/CascFiles.cpp                         # GetDefaultLocaleMask

git show origin/3.3.5:src/common/Common.h | sed -n '47,64p'             # 3.3.5 的 TOTAL_LOCALES = 9
git show origin/3.3.5:sql/base/dev/world_database.sql \
  | grep -o 'CREATE TABLE `[a-z_]*locale[a-z_]*`' | sort               # 16 張 *_locale 表
git show origin/3.3.5:src/server/authserver/Server/AuthSession.cpp | sed -n '305,310p;518,526p'
git show origin/3.3.5:src/server/game/Server/WorldSocket.cpp | sed -n '263,295p'
git show origin/3.3.5:src/server/game/Globals/ObjectMgr.cpp | sed -n '5405,5415p'   # enUS 被 continue
git show origin/3.3.5:src/server/worldserver/worldserver.conf.dist | sed -n '637,652p'  # DBC.Locale
```

HermesProxy（`gh api`，唯讀）：

```
gh api "repos/Xian55/HermesProxy/contents/HermesProxy/CSV/Hotfix?ref=feature/wotlk-classic-v3.4.3" \
  --jq '.[] | "\(.name)\t\(.size)"'
# 原始碼：HermesProxy/Auth/AuthClient.cs:71,292
#         HermesProxy/BnetServer/Networking/BnetRestApiSession.cs:102,121
#         HermesProxy/BnetServer/Services/Services/Authentication.cs:39
#         Framework/Constants/Locale.cs
#         HermesProxy/World/GameData.cs:2134-2170（LoadHotfixes）、2416-2482（Spell / SpellName loader）
#         HermesProxy/World/Server/WorldSocket.cs:1290-1310（TableFilter）
#         HermesProxy/World/Server/Packets/HotfixPackets.cs:69-96（~5 MB parse-abort 註解）
#         HermesProxy/World/Client/PacketHandlers/QueryHandler.cs（六個 query handler）
```

外部（實際抓取）：

```
curl "https://wago.tools/db2/SpellName/csv?build=3.4.3.54261&locale=zhTW" | head
curl "https://wago.tools/db2/Spell/csv?build=3.4.3.54261&locale=zhTW" | wc -l
curl "https://us.version.battle.net/v2/products/wow_classic/cdns"        # us / eu / cn / kr / tw
```

FileDataID → 檔名對照：`https://github.com/wowdev/wow-listfile` 的 `community-listfile.csv`（**社群維護**）。

---

## 8. 實際取用過的來源

**本機（第一手實測）**
- `~/World of Warcraft 3.4.3.54261/.build.info`、`_classic_/Fonts/*`、`_classic_/WTF/Config.wtf`

**本 repo（第一手）**
- `src/common/Common.h` / `Common.cpp`
- `dep/CascLib/src/CascLib.h`、`CascRootFile_WoW.cpp`、`CascFiles.cpp`、`CascOpenStorage.cpp`、`CascRootFile_Install.cpp`、`dep/CascLib/README.md`
- `origin/3.3.5`：`src/common/Common.h`、`sql/base/dev/world_database.sql`、`src/server/authserver/Server/AuthSession.cpp`、`src/server/database/Database/Implementation/LoginDatabase.cpp`、`src/server/game/Server/WorldSocket.cpp`、`src/server/game/Server/WorldSession.cpp/.h`、`src/server/game/Globals/ObjectMgr.cpp`、`src/server/worldserver/worldserver.conf.dist`
- master：`sql/base/dev/hotfixes_database.sql`（99 張 DB2 `*_locale` 表，作為「現代 hotfix 也有 locale 維度」的對照）

**HermesProxy（`gh api` / 分支 tarball）**
- `Xian55/HermesProxy@feature/wotlk-classic-v3.4.3`：`Framework/Constants/Locale.cs`、`HermesProxy/Auth/AuthClient.cs`、`HermesProxy/BnetServer/Networking/BnetRestApiSession.cs`、`HermesProxy/BnetServer/Services/Services/Authentication.cs`、`HermesProxy/World/GameData.cs`、`HermesProxy/World/Server/WorldSocket.cs`、`HermesProxy/World/Server/Packets/HotfixPackets.cs`、`HermesProxy/World/Server/PacketHandlers/HotfixHandler.cs`、`HermesProxy/World/Client/PacketHandlers/QueryHandler.cs`、`CSV/Hotfix/*`

**Blizzard**
- `https://news.blizzard.com/zh-tw/world-of-warcraft/23833251/`、`.../23847495/`、`.../23850854/`
- `https://wow.blizzard.cn/news/23850855/` — 2024-07-11 巫妖王之怒經典版在中國回歸
- `https://us.support.blizzard.com/en/article/11417` — Changing Your Text Language
- `https://us.version.battle.net/v2/products/wow_classic/versions`、`.../cdns`

**社群（明確標示非官方）**
- `https://wowdev.wiki/TACT`、`https://wowdev.wiki/CASC`、`https://wowdev.wiki/MPQ`
- `https://wago.tools/db2/<Table>/csv?build=3.4.3.54261&locale=zhTW`
- `https://github.com/wowdev/wow-listfile`
- `https://github.com/yefq/wowdb-zh`、`gswxy/AC_db_chinese`、`amydomi/TrinityCore_Chinese_Locale`、`whosa/cndb`

**取用失敗**
- `news.blizzardgames.cn`（DNS 無法解析）→ zhCN 停服公告無法第一手驗證
- `wowdev.wiki` 對 WebFetch 回 403（Cloudflare），改以 `curl` 取得（200）
