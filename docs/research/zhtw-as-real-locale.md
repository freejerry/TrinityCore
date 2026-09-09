# 把 zhTW 做成「真正可選的 locale」而非覆寫 enUS：可行性裁決

> ⚠️ **更正（2026-09-04）**
>
> 本篇「做不成客戶端認可的語系選項」的結論**仍然成立**（遊戲內 `GetAvailableLocales()` 實測只回傳三個已註冊語系），但逐層檢視時**漏了鬆散檔案覆蓋這一層**——美術與字型可經由該途徑達成，實際效果的天花板高於本篇估計。
>
> 詳見 [實作記錄與更正](./zhtw-implementation-and-corrections.md)。


> 撰寫日期：2026-09-04
> 相關筆記：[zhTW 中文化能做到哪裡](./zhtw-localization.md)（§2 的 CASC locale 機制、§2.5 的「MPQ 補丁無等價物」是本篇的起點；本篇把該結論從「找不到記載」升級為「從 client binary 與寫入端工具兩側交叉確認」）、[hotfix DB2 中文化深度評估](./hotfix-db2-localization.md)（本篇 §4 回答該篇沒問的一題：hotfix 通道**本身**有沒有 locale 維度）、[用 addon 中文化 UI 框架字串](./ui-localization-addon.md)（`GlobalStrings` 是 DB2 這件事讓本篇 §1.4 的清單少一層）、[macOS client 取得與執行](./macos-client-options.md)（§3.3 的 CDN 404 牆，本篇 §3.5 直接繼承並指出它是本題的死結）、[`wow-patcher` runtime mode 評估](./wow-patcher-runtime-mode.md)（binary patch 這條路的既有基礎設施）
> 前提（承接前述筆記，非假設）：Windows 版 WoW Classic **`3.4.3.54261`** 解壓在 `~/World of Warcraft 3.4.3.54261/`，`.build.info` 的 `Tags` 只有 `enUS` + `ruRU`，`WTF/Config.wtf` 是 `SET textLocale "enUS"`。後端是 TrinityCore `3.3.5` + `Xian55/HermesProxy`。目前的中文化做法是「用 DB2 hotfix 覆寫 enUS 列」，已在 client 上驗證可用。
> 來源限定 primary sources：**本機 client 二進位與檔案系統實測**（`WowClassic.exe` 的 243,049 條字串、`Data/config/` 的 build config、`.build.info`、`Cache/`、`Logs/`）、本 repo 的 `dep/CascLib` 原始碼與 TrinityCore master 原始碼（唯讀）、`gh api` 取得的各專案原始碼與 metadata、`wowdev.wiki`。
> **wowdev.wiki 為社群維護的 wiki，非 Blizzard 官方**，凡引用皆已標明。
> 未使用瀏覽器自動化。未編譯、未執行、未改動任何 client 檔案。凡未實測者一律標示「**未驗證**」。

---

## 0. TL;DR — 裁決先講

> ## **做不到。在這一份安裝上，「真正可選的 zhTW locale」不可行；覆寫 enUS 就是實務天花板。**

**決定性的那一層是 CASC 的「內容層」**——具體說是 **root manifest 裡 `LocaleFlags = 0x100`（zhTW）的那些 block，以及它們指向的 data archive 內容**。這一層在這份安裝上**從來沒有被下載過**（`.build.info` 的 tag 只有 enUS/ruRU），而唯一能補的來源是 Blizzard CDN 上這個 build 的 build config，**實測 404**。

不是「工具不夠」。剩下五層每一層都已經有第一手證據顯示它是可寫的或可繞的：

| 層 | 狀態 |
|---|---|
| `.build.info` 的 `Tags` 欄 | 純文字 CSV，可編輯 |
| install / download manifest 的 tag bitfield | **`wowdev/TACT.Net` 有完整的讀寫實作**（`InstallFile.SetTags()`、`TagEntry.Write()`） |
| root 的 per-locale block | **同上，`LocaleFlags.zhTW = 0x100` 在 `TACT.Net/SystemFiles/Root/LocaleFlags.cs` 逐位元與 CascLib 相同** |
| DB2 的 locale（是 header 的 `uint32 locale` 欄，每個 locale 一個檔） | `wowdev/DBCD` 有「experimental writing（WDC3 works）」 |
| 字型 | **本機已經有 `ARKai_T`（33 MB 繁中）**，且 `Fonts/` 是 loose 目錄，addon 已在用 `override_*.slug` |
| **zhTW 的實際檔案內容** | **❌ 沒有，且拿不到** |

**而且第二道獨立的鎖也在**：就算把內容湊出來，**這個 client 沒有任何已驗證的途徑接受一份本機自建的 CASC 容器**。CascLib 唯讀（本 repo 原始碼實證，見 §3.1）；唯一做過「讓 client 讀自建 CAS」的兩個專案，一個（`CASCHost`）最後 commit 在 **2018-06-13** 且它的第一步就是「從 Blizzard CDN 下載所需檔案」——**同一道 404 牆**；另一個（`CascOverride`）是 2017 年針對 32-bit Legion build 硬寫 offset 的 runtime binary patch，對 54261 完全無效。

**三個附帶的硬事實（全部本機 binary 實測，是本篇最有價值的新料）：**

1. **client 自己會驗 DB2 的 locale。** `WowClassic.exe` 內有格式字串 `Table %s has wrong locale (found %i, expected %i)`，與 `wrong table hash` / `wrong layout hash` / `wrong number of columns` 並列。→ **DB2 的 locale 不是慣例，是 client 會拒收的欄位。**
2. **切 locale 會觸發 CAS 容器切換。** binary 內有 `CAS container switch requested with the current buildkey and locale.  Dropping request`。→ locale 是 CAS 容器的 key 之一，改 `textLocale` 不是改一個顯示選項，是要求換一個容器。
3. **client 有一個 Lua API 可以直接問它自己：`GetAvailableLocales`。** 這是本篇提供的最便宜實驗（§2.3），**30 秒、零風險、不用改任何檔案**。

**唯一沒被關死的門，在 hotfix 通道，但它的形狀天生就是「覆寫」**——見 §4：TrinityCore 的 hotfix 線材上**沒有任何 locale 欄位**，locale 完全是伺服器端依 session locale 挑列的行為。所以「hotfix 當成真 locale」在協定層根本無法表達。

---

## 1. 一個 CASC 時代的 locale 到底由哪些層構成

要讓 `SET textLocale "zhTW"` 真的成立，下面每一層都得到位。逐層列出並附證據來源。

### 1.1 第 0 層：`.build.info` 的 `Tags` 欄（本機實測）

本機 `~/World of Warcraft 3.4.3.54261/.build.info` 的實際內容（欄位表頭 + 唯一一列）：

```
Branch!STRING:0|Active!DEC:1|Build Key!HEX:16|CDN Key!HEX:16|Install Key!HEX:16|IM Size!DEC:4|CDN Path!STRING:0|CDN Hosts!STRING:0|CDN Servers!STRING:0|Tags!STRING:0|Armadillo!STRING:0|Last Activated!STRING:0|Version!STRING:0|KeyRing!HEX:16|Product!STRING:0
eu|1|c91609c69ed2ab39d44039390a1be969|00a60ae44b1a81c84743845a9b9df3a0|||tpr/wow|…|Windows x86_64 EU? acct-UKR? geoip-UA? enUS speech?:Windows x86_64 EU? acct-UKR? geoip-UA? enUS text?:Windows x86_64 EU? acct-UKR? geoip-UA? ruRU speech?:Windows x86_64 EU? acct-UKR? geoip-UA? ruRU text?|||3.4.3.54261||wow_classic
```

