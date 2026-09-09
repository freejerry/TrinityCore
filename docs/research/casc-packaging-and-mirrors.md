# CASC 能不能由 Blizzard 以外的工具「寫」出來？兼社群鏡像的正當用法

> 撰寫日期：2026-09-06
> 相關筆記：[macOS client 取得與執行](./macos-client-options.md)（client 取得牆）、[`wow-patcher` runtime mode 評估](./wow-patcher-runtime-mode.md)（本篇的 `--version-url` / `--cdns-url` 一節是它的延伸）、[hotfix DB2 中文化深度評估](./hotfix-db2-localization.md)、[zhTW 中文化實作記錄與更正](./zhtw-implementation-and-corrections.md)（「鬆散檔案覆蓋可行」的實測來源）、[TrinityCore client 設定與憑證](./tc-client-setup-and-certs.md)
> 來源限定 primary sources：**本機 `/Users/shinichi/World of Warcraft 3.4.3.54261` 的 CASC 逐位元組解剖**（唯讀，Python 直接 parse）、本機 TACTSharp clone（`cc5bf85`）原始碼與其 `git show HEAD:` 的**上游**版本、`wowdev.wiki` 的 `Special:Export` / MediaWiki API 原文、各專案 GitHub 原始碼與 README（`gh api` / `gh search code`）、`archive.wow.tools` 與各鏡像主機的實際 HTTP 回應。
> 凡未實測者一律標示「**未驗證**」。未使用瀏覽器自動化。**本文不記錄任何 game client 或遊戲資料的下載連結**——「某個來源存在」就是本文能講的極限。

---

## 0. 裁決先講

**問題一：能。CASC 可以由 Blizzard 以外的工具寫出來，而且公開專案裡有四個真的在寫。**
但這個「能」有一條沒人驗證過的縫：**四個寫入器沒有任何一個宣稱它的產物被真正的零售 client 開起來過**。其中最誠實的一個（`blizzget`）在自己的 README 裡直說產物「多半不能玩」，要拿去給 Battle.net app 修。

**問題二：把真 client 指向社群鏡像，是鏡像維運者白紙黑字禁止的行為。**
`archive.wow.tools` 首頁「Downloading」段落，原文（**NOT** 是他自己加粗標紅的）：

> **Do NOT use this directly as a CDN for World of Warcraft/Agent/Battle.NET, this is detectable and doing so will ruin the party for everyone and force me to take action/limit downloads.**

我們前一階段做的事——改寫 `.build.info` 的 CDN Hosts 指到本機 proxy、再由 proxy 轉發到 `archive.wow.tools`，讓 client 自己下載 97 個 Range request——**正是這句話禁止的那件事**。它能動不代表它被允許。

**唯一該用的方法**（第 6 節展開）：把鏡像**只給工具吃**（TACTSharp / `wow.tools.local` 這類，這是維運者明講的預期用途），抽成鬆散檔案落到 client 目錄——這條路我們已經實測有效（2,699 張中文貼圖、`_loose_out/`），而且完全不需要 client 碰到鏡像一次。

---

## 1. 本機 CASC 逐位元組解剖（一手，非引用）

先把「格式到底懂到什麼程度」用我們自己的安裝證明一次。以下全部是對
`/Users/shinichi/World of Warcraft 3.4.3.54261/Data/` 直接 parse 出來的，不是抄 wiki。

### 1.1 `Data/data/*.idx`（16 個，各 327,680 bytes）

Header 解出來：

```
hashSize=16  ver=7  bucket=n  extra=0
encodedSizeLength=4  storageOffsetLength=5  encodingKeyLength=9
fileOffsetBits=30    maxFileSize=0xFFC0000000
```

Entry = 18 bytes：`ekey[9]` + 5-byte **big-endian** storage offset + 4-byte **little-endian** size。
`archiveIndex = offset >> 30`，`fileOffset = offset & 0x3FFFFFFF`。16 檔合計 **247,791 筆**。

bucket 推導公式 `b = XOR(ekey[0..8]); bucket = (b & 0xF) ^ (b >> 4)`：

| 結果 | 筆數 |
|---|---|
| 公式命中檔名 bucket | 247,615 |
| 落在 `(bucket+1) & 0xF` | 176 |
| 其他 | **0** |

