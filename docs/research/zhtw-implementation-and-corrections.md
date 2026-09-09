# zhTW 中文化：實作記錄與既有筆記更正

> 本篇是 2026-09-04 實作階段的總結。它有兩個用途：
> 一是記錄**實際做出來並經遊戲內驗證**的做法；
> 二是**更正本目錄其他筆記中已被實測推翻的結論**——那些結論當時有其推理依據，但事後證明是錯的，若不標註會誤導後續工作。
>
> 相關筆記：[zhTW 中文化能做到哪裡](./zhtw-localization.md)、[hotfix DB2 中文化深度評估](./hotfix-db2-localization.md)、[UI 框架字串 addon](./ui-localization-addon.md)、[世界地圖標籤](./worldmap-label-localization.md)、[zhTW 做成真正語系](./zhtw-as-real-locale.md)、[hotfix 啟動時套用](./hotfix-startup-application.md)

---

## 0. 一句話結論

在 **3.4.3.54261 客戶端 → HermesProxy → TrinityCore 3.3.5** 這套架構上，
中文化實際達成的涵蓋率約九成，靠的是**三條互補的通道**，
而不是任何單一機制。

---

## 1. 實際運作的架構

```
客戶端 WowClassicFull.exe (3.4.3.54261, Ed25519+RSA patched)
  ├── 鬆散檔案      Fonts/*.ttf, Interface/WorldMap/**    ← 磁碟直接覆蓋
  ├── hotfix DB2    31 張表，由 HermesProxy 合成推送       ← 連線後套用
  └── 伺服器字串    12 張 *_locale 表                      ← TrinityCore 3.3.5
```

三條通道的分工與限制各不相同，**這是理解整件事的關鍵**：

| 通道 | 承載內容 | 何時生效 | 能否覆蓋 glue 畫面 |
|---|---|---|---|
| 鬆散檔案 | 字型、地圖美術 | **客戶端啟動即生效** | ✅ 可以 |
| hotfix DB2 | 幾乎所有字串資料 | 連線後（部分需 `/reload`） | ⚠️ 僅 `Flags=3`，`Flags=2` 不行 |
| 伺服器 `*_locale` | 任務、NPC、對話、書頁 | 進入世界後即時 | ❌ 不適用 |

---

## 2. 通道一：鬆散檔案覆蓋（本階段最大發現）

**客戶端在讀 CASC 之前會先找磁碟上的檔案。** 兩處實測確認：

- `_classic_/Fonts/FRIZQT__.TTF` 等四個檔 → UI 字型全面更換，**連登入畫面都生效**
- `_classic_/Interface/WorldMap/<區域>/*.blp` → 87 個區域、2,699 個貼圖全部生效

素材來自使用者自有的繁中 3.3.5a 客戶端，用 `mpyq` 從 `locale-zhTW.MPQ` 解出（2,708 個檔案、零失敗）。

### 字型的角色對應

繁中客戶端不是把 `FRIZQT__.TTF` 換成中文字型（它本身只有 61K，仍是拉丁字型），
而是另外帶四支中文字面，由客戶端按用途挑選：

| 放置檔名 | 實際字面 | 用途 |
|---|---|---|
| `FRIZQT__.TTF` | `bHEI00M` 黑體 | 一般 UI |
| `ARIALN.TTF` | `bHEI00M` 黑體 | 數字、聊天 |
| `MORPHEUS.TTF` | `bKAI00M` 楷體 | 任務、信件 |
| `SKURRI.TTF` | `bLEI00D` 隸書 | 地名、標題 |

### 地圖美術的一個必要例外

大陸層級地圖（`Azeroth`＝東部王國、`Kalimdor`、`Northrend`、`Expansion01`、`Cosmic`）的
**`*Highlight.blp` 必須保留原生**，否則在「艾澤拉斯」層 hover 子地圖時邊框錯位——
高亮座標由 DB2 提供且校準在原生美術上。底圖可以換成中文，只有 highlight 不行。

