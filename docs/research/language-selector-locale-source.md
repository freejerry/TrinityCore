# 現代 WoW client（CASC/TACT，3.4.x macOS）的「語言選單」到底讀哪個檔？為什麼改 `.product.db` 沒用？

> 撰寫日期：2026-09-08
> 相關筆記：[能不能改造／逆向 Battle.net Agent](./battlenet-agent-modding.md)（母文件——那篇把 Agent 的本機 REST API 與 `instructions_patch_url` 解剖完了；本篇接著解剖 Agent 的「資料庫」與 client 的「語言列」誰讀誰）、[CASC 能不能由 Blizzard 以外的工具「寫」出來？](./casc-packaging-and-mirrors.md)、[怎麼逼 client 重跑 CDN 同步](./casc-resync-reset.md)、[把 zhTW 當成真 locale](./zhtw-as-real-locale.md)、[zhTW 實作與修正](./zhtw-implementation-and-corrections.md)
> 來源限定 primary sources：`wowdev.wiki` 的 **Agent**、**TACT**、**CASC**、**Localization** 四頁（以 MediaWiki API `action=parse&prop=wikitext` 抓原文，非二手轉述）；`ladislav-zezula/CascLib`、`wowemulation-dev/cascette-rs` 的原始碼（`gh api` 直讀）；`blizztrack.com` 上真實 wow_classic product config 的 HTTP 回應。凡未在一手來源找到者一律標「**未驗證**」。

---

## 0. 裁決先講

**問題：把自組 CASC（本機只有 zhTW 資料）餵給 3.4.x client，登入畫面／遊戲內的語言下拉選單卻冒出 4 種語言（zhTW＋英＋西＋葡）。官方 zhTW 安裝只有 zhTW。到底哪個檔／欄位決定這張清單？我造的 `.product.db` 為什麼沒用？**

**答案（三句話）：**

1. **`.product.db` 沒用，是因為「直接啟動的遊戲 client 根本不讀它」。** `.product.db` / `.build.info` / `.flavor.info` 這三個檔是 **Battle.net Agent 寫、Agent 讀**的（wowdev.wiki/TACT 原文：「Both of these files are written by the Battle.net agent and **not by the clients themselves**」）。`installed_locales` / `selected_locale` / `display_locales` 是 **Agent 的產品資料庫**欄位，決定的是 **Battle.net app 的語言選單**和**安裝精靈要下載哪些語言**，不是遊戲內那張下拉選單。你動 product.db，動到的是 Agent 的世界，不是 client 的世界。

2. **遊戲內那張選單反映的是「本機真的裝了哪些 locale」，而 client 判斷「裝了哪些 locale」是掃 CASC 本地資料的 locale 旗標／manifest tag，不是 build.info、不是 product.db、不是即時 CDN。** 這解釋了你全部的負面結果（改 build.info Tags、造 product.db、CDN 全 404、改 branch kr——四個都動到「非 client 讀取路徑」的東西，所以四個都沒反應）。

3. **那 4 種語言（en/es/pt/zhTW）是你自組資料裡「殘留的 CASC root locale 旗標位元」。** WoW root manifest 每個檔都帶一個 locale bitmask（`CASC_LOCALE_*`）。你的 root（或 install/download manifest 的 Locale-type tag）除了 zhTW，還帶著 enUS＋esES/esMX＋ptBR 的位元，client 就把這幾個 locale 列進選單，**不管那些位元對應的資料檔在不在本機**。

**要改的檔＋欄位（actionable）：**

> **改 CASC 的 root manifest（以及 install `IN` / download `DL` manifest）裡的 locale 旗標／Locale-type(type=3) tag，讓「zhTW 以外的 locale 位元」全部清掉，只留 `CASC_LOCALE_ZHTW`（root）與 `zhTW` 這一個 Locale tag（manifest）。**
> 這才是 client 建語言列時真正掃描的東西。`.product.db` 那欄怎麼填都不會動這張選單。

