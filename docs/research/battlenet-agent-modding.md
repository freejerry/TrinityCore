# 能不能改造／逆向 Battle.net Agent（Agent.exe）去裝指定舊版、指向自架 CDN？

> 撰寫日期：2026-09-07
> 相關筆記：[CASC 能不能由 Blizzard 以外的工具「寫」出來？兼社群鏡像的正當用法](./casc-packaging-and-mirrors.md)（本篇的母文件——那篇把「容器怎麼被讀寫」與「鏡像給誰用」解剖完了，其 §4(b) 就是本篇的種子）、[怎麼逼客戶端重跑那次 CDN 同步](./casc-resync-reset.md)（client 自己 on-demand streaming 那條路，與本篇的 Agent 路互為對照組）、[`wow-patcher` runtime mode 評估](./wow-patcher-runtime-mode.md)（`--version-url` / `--cdns-url` 重導向）、[macOS client 取得與執行](./macos-client-options.md)（client 取得牆）、[TrinityCore client 設定與憑證](./tc-client-setup-and-certs.md)
> 來源限定 primary sources：`wowdev.wiki` 的 **Agent**、**Ribbit**、**TACT**、**CASC**、**NGDP** 五頁（以 MediaWiki API `action=parse&prop=wikitext` 抓原文，非二手轉述）、各 GitHub repo 的原始碼與 README（`gh api` / `gh search code` 直讀）、`archive.wow.tools` 等鏡像的實際 HTTP 回應（已在母文件記錄）。凡未在一手來源找到者一律標「**未驗證**」。未使用瀏覽器自動化。**本文不記錄任何 client 或遊戲資料的下載連結**。

---

## 0. 裁決先講

**問題（本案）：把真正的 Battle.net Agent 重導向到自架／鏡像 CDN，逼它裝一個已下架的舊 build（例如 WoW Classic 3.4.3.54261），是不是一條比「客戶端自己 streaming」更便宜的路，去拿到一份完整可玩的 CASC？**

**答案：不是。是更貴、更脆、且有多個未驗證的縫的路。除非你的目標剛好是「要一份由『真 Agent』寫出來、保證 client 開得起來的 CASC」，否則不值得走。**

三句話交代為什麼：

1. **協定層是通的、也真的有人做過。** Agent 綁 `127.0.0.1:1120`，是 JSON over HTTP REST，`/install` 的 request body 有一欄 **`instructions_patch_url`**——這就是 per-request 的版本服務／CDN 覆寫點。而且有一個 **252 star、維護到 2025 的現成工具 `barncastle/Battle.Net-Installer`**，原始碼裡就是照這個流程驅動 Agent 裝遊戲。**「驅動 Agent」不是理論，是既存事實。**

2. **但它裝不了下架的舊 build。** `barncastle/Battle.Net-Installer` 的 README 白紙黑字：「only (green) **Active** products will work」。Agent 會去問版本服務（Ribbit），版本服務只認官方「現行 active」的版本；3.4.3 早已不 active（母文件已證實 `wow_classic` 這個 product code 現在指向 MoP Classic 5.5.4）。要騙過這點，你得**自架一台 Ribbit／TACT Channels 版本服務**回你自己的舊 build config——這一步的簽章／整合性檢查在現行 Agent 上**沒人驗證過**（見 §5）。

3. **就算協定全騙過，CDN 上的 blob 還是得存在。** 這跟客戶端 streaming 撞同一面牆：Blizzard 定期刪舊 build 的 CDN 資料（`Marlamin/BuildBackup` README 原話）。Agent 路**沒有任何協定技巧能救回已被刪的 blob**——舊 build 能不能裝，取決於有沒有人事先存下來，跟走不走 Agent 無關。

**Agent 路唯一無可取代的價值**：它是**唯一保證產物能被零售 client 開起來的 CASC 寫入器**（因為就是真 Agent 寫的）。母文件 §3.1 證明過：四個社群 CASC 寫入器**沒有任何一個**宣稱產物被真 client 開起來過。所以「若能把真 Agent 餵一份舊 build」→ 你會得到一份貨真價實的 CASC。這是它的全部誘因。但上面三道牆讓這個「若」非常貴。

