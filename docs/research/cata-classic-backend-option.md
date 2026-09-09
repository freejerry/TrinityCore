# 用 `cata_classic` 血統當後端、把 3.3.5 內容降版過去 —— 提案評估

> 撰寫日期：2026-09-04
> 相關筆記：[HermesProxy 決策級評估](./hermesproxy-evaluation.md)（現行運作中的 stack）、[WotLK Classic 移植路線圖](./wotlk-classic-port-roadmap.md)（本篇沿用其 §3.2 的舊 lineage 發現並加以修正）、[在 TrinityCore 上跑 WotLK Classic](./wotlk-classic-on-modern-client.md)、[hotfix DB2 中文化深度評估](./hotfix-db2-localization.md)、[zhTW 中文化能做到哪裡](./zhtw-localization.md)
> 前提（既定事實，非假設）：使用者手上有 **Windows 版 WoW Classic `3.4.3.54261`**（Apple Silicon + Wine），現行 stack `3.4.3 client → Xian55/HermesProxy@feature/wotlk-classic-v3.4.3 → TrinityCore 3.3.5 + MariaDB(Docker)` **已經實際玩得動**：登入、建角、進世界、任務、戰鬥皆通，並已完成 12 張 world `*_locale` 表 + 約 28 張 client DB2 的 zhTW hotfix 推送。
> 來源限定 primary sources：本 repo 的唯讀 git（`origin/*`、tag `TDB343.*`，**未切換分支、未修改任何追蹤檔案**）、`gh api` 對 `TrinityCore/TrinityCore` 的 repo / branches / releases。凡未實跑者一律標示「**未驗證**」。未使用瀏覽器自動化。

---

## 0. TL;DR —— 直說

**這個提案的「形狀」是錯的，但它指向的東西是對的。**

1. **提案本身（`cata_classic` + 內容降版）是回歸。** `cata_classic` 是 **4.4.2.60895** 的伺服器。把 3.3.5 內容搬進它的 world schema，**不會讓 3.4.3 client 連得上**——協定、opcode 表、DB2 layout hash 全部是 4.4.2 的。內容與協定是兩件互不相干的事，換內容不會換協定。**proxy 不但沒被移除，反而變成需要一個「4.4.2 ↔ 3.4.3」的 proxy，而那東西不存在**（HermesProxy 的 legacy 後端只認 `V1_12_1_5875` / `V2_4_3_8606` / `V3_3_5a_12340`）。
2. **提案裡「把 3.3.5 內容降版過去」這件事，上游在 2024 年就做完並發行了。** tag `TDB343.24081`（commit `92796557f9`，2024-08-17）附有官方 release `TDB_full_343.24081_2024_08_17.7z`（**84,836,093 bytes，975 次下載**）。
3. **★ 本次調查最重要的一項：`TDB343.24081` 的目標 build 就是 `3.4.3.54261` —— 使用者手上那一份，一個位元不差。** 實測 `sql/base/auth_database.sql` 的 `build_info` 末列：`(54261,3,4,3,NULL,NULL,'25FD812475DCF26F9F1383AED37FC99E',NULL,NULL,NULL);`。**這是唯一一個真正「原生、無 proxy、且吃得下我們這個 client」的既存 TrinityCore 產物。**
4. **所以真正的問題不是「`cata_classic` 還是 `cata_classic`+proxy」，而是第三個選項（c）：直接建 `TDB343.24081` 這個 tag，不 rebase、不遷移、就用它自己的 build 跑。** 前置工作量從「數月」掉到「幾天」。
5. **但它是一個死在 2024-08-17 的快照，且不在任何分支上**（`git branch -r --contains TDB343.24081` 回傳空）。往前 rebase 到今天的 `cata_classic` 是 **3,489 檔 / +2,978,881 / −1,188,278** 的差距——那不是 rebase，是重寫。**要嘛凍結著用，要嘛別碰。**
6. **中文化這一塊反而是升級，不是損失。** TrinityCore 現代分支的 hotfixes DB 本來就是**逐表逐語系**的：`cata_classic` 有 **82 張 `*_locale` 表**、`TDB343.24081` 有 **98 張**，`HotfixDatabase.cpp` 為每張表準備了 `PREPARE_LOCALE_STMT`，`DB2Manager` 的 hotfix 容器是 `std::array<..., TOTAL_LOCALES>`，`LOCALE_zhTW = 5` 是一等公民。**我們在 HermesProxy 寫的那 ~28 支 loader，在這裡退化成「INSERT 幾行 SQL」。**
7. **唯一明確的中文化退步：`Spell.db2`（法術描述）。** `cata_classic` 與 `TDB343.24081` 都**只載 `SpellName.db2`**，hotfixes DB 裡**沒有 `spell` / `spell_locale` 表**。法術描述 / 光環描述的繁中要另外手工加一整條 DB2 支援鏈。
8. **裁決：不是更好的路，是值得花一個週末的平行實驗。** 現行 stack 已經在玩了；`TDB343.24081` 的價值在於它可能一步跨過 proxy 的整條長尾 bug。**先建起來看它會不會編、會不會進世界，再決定。在那之前不要動現行 stack 一根寒毛。**

---

## 1. 問題一：這真的移除了 proxy 嗎？

