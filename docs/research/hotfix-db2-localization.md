# 用 hotfix 把 client DB2 換成繁中：深度評估與實驗計畫

> ⚠️ **更正（2026-09-04）**
>
> 兩處更正：(1) 本篇引用的「CASC 無鬆散覆蓋」已被推翻；(2) `ItemSparse` 被判定為欄位不符是**參考來源與解析器兩個錯誤**造成的，改用 WoWDBDefs 對應 build 的 layout 後完全對齊，45,070 筆已實作生效。
>
> 詳見 [實作記錄與更正](./zhtw-implementation-and-corrections.md)。


> 撰寫日期：2026-09-03
> 相關筆記：[zhTW 中文化能做到哪裡](./zhtw-localization.md)（本篇是該篇 §4.3「有根據的推測」那一格的深入追查，**並修正其中兩項結論**）、[HermesProxy 決策級評估](./hermesproxy-evaluation.md)（stack 前提）、[用 addon 中文化 UI 框架字串](./ui-localization-addon.md)（**推翻本篇「UI 字串永遠是英文」的前提**：`GlobalStrings` 自 7.0.3 起是 DB2，zhTW 版可從 wago.tools 取得）
> 前提（承接前兩篇，非假設）：Windows 版 WoW Classic **`3.4.3.54261`** 解壓在 `~/World of Warcraft 3.4.3.54261/`，`.build.info` 只有 `enUS` + `ruRU`，但 `_classic_/Fonts/615974.slug` = `arkai_t.ttf`（繁中字型）已在。stack = 3.4.3 client → `Xian55/HermesProxy@feature/wotlk-classic-v3.4.3` → TrinityCore 3.3.5 / AzerothCore。
> 來源限定 primary sources：HermesProxy 分支 tarball 與**完整 git 歷史**（`git clone` 後 `git log -S` 追 commit，唯讀）、`gh api` 取的 commit message、本 repo master 的 TrinityCore 原始碼與 `sql/base/dev/hotfixes_database.sql`、本機 client 檔案（實際 `ls` / `cat`）、`wago.tools` 實測 `curl`、`nietras/Sep` README。
> **wowdev.wiki 為社群維護的 wiki，非 Blizzard 官方**，凡引用皆已標明。
> 未使用瀏覽器自動化。凡未實測者一律標示「**未驗證**」。

---

## 0. TL;DR

1. **裁決：可行（viable），而且比前一篇筆記估計的樂觀得多。** 三個被懷疑的阻礙裡，**沒有一個是致命的**。
2. **★ 最重要的一項：`TableFilter` 只放行 `AreaTrigger`，是「目前只需要這一張」，不是「其他都會壞」。** 這在 commit `81ccf066`（2026-08-28）的 message 裡寫得毫無模糊空間：`ChrCustomizationChoice`(1064) / `ChrCustomizationOption`(190) 被移除的唯一理由是它們**與 client 自己的 DB2 逐欄位完全相同**（「1064 compared, 1064 identical, 0 differing, 0 new」），是純浪費。這是**效能修剪，不是相容性退讓**。
3. **★ 而且維護者親口寫過 client 會吃下 hotfix 覆寫。** commit `bf717dc4`（2026-08-28）：「**The client will honour hotfixed AreaTrigger rows. It simply never received any**」，並附上 client 自己的 `Logs/Hotfix.log` 證據：`"Table AreaTrigger ... VALIDATION_RESULT_VALID"`。`AreaTrigger3.csv` 現行 4 列裡有一列註明是 **relocate 一個「client 已存在的列」** —— **覆寫既有列（不是新增列）在 3.4.3 上已經實證可行。**
4. **★ 「~5 MB parse-abort」是被誤讀的。** 追 git 歷史後發現：那個觀察（commit `281001d`）與**同一天、緊接其後**的 commit `8f49b45` 是同一件事的兩半。`8f49b45` 找出真因是**壓縮 bug**：V3_4_3 沒有 `SMSG_COMPRESSED_PACKET` 的 opcode 對映，proxy 把任何 >1 KB 的封包包進去就變成 opcode-0 被 client 靜默丟棄。修掉之後 14 KB 的封包**立刻就通了**。→ **那個 ~5 MB 從來沒有在壓縮修好之後被重測過，也從來沒有量出精確上限。**
5. **`SpellName` 與 `Spell` 是「純字串表」** —— wago 的欄位就只有 `ID,Name_lang` 與 `ID,NameSubtext_lang,Description_lang,AuraDescription_lang`。**loader 已存在、欄位順序與 wago 匯出逐欄相同、可以零轉換直接丟檔。** 這是整件事最大的運氣。
6. **天賦不需要另做。** wago 的 `Talent.Description_lang` 在 WotLK **全是空的**；天賦的名稱與敘述實際來自 `SpellRank_N` 指向的 `SpellName` / `Spell` 列。→ **做掉 SpellName + Spell，天賦面板一併變中文。**
7. **需要新寫 loader 的只有**：`Achievement`、`AreaTable`、`Map`（以及 `ChrClasses` / `ChrRaces` / `Faction`）。這些表有大量非字串欄位，必須整列照 client 欄位順序序列化。`SkillLine` 例外 —— loader 已存在且欄序相符。
8. **修正前一篇的兩個數字。** `Spell` 的 zhTW 是 **49,357 列**、`Map` 是 **130 列**（前篇的 53,071 / 177 是把描述欄裡的換行當成資料列數了：`Spell` 有 2,013 列含內嵌換行）。
9. **天花板不變**：**UI 框架字串（FrameXML / `GlobalStrings`）永遠是英文。** 本機實測 `_classic_/Interface/` 底下只有 `AddOns/`，沒有任何 loose 的 FrameXML —— UI Lua 在 CASC 裡而且帶 locale tag，hotfix 完全打不到。

---

## 1. HermesProxy 的 hotfix 機器（原始碼實測）

### 1.1 現行 CSV 的實際狀況

`HermesProxy/CSV/Hotfix/` 共 **29 個檔**（前一篇已修正 README 的「18」）。**檔名尾碼是 modern client 的 expansion version**，3.4.3 只讀 `*3.csv`，共 **9 個**：

| 檔 | 資料列 | bytes | 有字串欄嗎 |
|---|---|---|---|
| `AreaTrigger3.csv` | **4** | 981 | `Message_lang`（全空） |
| `BattlePetSpecies3.csv` | 178 | 3,395 | ❌ |
| `GlyphProperties3.csv` | 365 | 8,452 | ❌ |
| `Heirloom3.csv` | 38 | 390 | ❌ |
| `ItemEffect3.csv` | 24,709 | 866,194 | ❌ |
| `Mount3.csv` | 280 | 1,665 | ❌ |
| `SpellVisualMissile3.csv` | 1,824 | 10,121 | ❌ |
| `SpellXSpellVisual3.csv` | 33,466 | 1,263,645 | ❌ |
| `Toy3.csv` | 73 | 731 | ❌ |

**→ 3.4.3 目前一個字串都沒有透過 hotfix 送出去。** 另外 `ChrCustomizationChoice3.csv` / `ChrCustomizationOption3.csv` **已經從 repo 移除**（loader 仍在，缺檔就 `return`）—— 這正是 §2 那次修剪的產物。

`*1.csv`（Classic Era）那一組才有字串範例：`SpellName1.csv` 的 header 是 `SpellId,Name`、`Spell1.csv` 是 `SpellId,NameSubText,Description,AuraDescription`、`SkillLine1.csv` 是 `DisplayName,AlternateVerb,Description,HordeDisplayName,NeutralDisplayName,Id,...`。**這些 loader 是版本無關的，只是 3.4.3 沒有對應的 `*3.csv` 檔。**