那 176 筆**全部**是 `size=30`、`offset=0` 的 archive 哨兵列——也就是 wiki 講的 index cross-linking 記錄，其 bucket 規則本來就是 `(bucket+1) % 16`。
**即 247,791 筆 100% 可由公開公式重現，一筆例外都沒有。**

> **與 wiki 的一處出入**：`wowdev.wiki/CASC` 說 `ArchiveTotalSizeMaximum` 是 `0x4000000000`（256 GiB）。我們這份 3.4.3 安裝實測是 **`0xFFC0000000`**。wiki 的值標的是「usually」，此處以實測為準。

### 1.2 `Data/data/data.NNN`（11 個，各 1 GiB 上限）

每筆前置 30-byte header，實測三筆全部逐位元組對上：

```
[0x00..0x10)  ekey 反序右靠（9 bytes 反轉，前 7 bytes 補 0）
[0x10..0x14)  size (LE)
[0x14..0x16)  flags
[0x16..0x1E)  checksum-of-header（8 bytes）
[0x1E..    )  BLTE payload（magic 'BLTE' 已驗）
```

例：idx 第一筆 ekey `00031e3dc341bbb047` → `data.001 @ 783804950 size 3878`，
該 offset 讀出的 header 前 16 bytes 是 `0000000000000047b0bb41c33d1e0300`，反轉後正是同一把 ekey。

### 1.3 `Data/data/shmem`（20,480 bytes）—— **client 會自己重建它**

```
block1 type=5, nextBlock=0x154
  內嵌絕對路徑：/Users/shinichi/World of Warcraft 3.4.3.54261/Data/data/index
  其後 16 個 uint32 = 各 bucket 目前的 .idx 版本號
  實測 0x25,0x26,0x2a,0x25,0x26,0x21,0x27,0x26,0x27,0x22,0x26,0x26,0x28,0x25,0x25,0x28
  ↑ 與 .idx 檔名尾碼（0000000025.idx / 0100000026.idx / 020000002a.idx …）完全一致
block2 type=1, size=552：free-space 表
```

**決定性的一點**：這份安裝原本是 Windows 上的 `D:/Games/World of Warcraft`（見 `.product.db.win`），
搬到 macOS 之後 shmem 裡是**新的 macOS 路徑**。也就是 client 自己重寫了它。
`wowdev.wiki/CASC` 明講「The file is recreated every time a client is started」，
`blizzget` 的 wiki 更直接：「This file does not need to be created when downloading the game data.」
→ **第三方寫入器不必完美產生 shmem。**

### 1.4 `Data/indices/*.index`（1,847 個）—— 是 CDN archive index，不是本機 idx

抽驗 footer（最後 0x1C bytes）：`version=1, blockSizeKB=4, offsetBytes=4, sizeBytes=4, keySizeBytes=16, checksumSize=8, numElements=7060, footerChecksum(8)`。與 `wowdev.wiki/TACT` 的規格一致。

### 1.5 `.build.info` / `.flavor.info` / `.product.db`

`.build.info` 是 BPSV（與 Ribbit 的 `versions` / `cdns` 同一種表格格式）。我們這份實測有 **15 欄**：

```
Branch|Active|Build Key|CDN Key|Install Key|IM Size|CDN Path|CDN Hosts|CDN Servers|
Tags|Armadillo|Last Activated|Version|KeyRing|Product
```

> **注意欄位並非固定**。`blizzget` wiki 記的版本是 14 欄、結尾為 `Keyring|KeyService` 而沒有 `CDN Servers`；`cascette-rs` 的 `build_info.rs` 記的是 14 欄、有 `CDN Servers` 但**沒有** `KeyRing`。三者互不相同。寫入器不能寫死欄位表，必須照抄目標安裝既有的 header 行。

原始（Windows）Tags 只有 `enUS` + `ruRU` 的 speech/text，**沒有任何 zhTW** ——這就是 zhTW 內容不在 CASC 裡的直接證據。

`.product.db` 是 protobuf，且**不屬於遊戲安裝目錄的格式**（Agent 自己的狀態庫）。我們的 `.product.db.win`（519 bytes）與真 macOS 安裝（`/Applications/World of Warcraft/.product.db`，588 bytes）對照：

| | 我們的（Windows 血統） | 真 macOS 安裝 |
|---|---|---|
| install path | `D:/Games/World of Warcraft` | `/Applications/World of Warcraft` |
| locale | `enUS` / `ruRU` | `zhTW` |
| region / geoip | `us` / `UKR` / `UA` | `TWN` / `TW` |
| Tags | `Windows x86_64 EU? …` | `OSX x86_64 KR? … zhTW speech/text` |
| **版本** | `3.4.3.54261` | **`5.5.4.69585`** |

