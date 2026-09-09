# 怎麼逼客戶端重跑那次 CDN 同步、把缺的檔補進 CASC？

> 撰寫日期：2026-09-06
> 相關筆記：[CASC 能不能由 Blizzard 以外的工具「寫」出來？兼社群鏡像的正當用法](./casc-packaging-and-mirrors.md)（本篇是它的續集——那篇把容器「怎麼被讀寫」解剖完了，本篇處理「客戶端何時會主動去 CDN 補檔」）、[`wow-patcher` runtime mode 評估](./wow-patcher-runtime-mode.md)、[macOS client 取得與執行](./macos-client-options.md)、[TrinityCore client 設定與憑證](./tc-client-setup-and-certs.md)
> 來源限定 primary sources：**本機 `/Users/shinichi/World of Warcraft 3.4.3.54261` 的唯讀檢視**（Python 直接 parse shmem／`.build.info`／`Config.wtf`）、`wowdev.wiki` 的 `CASC` / `TACT` / `Agent` 三頁（用 MediaWiki API `action=raw` 與 `Special:Export` 抓原文，非二手轉述）、`ladislav-zezula/CascLib` 作者 zezula 的 CascLib 文件、`Stanzilla/AdvancedInterfaceOptions` 的 `cvars.dump`（客戶端 cvar 一手清單）。
> **凡未在一手來源找到者一律標「推測」或「未驗證」。本文唯讀，除寫本檔外不改任何檔案，尤其沒碰那個安裝的 `Data/`。** 未使用瀏覽器自動化。

---

## 0. 裁決先講

**沒有找到「純客戶端、一個開關就重跑完整 CDN 同步」的官方機制。** 官方那條「重掃缺檔並補下載」的路是 **Battle.net Agent 的 `/repair` 與 `/backfill` 端點**（wowdev.wiki/Agent 有記載）——而我們這個安裝**沒有 Agent**，所以那條路本身就不存在。

但有一件事被一手文件講得很死，且**與我們曾經觀察到的 +777 MB 完全吻合**：

> **客戶端自己在遊玩中就會 on-demand 補檔。** wowdev.wiki/TACT 的 Download manifest 段原話：「the client will download on demand… **if the game is running, missing assets in the player's vicinity take precedence**」。CascLib 作者 zezula 的文件更直接：「**Every time when a missing or corrupt file is detected, the game client automatically downloads the data from the server.**」

也就是說，**+777 MB 不是什麼「一次性建立世界資料」的特殊儀式，就是這個 on-demand streaming**——你當時走到的地方需要那些 tile，客戶端在本機 `.idx` 找不到，於是照 `Data/indices/` 的 CDN archive index 定位、對 `.build.info` 裡的 CDN host（我們改成 `127.0.0.1:8100`）發 Range request、寫回 `data.NNN` 並把 `.idx` 版本號 +1。這條路**現在仍然是啟用狀態**（見第 1、6 節的實測：`enableStreaming` 沒被關、shmem 還在「未完成」狀態）。

**所以最接近可靠的做法，不是「重置某個完成旗標」，而是「重新製造 on-demand 的觸發條件」**：確保 streaming/bgdl cvar 開著、打開 streaming 狀態訊息來確認客戶端到底有沒有在嘗試、把 preload 距離拉大讓它更早去要那些 tile，然後真的把角色移動到那 12 個檔對應的座標。詳細步驟與風險排序在第 7 節。

**為什麼不敢保證**：客戶端「決定去要某個 FDID」的內部條件（尤其是「這一格 tile 這個 session 已經嘗試過、失敗了要不要重試」）**沒有任何一手文件**，是黑箱。我們能證明的是「機制存在且沒被關」，不能證明「照做一定會再打 8100」。

---

## 1. 一手觀察：這個安裝現在到底是什麼狀態

全部是對本機唯讀 parse 出來的，不是引用。

### 1.1 `.build.info`（root，15 欄）—— CDN 指向本機代理，仍然有效