### 1.2 loader 怎麼載（`HermesProxy/World/GameData.cs`）

`LoadHotfixes()`（2134 行）用 `Parallel.Invoke` 跑 19–22 個 sub-loader，每個 sub-loader 寫進**互不重疊的 HotfixId 區段**（2106–2127 行的 `HotfixXxxBegin` 常數，間隔 100,000）：

```csharp
public const uint HotfixSpellBegin      = 1_400_000;
public const uint HotfixSpellNameBegin  = 1_500_000;
public const uint HotfixSpellLevelsBegin= 1_600_000;
```

`LoadSpellNameHotfixes()`（2451 行）全文的關鍵部分：

```csharp
var path = Path.Combine("CSV", "Hotfix", $"SpellName{ModernVersion.ExpansionVersion}.csv");
if (!File.Exists(path))
{
    // Not shipped for this expansion: the client's own DB2 already carries these
    // rows verbatim, so there is nothing to override. See scripts/compare-hotfix-csv.py.
    return;
}
using var reader = Sep.Reader(o => o with { HasHeader = true, Unescape = true }).FromFile(path);
uint counter = 0;
foreach (var row in reader)
{
    counter++;
    uint id = uint.Parse(row[0].Span);
    string name = row[1].ToString();

    HotfixRecord record = new HotfixRecord();
    record.TableHash = DB2Hash.SpellName;
    record.HotfixId  = HotfixSpellNameBegin + counter;
    record.UniqueId  = record.HotfixId;
    record.RecordId  = id;
    record.Status    = HotfixStatus.Valid;
    record.HotfixContent.WriteCString(name);
    Hotfixes[record.HotfixId] = record;
}
```

三件要記住的事：

1. **`HasHeader = true` + `row[0]` / `row[1]` 是位置索引** —— **header 的欄名完全不影響解析，只有欄序重要。**
2. `WriteCString` 在 `Framework/IO/ByteBuffer.cs:539` 用的是 **`Encoding.UTF8`**。中文字串直接就是 UTF-8 下線。
3. `HotfixId = Begin + counter`（CSV 中的位置），**不是 `Begin + id`**。這一點在 §5.2 會變成一個必須注意的坑。

`LoadSpellHotfixes()`（2416 行）同理，寫三個 `WriteCString`：`NameSubText`、`Description`、`AuraDescription`。

### 1.3 三個封包與一個 filter

`HermesProxy/World/Server/Packets/HotfixPackets.cs`：

| 類別 | opcode | 內容 |
|---|---|---|
| `AvailableHotfixes` | `SMSG_AVAILABLE_HOTFIXES` | `VirtualRealmAddress` + count + **每列 8 bytes**（`HotfixId`, `UniqueId`） |
| `HotfixRequest`（讀） | `CMSG_HOTFIX_REQUEST` | `ClientBuild`, `DataBuild`, count + N × uint32 id |
| `HotfixConnect` | `SMSG_HOTFIX_CONNECT` | count + N × **21 bytes header**（HotfixId/UniqueId/TableHash/RecordId/Size + 3 bits status flush）+ 串接的 body |
| `HotFixMessage` | `SMSG_HOTFIX_MESSAGE` | 與 `HotfixConnect` **格式完全相同**，但可在 session 中隨時推送 |

`HotfixRecord.cs:21-28` 的註解解釋了 cache 機制（**這段是本題最有用的一段註解**）：

> "`UniqueID` is the V3_4_3 client's cache validator — when it matches the value the client has stored in `Cache/WDB/HotfixCache.bin` for this PushID, the client trusts its cached body and skips re-requesting via `CMSG_HOTFIX_REQUEST`."

（**路徑有出入**：`bf717dc4` 的 commit message 寫的是 `Cache/ADB/<locale>/DBCache.bin`，而本機實測 `~/World of Warcraft 3.4.3.54261/_classic_/Cache/` 底下確實有 `ADB/enUS/`（空的，因為還沒登入過）與 `WDB/enUS/*.wdb`。**以本機檔案系統為準：hotfix cache 在 `Cache/ADB/<locale>/`，`WDB/` 是 query cache。** 原始碼註解那一行是舊的。）

`HotfixHandler.cs`：
- `HandleDbQueryBulk`（16 行）—— 只對 `TactKey`（回 `NotPublic`）、`BroadcastText`、`Item`、`ItemSparse` 有實作，**其他所有 TableHash 一律回 `Status = Invalid`**。
- `HandleHotfixRequest`（124 行）—— 對 client 送來的每個 id 查 `GameData.Hotfixes`，命中的塞進**一個** `HotfixConnect` 送出，並印出 `[Hotfix] Sending SMSG_HOTFIX_CONNECT: matched=X/Y`。**這行 log 就是實驗的主要儀表。**

**一個很重要的推論（本人判斷）：`CMSG_DB_QUERY_BULK` 這條 lazy 路徑對「覆寫」是沒用的。** client 只會去 query 它**自己沒有**的列；`SpellName` 的 49,357 列 client 全都有（英文版）。所以**要覆寫就一定得走 advertise → request → connect 這條，一定得改 `TableFilter`**。丟 CSV 而不改 `TableFilter` 等於什麼都沒做 —— 這一點 `bf717dc4` 的 commit message 已經替我們證實過一次了（見 §2.2）。

---

## 2. ★ `TableFilter` 為什麼只有 `AreaTrigger`

這是整份任務最重要的一題。答案是**「目前只需要這一張」**，不是「其他都會壞」。三段獨立證據。

### 2.1 現行程式碼與其註解（`WorldSocket.cs:1290-1310`）

```csharp
public void SendAvailableHotfixes()
{
    AvailableHotfixes hotfixes = new AvailableHotfixes();
    hotfixes.VirtualRealmAddress = GetSession().RealmId.GetAddress();
    // V3_4_3: advertise only tables where we actually override the client's own data.
    // Hotfixes are an override channel — a record identical to the baked-in DB2 costs a
    // round trip and changes nothing.
    //
    // ChrCustomizationChoice (1064 rows) and ChrCustomizationOption (190) used to be
    // advertised here. Both were verified byte-identical to the client's 3.4.3.54261
    // DB2s (1064/1064 and 190/190, zero differing, zero new), i.e. 1254 wasted records
    // per login. Neither store is read anywhere else in the proxy.
    if (ModernVersion.Build == ClientVersionBuild.V3_4_3_54261)
    {
        hotfixes.TableFilter = new HashSet<DB2Hash>
        {
            DB2Hash.AreaTrigger,
        };
    }
    SendPacket(hotfixes);
}
```

理由字面就是**「只 advertise 我們真的有覆寫的表」**。移除 `ChrCustomization*` 的理由是**它們是 mirror（與 client 資料逐位元相同）**。

### 2.2 縮成 `AreaTrigger` 的那個 commit（`81ccf066`，2026-08-28）

commit message 全文的重點（`gh api` 實測取得）：

> "Hotfixes are an override channel: the client only needs rows that differ from its baked-in DB2, or that do not exist in it. Everything else costs a round trip and changes nothing.
>
> ChrCustomizationChoice: 1064 compared, 1064 identical, 0 differing, 0 new
> ChrCustomizationOption:  190 compared,  190 identical, 0 differing, 0 new
>
> Dropping both from the advertised set takes the login from 1256 hotfix ids down to 4 …
>
> before: `[Hotfix] CMSG_HOTFIX_REQUEST: client requested 1256 hotfix IDs`
> after:  `[Hotfix] CMSG_HOTFIX_REQUEST: client requested 4 hotfix IDs`
>
> Verified on AzerothCore with `-ClearCache`, so nothing was served from a stale `Cache/ADB DBCache.bin`"