四組 tag，`enUS text` / `enUS speech` / `ruRU text` / `ruRU speech`。**沒有 zhTW。**

CascLib 直接解析這一欄：`dep/CascLib/src/CascFiles.cpp:706` 呼叫 `GetDefaultLocaleMask(Csv[nSelected]["Tags!STRING:0"])`（實作在 `CascFiles.cpp:587-605`）。

而 client 自己也讀它——binary 內有 `Attempting to initialize from .build.info`、`Unable to initialize CAS from build info file. Code version does not match .build.info.`、`Unable to initialize CAS from build info file. No active install info entries.`，以及對應的欄位名 `Region` / `BuildConfig` / `CDNConfig` / `KeyRing` / `BuildId` / `VersionsName` / `ProductConfig` / `Hosts` / `Servers` / `ConfigPath`。

**這一層是純文字，改起來零成本。但它只是「宣告」，不產生內容。**

### 1.2 第 1 層：install / download manifest 的 tag bitfield（wowdev.wiki，社群）

`https://wowdev.wiki/TACT` 對 install manifest 的原文：

> "The install file lists files installed on disk. Since the install file is shared by architectures and OSs, there are also tags to select a subset of files. When using multiple tags, a binary combination of the bitfields of files to be installed can be created."

對 download manifest：

> "Just like the install file, the download file is shared across all architectures and locales so utilizes the same bitfield-tag system to assess what subset of files are needed."

tag 的結構（同頁）：

```c
struct {
  string name;                                   // e.g. "zhTW"
  uint16_BE_t type;                              // 見下
  char flags[divru (num_files, CHAR_BIT)];       // 每個檔一個 bit
} tags[num_tags];
```

`type` 的值依 build 不同（同頁列了三組），**≥ 8.0.1.26604 是**：

```
platform = 1, architecture = 2, locale = 3, region = 4, category = 5, alternate = 0x4000
```

**→ locale 在這一層是 tag type 3，一個 tag name 對應一個「哪些檔案屬於我」的 bitmask。**

本機 build config（`Data/config/c9/16/c91609c69ed2ab39d44039390a1be969`，37,547 bytes，實測 `cat`）確認這兩份 manifest 存在且各有兩個 key：

```
install = 8c3b9bb3248a8d718f76a7092ac0cc24 59bebcea12d0a9ceba2af8859653bcc6
install-size = 17491 16957
download = 3ebb9f489c1414f34cf8873261e6aa5a 50bc469d89a446e232f4f1ca49df586d
download-size = 9394120 8192287
root = 28f965732c7762e2ef3d1c00d9d2f801
encoding = 84b699de66312213d237d45200d594e3 53a60f42b994c2ca732fa86aeb4f2f8a
```

### 1.3 第 2 層：root manifest 的 per-locale block（本 repo 原始碼，第一手）

**這是最關鍵的一層。** `dep/CascLib/src/CascRootFile_WoW.cpp` 的 `ParseWowRootFile_Level2`（約 445-451 行）：

```cpp
// WoW.exe (build 19116): Locales other than defined mask are skipped too
if(RootBlock.Header.LocaleFlags != 0 && (RootBlock.Header.LocaleFlags & dwLocaleMask) == 0)
    continue;
```

WoW 的 root file 由多個 block 組成，每個 block 帶自己的 `LocaleFlags`。**同一個 FileDataID 在不同 locale 的 block 各有一份不同的 CKey。** mask 沒對上的 block 根本不會被插進 file tree——**不是「查得到但拿不到」，是「這個 FileDataID 的那個變體不存在」。**

位元值（`dep/CascLib/src/CascLib.h:100-119`）：

```c
#define CASC_LOCALE_ENUS            0x00000002
#define CASC_LOCALE_ZHTW            0x00000100
#define CASC_LOCALE_RURU            0x00002000
```

**→ 「一個 locale」在 root 層的意思是：一整組獨立的 (FileDataID → CKey) 對應，涵蓋所有本地化資產。**

### 1.4 第 3 層：DB2 的 locale 是**檔案層級的 header 欄位**（雙重證據）

任務問的是「DB2 裡的 locale 是獨立 string block、per-record 欄位、還是分檔？」——**答案是分檔，而且是 header 裡一個 `uint32 locale` 欄。**

**證據一（wowdev.wiki，社群）**，`https://wowdev.wiki/DB2` 的 String Block 一節逐字：

> "DB2 records can contain localized strings. In contrast to DBCs, **a DB2 file only contains localized values for a given locale (header.locale)**. Since Cataclysm, all DB files contain only localized string values, including DBCs."

`locale` 欄在 WDB2 / WDB3 / WDB4 / WDB5 / WDB6 / WDC1 各版 header 裡都在，註解一律是 `// as seen in TextWowEnum`。WDC1 為例：

```c
  uint32_t table_hash;             // hash of the table name
  uint32_t layout_hash;            // changes only when the structure of the data changes
  uint32_t min_id;
  uint32_t max_id;
  uint32_t locale;                 // as seen in TextWowEnum
```

**證據二（本 repo 原始碼，第一手）**，`src/common/DataStores/DB2FileLoader.cpp:515-526`——TrinityCore 自己就用這個欄位擋錯放的檔：

```cpp
char* DB2FileLoaderRegularImpl::AutoProduceStrings(char** indexTable, uint32 indexTableSize, uint32 locale)
{
    if (!(_header->Locale & (1 << locale)))
    {
        …
        throw DB2FileLoadException(Trinity::StringFormat(
            "Attempted to load {} which has locales {} as {}. "
            "Check if you placed your localized db2 files in correct directory.", …));
```

TrinityCore 的目錄佈局也直接反映這件事（`src/server/game/DataStores/DB2Stores.cpp:600, 627`）：

```cpp
storage->Load(db2Path + localeNames[defaultLocale] + '/', defaultLocale);   // dbc/enUS/Xxx.db2
…
storage->LoadStringsFrom((db2Path + localeNames[i] + '/'), i);              // dbc/zhTW/Xxx.db2
```

**證據三（★ 本機 client binary 實測，本篇新料）**——client 自己也驗。`WowClassic.exe` 的字串表裡，DB2 載入器的錯誤訊息是連續的一組：

```
Invalid signature 0x%x for Table %s
Table %s has wrong table hash (found %i, expected %i)
Table %s has wrong layout hash (found %i, expected %i)
Table %s has wrong number of columns (found %i, expected %i)
Table %s has wrong locale (found %i, expected %i)
Table '%s' has invalid metadata flags
```

（附近的路徑字串 `D:\BuildServer\A\work-git\wow\WoW\Source\DB\DBEngine\WowClientSparseDB2.cpp` 確認這是 client 的 DB2 引擎。）

**→ 若 client 期待 zhTW 而拿到 enUS 的 DB2 檔，它會明確報 `wrong locale` 而不是靜默接受。這一層不能靠「把 enUS 檔改個名」蒙混。**

**同時這也是好消息的來源**：因為 locale 只在 header 一個欄位，理論上「把 wago.tools 的 zhTW 資料寫成 header.locale = zhTW 的 DB2 檔」是有明確目標的工程，不是逆向未知格式。

### 1.5 第 4 層：UI 字串——**已經不是 Lua 了**

[ui-localization-addon.md](./ui-localization-addon.md) §1 已實測確認：`interface/framexml/globalstrings.lua`（FileDataID 841794）只存在於 6.0.x 建置；這個世代是 `dbfilesclient/globalstrings.db2`（FileDataID 1394440），`wow_classic` 在內的 13 個 product 都有它，wowdev.wiki 的 `DB/GlobalStrings` 頁第一句是「successor of FrameXML/GlobalString.lua ≥ 7.0.3.22594」。