### 1.1 三種形狀，逐一裁定

| 形狀 | 內容 | 裁定 |
|---|---|---|
| **(a)** `wotlk_classic` rebase 到現在的 `cata_classic` | 得到一個 **3.4.4.61581** 的伺服器 | ❌ **build 不對。** 我們的 client 是 3.4.3.54261。見 §1.2 |
| **(b)** `cata_classic` + 一個 proxy | 需要「4.4.2 ↔ 3.4.3」翻譯層 | ❌ **這東西不存在。** HermesProxy 的 `LegacyServerOptions:Build` 允許值只有 `auto` / `V1_12_1_5875` / `V2_4_3_8606` / `V3_3_5a_12340`（見 [HermesProxy 筆記](./hermesproxy-evaluation.md)§3.1）。而且方向也反了：proxy 是把「新 client 講給舊 server 聽」，`cata_classic` 比 client 還新 |
| **(c)** **直接用 `TDB343.24081` tag（3.4.3.54261 原生）** | 不 rebase、不遷移、就用它 | ✅ **唯一能原生服務我們這個 client 的組合。** 見 §1.3 |

### 1.2 為什麼 (a) 不行——3.4.3 與 3.4.4 在線路上不是同一個東西

實測三個 ref 的同一組 opcode 數值（`src/server/game/Server/Protocol/Opcodes.h`）：

| opcode | `TDB343.24081`（3.4.3.54261） | `origin/wotlk_classic`（3.4.4.61581） | `origin/cata_classic`（4.4.2.60895） |
|---|---|---|---|
| `CMSG_ACCEPT_GUILD_INVITE` | **`0x35FE`** | `0x3A0029` | `0x390029` |
| `CMSG_ACTIVATE_TAXI` | **`0x34AB`** | `0x360036` | `0x350035` |
| `CMSG_ACCEPT_TRADE` | **`0x315A`** | `0x350005` | `0x340005` |

**注意 3.4.3 與 3.4.4 連編碼形制都不同**（前者是平坦數值，後者是 `handler group << 16 | id`）。這不是「差幾號」，是整張表換掉。

其他佐證（全部唯讀實測）：

- `origin/wotlk_classic:sql/base/auth_database.sql` 內 **`54261` 出現 0 次**，`61581` 出現 **10 次**。它從未支援過我們這個 build。
- `origin/wotlk_classic:src/server/game/DataStores/DB2Stores.cpp:826-832` 的版本哨兵註明 `// last area added in 3.4.4 (60340)`、`sItemStore.LookupEntry(242551)`、`sSpellNameStore.LookupEntry(1233554)`；`TDB343.24081` 的對應處是 `// last ... added in 3.4.3 (51943)`、`sItemStore.LookupEntry(211851)`、`sSpellNameStore.LookupEntry(429548)`。**哨兵不過就 `TC_LOG_ERROR` 拒絕啟動。**
- `DB2Metadata.h` 的 `LayoutHash` / `FieldCount` 綁死 client build（[路線圖](./wotlk-classic-port-roadmap.md)§4.2）。

→ **「把 `wotlk_classic` 指向 3.4.3.54261」＝ 把它 3.4.4 化的每一項工作反向做一次**（opcode 表、`DB2Metadata.h` 19,874 行、`DB2LoadInfo.h` 6,152 行、`UpdateFields`、343 張 hotfix 表的 schema）。**那正好是這個分支存在的全部理由。反著做一遍等於把它刪掉。**

### 1.3 為什麼 (c) 可行——`TDB343.24081` 本來就是 3.4.3.54261 的伺服器

| 項目 | 實測值（`TDB343.24081`） |
|---|---|
| commit | `92796557f9b0ba3d2d1c7c770f535153154cf83e`，2024-08-17 22:03:13 UTC，訊息 `TDB 343.24081 - 2024/08/17` |
| `build_info` 末列 | **`(54261,3,4,3,NULL,NULL,'25FD812475DCF26F9F1383AED37FC99E',NULL,NULL,NULL);`** |
| `realmlist.gamebuild` 預設 | `53788` |
| `CURRENT_EXPANSION` | `EXPANSION_WRATH_OF_THE_LICH_KING`（`SharedDefines.h:105`） |
| `CONF_Product` | `wow_classic` |
| DB2 版本哨兵 | `sAreaTableStore(14483)` / `sCharTitlesStore(757)` / `sItemStore(211851)` / `sMapStore(2567)` / `sSpellNameStore(429548)`，註解 **`3.4.3 (51943)`** |
| `Opcodes.h` 行數 | 2272 |
| `DB2Storage<>` 數 | 325 |
| world / hotfixes 表數 | **236 / 443** |
| 在哪個分支上 | **不在任何分支上**（`git branch -r --contains` 空） |

**關於 auth seed 的一項細節：** `TDB343.24081` 的 auth DB **沒有 `build_auth_key` 表**（那是 `cata_classic` / `wotlk_classic` 之後才有的新機制），它用舊的 `build_info` 欄位 `winAuthSeed` / `win64AuthSeed` / `mac64AuthSeed`。54261 那一列填的是 **`win64AuthSeed`**，`mac64AuthSeed` 為 `NULL`。**我們的 client 正好是 Windows 版（在 Wine 下跑），所以填的那一格就是我們需要的那一格。** 這是個運氣。