**對本案：** 我們手上 3.4.3 的完整 CASC **已經物化、已經可玩**（母文件 §7），缺的只有 zhTW locale 檔。**動 Agent 對這個目標是零收益**——它是「從零安裝一個 build」的工具，不是「補幾十 MB locale 檔」的工具。既定路線（TACTSharp 抽鬆散檔）不變。本篇的價值是**把「Agent 路為什麼不划算」查到一手證據為止、封掉這條分支**。

---

## 1. Battle.net Agent 是什麼、本機 API 長怎樣（一手：wowdev.wiki/Agent）

`wowdev.wiki/Agent`（頁面自述 **verified against Agent.exe build 9370 / TACT 3.13.3**，這是它唯一標的逆向基準，其他 build 差異另立表）記載得意外完整。原文摘要：

> Agent (Agent.exe) is a standalone process launched by the Battle.net desktop application to manage game installations. It handles installing, updating, repairing, and uninstalling game products via the TACT content delivery system and stores game data in CASC archives. … exposes a local HTTP REST API (default port 1120).

- **綁定**：`127.0.0.1`，port 由 `--port=` 指定（**預設 1120**，注意不是 1119；1119 是 Ribbit）。port 號透過 Win32 named file mapping `Global\Battle.netHelperSvcPortObject` 公告給 Battle.net app 發現。啟動時 log 的 base URL 是 `http://127.0.0.1:{port}`。
- **授權**：**所有請求都要帶 `Authorization` header（session token）**。User-Agent 用 `phoenix-agent/1.0`。token 的取得方式是先 GET `/agent`，從回應的 `authorization` 欄拿。router 有 5 個授權 callback，會驗**呼叫者的數位簽章、process ID、session 資料**；失敗回 HTTP 403。
  > ⚠️ 這是本案第一道實務牆：token 不是憑空生的，是**由一個已登入的、真的 Battle.net app 產生**的。你不能只跑 Agent.exe 就自己發 token（除非用 `--nohttpauth`，但 build 9370 **沒有**這個旗標，只在其他 build 觀察到）。
- **JSON 解析**：`nlohmann::json` v3.11.2。共用欄位 `uid`（product 識別碼）、`priority`（預設 700）。

### 1.1 22 個端點，本案只在乎這幾個

`agent::HttpJsonRouter` 註冊 22 個靜態端點，另有 `/install/{product}` 這類 per-product 子端點在 runtime 動態註冊。與本案相關的：

| 端點 | 作用（wiki 原文摘要） |
|---|---|
| `/agent` GET | 拿 authorization token、version、region、session |
| `/install` POST | **註冊一個新 product 待安裝**（還沒真的開始下載） |
| `/install/{product}` POST | 真正把安裝排進佇列（帶 `game_dir` / `language` / `finalized`） |
| `/install/{product}` GET | 查安裝進度（`progress` / `download_total` / `state`…） |
| `/register` POST | 用 TACT CDN URL + 安裝目錄註冊 product |
| `/update/{product}` POST | 開始更新 |
| `/repair` `/repair/{product}` | 修復（重掃缺檔補下載） |
| `/backfill` `/backfill/{product}` | 「product 可玩後於背景補下載剩餘資料」 |
| `/size_estimate` POST | 估算安裝大小，內部用 `"sz"` size manifest；欄位含 `encryption_key` |
| `/version/{product}` GET | 回 versions 檔（JSON 化） |
| `/admin_command` POST | 需 `--allowcommands`；「Actual command structure is unknown」 |

### 1.2 決定性的一欄：`instructions_patch_url`

`/install` POST 的 wiki 範例 body（**逐字**）：

```json
{
    "instructions_dataset" : [ "torrent", "win", "wow_classic_beta", "enus" ],
    "instructions_patch_url" : "http://eu.patch.battle.net:1119/wow_classic_beta",
    "instructions_product" : "NGDP",
    "monitor_pid" : 12345.0,
    "priority" : { "insert_at_head" : false, "value" : 900.0 },
    "uid" : "wow_classic_beta"
}
```

`/register` POST 也有同一欄：

