# hotfix 能不能在 client 啟動時就套用？—— 用 client 自己的 log 結案

> 撰寫日期：2026-09-04
> 相關筆記：[hotfix DB2 中文化深度評估](./hotfix-db2-localization.md)（本篇補完該篇 §5.2 的時序，並回答該篇 §9 的「暖快取／時序」未驗證項）、[用 addon 中文化 UI 框架字串](./ui-localization-addon.md)（本篇**證實**該篇 §5.3 的三個疑問中最關鍵的一個：client 何時把 `GlobalStrings` 攤成 Lua 全域）
> 前提（已由使用者實機驗證，視為事實，不再論證）：`3.4.3.54261` client → `Xian55/HermesProxy` → TrinityCore `3.3.5`；約 28 張 DB2 以 hotfix 推送；**法術名／法術描述／物品名／區域名進遊戲即為繁中，不需要 reload**；**只有 `GlobalStrings` 需要 `/reload`**；`/run print(SPELLBOOK_BUTTON)` 在 reload 前就已經印出中文，但畫面上的框架仍是英文。
> 來源限定 primary sources：**本機 client 自己的 `Logs/Hotfix.log` 與 `Logs/Hotfix.log.old`（第一手、有毫秒時戳）**、本機 `Cache/ADB/enUS/DBCache.bin*.tmp` 的**實際位元組**、`WowClassic.exe` 的 `strings` 輸出（RTTI 與 log 樣板）、Blizzard 自家的 `Gethe/wow-ui-source` **tag `3.4.3`** 全文、本 repo 的 TrinityCore master 原始碼、`~/Works/side-project/wotlk-stack/hermesproxy` 的 HermesProxy 原始碼。
> **wowdev.wiki 與 wago.tools 為社群維護的資源，非 Blizzard 官方**，凡引用皆已標明。
> 未使用瀏覽器自動化。未編譯、未修改任何檔案。凡未實測者一律標示「**未驗證**」。

---

## 0. TL;DR

1. **裁決：不行。透過 hotfix 通道讓資料在「client 啟動、UI 建立之前」套用，是做不到的 —— 而且這不是我們這套 stack 的缺陷，是協定與 client 實作的結構性事實。**
2. **★ 決定性證據是 client 自己寫的 log**（`_classic_/Logs/Hotfix.log`，第一手）：

   ```
   9/4 16:30:23.938  ---- Startup ----
   9/4 16:30:35.368  ---- ClientAvailableHotfixes: region 16842753 ----
   9/4 16:30:35.415  ---- UserClientHotfixRequest ----
   9/4 16:30:35.896  ---- ApplyingHotfixes from Cache ----
   9/4 16:30:35.898  ---- ApplyingHotfixes from Server ----
   ```

   **`ApplyingHotfixes from Cache` 出現在 `Startup` 之後 11.96 秒，而且排在 `ClientAvailableHotfixes` 之後。** → **磁碟上的 `DBCache.bin` 不是啟動時讀的**，它和 server 送來的 hotfix 在同一個時點、同一條路徑套用。「先把快取灌好，下次啟動就直接是中文」這條路**在 client 裡不存在**。
3. **★ 為什麼快取不可能更早：cache 的每一筆條目都綁 region。** 本機 `DBCache.bin708.tmp` 的實際位元組：header `XFTH` / version **9** / build **54261** / 32 bytes verification hash；第一筆 entry 的欄位是 `XFTH, 16842753, 3900001, 3900001, <ItemSet table hash>, 1, 94, status=1`。**`16842753` 正是 log 裡 `ClientAvailableHotfixes: region 16842753` 的那個數字**（= `SMSG_AVAILABLE_HOTFIXES` 的 `VirtualRealmAddress`）。client 必須先從 server 收到 region 與 push id 清單，才能判斷快取裡哪些列還算數 —— **所以它「只能」在登入之後才套用快取**。
4. **★ proxy 已經在最早的合法時點送了。** TrinityCore master 的 `SendAvailableHotfixes()` 是在 `WorldSession::InitializeSessionCallback`（`WorldSession.cpp:1456`）裡呼叫的，緊接在 `SendFeatureSystemStatusGlueScreen()` 之後 —— **glue（選角）階段，還沒進世界**。HermesProxy 一模一樣：`WorldSocket.cs:972`，在 Realm 連線的 `HandleEnterEncryptedModeAck()` 裡，同樣緊接 `SendFeatureSystemStatusGlueScreen()`。**兩邊都已經是「握手一完成就送」，沒有更早的位置可以搬。**
5. **★ Blizzard 自己知道這件事，而且在 client 的 Lua 裡留了兩處痕跡。** `Gethe/wow-ui-source` tag `3.4.3`：
   - `Interface/GlueXML/CharacterSelect.lua:181` 註冊了事件 **`INITIAL_HOTFIXES_APPLIED`**（Blizzard 自家產生的 API 文件 `Blizzard_APIDocumentationGenerated/SystemDocumentation.lua:75-78` 有這個事件的定義），並在 `:355` 收到時重刷面板 —— **官方 UI 自己就假設「hotfix 會在 UI 建好之後才到，所以要重刷」**。
   - `Interface/GlueXML/CharacterSelect.lua:3554` 有一行 Blizzard 自己的註解：**`-- HACK, avoid global string hotfix:`** —— 官方程式碼裡明文出現「global string hotfix」這個東西。