```
...|CDN Path|CDN Hosts|CDN Servers|Tags|...|Version|KeyRing|Product
eu|1|c916...|00a6...|||tpr/wow|127.0.0.1:8100|http://127.0.0.1:8100/?maxhosts=1|OSX x86_64 ... zhTW ...|||3.4.3.54261||wow_classic
```

- `CDN Hosts` = `127.0.0.1:8100`、`CDN Servers` = `http://127.0.0.1:8100/?maxhosts=1`。**客戶端要 streaming 時會讀這裡**（見 §3 的 Shared storage 規則）——指向沒問題。
- 對照 `.build.info.win.bak`（原 Windows 血統）CDN 還是 `blzddist1-a.akamaihd.net` 那一組。我們已經改過了。
- `Product` = `wow_classic`、`Version` = `3.4.3.54261`。

### 1.2 `shmem`（20,480 bytes）—— block type = **5**，即「未完成/待補」狀態

parse 出來：`block1 type=5, nextBlock=0x154`，內嵌路徑是**現在的 macOS 路徑**（`/Users/shinichi/World of Warcraft 3.4.3.54261/Data/data/index`），16 個 bucket 版本號與磁碟上 `.idx` 檔名尾碼一致（`31,32,36,31,32,2d,33,32,33,2e,32,32,34,31,...`），`block2 type=1`（free-space 表）。

**這一點很關鍵、而且推翻了「有個完成旗標鎖死它」的假設**：wowdev.wiki/CASC 對 block type 5 的原話是——

> 「There is a special case after a game update by the Battle.Net client. It seems that **the client only writes a template file without free space entries and lets the game later complete the file.**」

我們的 shmem **就是** type 5，也就是文件定義的「還沒完成、等遊戲把它補完」的狀態。**它不是「已完成」旗標，反而是「未完成」旗標。** 而且它在 +777 MB **之前和之後都是 type 5**（前一份筆記 casc-packaging §1.3 記的也是 type 5）。→ **shmem 的 block type 不是讓客戶端停手的原因。**（`shmem` 的 mtime 是最後一次啟動的時間，證明客戶端每次啟動都重寫它——wiki 也說「recreated every time a client is started」。）

### 1.3 `.idx` 版本號**已經 +1 過**——證明串流真的寫進去了

現在的檔名：`0000000031.idx / 0100000032.idx / 0200000036.idx / …`。前一份筆記記錄串流前 shmem 裡的版本是 `0x25,0x26,0x2a,…`（= 37,38,42…）。現在是 `0x31,0x32,0x36,…`（= 49,50,54…）。**每個 bucket 都往上跳了十幾代**——wowdev.wiki/CASC 說得很清楚：檔名尾碼「is just a version number that **increments when a new set of files is added to the local archives**」。→ 串流確實把新檔加進了本機 archive，`data.011`（133 MB，未滿 1 GiB）就是最後那個正在被填的 archive。**這不是缺陷，是「它曾經正常運作」的鐵證。**

### 1.4 `Config.wtf` —— **完全沒有** streaming 相關 cvar

`_classic_/WTF/Config.wtf` 裡 `grep -i stream|bgload|download|cache` **零命中**。意思是 `enableStreaming` / `enablebgdl` 這些**全在預設值**（見 §6：預設是開的）。→ **streaming 不是被 config 關掉的。**

### 1.5 目錄差異（coordinator 的實地觀察，納入分析）

| | 我們的安裝 | 官方 BNet 安裝（macOS 5.5.4 對照組） |
|---|---|---|
| `Data/` 子項 | `config` `data` `indices` | `config` `data` `ecache` `indices` `wow_classic` |
| 產品子容器 | **無** `Data/wow_classic/` | 有，內含 `*.idx` `index.lock.0` `.residency` |
| encoding cache | **無** `Data/ecache/` | 有，一堆 `*.idx` |

這三個缺項（`wow_classic/`、`ecache/`、`.residency`）的意義在 §4 專門處理——**先講結論：沒有任何一手文件記載它們，所以任何「就是因為缺這個才不下載」的說法都只能是推測，而且我們手上的反證（串流曾在缺這三項的情況下成功）讓這個推測站不太住。**

---

## 2. 逐一回答：CASC 容器裡哪些檔是「狀態/完成度」、哪個決定「要不要向 CDN 補」