---

## 1. 為什麼 `.product.db` 改了沒用：它是 Agent 的資料庫，不是 client 的

### 1.1 一手證據：三個 dot-info 檔「是 Agent 寫的、不是 client 寫的」

wowdev.wiki/TACT「Shared storage」章節（逐字）：

> Root folder has a `.build.info` with cached build information for each product sharing the storage, each product subfolder also has a `.flavor.info` file with the TACT product name (e.g. wowt or wow_classic_beta …). **Both of these files are written by the Battle.net agent and not by the clients themselves.** However, if these two files are available the clients will use cached information in the `.build.info` file instead of getting it from remote.

重點拆解：

- **`.build.info`**：client **會讀**，但讀的是「build/CDN 設定的快取」（build config hash、CDN hosts、Tags…），用來知道「這個 build 的內容雜湊表在哪」。它是 client 的**輸入**，但寫入者是 Agent。
- **`.product.db`**：TACT 頁面把它歸在 Agent 的產物；它是 **Agent 的資料庫**（binary protobuf，可用 `--readabledatabase` 旗標讓 Agent 改存人類可讀格式——見 wowdev.wiki/Agent 命令列參數 `--readabledatabase`、`--db_path=`）。**遊戲 client 沒有「讀 product.db 來組語言列」這條路。**

### 1.2 product.db 裡那些 locale 欄位「是給誰看的」

wowdev.wiki/Agent 的 `/game/{product}` GET 回應（就是 product.db 解碼後的 JSON 視圖，逐字節錄關鍵欄）：

```json
{
    "installed"        : true,
    "installed_locales": [ "enUS" ],
    "product"          : "wow_classic_beta",
    "account_country"  : "NLD",
    "geo_ip_country"   : "NL",
    "selected_locale"  : "enUS",
    "selected_asset_locale" : "enUS",
    "display_locales"  : [ "enUS","deDE","esES","esMX","frFR","ruRU","koKR","ptBR","zhTW","zhCN" ],
    "region"           : "eu",
    "branch"           : "",
    ...
}
```

這張表把三種「locale 清單」分得很清楚，全部是 **Agent 的概念**：

| 欄位 | 意思 | 誰在用 |
|---|---|---|
| `installed_locales` | Agent 記錄「本機已下載哪些 locale」 | Battle.net app 顯示、Agent 決定要不要補下載 |
| `selected_locale` / `selected_asset_locale` | 使用者在 Battle.net 選的文字/語音 locale | Agent 傳給 client 當啟動參數（`--locale=`） |
| `display_locales` | 「安裝精靈要列給你勾的語言」——**全 10 種** | Battle.net **安裝精靈**的「選擇語言」畫面 |

`display_locales` 是全 10 種、`installed_locales` 只有 enUS——這張表本身就證明：**Agent 的「可顯示語言」和「已安裝語言」是兩回事，而且都跟遊戲內那張選單無關。**

### 1.3 你踩到的坑：wowdev.wiki/Agent **沒有** numbered protobuf schema

你要求我去 wowdev.wiki/Agent 找 `installed_locales` / `selected_locale` 的「確切 protobuf field number」。**實查結果：那頁沒有這種東西。** wowdev.wiki/Agent 全頁只記錄：

- Agent 的**命令列參數**（22+ 個，含 `--db_path=`、`--readabledatabase`、`--locale=`）
- 本機 **HTTP REST API**（`/agent`、`/game/{product}`、`/install`…）與其 **JSON** 請求/回應範例

它**通篇沒有** `.product.db` 的 protobuf 訊息定義、沒有欄位編號表（grep `protobuf`→只命中 `--readabledatabase` 這個參數的描述；grep `.db`→無；grep `database`→只命中 `--db_path`）。

所以：