最後一列值得停一下：**`wow_classic` 這個 product code 現在指向的是 MoP Classic 5.5.4**。3.4.3 不是「另一個產品」，是同一條產品線上一個已被下架的歷史 build。Battle.net 沒有「安裝舊版」這個選項。

---

## 2. 格式文件化到什麼程度：夠寫，但有幾個軟點

`wowdev.wiki/CASC`（最後編輯 2026-02-19）與 `wowdev.wiki/TACT`（2026-08-15）兩頁都仍在維護。
兩頁**加起來**把寫入需要的東西都寫了：BLTE 框架與全部編碼模式、30-byte record header 連 ChecksumA/ChecksumB 的完整 C 實作（含從 Agent.exe 8020 抽出的常數表）、`.idx` 的 bucket 函式與 v7 header 與 entry packing（兩個 Jenkins `hashlittle2` 檢查碼）、CDN `.index` 的 footer-hash-of-zeroed-footer 規則、config 檔的 key/value 字彙。

> 用詞更正：`.idx` 的兩個檢查碼是 **Jenkins hashlittle2**，不是 TrimmedMD5。截斷 MD5 是 CDN 端 `.index` 在用的，兩者不同層。

wiki **自己標為未知或會變動**的部分：

| 位置 | wiki 原話 |
|---|---|
| data.NNN header `0x14` 兩 bytes | `Flags??` … "**Unknown.** Mostly 0." |
| data.NNN ChecksumB | "**The exact algorithm seems to vary over time.**" |
| 16 個 cross-linking 記錄 | "**The purpose of these files is unclear.**" |
| shmem DataNumber 語意 | "Before Agent v8012? this was always set to 0…" |
| Patch Config 整段 | "**The structure and purpose of all of the fields of this file requires further research.**" |

**沒寫在 wiki 上、只存在於實作原始碼裡的**：`.idx` 只保留最新兩個版本的淘汰規則（CascLib `src/CascIndexFiles.cpp` 的註解 `// Note: WoW6 only keeps last two index files`）。

**一處未解的一手矛盾**：`blizzget` wiki 說 data.NNN header 的 `0x14..0x1E`（也就是 flags + 兩個 checksum）「**Setting this to zeroes seems to work fine**」，而 wowdev.wiki 給了那十個 bytes 的完整演算法。兩邊可以同時為真（client 未必驗），但**現行 3.4.3 client 到底驗不驗，未驗證**。

`.product.db` 的 protobuf schema 是**完全公開**的：`overtools/TACTLib` 的 `TACTLib/Agent/Protobuf/ProtoDatabase.cs` 內嵌完整 base64 `FileDescriptorProto`（package `proto_database`），可直接 decode 出 `Database` / `ProductInstall` / `BaseProductState` / `UserSettings` 等全部 message 與欄位號。另有 `TinkoLiu/blizzard-product-parser` 為第二來源。→ **合成 `.product.db` 在技術上沒有障礙。**

---

## 3. 誰能寫、誰只能讀（逐專案裁決）