把 coordinator 問的每個檔名對到一手來源，並標明它到底 gating 不 gating。

| 檔／目錄 | 一手來源怎麼定義 | 是「內容」還是「狀態」 | 決定要不要向 CDN 補檔？ |
|---|---|---|---|
| `Data/data/data.NNN` | wowdev.wiki/CASC：BLTE payload + 30-byte record header | **內容** | 否 |
| `Data/data/*.idx` | 「mapping from keys to the location of their data in **the local** CASC archives」 | **狀態**（本機 EKey→offset 索引；檔名尾碼是「加檔就 +1」的版本號） | **間接、關鍵**：客戶端要一個 EKey 時**先查 `.idx`**；查不到才會走 CDN。`.idx` 就是「本機有什麼」的權威清單 |
| `Data/data/shmem` | 「recreated every time a client is started」；type 5 = 未完成模板 | **狀態**（archive 佈局 + free-space；每次啟動重建） | 否（見 §1.2：它是啟動時重建的暫存，不是完成鎖） |
| `Data/data/index.lock.0` | 一手：0-byte lock 檔 | **狀態**（互斥鎖） | 否 |
| `Data/config/**` | wowdev.wiki/TACT：Build/CDN/Patch config（BLTE-less，hash 命名） | **內容/清單**（指向 encoding、root、install、download manifest 的 key） | 否（但它指到的 download/install manifest 會，見 §5） |
| `Data/indices/*.index`（1,847 個） | wowdev.wiki/TACT：**CDN** archive index（footer 帶 numElements/checksum） | **狀態**（「CDN 上哪個 archive 的哪個 offset 有這個 EKey」） | **關鍵**：這是客戶端把「缺的 EKey」翻成「去 CDN 抓哪個 Range」的地圖。**缺它就抓不了**（coordinator 說那 12 個檔在 archive-group 可解析，代表這一步是通的） |
| `.build.info`（root） | wowdev.wiki/TACT：Shared storage 的快取 build 資訊；**「if these two files are available the clients will use cached information instead of getting it from remote」** | **狀態** | 是（提供 CDN host/path；我們已指向 8100） |
| `_classic_/.flavor.info` | 同上，內容就是 `wow_classic` | **狀態**（產品名，配對 `.build.info`） | 否（純標記） |
| `.product.db` | wowdev.wiki + TACTLib protobuf schema：**Agent 自己的**狀態庫，不屬遊戲安裝格式 | **狀態（Agent 的，不是客戶端的）** | 否（沒 Agent 就沒人讀它） |
| `.residency` | **查無任何一手來源**（見 §4） | 推測：狀態 | **未知/推測** |
| `Data/ecache/` | **查無任何一手來源**（見 §4） | 推測：encoding cache | **未知/推測** |
| `.bgdl`（作為檔案） | **查無「本機檔案」定義**；`enablebgdl` 是 cvar、`BGDL` 是 Ribbit 端點型別（`Warpten/tactmon` 有 `ribbit/types/BGDL`） | 見 §6 | 否（我們沒接 Ribbit） |

**一句話**：真正決定「本機有沒有 / 缺了要去哪抓」的三件事是 **`.idx`（本機有什麼）＋ `Data/indices/`（缺的在 CDN 哪）＋ `.build.info`（CDN 是誰）**。這三件我們都是好的。缺的不是「狀態檔」，缺的是「客戶端主動去要那 12 個 FDID 的觸發」。

---

## 3. Shared storage：客戶端讀哪份 `.build.info`

wowdev.wiki/TACT「Shared storage」段（8.1 起）原話：

> 「There is one Data folder in the root folder with storage for multiple products. … Root folder has a `.build.info` … each product subfolder also has a `.flavor.info` … Both of these files are written by the Battle.net agent and not by the clients themselves. **However, if these two files are available the clients will use cached information in the `.build.info` file instead of getting it from remote.**」