**結論（問題一）：形狀是 (c)，不是 (a) 也不是 (b)。而 (c) 是真的沒有 proxy。**

---

## 2. 問題二：`origin/wotlk_classic` 今天的狀態（重新實測，2026-09-04）

```
git ls-remote --heads origin
git log -1 --format='%ci %h %s' origin/wotlk_classic
git merge-base origin/cata_classic origin/wotlk_classic     → af8de3493f
git rev-list --count origin/cata_classic..origin/wotlk_classic   → 31
git rev-list --count origin/wotlk_classic..origin/cata_classic   → 1264
git diff --stat af8de3493f origin/wotlk_classic | tail -1
```

| 項目 | 值 |
|---|---|
| 最後 commit | `12c81a6f86`，**2025-07-02T01:49:56Z**（`gh api` 與本機 git 一致）→ **停滯 14 個月** |
| 領先 `cata_classic` | **31** commits |
| 落後 `cata_classic` | **1264** commits |
| diffstat | **57 files changed, 32,696 insertions(+), 12,013 deletions(-)** |
| world / hotfixes 表數 | 241 / 354 |
| `revision_data.h.in.cmake` | 仍指 `TDB_full_world_442.25051_2025_05_11.sql` / `TDB_full_hotfixes_442.25051`（**Cataclysm 的 DB**） |
| `build_info` 末列 | `(61581,3,4,4,NULL);` |
| 針對它的 PR 總數（歷來） | **13** |
| 上游 repo description（2026-09-04 實測） | `master = 12.1.0.69497, 3.3.5 = 3.3.5a.12340, cata classic = 4.4.2.60895` —— **仍不含 `wotlk_classic`** |

對照組（同時實測）：`origin/master` `bccf42d4ac` 2026-09-03、`origin/cata_classic` `3bc146f58a` 2026-08-31、`origin/3.3.5` `65f4f04650` 2026-08-30。

### 2.1 3.4.4 對 3.4.3 的意義

**需要 3.4.4.61581 嗎？** 若走 (a)，是的——而 [路線圖](./wotlk-classic-port-roadmap.md)§1.2 已實測該 build 的 CDN build config 為 **404**。**但這個問題現在不重要了**：走 (c) 根本不需要 3.4.4，需要的是 3.4.3.54261，**而那一份使用者已經有了**。

**能不能把它指向 3.4.3.54261？** 不能，理由見 §1.2。**而且沒有必要**——`TDB343.24081` 已經是 3.4.3.54261 的完成品。**`wotlk_classic` 對我們這個 client 而言，提供不了任何 `TDB343.24081` 沒有的東西。**

---

## 3. 問題三：TDB343 releases 與 schema 距離（重新驗證）

### 3.1 兩個 release 都在，且都是官方的

```
gh api repos/TrinityCore/TrinityCore/releases --paginate \
  --jq '.[]|select(.tag_name|startswith("TDB343"))|"\(.tag_name) \(.published_at) \(.assets[].name):\(.assets[].size):dl=\(.assets[].download_count)"'
```

| tag | 發佈時間（UTC） | asset | 大小 | 下載數 | 目標 build（`build_info` 末列） |
|---|---|---|---|---|---|
| `TDB343.23121` | **2023-12-20T23:32:59Z** | `TDB_full_343.23121_2023_12_20.7z` | **65,148,397 B** | **1,348** | `(52237,3,4,3,...)` |
| **`TDB343.24081`** | **2024-08-17T22:03:17Z** | `TDB_full_343.24081_2024_08_17.7z` | **84,836,093 B** | **975** | **`(54261,3,4,3,...)`** |

`TDB343.24081:revision_data.h.in.cmake` 同時指名兩個檔：`TDB_full_world_343.24081_2024_08_17.sql` 與 `TDB_full_hotfixes_343.24081_2024_08_17.sql` → **這個 7z 裡是 world + hotfixes 兩套，不是只有 world。**

對照今日各線最新 TDB（同一次 API 取得）：`TDB442.26081`（2026-08-14）、`TDB335.25101`（2025-10-21）、`TDB1200.26021`（2026-02-06）。**343 這條線在 2024-08-17 之後再無新版。**

### 3.2 world schema 距離：9 張表（重新逐表比對，數字與前一篇一致）

```
git show <ref>:sql/base/dev/world_database.sql | grep '^CREATE TABLE' | sed 's/CREATE TABLE .\([a-z_0-9]*\).*/\1/' | sort
```

| ref | world 表數 |
|---|---|
| `origin/3.3.5` | 186 |
| **`TDB343.24081`** | **236** |
| `origin/cata_classic` | 239 |
| `origin/wotlk_classic` | 241 |

`TDB343.24081` vs `origin/cata_classic` 的對稱差 = **3 + 6 = 9**：

- **只在 TDB343**：`map_corpse_position`、`spell_scripts`、`warden_checks`
- **只在 cata_classic**：`battleground_scripts`、`creature_immunities`、`creature_quest_currency`、`creature_static_flags_override`、`destructible_hitpoint`、`quest_treasure_pickers`