| 專案 | 語言 | 裁決 | 證據 |
|---|---|---|---|
| `ladislav-zezula/CascLib` | C++ | **唯讀** | `src/CascLib.h` 全部是 `CascOpenStorage` / `CascOpenFile` / `CascReadFile` / `CascFindFirstFile`。**`CascCreateStorage`、`CascAddFile`、`CascWriteFile` 不存在。** README：「library for **reading** Blizzard's CASC storages」 |
| ↑ 同作者 `StormLib`（對照組） | C++ | **可寫** | `SFileCreateArchive` / `SFileCreateFile` / `SFileWriteFile` / `SFileAddFile` / `SFileCompactArchive` 一應俱全。**同一個人寫了 MPQ 的建立、沒寫 CASC 的建立**——這個不對稱本身就是答案 |
| `wowdev/TACTSharp` + `TACTTool` | C# | **唯讀** | 本機 clone 實地 grep：`IndexInstance` / `CASCIndexInstance` / `RootInstance` / `EncodingInstance` / `InstallInstance` 全部 `MemoryMappedFileAccess.Read`；`BuildInfo.cs` 只有 `File.ReadAllLines`。唯一的寫入是自己的 cache 目錄與 `TACTTool` 的鬆散輸出。**無 `.idx` / shmem / data.NNN 寫入路徑** |
| `Marlamin/BuildBackup` | C# | **唯讀**（產出 CDN 形狀的鬆散鏡像，非容器） | `Program.cs` grep `build.info` / `.idx` / `Data/data` **零命中**。README 首句即「no longer actively supported」 |
| `Marlamin/wow.tools.local` | C# | **唯讀** | `Services/CASC.cs` 是 TACTSharp 的消費者；只寫 `temp/<build>/<fdid>` |
| `WoW-Tools/CASCExplorer` + `WoW-Tools/CascLib` | C# | **唯讀** | `LocalIndexHandler.cs` 以 `FileMode.Open, FileAccess.Read` 開 `.idx`；`InstallHandler` / `DownloadHandler` 只**解析** manifest，不套用 |
| `overtools/TACTLib` | C# | **唯讀** | repo description 自述「for **reading**」；`ContainerHandler.cs` 用 `FileAccess.Read, FileShare.Read` |
| `Burralis/Game-Launcher`（Arctium 血統） | C# | **不適用** | 不是 CASC 工具，是 runtime memory patcher。全樹 grep `CASC` / `build.info` **零命中** |
| **`d07RiV/blizzget`** | C++ | **可寫（下載 CDN → 產出安裝目錄）** | wiki 開宗明義：「only contains **the information required to write the files downloaded from the Blizzard CDNs**」 |
| **`FernandoS27/WhiteoutLib`** | C++ | **可寫（從零建容器）** | README：「CASC reading *and writing* are implemented in-house」。`storage_writable.h` 有 `create()` / `writeFile()` / `save()`；`writer.cpp` 實際寫 archive、`.idx`、config、**`.build.info`**、`shmem`。自述 **beta** |
| **`ldmonster/go-casclib`** | Go | **可寫（從零建容器）** | `pkg/casc/flush.go`：BLTE 編碼 → `data.NNN` → INSTALL/ENCODING manifest → V1 `.idx` → `Data/config/<aa>/<bb>/<hex>` → `.build.info` |
| **`wowemulation-dev/cascette-py`** | Python | **可寫（Ribbit+CDN → 完整安裝，不經 Agent）** | `cascette install product`；`core/local_storage.py` 有 `LocalIndexEntry.to_bytes` / `LocalIndexHeader.to_bytes` / `_write_empty_index` / `flush_indices`，`.idx` 命名 `f"{bucket:02x}{generation:08x}.idx"`（V7 與 V8/KMT 都有）；`formats/build_info.py` 有 `BuildInfoParser.build()`；`core/shmem.py` 支援 `--shmem-version {4,5}` |
| `wowemulation-dev/cascette-rs` | Rust | **半可寫**（能改既有容器，不能從零起） | `cascette-client-storage/src/installation.rs` 有 `write_file(...) -> ContentKey`；crate 文件寫「**Dynamic Container**: Read-write CASC archives」。但 `build_info.rs` 只有 parser，**沒有 writer** |

**負面搜尋結果**（重要，說明這三個寫入器為什麼沒人知道）：`gh search repos` 對 `"casc packer"` / `"casc writer"` / `"ngdp install"` / `"tact install"` **全部零命中**；`gh search code` 對 `CascCreateStorage` / `CascAddFile` 全 GitHub 只命中 `go-casclib`。它們不會出現在任何人會直覺搜的關鍵字下面。

### 3.1 這個「能」的縫在哪

**沒有任何一個寫入器宣稱它的產物被真正的零售 WoW client 開起來過。**

- `blizzget` README 自述：產物「will most likely **not be playable**, but can be used for datamining and such - if you're going to try to play the game, make sure you run it through battle.net app **so it can fix the possible inconsistencies**」，且「**incapable of patching**」。
- `go-casclib` 的驗證標準是自己：「The output is round-trippable: **OpenStorage** can re-open the directory」——對自己閉環，不是對 client。
- `cascette-py` 把「Produce a local CASC installation readable by game clients」寫在 `docs/full-installation-execution-plan.md` 裡，是**目標**不是成果；同 repo 的 `docs/install-workflow-differences.md` 誠實列出與真 Agent 的差異。
- `WhiteoutLib` 自標 beta。

