# 用 addon 中文化 UI 框架字串：可行性、天花板與最小實驗

> ⚠️ **更正（2026-09-04）**
>
> 本篇建議的 addon 覆寫 `_G` 路線**已被 hotfix 取代**，不需要 addon、無 taint 風險、無載入順序問題。另，本篇「找不到 zhTW/zhCN UI 漢化插件」的結論過早，確有 zhCN 專案存在（但對本案無用）。
>
> 詳見 [實作記錄與更正](./zhtw-implementation-and-corrections.md)。


> 撰寫日期：2026-09-03
> 相關筆記：[zhTW 中文化能做到哪裡](./zhtw-localization.md)（本篇推翻該篇 §4.1 最後一列與 §6「天花板」對 UI 的判斷）、[hotfix DB2 中文化深度評估](./hotfix-db2-localization.md)（本篇推翻該篇 §8.2「UI 框架字串永遠是英文」的**前提**，並為該篇的 Stage 5 新增一張表）
> 前提（承接前兩篇，非假設）：Windows 版 WoW Classic **`3.4.3.54261`** 解壓在 `~/World of Warcraft 3.4.3.54261/`，`.build.info` 只有 `enUS` + `ruRU`，`_classic_/Fonts/615974.slug` = `arkai_t.ttf`（繁中字型）已在，`_classic_/Interface/` 底下只有 `AddOns/`。
> 來源限定 primary sources：本機 client 檔案與**實際安裝的 addon `.toc`**、`gh api`（repo metadata / code search / raw 檔案內容）、`greenya/ClassicUA` 與 `GabrielBosco/AscensionPTBR` 的**原始碼全文**、`wago.tools` 實測 `curl`、`tekkub/wow-globalstrings` 的檔案與 README、WoWInterface 與 CurseForge 的專案頁（first-party listing）、`TrinityCore/WowPacketParser` 與 `Xian55/HermesProxy` 的 `DB2Hash.cs`。
> **wowdev.wiki 與 warcraft.wiki.gg（前 Wowpedia）皆為社群維護的 wiki，非 Blizzard 官方**，凡引用皆已標明。
> 未使用瀏覽器自動化。未編譯、未執行、未登入遊戲。凡未實測者一律標示「**未驗證**」。

---

## 0. TL;DR

1. **裁決：可行（viable），而且前兩篇筆記對這一層的判斷有一個關鍵事實錯誤。**
2. **★ 最重要的發現：`GlobalStrings` 在這個世代的 client 已經不是 Lua 檔，而是一張 DB2。** wago.tools 的檔案索引實測：`interface/framexml/globalstrings.lua`（FileDataID **841794**）只存在於 **6.0.x 的 `wow_beta` / `wowt`** 建置；而 `dbfilesclient/globalstrings.db2`（FileDataID **1394440**）存在於 **`wow_classic` 在內的 13 個 product**。wowdev.wiki 的 `DB/GlobalStrings` 頁對這張表的第一句就是：「Contains all interface String values, **successor of FrameXML/GlobalString.lua ≥ 7.0.3.22594**」。
3. **★ 因此「zhTW UI 字串拿不到」是錯的 —— 它就在 wago.tools 上，而且是這個 build 的。** 實測 `https://wago.tools/db2/GlobalStrings/csv?build=3.4.3.54261&locale=zhTW` 回 200、1,184,173 bytes、**18,232 列**，欄位是 `ID,BaseTag,TagText_lang,Flags`：

   ```
   9601,SPELLBOOK_BUTTON,法術書,1
   9604,ARMOR_COLON,護甲:,1
   ```

   **`BaseTag` 就是 Lua 全域變數名。** 與 `tekkub/wow-globalstrings` 的 `enUS.lua`（12,431 個 key）交叉比對：**99.1% 的 Lua key 出現在 `BaseTag` 集合裡**。→ §4 的「資料從哪來」不是問題，是已解決。
4. **★ `_G[key] = value` 這個手法有現成、活著、而且支援 Wrath Classic 的實證。** `greenya/ClassicUA`（烏克蘭語 Classic 中文化 addon，2019 建立，**最後 push 2026-08-25**，CurseForge 51.8K 下載）的 `scripts/strings.lua` 全文核心就是：

   ```lua
   for key, val_uk in pairs(addon_table.string_globals) do
       _G[key] = val_uk
   end
   ```

   而 repo 裡有 **`ClassicUA_Wrath.toc`，`## Interface: 30403`** —— 正是 3.4.3 的 interface 版本（本機安裝的 `Bagnon-Wrath.toc` 獨立佐證同一個數字）。
5. **★ 載入順序問題是真的，而且 ClassicUA 的原始碼裡有一個逐字的病例。** 同一個 `strings.prepare()` 在覆寫完全域之後，**手動重建了一張在 FrameXML 載入時就用舊值組好的表**，並附上出處連結：

   ```lua
   -- rebuild the table the game filled in with the original strings while it was loading
   -- https://www.townlong-yak.com/framexml/era/Blizzard_UIPanels_Game/QuestInfo.lua#405
   QUEST_INFO_SPELL_REWARD_TO_HEADER = { [QUEST_SPELL_REWARD_TYPE_FOLLOWER] = REWARD_FOLLOWER, ... }
   ```

   `scripts/frame_hooks.lua` 另有一張 **15 個 FontString 的 `hooked_labels` 清單**（`QuestInfoDescriptionHeader`、`QuestLogRewardTitleText`…），對每一個 `hooksecurefunc(frame, "SetText", ...)` 並提供 `update_hooked_labels()` 強制重刷。**這就是「已建立的框架」的標準解法，而且是抄得到的。**