本機也獨立佐證：`_classic_/Interface/` 底下**只有 `AddOns/`**，沒有任何 loose 的 FrameXML。

**→ 對本題的意義：UI 字串這一層併入 §1.4（就是又一張 locale-tagged DB2），不是額外的一層。**

但要注意 binary 裡另有一組**檔案類別名**（`Locally overridden files` 附近）：

```
AddOns  Automation  DBFilesClient  Editor  FrameXML  GlueXML
InspectorFields  LCDXML  Shaders  SharedXML  SymCache
```

→ client 內部仍保有這些類別的 loose 覆寫概念。**這是否在 release build 上可用——見 §3.4，未驗證。**

### 1.6 第 5 層：字型（本機實測，已經在裡面了）

`_classic_/Fonts/` 實測：

```
615960.slug / .slugo   →  fonts/frizqt__.ttf
615968.slug            →  fonts/2002b.ttf      （韓文，5.9 MB）
615971.slug            →  fonts/frizqt___cyr.ttf（西里爾，來自 ruRU）
615974.slug            →  fonts/arkai_t.ttf    （★ 繁中，33,328,656 bytes）
override_3171977063.slug / override_3233945550.slug / override_3910457219.slug
```

`ARKai_T` 就是 zhTW WoW 的繁中字型，而它已經裝在這份 enUS+ruRU 的安裝上（**不帶 locale tag，屬全域安裝**）。三個 `override_*.slug` 是使用者自己的字型 addon 的產物——**這證明 `Fonts/` 是一個 client 真的會讀的 loose 覆寫目錄。**

**→ 這一層完全不是障礙，而且它是整個 client 上唯一一個已驗證可用的第三方 loose 寫入點。**

### 1.7 第 6 層：`.product.db` 與快取目錄

- `.product.db`（519 bytes，protobuf）與 `Launcher.db`（4 bytes）由 Battle.net Agent 維護。**本篇未解析其內容**，標為未驗證；但 §1.1 的 `.build.info` 才是 CascLib 與 client 兩邊都明文讀的那一個。
- **`Cache/ADB/<locale>/` 與 `Cache/WDB/<locale>/` 都以 text locale 命名**（本機實測：目前是 `Cache/ADB/enUS/` 與 `Cache/WDB/enUS/`，前者已被之前的 hotfix 實驗填出 `DBCache.bin768.tmp` / `Spell768.tmp` / `ItemSparse768.tmp` 等檔）。
  **→ 一旦切到 zhTW，hotfix 快取會換到 `Cache/ADB/zhTW/`，等於一次冷快取。** 這對 [hotfix 那篇](./hotfix-db2-localization.md) 的 push id 穩定性討論是個實務注記。

### 1.8 小結：六層的可寫性總表

| # | 層 | 內容 | 這份安裝上有 zhTW 嗎 | 第三方能造嗎 |
|---|---|---|---|---|
| 0 | `.build.info` `Tags` | 純文字 | ❌ | ✅ 直接編輯 |
| 1 | install / download manifest tag（type=3） | bitfield | ❌ | ✅ `TACT.Net` 有 writer |
| 2 | **root 的 `LocaleFlags` block** | (FileDataID → CKey) | ❌ | ✅ 結構可寫（`TACT.Net`）／**❌ 內容拿不到** |
| 3 | DB2（`header.locale`，每 locale 一檔） | 實際字串 | ❌ | ⚠️ 資料可從 wago 取；**寫檔工具是 experimental** |
| 4 | UI 字串 | = 第 3 層（`GlobalStrings.db2`） | ❌ | 同上 |
| 5 | 字型 | `ARKai_T` | **✅ 已在** | — |
| 6 | `Cache/ADB/<locale>` | 執行期產生 | 自動 | — |

**第 2 層那一格「內容拿不到」就是全篇的裁決點。**

---

## 2. 直接把 `textLocale` 設成 `zhTW` 會怎樣？

**誠實答案：沒有第一方文件，也沒找到可信的社群實測報告。以下是從 client 自己的 binary 字串推出的預測，明確標為推論。**

### 2.1 已知的機制事實（本機 binary 實測）

CVar 本身確實存在，且與 audio 分離：

```
textLocale        Set the game locale for text
audioLocale       Set the game locale for audio content
locale            Set the game locale
```

同時有命令列 `-locale %s`、Lua 端 `GetAvailableLocales` / `GetOSLocale` / `GetCurrentRegion`、以及 `<Locale.Text> %s` / `<Locale.Audio> %s` 兩行診斷輸出。

**最有份量的一條**（CAS 層）：

```
CAS container switch requested with the current buildkey and locale.  Dropping request
```

→ **locale 與 buildkey 一起構成 CAS 容器的識別**。改 locale 是要求 client 切換容器，而不是換一個字串表。同一段 binary 附近的 CAS 錯誤族群：

```
Unable to load root manifest for build with key %s: %s
Unable to load new root manifest for build with key %s: %s
Can't find file in build manifest
A download request has failed (no file context is available).
Streaming Error: %s
Loose file not found and CAS is in loose file only mode.
Exhausted all hosts trying to download loose file '%s'.
```

### 2.2 推論（**未驗證**）

依 §1.3 的 root block 機制 + 上面的錯誤字串，最可能的結果是：

1. client 用 zhTW mask 重建 file tree → **所有 locale-tagged 的 FileDataID 都查不到本機 CKey**；
2. CAS 轉而向 CDN 串流那些檔 → 這個 build 的 config 實測 **404**（[macOS 筆記](./macos-client-options.md)§3.3；`.build.info` 的 Build Key `c91609c69ed2ab39d44039390a1be969` 就是那筆 404 的同一個 hash）；
3. 結果落在 `Streaming Error` / `Can't find file in build manifest` / `The CAS system was unable to initialize:` 這一族，**最可能是在 glue screen 之前就失敗**。

**CascLib 本身完全沒有 locale fallback**（`CascRootFile_WoW.cpp` 是 `continue`，不是 fallback）。**client 上層有沒有 fallback，wowdev.wiki 與 CascLib 都沒有記載。**

### 2.3 ★ 怎麼安全地實測（便宜，建議照這個順序）

**Step A — 零風險、不改任何檔案（30 秒）**：進遊戲，`/run print(GetAvailableLocales())`（或 `/dump GetAvailableLocales()`）。

- 這是 client 自己回答「我認為哪些 locale 可用」。若回傳只含 `enUS`（可能還有 `ruRU`），§2.2 的推論就等於被 client 自己確認了一半。
- **這一步不碰 `Config.wtf`、不碰 CASC、失敗成本為零。**

**Step B — 可逆的最小改動**：

```bash
D=~/'World of Warcraft 3.4.3.54261/_classic_'
cp "$D/WTF/Config.wtf" "$D/WTF/Config.wtf.bak"       # 先備份
: > "$D/Logs/Tact.log"                                # 清空，當作儀表（目前 0 bytes）
# 手動把 SET textLocale "enUS" 改成 "zhTW"，audioLocale 保持 enUS
# 啟動 → 不論成功失敗，立刻看：
cat "$D/Logs/Tact.log"      # CAS / TACT 層的錯誤都會進這裡
cat "$D/Logs/Client.log"
ls  "$D/Cache/ADB"          # 有沒有多出 zhTW 目錄
# 還原：
cp "$D/WTF/Config.wtf.bak" "$D/WTF/Config.wtf"
```