hotfixes schema 差距**大得多**（前一篇未量）：

| ref | hotfixes 表數 |
|---|---|
| `TDB343.24081` | **443** |
| `origin/cata_classic` | 354 |
| `origin/wotlk_classic` | 354 |
| `origin/master` | 467 |

對稱差：**只在 TDB343 有 100 張、只在 cata_classic 有 11 張**。只在 TDB343 的那 100 張裡有大量 retail 殘留（`garr_*` 要塞、`artifact_*` 神器、`azerite_essence*`、`trait_*`、`chr_specialization_locale`、`pvp_talent_locale`…），因為它是從 **2023-11 的 `master`** 分岔的。

### 3.3 「把 3.3.5 內容降版」實際上還要做多少？—— 幾乎為零，因為它已經做完了

**這是本節最重要的一句：提案想做的事，`TDB343.24081` 就是它的成品。** 該 lineage 的 commit 訊息本身就是施工紀錄（[路線圖](./wotlk-classic-port-roadmap.md)§3.2 已全文引用）：`DB/GameObjects: migrate gameobject_template from 3.3.5 branch`、`DB/Creatures: removed all creatures ... not been present in the 3.3.5 database`、`DB/Quests: updated quest template, poi and objective data for WotLK classic`、`DB/Transports: backported transports from 3.3.5 branch`。

**所以真正的工作量問題不是「怎麼降版」，而是「要不要把它往前遷移」——而答案應該是不要**（見 §5.1 的數字）。**用它自己的 build、自己的 schema、自己的 DB 跑，9 張表的差距就完全不必付。**

---

## 4. 問題四：相對現行 HermesProxy stack 的得與失

### 4.1 得到

| 項目 | 具體 |
|---|---|
| **原生協定** | 3.4.3 client ↔ 3.4.3 server，沒有翻譯層。[HermesProxy 筆記](./hermesproxy-evaluation.md)§2.4 那整批 Pattern A–H（驅散被拒、地面 AOE 被拒、變形卡住、聖騎士祝福、薩滿附魔…）、Warlock 靈魂碎片 DC、偶發 `CMSG_LOG_DISCONNECT(reason=7)`、以及 §2.4-B 那個「原生 server 會算、3.3.5a server 不算，翻譯層必須自己合成衍生欄位」的**結構性天花板**——**這一整類問題在原生路徑上按定義不存在。** |
| **沒有陳舊的 proxy 內建資料** | HermesProxy 靠 repo 內建的 29 個 CSV（`BattlePetSpecies3.csv` 只有 178 列，早於 Classic 期的物種）。原生路徑的 DB2 是 **`map_extractor` 從使用者自己的 3.4.3.54261 client 抽出來的**，定義上與 client 同版。 |
| **Classic 期實體有資料列** | `TDB343.24081` 的 world DB 是 retail lineage 演化來的，creature id 180k–220k 的區間**有列**（3.3.5a 的 TDB 完全沒有）。**未驗證**：本次未匯入該 DB 實際抽樣計數，僅由其 lineage 與 `TRUNCATE`+重灌式 commit 推論。 |
| **★ 中文化機制是原生且更好的** | 見 §4.3 |

### 4.2 失去

| 項目 | 具體 |
|---|---|
| **HermesProxy 的 3.4.3 修正** | 不可移植——它們是 proxy 內部的封包翻譯修正，原生路徑上沒有對應物。**但也不需要。** |
| **★ `Spell.db2`（法術描述）的中文化** | **這是最明確的一項退步。** 實測 `cata_classic` 與 `TDB343.24081` 的 `DB2Stores.cpp` **只有 `sSpellNameStore("SpellName.db2")`，沒有 `Spell.db2`**；hotfixes DB 裡也**沒有 `spell` / `spell_locale` 表**（只有 `spell_name_locale`、`spell_category_locale`、`spell_item_enchantment_locale` 等）。→ 法術描述 / 光環描述的繁中，要自己加 `DB2Structure` + `DB2LoadInfo` + `DB2Meta` + hotfix 表 + `PrepareStatements` 一整條鏈。**而 [hotfix 中文化筆記](./hotfix-db2-localization.md)§0.6 指出天賦面板的文字正是走 `Spell` 這張表。** |
| **12 張 world `*_locale` 表無法 1:1 搬** | `origin/3.3.5` 有 16 張 world `*_locale`，`TDB343.24081` / `cata_classic` 各 15 張。**只在 3.3.5 有、現代 world schema 沒有的 4 張**：`broadcast_text_locale`、`item_set_names_locale`、`item_template_locale`、`npc_text_locale`。其中 `broadcast_text_locale` 與 `item_sparse_locale`（＝ `item_template_locale` 的現代對應）**在 hotfixes DB 裡有**，所以是「換一個資料庫放」而非消失；`item_set_names` 與 `npc_text` 則沒有直接的 locale 落點。反向新增的有 `playerchoice_locale`、`playerchoice_response_locale`、`quest_objectives_locale`。 |
| **內容成熟度與維護** | 現行後端是 `origin/3.3.5`（2026-08-30 仍有 commit，官方 TDB `TDB335.25101` 2025-10-21）。`TDB343.24081` 凍結於 2024-08-17，**不在任何分支上**，永遠不會有修正。**你會是唯一的維護者。** |
| **執行前置成本** | 必須自己跑 `map_extractor` / `vmap4_extractor` / `vmap4_assembler` / `mmaps_generator` 抽 client 資料——這正是 [HermesProxy 筆記](./hermesproxy-evaluation.md)§7.3 說「你不需要做」的那一整批。 |
| **已知未完成項** | lineage 自己的 commit 寫明 `disabled Death Knight rune regeneration mechanics for the time being`；以及 [路線圖](./wotlk-classic-port-roadmap.md)§4.4 末段那個**沒有乾淨解**的問題：**1–60 舊世界＝災變前地形（client） × 災變後 spawn（server）**。 |