6. **覆寫的天花板可以精確算出來。** `Flags` 欄是 bitmask（**推論，由資料反推**：bit1 = 遊戲內、bit2 = glue 登入畫面）：15,992 列只有遊戲內、**1,248 列只有 glue**、981 列兩者皆是、11 列皆非。→ **addon 打得到 16,973 / 18,232 = 93.1%；打不到的 1,248 列（6.8%）是登入與選角畫面**，這一項有獨立佐證（`tekkub/wow-globalstrings` README：「GlueStrings.lua is only loaded for the login and character/realm selection UI, **so its contents are not available to addons**」）。
7. **另有 1,338 列的 zhTW 與 enUS 逐字相同**（`SLASH_ASSIST1`、`CHAT_EMOTE_GET` 之類的格式樣板與斜線指令）—— 覆寫了也看不出差別，屬於帳面上有、視覺上沒有的部分。
8. **★ 而且冒出了第二條路：`DB2Hash.GlobalStrings = 0xBF0BC27A` 在 HermesProxy 與 TrinityCore 的 WowPacketParser 裡都已經存在。** 這代表 [hotfix 那篇](./hotfix-db2-localization.md) 的整套機器**原則上也能送 UI 字串**，而且欄序（`ID, BaseTag, TagText_lang, Flags`）與 wowdev 記載的 `GlobalStringsRec { m_ID; stringname; stringvalue; unk; }` 逐欄對應。**這條路沒有 Lua taint 問題**（見 §5.2），但 client 何時把 DB2 攤成 Lua 全域 —— **未驗證**。
9. **真正的技術風險只有一個，而且是實在的：taint。** warcraft.wiki.gg 的 `Taint` 頁（社群）：「When code sets global values, the resulting value has the taint of the execution path.」→ **addon 寫過的全域是 tainted 的**，Blizzard 的 secure 程式碼之後讀到它、又去呼叫 protected function 就會失敗。**ClassicUA 只覆寫 187 個手選的 key，不是全部 16,973 個** —— 這很可能不是懶，是設計。
10. **一句話**：把 §0.3 的 CSV 轉成一張 Lua 表、在自己的 addon 裡跑一次 `_G[k] = v`，是**一個下午**的工作量，而且失敗完全可逆（刪資料夾）。**但不要一次上 16,973 個 key。**

---

## 1. 事實基礎：`GlobalStrings` 現在是 DB2，不是 Lua

### 1.1 檔案索引實測（wago.tools）

wago.tools 的 `/files` 頁是一個 2,236,667 筆的 CASC 檔案索引（每筆帶 FileDataID、檔名、以及**每個 build 的 md5**）。搜尋 `GlobalStrings` 得到 4 筆：

| FileDataID | 檔名 | 出現在哪些 product | 有 3.4.3 嗎 |
|---|---|---|---|
| 841794 | `interface/framexml/globalstrings.lua` | **只有 `wow_beta`、`wowt`**（版本全部是 6.0.x / 6.0.2） | ❌ |
| **1394440** | **`dbfilesclient/globalstrings.db2`** | `wow`, `wow_anniversary`, `wow_beta`, **`wow_classic`**, `wow_classic_beta`, `wow_classic_era`, `wow_classic_era_ptr`, **`wow_classic_ptr`**, `wow_classic_titan`, `wowlivetest`, `wowt`, `wowxptr`, `wowz` | ✅ `3.4.3.51126`…`3.4.3.51831`（PTR）、`3.4.3.54948`／`55085`／`55325`／`55417`（正式） |
| 4007183 | `dbfilesclient/globalstrings.scn` | 含 `wow_classic` | — |
| 4007301 | `dbfilesclient/globalstrings_internal.scn` | 不含 `wow_classic` | — |

**讀法**：`GlobalStrings.lua` 這個檔在 WoD beta 之後就不再出貨了；同一份內容改以 `GlobalStrings.db2` 存在，且 Wrath Classic 明確在列。

> **注意一個細節**：檔案索引裡沒有 `3.4.3.54261` 這一個 build（有 54948 之後的），但 **DB2 匯出端點吃得下 54261**（§4.1）。這兩個是不同的索引，不衝突。

### 1.2 wowdev.wiki 的規格（社群，非官方）

`https://wowdev.wiki/DB/GlobalStrings`（分類標為 `DBC Legion` / `7.0.3.22594`）：

> "Contains all interface String values, successor of FrameXML/GlobalString.lua ≥ 7.0.3.22594"
>
> ```c
> struct GlobalStringsRec {
>   uint32_t m_ID;
>   stringrefⁱ stringname;
>   langstringrefⁱ stringvalue;
>   uint8_t unk;
> };
> ```

**四個欄位與 wago 匯出的 `ID,BaseTag,TagText_lang,Flags` 逐欄對應**（`stringname` = `BaseTag`、`stringvalue` = `TagText_lang`、`unk` = `Flags`）。

### 1.3 `BaseTag` 真的就是 Lua 全域名嗎？—— 99.1%（實測）

拿 `tekkub/wow-globalstrings` 的 `GlobalStrings/enUS.lua`（Blizzard 自產、檔頭寫 `-- AUTOMATICALLY GENERATED -- DO NOT EDIT!`，2014 年從當時的本地化 client 抽出）解出 **12,431 個 `KEY = "value";`**，與 3.4.3.54261 的 `BaseTag` 集合（18,232 個）比對：

```
lua keys present in wago tags: 12318 = 99.1%
```

差集是 6.0 之後才加的 key（`CHALLENGE_MODE_MEDAL1`、`BLIZZARD_STORE_LICENSE_ACK_TEXT` 之類），方向完全合理。

**→ 結論：`_G["SPELLBOOK_BUTTON"]` 這個全域，其值在 3.4.3 上是 client 從 `GlobalStrings.db2` 讀出來後放進 Lua 環境的。addon 可以讀、可以寫。**

---

## 2. `_G[key] = value` 到底有沒有用，什麼時候有用

三種情況必須分開，這是本題的核心。

### (a) 顯示時才讀全域 → **重新指派直接生效**

大多數 FrameXML 程式碼在事件發生時才 `format(ERR_LEARN_SPELL_S, name)` 或 `SomeText:SetText(REWARDS)`。addon 在 `ADDON_LOADED` 時改掉全域，**下一次顯示就是新值**。這是這條路能成立的原因。

### (b) 載入時就被固化 → **改了也沒用，必須額外處理**

兩個子情形，`ClassicUA` 的原始碼對兩者都有現成解法。

**(b-1) 被複製進表裡** —— `scripts/strings.lua` 全文（41 行）在覆寫迴圈之後接的就是這一段：

```lua
    -- rebuild the table the game filled in with the original strings while it was loading
    -- https://www.townlong-yak.com/framexml/era/Blizzard_UIPanels_Game/QuestInfo.lua#405
    QUEST_INFO_SPELL_REWARD_TO_HEADER = {
        [QUEST_SPELL_REWARD_TYPE_FOLLOWER] = REWARD_FOLLOWER,
        [QUEST_SPELL_REWARD_TYPE_TRADESKILL_SPELL] = REWARD_TRADESKILL_SPELL,
        ...
    }
```

FrameXML 在載入時把 `REWARD_FOLLOWER` 等**值**抄進一張查表；之後改全域不會回頭改那張表，只能整張重建。**這是一個逐字的病例，不是理論。**

**(b-2) 被 `SetText` 進 FontString（XML 的 `text="REWARDS"` 屬性）** —— `scripts/frame_hooks.lua:18-34` 的 `hooked_labels` 是一張 **15 筆的手工清單**：