**風險評估**：`Config.wtf` 是純文字、有備份；CASC 是 content-addressable、client 不會因為讀不到而破壞既有資料（最壞是往 CDN 要檔然後失敗）。**唯一真正該注意的是**：若 client 真的成功切換容器並開始下載，它可能會改寫 `.build.info`——所以**連 `.build.info` 一起備份**。

> **這一格是本篇裡使用者唯一能用一個下午把「未驗證」變成「已驗證」的地方。** 值得做，因為 Step A 的結果就足以決定要不要往下想。

---

## 3. 能不能把一個 locale「加進」既有的 CASC 安裝？——本篇的核心題

### 3.1 CascLib 的公開 API：確認**完全沒有寫入方向**（本 repo 原始碼，第一手）

`dep/CascLib/src/CascLib.h:393-427` 的完整函式清單（實際 `sed` 出來，不是摘要）：

```c
// Functions for storage manipulation
CascOpenStorageEx / CascOpenStorage / CascOpenOnlineStorage
CascGetStorageInfo / CascCloseStorage
CascOpenFile / CascOpenLocalFile / CascGetFileInfo / CascSetFileFlags
CascGetFileSize64 / CascSetFilePointer64 / CascReadFile / CascCloseFile
CascGetFileSize / CascSetFilePointer
CascFindFirstFile / CascFindNextFile / CascFindClose
CascAddEncryptionKey / CascAddStringEncryptionKey
CascImportKeysFromString / CascImportKeysFromFile
CascFindEncryptionKey / CascGetNotFoundEncryptionKey
// CDN Support
CascCdnGetDefault / CascCdnDownload / CascCdnFree
```

**沒有 `CascWriteFile`、沒有 `CascCreateFile`、沒有 `CascCreateStorage`、沒有 `CascAddFile`、沒有任何 tag 或 root 的 mutator。** 唯一名字裡有 `Add` / `Import` 的四個全部是**加密金鑰**，與檔案內容無關。

`grep -rn "CascWriteFile\|CascCreateStorage\|CascBuild" dep/CascLib/src/` 的所有命中都是 `CascBuildNone` / `CascBuildDb` / `CascBuildInfo` 這個「build file 型別」enum 與相關的 `CheckCascBuildFile*()`——**是判斷本機安裝用哪種 build 描述檔，不是「建構」任何東西**。

repo 自述（`dep/CascLib/README.md` 第一行）：

> "An open-source implementation of library for reading CASC storage from Blizzard games since 2014"

**→ 前篇的「CascLib 唯讀」結論，在 write/build 方向上逐函式確認成立。**

### 3.2 但本機 CASC 的格式**是被完整記載的**（wowdev.wiki，社群）

要誠實：唯讀的是 CascLib，不是格式本身。`https://wowdev.wiki/CASC` 把本機儲存的三個組件都寫得很細：

- **`.idx` journal**：16 個 bucket，bucket index 由 key 前 9 bytes 的 nibble XOR 決定，wiki 甚至給了 C 函式 `cascGetBucketIndex()`；header 有 `HeaderHashSize` / `HeaderHash`（`hashlittle2`）。
- **`shmem`**：記錄 data 路徑、各 `.idx` 的版本號、以及 data 檔的可用空白區（最多 1090 筆）。wiki 明寫「The file is recreated every time a client is started」，並記載了 Battle.net Agent 寫入 vs 遊戲寫入的路徑差異（絕對 vs 相對）。
- **`data.NNN`**：BLTE 壓縮後的內容片段。

本機實測完全對得上：`Data/data/` 有 16 個 `.idx`（`0000000022.idx` … `0f00000025.idx`）、`data.000`…`data.NNN`、以及 `shmem`；`Data/config/` 是雜湊分層目錄，build config 就在 `c9/16/c91609…`；另有 `Data/indices/`。

**→ 「寫一個 CASC 出來」在格式層面不是黑箱。真正的問題在 §3.3 與 §3.5。**

### 3.3 有工具真的在寫嗎？有——`wowdev/TACT.Net`（第一手，`gh api`）

| 項目 | 實測值 |
|---|---|
| repo | `wowdev/TACT.Net`（`barncastle/TACT.Net` 會 redirect 到這裡） |
| 自述 | 「A C# library for **reading and writing** World of Warcraft's TACT repositories used to distribute the game.」 |
| License | **GPL-3.0** |
| ★ / 最後 push | 12 / **2024-10-23** |

原始碼結構（`gh api contents` 實測）：`SystemFiles/{Root, Encoding, Install, Download, Patch, Tags}`、`Indices`、`BlockTable`、`Configs`、`Network`、`Cryptography`、`FileLookup`。

**它確實有 §1.1–§1.3 每一層的 writer：**

- `TACTRepo.Create(string product, Locale locale, uint build)` 的註解逐字：「Creates a new TACT container populated with: defaulted configs, an index container and an **empty root, encoding, install and download file**」。
- `SystemFiles/Root/RootFile.cs` 的類別註解：「A catalogue of all files stored in the data archives. **Blocks contain variants of each file seperated by their Locale and Content flags**」，並有 `public LocaleFlags LocaleFlags { get; set; } = LocaleFlags.enUS;`。
- `SystemFiles/Root/LocaleFlags.cs` 的值**與 CascLib 逐位元相同**：`enUS = 0x2, zhCN = 0x40, zhTW = 0x100, ruRU = 0x2000`。
- `SystemFiles/Install/InstallFile.cs` 有 `SetTags(string filename, bool value, params string[] tags)`、`AddOrUpdate(TagEntry)`、`SetDefaultTags(uint build)`；`Tags/TagEntry.cs` 有完整的 `Read`/`Write`（`Name` + `TypeId` + `FileMask`）。

**一個必須講清楚的陷阱**：`TACT.Net/Locales.cs` 的 `enum Locale { US, EU, CN, KR, TW, SG, XX }` 是 **CDN region**（對應 `us.patch.battle.net` 那個 region），**不是 text locale**。text locale 是 `Root/LocaleFlags.cs` 那一組。**兩者都叫「locale」但完全不同，很容易誤讀。**

**裁決（§3.3）：「CASC/TACT 只能讀不能寫」這句話，在 CascLib 是對的，在整個生態是錯的。寫入端存在、是 GPL-3.0、2024 年還在維護，而且它顯式支援 per-locale root block。**

### 3.4 但**讓 client 接受**自建容器，才是真正的鎖

寫得出容器 ≠ client 會吃。已知只有兩條路，兩條都不通向 54261：

#### (a) `barncastle/CASCHost` — 自架 CDN（**最接近的一次，但已死**）

README 自述（`gh api readme` 實測）：

> "CASCHost is a specially designed web service that both builds and hosts modified a CAS container. This web service is designed to replicate Blizzard's own CDN meaning a client works as seamlessly with custom content as with retail."

它的作法完全對得上 §1 的分層：

- 使用者把目標 client 的 `.build.info` 丟進 `wwwroot\systemfiles`，把自訂檔按 Blizzard 目錄結構丟進 `wwwroot\data`，服務重建 root/encoding/install/download 並輸出成 CDN 結構。
- 設定裡**明確有一項 `Locale`**：「This is the client locale you'll be targeting, **this is important for localised DB files to work correctly**」——**這正是本題的那一層，而且它承認這一層需要單獨處理。**
- 使用方式第 5 步：「You will need to **patch your exe/app** to point the Versions and CDNs URLs to your CASCHost server」，並且「the `.build.info` will need to be renamed/deleted to force the client to connect to your CDN opposed to Blizzard's」。

**為什麼對 54261 不成立（三項，全部第一手）：**