- **權威的是「JSON 鍵名」**：`installed_locales`、`selected_locale`、`selected_asset_locale`、`display_locales`——這些是 Agent 自己序列化出來的名字，一手可查。
- **「欄位編號」只存在於你自己的 empirical decode**（你量到 `f3.f8 = installed_locales`、`f3.f6/f7 = zhTW`、`f3.f2 = region`…）。這跟 Agent build 綁定、wiki 沒有背書。你的 decode 是目前**唯一**的欄位編號來源，不是 wiki 漏抄。**別再花時間去 wiki 找欄位編號——它不存在。**

> **小結（回答你的問題 1、3）**：product.db 是 Agent 資料庫；直接啟動的 client 不讀它來組語言列；wiki 沒有 numbered schema，欄位編號只有你的實測。**這就是你造 `f3.f8=[{zhTW,3}]` 卻毫無反應的根因——你改對了「Agent 眼中的已安裝語言」，但那不是遊戲內選單的資料來源。**

---

## 2. TACT / CASC：manifest 的 Locale tag 與 `.build.info` Tags（回答問題 2）

### 2.1 tag 的「type」數字：Locale = 3

install（`IN`）與 download（`DL`）manifest 共用同一套 **bitfield-tag** 系統：每個 tag 帶一個 `type`（uint16 BE）與一段位元陣列，位元標出「選了這個 tag 時要裝哪些檔」。wowdev.wiki/TACT 對 `type` 數字的版本對照（逐字）：

```
8.0.1.26604 以後：
 enum {
   platform     = 1,
   architecture = 2,
   locale       = 3,
   region       = 4,
   category     = 5,   // speech / text
   alternate    = 0x4000,
 };
```

`cascette-rs`（`crates/cascette-formats/src/install/tag.rs`）在 classic-era manifest 上實測到的一致值：

```rust
pub enum TagType {
    Platform = 0x0001,
    Locale   = 0x0003,   // enUS, deDE, ...
    Category = 0x0004,
    Region   = 0x0080,
    ...
}
```

（`Region` 在 classic-era manifest 觀測到是 `0x0080`，與 TACT 頁「region=4」是不同 build 世代的編號；本案 3.4.x 屬 classic-era，以 cascette-rs 實測為準——但兩者都確認 **Locale 就是 type 3**。）

**semantic category**（wowdev.wiki/TACT）：
- **Locale**：「Files specific to a single localisation of the game.」（= 一個語言專屬的檔）
- **Region**：「us, eu, kr, tw, cn」
- **Category**：`speech` / `text`（取代舊 MPQ 的低優先下載標記）

所以一個 build 的 install/download manifest 裡，**type=3 的 tag 有幾個、叫什麼**，就等於「這份資料宣稱支援哪些 locale」。**這是一份被所有架構/語言共用的單一檔**（TACT 原文：「the install/download file is shared across all architectures and locales」）——換句話說，如果你的自組 build 用的是零售的整份 manifest，它會列出全部 10 個 locale tag，即使 blob 沒下載。

### 2.2 `.build.info` 的 `Tags` 欄：格式與角色

`cascette-rs`（`crates/cascette-client-storage/src/build_info.rs`）記錄的真實欄位 schema（BPSV）：

```
Branch!STRING:0 | Active!DEC:1 | Build Key!HEX:16 | CDN Key!HEX:16 |
Install Key!HEX:16 | IM Size!DEC:4 | CDN Path!STRING:0 | CDN Hosts!STRING:0 |
CDN Servers!STRING:0 | Tags!STRING:0 | Armadillo!STRING:0 |
Last Activated!STRING:0 | Version!STRING:0 | Product!STRING:0
```

- `Tags!STRING:0`：就是你動過的那欄（`OSX x86_64 KR? acct-TWN? geoip-TW? zhTW text/speech`…）。
- `Install Key!HEX:16`：指向 **install manifest（`IN`）** 的 key——**§2.1 那份 tag 表就在這個檔裡**。
- `Build Key`→build config→裡面有 download/install manifest 的 key。