```lua
local hooked_labels = {
    { frame=CurrentQuestsText },              -- "Current Quests"
    { frame=AvailableQuestsText },            -- "Available Quests"
    { frame=QuestInfoDescriptionHeader },     -- "Description"
    { frame=QuestInfoObjectivesHeader },      -- "Quest Objectives"
    { frame=QuestInfoRewardsFrame.Header },   -- "Rewards"
    ...
}
```

配上兩個函式（`fh.lua:240-258`）：

```lua
local function prepare_hooked_labels()
    for _, l in ipairs(hooked_labels) do
        if l.frame then
            l.frame.classicua = {}
            hooksecurefunc(l.frame, "SetText", on_hooked_label_set_text)
        end
    end
end

local function update_hooked_labels()
    for _, l in ipairs(hooked_labels) do
        if l.frame then
            local text = l.frame:GetText()
            if text then l.frame:SetText(text) end   -- 觸發自己的 hook
        end
    end
end
```

**「用原值再 SetText 一次以觸發自己的 hook」** —— 這是「已建立的框架」問題的標準解，可以照抄。

> 對於**純 GlobalStrings 覆寫**，其實還有一個更省事的變體：因為值已經在 `_G` 裡換掉了，直接 `frame:SetText(_G[TAG])` 就好，不必走 hook。hook 的存在是因為 ClassicUA 還要翻譯**動態內容**（任務標題等）。

### (c) 根本不是 Lua 全域 → **打不到**

- **glue（登入 / 選角 / 領域列表）畫面**：1,248 個 `Flags = 2` 的 tag。`tekkub/wow-globalstrings` 的 README 講得最白：
  > "GlueStrings.lua is only loaded for the login and character/realm selection UI, **so its contents are not available to addons**"
  addon 在進入遊戲世界之後才載入，glue 已經過去了。
- **伺服器直接送的字面字串**（TrinityCore 的 `trinity_string`、GM 指令輸出、自訂公告、HermesProxy 自己印的訊息）：client 只是把收到的字串貼上聊天視窗，沒有任何 tag 可覆寫。**這一類要走 [zhtw-localization.md](./zhtw-localization.md) §3.3 的 `trinity_string.content_loc5` + locale 切換。**
- **DB2 資料文字**（法術名、物品名、區域名、成就）：不在 `GlobalStrings` 裡，走 [hotfix 那篇](./hotfix-db2-localization.md) 的路。
- **烘進貼圖的字**（部分按鈕美術、小地圖裝飾）：無解。

### 2.1 載入時序（實測自 `ClassicUA/scripts/main.lua`）

```
FrameXML 載入（全域從 GlobalStrings.db2 被建立、XML 的 text= 被解析成 FontString）
  → addon 的 .lua 檔被載入執行
  → ADDON_LOADED（自己）：utils.prepare / options.prepare / strings.prepare ← _G 覆寫在這裡
                          dev_log / fonts / tooltips / chats / nameplates
  → PLAYER_LOGIN：entries / data_hooks / frame_hooks / options_ui   ← 框架 hook 在這裡
```

**`strings.prepare()` 掛在自己的 `ADDON_LOADED`，`frame_hooks.prepare()` 掛在 `PLAYER_LOGIN`。** 這個分工是有道理的：全域要盡早改（讓後面所有讀取都拿到新值），框架要等它們存在了才 hook。

---

## 3. 既有的翻譯 addon —— 最有力的證據

全部從 repo / 專案頁實際取得，不採信描述文案。

| 專案 | 目標語言 / client | 最後 push | ★ | License | Classic 支援？ | 手法 |
|---|---|---|---|---|---|---|
| **`greenya/ClassicUA`** | 烏克蘭語 / WoW Classic | **2026-08-25** | 23 | **無 LICENSE 檔** | ✅ repo 內有 `ClassicUA_Vanilla/_TBC/_Wrath/_Cata/_Mists.toc`，**`_Wrath` 是 `## Interface: 30403`** | **`_G[key] = val`**（`scripts/strings.lua`）+ `hooksecurefunc(fs,"SetText")` + 表重建 + `font:SetFont` 換字型 |
| `GabrielBosco/AscensionPTBR` | 巴西葡文 / Project Ascension（3.3.5a） | 2026-08-25 | 9 | `NOASSERTION`（有 `LICENSE-NOTICE.md` / `PERMISSION.md`） | `## Interface: 30300` | **刻意不動 `_G`**：走 FontString 掃描 + `hooksecurefunc(fs,"SetText")` + tooltip hook + `UI_ERROR_MESSAGE` 攔截 |
| `HideXs/AscensionES` | 西班牙文 / Project Ascension | 2026-08-19 | 15 | 無 | 同上（`AscensionPTBR` 的上游） | 同上 |
| `qqytqqyt` 的 `WoWeuCN_Quests` / `WoWenCN-Tooltips`（WoWInterface #25954 / #25955） | **簡中 zhCN** / **明確給「歐服語言鎖」的 enUS client 用** | 更新 2025-04-10，建立 2021-04-10，分類含 **WOTLK Classic** | — | 未標示 | 頁面標的相容性 `Cataclysm Classic (4.4.2)`，分類同時掛 TBC / WOTLK Classic | 只做**任務文字**與**tooltip**；自帶 `Fonts\woweucn.ttf`；**不碰 UI 框架字串** |
| `tekkub/wow-globalstrings` | 資料，非 addon | 2014-09-12 | 37 | **無** | — | 11 個 locale 的 `GlobalStrings.lua` / `GlueStrings.lua` 原檔（`zhTW.lua` 762,964 bytes、12,431 個 key） |
| `Sarjuuk/wow-globalstrings` | 同上的較新 fork | 2024-05-27 | 0 | 無 | — | 同結構 |

**四個必須講清楚的觀察：**

1. **ClassicUA 是唯一一個「真的改全域」而且「真的支援 Classic Wrath」的樣本，也是唯一還在維護的。** 它是本篇所有機制結論的來源。
2. **ClassicUA 只覆寫 187 個 key**（`entries/string.lua` 實測 `grep -c '^{ "'` = 187），不是全部。清單是手選的高可見度字串：`AMMOSLOT`、`CHARACTER_INFO`、`CONTESTED_TERRITORY`、`COPPER_AMOUNT`、`DEFAULT_AGILITY_TOOLTIP`、一整批 `ERR_*`……**而且它的初始化迴圈會先檢查該 key 在 client 上真的存在：**
   ```lua
   local val_en = _G[key]
   if type(val_en) == "string" then ... end
   ```
   （順帶建了 `string[val_en] = val_uk` 的英→烏反查表，供 §2(b) 的 SetText hook 用。）