1. **最後 commit `2018-06-13T11:39:12Z`**（`gh api commits` 實測）。README 的「What versions are supported? Everything WoD+」是 2018 年的 WoD+，**3.4.3 Classic（2023）遠在其後**，且 Classic 的 root 有 `_isClassic` 這類特殊處理（`TACT.Net` 自己有這個欄位）。
2. **它需要 .NET Core 2.1 + MySQL**，且 README 明寫 HostDomain「must be "localhost" or a domain, **IP addresses are NOT supported**」。
3. **★ 致命的一項**：README 的 Notes 逐字：「On the first build **the system downloads the files it needs from Blizzard's CDN** so may take a few minutes to complete. **If this fails, as Blizzard does delete old client versions**, you must use CASCExtractor to extract the required files.」
   → **這就是同一道 404 牆**（[macOS 筆記](./macos-client-options.md)§3.3）。而「改用 CASCExtractor 從本機抽」對本題**沒有幫助**——本機根本沒有 zhTW 的內容（§1.3）。

#### (b) `Dramacydal/CascOverride` — runtime binary patch（**2017 年的 32-bit Legion，完全無效**）

repo 描述：「safe WoW tool to override loading files from CASC」。無 README、無 License、★0、最後 push **2017-02-07**。

讀原始碼（`CascBP/CascBP.cs`）確認它實際做什麼：用 `WhiteMagic` 的 `ProcessDebugger` 在執行中的 WoW 進程設中斷點，位址是**逐 build 硬寫的兩個 `jz` 分支**：

```csharp
// .text:004913D1 74 6B    jz  short loc_49143E
{ 22293, new OffsData(0x004913D1 - 0x400000, 0x004912D2 - 0x400000) },
{ 22423, … }, { 22498, … }, { 22522, … }, { 22566, … }, { 22594, … },
{ 22624, … }, { 22747, … }, { 22810, … }, { 22908, … },
```

**`- 0x400000` 的 image base 說明它針對的是 32-bit PE**，build 號 22293–22908 是 **Legion 7.0.x/7.1.x**。本機的 `WowClassic.exe` 是 **50,589,832 bytes 的 64-bit**、build 54261。**這份 offset 表對它一個字都不適用**，而重建等於從零逆向 CASC 開檔路徑。

> 值得記一筆：**這個手法本身不是無稽之談**——[wow-patcher 筆記](./wow-patcher-runtime-mode.md) 已經證明對這顆 binary 做定點 patch 是做得到的（Ed25519 公鑰換 32 bytes）。差別是「換一個已知常數」與「改寫 CAS 開檔的控制流」不是同一個量級。**未驗證，且不建議。**

#### (c) `Fonts/` 這個例外，說明了規則

本機 `Fonts/override_3171977063.slug` 等三個檔證明：**client 對某些類別確實會先看 loose 檔。** binary 裡也有 `Locally overridden files` 與 `modification of fileId %i ignored as it is overridden by local manifest file %s`、`Loose file not found and CAS is in loose file only mode.`、CVar `overrideArchive`（說明字串：「Whether or not the client loads alternate data」）。

**但**：`overrideArchive` 是 MPQ 時代留下來的 CVar 名，**它在 CASC 時代的 release build 上是否還有作用——完全未驗證**，wowdev.wiki 也沒有記載。`Fonts/` 能用不代表 `DBFilesClient/` 能用。

> **這是本篇唯一一個「值得再挖一次」的縫隙**，但它的上限也只是「注入單檔」，不是「宣告一個新 locale」——因為 §1.3 的 root block 仍然決定了 client 要不要去找那個 FileDataID 的 zhTW 變體。

### 3.5 ★ 最後一道，也是無法繞的一道：**內容本身不存在**

即使 (a) 或 (b) 其中一條被打通，還是要有 zhTW 的**檔案內容**。三個來源逐一結案：

| 來源 | 結果 |
|---|---|
| 本機 CASC | ❌ 從未下載（`.build.info` 只有 enUS/ruRU tag，root 的 zhTW block 對應的 CKey 不在本機 data archive 裡） |
| Blizzard CDN | ❌ 這個 build 的 build config `c91609c6…` **實測 404**（macOS 筆記 §3.3；與 `.build.info` 的 Build Key 是同一個 hash） |
| 自行合成 | ⚠️ **只有文字那一部分做得到** |

**「自行合成」這一格值得展開，因為它是唯一沒有被完全關死的：**

- **資料在**：[hotfix 筆記](./hotfix-db2-localization.md)§6.2 已實測 wago.tools 能匯出 `3.4.3.54261` 的 zhTW `SpellName`(49,357)、`Spell`(49,357)、`Achievement`(1,912)、`AreaTable`(2,373)、`Map`(130)、`SkillLine`(152)，[UI 筆記](./ui-localization-addon.md)§0.3 再加上 `GlobalStrings`(18,232)。
- **DB2 writer 也在**：`wowdev/DBCD`（MIT，★54，最後 push 2026-08-23）README 逐字：

  > "**Experimental writing** (`WDC3` works, the others likely will too but are largely untested with actual WoW clients)."
  > 限制：「_(Writing)_ Does not support writing out DB2s with **multiple sections**.」

  **兩個限制都很重**：(i) 「largely untested with actual WoW clients」是作者自己的話；(ii) 3.4.3.54261 的 DB2 用的是 WDC3 還是 WDC4、有沒有 multiple sections——**本篇未驗證**。
- **但非文字的部分做不到**：locale-tagged 的不只 DB2。glue 畫面的在地化貼圖、過場字幕、以及任何被標成 zhTW 的資產，都得有一份。**要嘛全部合成，要嘛就得讓 client 對「缺 zhTW 變體」的檔退回 enUS——而 §1.3 的機制說它不會退，§2.2 說它會去 CDN 要，而 CDN 是 404。**

---

## 4. hotfix 通道到底有沒有 locale 維度？（TrinityCore 原始碼，第一手）

任務問的是關鍵一題：**hotfix 記錄自己帶 locale，還是伺服器只是照 session locale 挑列？答案明確是後者。**

### 4.1 schema：`hotfix_data` **沒有 locale 欄**，`hotfix_blob` 有

`sql/base/dev/hotfixes_database.sql`（實測）：

```sql
CREATE TABLE `hotfix_data` (
  `Id` int NOT NULL, `UniqueId` int unsigned NOT NULL DEFAULT '0',
  `TableHash` int unsigned NOT NULL, `RecordId` int NOT NULL,
  `Status` tinyint unsigned NOT NULL DEFAULT '3', `VerifiedBuild` int NOT NULL DEFAULT '0',
  PRIMARY KEY (`Id`,`TableHash`,`RecordId`)          -- ← 沒有 locale
);

CREATE TABLE `hotfix_blob` (
  `TableHash` int unsigned NOT NULL, `RecordId` int NOT NULL,
  `locale` varchar(4) NOT NULL,                       -- ← 有 locale
  `Blob` blob, `VerifiedBuild` int NOT NULL DEFAULT '0',
  PRIMARY KEY (`TableHash`,`RecordId`,`locale`)
);
-- hotfix_optional_data 同樣有 locale 欄
```

而字串本身住在每張 DB2 的 `*_locale` 伴生表，例如：

```sql
CREATE TABLE `spell_name` (        `ID`, `Name`, `VerifiedBuild` );
CREATE TABLE `spell_name_locale` ( `ID`, `locale` varchar(4), `Name_lang` text, `VerifiedBuild`,
  PRIMARY KEY (`ID`,`locale`,`VerifiedBuild`) )
  PARTITION BY LIST COLUMNS(locale) (PARTITION deDE …, PARTITION esES …, …);
```