### 4.3 ★ 中文化：TrinityCore 的原生 hotfix 管線比我們手寫的 loader 好

**問題：「hotfix 機制在 TrinityCore 也是 server-side 的嗎？`cata_classic` / `wotlk_classic` 有沒有能吃同一份 wago.tools zhTW 資料的管線？」答案是：有，而且是一等公民。**

實測證據（全部唯讀 git）：

1. **hotfixes DB 本身就是逐表逐語系的。**
   - `origin/cata_classic:sql/base/dev/hotfixes_database.sql` → **82 張 `*_locale` 表**
   - `TDB343.24081:sql/base/dev/hotfixes_database.sql` → **98 張 `*_locale` 表**
   - 我們需要的表**全部在**（兩個 ref 皆有）：`spell_name_locale`、`achievement_locale`、`area_table_locale`、`map_locale`、`chr_classes_locale`、`chr_races_locale`、`faction_locale`、`skill_line_locale`、`battle_pet_species_locale`、`item_sparse_locale`、`broadcast_text_locale`、`talent_locale`、`currency_types_locale`、`quest_info_locale`。
2. **每一張都有現成的 prepared statement。** `src/server/database/Database/Implementation/HotfixDatabase.cpp:30-32` 定義 `PREPARE_LOCALE_STMT`，並在 `:1308` 這樣用：

   ```sql
   SELECT ID, Name_lang FROM spell_name_locale WHERE (`VerifiedBuild` > 0) = ? AND locale = ?
   ```

3. **`DB2Manager` 的 hotfix 容器本身是 locale 陣列**（`DB2Stores.cpp`）：`std::array<HotfixBlobMap, TOTAL_LOCALES> _hotfixBlob;`、`LoadHotfixBlob(uint32 localeMask)` 讀 `SELECT TableHash, RecordId, locale, Blob FROM hotfix_blob`、`GetHotfixBlobData(tableHash, recordId, LocaleConstant locale)`。
4. **`LOCALE_zhTW = 5`** 是 `src/common/Common.h:57` 裡的一等公民，`TOTAL_LOCALES` 涵蓋之。

**→ 意義：我們在 HermesProxy 手寫的那 ~28 支 loader（從 WoWDBDefs layout 產生、逐欄序列化、還要閃過 `sbyte→short` 之類的欄寬 bug），在原生路徑上退化成「把 wago.tools 的 zhTW 匯出轉成 INSERT 丟進對應的 `*_locale` 表」。** 資料可以完整重用，程式碼不必移植（也移植不了），而且維護成本大幅下降——**因為序列化與推送由 core 負責，不是由我們負責。**

**唯一要自己補的就是 §4.2 的 `Spell.db2`。** 其餘幾乎是純資料工。

**未驗證**：本次未實際匯入任何 zhTW 資料到 `TDB343.24081` 的 hotfixes DB，也未驗證 3.4.3.54261 client 會接受由 TrinityCore（而非 HermesProxy）推送的 hotfix。**但 [hotfix 中文化筆記](./hotfix-db2-localization.md)§0.3 已記錄 client 端 `Logs/Hotfix.log` 出現 `VALIDATION_RESULT_VALID`，也就是 client 對 hotfix 覆寫的接受度本身不是問題。**

---

## 5. 問題五：以證據為基礎的工作量估計

### 5.1 「rebase 到現在的 `cata_classic`」的實際規模——不要做

```
git merge-base TDB343.24081 origin/master        → e72bde5236  (2023-11-14)
git rev-list --count e72bde5236..TDB343.24081    → 257
git rev-list --count e72bde5236..origin/master   → 4018
git diff --stat TDB343.24081 origin/cata_classic | tail -1
  → 3489 files changed, 2978881 insertions(+), 1188278 deletions(-)
git rev-list --count --since=2024-08-17 origin/cata_classic       → 1946
git rev-list --count --since=2024-08-17 origin/cata_classic -- src → 1338
```

**297 萬行的差距不是 rebase 能處理的東西。** 而且方向本身有問題：往 `cata_classic` 靠攏＝往 4.4.2 靠攏＝**離我們的 client 更遠**。

**另一個容易踩的坑：`sql/updates/world/cata_classic/` 現在只剩 16 個檔**（歷次 TDB release 會把累積的 update 吸收進 base dump）。所以「replay 2024-08 以來的 world update」**不能從現在的工作目錄取得**，得從 git 歷史或 `sql/old/` 挖。**這讓「往前遷移」比 [路線圖](./wotlk-classic-port-roadmap.md)§5 Stage 6 描述的更麻煩。**