3. **兩個 Ascension 專案刻意選了相反的路（不碰 `_G`）**，而且在 `Core.lua:3801-3808` 留下了為什麼要收斂掃描範圍的紀錄：
   > "A versão anterior enumerava a UI inteira e instalava hooks permanentes em cada FontString e GameTooltip encontrado. O pool de nameplates e o tooltip privado de NPC acabavam presos nesse pipeline, **causando travadas ao andar ou girar a câmera**. … **Não há EnumerateFrames global, não há hook em FontString arbitrário**"

   → **全域框架掃描 + 對任意 FontString 掛 hook 會造成移動／轉鏡頭時的卡頓。這是實作過的人寫的。** 我們要做的是最單純的全域覆寫，不需要走這條，但這條註解說明了「為什麼不要用暴力法」。
4. **沒有找到任何 zhTW（或 zhCN）版的 UI 框架字串翻譯 addon。** 多組關鍵字（GitHub repo search + code search + 中文關鍵字 + WoWInterface / CurseForge）都是零結果或只命中資料類 / 聊天俚語類專案。**這是「未找到」，不是「已證明不存在」。**

### 3.1 順帶：字型與錯誤訊息，兩個現成的樣板

- **字型**：`ClassicUA/scripts/fonts.lua` 對 29 個具名 Font 物件（`SystemFont_Shadow_Med1`、`QuestFont`、`GameTooltipHeader`…）逐一 `font:SetFont(file, height, flags)`，並且有一段很實用的踩雷紀錄：
  > "Since 2.5.6 (and corresponding builds for other versions) `GetFont()` reports internal font attributes (e.g. FILTER, FIXEDHEIGHT) among flags. Passing FIXEDHEIGHT back into `SetFont()` **breaks rendering of pooled combat text font strings**"

  → 重新套用 flags 時必須先過濾，只留 `OUTLINE / THICKOUTLINE / MONOCHROME / SLUG`。
  **本機情況：`_classic_/Fonts/615974.slug` = `arkai_t.ttf`（33 MB 繁中字型）已經在**（[zhtw-localization.md](./zhtw-localization.md) §4.4）。**但 addon 能不能直接以 `Fonts\ARKai_T.ttf` 這種 CASC 虛擬路徑引用它 —— 未驗證。** 最保險的退路是照 `qqytqqyt` 的做法自備一份 `.ttf` 放進 addon 資料夾。
- **伺服器錯誤訊息**：`AscensionPTBR/Errors.lua` 全文 80 行示範了另一種攔截 —— 對 `UIErrorsFrame` `UnregisterEvent("UI_ERROR_MESSAGE")`，自己註冊、翻譯後 `UIErrorsFrame:AddMessage(...)`。**但在我們的情境用不到**：3.4.3 的 `ERR_*` 是 client 端 GlobalStrings（`ERR_NOT_ENOUGH_MONEY` = `Flags 1`），覆寫全域就會變中文。**這套攔截是給「伺服器送整句字面字串」的情境用的，剛好是 §2(c) 的第二項。**

---

## 4. 資料來源：zhTW 的 UI 字串在哪（已解決）

### 4.1 wago.tools 的 `GlobalStrings` DB2 匯出（實測）

```
$ curl "https://wago.tools/db2/GlobalStrings/csv?build=3.4.3.54261&locale=zhTW"
ID,BaseTag,TagText_lang,Flags
9597,BUG_BUTTON,Bug及建議,1
9598,CHARACTER_BUTTON,角色資訊,1
9599,MAINMENU_BUTTON,遊戲選項,3
9600,QUESTLOG_BUTTON,任務記錄,1
9601,SPELLBOOK_BUTTON,法術書,1
```

| 項目 | 實測 |
|---|---|
| HTTP | 200，不需登入 |
| bytes | zhTW **1,184,173** / enUS 1,241,779 |
| 列數 | **18,232**（兩個 locale 相同） |
| ID 範圍 | 9,597 – 51,533 |
| `TagText_lang` 為空 | 27 列 |
| zhTW 含真實換行 | **45 列** |
| 含反斜線跳脫（`\32` 等） | **344 列** |
| zhTW 與 enUS 逐字相同 | **1,338 列** |

**→ 任務要求「verify and say so plainly」的那一項，答案是反過來的：wago.tools 確實有這份 UI 字串，因為它們早就不是 Lua/CASC-only 的資料，而是 DB2。這不是內容問題，是已解決的問題。**

同樣的查詢對 `3.4.3.54948` 也回 200（1,185,962 bytes），內容抽樣一致 —— 這條端點對 3.4.3 這一系是穩的。

### 4.2 轉成 Lua 時的兩個真實陷阱

拿 wago 的 zhTW 與 `tekkub` 的 `zhTW.lua`（Blizzard 自產的生成檔）對同一個 key 比對：

| key | wago `TagText_lang`（Python repr） | tekkub `.lua` 原始碼（repr） |
|---|---|---|
| `CHAT_MONSTER_SAY_GET` | `'%s說:\\32'` | `'%s說:\\32'` |
| `ABANDON_QUEST_CONFIRM` | `'放棄「%s」?'` | `'放棄「%s」?'` |

**兩者逐字相同 —— 也就是說 DB2 存的就是「Lua 原始碼層級」的字串。**

1. **`\32`（以及其它反斜線序列，344 列）必須原封不動寫進 Lua 字面量裡，讓 Lua 自己解碼。** 如果你把 `\` 再跳脫一次成 `\\32`，玩家就會在聊天視窗看到字面上的 `\32`。
2. **45 列真的含換行**，寫進 Lua 字面量時必須轉成 `\n`（單行字面量不能有實體換行）。

（`hotfix-db2-localization.md` §6.3 記過同一種內嵌換行風險，只是那邊是 CSV parser 的問題，這邊是 Lua 產生器的問題。）

### 4.3 備援來源

`tekkub/wow-globalstrings` 的 `GlobalStrings/zhTW.lua`（762,964 bytes、12,431 key）是**現成、可直接 `#include` 的 Lua 檔**，格式就是 `KEY = "值";`。缺點：**2014-09-12 之後沒更新過**，是 MoP/WoD 之交的內容，對 3.4.3 會少掉 5,801 個 tag、也會多出一些已移除的。**當作對照與抽查用，不當主來源。** `Sarjuuk` 的 fork（2024-05-27）較新但同樣沒有 build 維度。

**授權**：`tekkub`、`Sarjuuk`、`greenya/ClassicUA` **三者都沒有 LICENSE 檔**；wago.tools 是第三方社群存檔，內容是 Blizzard 的遊戲文字。**個人本機使用與公開再散布是兩回事**（同 [zhtw-localization.md](./zhtw-localization.md) §5.3.3）。