**這裡沒有一個字提到相容性、崩潰、或 client 拒絕。純粹是「1254 筆是白費的」。** 順帶得到兩個實驗用的細節：**`-ClearCache` 這個 client 啟動旗標**，以及 **advertise 的 store 當時有 600,211 筆記錄**。

### 2.3 加入 `AreaTrigger` 的那個 commit（`bf717dc4`，同日）—— 決定性

> "**The client will honour hotfixed AreaTrigger rows. It simply never received any:** `SendAvailableHotfixes` advertised only the ChrCustomization tables, so although GameData loaded the AreaTrigger records the client was never told they existed and never requested them. **Advertising `DB2Hash.AreaTrigger` is the whole unlock** — the client then validates every row (confirmed in the client's own `Logs/Hotfix.log`: `"Table AreaTrigger ... VALIDATION_RESULT_VALID"`).
>
> Push ids must be stable across sessions. `SMSG_AVAILABLE_HOTFIXES` carries only a list of ids; the client diffs it against `Cache/ADB/<locale>/DBCache.bin` and re-requests just what it lacks. …
>
> `AreaTrigger3.csv` now ships 4 override rows instead of a 1155-row mirror of data the client already has: **452 bytes rather than 123 KB per login**."

**三件事一次證完：**
1. 「advertise 是唯一的開關」—— 與 §1.3 的推論一致。
2. client **會驗證每一列並在自己的 log 記錄結果**（`VALIDATION_RESULT_VALID`）。
3. 這條路是**新增一張表到 `TableFilter` 就通**的量級 —— 就是本篇實驗計畫的第一步。

### 2.4 而且 `AreaTrigger3.csv` 覆寫的正是「既有列」

`AreaTrigger3.csv` 第一列的 `Comment` 欄（檔案內實測）：

```
4356 ... "Dark Portal Outland->BL. Existing client row relocated onto legacy 4352's DBC box; AreaTriggerReconciliation remaps 4356->4352."
```

**「Existing client row relocated」**—— 這正是任務要求區分的那件事：**覆寫既有列 ≠ 新增列，而覆寫既有列在 3.4.3 上已經跑過了。**

---

## 3. ★ 「~5 MB parse-abort」的真相

前一篇引用的是 `HotfixPackets.cs:77-81` 的註解：

> "Shipping the full ~600k Item/Spell index produces a ~5 MB packet the client never even logs ('ClientAvailableHotfixes' line missing), suggesting a parse-abort."

追 git 歷史（`git log -S "parse-abort"`）後，這句話的來歷完全改變了它的份量。

### 3.1 時間線（全部第一手 commit）

| 時間 | commit | 發生什麼 |
|---|---|---|
| 2026-04-26 | `6b2fe8c2` | 從 wago.tools 灌進 ~700K 筆真實 WotLK hotfix 資料 |
| 2026-05-01 **17:45** | `281001d` | 全量 advertise 失敗。當時的程式碼註解（已被後續改掉）寫的是：「V3_4_3 ships ~700k real WotLK hotfix records; enumerating them all in `SMSG_AVAILABLE_HOTFIXES` yields a **multi-MB packet that stalls the client at the glue-screen loading bar**」。於是引入 `TableFilter`，並寫下那句 ~5 MB / parse-abort。 |
| 2026-05-01 **17:46** | `8f49b45` | **一分鐘後，找到真因。** |

`8f49b45` 對 `WorldSocket.cs` 的 diff（實測）：

```diff
-            if (packetSize > 0x400 && _worldCrypt.IsInitialized)
+            // V3_4_3 has no SMSG_COMPRESSED_PACKET opcode mapping (only
+            // SMSG_COMPRESSED_UPDATE_OBJECT exists), so wrapping a >1KB packet via
+            // SMSG_COMPRESSED_PACKET produces an opcode-zero packet the client silently
+            // drops. Skip per-packet compression for V3_4_3; let the raw packet go out.
+            // Confirmed via WoW's own Hotfix.log: 14KB SMSG_AVAILABLE_HOTFIXES never
+            // resulted in a "ClientAvailableHotfixes" log entry while a smaller (<1KB)
+            // count=0 version of the same opcode always logged it.
+            ushort compressedOpcode = (ushort)ModernVersion.GetCurrentOpcode(Opcode.SMSG_COMPRESSED_PACKET);
+            if (packetSize > 0x400 && _worldCrypt.IsInitialized && compressedOpcode != 0)
```

同一個 commit 裡 `SendAvailableHotfixes` 的註解也一起改成：

```diff
-        // V3_4_3 ships ~700k real WotLK hotfix records; enumerating them all in
-        // SMSG_AVAILABLE_HOTFIXES yields a multi-MB packet that stalls the client
-        // at the glue-screen loading bar (character preview never renders). Suppress
-        // the record list ...
+        // V3_4_3: ship the char-customization tables. Filtered scope keeps the index
+        // around 14 KB (vs 5 MB for full 600k records) — and now that compression is
+        // disabled for V3_4_3 (no SMSG_COMPRESSED_PACKET mapping), the raw packet
+        // actually reaches the client.
```

### 3.2 這代表什麼

> **「client 收不到大封包」的已證實原因是 opcode-0 的壓縮 bug，不是 hotfix 索引的大小。** 那個 bug 影響的是**任何** >1 KB 的 SMSG，只是先被 14 KB 的 `SMSG_AVAILABLE_HOTFIXES` 撞到。修掉之後 14 KB 立刻就通了。
>
> **~5 MB 這個數字，是在壓縮 bug 還在的時候量的，之後從未重測。上限從來沒有被精確量過。** `HotfixPackets.cs` 今天那句註解是 `81ccf066` 從舊註解**搬過來的文字**，不是新的觀察。

**這把「封包大小」從「已驗證的阻礙」降級成「未驗證的疑慮」。** 但不能因此就說沒問題 —— 5 MB 級的單一封包仍然是未知領域，而且 §6 的估算顯示全量 `Spell` 就會撞到那個量級。

### 3.3 分批／分頁在結構上做得到嗎？—— 做得到，而且有兩條路

1. **`SMSG_HOTFIX_CONNECT` 可以拆多包（proxy 側改幾行）。** `HandleHotfixRequest` 現在是把所有 matched 塞進一個 `HotfixConnect`。封包格式是自描述的（count + 記錄 + totalDataSize + body），拆成 N 個各帶自己 count 的封包在**寫入端沒有任何障礙**。**client 是否接受多個 `SMSG_HOTFIX_CONNECT` —— 未驗證。**
2. **`SMSG_HOTFIX_MESSAGE` 是現成的、已驗證的漸進推送通道。** 格式與 `HotfixConnect` 完全相同，而 proxy **已經在用它**：`GameData.GenerateItemUpdateIfNeeded` / `GenerateItemSparseUpdateIfNeeded` / `GenerateItemEffectUpdateIfNeeded` 在遊戲中隨時單筆推送 Item 系 hotfix，且 `wotlk.md` 的「Hotfix data」在三個後端都是 ✅。**→ client 接受 session 中途、小批次的 hotfix，這件事在 3.4.3 上已經是實證。**