美術規格本身沒有落差：查 `UiMapArtStyleLayer`，此 build 全部 178 筆地圖美術都用
`style 1`（1002×668 / 12 張 256×256 圖磚），與 3.3.5a 完全相同；
定義中雖有高解析度的 `style 5`（3840×2560 / 150 張），但**沒有任何地圖引用它**。

---

## 3. 通道二：hotfix DB2

### 資料來源與產生方式

- 字串資料：`wago.tools` 的 **`3.4.3.54261` zhTW 匯出**
- 欄位定義：**`wowdev/WoWDBDefs`** 對應 build 的 layout 區塊
- loader：由 DBD 定義**程式產生** C#，內含 `assert 欄位數 == wago 欄位數` 的檢查，不符即中止

31 張表，較大者：`ItemSparse` 45,070 / `SpellName` 49,352 / `Spell` 33,179 /
`GlobalStrings` 18,205 / `AreaTable` 2,373 / `Achievement` 1,912 / `Talent` 892。

### 對 HermesProxy 的三處實質修改

1. **強制 zhTW**（`AuthClient.cs`）——在 LOGON_CHALLENGE 送 `zhTW`，
   後端據此使用 `*_locale`。客戶端只會回報 enUS/ruRU，但採用的是 proxy 送的值。
2. **`TableFilter` 擴充**（`WorldSocket.cs`）——原本只廣告 `AreaTrigger`。
   上游限制它的理由是效能修剪（那些表對 enUS 逐欄位相同），**不是相容性問題**。
3. **`CMSG_DB_QUERY_BULK` 查表回退**（`HotfixHandler.cs`）——
   原本對沒有專屬分支的表一律回 `Status=Invalid`；
   改為先查 `(TableHash, RecordId)` 索引，命中就回 `Valid` 並附內容。
   這是通用修正，不只惠及單一表。

### 時序（重要）

`hotfix-startup-application.md` 已證實：**無法在啟動時套用**。
客戶端的 `DBCache.bin` 每筆 entry 綁 `region`，而 region 來自 `SMSG_AVAILABLE_HOTFIXES`
——必須先連線。且 proxy 已送在最早的合法時點（glue 階段），與 TrinityCore 官方同位置。

實務影響：`GlobalStrings` 這類「載入時讀一次」的資料需要一次 `/reload`。
其餘（法術、物品、地名等每次顯示才查表的）**即時生效，無需 reload**。

---

## 4. 已確認的邊界（無法從我們這側解決）

| 項目 | 成因 | 證據 |
|---|---|---|
| glue 專用字串（`Flags=2`，1,248 筆） | 客戶端不從 hotfix 套用該類 | `CHAR_CUSTOMIZATION1-6_DESC` 已送達且 `VALID`，完整重開後創角畫面仍英文 |
| Classic 世代寵物模型 | 模型資產不在此安裝內 | 客戶端回報 `creatureDisplayID=115636`（與我們推送值一致），舊世代寵物模型正常、Classic 世代不正常 |
| 大陸地圖 Highlight | 刻意取捨 | 換成 3.3.5a 版會導致 hover 邊框錯位 |

**注意 `Flags` 的語義**（由資料反推，非官方文件）：
`1` = 遊戲內、`2` = glue 專用、`3` = 兩者共用。
`Flags=3` 的字串在 glue 畫面**有效**（登入畫面部分中文即為此），`Flags=2` 無效。

---

## 5. 更正：本目錄其他筆記中已被推翻的結論

### 5.1 「CASC 沒有鬆散檔案覆蓋機制」——**錯誤**

- **出現於**：`zhtw-localization.md`、`worldmap-label-localization.md`、`zhtw-as-real-locale.md`、`hotfix-db2-localization.md`
- **原推理**：CascLib 的公開 API 唯讀 → 推論客戶端不會讀磁碟檔案
- **錯在哪**：「不能改 CASC 容器」與「客戶端不會先看磁碟」是**兩件不同的事**，被混為一談
- **實測**：`Fonts/` 與 `Interface/WorldMap/` 皆生效
- **連帶更正**：`worldmap-label-localization.md` 對 WoWInterface「Atlas World Map WOTLK Classic」
  插件（宣稱安裝到 `_classic_/Interface/WorldMap`）的懷疑是**不成立的**，該插件的說法正確