---

## 5. 天花板：跑完之後還有什麼是英文

### 5.1 可覆寫的比例（由 `Flags` 欄實算）

`Flags` 是 bitmask。**語意由資料反推（推論，非文件）**：

| Flags | 列數 | 樣本 | 判讀 |
|---|---|---|---|
| `1` | **15,992** | `SPELLBOOK_BUTTON`, `ERR_NOT_ENOUGH_MONEY`, `QUEST_LOG`, `SLASH_DUEL1`, `CHAT_MONSTER_SAY_GET` | 只在遊戲內 |
| `2` | **1,248** | `ENTER_WORLD`, `DELETE_CHARACTER`, `ACCOUNT_NAME`, `ABILITY_INFO_BLOODELF1` | **只在 glue（登入／選角）** |
| `3` | **981** | `MAINMENU_BUTTON`, `CANCEL`, `OKAY`, `LEVEL`, `ARMOR` | 兩邊都用 |
| `0` | 11 | `CRITERIA_TREE_OPERATOR_*`, `ERR_MOUNT_NO_MOUNTS` | 皆非（內部） |

> **addon 打得到：`1` + `3` = 16,973 / 18,232 = 93.1%。**
> **打不到：`2` = 1,248 = 6.8%，全部是登入畫面與選角畫面。**

再扣掉 **1,338 列 zhTW 與 enUS 相同**（斜線指令、`%s`-only 的格式樣板）與 **27 列空值**，實際「會讓玩家看到差別」的大約是 **15,600 列上下**。這個數字**不是精確的視覺涵蓋率**，只是「有翻譯且能寫得到的 tag 數」。

### 5.2 完整覆寫之後，玩家還會看到的英文（具體列舉）

| 類別 | 為什麼打不到 | 有沒有別的路 |
|---|---|---|
| **登入畫面、選角畫面、領域列表、刪除角色確認** | GlueStrings，addon 尚未載入（1,248 tag） | ❌（除非走 §5.3 的 hotfix 路，**未驗證**） |
| **伺服器送的字面字串**：`trinity_string`、GM 指令輸出、自訂公告、HermesProxy 自己的訊息 | client 只是原樣顯示 | ✅ 伺服器端：`trinity_string.content_loc5` + [zhtw-localization.md](./zhtw-localization.md) §3.4 的 locale 切換 |
| **法術名／描述、物品、任務、NPC、區域、成就名** | 不在 `GlobalStrings`，在各自的 DB2 / 伺服器表 | ✅ 另外兩篇筆記已經處理 |
| **戰鬥紀錄的「句型」**（`COMBATLOG_*`、`SPELLLOG*`） | **其實在 `GlobalStrings` 裡（`Flags 1`），打得到** | ✅ 句型會中文化；**句子裡嵌的法術名／單位名仍取決於 DB2 與伺服器** |
| **其他 addon 自己的 UI**（Bagnon 等） | 它們有自己的 locale 檔 | 各自處理，與本篇無關 |
| **烘進貼圖的字**（部分按鈕美術） | 不是文字 | ❌ |
| **C++ 端組裝後才交給 Lua 的 tooltip 行** | 若真有這類，覆寫全域無效 | **未驗證**：WotLK 的單位／物品 tooltip 有多少是引擎組好的，本篇沒有查證 |
| **`_G` 覆寫時序太晚而固化的字**（§2(b)） | 需要逐一 hook / 重建 | ✅ 有 ClassicUA 的樣板，但**要一個一個找出來** |

### 5.3 ★ 附帶發現：hotfix 也打得到 `GlobalStrings`（未驗證，但值得記）

實測 `gh api`：

```
Xian55/HermesProxy  HermesProxy/World/Enums/DB2Hash.cs:329
    GlobalStrings                   = 0xBF0BC27A,
TrinityCore/WowPacketParser  WowPacketParser/Enums/DB2Hash.cs:470
    GlobalStrings                     = 0xBF0BC27A,
```

**兩份獨立來源、同一個 hash。** 加上 §1.2 的 record 佈局（`uint32 ID` + 兩個 string + `uint8`）與 wago 匯出欄序逐欄對應，[hotfix 那篇](./hotfix-db2-localization.md) §4.2 的「需要新寫 loader」清單其實可以再加一張 `GlobalStrings`，工作量與 `SkillLine` 同級。

**兩個好處：**
1. **完全沒有 Lua taint 問題**（見 §6.1）—— 值在 client 建立全域之前就已經是中文的。
2. **理論上連 glue 畫面那 1,248 個 tag 也涵蓋**，因為 glue 也是同一張 DB2。

**三個未驗證的關鍵疑問：**
- client 何時把 `GlobalStrings.db2` 攤成 Lua 全域？若在 hotfix 抵達之前（很可能，UI 在進世界前就載入了），這條路就只有**下一次登入**才生效，甚至完全無效。
- 18,232 列 × 平均 ~65 bytes ≈ **1.2 MB 的 `SMSG_HOTFIX_CONNECT` 冷快取 payload**，advertise 側 +146 KB。落在該篇 §3 那個「從未複測過的大小疑慮」區間內。
- glue 畫面在 hotfix 抵達時**根本還沒連上世界伺服器**，所以「連 glue 也涵蓋」這句在時序上很可能是錯的。

**→ 記錄為一條有價值的後續，但 addon 路仍然是風險低得多、可逆得多的第一選擇。**

---

## 6. 風險

### 6.1 ★ taint —— 唯一實在的技術風險

`warcraft.wiki.gg/wiki/Taint`（**社群維護的 wiki，非 Blizzard 官方**）：

> "When code sets global values, the resulting value has the taint of the execution path."
> "When code accesses tainted values, the resulting value will remain tainted and the execution path is also tainted."

**逐字翻**：addon 寫進去的全域帶著 addon 的 taint；Blizzard 的 secure 程式碼之後讀到它，那條執行路徑就被污染，接著若要呼叫 protected function（動作條施法、單位框架的保護操作等）就會失敗（玩家看到的是 "Interface action failed because of an AddOn"）。

**這解釋了 ClassicUA 為什麼只覆寫 187 個 key。** 這是本篇最重要的實作建議：

> **不要一次 `for k,v in pairs(全部 16,973) do _G[k] = v end`。**
> 從高可見度、確定不在 secure 路徑上的 tag 開始（面板標題、按鈕、`ERR_*`、tooltip 標籤），逐批擴大，每批都在戰鬥中實測動作條與單位框架。
>
> **未驗證**：3.4.3 的哪些 `GlobalStrings` tag 會被 secure 程式碼讀到。這需要對 FrameXML 原始碼（`townlong-yak.com/framexml` 有各版本鏡像，**社群站**）逐一比對，本篇沒有做。