### 5.2 `TDB343.24081` 上還沒完成的東西（來自它自己的 commit 訊息與 §3 的量測）

1. **DK 符文回復被停用**（`disabled Death Knight rune regeneration mechanics for the time being`）——lineage 自述。
2. **1–60 舊世界地形 × spawn 錯位**——[路線圖](./wotlk-classic-port-roadmap.md)§4.4 末段判定為「最大的未知、可能沒有乾淨解」。本次調查**未推翻也未證實**，維持未驗證。
3. **封包覆蓋率只到 2024-08 當時測過的範圍**——維護者 funjoker 對前一代 3.4.3 分支的公開評語是 **"It's very raw and DB is no updated yet (crashes)"**（[前一篇](./wotlk-classic-on-modern-client.md)§3.4 引）。**但要注意這句是針對 `3.4.3.52237` 講的，也就是更早的 `TDB343.23121`；`TDB343.24081` 正是「DB 已更新」的那一版**（它就是 world DB release 本身）。**這句評語不能直接套到 24081 上——這是本篇對前篇的一個語境修正。**
4. **2023-11 的原始碼在 2026 的工具鏈上能不能編**（macOS clang / MariaDB / boost / OpenSSL 3.x / CMake）——**完全未驗證，本次未嘗試建置。這是第一個要回答的問題。**

### 5.3 務實的第一里程碑（不需要重寫任何東西）

> **Milestone 1：把 `TDB343.24081` 這個 tag 原封不動建起來，用使用者手上的 3.4.3.54261 client 抽資料，匯入官方 `TDB_full_343.24081`，走到角色選單。**

- **不需要**：rebase、9 張表的 schema migration、3.3.5 內容降版、`wotlk_classic` 的 31 個 commit、3.4.4 client。
- **需要**：一個獨立 worktree/clone（**不要碰現行 stack**）、能編出 `bnetserver`/`worldserver`/五個 extractor、`map_extractor` 的 local 模式指向本機 3.4.3.54261 安裝、匯入 84 MB 的 7z、`build_info` 的 54261 那列已經在。
- **完成的定義**：client 走完 Battle.net REST/protobuf 登入 → realm 選單 → 角色列表。
- **時間感**：若編得過，**以天計**；編不過則卡在 §5.2 第 4 點，那是一個要獨立評估的坑。**推估，未驗證。**
- **Milestone 2（只有 M1 過了才談）**：進世界、跑一條 1–20 任務鏈與一個諾森德副本，同時抽樣比對 `creature` 表在 map 0/1 的座標，直接回答 §5.2 第 2 點。
- **Milestone 3**：把 wago.tools 的 zhTW 匯出灌進 hotfixes 的 `*_locale` 表，驗證 §4.3 的推論。

---

## 6. 問題六：裁決

**逐條直說：**

1. **使用者提案的原形（`cata_classic` + 內容降版）＝ 回歸。** 它換了內容卻沒換協定，proxy 移除不掉，反而需要一個不存在的 proxy；而且它想做的降版工作，上游 2024 年就做完並發行了。**不要走這條。**
2. **提案指向的正確版本（`TDB343.24081` 原生 3.4.3.54261）＝ 值得的平行實驗。** 它是四條路裡唯一「原生協定 + 我們手上這個 client build」的組合，而且中文化機制比我們現在手寫的更好。
3. **但它不是「更好的路」，因為它的風險集中在一個還沒回答的問題上：2023-11 的原始碼在 2026 的 macOS 工具鏈上編不編得過。** 在那之前，任何工作量估計都是空談。
4. **現行 HermesProxy stack 是既成事實：已經在玩、已經中文化、後端官方持續維護。** 它的成本是一條沒有上限的翻譯層 bug 長尾；它的價值是**現在就能玩**。
5. **具體建議**：
   - **保持現行 stack 為主線，不動。**
   - 開一個**獨立的 clone**（不是 worktree，因為要編譯產物），`git checkout TDB343.24081`，**只回答一個問題：編不編得過。** 這是整件事的閘門，成本一個週末。
   - 編得過 → 走 Milestone 1–2，用「進世界 + 一條 1–20 任務鏈 + 一個諾森德副本」當裁決點。
   - 編不過 → **結案，回到現行 stack**，並把力氣放在 HermesProxy 已知的 open 項目上。
   - **無論如何，不要 rebase `TDB343.24081`，也不要碰 `wotlk_classic`。** 前者是 297 萬行，後者 build 不對。

**一句話：提案問錯了問題（「要不要換成 `cata_classic`」），但問對了方向（「能不能不要 proxy」）。答案是可以，路徑叫 `TDB343.24081`，而它的第一道關卡是 `cmake && make`。**

---

## 7. 驗證指令（全部唯讀，未切換 working tree、未修改任何追蹤檔案）

> ⚠️ zsh 會把 `"$ref:src/..."` 的 `:s` / `:r` 當成 history modifier 吃掉，**以下務必用 `bash -c` 執行**。