```json
{
  "uid": "wow_enus",
  "instructions_patch_url": "http://eu.patch.battle.net:1119/wow",
  "instructions_product": "NGDP",
  "install_dir": "C:\\Program Files (x86)\\World of Warcraft",
  "region": "eu"
}
```

**`instructions_patch_url` 就是「這次安裝去哪台版本服務問 versions/cdns」的 per-request 覆寫點。** 把它從 `http://eu.patch.battle.net:1119/...` 改成 `http://127.0.0.1:1119/...`（指向自架 Ribbit server），理論上就能叫 Agent 去你的服務問版本。**這是整條「重導向 Agent」路的技術核心，而且它就寫在公開 wiki 上。**

命令列另有全域覆寫：**`--version_server_url=`**（覆寫版本服務 URL）、`--summary_seqn_override=`（強制重抓版本資料）。以及 `--skipupdate`（跳過自更新）、`--allowcommands`（開 `/admin_command`）。

### 1.3 Agent 自己也是一個 TACT product

產品表裡 `bna` = **Battle.net Agent (self-update)**。Agent 會自我更新（除非 `--skipupdate`）。這代表**你很難把 Agent 釘在某個「已知可騙」的舊 build 上**——它預設會把自己升級到現行版，而現行版的協定行為（Ribbit V2 / TACT Channels）與 wiki 逆向的 9370 可能已不同（見 §2、§5）。

---

## 2. 版本服務協定：Ribbit（一手：wowdev.wiki/Ribbit）

Agent 透過 `instructions_patch_url` 連上的，就是 **Ribbit**（NGDP 的版本發現元件）。一手重點：

- **傳輸**：TCP port **1119**，host `us.version.battle.net` / `eu.version.battle.net`（舊的 `us.patch.battle.net:1119` 現在是 proxy）。指令以 `\r\n` 結尾。
- **指令**：`v1/summary`、`v1/products/{product}/versions`、`.../cdns`、`.../bgdl`、`v1/certs/{hash}`、`v1/ocsp/{hash}`；V2 對應 `v2/...`（其中 **`v2/products/{product}/cdns` 標註 NYI**）。
- **V1 vs V2（本案關鍵）**：
  - **V1**：MIME 格式，內含一段 **ASN.1 / PKCS#7 base64 簽章**（SubjectKeyIdentifier，可從 certs 端點取完整憑證驗真），每則訊息結尾一行 **SHA-256 checksum**。「to ensure message validity and **prevent MITM attacks**」。**V1 於 2025 年 deprecated。**
  - **V2**：只回實際內容、**不含 V1 那層 metadata/簽章**，改**靠 HTTPS 做密碼學**（`https://us.version.battle.net/v2/...`）。「as of February 2026 this is the default for Agent and several games.」
  - **再上一層**：「**As of August 2026, the Battle.net app has also used TACT Channels instead of Ribbit for version discovery.**」（母文件記載其 host 為 `distribution.version.battle.net`，JSON 而非 BPSV。）
- **序號**：`summary` 給每個 endpoint 一個 seqn；「Sequence numbers never go down… rollbacks will also increase sequence numbers」——即**你沒辦法用「降序號」把 Agent 騙回舊版**，只能靠自架服務直接回舊 config。

**這段對本案的意義**：要騙 Agent 裝舊 build，你得**自架一台版本服務**回你的舊 build_config/cdn_config。母文件 §6.1 已查明現成實作是 `wowemulation-dev/cascette-rs` 的 `cascette-ribbit` crate（TCP v1/v2 + HTTP，`builds.json` 釘任意舊 build，預設 CDN `cdn.arctium.tools`）。**但它自己文件註明「does not include PKCS#7 signatures (unlike Blizzard's production servers)」**——這正是下面 §5 未驗證的核心。

---

## 3. 有沒有人真的驅動過 Agent？有，一手證據

**`barncastle/Battle.Net-Installer`（C#，252★，維護到 2025-08，Windows only）** 就是幹這件事的工具。它不是逆向筆記，是可跑的 code。README 原話：

> A tool for installing, updating and repairing games via Blizzard's Battle.net application. … **Battle.net must be installed, up to date and have been recently signed in to.**

`Program.cs` 的主流程（**逐字**節錄，一手）：