**→ 「一列 hotfix」是 locale 無關的；「那一列的字串」才有 locale。**

### 4.2 執行期：locale 是**伺服器端的挑選**，而且會被 advertise 過濾

`src/server/game/DataStores/DB2Stores.cpp:1785-1789`（`LoadHotfixData`）為每一列算出一個 mask：

```cpp
hotfixRecord.AvailableLocalesMask = availableDb2Locales.to_ulong();
HotfixPush& push = _hotfixData[id];
push.Records.push_back(hotfixRecord);
push.AvailableLocalesMask |= hotfixRecord.AvailableLocalesMask;
```

`src/server/game/Handlers/HotfixHandler.cpp` 的三個地方都拿它跟 session locale 比：

```cpp
void WorldSession::SendAvailableHotfixes() {
    for (auto const& [pushId, push] : sDB2Manager.GetHotfixData()) {
        if (!(push.AvailableLocalesMask & (1 << GetSessionDbcLocale())))
            continue;                                   // ← 這個 locale 沒有資料就不 advertise
        availableHotfixes.Hotfixes.insert(push.Records.front().ID);
    }
    SendPacket(availableHotfixes.Write());
}

void WorldSession::HandleHotfixRequest(...) {
    …
    if (!(hotfixRecord.AvailableLocalesMask & (1 << GetSessionDbcLocale())))
        continue;
    …
    storage->WriteRecord(uint32(hotfixRecord.RecordID), GetSessionDbcLocale(), hotfixQueryResponse.HotfixContent);
    …
    else if (std::vector<uint8> const* blobData =
             sDB2Manager.GetHotfixBlobData(hotfixRecord.TableHash, hotfixRecord.RecordID, GetSessionDbcLocale()))
    …
    else
        // Do not send Status::Valid when we don't have a hotfix blob for current locale
        hotfixData.Record.HotfixStatus = storage ? Status::RecordRemoved : Status::Invalid;
}
```

`HandleDBQueryBulk` 同樣是 `store->WriteRecord(record.RecordID, GetSessionDbcLocale(), dbReply.Data)`。

session locale 的來源：`WorldSession.cpp:132` 的 `m_sessionDbcLocale(sWorld->GetAvailableDbcLocale(locale))`，`WorldSession.h:1198` 的 `GetSessionDbcLocale()`。

### 4.3 線材上**沒有** locale 欄位（決定性）

`src/server/game/Server/Packets/HotfixPackets.h` 的四個類別，逐欄檢查：

| 封包 | 欄位 |
|---|---|
| `DBQueryBulk`（C→S） | `TableHash`, `Queries[].RecordID` |
| `DBReply`（S→C） | `TableHash`, `Timestamp`, `RecordID`, `Status`, `Data` |
| `AvailableHotfixes`（S→C） | `VirtualRealmAddress`, `Hotfixes[]`（只有 id） |
| `HotfixConnect`（S→C） | `Hotfixes[].Record`（HotfixId/UniqueId/TableHash/RecordId/Status）+ `Size` + `HotfixContent` |

**沒有任何一個欄位攜帶 locale。**

> ### 裁決（§4）
>
> **hotfix 通道在協定層完全不知道 locale 的存在。** 伺服器依 session 的 locale 挑出一份 body 塞進去，client 收到的就是「這一列的新內容」——**它無從得知也不在乎那是哪個語言**。
>
> **→ 「把 hotfix 當成一個真 locale 來註冊」在線材上無法表達。hotfix 的語意天生就是覆寫**（wowdev.wiki 的 `DBCache.bin` 頁：`RecordState::Valid = 1 // has data, overwrites source record (if exists)`）。
>
> **這不是壞消息，是好消息的一半**：正因為 hotfix 與 locale 正交，**現在這套「覆寫 enUS」的做法，在 `textLocale` 是什麼的情況下都一樣有效**。§1.4 的 `Table %s has wrong locale` 檢查是針對**檔案**的 header，不是針對 hotfix 記錄。
>
> **另一半是壞消息**：也正因為正交，hotfix 永遠只能是「覆寫」，永遠不會讓 client 認為自己在跑中文。

---

## 5. 社群到底做出了什麼（全部 `gh api` 實測）

### 5.1 分兩類：讀／匯出（多）vs 寫／注入（極少）

| 專案 | 它證明做得到什麼 | 方向 | License | ★ | 最後 push |
|---|---|---|---|---|---|
| `ladislav-zezula/CascLib` | 讀 CASC storage（**業界標準，本 repo 就 vendored 這一份**） | 讀 | MIT | 489 | 2026-08-22 |
| `WoW-Tools/CASCExplorer` | GUI 瀏覽／抽出本機 CASC | 讀 | 無 | 436 | 2025-11-10 |
| `Marlamin/wow.export` | 抽出／轉檔，**支援直接串流 CDN 而不需要 client** | 讀 | — | — | — |
| `Marlamin/BuildBackup` | 「Backs up CASC data from Blizzard CDNs」 | 讀 | MIT | 37 | 2025-09-13 |
| `wowdev/WoWDBDefs` | 所有 build 的 DB2 欄位定義（**目前的 hotfix 做法就靠它**） | 定義 | NOASSERTION | 323 | **2026-09-03** |
| `wowdev/DBCD` | 讀 WDBC/WDB2-6/WDC1-5；**experimental 寫（WDC3）**；套用 `DBCache.bin` | **讀＋寫（實驗性）** | MIT | 54 | 2026-08-23 |
| **`wowdev/TACT.Net`** | **「reading and writing … TACT repositories」——含 root 的 per-locale block、install/download 的 tag writer** | **寫** | **GPL-3.0** | 12 | 2024-10-23 |
| **`barncastle/CASCHost`** | **自架 CDN，讓 client 以為在跟 Blizzard 講話** | **寫＋供給** | 無 | 0 | **2018-06-13** |
| `Dramacydal/CascOverride` | runtime debugger patch，NOP 掉兩個 `jz` 讓 client 吃 loose 檔 | **注入** | 無 | 0 | **2017-02-07** |

### 5.2 已證明 vs 只是宣稱

**已證明（讀過原始碼／README 原文）：**
- `TACT.Net` **確實有** per-locale root block 與 install tag 的 writer——這是讀 `LocaleFlags.cs` / `RootFile.cs` / `InstallFile.cs` / `TagEntry.cs` 的實際內容得到的，不是靠 README。
- `DBCD` **自己承認** 寫入是 experimental 且「largely untested with actual WoW clients」。
- `CASCHost` **自己承認** 第一次 build 要從 Blizzard CDN 下載，且「Blizzard does delete old client versions」。
- `CascOverride` 的 build 表證明它是 32-bit Legion 專用。

**只是宣稱／未驗證：**
- **沒有任何一個專案宣稱做過「為既有安裝新增一個 locale」。** 一個都沒有。最接近的是 `CASCHost` 的 `Locale` 設定項，而那是「你要**針對**哪個 locale 建容器」，不是「新增一個」。
- 沒有找到任何「locale repack」「custom locale patch」的現代 CASC 專案（GitHub repo search 對 `CASC wow` / `TACT wow` 的前 12 筆全部檢視過，其餘均為讀取工具、bruteforcer、或無關同名專案）。
- **這是「未找到」，不是「已證明不存在」。** 但三個獨立面向（wowdev.wiki 沒有記載、CascLib 沒有 API、沒有任何專案宣稱做過）指向同一結論。

### 5.3 對照組：MPQ 時代為什麼可以