```bash
# §1.2 opcode 三方比對
bash -c 'for op in CMSG_ACCEPT_GUILD_INVITE CMSG_ACTIVATE_TAXI CMSG_ACCEPT_TRADE; do
  printf "%-28s " "$op"
  for r in TDB343.24081 origin/wotlk_classic origin/cata_classic; do
    v=$(git show "${r}:src/server/game/Server/Protocol/Opcodes.h" | grep -E "^\s+${op}\s*=" | head -1 | sed "s/.*= *//;s/,.*//")
    printf "%s=%s  " "${r##*/}" "$v"; done; echo; done'

# §1.3 / §2 build_info 末列（決定性）
bash -c 'for r in TDB343.24081 TDB343.23121 origin/wotlk_classic origin/cata_classic origin/3.3.5 origin/master; do
  printf "%s: " "$r"; git show "${r}:sql/base/auth_database.sql" | awk "/INSERT INTO .build_info./,/;\$/" | tail -1; done'
bash -c 'git show "origin/wotlk_classic:sql/base/auth_database.sql" | grep -c 54261'   # → 0
bash -c 'git show "TDB343.24081:src/server/game/DataStores/DB2Stores.cpp" | grep -n "last .* added in 3.4.3"'
git branch -r --contains TDB343.24081        # → 空

# §2 分支狀態
git ls-remote --heads origin
git log -1 --format='%ci %h %s' origin/wotlk_classic
git rev-list --count origin/cata_classic..origin/wotlk_classic   # 31
git rev-list --count origin/wotlk_classic..origin/cata_classic   # 1264
gh api repos/TrinityCore/TrinityCore --jq '{description,pushed_at}'
gh api repos/TrinityCore/TrinityCore/branches/wotlk_classic --jq '{sha:.commit.sha[0:10],date:.commit.commit.author.date}'

# §3.1 releases
gh api repos/TrinityCore/TrinityCore/releases --paginate \
  --jq '.[]|select(.tag_name|startswith("TDB343"))|"\(.tag_name) \(.published_at) \(.assets[].name):\(.assets[].size):dl=\(.assets[].download_count)"'
bash -c 'git show "TDB343.24081:revision_data.h.in.cmake" | grep -i "_DATABASE"'

# §3.2 schema 距離
bash -c 'for spec in "TDB343.24081:w343" "origin/cata_classic:wcata"; do
  ref=${spec%%:*}; out=${spec##*:}
  git show "${ref}:sql/base/dev/world_database.sql" | grep "^CREATE TABLE" \
    | sed "s/CREATE TABLE .\([a-z_0-9]*\).*/\1/" | sort > /tmp/$out; done
comm -23 /tmp/w343 /tmp/wcata; echo ---; comm -13 /tmp/w343 /tmp/wcata'
bash -c 'for r in TDB343.24081 origin/cata_classic origin/wotlk_classic origin/master; do
  printf "%s hotfix tables: " "$r"
  git show "${r}:sql/base/dev/hotfixes_database.sql" | grep -c "^CREATE TABLE"; done'

# §4.3 中文化管線
bash -c 'for r in TDB343.24081 origin/cata_classic; do printf "%s _locale tables: " "$r"
  git show "${r}:sql/base/dev/hotfixes_database.sql" | grep "^CREATE TABLE" \
    | sed "s/CREATE TABLE .\([a-z_0-9]*\).*/\1/" | grep -c "_locale"; done'
bash -c 'git show "origin/cata_classic:src/server/database/Database/Implementation/HotfixDatabase.cpp" \
  | grep -n "spell_name_locale"'                                   # PREPARE_LOCALE_STMT
bash -c 'git show "origin/cata_classic:src/server/game/DataStores/DB2Stores.cpp" \
  | grep -nE "_hotfixBlob|LoadHotfixBlob|GetHotfixBlobData"'
bash -c 'git show "origin/cata_classic:src/common/Common.h" | grep -n "LOCALE_zhTW"'   # = 5
# Spell.db2 的缺席（§4.2）
bash -c 'for r in TDB343.24081 origin/cata_classic; do printf "%s: " "$r"
  git show "${r}:src/server/game/DataStores/DB2Stores.cpp" | grep -cE "\"Spell\.db2\""; done'   # → 0 0

# §5.1 遷移規模
bash -c 'MB=$(git merge-base TDB343.24081 origin/master); echo $MB
  git rev-list --count $MB..TDB343.24081; git rev-list --count $MB..origin/master'
git diff --stat TDB343.24081 origin/cata_classic | tail -1
git ls-tree -r --name-only origin/cata_classic -- sql/updates/world | wc -l   # 16
```

---

## 8. 對既有筆記的修正／補充