```csharp
await app.AgentEndpoint.Get();                       // GET /agent 拿授權 token
app.InstallEndpoint.Model.InstructionsPatchUrl =
    $"http://us.patch.battle.net:1119/{options.Product}";  // ← 就是這一欄
app.InstallEndpoint.Model.Uid = options.UID;
await app.InstallEndpoint.Post();                    // POST /install 註冊
app.InstallEndpoint.Product.Model.GameDir = options.Directory;
await app.InstallEndpoint.Product.Post();            // POST /install/{product} 開跑
// 之後輪詢進度
```

**這證明了三件事**：

1. 母文件 §1.2 講的 Agent 本機 API 流程是真的、可用的（GET /agent → POST /install → POST /install/{product} → 輪詢）。
2. **`InstructionsPatchUrl` 是 code 裡真的會設的欄位**——這裡寫死官方 `us.patch.battle.net:1119`，但**改成任意 URL 是一行的事**。「重導向 Agent 到自架 CDN」在工程上就是改這一行 + 架一台 §2 的版本服務。
3. **但它裝不了舊版**。README 兩處把牆講死：
   - 「All TACT Products and Agent UIDs can be found [on wowdev.wiki] however **only (green) Active products will work**.」
   - 錯誤碼 `"2221", the supplied TACT Product is unavailable or invalid.`
   - 且必須有**真的、已登入的 Battle.net app**（否則 `"Unable to authenticate"`）。

也就是說：`barncastle/Battle.Net-Installer` 走的是**官方版本服務 + 官方 CDN + 你的帳號**，它只是把 Battle.net app 圖形介面替換成 CLI。**它從未把 `InstructionsPatchUrl` 指向非官方主機**，也沒有任何 issue/README 宣稱裝過下架 build。要走那步得自己改它並自架服務——沒有一手來源記載有人做成過。

---

## 4. 社群 NGDP/TACT 工具盤點（本案關切：誰碰 Agent、誰只做協定）

母文件 §3 已逐專案裁決過「誰能寫 CASC」。這裡只補**與 Agent／版本服務／舊版安裝**相關的定位，並修正任務清單裡幾個名字。

| 專案 | 語言 | 維護 | 定位（一手） |
|---|---|---|---|
| **`barncastle/Battle.Net-Installer`** | C# | 2025 活躍，252★ | **唯一驅動真 Agent 本機 API 的工具**。見 §3。只裝 active 版、需登入的 Battle.net app |
| **`keg`**（原 `HearthSim/keg`，作者 jleclanche，Python） | Python | **原 repo 已 404** | NGDP client，**git 式**：`ngdp init` / `remote add` / `fetch` / **`install {remote} {version} {outdir}`**。object store 1:1 複製 CDN；install 是**把 build 的檔案 checkout 成鬆散檔到 outdir**，可按 `--tags Windows enUS` 過濾。**不碰 Agent、不寫 CASC 容器**。原 repo 找不到，僅存 2022 年鏡像 `MrMoonKr/keg-doc`（Travis badge 仍指 `HearthSim/keg`）——**任務清單說的「keg（Go）」有誤，keg 是 Python** |
| `jleclanche/patchtools` | Python | **archived（2017）** | 舊式 Blizzard patch 下載器，keg 的前身。已封存 |
| `jleclanche/python-ngdp` / `ngdp-client` | — | **在 GitHub 上都 404** | 任務清單點名的這兩個名字**現在都找不到**。jleclanche 的 NGDP 產出實質收斂在 keg（已 404）與一份 gist 文件。**未驗證是否改名或刪除** |
| `ngdp-client`（Rust, crates.io / lib.rs） | Rust | 見下 | **與 jleclanche 無關**；是 `cascette-rs` 早期 crate 名。母文件 §6.1 已更正 `cascette-rs` 的 crate 已整併改名為 `cascette-*` |
| **`wowemulation-dev/cascette-rs`** | Rust | 2026-08 活躍 | NGDP 全套。含 **`cascette-ribbit`（自架版本服務，本案 §2 的引擎）**、TACT client、`casc-storage`「read/write support」。母文件 §3 裁 `.build.info` 只有 parser 無 writer（半可寫） |
| `wowemulation-dev/cascette-py` | Python | 2026-08 活躍 | `cascette install product`：**不經 Agent**，直接 Ribbit+CDN 拉成安裝目錄。母文件 §3 裁「可寫」但**產物能否被 client 開起未驗證** |
| `miceiken/SharpNGDP` | C# | **2019 停更** | NGDP/TACT/Ribbit 通訊庫。純協定，不裝、不寫容器 |
| `lukegb/snowstorm`（`/ngdp`） | Go | **2017 停更** | 任務清單問的「Go NGDP client」實際是這個（不是 keg）。純協定實驗，久未動 |
| `jaenster/d2r-cdn` | Zig | 2026-08 | D2R 如何走 NGDP/TACT + 一個 pure-curl 參考 client。**示範「直接對 CDN 下載、不經 Agent」**，是文件+PoC 非安裝器 |
| Arctium（`cdn.arctium.tools` / `ngdp.arctium.io`） | — | 鏡像活著 | 母文件 §5 已查：是 **CDN 鏡像**，非工具、非版本服務、無公開政策。`Burralis/Game-Launcher`（Arctium 血統）是 runtime memory patcher，改 client 的 `--versionurl`/`--cdnsurl`，**與 Agent 無關** |