→ **「結構完整」與「client 開得起來」是兩個不同的主張，目前只有前者有證據。**

### 3.2 順帶更正兩個看 README 會看錯的地方

1. `go-casclib` 的 `write.go` 檔頭註解**是過期的**，說 `Flush` 會回 `ErrNotSupported`、`CreateStorage` 只有記憶體。但 `flush.go` 已經把整條 on-disk pipeline 實作完了，`ErrNotSupported` 只在用 `OpenStorage`（唯讀）開啟時才回。只讀 `write.go` 會得到相反的結論。
2. `cascette-rs` 頂層 README 低估了自己——特性列表只寫「Local CASC storage (…)」沒說可寫，crate 層文件才寫「Read-write CASC archives」。

### 3.3 有沒有人講過「第三方做不出來」

**沒有找到任何一句這樣的話。** 最接近的是 `WowDevTools/CASCHost` 的範圍聲明：「For those wanting to create CAS from scratch, have their own build pipeline or want a MPQEditor style tool, **you will need to find another solution**」——這是在講 CASCHost 自己不做，不是在講做不到。

---

## 4. 有沒有「不經 Battle.net Agent 安裝」的路

有三條，成熟度差很多。

**(a) 純第三方安裝器** —— `cascette-py install product` 與 `blizzget`。完全不碰 Agent，直接 Ribbit + CDN 拉下來鋪成安裝目錄。成熟度見 §3.1。

**(b) 驅動 Agent 本身（逆向，非官方支援）** —— `wowdev.wiki/Agent`（自述對 Agent.exe build 9370 / TACT 3.13.3 驗證過）記載得意外詳細：

- Agent 綁 `127.0.0.1`，`--port=` 預設 **1120**，是 **JSON over HTTP REST**（不是 JSON-RPC），由 `agent::HttpJsonRouter` 22 個 handler 提供。
- 端點：`/install`、`/install/{product}`、`/update/{product}`、`/register`、`/uninstall`、`/repair`、`/size_estimate`、`/game`、`/version`、`/admin_command` 等。
- `/install` 的 POST body 有 **`instructions_patch_url`** 一欄（wiki 範例值形如 `http://eu.patch.battle.net:1119/<product>`）——**這是 per-request 的版本服務 / CDN 覆寫**，不必動 Agent 的全域設定。
- 命令列另有 **`--version_server_url=`**（覆寫版本服務 URL）與 `--summary_seqn_override=`。

**兩個未驗證的關鍵點**：現行 build 的這個 API 要不要 auth token（某些 build 有 `--nohttpauth` 旗標，但 9370 沒有）；以及 Agent 已經改走 Ribbit V2 / TACT Channels 之後，`instructions_patch_url` 是否還被尊重。

**(c) 不接觸版本服務** —— 這是我們現在的狀態，也是最穩的。`wowdev.wiki/TACT` 原話：

> "Both of these files are written by the Battle.net agent and not by the clients themselves. **However, if these two files are available the clients will use cached information in the `.build.info` file instead of getting it from remote.**"

一個已經物化完成的安裝**根本不會去問任何版本服務**。

---

## 5. 鏡像是給誰用的：維運者自己怎麼說

| 主機 | HTTP | 是什麼 |
|---|---|---|
| `wow.tools` | 200 | 只剩退役公告：「The box that the old wow.tools site was on has been retired as of May 2025.」署名 Marlamin |
| `archive.wow.tools` | 200 | 本體。「WoW.tools started as an **archival project** for CDN data for all WoW builds starting at 6.0.」約 3.2 TB，`tpr/wow/...` 結構與官方 CDN 相同 |
| `casc.wago.tools` | **403**（root） | 只按確切路徑供檔，無索引、無 about、**無任何公開政策** |
| `cdn.arctium.tools` | 200 | body 就是 `eu` 兩個字。無政策 |
| `ngdp.arctium.io` | 200 | body 就是 `eu-central`。無政策 |
| `arctium.tools`（apex） | 連不上 | 只有 `cdn.` 子網域活著 |

### 5.1 唯一存在的使用規範，是 Marlamin 的，而且很明確

`archive.wow.tools` 首頁「Downloading」（**NOT** 為原文加粗標紅）：

> **Do NOT use this directly as a CDN for World of Warcraft/Agent/Battle.NET, this is detectable and doing so will ruin the party for everyone and force me to take action/limit downloads.**

緊接著：