對我們的意義有二：
1. **好消息**：客戶端會吃 root `.build.info` 的 CDN 欄位（→ 8100），不會去問任何版本服務。這也是 casc-packaging §4(c) 講的「已物化的安裝不問版本服務」。
2. **要注意**：這段講的是 `.build.info` + `.flavor.info` **成對**存在時的行為。我們 root 有 `.build.info`，`.flavor.info` 在 `_classic_/` 底下（而非 `Data/wow_classic/`）。串流既然成功過，代表這個擺法客戶端接受。**未驗證** 官方原本預期 `.flavor.info` 的位置是否影響 streaming 判定。

---

## 4. `.residency` / `wow_classic/` / `ecache/`：誠實說——查無一手文件

coordinator 的核心假設是「缺了 `Data/wow_classic/`（產品子容器）和 `.residency`，客戶端每次都當成『無法背景下載』而略過」。我盡力找了一手來源：

- **wowdev.wiki 的 `CASC`、`TACT`、`Agent` 三頁全文**：`residency`、`ecache` **零命中**。`wow_classic` 只出現在 flavor/product 名的語境，沒有「這個子目錄裝什麼」的規格。
- **GitHub 全站 code search**（`residency` + CASC / `.residency wow` / `ecache CASC`）：命中的 `residency` 全是無關專案（記憶體 residency、GPU residency…），**沒有任何 CASC 工具用到 `.residency`**。CascLib、TACTSharp、cascette-rs、TACTLib 都沒有這個字。
- CascLib 作者只有「missing/corrupt → 自動下載」這一句一般性描述，沒提 `.residency`。

**所以：**

1. **`.residency` 的格式與作用——沒有任何一手佐證，我不臆造。** 就名字推測（**推測，非文件**）它可能記錄「哪些 encoded 檔被標記為必須常駐本機」，屬於 shared-storage 時代 Agent 幫每個產品維護的「這台機器要留哪些檔」清單。但這是**猜的**。
2. **`ecache/` = encoding cache 也是純推測**（名字），可能是跨產品共用時把 encoding table 的解析結果快取起來，避免每次重解。**無文件。**
3. **「缺這三項所以不下載」這個因果——有一條硬反證**：**我們的 +777 MB streaming 就是在缺這三項的情況下發生的。** 如果「沒有 `wow_classic/.residency` 就一定不背景下載」，那第一次也不該下載成功。所以更可能的情況是：這三項是 **Agent** 在管的東西（Agent 安裝/維護時建的），對「**客戶端執行期的 on-demand streaming**」**不是必要條件**。客戶端的 streaming 只認 `.idx` + `Data/indices/` + `.build.info`（§2 那三件）。

> **推測（明確標示）**：`wow_classic/` + `ecache/` + `.residency` 是「由 Agent 安裝流程建立、供 Agent 的 `/backfill`/`/repair` 使用」的產物；沒有 Agent 就不會有它們，也不影響客戶端自身的 on-demand 補檔。**手動去建一個空的 `Data/wow_classic/` 或假造 `.residency` 幾乎不可能有幫助**——格式未知，造錯反而可能讓客戶端解析失敗。**不建議動它。**

---

## 5. install manifest vs download manifest：priority 與「常駐」

一手（wowdev.wiki/TACT）：

- **install manifest（"IN"）**：列出「裝在磁碟上的檔」，用 tag bitfield 按平台/語系/architecture 篩子集。這是「安裝時就該落地的最小集合」。
- **download manifest（"DL"）**：列出「data archive 裡所有檔」，每筆有 **`DownloadPriority`：0 = 最高、2 = 最低**（install 集自 8.x 起是 `-1`）。原話：
  > 「The client uses this to **download files ahead of time**, without it, the client will **download on demand** which can lead to issues. … if the game is running, **missing assets in the player's vicinity take precedence**.」
- **Download Size（"DS"）**、**Tags**（platform/architecture/locale/region/category=speech|text/alternate）：把「哪些 tag 的檔要不要拿」編碼成 bitfield。

**回答 coordinator 的 Q3「有沒有辦法讓客戶端把某批 FDID 視為必須常駐而觸發下載」**：