**負面結果（重要）**：`gh search` 對 `keg` / `ngdp` 已無活躍的獨立 client 專案浮出；能自架版本服務去餵舊 build 的，實質上仍只有 `cascette-ribbit` 一個（母文件 §6.1 同結論）。**沒有任何專案宣稱「MOCK 一台 Ribbit 讓真 Agent 去裝舊版並成功」**——這正是本案想找而找不到的東西。

---

## 5. 關鍵問題：有沒有工具把 NGDP/TACT 下載打包成 client 讀得動的 CASC？

**這題母文件 [`casc-packaging-and-mirrors.md`](./casc-packaging-and-mirrors.md) §3 已經做到見底，這裡只給結論與本案關聯，不重抄。**

- **CASC-READ**（只讀）：`CascLib`、`TACTSharp`/`TACTTool`、`TACTLib`、`CASCExplorer`、`BuildBackup`、`wow.tools.local`——全部只讀，或只抽鬆散檔。
- **CASC-WRITE**（真的寫 `.idx` / `data.NNN` / `.build.info` / shmem）：只有四個——**`d07RiV/blizzget`（C++）、`FernandoS27/WhiteoutLib`（C++, beta）、`ldmonster/go-casclib`（Go）、`wowemulation-dev/cascette-py`（Python）**，外加 `cascette-rs` 半可寫。
- **母文件 §3.1 的縫（本案最該記住的一句）**：**這四個寫入器沒有任何一個宣稱產物被真正的零售 client 開起來過。** 最誠實的 `blizzget` 自己 README 說產物「will most likely **not be playable**… make sure you run it through **battle.net app so it can fix the possible inconsistencies**」。

→ **這就是 Agent 路唯一的、無可取代的賣點**：`blizzget` 自己都叫你「拿去給 Battle.net app 修」——因為**只有真 Agent 寫的 CASC 保證 client 開得起來**。社群工具能寫出「結構完整」的容器，但「結構完整」≠「client 開得起來」，目前只有前者有證據。**若**你能把真 Agent 餵一份舊 build，你就跳過了這整個未驗證區。**但 §6 說明這個「若」有多貴。**

---

## 6. 能不能逼 Agent 裝「指定舊版」並指向自架 CDN？逐一列阻擋因素

把 §1–§3 的一手事實組起來，一條理論上的路徑是：

> 改 `barncastle/Battle.Net-Installer` 把 `InstructionsPatchUrl` 指向本機 → 跑 `cascette-ribbit` 回一份 3.4.3 的 build_config/cdn_config，CDN 指向鏡像 → Agent 去裝 → 得到真 Agent 寫的 CASC。

每一步都有牆，由硬到軟：