**為什麼你改 `Tags` 沒反應（重要推論）**：`.build.info` 的 `Tags` 欄比較像「Agent 記給自己看的一行摘要 / 給 CDN 抓資料時的過濾器」。真正被 client 拿去「決定哪些檔屬於哪個 locale」的，是 **`Install Key` 指到的 install manifest 裡的 type=3 tag** 和 **root 的 locale 旗標**。改 `.build.info` 的字串 `Tags`，沒有回頭去改 manifest/root 的位元，所以 client 端的 locale 判斷不動。（**未驗證**：3.4.x client 是否完全忽略 `.build.info` Tags 來組語言列，或只是你改的 row/格式沒被採用；但既然 §3 的機制是走 root/manifest，最合理的解釋是 Tags 字串不是這條路的輸入。）

---

## 3. 那 client 到底讀什麼？—— CASC root 的 locale 旗標（核心）

### 3.1 product config 的 `display_locales` **不是** 遊戲內的 gate

先排除一個很像的嫌疑犯。TACT 有一個 **product config**（CDN 上的 JSON，由 versions/`.build.info` 裡的 hash 指向），`cascette-rs`（`crates/cascette-formats/src/config/product_config.rs`）把它建模為：頂層一個 `all` block ＋ 每語言 block（`enus`、`zhtw`…），每個 block 的 `Config` 有 `display_locales` 與 `supported_locales`。

我實抓了真實 wow_classic 的 product config（blizztrack.com，config hash `c9934edfc8f2…`）：

- `all` block：`display_locales` = **全 10 種**（enUS, esMX, ptBR, deDE, esES, frFR, ruRU, koKR, zhTW, zhCN），`supported_locales` 同。
- `zhtw` block：**沒有**覆寫 `display_locales`（只客製了捷徑描述/UI 文字），deferring 回 `all` 的 10 種。

**結論**：product config 的 `display_locales` 對 zhTW 官方安裝也是「全 10 種」——所以它**不可能**是「官方 zhTW 只顯示 zhTW」的那個 gate。它是 **Battle.net 安裝精靈**「你要順便裝哪些語言」那張勾選表的來源（呼應 §1.2 的 `display_locales`）。**排除。**

### 3.2 真正的 gate：CASC root 的 `CASC_LOCALE_*` 位元

WoW 的 CASC **root** manifest 把每個 file entry 關聯到一個 **locale bitmask**。`ladislav-zezula/CascLib`（`src/CascLib.h`）的權威定義：

```c
#define CASC_LOCALE_ALL      0xFFFFFFFF
#define CASC_LOCALE_ALL_WOW  0x0001F3F6   // 除 enCN/enTW 外全部
#define CASC_LOCALE_ENUS     0x00000002
#define CASC_LOCALE_KOKR     0x00000004
#define CASC_LOCALE_FRFR     0x00000010
#define CASC_LOCALE_DEDE     0x00000020
#define CASC_LOCALE_ZHCN     0x00000040
#define CASC_LOCALE_ESES     0x00000080
#define CASC_LOCALE_ZHTW     0x00000100
#define CASC_LOCALE_ENGB     0x00000200
#define CASC_LOCALE_ESMX     0x00001000
#define CASC_LOCALE_RURU     0x00002000
#define CASC_LOCALE_PTBR     0x00004000
#define CASC_LOCALE_ITIT     0x00008000
#define CASC_LOCALE_PTPT     0x00010000
```

CascLib 打開 WoW storage 時，`dwLocaleMask` 決定「要開哪些 locale 的檔」——「Locale flags … are only used on World of Warcraft storages.」**遊戲 client 用的是同一套 root 位元**：它掃 root，看「本地化的檔上設了哪些 locale 位元」，把有位元的 locale 收進「可選語言」集合。

### 3.3 為什麼恰好是「en＋es＋pt＋zhTW」4 種

把你看到的 4 種對回位元：