6. **★ 前提檢驗：Blizzard 確實把 `GlobalStrings` 當 hotfix 出貨。** wago.tools 的 hotfix 存檔（社群）搜 `globalstrings` 回 **15,654 列**，最近兩批是 2026-08-29 與 2026-09-02（`zhCN` build 69497、`esES` build 49474）。**所以「Blizzard 的 hotfix 不需要 reload」這個前提，對 `GlobalStrings` 而言是不成立的** —— 他們也一樣受同一條載入順序約束，只是他們一次只改幾十列、而且玩家的 client 本來就是母語，看不出來。
7. **真正的機制不是「hotfix 沒生效」，而是「生效得太晚」。** 使用者實測 `print(SPELLBOOK_BUTTON)` 已是中文 → **client 在套用 hotfix 時確實有把 `GlobalStrings` 重新寫回 Lua 全域**（`WowClassic.exe` 的 RTTI 有 `DynamicLifeTimeDB<GlobalStringsRec_C>` 與 `function<void(int, GlobalStringsRec_C const*, DB2CallbackEvent)>`，即這張表有 DB2 變更回呼）。**但已經建好的 FontString 不會回頭重讀全域。**
8. **代價可以精確算出來：需要補救的只有「載入時就固化」的那一小撮。** `wow-ui-source@3.4.3` 裡 XML 直接寫死 `text="TAG"` 的地方共 **675 處**（`Interface/FrameXML` 391 + `Interface_Wrath/FrameXML` 284，另 `SharedXML` 81、`AddOns` 328+24），distinct tag **445 個**。**相對於我們推的 18,205 列 `GlobalStrings`，需要 hook 的不到 2.5%。**
9. **最佳近似（推薦）**：一個**不含任何字串資料**的小 addon —— hotfix 已經把 `_G` 換成中文了，addon 只要在 `PLAYER_LOGIN` 對那批固化的 FontString 做 `frame:SetText(_G[TAG])`。**成本是「列一張清單」，不是「翻譯」。** 次選是每次登入自動 `ReloadUI()`（可行但笨重，且每次登入多花數秒）。
10. **唯一真正的「啟動即中文」是讓資料在 client 自己的 DB2/CASC 裡** —— 也就是安裝 zhTW locale。本機 `.build.info` 只有 `enUS` + `ruRU`（[zhtw-localization.md](./zhtw-localization.md)），這條路不在射程內。

---

## 1. client 什麼時候消費 hotfix（含 `DBCache.bin`）—— 有 log 就不必猜

### 1.1 本次 session（`Logs/Hotfix.log`，12,395,782 bytes）

全檔只有 5 行不是逐列驗證結果：

```
9/4 16:30:23.938  ---- Startup ----
9/4 16:30:35.368  ---- ClientAvailableHotfixes: region 16842753 ----
9/4 16:30:35.415  ---- UserClientHotfixRequest ----
9/4 16:30:35.896  ---- ApplyingHotfixes from Cache ----
9/4 16:30:35.898  ---- ApplyingHotfixes from Server ----
```

之後是 **155,477 行 `VALIDATION_RESULT_VALID`，0 行 `VALIDATION_RESULT_INVALID`**。逐表統計（實測 `awk | sort | uniq -c`）：

| 表 | 列數 | 表 | 列數 |
|---|---|---|---|
| `SpellName` | 49,352 | `AreaTable` | 2,373 |
| `ItemSparse` | 45,070 | `Achievement` | 1,912 |
| `Spell` | 33,179 | `Talent` | 892 |
| **`GlobalStrings`** | **18,205** | `AreaPOI` | 818 |

（另有 `ItemSet` 509、`DungeonEncounter` 423、`TaxiNodes` 363、`Faction` 336、`UiMap` 261、`SkillLine` 152、`Map` 130、`ChrRaces` 21、`ChrClasses` 10、`AreaTrigger` 4 等共 35 張表。）

**三個直接讀出來的結論：**

1. **`ApplyingHotfixes from Cache` 在 `Startup` 之後 11.96 秒，而且在 `ClientAvailableHotfixes` 之後 0.53 秒。** → **快取不是開機時讀的。** 這一條就把「把 `DBCache.bin` 預先灌好、讓 client 啟動時直接吃」這個想法否掉了。
2. `UserClientHotfixRequest`（= `CMSG_HOTFIX_REQUEST`）發生在 advertise 之後 47 ms，套用又在 481 ms 之後 —— **advertise → request → connect → apply 是一次連續的、由 server 觸發的流程**，client 沒有任何「自己先套快取」的旁路。
3. **`GlobalStrings` 18,205 列全部 `VALIDATION_RESULT_VALID`** —— 佈局與 table hash 對 build 54261 是對的。這順帶結掉 [ui-localization-addon.md](./ui-localization-addon.md) §8 的兩個未驗證項（`DB2Hash.GlobalStrings = 0xBF0BC27A` 正確、hotfix 通道確實吃得下這張表）。