> **NOTE:** When downloading, I would prefer if you checked if the file still exists on original CDNs (e.g. `cdn.blizzard.com` or `level3.blizzard.com`) first, if so, these won't have integrity issues and will also lessen the load on this server.

「Rehosting」段：

> Feel free to rehost the CDN files, but keep in mind that as per Blizzard's policy, rehosting patch data is only fine **provided it isn't modified**. Modifying it also goes out of bounds of this project's archiving goal, so I don't condone that.

**預期用途是「給工具吃」，這也是他自己寫的**：

> "To back up a specific build, you can modify **BuildBackup** … to add `archive.wow.tools` to the CDN list…"
> "How to extract files from CDN data — Because the archive contains raw CDN data, your best bet is to locally host it and then modifying tools like **CASCExplorer or BuildBackup** to add your local CDN…"

### 5.2 「Please contact me if you are mirroring」——證實，但先前的引述被截斷了

原文在頁面最底「Community mirrors」段：

> Please contact me if you are mirroring any of WoW.tools's files **so you can be added to the list.**

補上後半句意思就變了：這是**邀請你被列進鏡像清單**，不是使用的許可門檻。清單本身列出：`casc.wago.tools`（maintained）、`cdn.arctium.tools`（maintained）、`reliquaryhq.com`（unknown）、`GW2Archive.eu`（限 DBC/DB2/GameTable/Interface）。

注意 Marlamin 把 wago 與 Arctium 稱為 **3rd-party mirrors**——**`casc.wago.tools` 不是 Marlamin 經營的**。因此他的政策文字在形式上不拘束 wago 與 Arctium；但那兩家什麼都沒公告，合理推定同一社群規範。

### 5.3 聯絡管道（皆為維運者自己公開的）

- **Marlamin**：BlueSky `bsky.app/profile/marlam.in`、blog `blog.marlam.in`、GitHub `@Marlamin`。網站上未公開 email。
- **Arctium**：Discord `arctium.io/discord`。Legal Notice 載明 Arctium / Fabian König（德國 Emsbüren），但 email 在 HTML 裡是混淆佔位符，實際位址未公開。
- **wago.tools**：伺服器端未公開任何聯絡方式；站上有 `/feedback` 路由，應為預期管道。**經營者身分未由一手來源證實。**

### 5.4 wowdev.wiki 對鏡像的態度

`wowdev.wiki/TACT` 全文 grep `mirror` / `wago` / `arctium` / `archive.wow.tools` —— **零命中**。它只記官方主機。archive.wow.tools 會連出去指向 wiki 當格式文件，wiki 不回指、不背書任何鏡像。

### 5.5 工具的預設值透露的事

- `Marlamin/wow.tools.local` `SettingsManager.cs`：`additionalCDNs` 的 `DefaultValue = "casc.wago.tools,cdn.arctium.tools,archive.wow.tools"`。**確實內建**。
- `wowdev/TACTSharp` **沒有**內建鏡像清單。上游 `Settings.cs` 是 `AdditionalCDNs = []` 且 `BlockedCDNs = []`，鏡像靠 `--cdns` 旗標 opt-in。
  > ⚠️ 我們本機這份 clone 的 `Settings.cs` **被改過**（`BlockedCDNs` 被填入六個官方主機並加了中文註解）。引用時勿把它當上游行為。
  但上游 `TACTSharp.Tests/ExtractionTests.cs:15` 確實寫著 `build.Settings.AdditionalCDNs.AddRange("casc.wago.tools", "cdn.arctium.tools");`——**上游的測試套件自己就在打這兩個鏡像**。
- 上游 `CDN.cs:103` 有一行註解：`// TEMP: Penalize Akamai for having missing files as of November 2025`。官方 CDN 有洞是上游已知的問題。
- `cascette-ribbit` 與 `wow-patcher` 都把 `cdn.arctium.tools` / `cdn.arctium.io` 當**預設** CDN。

---

## 6. 跑一個已下架的舊 build，「正確方法」是什麼

### 6.1 協定端：自架 versions / cdns 是標準做法，而且已經有現成實作

`wowdev.wiki/TACT` 與 `wowdev.wiki/Ribbit` 把端點寫得夠實作一台伺服器：

| 舊（現為 Ribbit V2 的 proxy） | 新 |
|---|---|
| `http://us.patch.battle.net:1119/(product)/versions` | `https://us.version.battle.net/v2/products/(product)/versions` |
| `.../cdns` | `.../v2/products/(product)/cdns` |
| `.../bgdl` | `.../v2/products/(product)/bgdl` |