### 5.2 「地形與文字是同一批像素，除非換底圖否則無解」——**結論成立但已被繞過**

- **出現於**：`worldmap-label-localization.md`
- 該敘述本身正確（底圖確實包含文字），但推出的「無解」不成立——**底圖可以換**

### 5.3 `ItemSparse` / `Faction` / `Map` 「欄位對不上」——**錯誤**

- **出現於**：`hotfix-db2-localization.md`、`wotlk-classic-port-roadmap.md` 的相關段落與當時的口頭判斷
- **兩個獨立原因**：
  1. 參考來源錯誤——使用 TrinityCore `wotlk_classic` 的 `DB2Metadata.h`，
     但該分支 target **3.4.4.61581**，與本 build 不同
  2. 解析器錯誤——以 `LAYOUT` 切分 DBD 區塊，未處理單一檔案含多份定義的情況
     （`Faction.dbd` 有三份，被接成 88 欄，實際 35 欄）
- **改用 WoWDBDefs 並以空行切分後**：三張表全部乾淨對齊，皆已實作並生效

### 5.4 「找不到 zhTW/zhCN UI 漢化插件」——**過早**

- **出現於**：`ui-localization-addon.md`
- 後續於 `worldmap-label-localization.md` 更正：確有兩個 zhCN 專案存在
- **但更重要的是**：該篇建議的 addon 覆寫 `_G` 路線**整條已被 hotfix 取代**，
  不需要 addon、沒有 taint 風險、也沒有載入順序問題

### 5.5 `zhtw-as-real-locale.md` 的推理缺一層

- 該篇逐層檢視 locale 的構成時**未納入鬆散檔案覆蓋**
- 「做成客戶端認可的語系選項」的結論仍然成立
  （遊戲內 `GetAvailableLocales()` 實測只回傳客戶端已註冊的三個語系）
- 但「實際效果」的天花板比該篇估計的高：美術與字型可由鬆散檔案達成

### 5.6 `wow-patcher-runtime-mode.md` 中已含的更正（此處僅標記，非新增）

- Arctium **不是閉源**：`arctium.io` 已導向 `burralis.io`，repo 為 `Burralis/Game-Launcher`，MIT
- Arctium **需要**可信 TLS 憑證（有 `SslStream` 預檢），HermesProxy README 的相反說法有誤

---

## 6. 實作上的教訓

### 6.1 HotfixId 號段碰撞

批次產生 loader 時以 `5_100_000 + i×100_000` 配號（排到 6,600,000），
之後手動新增表時又從 6,000,000 起算，**撞上三張已配號的表**。
由於 loader 以 `Parallel.Invoke` 平行執行，覆寫順序不確定，症狀極具誤導性：
某張表只到 15/41 筆、某張表全部 `INVALID`、寵物模型錯亂。

**教訓**：新增號段前先掃描既有常數。修正後最高號段為 7,600,000。

### 6.2 追查字串來源的正確順序

創角畫面的「Skin Color」追了三輪才找對，前兩次都是**從症狀推論來源**
（先猜 glue 時序、再猜 `ChrCustomizationOption`）。

**正確做法**：直接在該 build 的 enUS 匯出裡**搜尋那個英文字串**，
找出它屬於哪張表、哪個 tag。這一步十秒可得答案，
本例中答案是 `CHAR_CUSTOMIZATION1_DESC`（`Flags=2`），
既不是 `SKIN_COLOR`（`Flags=1`）也不是 `ChrCustomizationOption`。

### 6.3 歸因需要隔離變因