### 6.2 其它

- **效能**：純全域覆寫是 O(n) 一次性，n 最多 16,973，**不是問題**。真正會卡的是 AscensionPTBR 註解裡的那種「全域框架掃描 + 對任意 FontString 掛 hook」（§3.4），**不要做**。
- **`.toc` 版本**：3.4.3 的 interface 版本是 **`30403`**，兩個獨立實證：本機 `Interface/AddOns/Bagnon/Bagnon-Wrath.toc` 與 `ClassicUA_Wrath.toc`。
- **可逆性**：刪掉 addon 資料夾即完全復原。**代價最低的一條路。**

---

## 7. 裁決與最小 addon

### 7.1 裁決

> ## **可行（viable）。**
>
> | 疑慮 | 結案狀態 |
> |---|---|
> | 「`_G` 重新指派有沒有用」 | **有用。** `greenya/ClassicUA` 的 `scripts/strings.lua` 逐字做這件事，且 repo 有 `## Interface: 30403` 的 Wrath toc、2026-08 仍在維護 |
> | 「載入順序來不及」 | **是真問題，但已有解。** ClassicUA 對表重建與 15 個 FontString 的 hook 提供了可抄的樣板 |
> | 「zhTW UI 字串拿不到」 | **錯的。** `GlobalStrings` 自 7.0.3 起是 DB2，wago.tools 對 `build=3.4.3.54261&locale=zhTW` 回 200 / 18,232 列 |
> | 「3.4.x Classic 有沒有額外限制」 | **沒找到針對 Classic 的額外限制。** taint 模型是全版本共通的，且 ClassicUA 六年來一直在 Classic 各 flavor 上出貨 |
> | **taint** | **唯一還活著的風險。** 分批覆寫 + 排除清單是可控的，但需要實測 |
>
> **涵蓋率的誠實說法**：`GlobalStrings` 佔了「client 自己知道的 UI 字」的**絕大部分**，其中 addon 打得到 **93.1%**（16,973 / 18,232 tag），打不到的 6.8% 全部是登入與選角畫面。但 **`GlobalStrings` 不等於「玩家看到的全部文字」** —— 面板上的標題與按鈕來自它，格子裡的內容（法術名、物品名、任務文）不來自它。
>
> **三篇筆記合起來，剩下真正打不到的只有：登入／選角畫面、伺服器自訂字面訊息、以及貼圖裡的字。**
> 前一篇說的「真正打不到的只剩按鈕上的字」—— **連按鈕上的字都在射程之內了。**

### 7.2 最小 addon 的樣子

```
~/World of Warcraft 3.4.3.54261/_classic_/Interface/AddOns/zhTWStrings/
├── zhTWStrings.toc
├── data/GlobalStrings_zhTW.lua      ← 由 wago CSV 產生
└── main.lua
```

**`zhTWStrings.toc`**（只服務這一個 client，不需要多 flavor 後綴）：
```
## Interface: 30403
## Title: zhTW UI Strings
## Version: 0.1

data\GlobalStrings_zhTW.lua
main.lua
```

**`data/GlobalStrings_zhTW.lua`**（產生器輸出；注意 §4.2 的兩個陷阱）：
```lua
ZhTWStrings = {
["SPELLBOOK_BUTTON"] = "法術書",
["ARMOR_COLON"] = "護甲:",
["CHAT_MONSTER_SAY_GET"] = "%s說:\32",   -- 反斜線原封不動
["ADD_IGNORE_LABEL"] = "輸入想要忽略的玩家名字\n或者在聊天視窗中\n按住Shift點擊該玩家的名字：",
}
```

**`main.lua`**（照 ClassicUA 的骨架，含它的存在性檢查）：
```lua
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, name)
    if name ~= "zhTWStrings" then return end
    self:UnregisterEvent("ADDON_LOADED")
    local n = 0
    for k, v in pairs(ZhTWStrings) do
        if type(_G[k]) == "string" then   -- 只覆寫 client 上真的存在的 tag
            _G[k] = v
            n = n + 1
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage("zhTWStrings: " .. n .. " overridden")
end)
```

**產生器**（本機跑一次，唯讀取用 wago）：
```python
import csv, io, urllib.request
URL = "https://wago.tools/db2/GlobalStrings/csv?build=3.4.3.54261&locale=zhTW"
rows = csv.DictReader(io.StringIO(urllib.request.urlopen(URL).read().decode("utf-8")))
out = ['ZhTWStrings = {']
for r in rows:
    if int(r["Flags"]) & 1 == 0:      # 略過 glue-only（Flags == 2）
        continue
    t = r["TagText_lang"]
    if not t:
        continue
    # 只跳脫雙引號與實體換行；既有的反斜線序列（\32 等）必須原樣送給 Lua
    t = t.replace('"', '\\"').replace("\r", "").replace("\n", "\\n")
    out.append('["%s"] = "%s",' % (r["BaseTag"], t))
out.append('}')
open("GlobalStrings_zhTW.lua", "w", encoding="utf-8").write("\n".join(out))
```

**已建立框架的處理**（第二階段才做）：先看哪些標題沒變，再照 ClassicUA 的 `hooked_labels` 做一張清單，在 `PLAYER_LOGIN` 時對每個 `frame:SetText(_G[TAG])`。

### 7.3 第一個具體實驗（證明或殺死它）