- **priority 是寫在 CDN 上的 download manifest 裡的**，不是本機可調的旋鈕。改它要重簽 manifest，客戶端不會吃我們偽造的（也超出唯讀範圍）。
- 客戶端「ahead-of-time 下載」是照 download manifest 的 priority **由高到低**掃；但那 12 個副本 tile/WMO 幾乎肯定是 **priority 2（最低）**——正是「不會 install 時就抓、只在你走到附近才 on-demand」那一批。**這解釋了為什麼它們一開始就不在本機、也解釋了為什麼只有『走到附近』才會觸發**。
- **沒有客戶端側的合法手段把某批 FDID 提升成「必須常駐」。** 官方做這件事的是 **Agent `/backfill`**（見 §6），我們沒有。

---

## 6. 沒有 Agent 時，客戶端自身的 streaming 靠什麼觸發

### 6.1 一手 cvar（`Stanzilla/AdvancedInterfaceOptions` `cvars.dump`）

| cvar | 一手描述 | 對我們的意義 |
|---|---|---|
| `enableStreaming` | 「**Set to 0 to disable all streaming (requires client restart)**」 | 總開關。預設非 0（開）。我們 `Config.wtf` 沒設 → 開著 |
| `enablebgdl` | 「**Background Download (on async net thread) Enabled**」 | 背景下載執行緒。這就是 coordinator 說的「背景任務」的真身 |
| `streamStatusMessage` | 「Whether to **display status messages while streaming content**」 | **診斷金鑰**：設 1 就會在畫面上顯示串流狀態，能直接看出客戶端到底有沒有在嘗試 streaming |
| `preloadstreamingdistTerrain` | 「Terrain preload distance when streaming」 | 把它調大 → 更早、更遠去要 terrain tile |
| `preloadstreamingdistObject` | 「Object preload distance when streaming」 | 同上，for WMO/物件 |
| `streamingcameraradius` / `streamingCameramaxradius` / `streamingCameralookAheadtime` | streaming camera 的半徑/前瞻 | 影響「預取多遠」 |

`.bgdl` 作為**本機檔案**沒有一手定義；`enablebgdl` 是客戶端 cvar，`BGDL` 是 Ribbit 的一種 config 型別（`Warpten/tactmon` 的 `ribbit/types/BGDL`）——**我們沒接 Ribbit，所以沒有 BGDL config 進來，背景下載只能靠客戶端讀本機 download manifest + `.build.info` 自走。**

### 6.2 那 +777 MB 最可能是什麼條件下發生的

綜合 §1（shmem 仍 type 5、`.idx` 版本已 +1、streaming cvar 沒關）與 §5 的 priority 模型，**最可能的解釋**：

> 那次登入你走到的地圖格，需要一批 priority-2 的 on-demand 檔；客戶端 `.idx` 查不到 → 照 `Data/indices/` 定位 → 對 8100 發 Range → 寫回 archive、`.idx` +1。**這就是 on-demand streaming 的正常行為，不是一次性儀式。**（**推測，但與所有實測一致**：shmem 沒進「完成」態、cvar 沒關，代表機制沒有被任何旗標「關掉」。）

### 6.3 官方的「重掃補檔」端點——我們沒有

wowdev.wiki/Agent 記載（Agent 是 REST-over-HTTP，綁 127.0.0.1）：

- **`/backfill`（POST）**：「**Sets backfill parameters (background download of remaining data after a product becomes playable)**」，欄位 `uid` + `priority`（預設 700）。**這才是官方版「進遊戲後在背景把剩下的補完」。**
- **`/repair`（POST）**：請求修復一個產品（重掃缺/壞檔）。
- **`/download`（POST）**：設下載速率/優先權。

**這三個全是 Agent 的**。我們的安裝沒有 Agent（是直接啟 `.app`，見背景），所以**這條官方路徑不存在**——這正是為什麼「重置某個檔逼它重掃」在我們的情境下沒有對應機制：那個會「重掃」的元件（Agent）根本沒在跑。

---

## 7. 最實際的重置操作：按「風險由低到高」排序

前提：唯讀調查已知「機制在、沒被關」，缺的是**觸發**。以下每項都附「做了會怎樣」與最壞情況。**強烈建議在動任何檔案前，先把整個 `Data/` 連同 `.build.info` 複製一份備份**（casc-packaging 已證明容器可被完整 parse，備份=保命）。