**另外，`CMSG_HOTFIX_REQUEST` 的方向本來就是 client 自己決定要哪些。** 而 TrinityCore master 自己的 `WorldSocket.cpp:348` 給了一個很有份量的旁證 —— 它**特別為這個 opcode 放寬封包上限到 1 MB**：

```cpp
// CMSG_HOTFIX_REQUEST can be much larger than normal packets, allow receiving it once per session
if (header->EncryptedOpcode != CMSG_HOTFIX_REQUEST || header->Size > 0x100000 || !_canRequestHotfixes)
```

1 MB / 4 bytes ≈ **26 萬個 id**。→ **「client 一次要求十萬筆等級的 hotfix」在 Blizzard 的協定設計裡是正常狀況，不是異常。** HermesProxy 這邊也已經處理好了（`WorldSocket.cs:351` 對 `CMSG_HOTFIX_REQUEST` 豁免 `IsValidSize()` 的 0x40000 上限）。

---

## 4. 字串 loader 到底存不存在？

### 4.1 已經存在、可直接用的（無需寫程式）

| DB2 表 | loader | 寫出的字串欄 | wago zhTW 欄序 | 相容？ |
|---|---|---|---|---|
| **`SpellName`** | `LoadSpellNameHotfixes()` `GameData.cs:2451` | `Name` | `ID,Name_lang` | ✅ **逐欄相同，零轉換** |
| **`Spell`** | `LoadSpellHotfixes()` `GameData.cs:2416` | `NameSubText`, `Description`, `AuraDescription` | `ID,NameSubtext_lang,Description_lang,AuraDescription_lang` | ✅ **逐欄相同，零轉換** |
| `SkillLine` | `LoadSkillLineHotfixes()` `GameData.cs:2251` | `DisplayName`, `AlternateVerb`, `Description`, `HordeDisplayName`, `NeutralDisplayName` | `DisplayName_lang,AlternateVerb_lang,Description_lang,HordeDisplayName_lang,NeutralDisplayName,ID,CategoryID,...` | ✅ 逐欄相同（loader 之後讀 8 個數值欄，順序也對） |
| `AreaTrigger` | `LoadAreaTriggerHotfixes()` `GameData.cs:2172` | `Message` | — | ✅（但 WotLK 的 `Message_lang` 全空，無翻譯價值） |

**`SpellName` 與 `Spell` 是「純字串表」** —— 整張表除了 ID 之外只有字串欄。這是為什麼它們可以零轉換：hotfix 的 record body 必須**照 client DB2 的欄位順序寫完整列**，而這兩張表的「完整列」就是那幾個字串。

**`wotlk.md:469` 也獨立佐證了欄序這件事：**

> "Per-loader column projections were tightened during that regen — **5 of 18 tables** (`SpellMisc`, `ItemSparse`, `Item`, `ItemDisplayInfo`, `CreatureDisplayInfo`) need explicit reorder + drop of wago-only columns; **the other 13 match wago's column order verbatim**."

### 4.2 需要新寫 loader 的

| 目標 | 表 | 為什麼要新寫 | 工作量（本人判斷） |
|---|---|---|---|
| 成就名稱／敘述 | `Achievement` | 無 loader；15 欄裡只有 3 個字串（`Description_lang`, `Title_lang`, `Reward_lang`），其餘 12 個數值欄必須照序寫 | 中（照 `LoadSkillLineHotfixes` 抄一份） |
| 區域名 | `AreaTable` | 無 loader；28 欄，1 個字串（`AreaName_lang`），另有 `ZoneName`（內部代號，**不是** `_lang`） | 中偏高（欄多、含 float 與陣列欄） |
| 地圖／副本名 | `Map` | 無 loader；25 欄，5 個字串 | 中 |
| 職業／種族／陣營 | `ChrClasses` / `ChrRaces` / `Faction` | 無 loader | 中 |
| **天賦** | `Talent` | **不需要做** —— 見下 |

**★ 天賦這一格是好消息。** wago 的 `Talent?build=3.4.3.54261&locale=zhTW` 實測：892 列，**`Description_lang` 欄全部是空字串**。WotLK 的天賦名稱與敘述實際來自 `SpellRank_0..8` 指向的法術。→ **`SpellName` + `Spell` 做完，天賦樹自動變中文，不必碰 `Talent`。**

同理，**雕紋敘述**也走 `GlyphProperties.SpellID` → `Spell.Description_lang`，一併吃到。

---

## 5. client 端的 hotfix 行為

### 5.1 覆寫既有列的語意 —— 已確認（兩個獨立來源）

**來源一（社群 wiki，非官方）**：`wowdev.wiki/DBCache.bin` 的 `dbcache_entry_v7` 的 `RecordState` enum：

```c
enum RecordState
{
    Valid     = 1, // has data, overwrites source record (if exists)
    Delete    = 2, // no data, deletes source record (if exists)
    Invalid   = 3, // no data, deletes previous hotfixes, restoring source record (if exists)
    NotPublic = 4, // Added in 9.1.0.38394, no data
};
```

**「`Valid = 1`：有資料，覆寫來源列（若存在）」** —— 這正是本地化需要的語意，而且 `HotfixStatus.Valid` 就是 HermesProxy 每個 loader 都在設的值。

**來源二（HermesProxy 的實作經驗，第一手）**：`wotlk.md:310`

> "`Item*` hotfix RecordIDs **must align with the V3_4_3.54261 baked-in DBC slot** or the client stores the row but doesn't re-route the tooltip 'Use:' line through it. … so the wire packet becomes an **UPDATE (re-read)** instead of a **stranded INSERT**."

→ **維護者自己把「對齊既有 RecordID = UPDATE」與「不對齊 = 孤立的 INSERT」分得清清楚楚，而且是為了讓 UPDATE 生效才特地做對齊。** 對本地化來說這反而是最容易的情境：我們用的 RecordID 就是 wago 從**同一個 build 的 DB2** 匯出的 ID，天生對齊。

### 5.2 client 怎麼要、怎麼快取、怎麼驗證

```
登入 → proxy: SMSG_AVAILABLE_HOTFIXES  (只有 id 清單，每筆 8 bytes)
     → client 拿清單去 diff  Cache/ADB/<locale>/DBCache.bin
     → client: CMSG_HOTFIX_REQUEST     (只要它沒有的那些 id)
     → proxy: SMSG_HOTFIX_CONNECT      (21 bytes/列 + body)
     → client 逐列驗證，結果寫進 Logs/Hotfix.log（VALIDATION_RESULT_VALID / _INVALID）
     → 寫回 Cache/ADB/<locale>/DBCache.bin，下次登入 0 request
```

**本機實測佐證（唯讀）：**
- `~/World of Warcraft 3.4.3.54261/_classic_/Cache/ADB/enUS/` **存在但是空的**（client 啟動過但沒登入）→ 確認 hotfix cache 路徑**帶 locale 目錄**。
- `_classic_/Logs/Hotfix.log` 存在（目前只有 `---- Startup ----` / `---- Shutdown ----` 兩行）。
- `WTF/Config.wtf` 裡有 `SET CACHE-WQST-QuestV2HotfixCount "0"`、`SET CACHE-WGOB-GameObjectsHotfixCount "0"` —— **client 自己在 config 裡逐 cache 記 hotfix 筆數**，也是一個可觀測的計數器。