> **十個字，五分鐘，零風險。**
>
> 1. 建 `Interface/AddOns/zhTWStrings/`，`.toc` 如上，`data/GlobalStrings_zhTW.lua` **只放十個高可見度的 tag**（先手抄，不要跑產生器）：
>    `SPELLBOOK_BUTTON`(法術書)、`CHARACTER_BUTTON`(角色資訊)、`QUESTLOG_BUTTON`(任務記錄)、`MAINMENU_BUTTON`(遊戲選項)、`TALENTS`(天賦)、`ACHIEVEMENTS`(成就)、`BACKPACK_TOOLTIP`(背包)、`ARMOR_COLON`(護甲:)、`CANCEL`、`OKAY`。
> 2. 登入，在聊天視窗確認出現 `zhTWStrings: 10 overridden`。
> 3. **看三個地方**：
>    - 滑鼠移到微型選單的法術書按鈕 → tooltip 是不是「法術書」？（**顯示時才讀全域**，應該會變）
>    - 開角色面板 → 「護甲:」變了嗎？
>    - 任意確認對話框的 Cancel / Okay 按鈕 → 變了嗎？（`Flags 3`，兩邊共用）
>
> **判讀：**
>
> | 結果 | 意義 | 下一步 |
> |---|---|---|
> | 三個都變中文 | **全案成立。** 顯示時讀取 + 字型 + UTF-8 一次全部驗完 | 跑產生器，分批擴大（先 1,000 個，測動作條與戰鬥） |
> | 變中文但是方塊 | 覆寫成功、**字型才是瓶頸** | 照 `ClassicUA/scripts/fonts.lua` 做 `font:SetFont`，或自備 `.ttf` |
> | tooltip 變了、面板標題沒變 | 正是 §2(b) 的固化問題 | 加 `hooked_labels` 樣板 |
> | 完全沒變、且沒有那行訊息 | addon 沒載入 | 檢查 `.toc` 的 `## Interface: 30403` 與資料夾名稱是否等於 `.toc` 檔名 |
> | 之後出現 "Interface action failed because of an AddOn" | **taint 咬到了** | 二分法找出是哪個 tag，加進排除清單（§6.1） |
>
> **代價：刪掉一個資料夾就完全復原。** 這一步應該排在 [hotfix 那篇](./hotfix-db2-localization.md) 的 Stage 1 之前 —— 它更便宜、更快、而且與 hotfix 完全正交。

---

## 8. 明確記錄「未驗證」

- **未驗證**：3.4.3.54261 的 client 何時、以什麼順序把 `GlobalStrings.db2` 攤成 Lua 全域。§1 的證據鏈（DB2 存在 + wowdev 說是 `.lua` 的後繼 + `BaseTag` 與 Lua key 99.1% 相符）很強，但**沒有在遊戲裡 `/dump` 過任何一個值**。
- **未驗證**：`Flags` 欄的 bit 語意。§5.1 的「bit1=遊戲、bit2=glue」是從 `ENTER_WORLD/DELETE_CHARACTER/ACCOUNT_NAME = 2` 對 `SPELLBOOK_BUTTON/ERR_* = 1` 對 `CANCEL/OKAY/LEVEL = 3` 反推的，**wowdev 只寫 `uint8_t unk`**。
- **未驗證**：哪些 `GlobalStrings` tag 會被 Blizzard 的 secure 程式碼讀到（taint 風險面）。**這是唯一可能讓大規模覆寫翻車的東西。**
- **未驗證**：addon 能不能以 `Fonts\ARKai_T.ttf` 之類的路徑引用 client 自帶的 `615974.slug`。退路（自備 `.ttf`）已知可行（`qqytqqyt` 的 addon 就是這樣做的）。
- **未驗證**：3.4.3 的單位／物品 tooltip 有多少行是 C++ 組好才交給 Lua 的（§5.2 最後一列）。
- **未驗證**：`GlobalStrings` 走 hotfix 通道（§5.3）的一切 —— 時序、大小、glue 是否涵蓋。`DB2Hash = 0xBF0BC27A` 對 build 54261 是否正確同樣未驗證（與 [hotfix 那篇](./hotfix-db2-localization.md) §9 的第一項同性質）。
- **未找到**：任何 zhTW 或 zhCN 的 WoW UI 框架字串翻譯 addon。**「未找到」不是「不存在」。**
- **未做**：沒有寫過、安裝過或執行過任何 addon；沒有登入遊戲；沒有實際產生 `GlobalStrings_zhTW.lua`（§7.2 的產生器未執行）。
- **未做**：瀏覽器自動化。`warcraft.wiki.gg` 對直接 `curl` 回 403，改以 WebFetch 取得（`Localizing_an_addon`、`Taint` 兩頁）；`Global_strings` 這個頁名不存在（404）。WoWInterface 對 WebFetch 回 403，改以帶 UA 的 `curl` 取得。
- **未評估**：把 wago.tools 匯出的 Blizzard UI 文字打包成 addon 再散布的授權問題。**個人本機使用與公開再發布是兩回事。** `tekkub`、`Sarjuuk`、`greenya/ClassicUA` 三個 repo 均無 LICENSE 檔（= 預設保留所有權利）。

---

## 9. 驗證指令（可重跑，全部唯讀）