| # | 阻擋因素 | 一手依據 | 狀態 |
|---|---|---|---|
| 1 | **CDN blob 得存在**。3.4.3 的 data/config blob 若官方已刪，鏡像也沒存，就無解 | `BuildBackup` README「Blizzard often removes data for older builds… making them unavailable for install」；母文件 §6.3 | **與 client streaming 撞同一面牆**，Agent 路無任何優勢 |
| 2 | **需要真的、已登入的 Battle.net app** 產生 `/agent` 授權 token（驗簽章+PID+session） | wowdev.wiki/Agent「Authorization」段；`barncastle` README「must be… recently signed in」；`"Unable to authenticate"` | 硬牆。不能純離線。**未驗證** token 能否在不連 Blizzard 帳號服務下取得 |
| 3 | **Agent 只裝 active product**。要繞過就得自架版本服務回舊 config | `barncastle` README「only (green) Active products will work」；錯誤碼 2221 | 可繞（自架 Ribbit），但引出第 4 點 |
| 4 | **自架版本服務的簽章／整合性**。V1 有 PKCS#7 + SHA-256；V2 靠 HTTPS。`cascette-ribbit` **不附 PKCS#7 簽章** | wowdev.wiki/Ribbit；`cascette-rs` 文件自述 | **未驗證**：現行 Agent 對 redirect 來的 `instructions_patch_url` 收不收未簽章回應。母文件 §6.2 記 `wow-patcher`/`Game-Launcher` 之所以能餵未簽章 server，是因為它們**同時 patch 了 client 的 RSA modulus**——但那是 patch **client**，不是 patch **Agent**；沒人做過「patch Agent 的簽章驗證」 |
| 5 | **協定世代漂移**。wiki 逆向的是 Agent 9370（Ribbit V1 時代）；現行 Agent 預設 **Ribbit V2（2026-02）甚至 TACT Channels（2026-08）** | wowdev.wiki/Ribbit | **未驗證**：現行 Agent 是否還尊重舊式 `instructions_patch_url = ...:1119/...`；`cascette-ribbit` 是否涵蓋 TACT Channels（母文件 §6.1 說**目前沒有 Ribbit server 實作涵蓋 TACT Channels**） |
| 6 | **Agent 自更新**。除非 `--skipupdate`，Agent 會把自己升到現行版（見 §1.3） | wowdev.wiki/Agent 產品表 `bna` | 可用旗標壓制，但要能傳旗標你得自己起 Agent，又回到第 2 點的 token 問題 |
| 7 | **加密產品**。部分 product 要 `encryption_key`（`/size_estimate` / 錯誤碼 3001） | wowdev.wiki/Agent；`barncastle` 錯誤碼 3001 | 3.4.3 未知是否受影響，**未驗證** |

**沒有任何一手來源記載有人把 1–7 全部走通、用真 Agent 裝成一份下架舊 build。** 這是本案查證的終點：**這條路在公開紀錄裡從未被完成過。**

---

## 7. BNETDocs 澄清（避免把來源搞錯）

任務把 BNETDocs 與 wowdev.wiki 並列為 Agent／NGDP 的一手來源，需更正：**BNETDocs（bnetdocs.org）記的是「舊 Battle.net 聊天／對戰協定」（BNCS，Diablo/Warcraft III/StarCraft 時代那套 `bnetd` 協定），不是 NGDP/TACT/Agent。** 站方自述「documents and discusses the Battle.net protocol… from 2003 to today」——那個「protocol」是遊戲大廳協定，與現代 CDN 發佈系統無關。

→ **Agent / NGDP / TACT / Ribbit / CASC 的一手文件，權威來源是 `wowdev.wiki`，不是 BNETDocs。** 本篇所有協定細節都出自 wowdev.wiki 五頁。**未在 BNETDocs 找到任何 Agent.exe 或 NGDP 內容**——若日後有人引用「BNETDocs 講 Agent」，八成是搞混了。

---

## 8. 對本案的裁決：貴 vs 便宜

把「重導向 Agent」和我們**已在走**的「工具抽鬆散檔」並排：