**驗證 / 不匹配時會怎樣：**
- **驗證是逐列的**，結果進 `Hotfix.log`（`VALIDATION_RESULT_VALID` / `VALIDATION_RESULT_INVALID` 兩個字串都在 HermesProxy 的註解裡被引用過）。
- **`TableHash` 本身就是「欄位集合的 FNV hash」**（`HotfixRecord.cs:24` 的原文：「TableHash (a column-set FNV hash)」）。TrinityCore master 的 `DB2FileLoader.h:209` 顯示這個值是**從 DB2 檔頭讀出來的**，不是常數。HermesProxy 用的是硬寫的 enum（`SpellName = 0x46C66698`、`Spell = 0xE111669E`）。**TrinityCore 官方的 `TrinityCore/WowPacketParser` 的 `DB2Hash.cs` 有完全相同的值**（`gh api` 實測），而 WPP 正是 `wotlk.md` 用來解 3.4.3 封包的工具 —— **但「這些 hash 對 build 54261 也成立」仍屬未驗證，只能靠 `Hotfix.log` 的驗證結果現場確認。**
- **body 欄序／欄寬寫錯的後果是 client 側靜默錯亂**，不是拒絕。`wotlk.md` 記過一個更兇的例子：「Sending an ItemSparse hotfix for an item missing from the baked DBC **crashed the V3_4_3.54261 client (Error 132 ACCESS_VIOLATION at 0x0)**」。→ **只覆寫「client 一定有的列」是安全邊界，本地化剛好天生落在這個邊界內。**

### 5.3 一個必須處理的坑：push id 穩定性

`bf717dc4` 明確警告：

> "Push ids must be stable across sessions. … `LoadAreaTriggerHotfixes` keyed the id off the row's position in the CSV, so shipping a different subset silently re-keyed every record and defeated that diff. **Now derived from the record id.**"

**但 `LoadSpellNameHotfixes` / `LoadSpellHotfixes` 至今仍然是 `Begin + counter`（CSV 位置）。** 而它們**不能**照抄 `Begin + id` 的解法：實測 wago 的 `SpellName` / `Spell` **最大 ID 是 446,920**，遠超過 `HotfixXxxBegin` 之間 100,000 的間隔，直接用 id 會撞進隔壁表的區段。

**→ 兩個可行做法（皆需程式修改）：**
(a) **接受 counter**，但把 CSV 當成不可變的成品（固定排序、固定內容）—— 只要不換檔就穩定。這是成本最低的做法，實驗階段用這個。
(b) 為 `SpellName` / `Spell` 另配一段夠寬的 id 空間（例如 `10_000_000` / `11_000_000` 起、間隔 500,000）再用 `Begin + id`。長期正解。

**若忽略這一點的症狀：每次改 CSV 內容，全部 push id 重新編號，client 的 `DBCache.bin` 全部失效 → 每次登入都重下完整 payload。** 這不會壞，但會把「冷快取才有的大封包」變成「每次登入都有」。

---

## 6. wago.tools 作為資料來源（實測）

### 6.1 介面與授權

| 項目 | 實測結果 |
|---|---|
| 匯出 URL | `https://wago.tools/db2/{Table}/csv?build=3.4.3.54261&locale=zhTW` |
| 需要登入？ | **不需要**。頁面 props 的 `user` 為 `null`，直接 `curl` 即 200 |
| 有沒有 API？ | 有。路由表（從頁面自帶的 ziggy route 清單讀出）包含 `db2/{table}/csv`、`db2/{table}/diff`、`builds`、`hotfixes`、`files`。`https://wago.tools/api/builds` 回 200 / JSON（536 KB，含 `wow_classic` 的完整 build 歷史）。另有 `/apis` 頁但**內容是 JS 前端渲染的，無法在不跑瀏覽器的前提下讀到**（本次不使用瀏覽器自動化） |
| 格式 | RFC4180 CSV，UTF-8，含引號跳脫；**描述欄可能含內嵌換行** |
| locale 打錯會怎樣 | **靜默退回 enUS**（實測 `locale=xxYY` → `5,"Death Touch"`）。這是一個很容易誤判的陷阱 |
| 定位 | **第三方社群存檔，非 Blizzard 服務。** HermesProxy 自己就是這樣用的（`scripts/compare-hotfix-csv.py` 內建 `WAGO = "https://wago.tools/db2/{table}/csv?build={build}"`） |

### 6.2 3.4.3.54261 的 zhTW 匯出完整度（全部實測）

| 表 | 真實列數 | 字串欄 | 匯出 bytes |
|---|---|---|---|
| **`SpellName`** | **49,357** | `Name_lang` | 1,121,637 |
| **`Spell`** | **49,357**（**非** 53,071，見下） | `NameSubtext_lang`, `Description_lang`, `AuraDescription_lang` | 3,699,947 |
| `Achievement` | 1,912 | `Description_lang`, `Title_lang`, `Reward_lang` | 236,060 |
| `AreaTable` | 2,373 | `AreaName_lang` | 256,982 |
| `Map` | **130**（**非** 177） | `MapName_lang`, `MapDescription0/1_lang`, `PvpShort/LongDescription_lang` | 17,420 |
| `SkillLine` | 152 | 4 個 `_lang` | 10,318 |
| `Talent` | 892 | `Description_lang` **全空** | 63,370 |
| `SpellDescriptionVariables` | — | — | 2,565（很小，未細查） |

> **修正 [zhtw-localization.md](./zhtw-localization.md) §1.2 的兩個數字。** 該表的 `Spell` 53,071 與 `Map` 177 是 `wc -l` 的原始行數。用 Python `csv` 模組正確解析後：`Spell` 是 **49,357 列**，其中 **2,013 列的描述欄含內嵌換行**；`Map` 是 **130 列**，7 列含換行。`SpellName`（49,357）與 `AreaTable`（2,373）兩項原數字正確。

抽樣驗證（實測，確實是繁中而非簡中）：`SpellName` id 5 = `死亡之觸`（zhCN 版是 `死亡之触`）；`AreaTable` id 1 = `丹莫洛`；`Map` id 30 = `奧特蘭克山谷`；`SkillLine` id 6 = `冰霜`。

### 6.3 需要多少轉換工作？

| 表 | 轉換工作 |
|---|---|
| **`SpellName`** | **零。** 存成 `HermesProxy/CSV/Hotfix/SpellName3.csv` 即可 |
| **`Spell`** | **零。** 存成 `Spell3.csv` 即可 |
| `SkillLine` | **零**（欄序相符） |
| `Achievement` / `AreaTable` / `Map` | 匯出本身不用改，但**要新寫 loader**（§4.2） |

**內嵌換行能不能吃？** loader 用的是 `Sep` 0.12.2（`Directory.Packages.props:15`）。Sep 的 README 明寫「**Sep has to track line endings inside quotes**」→ 支援引號內換行。**但這條沒有在 HermesProxy 上實測過**（現行所有 hotfix CSV 都沒有內嵌換行）—— **列為實驗中要盯的第一個解析風險。**

### 6.4 封包大小估算（依 §1.3 的線材格式實算）

| 表 | 列數 | 字串 bytes | `SMSG_AVAILABLE_HOTFIXES` 增量（8 B/列） | `SMSG_HOTFIX_CONNECT` 冷快取總量（21 B/列 + body） |
|---|---|---|---|---|
| `SpellName` | 49,357 | 0.78 MB | **386 KB** | **≈ 1.77 MB** |
| `Spell` | 49,357 | 3.23 MB | **386 KB** | **≈ 4.22 MB** |
| `Achievement` | 1,912 | 0.15 MB | 15 KB | ≈ 0.18 MB |
| `AreaTable` | 2,373 | 0.03 MB | 19 KB | ≈ 0.08 MB |
| `Map` | 130 | 0.01 MB | 1 KB | ≈ 0.01 MB |
| `SkillLine` | 152 | ~0.01 MB | 1 KB | ≈ 0.01 MB |