| 位置 | 原文 | 本篇的修正 |
|---|---|---|
| [路線圖](./wotlk-classic-port-roadmap.md)§0.1、§3.3 | 建議「以 `cata_classic` 為 base → 疊 `wotlk_classic` 的 31 commit → cherry-pick 舊 lineage → 用 TDB 343.24081 當內容起點」 | **對「目標 build = 3.4.4」的人成立，對我們不成立。** 我們的 client 是 **3.4.3.54261**，而 `TDB343.24081` **本來就是那個 build 的完成品**。整條組裝線可以跳過——**直接建 tag 就好。** |
| [路線圖](./wotlk-classic-port-roadmap.md)§3.2 表格 | 未列 `TDB343.24081` 的目標 build 具體數值來源 | 補上實測：`build_info` 末列 `(54261,3,4,3,NULL,NULL,'25FD812475DCF26F9F1383AED37FC99E',NULL,NULL,NULL)`；`realmlist.gamebuild` 預設 `53788`；且該 lineage **沒有 `build_auth_key` 表**，用舊的 `build_info.win64AuthSeed`。`TDB343.23121` 則是 build **52237**。 |
| [前一篇](./wotlk-classic-on-modern-client.md)§3.4 | 引 funjoker「It's very raw and **DB is no updated yet** (crashes)」來描述 3.4.3 分支 | **語境要修正**：該句是針對 **3.4.3.52237**（即 `TDB343.23121` 之前）講的。`TDB343.24081` 正是「DB 已更新」的那一版。**這句不能直接套到 24081 上。** |
| [路線圖](./wotlk-classic-port-roadmap.md)§5 Stage 6 | 「把 TDB343 的 schema 往前 migrate（差 9 張表）+ replay `cata_classic` 自 2024-08 以來的 world update」 | **補一個實務障礙**：`sql/updates/world/cata_classic/` 現在**只剩 16 個檔**（TDB release 會吸收累積的 update），所以要 replay 的檔案**不在工作目錄裡**，必須從 git 歷史或 `sql/old/` 挖。**這讓 Stage 6 比原描述更麻煩——也更支持「凍結著用」的結論。** |
| [路線圖](./wotlk-classic-port-roadmap.md)§4.4 | 只比對 world schema | **補上 hotfixes schema**：`TDB343.24081` 443 張 vs `cata_classic` 354 張，對稱差 **100 / 11**（TDB343 保留大量 retail 殘留如 `garr_*` / `artifact_*` / `azerite_*` / `trait_*`）。**hotfixes 的距離遠大於 world 的 9 張。** |
| [hotfix 中文化筆記](./hotfix-db2-localization.md) | 全篇假設 hotfix 推送由 HermesProxy 的手寫 loader 負責 | **補一條替代管線**：TrinityCore 現代分支的 hotfixes DB 本身就有 **82（cata）/ 98（TDB343）張 `*_locale` 表** + `PREPARE_LOCALE_STMT` + locale-keyed 的 `_hotfixBlob`，`LOCALE_zhTW = 5`。**在原生路徑上，同一份 wago 資料是 SQL 而不是 C# loader。唯一的例外是 `Spell.db2`——TrinityCore 兩個 ref 都不載它，法術描述要自己補整條鏈。** |

---

## 9. 明確記錄「沒做／未驗證」

- **未建置**：本次**沒有**編譯 `TDB343.24081`（或任何 ref）。2023-11 的原始碼在 2026 macOS 工具鏈上能否編過，**完全未驗證，且是這條路的第一道閘門。**
- **未匯入**：沒有下載或匯入 `TDB_full_343.24081_2024_08_17.7z`。其內部檔案清單、實際表列數、creature id 分佈**皆未驗證**（§4.1 的「Classic 期實體有列」是由 lineage 與 commit 訊息推論）。
- **未驗證**：3.4.3.54261 client 是否接受由 **TrinityCore**（而非 HermesProxy）推送的 hotfix。
- **未驗證**：`TDB343.24081` 在 3.4.3.54261 上的實際封包覆蓋率、以及 1–60 舊世界 spawn 錯位的嚴重度。
- **未驗證**：`TDB343.24081` 的 `build_info` 僅填 `win64AuthSeed`，實際登入是否成功。
- **未做**：任何 client 取得途徑的調查或記錄；瀏覽器自動化；切換分支或修改任何追蹤檔案（全程唯讀 git + `gh api`）。
- **推估未驗證**：§5.3 的「以天計」時間感。

---

## 10. 實際取用過的來源

**本 repo（唯讀 git，2026-09-04 實測）**
- `origin/master`（`bccf42d4ac`）、`origin/cata_classic`（`3bc146f58a`）、`origin/3.3.5`（`65f4f04650`）、`origin/wotlk_classic`（`12c81a6f86`）
- tag `TDB343.24081`（`92796557f9`）、`TDB343.23121`（`f5c8b53b2e`）
- `sql/base/auth_database.sql`、`sql/base/dev/world_database.sql`、`sql/base/dev/hotfixes_database.sql`、`sql/updates/world/cata_classic/`
- `src/server/game/Server/Protocol/Opcodes.h`、`src/server/game/DataStores/DB2Stores.cpp`
- `src/server/database/Database/Implementation/HotfixDatabase.cpp`、`src/common/Common.h`
- `src/server/game/Miscellaneous/SharedDefines.h`、`src/tools/map_extractor/System.cpp`、`revision_data.h.in.cmake`

**TrinityCore 官方 GitHub（`gh api`）**
- `repos/TrinityCore/TrinityCore`（description / pushed_at）
- `repos/TrinityCore/TrinityCore/branches/wotlk_classic`
- `repos/TrinityCore/TrinityCore/releases`（TDB343.23121 / TDB343.24081 的 asset 名稱、大小、下載數；以及各線最新 TDB）
- `search/issues?q=repo:TrinityCore/TrinityCore+base:wotlk_classic+is:pr`（13）

**取用失敗**：無。