```bash
# ---- 本機 client（唯讀）----
ls    ~/'World of Warcraft 3.4.3.54261/_classic_/Interface'          # 只有 AddOns
grep -H '## Interface' \
      ~/'World of Warcraft 3.4.3.54261/_classic_/Interface/AddOns/Bagnon/Bagnon-Wrath.toc'
#     → 30403（3.4.3 的 interface 版本，來自實際安裝的 addon）

# ---- ★ GlobalStrings 是 DB2 的證據 ----
curl -sL "https://wago.tools/files?search=GlobalStrings" -o f.html
python3 - <<'EOF'
import re,json,html
d=json.loads(html.unescape(re.search(r'data-page="(.*?)"></div>',open('f.html').read(),re.S).group(1)))
for r in d['props']['files']['data']:
    print(r['fdid'], r['filename'], sorted({c['product'] for c in r['chashes']}))
EOF
#  841794 interface/framexml/globalstrings.lua ['wow_beta','wowt']            ← 只有 6.0.x
# 1394440 dbfilesclient/globalstrings.db2      [... 'wow_classic' ...]        ← 含 Wrath Classic

curl -s -A "Mozilla/5.0" "https://wowdev.wiki/DB/GlobalStrings" | grep -o "successor of[^<]*"

# ---- ★ zhTW 的 UI 字串（本篇的核心資料）----
curl -s "https://wago.tools/db2/GlobalStrings/csv?build=3.4.3.54261&locale=zhTW" -o gs_zhTW.csv
curl -s "https://wago.tools/db2/GlobalStrings/csv?build=3.4.3.54261&locale=enUS" -o gs_enUS.csv
head -6 gs_zhTW.csv
python3 - <<'EOF'
import csv, collections
z=list(csv.DictReader(open('gs_zhTW.csv',encoding='utf-8')))
e={r['BaseTag']:r['TagText_lang'] for r in csv.DictReader(open('gs_enUS.csv',encoding='utf-8'))}
print('rows', len(z))                                                        # 18232
print('flags', collections.Counter(r['Flags'] for r in z))                   # 1:15992 2:1248 3:981 0:11
print('same as enUS', sum(1 for r in z if e.get(r['BaseTag'])==r['TagText_lang']))  # 1338
print('multiline', sum(1 for r in z if '\n' in r['TagText_lang']))           # 45
print('backslash', sum(1 for r in z if '\\' in r['TagText_lang']))           # 344
EOF

# ---- BaseTag == Lua 全域名（99.1%）----
curl -sL "https://raw.githubusercontent.com/tekkub/wow-globalstrings/master/GlobalStrings/enUS.lua" -o gs_enUS.lua
python3 - <<'EOF'
import csv,re
tags={r['BaseTag'] for r in csv.DictReader(open('gs_enUS.csv',encoding='utf-8'))}
lua=set(re.findall(r'^([A-Z0-9_]+) = ',open('gs_enUS.lua',encoding='utf-8').read(),re.M))
print(len(lua),'lua keys;',len(lua&tags),'in wago =%.1f%%'%(100*len(lua&tags)/len(lua)))
EOF

# ---- ★ ClassicUA：_G 覆寫、Wrath toc、hooked_labels ----
B=https://raw.githubusercontent.com/greenya/ClassicUA/master
curl -sL $B/ClassicUA_Wrath.toc | head -1              # ## Interface: 30403
curl -sL $B/scripts/strings.lua                        # 全文 30 行：_G[key] = val_uk + 表重建
curl -sL $B/entries/string.lua | grep -c '^{ "'        # 187 個手選的 key
curl -sL $B/scripts/frame_hooks.lua | sed -n '18,34p;240,258p'   # hooked_labels + 兩個函式
curl -sL $B/scripts/fonts.lua                          # 字型覆寫與 FIXEDHEIGHT 踩雷紀錄
curl -sL $B/scripts/main.lua | sed -n '/ADDON_LOADED/,/prepare_nameplates/p'  # 載入時序

# ---- AscensionPTBR：刻意不動 _G 的反例 ----
A=https://raw.githubusercontent.com/GabrielBosco/AscensionPTBR/main
curl -sL $A/AscensionPTBR.toc | head -2                # ## Interface: 30300
curl -sL $A/Core.lua | sed -n '3801,3810p'             # 為什麼不做全域框架掃描
curl -sL $A/Errors.lua                                 # UI_ERROR_MESSAGE 攔截樣板
curl -sL $A/data/UIStrings.lua | head -5               # 15363 行的 tag→pt-BR 對照

# ---- hotfix 也打得到 GlobalStrings（附帶發現）----
gh api "repos/Xian55/HermesProxy/contents/HermesProxy/World/Enums/DB2Hash.cs?ref=feature/wotlk-classic-v3.4.3" \
  --jq '.content' | base64 -d | grep -n GlobalStrings
gh api "repos/TrinityCore/WowPacketParser/contents/WowPacketParser/Enums/DB2Hash.cs" \
  --jq '.content' | base64 -d | grep -n GlobalStrings
# 兩邊都是 0xBF0BC27A
```

---

## 10. 實際取用過的來源

**本機（第一手實測，唯讀）**
- `~/World of Warcraft 3.4.3.54261/_classic_/Interface/`（只有 `AddOns/`）、`AddOns/Bagnon/Bagnon-Wrath.toc`（`## Interface: 30403`）、`AddOns/BagBrother/*.toc`、`_classic_/WTF/Config.wtf`

**`greenya/ClassicUA`（第一手，raw 檔案全文 + `gh api` metadata）**
- `ClassicUA_Wrath.toc`（`## Interface: 30403`、Version 6.7）、`ClassicUA_Vanilla/_TBC/_Cata/_Mists.toc`
- `scripts/strings.lua`（全文，`_G[key] = val_uk` + `QUEST_INFO_SPELL_REWARD_TO_HEADER` 重建）
- `scripts/main.lua`（全文，載入時序）、`scripts/frame_hooks.lua:18-34,240-258`（`hooked_labels`）、`scripts/fonts.lua`（全文）
- `entries/string.lua`（187 個 key + 初始化迴圈）、`entries/wrath/`（22 個檔的清單與大小）
- repo metadata：created 2019-08-10、pushed 2026-08-25、★23、**無 LICENSE**

**`GabrielBosco/AscensionPTBR` / `HideXs/AscensionES`（第一手）**
- `AscensionPTBR.toc`（`## Interface: 30300`）、`Core.lua`（6,331 行；3801-3808 的設計註解、`hooksecurefunc` / `GetRegions` 用法）、`Errors.lua`（全文）、`Runtime.lua`、`data/UIStrings.lua`（15,363 行）、`data/Globals.lua`、`README.md`

**`tekkub/wow-globalstrings` / `Sarjuuk/wow-globalstrings`（第一手）**
- `README.md`（GlueStrings 不可用於 addon 的明文）、`GlobalStrings/{enUS,zhTW,ruRU}.lua`（各 12,431 個 key）

**`Xian55/HermesProxy` / `TrinityCore/WowPacketParser`（第一手，`gh api`）**
- 兩份 `DB2Hash.cs` 的 `GlobalStrings = 0xBF0BC27A`

**第三方社群存檔（明確標示非官方）**
- `https://wago.tools/db2/GlobalStrings/csv?build={3.4.3.54261,3.4.3.54948}&locale={enUS,zhTW}`
- `https://wago.tools/files?search={GlobalStrings,FrameXML}`（inertia props 內的 FileDataID / product / md5 索引）
- `https://wowdev.wiki/DB/GlobalStrings`（`GlobalStringsRec` 結構與「successor of FrameXML/GlobalString.lua ≥ 7.0.3.22594」）

**社群 wiki（明確標示非官方；前 Wowpedia）**
- `https://warcraft.wiki.gg/wiki/Localizing_an_addon`
- `https://warcraft.wiki.gg/wiki/Taint`（taint 如何透過全域擴散）

**專案頁（first-party listing）**
- `https://www.curseforge.com/wow/addons/classicua`（v6.7 / 2026-08-25 / 51.8K 下載；目前列的 flavor 是 MoP Classic、Classic、Classic TBC —— **與 repo 內仍在的 `_Wrath.toc` 不衝突，只是 Wrath 這個 live flavor 已經結束**）
- `https://www.wowinterface.com/downloads/info25954-QuestTranslator-ChineseWotLKClassic.html`
- `https://www.wowinterface.com/downloads/info25955-TooltipsTranslator-ChineseWotLKClassic.html`
- `https://www.curseforge.com/wow/addons/translatecn`（**查證後排除**：只翻譯聊天俚語，與 UI 無關）

**取用失敗**
- `warcraft.wiki.gg` 直接 `curl` 一律 403（Cloudflare）；`/wiki/Global_strings` 這個頁名不存在（404）。
- `wowinterface.com` 對 WebFetch 回 403，改以帶 UA 的 `curl` 取得（200）。
- GitHub repo search 對含中文的 query 需要 `-X GET -f q=`，直接拼進 URL 會回 `invalid character '<'`。