### 1.2 前一個 session（`Hotfix.log.old`，86,671,813 bytes）—— 更有資訊量

同一個 client process 裡有**三次**完整的 hotfix 流程：

```
15:06:08.489  ---- Startup ----
15:06:29.192  ---- ClientAvailableHotfixes: region 16842753 ----
15:06:29.336  ---- UserClientHotfixRequest ----
15:06:29.369  ---- ApplyingHotfixes from Cache ----      ← 152,308 行
15:06:29.782  ---- ApplyingHotfixes from Server ----     ←   2,512 行
15:06:29.794  ---- Done applying initial hotfixes ----
15:06:56.347  ---- ClientHotfixMessage ----              ← 進世界之後的單筆推送
15:10:30.312  ---- ClientAvailableHotfixes: region 16842753 ----   ← 第二次登入
15:15:27.672  ---- ClientAvailableHotfixes: region 16842753 ----   ← 第三次登入
```

**讀法：**

- **暖快取確實有用**：15:06 那一輪有 152,308 列來自 Cache、只有 2,512 列來自 Server。→ [hotfix-db2-localization.md](./hotfix-db2-localization.md) §9 的「暖快取在字串 hotfix 上是否正常」**已驗證：正常**。
- **但「有用」是省頻寬，不是提早。** 快取那 152,308 列同樣是在 `Startup` 之後 **20.9 秒**才套用的。
- **每次登入都重跑一次完整流程**（同一個 process 內三次），而且每次都有 `Done applying initial hotfixes`。
- `ClientHotfixMessage`（= `SMSG_HOTFIX_MESSAGE`）出現在 hotfix 套用之後約 **27 秒** —— 那是進入世界之後 proxy 推的 Item 系更新。**這個 27 秒的落差正是「hotfix 套用（glue）」與「進入世界」之間的距離。**

### 1.3 為什麼快取「不能」更早 —— 讀 `DBCache.bin` 的實際位元組

本機 `Cache/ADB/enUS/` 目前是 client 執行期的暫存檔（`DBCache.bin708.tmp`，26,506,936 bytes；`708` 是 process 相關的尾碼）。實際解出來的 header 與第一筆 entry：

```
header : magic='XFTH'  version=9  build=54261  verification_hash=f4bb6263f59a190f…（32 bytes）
entry#1: magic='XFTH'  region=16842753  push=3900001  unique=3900001
         table_hash=0x8E75…(ItemSet)  record_id=1  data_size=94  status=1(Valid)
```

對照 log 的第一列 `3900001 Table ItemSet RecID 1 VALIDATION_RESULT_VALID` —— 逐欄吻合。

> **（社群，非官方）** wowdev.wiki 的 `ADB`（`DBCache.bin` 重導向）頁記載 v7 起的 header 是 `magic / version / build_id / verification_hash[32]`，`RecordState { Valid=1 // overwrites source record }`。本機檔案是 **v9**，wiki 對 v8/v9 寫的是「Version bumped but no visible changes」，與實測相符。

**兩個綁定讓「離線預載」在結構上不可能：**

| 綁定 | 證據 | 後果 |
|---|---|---|
| **build** | header `build_id = 54261` | 換 build 快取即失效（這對我們無妨） |
| **region / virtual realm** | 每一筆 entry 都帶 `16842753`，與 `SMSG_AVAILABLE_HOTFIXES` 的 `VirtualRealmAddress` 同值 | **client 必須先知道自己連的是哪個 region 才能用快取** → 必須先登入 |
| **push id 清單** | `ClientAvailableHotfixes` 之後才 `ApplyingHotfixes from Cache` | 快取只是 server 那份清單的**本地副本**，沒有清單就不知道哪些還有效 |

**→ 對任務問題 1 的正面回答：`DBCache.bin` 不在 process 啟動時被讀取；它在登入握手收到 `SMSG_AVAILABLE_HOTFIXES` 之後才被套用。因此「快取為什麼救不了 `GlobalStrings`」不是快取被什麼 token 作廢，而是它從一開始就不在啟動路徑上。**

---

## 2. `GlobalStrings` 怎麼進 Lua、有沒有辦法不 reload 就重灌

### 2.1 client 端：這張表有 DB2 變更回呼（`WowClassic.exe` 的 RTTI）

```
.?AUCallbacks@?$DynamicLifeTimeDB@VGlobalStringsRec_C@@@@
.?AV?$function@$$A6AXHPEBVGlobalStringsRec_C@@W4DB2CallbackEvent@@@Z@blz@@
GetGlobalString
GlobalStrings
```