CDN 物件路徑：`http://(cdnsHost)/(cdnsPath)/(pathType)/(前兩碼)/(第三四碼)/(完整 hash)`，`pathType ∈ config|data|patch`。
Ribbit 走 TCP **1119**，指令以 `\r\n` 結尾；**V1 是 MIME multipart + PKCS#7 簽章 + SHA-256 checksum，V2 是裸 BPSV 靠 HTTPS**。wiki 記：V1 **2025 年已 deprecated**，V2 為 2026-02 起 Agent 與多數遊戲的預設。

> **再上一層的變化**：2026-08-07 起 Battle.net app 已改用 **TACT Channels**（`distribution.version.battle.net`，JSON 而非 BPSV）。我們本機 TACTSharp 的 `VersionServices/TACTChannels.cs` 正是打這個。**目前沒有任何 Ribbit server 實作涵蓋 TACT Channels。**

**現成實作**：`wowemulation-dev/cascette-rs` 的 `cascette-ribbit` crate。README 原話：

> **Ribbit Server** — A Ribbit protocol server for hosting and distributing custom game builds. Intended for mod developers and private server operators who need to serve their own content to clients.

TCP v1/v2 + HTTP handler 都有；`--tcp-bind`（預設 `0.0.0.0:1119`）、`--http-bind`、`--builds`（一個 JSON 檔，逐 build 指定 `product/version/build/build_config/cdn_config/product_config/keyring`）、`--cdn-hosts`（**預設 `cdn.arctium.tools`**）、`--cdn-path`（`tpr/wow`）、`--tls-cert`/`--tls-key`。
**`builds.json` 就是「釘住任意舊 build」的機制。** 但它自己的文件註明：「The server does not include PKCS#7 signatures (unlike Blizzard's production servers).」

> **更正三個前提**：`cascette-rs` **沒有** `ribbit-client` / `tact-client` / `ngdp-cdn` 這幾個 crate（已整併改名為 `cascette-*`）。`Arctium/bnet-tact-channel` **存在但是個鏡像不是伺服器**（自述「Mirror of Blizzards distribution version service… Files are stored as-is and named by the MD5 of their content」）。**`HearthSim/keg` 不存在**——該 org 全部約 101 個 repo 列舉過，沒有 `keg` / `ngdp-*` / `casc` / `tact`。

其他：`BlizzTrack/ribbit-server`（Go，是 proxy/archiver，最後推送 2020-04-04）、`erorus/ribbit.sh`。`gh search repos` 對 `"ngdp server"` / `"tact server"` 零命中——**`cascette-ribbit` 實質上是唯一在維護的伺服器。**

### 6.2 Client 端：兩個獨立的重導向機制（皆已在原始碼證實）

| 工具 | 旗標 | 方式 | 適用 |
|---|---|---|---|
| `wowemulation-dev/wow-patcher` | `--version-url` / `--cdns-url`（`src/cli.rs`，global，驗證需 `http(s)://` 且 ≤512 字元） | **落地改檔**，跨平台 | 1.13–1.14 / 2.5 / **3.4** / 4.4 |
| `Burralis/Game-Launcher` | `--versionurl` / `--cdnsurl` / `--product` / `--region`（`src/LaunchOptions.cs`） | **記憶體 patch**，僅 Windows，不持久 | Mainline 10.1.5+ / Classic 3.4.2–5.5.3 等 |

`Game-Launcher` 的 README 直接回答了這一節的題目：

> - **Allow custom client version & cdn urls**
>   **Useful for launching older clients or serving data from your own CDN**

兩者都同時 patch RSA modulus / 憑證，這正是「未簽章的自架 Ribbit server 為何 client 會收」的原因。
`wow-patcher` 的 `docs/src/configuration.md` 另有一句要注意：「Newer WoW clients use a unified version API. If detected, the patcher uses the v3 pattern and **ignores the separate CDNs URL**.」

### 6.3 但協定不是瓶頸

`wowdev.wiki/TACT` 自己寫：「Blizzard regularly cleans old builds from the CDN so any example files mentioned in this article might be unavailable at the time of reading.」
`Marlamin/BuildBackup` README：「**Blizzard often removes data for older builds from their CDN, making them unavailable for install.**」——然後緊接著是它自己的停止維護聲明。
`cascette-rs` 與 `wow-patcher` 的贊助目標都列著「**Public CDN mirror** — Host a community mirror for World of Warcraft builds」——**那是願景，不是既存服務。**