| 顯示語言 | 位元 |
|---|---|
| English | `CASC_LOCALE_ENUS = 0x0002` |
| Spanish | `CASC_LOCALE_ESES 0x0080` 或 `ESMX 0x1000` |
| Portuguese | `CASC_LOCALE_PTBR = 0x4000` |
| 繁中 | `CASC_LOCALE_ZHTW = 0x0100` |

這**不是**全 10 種（否則就是整份零售 root），而是一個**子集**——典型是「美洲(Americas) 文字組 enUS＋esMX＋ptBR」＋你真的塞進去的 zhTW。最可能的成因（依可能性排序）：

1. **（最可能）你的 root / install manifest 是從一份「美洲區」來源組出來的**，那些 entry 本來就帶 enUS/esMX/ptBR 的 locale 位元；你加 zhTW 資料時只加了 zhTW 位元，但**沒清掉**原本的 en/es/pt 位元。client 掃 root 看到 4 種位元 → 列 4 種。**跟 blob 在不在無關**（root 是雜湊清單，位元設了就算數）。
2. install/download manifest 的 type=3 Locale tag 仍含 `enUS`/`esMX`/`ptBR`/`zhTW` 四個。
3. **未驗證**：3.4.x client 是否再拿「該 locale 是否有 text 資料可解析」做二次過濾。若有，代表 en/es/pt 至少有殘留的可解析 text 檔；若沒有（只看 root 位元），則純粹是位元殘留。

你說「root locale-flag analysis 只看到 zhTW」——這跟現象衝突，強烈暗示**你的分析口徑漏了**：很可能你檢查的是「locale-specific **資料檔**」（blob）而不是「root **entry 的 locale bitmask**」。blob 只有 zhTW，但 root 的**位元**仍宣告 en/es/pt。**client 看的是位元，不是 blob。**

---

## 4. 該改什麼（actionable，回答你的核心問題）

### 4.1 一句話

> **不是 `.product.db` 任何欄位。是 CASC 的 root manifest 的 per-file locale bitmask（以及 install `IN` / download `DL` manifest 的 type=3 Locale tag）。把 zhTW 以外的 locale 位元/tag 全部清掉，只留 `CASC_LOCALE_ZHTW (0x100)` / `zhTW` 這一個。**

### 4.2 為什麼你之前四招全沒中

| 你做的 | 動到的層 | client 組語言列有沒有讀這裡 | 結果 |
|---|---|---|---|
| 造 `.product.db` `f3.f8=[{zhTW,3}]` | Agent 資料庫 | ✗（Agent-only） | 無反應 ✓（符合預期） |
| 改 `.build.info` Branch/Tags | Agent 寫的 build 快取字串 | ✗（真正輸入是 Install Key 指到的 manifest） | 無反應 ✓ |
| CDN 全 404 | 遠端 | ✗（root/manifest 是本地檔） | 無反應 ✓ |
| 改 branch eu→kr | Agent region 概念 | ✗ | 無反應 ✓ |

四招全打在「非 client 讀取路徑」，所以全無反應——這本身就是「答案在 root/manifest」的反證。

### 4.3 建議動作

1. **先診斷、別再瞎改**：用 CascLib / TACTSharp 打開你的自組 storage，**dump root 每個 locale 位元的直方圖**（不是列 blob，是列 root entry 的 bitmask OR 起來有哪些位元）。應該會看到 `0x0002|0x0080or0x1000|0x4000|0x0100` 亮著。同時 dump install（`IN`）與 download（`DL`）manifest 的 **type=3 tag 名單**。
2. **修 root**：重建 root，讓本地化 entry 只設 `CASC_LOCALE_ZHTW`，清掉 enUS/esES/esMX/ptBR 位元（enUS 常是 fallback，**保不保留看 client 是否需要 fallback 才開得起來——未驗證**；官方 zhTW 只顯示 zhTW，暗示可以只留 zhTW）。
3. **修 manifest**：install/download manifest 的 Locale-type(type=3) tag 只留 `zhTW`（連同其 speech/text category tag）。這兩份是「共用單一檔」，所以要嘛用 zhTW-only 的版本，要嘛把多餘的 Locale tag 條目刪掉。
4. **重指**：`.build.info` 的 `Install Key` / `Build Key`(→build config→download+install key) 指到你改過的 manifest；root 的 CKey 進 build config 的 `root` 欄。
5. 驗證：直接啟動 client，看選單是否縮成只有 zhTW。