**`DynamicLifeTimeDB<GlobalStringsRec_C>` + `function<void(int, GlobalStringsRec_C const*, DB2CallbackEvent)>`** —— 這張表是「動態生命週期 DB」，且註冊了逐列的變更回呼。這與使用者的實測（reload 前 `print(SPELLBOOK_BUTTON)` 已是中文）互相印證：**client 在套用 hotfix 時會把新值寫回 Lua 全域。**

> 同一份 `strings` 輸出裡也有 client 的四個進度狀態字串：`Initial Hotfixes: Requested / Received / Fake Connect / Applied`，以及 `Cache\ADB`、`DBCache.bin`、`Logs/Hotfix.log`。**`GetGlobalString` 是 binary 裡的符號，不代表它是可呼叫的 Lua API** —— `wow-ui-source@3.4.3` 全文 `grep GetGlobalString` 是 **0 命中**，Blizzard 的 UI 從來沒用過它。

### 2.2 那為什麼畫面還是英文 —— 是「固化」，不是「沒生效」

`wow-ui-source@3.4.3` 裡 XML 直接把 tag 寫死在 `text=` 屬性上的地方：

| 目錄 | `text="TAG"` 出現次數 |
|---|---|
| `Interface/FrameXML` | 391 |
| `Interface_Wrath/FrameXML` | 284 |
| `Interface/SharedXML` | 81 |
| `Interface/AddOns`（Blizzard 自家） | 328 |
| `Interface_Wrath/AddOns` | 24 |
| **FrameXML 兩者合計的 distinct tag** | **445** |

例（`Interface_Wrath/FrameXML/CharacterFrame.xml`）：`text="CHARACTER"`、`text="PET"`、`text="REPUTATION"`、`text="SKILLS"`、`text="CURRENCY"`；`WatchFrame.xml` 的 `text="OBJECTIVES_TRACKER_LABEL"`。

**這些是在 XML 被解析、FontString 被建立的那一刻就把當時的 `_G[TAG]` 抄進去的。之後改全域不會回頭改它們** —— 與 [ui-localization-addon.md](./ui-localization-addon.md) §2(b-2) 描述的是同一件事，只是那邊的肇因是 addon 載入太晚，這邊的肇因是 hotfix 抵達太晚。**兩者的解法完全相同。**

另外還有 §2(b-1) 那一類：FrameXML 在載入時把值抄進 Lua 表（ClassicUA 逐字記錄過的 `QUEST_INFO_SPELL_REWARD_TO_HEADER`）。這類要整張重建。

### 2.3 有沒有「不 reload 就重刷」的官方管道？

| 候選 | 實測結果 |
|---|---|
| **事件 `INITIAL_HOTFIXES_APPLIED`** | **存在，而且是 Blizzard 官方定義的。** `Blizzard_APIDocumentationGenerated/SystemDocumentation.lua:75-78`：`{ Name = "InitialHotfixesApplied", Type = "Event", LiteralName = "INITIAL_HOTFIXES_APPLIED" }`。`Interface/GlueXML/CharacterSelect.lua:181` 註冊它、`:355` 收到就 `AccountUpgradePanel_Update(...)`。**但它是在 glue（選角）畫面被使用的，addon 在那個階段還沒載入。**（在遊戲內註冊得到、會不會再觸發 —— **未驗證**） |
| 重刷 `GlobalStrings` 的 API | **未找到。** `wow-ui-source@3.4.3` 沒有任何 `GetGlobalString` / `SetGlobalString` / 重載字串的呼叫 |
| CVar | **未找到。** `WowClassic.exe` 的 `strings` 裡與 hotfix 相關的只有 log 樣板與 RTTI，沒有任何看起來像 CVar 的 token；`WTF/Config.wtf` 裡與 hotfix 有關的只有 `CACHE-WQST-QuestV2HotfixCount` / `CACHE-WGOB-GameObjectsHotfixCount` 這類**計數器**，不是開關 |
| 啟動旗標 | **未找到**能改變 hotfix 時序的旗標。（`-ClearCache` 只會讓快取失效、讓下一次登入重下，**方向剛好相反**） |

> **「未找到」不等於「不存在」** —— 我沒有反編譯，只做了 `strings` 與官方 UI 原始碼全文檢索。

### 2.4 一個誠實的缺口：時序上仍有一個對不起來的地方

本篇量到的事實是：**hotfix 在進入世界之前約 27 秒（glue 階段）就套用完畢**（§1.2）。若遊戲內 FrameXML 是在「進入世界」時才載入，那它讀到的 `_G` 應該已經是中文的 —— 但使用者實測畫面是英文。

**推論（非直接觀測）**：這一代 client 的遊戲內 UI（FontString 與 XML `text=` 的求值）在 hotfix 抵達之前就已經完成，也就是 UI 的建立早於第一個封包；hotfix 的 DB2 回呼（§2.1）之後只更新了 `_G`，更新不到已經存在的 FontString。**這與使用者觀測到的「全域中文、畫面英文」完全一致，但我沒有直接證據指出 UI 是在哪一毫秒建立的。標示為推論。**