[前篇](./zhtw-localization.md)§2.5 已記錄：MPQ 有 `PTCH` entry、同檔名覆寫、client 依優先序套用——**這是格式內建的第三方擴充點**。CASC 沒有對應物：檔案以 encoding key 定址，(FileDataID → CKey) 的對應由 root manifest 獨佔，而 root 的完整性由 build config 的 hash 鏈保證。**「補丁」這個概念在 content-addressable storage 裡沒有位置。**

---

## 6. 裁決與工作形狀

### 6.1 裁決

> ## **不可行。**
>
> **卡住的是第 2 層：root manifest 裡 `LocaleFlags = 0x100` 的 block 與它們指向的 data archive 內容。**
>
> 這一層的特別之處在於**它是唯一一個「不能用寫的解決」的層**：
>
> - 第 0、1、2 層的**結構**：`TACT.Net` 寫得出來（GPL-3.0，2024 年還活著）。
> - 第 3、4 層的**資料**：wago.tools 拿得到（本 build 的 zhTW，含 `GlobalStrings`）。
> - 第 5 層字型：**已經在本機了**。
> - 第 2 層的**內容**：本機沒有、CDN 404、合成只涵蓋文字資產。
>
> 而且即使內容有了，**第二道鎖仍在**：沒有任何已驗證的方式讓 54261 接受一份自建容器。`CASCHost` 停在 2018 且它自己的第一步就撞同一道 404；`CascOverride` 是 2017 年的 32-bit Legion offset 表。

### 6.2 「如果非做不可」的工作形狀（為完整性列出，**不建議**）

1. 用 `DBCD` 把 wago 的 zhTW CSV 寫成 `header.locale = zhTW` 的 DB2 檔——**先要確認 54261 的 DB2 是不是 WDC3、有沒有 multiple sections**（DBCD 的兩個明文限制）。約 30–50 張表，包含 `GlobalStrings`。
2. 用 `TACT.Net` 建一份容器：root 加上 `LocaleFlags.zhTW` 的 block、install/download 加上 `type=3` 的 `zhTW` tag、重算 encoding 與 index。
3. **為所有「非 DB2 的 locale-tagged 資產」找到來源**——這一步沒有解，也是全案的死點。
4. 讓 client 接受它：改寫 `.build.info`，或起一個 CASCHost 式的本機 CDN（要先把 2018 年的程式碼移植到 3.4.3 Classic 的 root 格式），或走 binary patch（要從零逆向 64-bit 54261 的 CAS 開檔路徑）。
5. 全部做完之後得到的，**還是同一批中文字**——只是它們住在 DB2 檔裡而不是 hotfix 記錄裡。

**成本是數量級的差距，產出的可見差異接近零。**

### 6.3 現行做法為什麼其實是對的

「覆寫 enUS」不是將就，它在這條 stack 上有三個結構性優勢：

1. **與 locale 正交**（§4.3）：不管 `textLocale` 是什麼都成立，不會被 CASC 層的任何事情擋住。
2. **零 client 檔案改動**：不碰 CASC、不碰 `.build.info`，失敗完全可逆（刪 CSV／還原一行）。
3. **client 自己有驗證回饋**：`Logs/Hotfix.log` 的 `VALIDATION_RESULT_VALID` / `_INVALID` 是逐列的儀表——**這比任何自建容器方案的可觀測性都好**。

**代價只有一項，而且是認知上的**：client 的 `GetLocale()` 會一直回 `enUS`，`Cache/ADB/enUS/`、`Fonts/` 的 fallback 邏輯、以及任何依 `GetLocale()` 分支的 addon，都會以為自己在跑英文版。**這是「覆寫」這個形狀的固有性質，不是實作缺陷。**

### 6.4 值得做的兩件小事

1. **§2.3 Step A：`/dump GetAvailableLocales()`**——30 秒、零風險，把本篇最大的一項推論（§2.2）變成已驗證或推翻。
2. **§3.4(c) 的縫隙**：既然 `Fonts/override_*.slug` 已證明 loose 覆寫在某些類別上可行，而 binary 裡列了 `DBFilesClient` / `FrameXML` / `GlueXML` 等類別名與 `overrideArchive` CVar，**「試著在 `_classic_/` 底下放一個 loose DB2 看 client 理不理」是一個便宜的實驗**。成功機率低（未找到任何記載），但成本只有放一個檔。**注意：這仍然只是「注入單檔」，不會讓 zhTW 成為可選 locale。**

---

## 7. 驗證指令（可重跑，全部唯讀）

```bash
# ---- 本機 client（唯讀）----
D=~/'World of Warcraft 3.4.3.54261'
cat "$D/.build.info"                                   # Tags 欄只有 enUS / ruRU
cat "$D/Data/config/c9/16/c91609c69ed2ab39d44039390a1be969" | head -12   # root/install/download/encoding
ls  "$D/Data/data" | head -20                          # 16 個 .idx + data.NNN + shmem
ls  "$D/_classic_/Fonts"                               # 615974.slug = ARKai_T + 三個 override_*.slug
find "$D/_classic_/Cache" -maxdepth 3                  # Cache/ADB/enUS、Cache/WDB/enUS
ls -la "$D/_classic_/Logs/Tact.log"                    # 目前 0 bytes ← §2.3 的儀表

# ★ client binary 的字串（本篇最重要的一手來源）
strings -a -n 5 "$D/_classic_/WowClassic.exe" > /tmp/wow_strings.txt   # 243,049 行
grep -n "wrong locale"                       /tmp/wow_strings.txt   # DB2 locale 驗證
grep -n "CAS container switch"               /tmp/wow_strings.txt   # locale 是 CAS 容器 key
grep -n "GetAvailableLocales\|GetOSLocale"   /tmp/wow_strings.txt   # Lua API
grep -n "textLocale\|audioLocale\|overrideArchive" /tmp/wow_strings.txt
grep -n "Locally overridden files\|loose file only mode\|local manifest" /tmp/wow_strings.txt
grep -n "Streaming Error\|build manifest\|Unable to initialize CAS"     /tmp/wow_strings.txt

# ---- 本 repo（唯讀）----
cd /Users/shinichi/Works/side-project/TrinityCore
sed -n '393,427p' dep/CascLib/src/CascLib.h            # 公開 API 全表：沒有任何 write
grep -rn "CascWriteFile\|CascCreateStorage" dep/CascLib/src/   # 只命中 CascBuild* enum
sed -n '100,119p' dep/CascLib/src/CascLib.h            # CASC_LOCALE_ZHTW = 0x100
sed -n '445,451p' dep/CascLib/src/CascRootFile_WoW.cpp # root block 的 LocaleFlags 過濾
head -4 dep/CascLib/README.md                          # "for reading CASC storage"

sed -n '515,527p'  src/common/DataStores/DB2FileLoader.cpp        # header->Locale 檢查
sed -n '596,646p'  src/server/game/DataStores/DB2Stores.cpp       # dbc/<locale>/ 目錄佈局
sed -n '1734,1800p' src/server/game/DataStores/DB2Stores.cpp      # AvailableLocalesMask
cat src/server/game/Handlers/HotfixHandler.cpp                    # GetSessionDbcLocale() ×4
sed -n '29,95p' src/server/game/Server/Packets/HotfixPackets.h    # 線材上沒有 locale
grep -n "CREATE TABLE \`hotfix_data\`" -A 9 sql/base/dev/hotfixes_database.sql   # 無 locale 欄
grep -n "CREATE TABLE \`hotfix_blob\`" -A 8 sql/base/dev/hotfixes_database.sql   # 有 locale 欄
grep -n "CREATE TABLE \`spell_name_locale\`" -A 8 sql/base/dev/hotfixes_database.sql

# ---- 外部（gh api，唯讀）----
gh api repos/wowdev/TACT.Net --jq '.description, .license.spdx_id, .pushed_at'
gh api repos/wowdev/TACT.Net/contents/TACT.Net/SystemFiles/Root/LocaleFlags.cs --jq .content | base64 -d
gh api repos/wowdev/TACT.Net/contents/TACT.Net/Locales.cs --jq .content | base64 -d   # ← region，不是 text locale
gh api repos/wowdev/TACT.Net/contents/TACT.Net/SystemFiles/Install/InstallFile.cs --jq .content | base64 -d | grep -n Tag
gh api repos/barncastle/CASCHost/readme --jq .content | base64 -d
gh api "repos/barncastle/CASCHost/commits?per_page=3" --jq '.[].commit.author.date'   # 2018-06-13
gh api repos/wowdev/DBCD/readme --jq .content | base64 -d | head -12                  # experimental writing
gh api repos/Dramacydal/CascOverride/contents/CascBP/CascBP.cs --jq .content | base64 -d | head -50

# ---- wowdev.wiki（社群；直接 curl 被 Cloudflare 擋 403，加 UA 後 200）----
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
curl -s -A "$UA" https://wowdev.wiki/DB2   | grep -i "only contains localized"
curl -s -A "$UA" https://wowdev.wiki/TACT  | grep -i "shared by architectures"
curl -s -A "$UA" https://wowdev.wiki/CASC  | grep -i "content-addressable"
```