| 維度 | 重導向真 Agent（本篇） | 客戶端 streaming（[casc-resync](./casc-resync-reset.md)） | TACTSharp 抽鬆散檔（[casc-packaging §7](./casc-packaging-and-mirrors.md)，**現行方案**） |
|---|---|---|---|
| 要不要 Windows + 登入的 Battle.net app | **要**（§6 第 2 點） | 不要 | 不要 |
| 要不要自架版本服務 | **要**（§6 第 3–5 點，簽章未驗證） | 不要（改 `.build.info` 指 CDN 即可） | 不要 |
| 舊 build blob 已刪時 | **無解** | 無解 | 無解（三者同牆） |
| 產物 | **真 Agent 寫的 CASC（唯一保證可開）** | 補進既有 CASC | 鬆散檔覆蓋（已實測有效） |
| 對「補 zhTW 幾十 MB」 | **殺雞用牛刀，且多數步驟未驗證** | 可行但觸發條件是黑箱 | **已驗證可行，零 Agent、零對外連線** |
| 合規 | 需真帳號＋可能打鏡像當 CDN（母文件 §5 明禁） | 改 client 指鏡像＝母文件明禁 | 鏡像只給工具吃＝Marlamin 明講的預期用途 |

**結論：對「拿到一份完整可玩的舊 build CASC」這個抽象目標，Agent 路是最貴的一條**——它把「需要真帳號的 Windows app」「自架帶簽章的版本服務」「未驗證的協定世代相容」三個成本疊在一起，換來的唯一好處（真 Agent 寫的可開 CASC）**在 blob 已被刪時根本兌現不了**，而在 blob 還在時，工具路已經能不碰 Agent 就拿到檔。

**對我們的實際處境（已有可玩的 3.4.3、只缺 zhTW），Agent 路是純粹的零收益。** 維持既定路線：TACTSharp 向鏡像抽 zhTW 鬆散檔落地，`.build.info` 的 CDN 指回官方，client 不再對外連線。**本篇正式封掉「改 Agent」這條分支。**

**唯一值得記住的例外情境**：**若**未來要「從零重建一份必須被零售 client 開起來、且 blob 確定還在鏡像上的完整安裝」，那麼「餵真 Agent」是繞過『社群 CASC 寫入器產物未驗證』的**理論最短路**——但得先解決 §6 的授權 token（第 2 點）與簽章（第 4 點）兩道未驗證牆。在有人把這兩道走通並公開之前，這仍是研究題，不是可執行方案。

---

## 9. 未驗證項清單（本篇新增，不重複母文件的）

- 現行（2026）Agent 是否還尊重舊式 `instructions_patch_url = http://...:1119/{product}`，還是已全面轉 Ribbit V2 HTTPS / TACT Channels 而忽略它
- 現行 Agent 對 redirect 來的版本服務**收不收未附 PKCS#7 簽章的 V1 回應**（`cascette-ribbit` 不簽章）；以及有沒有等同 `wow-patcher` 對 client 做的「patch 掉 Agent 簽章驗證」的手法（**查無任何實作**）
- `/agent` 的授權 token 能否在**不透過已登入 Battle.net app**、不連 Blizzard 帳號服務的情況下取得（build 9370 無 `--nohttpauth`）
- 把 `barncastle/Battle.Net-Installer` 的 `InstructionsPatchUrl` 改指本機 + `cascette-ribbit` 餵舊 config，真 Agent 會不會裝——**公開紀錄中無人做過**
- `keg` 的 `ngdp install` 產物到底是純鬆散檔還是有無容器化（README 用語「checked out files」偏向鬆散檔，但未逐位元組驗證）
- jleclanche 的 `python-ngdp` / `ngdp-client` 是刪除、改名還是併入 keg（GitHub 現皆 404）
- 3.4.3.54261 的 build/cdn config blob 目前是否還在任一鏡像（母文件 §6.3 已指出「協定技巧救不回已刪 blob」，此為所有路徑的共同前提）

---

## 10. 修正與補遺：BuildBackup「鏡像下載」管線(復刻工具路,非 Agent 路)

**日期補記**：2026-09-07

**先認錯**:本篇 §0–§9 只查了「重導向**真** Agent」這一條,並正確地判它貴。但漏了使用者指的另一類——**社群復刻的下載器 + 建 CASC 工具**。這是**不同的一條路**,而且對「下載/保存完整舊 build」是**可行**的。把兩者分清楚:

| 路線 | 工具 | 判決 |
|---|---|---|
| **重導向真 Agent** | Battle.net Agent + cascette-ribbit + barncastle installer | ❌ 貴(需登入的 Windows app + 未驗證簽章),§8 結論不變 |
| **復刻下載器**(本節) | [BuildBackup](https://github.com/Marlamin/BuildBackup) + 自架 CDN + patched client | ✅ 下載/保存可行;可玩性靠 **client 自己建 CASC** |

### 10.1 關鍵洞察:繞過「社群 CASC 寫入器產物未驗證」那道牆

§5 說「沒有社群工具能寫出零售 client 開得動的 CASC」——**對,但那道牆可以繞過:client 自己就是 CASC 寫入器**。它安裝時會把 CDN 資料寫成本機 CASC(現在的 streaming 就是這樣,只是走登入後的節流通道)。所以:

> **不需要任何社群 CASC 寫入器,也不需要 Agent**——只要把完整 CDN 資料放到本機,讓 **patched client 自己去安裝**,client 就寫出貨真價實的 CASC。

### 10.2 BuildBackup 指向鏡像的具體步驟(評估)

輸入我們**已經有**:`.build.info` 的 `Build Key c91609c69ed2ab39d44039390a1be969` + `CDN Key 00a60ae44b1a81c84743845a9b9df3a0`(= build_config / cdn_config 雜湊)。

1. **餵 config 雜湊**(繞過版本服務):BuildBackup 正常流程是查版本服務拿「當前版」,但 3.4.3.54261 已下架 → 版本服務不回。所以要用「直接給 build/cdn config 雜湊」的模式。`Program.cs` 有多個模式,是否支援「指定任意 config 雜湊備份」= **待驗證的第一點**。
2. **cdnList 指向鏡像/代理**:`CDN.cs` 的 `public List<string> cdnList` 可改;URL 樣式 `http://{cdn}/{path}`。指到我們的代理 `127.0.0.1:8100`(已代理鏡像 + 快取 8G)即可。**這層已被證明相容**——我們的 cdnproxy 抓的正是同一批 `tpr/wow/{type}/{hashprefix}/{hash}` blob。
3. **輸出**:一份本機 CDN 鏡像(config/data/indices,暴雪目錄結構)。
4. **變可玩**:自架一台 web server 服務這份鏡像(CASCHost 註明「IP 不行、要 domain」,我們有 `lvh.me`)+ 一個回這個 build 的 `/versions`+`/cdns`(cascette-ribbit 或靜態檔)+ patched client(wow-patcher,已有)指過去 → **client 全新安裝 → 自己寫 CASC**。

### 10.3 未驗證/風險點

- **BuildBackup 已「不再維護」**(README 明載),無 CLI 文件,得讀源碼定參數。
- **「指定舊 config 雜湊備份」模式是否存在** = 第一未知(否則得改源碼)。
- **加密內容的 TACT keys**:若該 build 有加密 blob,要金鑰才解得開(WoW 本體多數未加密,風險低)。
- **全新安裝是否「全速」** vs 我們看到的登入後 streaming「節流 ~16MB/分」= **最關鍵未知**。install 前置的「Downloading」階段通常全速,但能否從本機鏡像觸發該模式**沒實測過**。
- **版本服務給 install 用**:client 安裝要問 `/versions`+`/cdns`,得自架回這個 build。

### 10.4 對本案裁決

- **「復刻帶下載的 CASC 管線」存在嗎?** ✅ 存在(BuildBackup + CASCHost + cascette-rs)。§0 對「Agent 路」的否定不變,但**不該延伸成否定這條**——先前是我查淺了。
- **對補 zhTW**:仍是 overkill(已有完整可玩 CASC)。
- **若要「從鏡像乾淨重建、zhTW 內建的完整安裝」**:這條(BuildBackup → 本機 CDN → client 自裝)是**理論上可行且不需 Agent** 的正解,但卡在 §10.3 那幾個未實測點,尤其「全新安裝是否全速」。

**來源**:[BuildBackup](https://github.com/Marlamin/BuildBackup)(README + `Program.cs` + `CDN.cs`)、[CASCHost](https://github.com/WowDevTools/CASCHost)、[cascette-rs](https://github.com/wowemulation-dev/cascette-rs)。相關:[[casc-packaging-and-mirrors]]、[[casc-resync-reset]]。