**可以一次判定的診斷（5 分鐘，零風險）**——建一個空 addon：

```lua
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("INITIAL_HOTFIXES_APPLIED")   -- 遊戲內收不收得到，順便驗
f:SetScript("OnEvent", function(_, e, a)
    if e == "ADDON_LOADED" and a ~= "HotfixProbe" then return end
    print(("[%s] %s SPELLBOOK_BUTTON=%s CHARACTER=%s")
        :format(date("%H:%M:%S"), e, tostring(SPELLBOOK_BUTTON), tostring(CHARACTER)))
end)
```

- 若 `ADDON_LOADED` 當下就印中文 → 全域早已就緒，**畫面上的英文純粹是 §2.2 的固化問題**，解法是 §3.1 的清單，**確定不需要 reload**。
- 若 `ADDON_LOADED` 印英文、`PLAYER_ENTERING_WORLD` 才印中文 → hotfix 比 addon 載入還晚，`_G` 覆寫要延到後者。
- 把印出的時戳與 `Logs/Hotfix.log` 的 `Done applying initial hotfixes` 對齊，就能把 §2.4 這個缺口徹底補上。

---

## 3. 四個替代方案，逐一裁決

| # | 方案 | 真的免 reload？ | 代價 / 風險 |
|---|---|---|---|
| **(a)** | **addon 在 `PLAYER_LOGIN` 對固化的 FontString 重新 `SetText(_G[TAG])`** | ✅ **是。這是唯一「乾淨」的解** | 要維護一張清單（上限 445 個 tag / 675 處，實務上只需做玩家真的會看到的數十個）。**因為 hotfix 已經把 `_G` 換成中文，這個 addon 完全不需要內含任何翻譯資料** —— 它只是「叫框架重讀一次」。範式抄 `greenya/ClassicUA` 的 `hooked_labels` / `update_hooked_labels()`（[ui-localization-addon.md](./ui-localization-addon.md) §2(b-2)）。**注意**：`AscensionPTBR/Core.lua:3801-3808` 記錄過「全域列舉所有 FontString 並掛 hook 會造成移動／轉鏡頭卡頓」——**要用明列的清單，不要掃全 UI** |
| **(b)** | **每次登入自動 `ReloadUI()` 一次** | ✅ 是（已由使用者實測有效） | 每次進世界多花數秒黑畫面；必須用旗標防止無限迴圈；戰鬥中／載入中呼叫要防護。**能用，但它是把成本轉嫁給每一次登入**，而 (a) 是一次性把清單列出來 |
| **(c)** | **CVar 或啟動旗標** | ❌ **未找到任何這種東西**（§2.3）。而且就算有，§1 已證明 hotfix 資料本身要等連線才存在，旗標無從改變 | — |
| **(d)** | **改用 addon 送字串（不走 hotfix）** | ❌ **不會比較好。** addon 也是在 FrameXML 之後才執行，`_G` 覆寫一樣打不到已建立的 FontString —— **需要的補救清單和 (a) 一模一樣**。而且它多出 taint 風險（[ui-localization-addon.md](./ui-localization-addon.md) §6.1），還打不到 glue | 唯一優勢：不佔 hotfix 頻寬。**在我們已經有 hotfix 通道的前提下，這是純退步** |
| **(e)** | 把 zhTW 資料放進 client 自己的 DB2 / CASC | ✅ 這才是真正的「啟動即套用」 | **不可行**：CASC 沒有第三方寫入路徑，`.build.info` 只有 `enUS` + `ruRU`（[zhtw-localization.md](./zhtw-localization.md)） |

### 3.1 推薦做法（最小、可逆）

1. 先跑 §2.4 的診斷 addon，確認 `_G` 在 `PLAYER_LOGIN` 前就已是中文（**高機率是**）。
2. 從 `wow-ui-source@3.4.3` 撈出候選清單：
   ```bash
   grep -rho 'text="[A-Z][A-Z0-9_]*"' Interface/FrameXML Interface_Wrath/FrameXML | sort -u
   ```
   445 個 tag。**不要全做** —— 先挑角色面板、任務面板、法術書、追蹤條這些天天看到的。
3. addon 在 `PLAYER_LOGIN` 對每個對應的 FontString `frame:SetText(_G[TAG])`；找不到 frame 就跳過。
4. 剩下 §2.2 提到的「被抄進 Lua 表」那一類（`QUEST_INFO_SPELL_REWARD_TO_HEADER` 之類），發現一個補一個。
5. **保留 (b) 作為隨時可退回的保險**：一行 `ReloadUI()` 就是永遠正確但笨重的答案。

---

## 4. proxy 能不能更早送？—— 已經是最早了

### 4.1 TrinityCore master（本 repo，第一手）