### 階 0（零風險，先做）：不改檔，只加 cvar 觀察 + 拉大預取

在 `_classic_/WTF/Config.wtf` 加：

```
SET enableStreaming "1"
SET enablebgdl "1"
SET streamStatusMessage "1"
SET preloadstreamingdistTerrain "..."   # 比預設大
SET preloadstreamingdistObject "..."    # 比預設大
```

然後進死亡礦坑，**貼著缺檔對應的座標走動並轉視角**（priority-2 檔要「in the player's vicinity」才會被要）。
- **做了會怎樣**：`streamStatusMessage=1` 會把「有沒有在串流」直接畫在畫面上——**這一步的主要價值是診斷**：若畫面顯示在串流但 `lsof` 沒有 8100，問題在網路層（代理/`.build.info`）；若畫面完全沒有串流跡象，問題在「客戶端根本沒嘗試」。
- **最壞情況**：無（只加 cvar）。改壞了刪掉那幾行即可。
- **風險**：低到可忽略。**這是第一件該做的事。**

### 階 1（低風險）：確認 8100 代理與 `.build.info` 這條鏈當下是活的

在客戶端還開著時，手動 `curl http://127.0.0.1:8100/tpr/wow/data/<那 12 個檔之一的 archive 路徑>` 驗證代理現在回得了那個 Range。
- **做了會怎樣**：純讀。若 curl 也抓不到，那客戶端不動的原因根本不是「狀態鎖」，是**代理現在轉不過去**（鏡像變動/代理沒起）——先修這個。
- **最壞情況**：無。

### 階 2（中風險，且是「刪狀態逼重評估」最有依據的一招）：刪 `shmem`，讓客戶端重建

- **依據**：wowdev.wiki/CASC 明文「shmem is **recreated every time a client is started**」。刪掉它，下次啟動客戶端會依 `.idx` + `data.NNN` 重掃、重寫 shmem。
- **做了會怎樣（推測，但有文件支撐重建行為）**：客戶端重新盤點本機 archive 佈局。**不會刪你已有的 `data.NNN`/`.idx`**，因此不會重下 15 GB。理想情況下重掃會讓它重新意識到「哪些 bucket 還沒滿/缺」。
- **最壞情況**：客戶端若在重建 shmem 時判定佈局不一致，可能拒絕啟動或要求修復（但我們沒有 Agent 可修）。→ **所以務必先備份 `shmem`**（單檔 20 KB）。刪錯就還原。
- **未驗證**：刪 shmem 是否真的會讓它「重新去補那 12 個缺檔」——**沒有文件保證**，這只是「最有重建語意依據」的一招。

### 階 3（較高風險，不建議輕試）：刪部分 `.idx` 逼重掃

- **理論**：`.idx` = 本機有什麼。刪掉某 bucket 的 `.idx`，客戶端會重建該 bucket 的索引（CascLib 註解：WoW 只保留最新兩個版本）。
- **最壞情況（嚴重）**：若客戶端重建後認為該 bucket 的內容「不在本機」，**可能觸發把該 bucket 對應的大量檔重新 streaming**——那可能遠超 777 MB。**這正是 coordinator 擔心的「刪錯導致重下」的情境。**
- **裁決**：**除非階 0–2 都無效、且你能接受重下風險，否則不要碰 `.idx`。** 碰的話一次只刪一個 bucket、先備份。

### 明確「不要做」清單

- **不要**手動建 `Data/wow_classic/` 或假造 `.residency`/`ecache/`：格式無一手來源（§4），造錯只會讓解析失敗；且有反證顯示它們對客戶端 on-demand 非必要。
- **不要**刪 `.build.info`：刪了客戶端會回頭問遠端版本服務（§3 的反面），而我們的 build 3.4.3 在官方版本服務上已下架（casc-packaging §1.5），可能整個安裝變不可用。
- **不要**刪 `config/` 或 `data.NNN`：那是內容本身，刪了才真的要重下。

---

## 8. 診斷：它為什麼「連 8100 的 TIME_WAIT 都沒有」——假設排序