**沒有任何協定技巧能救回已被刪除的 blob。** 舊 build 能不能跑，取決於有沒有人事先存下來。

---

## 7. 對本案的裁決

我們的處境其實比上面所有情境都好：**3.4.3.54261 的完整安裝已經在手上、已經物化完成、已經玩得動。**
缺的只有 zhTW 這一批 locale 檔（因為原始 Windows 安裝的 Tags 只勾了 enUS + ruRU）。

排掉不該做的：

| 路線 | 裁決 |
|---|---|
| 改 `.build.info` 把 client 指向鏡像（我們前一階段做的） | **停用**。維運者白紙黑字禁止，且自述可偵測 |
| 用 `blizzget` / `WhiteoutLib` / `go-casclib` / `cascette-py` 重建整個 CASC | 過度。要重灌 15 GB 去換幾十 MB 的 zhTW 檔，且沒有任何一個寫入器驗證過產物能開機（§3.1） |
| 自架 `cascette-ribbit` + 重新安裝 | 過度。我們不需要重裝，只需要補檔 |
| 手寫 `.idx` / data.NNN 把 zhTW 檔塞進既有 CASC | 技術上有路（§1 證明格式全懂），但 ChecksumB 是否被驗未驗證（§2），而且**下一條路完全不需要它** |

### 建議的唯一方法

**用 TACTSharp（工具，非 client）向鏡像取 zhTW 檔，抽成鬆散檔案落到 client 目錄。**

1. `TACTTool` 以 `-d` 讀本機 CASC、`--cdns casc.wago.tools,cdn.arctium.tools,archive.wow.tools` 補缺口，`-m fdid` 或 `-m name` 抽出 zhTW 的 DB2 / 字型 / 貼圖。這**正是** Marlamin 明講的預期用途（「modifying tools like CASCExplorer or BuildBackup to add your local CDN」）。
2. 產物是鬆散檔案，直接放進 client 目錄——**這條路我們已經實測有效**（2,699 張中文地圖貼圖已生效，見 [zhTW 實作記錄](./zhtw-implementation-and-corrections.md) 與 [世界地圖標籤](./worldmap-label-localization.md) 的更正欄）。
3. `.build.info` 的 CDN Hosts **改回官方主機**（`.build.info.win.bak` 裡有原值），client 從此不再對外連任何 CDN——反正 §4(c) 說了，物化完成的安裝根本不問版本服務。
4. 依 Marlamin 的請求：能在官方 CDN 拿到的檔就先打官方，鏡像只補官方沒有的。3.4.3 的情況是官方全 404，所以實際上都會落到鏡像——這時**流量克制**就是唯一能盡的義務：抽完就停，別當常駐 CDN。

一句話：**鏡像給工具吃，不給 client 吃。** 這是既合規、又剛好是我們已經驗證過可行的那條路。

---

## 8. 未驗證項清單

- 現行 3.4.3.54261 client 是否真的驗證 data.NNN header 的 ChecksumA / ChecksumB（wowdev.wiki 給了演算法，`blizzget` 說填 0 也行，兩邊未調和）
- 四個 CASC 寫入器（`blizzget` / `WhiteoutLib` / `go-casclib` / `cascette-py`）的產物是否能被零售 client 開起來——**沒有任何一個 repo 有這樣的宣稱、測試或 issue**
- 它們是否處理 Armadillo / 加密產品
- Agent 本機 API（port 1120）在現行 build 是否要求 auth token
- Agent 改走 Ribbit V2 / TACT Channels 之後，`/install` 的 `instructions_patch_url` 是否還被尊重
- 真實 client 是否接受 `cascette-ribbit` 未附 PKCS#7 簽章的 V1 回應（推測需搭配 §6.2 的二進位 patch）
- BPSV 的 `## seqn = N` 行位置：wiki 範例放在 header 之後、資料列之前；`cascette` 文件放在結尾。兩種都在野外出現過
- `casc.wago.tools` 的經營者身分（SPA 無伺服器端渲染，無法由一手來源證實）
- 16 個 cross-linking 記錄在 3.4.3 上的實際語意（wiki 自承「purpose is unclear」）