**讀法：**
- **advertise 側完全不是問題。** 兩張大表加起來 772 KB，離舊觀察的 5 MB 差一個數量級，而且已知 14 KB 可通、5 MB 的失敗又已被歸因到壓縮 bug。
- **`SMSG_HOTFIX_CONNECT` 才是壓力點，而且只在冷快取（第一次登入 / `-ClearCache`）時發生。** `Spell` 全表 ≈ 4.2 MB 的單一封包，正好落在那個從未複測過的 5 MB 級。
- **`SpellName` 單獨上（1.77 MB）是風險最低、資訊量最高的第一發。**

---

## 7. 裁決與分階段實驗計畫

### 7.1 裁決

> ## **可行（viable）。**
>
> 三個候選阻礙逐一結案：
>
> | 阻礙 | 狀態 | 依據 |
> |---|---|---|
> | **`TableFilter`** | **不是阻礙。** 是「目前只需要一張表」的效能修剪，改一行 enum 即可 | `81ccf066` / `bf717dc4` commit message（§2） |
> | **覆寫語意** | **不是阻礙。** `RecordState::Valid = 1` 明文「overwrites source record」；`AreaTrigger` 覆寫既有列已在 3.4.3 實證 | wowdev.wiki（社群）+ `AreaTrigger3.csv` + `wotlk.md:310`（§5.1） |
> | **封包大小** | **唯一還活著的風險，但已從「已驗證的阻礙」降級為「未量測的疑慮」。** 5 MB 那次失敗的已證實真因是壓縮 bug，修好後從未重測 | `8f49b45` diff（§3） |
>
> **但這仍然是一個實驗，不是一條照著走的路。** 沒有任何人跑過 3.4.3 的字串 hotfix，`SpellName` / `Spell` 的 `TableHash` 對 build 54261 是否正確也只有間接證據。**分階段做，每一階段都有明確的成功／失敗判準。**

### 7.2 儀表（每一階段都看這五個）

| # | 觀測點 | 在哪 |
|---|---|---|
| 1 | `[Hotfix] CMSG_HOTFIX_REQUEST: client requested N hotfix IDs` | proxy log（`HotfixHandler.cs:127`） |
| 2 | `[Hotfix] Sending SMSG_HOTFIX_CONNECT: matched=X/Y` | proxy log（`HotfixHandler.cs:143`） |
| 3 | `Table SpellName ... VALIDATION_RESULT_VALID` / `_INVALID` | **client 的 `_classic_/Logs/Hotfix.log`** |
| 4 | `Cache/ADB/enUS/DBCache.bin` 有沒有生出來、多大 | 檔案系統 |
| 5 | 遊戲內：法術書 / 動作條 tooltip 是不是中文 | 眼睛 |

**每次實驗都要用 `-ClearCache` 啟動 client**（`81ccf066` 用的就是這個），否則會被上一輪的 `DBCache.bin` 騙。

### 7.3 階段計畫

---

#### **Stage 0 — 30 秒：確認字型（先做，因為它能一票否決後面全部）**

進遊戲，在聊天輸入框打幾個中文字。

- ✅ 顯示中文 → 繼續。（`_classic_/Fonts/615974.slug` = `ARKai_T`，33 MB 繁中字型已在，見 [zhtw-localization.md](./zhtw-localization.md) §4.4）
- ❌ 顯示方塊 → **整條路歸零**，先解字型再說。

---

#### **Stage 1 — 最小可證偽實驗：10 列 `SpellName`**

**做什麼：**
1. `curl "https://wago.tools/db2/SpellName/csv?build=3.4.3.54261&locale=zhTW"`，**只留 10 列**：自己職業最常用的、動作條上看得到的法術（例如戰士 `Heroic Strike` 78 / `Charge` 100 / `Battle Shout` 6673）。保留 header。存成 `HermesProxy/CSV/Hotfix/SpellName3.csv`。
2. `WorldSocket.cs:1304` 的 `TableFilter` 加一行 `DB2Hash.SpellName,`。
3. `dotnet publish`，`-ClearCache` 啟動 client，登入。

**成功長什麼樣：**
- log 1 顯示 `requested 14 hotfix IDs`（10 + AreaTrigger 的 4）。
- log 2 顯示 `matched=14/14`。
- **`Hotfix.log` 出現 `Table SpellName ... VALIDATION_RESULT_VALID`。**
- **動作條上那 10 個法術的名字變成中文。**

**失敗長什麼樣，以及各代表什麼：**

| 症狀 | 最可能的原因 | 下一步 |
|---|---|---|
| `requested 4`（沒變多） | advertise 沒送出去 / `TableFilter` 沒生效 / CSV 沒被複製到輸出目錄 | 檢查 `.csproj` 的 `<Content Include="CSV\Hotfix\*.*">` 有沒有把新檔複製過去 |
| `matched=14/14` 但 `Hotfix.log` 是 `VALIDATION_RESULT_INVALID` | **`DB2Hash.SpellName` 對 54261 不成立，或 record body 佈局不符** | 這是最有價值的失敗。先確認 hash（可拿 `SkillLine` 這種小表交叉測），再確認 body 是否應該只有那一個字串 |
| 名字仍是英文，但驗證 VALID | 覆寫進了 store 但 UI 沒重讀 | 重登 / 換角色測；也可能真的是 INSERT 而非 UPDATE（RecordId 對齊問題） |
| client 崩潰 | 佈局錯誤（參考 `wotlk.md` 的 Error 132 前例） | 立刻回退，改用更小的子集（1 列）定位 |

**代價：刪掉一個檔 + 還原一行程式碼就完全復原。**

---

#### **Stage 2 — 擴量到「一個職業」：數百列 `SpellName`**

從 wago 匯出裡挑自己職業的全部技能 + 常用消耗品 / 坐騎（數百到 ~2,000 列）。

- **要看的**：`SMSG_AVAILABLE_HOTFIXES` 從 ~112 bytes 長到 ~16 KB（正好跨過那個「14 KB 已知可通」的門檻），`SMSG_HOTFIX_CONNECT` 到數十 KB。
- **成功判準**：法術書、天賦樹的技能名、動作條全中文；第二次登入（暖快取）`requested 0`。
- **順便驗證 push id 穩定性**：第二次登入若 `requested` 不是 0，代表 §5.2 的 counter 問題已經在咬人。

---

#### **Stage 3 — 全量 `SpellName`（49,357 列）**

這一步才真正測試大小。advertise +386 KB，冷快取 connect ≈ 1.77 MB。

- **成功判準**：所有法術名（含 NPC 技能、boss 技能、buff）中文；暖快取登入 0 request。
- **失敗判準**：client 卡在 glue screen / loading bar（就是 `281001d` 描述的那個症狀），或 `Hotfix.log` 完全沒有 `ClientAvailableHotfixes` 那一行。
- **如果失敗** → 這才是「大小上限」第一次被真正量到。做二分搜尋（25k → 12k → …）找出實際門檻，**這個數字本身就是值得回報給上游的成果**。
- **同時，備援方案已經現成**：改走 `SMSG_HOTFIX_MESSAGE` 分批推送（§3.3），這條通道 proxy 已經在用而且已驗證。

---

#### **Stage 4 — `Spell`（tooltip 全文）**