`src/server/game/Server/WorldSession.cpp:1441-1460`（`InitializeSessionCallback`）：

```cpp
    if (!m_inQueue)
        SendAuthResponse(ERROR_OK, false);
    ...
    SendSetTimeZoneInformation();
    SendFeatureSystemStatusGlueScreen();
    SendClientCacheVersion(sWorld->getIntConfig(CONFIG_CLIENTCACHE_VERSION));
    SendAvailableHotfixes();                 // ← 就在這
    SendAccountDataTimes(ObjectGuid::Empty, GLOBAL_CACHE_MASK);
```

**這是 `CMSG_AUTH_SESSION` 的處理尾端，緊鄰 `SendFeatureSystemStatusGlueScreen()`** —— 也就是**選角畫面**，遠早於進入世界。`SendAvailableHotfixes()` 本體（`HotfixHandler.cpp:59-72`）還會用 `push.AvailableLocalesMask & (1 << GetSessionDbcLocale())` 逐 push 過濾 locale，`HandleHotfixRequest` 也用 `WriteRecord(..., GetSessionDbcLocale(), ...)` 逐列寫出對應語系 —— **官方伺服器的 hotfix 本來就有 locale 維度**。

`WorldSocket.cpp` 另外兩點：`:348` 為 `CMSG_HOTFIX_REQUEST` 放寬到 0x100000，`:411` 收到第一個 `CMSG_HOTFIX_REQUEST` 之後就把 `_canRequestHotfixes = false` —— **每個連線只准要一次**，這也印證了「初始 hotfix 是一次性的登入事件」。

### 4.2 HermesProxy（`~/Works/side-project/wotlk-stack/hermesproxy`，第一手）

`HermesProxy/World/Server/WorldSocket.cs:955-975`，在 Realm 連線的 `HandleEnterEncryptedModeAck()` 裡：

```csharp
SendAuthResponse(BattlenetRpcErrorCode.Ok, worldClient.GetQueuePosition());
SendSetTimeZoneInformation();
SendFeatureSystemStatusGlueScreen();
SendClientCacheVersion(0);
SendAvailableHotfixes();       // ← 位置與順序與 TrinityCore master 完全相同
SendBnetConnectionState(1);
```

**→ 對任務問題 3 的正面回答：hotfix 已經是在 realm／選角（glue）階段送出的，不是進世界才送。TrinityCore 與 HermesProxy 在這件事上是同一份寫法，沒有可以往前搬的空間。** 再往前只剩下「玩家還沒輸入密碼」的階段 —— 那時候連線根本不存在。

### 4.3 那 12～21 秒是誰的

| session | Startup | 第一個 `ClientAvailableHotfixes` | 差 |
|---|---|---|---|
| `Hotfix.log` | 16:30:23.938 | 16:30:35.368 | **11.4 s** |
| `Hotfix.log.old` | 15:06:08.489 | 15:06:29.192 | **20.7 s** |

**這段時間是登入畫面在等人打帳號密碼**，長度由玩家決定。client 的 UI 在這段期間早就活著了。**任何協定層的優化都碰不到這段。**

---

## 5. 前提檢驗：Blizzard 自己怎麼做

使用者的推理是「Blizzard 的 hotfix 一定不用 reload，所以要 reload 就不合理」。逐項檢驗：

| 主張 | 檢驗結果 |
|---|---|
| Blizzard 的 hotfix 大多不需要 reload | **對，但那是因為它們是「顯示時才讀」的資料。** 我們自己的實測也一致：法術名、法術描述、物品名、區域名進遊戲即為中文 —— **這些表跟 Blizzard 的 hotfix 是同一類東西**（wago hotfix 存檔今天的前幾筆就是 `SpellMisc`、`CreatureDifficulty`、`SpellScript`、`QuestObjective`、`SpellName`、`Spell`、`AreaTriggerCreateProperties`） |
| UI 字串只走 client patch，不走 hotfix | **錯。** wago.tools 的 hotfix 存檔（**社群**）搜 `globalstrings` 回 **15,654 列**，最新兩批是 2026-08-29 / 2026-09-02（`zhCN` build 69497、`esES` build 49474）。**Blizzard 確實把 `GlobalStrings` 當 hotfix 推** |
| 所以 `GlobalStrings` hotfix 對 Blizzard 也不用 reload | **沒有證據支持，而且官方 UI 的兩處寫法指向相反方向**：`INITIAL_HOTFIXES_APPLIED` 這個事件的存在，就是承認「hotfix 會在 UI 建好之後才到，收到要自己重刷」；`CharacterSelect.lua:3554` 的 `-- HACK, avoid global string hotfix:` 更是直接在迴避這個問題 |
| 要 reload 是我們做法的缺陷 | **不是。** 這是 **load-once UI 字串的本質**：任何在 FontString 建立那一刻被抄走的字串，都不會因為之後改了來源而自己更新 —— 對 Blizzard 的 hotfix、對我們的 hotfix、對 addon 的 `_G` 覆寫，三者一視同仁 |