寵物模型錯亂一度被歸因於新加的 `Creature` 表而撤除該表，
但撤除後模型依舊錯誤，且 log 顯示相關 `INVALID` 紀錄**早於該表加入**。
當時號段碰撞的 bug 也同時存在，兩個變因未隔離。

---

## 7. 現況清單

**已中文化**：任務／NPC／對話／書頁、法術名稱與說明、物品、天賦、成就、陣營、
技能、貨幣、種族／職業、坐騎、寵物家族、區域與地圖名稱、地圖地標、讀取畫面提示、
UI 框架文字、地圖美術（87 區域）、字型（含登入畫面）

**仍為英文**：glue 專用字串（`Flags=2`）、Classic 世代寵物模型、大陸地圖 Highlight

**檔案位置**：
- proxy 與 CSV：`~/Works/side-project/wotlk-stack/`
- 客戶端鬆散檔案：`_classic_/Fonts/`、`_classic_/Interface/WorldMap/`
- 中文版大陸地圖（未使用）：`Interface/WorldMap/<區域>` 內已移除 highlight

---

## 8. 四層快取：改資料後的正確順序

一次「物品名稱仍是簡體」的追查暴露了整條鏈上**四個各自獨立的快取**。
只清其中一層會看到舊值，而症狀會誤導成「資料沒改對」。

| 層級 | 何時失效 |
|---|---|
| 資料庫 | 立即 |
| worldserver 記憶體 | **重啟才重載**（`*_locale` 在啟動時載入） |
| proxy 記憶體 | **重啟才清空**（`GameData.GetItemTemplate` 快取） |
| 客戶端 `Cache/` | 刪除目錄或重新索取 |

**正確順序**：改 DB → 重啟 worldserver → 重啟 proxy → 清客戶端快取。

特別注意：`HotfixHandler` 處理 `ItemSparse` 查詢時**先查 proxy 記憶體，不走 CSV**，
所以只改 `bin/CSV/Hotfix/*.csv` 對已被快取的物品完全無效。

### 追查字串來源的教訓（補充 §6.2）

從中文名反推英文物品名**不可靠**——zhCN 與 zhTW 的譯名可能完全不同
（例：item 4865 `Ruined Pelt`，zhCN「破烂的皮毛」vs zhTW「破爛的毛皮」，連詞序都不同），
所以用中文去 LIKE 查詢會查不到。**應該直接在遊戲內取得 itemID**：

```
/run local C=C_Container local g=C and C.GetContainerItemID or GetContainerItemID local ns=C and C.GetContainerNumSlots or GetContainerNumSlots for b=0,4 do for s=1,(ns(b) or 0) do local id=g(b,s) if id then print(b,s,id,(GetItemInfo(id))) end end end
```

## 9. 社群翻譯資料的品質問題

伺服器端 `*_locale` 來自 `yefq/wowdb-zh` 的 `zhTW` 目錄，**該目錄混入大量 zhCN 資料**。
以字元級判定（僅簡體專屬字形才計入，避免異體字誤判）實測：

| 表 | 含簡體 / 總數 | 比例 |
|---|---|---|
| `gameobject_template_locale` | 11,055 / 20,879 | 52.9% |
| `creature_template_locale` | 4,399 / 29,923 | 14.7% |
| `item_template_locale` | 1,829 / 45,109 | 4.1% |
| `gossip_menu_option_locale` | 1,015 / 3,486 | 29.1% |
| 其餘四張 | 2,031 | — |
| **合計** | **20,329 / 123,577** | **16.5%** |

**物品已修復**：改用 wago.tools 的 `3.4.3.54261` zhTW `ItemSparse` 匯出重建
（45,069 筆官方繁中）。剩下的 1,829 筆是資料庫有、wago 匯出沒有的舊物品。

**其餘七張表無權威來源**——生物名、任務文字、遊戲物件、對話都是伺服器端概念，
不存在於客戶端 DB2，wago 沒有對應資料。只能用 `opencc s2twp` 做字形轉換，
**能修字形，修不了譯名差異**。