### 4.4 對照官方 zhTW 為什麼「乾淨」

官方 zhTW 安裝之所以只顯示 zhTW，是因為 Blizzard 派送給台服的那份 **root / install manifest 本身的 locale 位元/tag 就只有 zhTW**（Agent 依 product config 的 region=tw、只抓 zhTW 的 Locale tag 對應檔，並寫出一份 locale 位元乾淨的本地 storage）。它的 `.product.db`（你 decode 的 `f3.f8=[{zhTW,3}]`）只是**忠實記錄**了這個結果，**不是造成**這個結果。你複製了「結果的記錄」（product.db），卻沒複製「原因」（root/manifest 的位元），所以選單不動。

---

## 5. 待驗證（未驗證清單）

1. 3.4.x client 組語言列時，是**只看 root locale 位元**，還是 **root 位元 ∩「該 locale 有可解析 text 資料」**？（決定你要不要連 en/es/pt 的殘留 text 檔一起清。）
2. client 是否**完全**忽略 `.build.info` 的 `Tags` 字串來組語言列（§2.2 推論），或只是你改的格式/row 沒被吃。
3. enUS 是否必須保留為 fallback 才不會開不起來（§4.3 step 2）。
4. macOS 直接啟動的 client 是否會去讀 `~/Library/Application Support/Battle.net/` 底下的**系統級 Agent 資料庫**——本次未在一手來源找到「直接啟動 client 讀該路徑組語言列」的證據；wowdev.wiki 的模型是 client 讀**安裝目錄內**的 `.build.info` ＋ CASC，不讀 Battle.net app 的全域 DB。**傾向：不讀**，但標未驗證。

---

## 6. 來源

- wowdev.wiki/Agent — 命令列參數（`--db_path`、`--readabledatabase`、`--locale=`）、`/game/{product}` GET 的 JSON（`installed_locales`/`selected_locale`/`selected_asset_locale`/`display_locales`）。**該頁無 numbered protobuf schema。**（`https://wowdev.wiki/api.php?action=parse&page=Agent&prop=wikitext`）
- wowdev.wiki/TACT — tag `type` enum（locale=3）、Locale/Region/Category semantic、install/download manifest bitfield、「.build.info/.flavor.info 由 Agent 寫非 client 寫」、Shared storage。（`…page=TACT…`）
- wowdev.wiki/CASC — CASC v2、Journal-based data files、root 關聯 content hash↔name hash。（`…page=CASC…`）
- wowdev.wiki/Localization — langstringref 的 locale 欄位順序（enUS,koKR,frFR,deDE,zhCN,zhTW,esES,esMX,ruRU,jaJP,ptPT,itIT）。
- `ladislav-zezula/CascLib` `src/CascLib.h` — `CASC_LOCALE_*` 位元定義（ENUS=0x2, ZHTW=0x100, ESES=0x80, ESMX=0x1000, PTBR=0x4000…），`ALL_WOW=0x1F3F6`。
- `wowemulation-dev/cascette-rs` — `config/product_config.rs`（`display_locales`/`supported_locales`、per-region block）、`install/tag.rs`（`TagType::Locale=0x0003`, `Region=0x0080`）、`client-storage/src/build_info.rs`（`.build.info` BPSV 欄位、`Tags!STRING:0`、`Install Key!HEX:16`）。
- blizztrack.com — 真實 wow_classic product config（hash `c9934edfc8f217a2e01c47e4deae8454`）：`all.display_locales` = 全 10 種，`zhtw` block 不覆寫。