---

## 8. 明確記錄「未驗證」

- **未驗證（最大的一項）**：把 `textLocale` 設成 `zhTW` 之後 client 的實際行為。§2.2 是從 binary 字串與 CascLib 機制推出的預測。**§2.3 給了兩步實驗，Step A 零風險。**
- **未驗證**：`GetAvailableLocales()` 在這份安裝上實際回傳什麼。
- **未驗證**：`overrideArchive` CVar 在 CASC 時代的 release build 上是否還有作用；`Locally overridden files` 那一組類別（`DBFilesClient` / `FrameXML` / …）是否對 release build 開放。**`Fonts/` 可用不能推論其他類別可用。**
- **未驗證**：3.4.3.54261 的 DB2 是 WDC3 還是 WDC4、是否含 multiple sections。這決定 `DBCD` 的 experimental writer 能不能用。
- **未驗證**：`TACT.Net` 是否真的能產出 3.4.3 Classic 能接受的 root（它有 `_isClassic` 欄位，但本篇沒有執行過它）。
- **未驗證**：`CASCHost` 移植到 3.4.3 的可行性（未嘗試；其 2018 的目標是 WoD+ 的 retail root 格式）。
- **未驗證**：`.product.db`（519 bytes）的內容與它在 locale 選擇上的角色。本篇只確認了 `.build.info` 這一條路徑。
- **未驗證**：除了 DB2 之外，這個 build 還有哪些 FileDataID 帶 zhTW 的 root block（沒有 zhTW 的 root 可讀，無從枚舉）。
- **未找到（≠ 已證明不存在）**：任何為現代 CASC client 建構或新增 locale 的專案。
- **未做**：沒有改動任何 client 檔案；沒有執行 `TACT.Net` / `DBCD` / `CASCHost`；沒有登入遊戲；沒有使用瀏覽器自動化。
- **未評估**：把 wago.tools 匯出的 Blizzard 遊戲文字重新打包成 client 資料的授權問題。**個人本機使用與公開再發布是兩回事。**

---

## 9. 實際取用過的來源

**本機 client（第一手實測，唯讀）**
- `~/World of Warcraft 3.4.3.54261/.build.info`（Tags 欄四組、Build Key `c91609c6…`）
- `Data/config/c9/16/c91609c69ed2ab39d44039390a1be969`（build config 全文 37,547 bytes：`root` / `install` / `download` / `encoding` / `vfs-*`）
- `Data/data/`（16 個 `.idx`、`data.000`+、`shmem`）、`Data/indices/`
- **`_classic_/WowClassic.exe`（50,589,832 bytes）的 243,049 條字串** —— `Table %s has wrong locale`、`CAS container switch requested with the current buildkey and locale`、`GetAvailableLocales`、`textLocale` / `audioLocale` / `overrideArchive`、`Locally overridden files`、`Loose file not found and CAS is in loose file only mode.`、`modification of fileId %i ignored as it is overridden by local manifest file %s`、CAS 錯誤族群、`.build.info` 欄位名
- `_classic_/Fonts/`（`615974.slug` = ARKai_T 33 MB + 三個 `override_*.slug`）、`_classic_/Cache/{ADB,WDB}/enUS/`、`_classic_/Logs/Tact.log`（0 bytes）、`_classic_/Interface/`（只有 `AddOns/`）

**本 repo TrinityCore（第一手，唯讀）**
- `dep/CascLib/src/CascLib.h`（公開 API 全表、`CASC_LOCALE_*`）、`CascRootFile_WoW.cpp`、`CascFiles.cpp`、`CascOpenStorage.cpp`、`CascCommon.h`、`README.md`
- `src/common/DataStores/DB2FileLoader.cpp:515-527, 1178-1192`、`DB2FileLoader.h`
- `src/server/game/DataStores/DB2Stores.cpp:596-646, 1734-1955`
- `src/server/game/Handlers/HotfixHandler.cpp`（全文）
- `src/server/game/Server/Packets/HotfixPackets.h`、`src/server/game/Server/WorldSession.h:1198`、`WorldSession.cpp:132`
- `sql/base/dev/hotfixes_database.sql`（`hotfix_data` / `hotfix_blob` / `hotfix_optional_data` / `spell_name` / `spell_name_locale`）

**外部專案（`gh api`，第一手原始碼與 metadata）**
- `wowdev/TACT.Net`：`README.md`、`TACT.Net/Locales.cs`、`TACTRepo.cs`、`SystemFiles/Root/{RootFile.cs, LocaleFlags.cs, ContentFlags.cs, RootRecord.cs}`、`SystemFiles/Install/InstallFile.cs`、`SystemFiles/Tags/TagEntry.cs`
- `barncastle/CASCHost`：`README.md` 全文、commit 歷史
- `wowdev/DBCD`：`README.md`
- `Dramacydal/CascOverride`：`CascBP/CascBP.cs`
- metadata 對照：`ladislav-zezula/CascLib`、`WoW-Tools/CASCExplorer`、`Marlamin/wow.export`、`Marlamin/BuildBackup`、`wowdev/WoWDBDefs`
- GitHub repo search（`CASC wow`、`TACT wow`）前 12 筆逐一檢視

**社群 wiki（明確標示非官方）**
- `https://wowdev.wiki/DB2` —— String Block 一節、WDB2–WDC1 各版 header 的 `uint32 locale`
- `https://wowdev.wiki/TACT` —— install / download manifest 與 tag 結構、tag type（`locale = 3`）、build config 欄位
- `https://wowdev.wiki/CASC` —— 本機儲存格式（`.idx` / `shmem` / `data.NNN`）
- `https://wowdev.wiki/DBCache.bin` —— `RecordState::Valid = 1 // overwrites source record`（經 [hotfix 筆記](./hotfix-db2-localization.md)§5.1 引用）

**取用失敗**
- `https://wowdev.wiki/.build.info` —— **404**，該 wiki 沒有這個頁面；`.build.info` 的欄位語意改由 CascLib 原始碼與 client binary 的欄位名字串佐證。
- `gh search repos` CLI 子指令在本機回空結果，改用 `gh api search/repositories` 取得。