`Spell3.csv` 直接丟。冷快取 connect ≈ 4.2 MB —— **最可能踩到大小問題的一步，所以排在最後。**

- **獨立的新風險**：這是第一次讓 hotfix CSV 帶內嵌換行（2,013 列），Sep 的多行引號解析在 HermesProxy 上是第一次跑（§6.3）。
- **拿到的東西最多**：法術描述、buff/debuff 描述、**天賦樹全部的敘述文字**、雕紋敘述。
- 若太大 → 只放「有描述且玩家會看的」子集（過濾掉三個字串欄全空的列可以砍掉不少）。

---

#### **Stage 5 —（選做）新 loader：`Achievement` / `AreaTable` / `Map` / `SkillLine`**

`SkillLine` 零成本（loader 已存在，152 列），**應該和 Stage 2 一起做掉**。
其餘三張要寫新 loader，照 `LoadSkillLineHotfixes` 的樣子抄，每張約 30–60 行。三張加起來 < 0.3 MB，大小完全不是問題 —— **成本在寫 code 與對欄序，不在協定。**

---

## 8. 天花板：跑完之後哪些變中文、哪些不會

### 8.1 會變中文（累計，含前一篇的伺服器端成果）

| 類別 | 來源 | 階段 |
|---|---|---|
| 任務全文、NPC 名字與對話、物品名稱與敘述、書頁、對話選項、boss 台詞 | 3.3.5a `*_locale` 表 | [zhtw-localization.md](./zhtw-localization.md) §3（已知可行） |
| **法術／技能名稱**（法術書、動作條、戰鬥訊息、buff 條） | `SpellName` hotfix | Stage 1–3 |
| **法術描述 / tooltip / aura 敘述** | `Spell` hotfix | Stage 4 |
| **天賦樹的名稱與敘述** | 走 `Talent.SpellRank_N` → `SpellName`/`Spell`，**免費附帶** | Stage 3–4 |
| **雕紋敘述** | 走 `GlyphProperties.SpellID` → `Spell`，**免費附帶** | Stage 4 |
| 技能線名稱（採礦、鍛造、火焰、冰霜…） | `SkillLine` hotfix（loader 已存在） | Stage 2/5 |
| 成就名稱與敘述 | `Achievement`（需新 loader） | Stage 5 |
| 區域名、地圖名、副本名 | `AreaTable` / `Map`（需新 loader） | Stage 5 |
| 職業／種族／陣營名 | `ChrClasses` / `ChrRaces` / `Faction`（需新 loader） | Stage 5 |

### 8.2 不會變中文 —— **確認**

**所有 UI 框架字串**：按鈕文字、面板標題、系統錯誤訊息、屬性名（`AGILITY` / `STRENGTH`）、選項介面、`GlobalStrings` 全部 —— **永遠是英文。**

三項證據：
1. 它們是 **Lua，不是 DB2**（`Interface/FrameXML/GlobalStrings.lua` 之類），hotfix 通道只運送 DB2 記錄。
2. **本機實測**：`~/World of Warcraft 3.4.3.54261/_classic_/Interface/` 底下**只有 `AddOns/`**，沒有任何 loose 的 FrameXML —— UI Lua 全在 CASC 裡，而且是 locale-tagged（[zhtw-localization.md](./zhtw-localization.md) §2.3：mask 沒對上的 block 根本不會進 file tree）。
3. CASC 沒有第三方寫入路徑（同篇 §2.5）。

**唯一的理論路徑**是寫一個 addon 在 runtime 覆寫 `_G` 裡的 `GlobalStrings`（`AGILITY = "敏捷"`）。這是行之有年的 addon 技巧，但 **(a) 本文未驗證它在 3.4.3 上的行為，(b) `wotlk.md` 對 addon 相容性完全沒有記載，(c) 找不到現成的 zhTW 專案。** 三重未驗證。

### 8.3 一句話

> **跑完 Stage 1–4，你會得到一個「除了 UI 按鈕與面板標題之外，幾乎全部是繁體中文」的 WotLK。**
> 這比前一篇筆記的天花板（「劇情與世界看得懂、系統介面英文」）**高出一整個層級** —— 法術、天賦、tooltip 是 WotLK 玩家盯著看最久的東西，而它們現在在射程之內。
> 真正打不到的只剩「按鈕上的字」。

---

## 9. 明確記錄「未驗證」

- **未驗證**：`DB2Hash.SpellName = 0x46C66698` / `Spell = 0xE111669E` 對 build **54261** 是否正確。間接證據強（`TrinityCore/WowPacketParser` 有相同值，且該 parser 就是 `wotlk.md` 用來解 3.4.3 封包的工具），但 `TableHash` 在 TrinityCore 是**從 DB2 檔頭讀出來的**（`DB2FileLoader.h:209`），理論上可隨 build 改變。**Stage 1 的 `Hotfix.log` 就是這一項的檢驗。**
- **未驗證**：`SpellName` 的 hotfix record body 是否真的「只有一個字串」（loader 是這樣寫的，但那是為 Classic Era 寫的，3.4.3 從未跑過）。
- **未驗證**：`SMSG_AVAILABLE_HOTFIXES` / `SMSG_HOTFIX_CONNECT` 的實際大小上限。**已知 14 KB 可通、~5 MB 曾失敗但真因是壓縮 bug、修好後未重測。**
- **未驗證**：client 是否接受**多個** `SMSG_HOTFIX_CONNECT`（分頁）。`SMSG_HOTFIX_MESSAGE` 的多次推送則已驗證可行（Item 系）。
- **未驗證**：Sep 0.12.2 在 HermesProxy 的 loader 路徑上處理**引號內換行**的實際行為（README 宣稱支援）。
- **未驗證**：3.4.3 client 對 UTF-8 中文 hotfix 字串的渲染（字型在，但沒實際跑過）。
- **未驗證**：`Achievement` / `AreaTable` / `Map` 的完整欄位佈局是否與 wago 匯出的欄序一致（`wotlk.md` 說 18 張裡有 13 張一致，但這三張不在那 18 張裡）。
- **未驗證**：暖快取（`DBCache.bin` 命中）在字串 hotfix 上是否與 AreaTrigger 一樣正常運作。
- **未做**：沒有編譯或執行 HermesProxy 的任何版本；沒有實際送出任何 hotfix；沒有登入過遊戲。**本篇全部是原始碼與封包格式層級的分析。**
- **未做**：瀏覽器自動化。`wago.tools/apis` 頁的內容因此無法讀取。
- **未評估**：把 wago.tools 匯出的 Blizzard 遊戲文字重新散布的授權問題。**個人本機使用與公開再發布是兩回事。**

---

## 10. 驗證指令（可重跑，全部唯讀）