**差別只在量。** Blizzard 一次改幾十列、玩家的 client 本來就是母語，所以「有幾個標題要到下次登入才更新」沒有人會注意；我們一次改 **18,205 列**、而且那是英文→中文的全面切換，於是同一個機制變得刺眼。

> **一句話**：這不是「hotfix 沒生效」，是「hotfix 生效的時機晚於 UI 建立」，而 **UI 建立必然早於任何封包**，因為 UI 在玩家還沒輸入密碼時就已經在畫面上了。

---

## 6. 明確記錄「未驗證」

- **未驗證**：3.4.3 client 究竟在哪一刻建立遊戲內 FrameXML 的 FontString（process 啟動時 vs 進入世界時）。§2.4 的推論與使用者的觀測一致，但沒有直接觀測，**§2.4 的診斷 addon 就是為了補這一項**。
- **未驗證**：`INITIAL_HOTFIXES_APPLIED` 在**遊戲內**（非 glue）是否會觸發、能否被 addon 註冊到。官方只在 `GlueXML/CharacterSelect.lua` 用它。
- **未驗證**：client 對 `GlobalStrings` 的 DB2 回呼**具體做了什麼**。RTTI（`DynamicLifeTimeDB<GlobalStringsRec_C>` + `DB2CallbackEvent`）加上使用者「reload 前 print 已是中文」的實測，共同指向「回呼會重寫 `_G`」，但這是推論，不是反編譯結果。
- **未驗證**：`GetGlobalString` 是否為可從 Lua 呼叫的 API。它是 binary 裡的符號，但 `wow-ui-source@3.4.3` 全文 0 命中。
- **未找到**（≠ 不存在）：任何能改變 hotfix 套用時序的 CVar 或啟動旗標。只做了 `strings` + 官方 UI 原始碼檢索，未反編譯。
- **未驗證**：`Cache/ADB/enUS/` 底下目前只有 `*.tmp`（client 執行中的暫存），**正式的 `DBCache.bin` 落盤時機與命名未觀測**。header 與 entry 佈局的解讀已與 `Hotfix.log` 逐欄對照過，可信度高。
- **未驗證**：`DBCache.bin` header 的 32 bytes `verification_hash` 是什麼的雜湊（wowdev 也只給名字）。**它不影響本篇結論** —— 就算它永遠有效，快取仍然要等 `ClientAvailableHotfixes` 才被套用。
- **未做**：沒有修改任何檔案、沒有編譯、沒有登入遊戲、沒有寫過 §2.4 的診斷 addon。本篇是 log／位元組／原始碼層級的分析。
- **未做**：瀏覽器自動化。

---

## 7. 驗證指令（可重跑，全部唯讀）

```bash
C=~/'World of Warcraft 3.4.3.54261/_classic_'

# ---- ★ 本篇的骨幹：client 自己的 hotfix log ----
grep -n -- '----' "$C/Logs/Hotfix.log"          # 只有 5 行：Startup / Available / Request / Cache / Server
grep -n -- '----' "$C/Logs/Hotfix.log.old" | head -20   # 一個 process 內三次登入
awk '{print $4, $5}' "$C/Logs/Hotfix.log" | sort | uniq -c | sort -rn | head   # 逐表列數
grep -c VALIDATION_RESULT_VALID   "$C/Logs/Hotfix.log"   # 155477
grep -c VALIDATION_RESULT_INVALID "$C/Logs/Hotfix.log"   # 0

# ---- ★ DBCache.bin 的實際位元組（header + 第一筆 entry）----
python3 - <<'EOF'
import struct, glob
p = sorted(glob.glob(__import__('os').path.expanduser(
    "~/World of Warcraft 3.4.3.54261/_classic_/Cache/ADB/*/DBCache.bin*")))[0]
d = open(p, 'rb').read(200)
print(struct.unpack_from('<4sII', d, 0), d[12:44].hex())   # XFTH / 9 / 54261 / hash
print(struct.unpack_from('<4s7I', d, 44))                  # magic, region, push, unique, hash, recid, size, status
EOF

# ---- client binary：GlobalStrings 是動態 DB、hotfix 的 log 樣板 ----
strings -a "$C/WowClassic.exe" | grep -i globalstring | sort -u
strings -a "$C/WowClassic.exe" | grep -i hotfix       | sort -u
grep -iE 'hotfix|textLocale' "$C/WTF/Config.wtf"

# ---- ★ Blizzard 官方 UI 原始碼（tag 3.4.3）----
git clone --depth 1 --branch 3.4.3 https://github.com/Gethe/wow-ui-source.git uisrc && cd uisrc
grep -rn INITIAL_HOTFIXES_APPLIED .                  # SystemDocumentation.lua + GlueXML/CharacterSelect.lua
sed -n '3550,3560p' Interface/GlueXML/CharacterSelect.lua   # "-- HACK, avoid global string hotfix:"
grep -rho 'text="[A-Z][A-Z0-9_]*"' Interface/FrameXML Interface_Wrath/FrameXML | wc -l        # 675
grep -rho 'text="[A-Z][A-Z0-9_]*"' Interface/FrameXML Interface_Wrath/FrameXML | sort -u | wc -l  # 445
grep -rn GetGlobalString .                            # 0 命中

# ---- 送出時點：兩邊都在 glue 階段 ----
sed -n '1450,1460p' ~/Works/side-project/TrinityCore/src/server/game/Server/WorldSession.cpp
sed -n '59,72p'     ~/Works/side-project/TrinityCore/src/server/game/Handlers/HotfixHandler.cpp
sed -n '965,975p'   ~/Works/side-project/wotlk-stack/hermesproxy/HermesProxy/World/Server/WorldSocket.cs

# ---- Blizzard 自己有沒有 hotfix GlobalStrings（社群存檔）----
curl -s -A "Mozilla/5.0" "https://wago.tools/hotfixes?search=globalstrings" -o hf.html
python3 - <<'EOF'
import re, json, html
p = json.loads(html.unescape(re.search(r'data-page="(.*?)"></div>', open('hf.html').read(), re.S).group(1)))
h = p['props']['hotfixes']; print('total', h['total'])
for r in h['data'][:5]: print(r['created_at'], r['build'], r['table_name'], r['record_id'], r['locale'])
EOF

# ---- ADB / DBCache.bin 規格（社群 wiki，直接 curl 需帶 UA）----
curl -s -A "Mozilla/5.0" https://wowdev.wiki/DBCache.bin | grep -o 'dbcache_file_header_v5' | head -1
```