按「與一手證據相容程度」排序，全部標明推測成分：

1. **（最可能，推測）客戶端這個 session 根本沒去載那 12 個檔對應的 tile/WMO。** priority-2 的 on-demand 檔只在「玩家附近真的要 render 到」時才要（§5）。若你進副本的落點、視角、preload 距離沒讓那幾格 tile 進入 streaming camera 範圍，客戶端就不會產生請求——**看起來像「不再補檔」，其實是「沒觸發」。** → 階 0 的「拉大 preload + 貼著座標走 + `streamStatusMessage`」正是針對這個。
2. **（可能，推測）per-session 負面快取**：某個 tile 上次嘗試 streaming 失敗（代理當時抽風/鏡像那一刻沒有），客戶端在本 session 內不重試。**無文件**，但能解釋「走過去也不再要」。→ 重啟客戶端（清 in-memory 狀態）可能就解，屬階 0 範圍。
3. **（可能）代理/鏡像鏈現在斷了**：8100 現在轉不過去，客戶端試了一兩次拿到錯誤就退避。→ 階 1 的 curl 直接證真/證偽。
4. **（較不可能，已被實測削弱）某個完成旗標鎖死**：shmem 還是 type 5「未完成」態（§1.2）、`.idx` 版本沒有異常、cvar 沒關——**沒有任何我們能檢視的狀態檔顯示「已完成、停手」。** 這個假設缺乏正面證據。

---

## 9. 建議動作（給實作者的最短路徑）

1. **先備份** `Data/`（至少 `shmem` + 全部 `.idx` + `.build.info`）。
2. **階 0**：`Config.wtf` 加 `streamStatusMessage "1"`、`enableStreaming "1"`、`enablebgdl "1"`、拉大 `preloadstreamingdist*`；進死亡礦坑貼著缺檔座標走動轉視角，看畫面有沒有串流訊息。
3. **階 1**：同時 `curl` 8100 驗證那 12 個檔此刻抓得到（排除代理/鏡像斷線）。
4. 依觀察分流：
   - 畫面顯示在串流、但 `lsof` 沒 8100 → 網路層問題（`.build.info` CDN 欄位 / 代理），不是狀態鎖。
   - 畫面完全沒串流跡象 → 才考慮**階 2 刪 `shmem`**（先備份），重啟客戶端重建後再走一次副本。
5. **階 3 刪 `.idx` 是最後手段**，接受可能重下的風險，一次一個 bucket。

**能保證的**：機制存在、沒被 config 關、CDN 指向正確、缺檔在 CDN 可解析——條件都齊。
**不能保證的**：客戶端「決定去要那 12 個 FDID」的內部觸發條件是黑箱，沒有一手文件；所以以上是「把觸發條件重新擺好」的工程手段，不是「按一個官方 resync 鈕」。**那個官方鈕（Agent `/repair` `/backfill`）需要 Battle.net Agent，而這個安裝沒有。**

---

## 附：一手來源清單

- wowdev.wiki [`CASC`](https://wowdev.wiki/CASC)、[`TACT`](https://wowdev.wiki/TACT)、[`Agent`](https://wowdev.wiki/Agent)（以 MediaWiki `action=raw` / `Special:Export` 取原文）
- CascLib 作者 zezula 的 CascLib 文件（`www.zezula.net/en/casc/`；online vs local storage、「missing/corrupt → 自動下載」、`IsLocal`）
- `Stanzilla/AdvancedInterfaceOptions` [`cvars.dump`](https://github.com/Stanzilla/AdvancedInterfaceOptions/blob/master/cvars.dump)（`enableStreaming` / `enablebgdl` / `streamStatusMessage` / `preloadstreamingdist*` 的一手描述）
- 本機唯讀檢視：`.build.info`、`shmem`（block type 5）、`Config.wtf`、`Data/data/*.idx`、`Data/indices/`
- 交叉參照：[`casc-packaging-and-mirrors.md`](./casc-packaging-and-mirrors.md)（容器逐位元組解剖、shmem type 5 先前紀錄、Agent REST 端點總覽、鏡像政策）