```bash
# ---- HermesProxy 原始碼與 git 歷史（本篇的骨幹）----
B=feature/wotlk-classic-v3.4.3
git clone --single-branch --branch $B https://github.com/Xian55/HermesProxy.git hp && cd hp

sed -n '1290,1310p' HermesProxy/World/Server/WorldSocket.cs      # TableFilter = { AreaTrigger }
sed -n '69,97p'     HermesProxy/World/Server/Packets/HotfixPackets.cs   # ~5 MB 註解
sed -n '1,44p'      HermesProxy/World/Objects/HotfixRecord.cs    # UniqueId = cache validator
sed -n '124,147p'   HermesProxy/World/Server/PacketHandlers/HotfixHandler.cs  # 兩行關鍵 log
sed -n '2416,2481p' HermesProxy/World/GameData.cs                # Spell / SpellName loader
sed -n '2106,2170p' HermesProxy/World/GameData.cs                # HotfixXxxBegin + LoadHotfixes
sed -n '583,594p'   HermesProxy/World/Server/WorldSocket.cs      # 壓縮 bug 的修正與註解
sed -n '345,357p'   HermesProxy/World/Server/WorldSocket.cs      # CMSG_HOTFIX_REQUEST 豁免大小檢查
head -50 scripts/compare-hotfix-csv.py                           # MIRROR vs POLYFILL 方法論

# ★ 三個決定性的 commit message
git log -1 --format=%B 81ccf066   # 為什麼縮成 AreaTrigger（byte-identical，不是壞掉）
git log -1 --format=%B bf717dc4   # "The client will honour hotfixed AreaTrigger rows"
git show 8f49b45 -- HermesProxy/World/Server/WorldSocket.cs | head -60   # 壓縮 bug 才是真因

git log --date=short --format="%ad %h %s" -S "parse-abort" -- HermesProxy/World/Server/
git log --date=short --format="%ad %h %s" -S "TableFilter" -- HermesProxy/World/Server/

ls -la HermesProxy/CSV/Hotfix/          # 29 個檔，9 個 *3.csv
for f in HermesProxy/CSV/Hotfix/*1.csv; do echo "== $f"; head -1 $f; done   # 字串 CSV 的 header

# ---- 本 repo（TrinityCore master，唯讀）----
sed -n '59,72p'   src/server/game/Handlers/HotfixHandler.cpp     # SendAvailableHotfixes（locale-aware）
sed -n '75,120p'  src/server/game/Handlers/HotfixHandler.cpp     # HandleHotfixRequest + WriteRecord(locale)
sed -n '336,360p' src/server/game/Server/WorldSocket.cpp         # CMSG_HOTFIX_REQUEST 上限 0x100000
grep -oE "CREATE TABLE \`(spell_name|talent|achievement|area_table|map|skill_line)(_locale)?\`" \
     sql/base/dev/hotfixes_database.sql | sort -u                # DB2 hotfix 的 locale 維度

# ---- 本機 client（唯讀）----
ls -la ~/'World of Warcraft 3.4.3.54261/_classic_/Cache/ADB/enUS'   # hotfix cache，帶 locale 目錄
cat    ~/'World of Warcraft 3.4.3.54261/_classic_/Logs/Hotfix.log'
grep -E 'CACHE-.*HotfixCount|textLocale' \
       ~/'World of Warcraft 3.4.3.54261/_classic_/WTF/Config.wtf'
ls     ~/'World of Warcraft 3.4.3.54261/_classic_/Interface'         # 只有 AddOns，沒有 FrameXML

# ---- wago.tools（實測）----
for t in SpellName Spell Talent Achievement AreaTable Map SkillLine; do
  curl -s "https://wago.tools/db2/$t/csv?build=3.4.3.54261&locale=zhTW" -o w_$t.csv
  echo "$t $(head -1 w_$t.csv)"
done
python3 -c "import csv;r=list(csv.reader(open('w_Spell.csv')));print(len(r)-1)"   # 49357，不是 53071
curl -s "https://wago.tools/db2/SpellName/csv?build=3.4.3.54261&locale=xxYY" | sed -n '5p'  # 靜默退回 enUS
curl -s "https://wago.tools/api/builds" | head -c 200

# ---- 交叉驗證 DB2 table hash ----
gh api "repos/TrinityCore/WowPacketParser/contents/WowPacketParser/Enums/DB2Hash.cs" \
  --jq '.content' | base64 -d | grep -E "0x46C66698|0xE111669E"
```

---

## 11. 實際取用過的來源

**`Xian55/HermesProxy@feature/wotlk-classic-v3.4.3`（第一手，tarball + 完整 git clone）**
- `HermesProxy/World/Server/WorldSocket.cs`（`SendAvailableHotfixes` 1290-1310、壓縮路徑 583-610、`ReadData` 330-357）
- `HermesProxy/World/Server/Packets/HotfixPackets.cs`（全文 164 行）
- `HermesProxy/World/Server/PacketHandlers/HotfixHandler.cs`（全文 147 行）
- `HermesProxy/World/Objects/HotfixRecord.cs`（全文 44 行）
- `HermesProxy/World/GameData.cs`（`LoadHotfixes` 2134、`HotfixXxxBegin` 2106-2127、`LoadSpellHotfixes` 2416、`LoadSpellNameHotfixes` 2451、`LoadSkillLineHotfixes` 2251、`LoadAreaTriggerHotfixes` 2172、`GenerateItemUpdateIfNeeded` 3889 等）
- `HermesProxy/World/Enums/DB2Hash.cs`（897 行）、`Framework/IO/ByteBuffer.cs:539`、`HermesProxy/World/Packet.cs:379`
- `HermesProxy/CSV/Hotfix/`（29 個檔的清單、大小、header、列數）、`HermesProxy/HermesProxy.csproj`、`Directory.Packages.props`
- `scripts/compare-hotfix-csv.py`（MIRROR / POLYFILL 方法論、wago URL 樣板、signedness 陷阱）
- `wotlk.md`（第 161、250、310、393、435、460-490 行）
- **commit：`81ccf066`、`bf717dc4`、`8f49b45`、`281001d`、`6b2fe8c2`、`76e91794` 的 message 與 diff**

**本 repo TrinityCore master（第一手）**
- `src/server/game/Handlers/HotfixHandler.cpp`（全文）
- `src/server/game/Server/WorldSocket.cpp:336-360`
- `src/server/game/DataStores/DB2Stores.cpp:1734-1800`、`src/common/DataStores/DB2FileLoader.h:209`、`src/server/shared/DataStores/DB2Store.h:40`
- `sql/base/dev/hotfixes_database.sql`（467 張表，含 `spell_name_locale` / `talent_locale` / `achievement_locale` / `area_table_locale` / `map_locale` / `skill_line_locale` / `chr_classes_locale` / `chr_races_locale` / `faction_locale`）

**`TrinityCore/WowPacketParser`（第一手，`gh api`）**
- `WowPacketParser/Enums/DB2Hash.cs`（交叉驗證 7 個 table hash）

**本機 client（第一手實測，唯讀）**
- `_classic_/Cache/ADB/enUS/`（空）、`_classic_/Cache/WDB/enUS/*.wdb`、`_classic_/Logs/Hotfix.log`、`_classic_/WTF/Config.wtf`、`_classic_/Interface/`、`_classic_/Fonts/`

**社群（明確標示非官方）**
- `https://wowdev.wiki/DBCache.bin` —— `RecordState` enum（`Valid = 1 // overwrites source record`）、WCH3-8 / DBCache.bin v1-v9 結構。**社群維護的 wiki，非 Blizzard 官方。** 直接 `curl` 被 Cloudflare 擋 403，加 UA header 後 200。
- `https://wago.tools/db2/{Table}/csv?build=3.4.3.54261&locale={zhTW,zhCN,koKR,xxYY}`、`https://wago.tools/api/builds`、`https://wago.tools/db2/SpellName`（ziggy 路由表）。**第三方社群存檔，非 Blizzard 服務。**
- `https://raw.githubusercontent.com/nietras/Sep/main/README.md` —— 引號內換行的支援聲明

**取用失敗**
- `https://wago.tools/apis` —— 內容由 JS 前端渲染，props 為空；本次不使用瀏覽器自動化，故未取得其 API 文件全文。
- `git clone --filter=blob:none` 對此 repo 失敗（promisor remote 取物件失敗），改用完整 clone。