---

## 8. 實際取用過的來源

**本機 client（第一手實測，唯讀）**
- `_classic_/Logs/Hotfix.log`（12,395,782 bytes；5 行標記 + 155,477 行驗證結果）與 `Logs/Hotfix.log.old`（86,671,813 bytes；1,087,218 行、三次登入）
- `_classic_/Cache/ADB/enUS/DBCache.bin708.tmp`（26,506,936 bytes；header + entry 逐欄解出）、同目錄的 `ItemSparse*.tmp` / `Spell*.tmp` / `ConversationLine*.tmp` / `SceneScriptText*.tmp`
- `_classic_/WowClassic.exe`（`strings`：`DynamicLifeTimeDB<GlobalStringsRec_C>`、`DB2CallbackEvent`、`GetGlobalString`、`Initial Hotfixes: Requested/Received/Fake Connect/Applied`、`Cache\ADB`、`DBCache.bin`、`Logs/Hotfix.log`）
- `_classic_/WTF/Config.wtf`（`CACHE-*HotfixCount`、`textLocale "enUS"`）

**Blizzard 官方 UI 原始碼（`Gethe/wow-ui-source`，tag `3.4.3`，最接近第一手的鏡像）**
- `Interface/AddOns/Blizzard_APIDocumentationGenerated/SystemDocumentation.lua:75-78`（`INITIAL_HOTFIXES_APPLIED` 的官方定義）
- `Interface/GlueXML/CharacterSelect.lua:181`（註冊）、`:355`（處理）、**`:3554`（`-- HACK, avoid global string hotfix:`）**
- `Interface/GlueXML/GlueLocalization.lua`、`Interface_Wrath/FrameXML/*.xml`（675 處 `text="TAG"`、445 個 distinct tag）

**TrinityCore master（本 repo，第一手）**
- `src/server/game/Server/WorldSession.cpp:1441-1460`（`InitializeSessionCallback` → `SendAvailableHotfixes()`）
- `src/server/game/Handlers/HotfixHandler.cpp`（全文；`AvailableLocalesMask`、`WriteRecord(..., GetSessionDbcLocale(), ...)`）
- `src/server/game/Server/WorldSocket.cpp:348, 411`（`CMSG_HOTFIX_REQUEST` 的 1 MB 上限與 `_canRequestHotfixes` 一次性）

**HermesProxy（`~/Works/side-project/wotlk-stack/hermesproxy`，第一手）**
- `HermesProxy/World/Server/WorldSocket.cs:955-975`（Realm 連線的 `HandleEnterEncryptedModeAck` → `SendAvailableHotfixes()`）、`:1290`（`SendAvailableHotfixes` 本體）

**社群資源（明確標示非官方）**
- `https://wowdev.wiki/DBCache.bin`（重導向到 `ADB`）—— `dbcache_file_header_v5`（`magic/version/build_id/verification_hash[32]`）、`dbcache_entry_v7`、`RecordState`。**社群 wiki，非 Blizzard 官方**；直接 `curl` 需帶 UA
- `https://wago.tools/hotfixes` 與 `?search=globalstrings` —— Blizzard 實際推送的 hotfix 存檔（`GlobalStrings` 15,654 列）。**第三方社群存檔，非 Blizzard 服務**
