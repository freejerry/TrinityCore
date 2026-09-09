# WotLK Classic（3.4.4.61581）移植路線圖

> ⚠️ **更正（2026-09-04）**
>
> 本篇引用 TrinityCore `wotlk_classic` 的 `DB2Metadata.h` 作為欄位參考——該分支 target **3.4.4.61581**，與 3.4.3.54261 不同，據此判定的「欄位不符」不可靠。正確來源是 `wowdev/WoWDBDefs` 對應 build 的 layout 區塊。
>
> 詳見 [實作記錄與更正](./zhtw-implementation-and-corrections.md)。


> 撰寫日期：2026-09-03
> 相關筆記：[TrinityCore 專案總覽](./trinitycore-overview.md)、[在 TrinityCore 上跑 WotLK Classic](./wotlk-classic-on-modern-client.md)、[開源模擬器全景調查](./classic-client-emulator-landscape.md)
> 本篇的定位：前兩篇是「可不可行 / 有沒有人做過」，本篇是**工程範圍與階段計畫**。假設使用者已決定要做，目標為個人技術專案而非公開伺服器。
> 來源限定 primary sources：本 repo 的 git 物件（唯讀，未切換分支）、TrinityCore 官方 GitHub（repo / releases / WowPacketParser）、以及 **Blizzard 自家的 TACT/CDN 端點**（實際 curl，含 HTTP 狀態碼）。凡未驗證者一律標示「**未驗證**」。
> 本篇會**修正前兩篇的兩項結論**，見 §3.2 與 §5.4。

---

## 0. TL;DR

1. **Base branch 應該用 `cata_classic`，不是 `master`。** 三項硬證據：`cata_classic` 的 talent 系統仍是 WotLK 型的 `TalentTab` 樹（`master` 已換成 Dragonflight 的 `Trait*` 系統，約 20 個 DB2 結構 + `TraitMgr.cpp`）；`cata_classic` 的 CASC product 已經是 `wow_classic`（`master` 是 `wow`）；上游自己的 `wotlk_classic` 分支正是從 `cata_classic` 切出來的（merge-base `af8de3493f`）。詳見 §2。
2. **有兩份 head start，不是一份。** 前兩篇只看到 2025 年那條 31-commit 的 spike。實際上還有一條**更有價值、被 branch reset 掩蓋掉的舊 lineage**：tag `TDB343.24081`（commit `92796557f9`，2024-08-17），從 `master` 切出、**257 個 commit、1040 個檔案、+1,040,716 行**，而且**有兩個官方 TDB world+hotfixes 資料庫 release**（`TDB343.23121`、`TDB343.24081`）。詳見 §3。
3. **最大的阻斷點不是程式碼，是 client。** 實測 Blizzard CDN：`3.4.4.61581` 的 build config **404**（對照組 live build 回 200）。Battle.net 的 `wow_classic` product 現在供應的是 **5.5.4.69585（MoP Classic）**，整個 3.4.x 與 4.4.x 都已從 CDN 清除。**沒有本機已存檔的 3.4.4.61581 client，整條路線的第 2 階段之後都跑不起來。** 詳見 §1。
4. 若手上**沒有**存檔 client，理性的作法是把目標 build 改成「現在能安裝的」——這會改變 base branch 的選擇。詳見 §1.4。

---

## 1. 前置條件（阻斷性）：你必須先擁有 3.4.4.61581 的 client 資料

這一節排在路線圖之前，因為它決定後面所有階段能不能執行。

### 1.1 Battle.net 現在供應什麼（實測）

`http://us.patch.battle.net:1119/<product>/versions`（TACT versions 端點，2026-09-03 實測）：

| product | BuildId | VersionsName |
|---|---|---|
| `wow` | 69587 | 12.1.0.69587 |
| `wow_classic` | **69585** | **5.5.4.69585**（MoP Classic） |
| `wow_classic_ptr` | 67849 | 5.5.4.67849 |
| `wow_classic_beta` | 62071 | 5.5.0.62071 |
| `wow_classic_era` | 69547 | 1.15.9.69547 |
| `wow_classic_era_ptr` | 69110 | 2.5.6.69110 |
| `wowz` | 50753 | 1.14.4.50753 |
| `wowt` | 69587 | 12.1.0.69587 |

**`wow_classic` 這個 product code 是「當前 Classic 進度」的滾動指標，不是固定資料片。** 它現在指向 MoP Classic。`cata_classic` 與 `wotlk_classic` 兩條分支的 `CONF_Product = "wow_classic"` 在寫下時是對的，但今天用它去做 remote CASC，抽到的會是 5.5.4 的資料。

### 1.2 舊 build 的 CDN 保留期（實測，附對照組）

從 Blizzard CDN 直接取 build config（`http://<host>/tpr/wow/config/<xx>/<yy>/<hash>`）：

| build | build config hash | `us.cdn.blizzard.com` | `level3.blizzard.com` |
|---|---|---|---|
| **3.4.4.61581（目標）** | `c2b611183fb96dfbde88c8f781dc5b4e` | **404** | **403** |
| 3.4.4.61581 的 CDN config | `bbfaf246fe12df7ff11f56de92d241df` | **404** | **403** |
| 4.4.2.60895 | `dae7ca8bbea21a2730c9d103a4ae9897` | 404 | 403 |
| 3.4.3.54261 | `c91609c69ed2ab39d44039390a1be969` | 404 | 403 |
| *對照組* 5.5.4.69585（live） | `a918d337491e3ffe961373f1a48df50c` | **200**（44,982 bytes） | **200** |
| *對照組* 12.1.0.69587（live） | `c9fa1a64b0170829cc5c5c98c71025c3` | **200**（87,533 bytes） | **200** |

對照組回 200 排除了「路徑寫錯 / 被擋」的可能——**404 就是真的被清掉了。**

保留期實測（同一 product、同一路徑格式）：

| build | 發佈日 | 狀態 |
|---|---|---|
| 5.5.4.69383 | 2026-08-19 | 200 |
| 5.5.4.68317 | 2026-06-24 | 200 |
| 5.5.3.67158 | 2026-04-27 | **404** |
| 5.5.3.65988 | 2026-02-18 | 404 |
| 3.4.5.63697 | 2025-10-09 | 404 |
| 3.4.4.61581 | 2025-06-23 | 404 |

→ **保留窗口大約 2–4 個月。** 這不是「3.4.x 被特別針對」，是通則。

> build config hash 來自 `https://wago.tools/api/builds`（**社群維護**，非 first-party；本文僅用它取 hash，實際的 200/404 判定全部來自 Blizzard 自家 CDN 的回應）。

### 1.3 TrinityCore 的 extractor 能不能指定舊 build？

- `src/tools/map_extractor/System.cpp:116-117` 定義 `CONF_Product = "wow"` / `CONF_Region = "eu"`，`HandleArgs()`（:179）只解析 **`-p`（product）與 `-r`（region）**（:237、:249）。
- `src/tools/extractor_common/CascHandles.cpp` 的 `Storage::OpenRemote()` 只填 `szLocalPath` / `szCodeName` / `szRegion` / `dwLocaleMask`，**沒有填 `szBuildKey`**。也就是 build 是**被偵測**的，不是**被選擇**的 → remote CASC 永遠抓當前 live build。
- 但內附的 CascLib **有這個能力**：`dep/CascLib/src/CascLib.h:383` `LPCTSTR szBuildKey; // If non-null, this will specify a build key (aka MD5 of build config that is different that current online version)`，`dep/CascLib/src/CascCommon.h:315` 亦有對應欄位。

→ **「讓 extractor 支援指定 build」是一個小改動（在 `CascHandles` 加參數、在 `HandleArgs` 加一個旗標）。但它救不了你**：CDN 上那個 build config 已經 404，指定了也取不到。這個改動只有在 build 仍在保留窗口內、或你自架/持有完整 CDN 鏡像時才有意義。

### 1.4 結論與取捨（直說）

- **這是一個「取得」問題，不是「工程」問題。** 本文不提供、也不建議任何規避 Blizzard 發佈機制或取得你未持有之遊戲資料的方法。
- **如果你本機（或既有的 Battle.net 安裝目錄）已經有 3.4.4.61581 的 CASC 資料**——例如當年裝過、資料夾還在——**你就沒有被卡住**，`map_extractor` 的 local 模式（`Storage::Open()`，`System.cpp:1404`）本來就是讀本機目錄，跟 CDN 無關。先去確認這件事，再決定要不要投入後面的階段。
- **如果沒有**，你有三個選項，誠實列出：
  1. **改變目標 build。** 現在能透過 Battle.net 安裝的 Classic 只有 `wow_classic`（5.5.4 MoP Classic）與 `wow_classic_era`（1.15.9）。若改打 5.5.4，base branch 的判斷會**完全不同**（MoP 的 talent 是 specialization + 六層天賦，與 WotLK 差更遠；且沒有任何現成分支瞄準它，見全景調查筆記 §7）。**代價是你拿不到 WotLK 的職業手感，但你有一個跑得起來的 client。**
  2. **退回 [Path A](./wotlk-classic-on-modern-client.md#path-a--335-分支--原版-12340-client)：`3.3.5` 分支 + 12340 client。** 內容完整度最高、官方持續維護，代價是舊架構。
  3. **暫緩，只做不需要 client 的部分。** §5 的 Stage 0/1（rebase、編譯、DB schema 準備）完全不需要 client；Stage 2 之後才需要。這是一個合理的中間狀態：把工程做到「只差 client 資料」。
- **值得知道的一件事：** WotLK Classic 並沒有停在 3.4.4。`wow_classic` 上最後一個 3.4.x 是 **3.4.5.63697（2025-10-09）**，而 TrinityCore 自家的 WowPacketParser 也已經有 `V3_4_5_61815` 的 opcode 表（見 §6）。前一篇筆記推論「3.4.4.61581 是 WotLK Classic 的終點 build」——**這一點不成立，應修正為 3.4.5**。

---

## 2. Base branch：`cata_classic`，不是 `master`

你說了 `master`。證據不支持這個選擇。以下逐項比較。

### 2.1 分支拓樸（已驗證）

```
git merge-base origin/master origin/cata_classic     → d397b636d4  (2024-03-07)
git merge-base origin/cata_classic origin/wotlk_classic → af8de3493f  (2025-05-11)
git rev-list --count origin/master..origin/cata_classic → 2502
git rev-list --count origin/cata_classic..origin/master → 3563
```

上游自己的 `wotlk_classic`（3.4.4）**確實是從 `cata_classic` 切出來的**。這不是推測，是 merge-base。

### 2.2 逐項距離

| 項目 | `cata_classic` | `master` | 對 3.4.4 的意義 |
|---|---|---|---|
| `CURRENT_EXPANSION` | `EXPANSION_CATACLYSM` | `EXPANSION_MIDNIGHT` | 目標是 `EXPANSION_WRATH_OF_THE_LICH_KING`；cata 距離 1 個資料片，master 距離 8 個 |
| CASC product | **`wow_classic`** | `wow` | cata 已對；master 要改 |
| `Opcodes.h` 行數 / CMSG / SMSG | 2067 / 696 / 1141 | 2690 / 1026 / 1409 | `wotlk_classic` 是 2072 / 706 / 1151 → **與 cata 幾乎同尺寸** |
| `DB2Stores.cpp` 的 `DB2Storage<>` 數 | **265** | 370 | `wotlk_classic` 也是 **265**（完全相同） |
| `DB2Structure.h` 行數 | 4146 | 5153 | `wotlk_classic` 4142 |
| `sql/base/dev/world_database.sql` 表數 | 239 | 247 | `wotlk_classic` 241（＝其 merge-base，未動） |
| `sql/base/dev/hotfixes_database.sql` 表數 | 354 | 467 | `wotlk_classic` 354 |
| Talent 系統 | `TalentEntry` + **`TalentTabEntry`** + `TalentTreePrimarySpellsEntry` | `ChrSpecializationEntry` + **約 20 個 `Trait*` 結構** + `TraitMgr.cpp` / `TraitHandler.cpp` / `TraitPackets*` | **決定性** |
| characters DB talent 表 | `character_talent`、`character_talent_group` | `character_talent`、`character_pvp_talent` | cata 的 `talent_group`＝雙天賦，正是 WotLK 的模型 |

**Talent 這一項是最重要的。** `cata_classic` 的 `TalentEntry` 長這樣（`src/server/game/DataStores/DB2Structure.h`）：

```c
struct TalentEntry {
    uint32 ID; LocalizedString Description;
    uint8 TierID; uint8 Flags; uint8 ColumnIndex; uint16 TabID;
    uint8 ClassID; uint16 SpecID; int32 SpellID; ...
    std::array<int32, 9> SpellRank;
    std::array<int32, 3> PrereqTalent; std::array<int32, 3> PrereqRank;
};
```

`TierID` / `ColumnIndex` / `TabID` / `SpellRank[]` / `PrereqTalent[]`——這就是 3.3.5 `DBCStructure.h:1664` 那個 `TalentEntry` 的同一個模型（欄位順序不同、多了 `SpecID`）。**Cataclysm 的天賦樹在資料模型上仍是 WotLK 的天賦樹。** 而 `master` 已經沒有這個東西了。

若以 `master` 為基底，你要額外做的事：把整個 Trait 系統拆掉並重建 TalentTab 系統（`TraitMgr.cpp`、`TraitHandler.cpp`、`TraitPackets*`、`UpdateFields` 的 traitConfig、characters DB 的 trait 表）。**舊 lineage 已經證明這件事做得到，但那是它 257 個 commit 裡最大的一塊**（見 §3.2 的 commit 清單：`Core/Players: re-implement talents`、`restore secondary talent specialization support`、`downgraded the glyph system`、`Core/Misc: ... dropped TraitHandler` …）。用 `cata_classic` 就整塊省掉。

### 2.3 但 `cata_classic` 也不是免費的

要誠實：`cata_classic` 上有一批 Cataclysm 才有的東西必須拿掉——`wotlk_classic` 的 31 個 commit 已經示範了其中一部分：

- `SharedDefines.h`：`EXPANSION_CATACLYSM` 移到 `MAX_CLASSIC_EXPANSIONS` 之後、刪掉 `CLASS_MONK` / `CLASS_DEMON_HUNTER` / `CLASS_EVOKER` / `CLASS_ADVENTURER`
- `RaceMask.h`：註解掉 `RACE_GOBLIN`（9）與 `RACE_WORGEN`（22），`MAX_RACES` 從 23 降到 12
- `CharacterHandler.cpp`：移除 Worgen / Goblin 的 faction change 語言對應
- Mastery（`TalentTabEntry::MasterySpellID[2]`）、Cata 的 `player_classlevelstats` 數值——後者 `wotlk_classic` 已用 800 條 `UPDATE` 換成 3.3.5 的 `basehp`

**判定：`cata_classic` 是正確的 base。以 `master` 為基底大約要多付出 §3.2 那條舊 lineage 的整個「downgrade 職業/天賦/物品/任務系統」工作量，而那正是它最重的部分。**

---

## 3. 現成的 head start：兩條 lineage

### 3.1 新 lineage：`origin/wotlk_classic`（3.4.4.61581，31 commits）

```
git merge-base origin/cata_classic origin/wotlk_classic   → af8de3493f  (2025-05-11)
git diff --stat af8de3493f origin/wotlk_classic
  → 57 files changed, 32696 insertions(+), 12013 deletions(-)
```

作者：`funjoker` 23、`Shauren` 8。時間跨度 2025-05-11 → 2025-07-02。

**31 個 commit 全文**（`git log --oneline origin/cata_classic..origin/wotlk_classic`，由新到舊）：

```
12c81a6f86 2025-07-02 funjoker Core/PacketIO: Fix FeatureSystemGlueScreen structure
83a1341b28 2025-06-30 funjoker Core/PacketIO: Update QueryCreatureResponse to 3.4.4
7a9a791c7a 2025-06-30 funjoker Core/packetIO: Update AuraDataInfo to 3.4.4
5a1af11d81 2025-06-30 funjoker Core/PacketIO: Update FeatureSystemStatus structure to 3.4.4
175086b27b 2025-06-30 funjoker Core/Spell: Change auraSlot to uint16
3bb40348cf 2025-06-30 funjoker Core/PacketIO: Followup e84736a4f7
d73d15e855 2025-06-30 funjoker Core/PacketIO: Fix PerksProgram structure
e84736a4f7 2025-06-30 funjoker Core/PacketIO: Fix BuildMovementUpdate
1d39243f24 2025-06-23 Shauren  Core: Updated allowed build to 3.4.4.61581
20957207e8 2025-06-05 Shauren  Core: Updated allowed build to 3.4.4.61256
7d8392171e 2025-06-04 Shauren  Core: Updated allowed build to 3.4.4.61187
dc20dbc97a 2025-05-31 Shauren  SQL: Fix filename
f5a18dfce7 2025-05-30 Shauren  Core: Updated allowed build to 3.4.4.61075
701a697a2b 2025-05-20 Shauren  Core: Updated allowed build to 3.4.4.60892
0bd3693036 2025-05-17 funjoker Core/Misc: Update CURRENT_EXPANSION
06d7821e12 2025-05-17 funjoker Core/Misc: Build fix
107f9d963a 2025-05-16 Shauren  Core: Updated allowed build to 3.4.4.60842
63891b4bf3 2025-05-15 funjoker Core/Player: Remove invalid TaxiNodes
38acb46dc9 2025-05-15 funjoker Misc: Fix 1 error
e0b06f6117 2025-05-15 funjoker Core/PacketIO: Update SMSG_ENTER_ENCRYPTED_MODE structure
2c40308671 2025-05-15 funjoker DB/Hotfixes: Clean up hotfix database
b2335abdee 2025-05-14 Shauren  Core: Updated allowed build to 3.4.4.60430
7cbcf93646 2025-05-14 funjoker Core/Misc: Remove unsupported classes
86d21d26e7 2025-05-13 funjoker Core/Stats: Reimplement HP from stamina
e723e7935e 2025-05-13 funjoker Core/Stats: Reimplement basehp
58485e6d7a 2025-05-13 funjoker Core/GameTables: Drop unneeded gametables for dmg and health and port 335 data
3b5a47ac3d 2025-05-13 funjoker Core/DataStores: Update DB2 version checks
d54175025e 2025-05-13 funjoker Core/Hotfixes: Update hotfix PrepareStatements
f31319912b 2025-05-13 funjoker Core/PacketIO: Change UNKNOWN_OPCODE to uint32
d8b7964112 2025-05-11 funjoker Core/Packets: fixed SMSG_ENUM_CHARACTERS_RESULT packet structure
9bd261f11c 2025-05-11 funjoker Core: Basic update to 3.4.4
```

**57 個檔案依子系統分類**（行數為 `git diff --stat` 實際值）：

| 子系統 | 檔案 | 行數 | 內容 |
|---|---|---|---|
| **Opcode 表** | `src/server/game/Server/Protocol/Opcodes.h` | 3754 | **整張表重編號**（+1889 / −1867）。`UNKNOWN_OPCODE` 由 `uint16 0xBADD` 改成 `uint32 0xBBAADD` |
| **DB2 metadata** | `DB2Metadata.h` | 19874 | 每個 DB2 的 layout hash + 欄位型別表 |
| | `DB2LoadInfo.h` | 6152 | **autogenerated from `DB2Structure.h`**（檔頭自述 "DO NOT EDIT!"） |
| | `DB2Structure.h` | 70 | 約 30 處欄位**型別/順序**微調（`uint8`↔`int8`、`ID` 位置、新增 `RegionGroupMask` / `TransmogPlayerConditionID` / `Flags` …） |
| | `DB2Stores.cpp` | 16 | 版本檢查值改為 3.4.4：`sAreaTableStore 14483`、`sItemStore 242551`、`sMapStore 2567`、`sSpellNameStore 1233554` … |
| | `DB2Meta.h`（common） | 6 | 刪掉一個 constexpr ctor |
| | `ExtractorDB2LoadInfo.h`（tools） | 204 | extractor 端的 DB2 載入資訊 |
| **UpdateFields** | `UpdateFields.cpp` / `.h` | 446 / 319 | 物件同步欄位版面 |
| **封包結構** | `CharacterPackets.h/.cpp` | 17 / 27 | `EnumCharactersResult`：新增 `Flags4`、`AvgEquippedItemLevel`；`RaceID` `int32`→`int8`；`WarbandGroup` 加 `WarbandSceneID` / `Name` |
| | `AuthenticationPackets.h/.cpp` | 1 / 3 | `EnterEncryptedMode` 新增 `int32 RegionGroup`，並改用 `Bits<1>` 寫 `Enabled` |
| | `SystemPackets`、`QueryPackets`、`SpellPackets`、`PerksProgramPacketsCommon` | 17/16/3/8 | FeatureSystemStatus、QueryCreatureResponse、AuraDataInfo … |
| | `MovementInfo.h`、`Object.cpp` | 14 / 11 | `BuildMovementUpdate` |
| **資料片/種族/職業** | `SharedDefines.h` | 14 | `CURRENT_EXPANSION`、移除 Monk/DH/Evoker/Adventurer |
| | `RaceMask.h` | 15 | 移除 Goblin / Worgen，`MAX_RACES` 23→12 |
| | `enuminfo_SharedDefines.cpp`、`enuminfo_RaceMask.cpp` | 12 / 6 | 由 `contrib/enumutils_describe.py` 產生 |
| **屬性/數值** | `StatSystem.cpp`、`Unit.cpp/.h`、`GameTables.cpp/.h` | 17/28/61/14/83 | basehp / stamina→HP 改回 3.3.5 公式 |
| **其他 core** | `Player.cpp`(111)、`ObjectMgr.cpp/.h`(52/3)、`PlayerTaxi.cpp`(15)、`CollectionMgr.cpp`(5)、`SpellAuras.cpp/.h`(2/4)、`AuthHandler.cpp`(2)、`CharacterHandler.cpp`(8)、`HotfixDatabase.cpp`(33) | | |
| **腳本** | `cs_learn.cpp`(4)、`spell_generic.cpp`(6) | | 只是配合 enum 變動 |
| **Extractor** | `map_extractor/System.cpp` | 23 | **只改 GameTables 清單**（註解掉 `NpcDamageByClass*` / `NpcTotalHp*` / `OCTBaseHPByClass` / `OCTHPPerStamina`，加入 `ChallengeModeDamage/Health`）。**`CONF_Product` 沒動——因為 `cata_classic` 已經是 `wow_classic`** |
| **SQL** | 7×auth、2×hotfixes、2×world | | 見下 |

**SQL 的實際內容（很重要，因為它決定了「內容資料」的狀態）：**

- **auth（7 檔）**：純粹是 `build_auth_key` + `build_info` 加入 60430 / 60842 / 60892 / 61075 / 61187 / 61256 / **61581**，並把 `realmlist.gamebuild` 預設值改成 `61581`。
- **hotfixes（2 檔）**：`2025_05_13_00_hotfixes.sql` 11,759 行 = **343 個 `DROP TABLE` + `CREATE TABLE`**，也就是**把整個 hotfixes schema 依 3.4.4 的 DB2 欄位重新產生一次**，**沒有任何資料**。`2025_05_15_00_hotfixes.sql` 2 行。
- **world（2 檔，共 1221 行）**：
  - `2025_05_13_00_world.sql`（419 行）＝ 重建 `creature_classlevelstats` 表 + 灌入 3.3.5 的數值。
  - `2025_05_13_01_world.sql`（802 行）＝ `ALTER TABLE player_classlevelstats ADD COLUMN basehp` + **800 條 `UPDATE`**。
- `revision_data.h.in.cmake` 仍指向 **`TDB_full_world_442.25051`**（Cataclysm 的 world DB）。

**定性（與前一篇一致）：這條 lineage 是純粹的「協定/資料表版面對齊」工作，內容資料完全沒碰。** 它的價值在於：**它是把 `cata_classic` 撞到 3.4.4 通訊層的完整 patch set，且是官方維護者寫的。**

### 3.2 舊 lineage：tag `TDB343.24081`（3.4.3.54261，257 commits）—— 前兩篇漏掉的東西

**這是本次調查最重要的發現。**

`origin/wotlk_classic` 在 2025-05 被**重新從 `cata_classic` 切出**，舊的歷史因此不在任何分支上。但它**還在 repo 裡**，被兩個 tag 釘住：

```
git tag -l "TDB343*"          → TDB343.23121  TDB343.24081
git tag --contains 92796557f9 → TDB343.24081
```

| 項目 | 值 |
|---|---|
| tip commit | `92796557f9b0ba3d2d1c7c770f535153154cf83e`（2024-08-17，"TDB 343.24081 - 2024/08/17"） |
| 從哪切出 | **`master`**：`git merge-base 92796557f9 origin/master` → `e72bde5236`（2023-11-14）。**比 `cata_classic` 誕生（2024-03-07）還早四個月** |
| commit 數 | **257** |
| diffstat | **1040 files changed, 1,040,716 insertions(+), 58,843 deletions(-)** |
| 作者 | Ovahlord 128、Shauren 57、funjoker 34、ModoX 22、Jeremy 5、Meji 4、其他 6 |
| `CURRENT_EXPANSION` | `EXPANSION_WRATH_OF_THE_LICH_KING` |
| 目標 build | `3.4.3.54261` |
| CMSG / SMSG | 882 / 1220 |
| `DB2Storage<>` 數 | 325 |
| world / hotfixes 表數 | 236 / 443 |
| `CONF_Product` | `wow` → **`wow_classic`**（此分支自己改的） |

**它做了 31-commit spike 完全沒做的事——真正的 WotLK 降級。** 摘自 commit 訊息（原文）：

*天賦 / 職業系統*
```
Cpre/Players: initial work on downgrading the talent system to WotLK
Core/Players: re-implement talents
Core/Spells: restore loading talent ranks
Core/Players: no longer rely on artificially created spell ranks and manually manage talent spell ranks
Core/Players: restore class and talent tier checks in Player::LearnTalent
Core/Players: restore secondary talent specialization support and implement SPELL_EFFECT_TALENT_SPEC_COUNT
Core/Players: downgraded the glyph system
Core/DataStores: load TalentTab.db2 / load GlyphSlot.db2
Core/Packets: implemented and enabled CMSG_LEARN_PREVIEW_TALENTS
Core/Misc: * removed various unused opcode and aura effect handlers ... * dropped TraitHandler ...
Core/Quests: restored rewarding talent points from quests
```

*數值 / 屬性*
```
Core/Player: backported health and mana regeneration calculations from 3.3.5
Core/Units: re-implement the MP5 mana regeneration rule
Core/Players: restore mana bonus from intellect
Core/Spells: Intellect will no longer increase spell power
Core/Players: downgraded stamina health bonus
Core/Units: downgraded power types enum and disabled Death Knight rune regeneration mechanics for the time being
Core/World: set Death Knight starting level back to 55
Core/World: updated player max level and make newer expansions fall back to WotLK maxlevel
```

*物品 / 任務 / 介面*
```
Core/Items: downgrade items part 1: removed item bonus generation, artifact weapon handling and azerite item mechanics
Core/Quests: downgrade quest fields / updated max quest log size
Core/Players: fixed structure of CMSG_SET_ACTION_BUTTON and downgraded player actions
Core/Player: updated inventory slots / Fix Inventory
Core/Taxi: removed non-exiting taxi nodes from InitTaxiNodesForLevel that have been added with Cataclysm and later
```

*內容資料（world / hotfixes DB）*
```
DB/GameObjects: migrate gameobject_template from 3.3.5 branch
DB/Creatures: removed all creatures from the database that have not been present in the 3.3.5 database
DB/Creatures: updated creature_template data from bruteforce data
DB/Quests: updated quest template, poi and objective data for WotLK classic
DB/Transports: backported transports from 3.3.5 branch
DB/Hotfixes: ported all broadcast_text entries from master branch which have been present in 3.3.5 as well
DB/Misc: removed spawns from non-existing maps and emptied/downgraded several database tables
Core/Creatures: ported creature classlevelstats from 335 branch and replaced scaling and content tuning difficulty fields with MinLevel and MaxLevel
Scripts/Misc: removed scripts of newer expansion's continents and dropped spell script files for unsupported classes
```

抽樣驗證：`sql/old/3.4.x/world/23101_2023_12_20/2023_11_25_00_world.sql`（43,079 行）第一行是 `TRUNCATE TABLE gameobject_template;`，後面的資料列 `VerifiedBuild` 欄位是 **`12340`**——**它字面上就是把 3.3.5 分支的 `gameobject_template` 灌進現代 schema。**

**而且有官方 TDB release**（GitHub Releases，實際 API 取得）：

| tag | 發佈日 | asset | release body |
|---|---|---|---|
| `TDB343.23121` | 2023-12-20 | — | — |
| `TDB343.24081` | **2024-08-17** | `TDB_full_343.24081_2024_08_17.7z`（**84,836,093 bytes**） | `![wotlk_classic](...badge/branch-wotlk_classic-yellow.svg)` |

→ **前一篇筆記 §3.2 第 3 點寫「沒有官方 TDB release（未驗證）」——這一點是錯的，應修正：有兩個，最新是 TDB 343.24081（2024-08-17）。**

### 3.3 兩條 lineage 怎麼合起來用

它們互補得幾乎完美：

| | 舊 lineage（`TDB343.24081`） | 新 lineage（`origin/wotlk_classic`） |
|---|---|---|
| 目標 build | 3.4.3.54261 | **3.4.4.61581** |
| 協定/DB2 對齊 | 舊（3.4.3） | **新（3.4.4）** |
| WotLK 遊戲系統降級 | **完整**（天賦/榮耀/數值/物品/任務） | 幾乎沒有（只有 basehp/stamina） |
| WotLK 內容資料庫 | **有，官方 TDB 343.24081** | 無（沿用 Cata 的 TDB 442） |
| 相對現在的落後 | 從 `master` 分岔於 2023-11-14 | 從 `cata_classic` 分岔於 2025-05-11 |

**建議的組合：以現在的 `cata_classic` 為 base → 疊上新 lineage 的 31 個 commit（協定層）→ 從舊 lineage cherry-pick 遊戲系統降級的那批 commit → 以 TDB 343.24081 為內容資料庫起點。**

---

## 4. 尚待補齊的 delta（逐子系統）

### 4.1 Opcodes / 協定

- 定義位置：`src/server/game/Server/Protocol/Opcodes.h`（enum `OpcodeClient` / `OpcodeServer` / `OpcodeMisc`）與 `Opcodes.cpp`（handler 表）。
- 規模：`cata_classic` 696 CMSG + 1141 SMSG；`wotlk_classic` 706 + 1151。
- **每個 build 的 opcode 數值都會整批重編。** 對照 diff：`CMSG_ACCEPT_GUILD_INVITE` 在 cata 是 `0x390029`，在 3.4.4 是 `0x3A0029`；`CMSG_ACTIVATE_TAXI` `0x350035` → `0x360036`。**高 16 位是 handler group，會隨 build 位移，不能靠 offset 推算。**
- **怎麼取得 3.4.4 的數值 —— 不用自己 sniff：** TrinityCore 自家的 **WowPacketParser** 就有現成的表。
  - `WowPacketParser/Enums/Version/V3_4_4_59817/Opcodes.cs`（**1709 行、1679 個 opcode 對映**），以及 `V3_4_5_61815/Opcodes.cs`。
  - 交叉驗證：WPP 的 `{ Opcode.CMSG_ACCEPT_GUILD_INVITE, 0x3A0029 }`、`{ Opcode.CMSG_ACCEPT_TRADE, 0x350005 }`、`{ Opcode.CMSG_ACTIVATE_TAXI, 0x360036 }` 與 `origin/wotlk_classic:Opcodes.h` 的值**逐一相符**。→ **上游那張 3.4.4 opcode 表就是從 WPP 這裡來的。**
  - `WowPacketParser/Enums/ClientVersionBuild.cs` 明確列出 `V3_4_4_61581 = 61581`（15 個 3.4.4 build）以及 3.4.5 到 `V3_4_5_62824`。
- **封包 body 結構**才是真工作量。31 個 commit 裡有 8 個是 `Core/PacketIO: ...`，而 `wotlk_classic` 停下來時只做完少數幾個（`SMSG_ENUM_CHARACTERS_RESULT`、`SMSG_ENTER_ENCRYPTED_MODE`、`FeatureSystemStatus`、`QueryCreatureResponse`、`AuraDataInfo`、`BuildMovementUpdate`、`PerksProgram`、`FeatureSystemGlueScreen`）。**其餘幾百個封包尚未逐一驗證過——這是最大的未知數，且只能靠實跑 client 逐個撞出來。**

### 4.2 DB2 / hotfixes

三層檔案，改動順序有嚴格依賴：

1. **`src/server/game/DataStores/DB2Structure.h`**（cata 4146 行 / master 5153 行）—— C++ 結構，**手寫**。
2. **`src/server/game/DataStores/DB2LoadInfo.h`**（cata 5475 行）—— 檔頭寫著 `// DO NOT EDIT! // Autogenerated from DB2Structure.h`。**產生器不在 repo 內**（`contrib/` 裡只有 `enumutils_describe.py`、`protoc-bnet`、SQL/codestyle 腳本）→ **未驗證**它是否公開存在；實務上要嘛手改、要嘛自己寫一支 parser。
3. **`src/server/game/DataStores/DB2Metadata.h`**（cata 12525 行 / `wotlk_classic` 19945 行）—— 每個 DB2 的 `DB2Meta{ FileDataId, IndexField, FieldCount, FileFieldCount, LayoutHash, Fields, ParentIndexField }`。**`LayoutHash` 與 `FieldCount` 是 client build 綁定的**：build 一換，client 的 `.db2` 檔版面就變，這裡不跟著改就整個載入失敗。

**store 數量**：`cata_classic` / `wotlk_classic` 各 **265** 個 `DB2Storage<>`；`master` 370；舊 lineage 325。

**版本檢查**在 `DB2Stores.cpp::LoadStores()`，`wotlk_classic` 已改成 3.4.4 的哨兵值（`sAreaTableStore 14483` / `sItemStore 242551` / `sMapStore 2567` / `sSpellNameStore 1233554`，註解標 `3.4.4 (60340)`）。

**hotfixes DB 的關係**：`hotfixes` schema 是 DB2 結構的 **SQL 鏡像**（`sql/base/dev/hotfixes_database.sql`，cata 354 表 / master 467 表）。DB2 結構一改，這裡的欄位就要跟著改，`HotfixDatabase.cpp` 的 `PrepareStatements` 也要（31 個 commit 裡就有 `Core/Hotfixes: Update hotfix PrepareStatements`）。`wotlk_classic` 的作法是**整份 schema 重新 dump**（343 個 `DROP`+`CREATE`）。

### 4.3 CASC / 資料抽取

- 工具：`src/tools/{extractor_common,map_extractor,vmap4_extractor,vmap4_assembler,mmaps_generator}`；`extractor_common` 內是 `CascHandles.cpp/.h`、`DB2CascFileSource.cpp/.h`、`ExtractorDB2LoadInfo.h`。
- **product code 已經對了**：`cata_classic` 與 `wotlk_classic` 的 `map_extractor/System.cpp` 都是 `CONF_Product = "wow_classic"`；`master` 是 `"wow"`。
- 要動的是：`ExtractorDB2LoadInfo.h`（`wotlk_classic` 改了 204 行）、GameTables 抽取清單（`System.cpp` 改了 23 行）、以及（若要離線指定 build）§1.3 說的 `szBuildKey` 接線。
- **`CONF_Product = "wow_classic"` 在今天已經不再指向 3.4.x**（§1.1）——**只有 local 模式（讀已安裝的資料夾）有意義**。

### 4.4 World DB —— 比前一篇說的樂觀得多

前一篇說「world DB 幾乎不相容，等於重建整個內容資料庫」。**有了舊 lineage 之後，這個判斷需要修正。**

**schema 距離（實測表清單比對）：**

| 比較 | 只在左 | 只在右 |
|---|---|---|
| `3.3.5`(186) vs `cata_classic`(239) | **27**：`item_template`、`item_template_locale`、`broadcast_text`、`spell_bonus_data`、`spell_ranks`、`spell_dbc`、`spelldifficulty_dbc`、`player_levelstats`、`waypoint_data`、`instance_encounters`、`achievement_criteria_data`、`warden_checks`、`script_waypoint`… | **80**：`areatrigger*`、`conversation_*`、`playerchoice*`(12)、`quest_objectives*`、`creature_template_difficulty`、`creature_template_model`、`waypoint_path`/`_node`、`serverside_spell*`、`phase_area`、`world_safe_locs`… |
| **`TDB343` lineage(236) vs `cata_classic`(239)** | **3**：`map_corpse_position`、`spell_scripts`、`warden_checks` | **6**：`battleground_scripts`、`creature_immunities`、`creature_quest_currency`、`creature_static_flags_override`、`destructible_hitpoint`、`quest_treasure_pickers` |
| `cata_classic`(239) vs `master`(247) | 1：`item_random_enchantment_template` | 9：`quest_reward_house_*`、`spawn_tracking*`(4)、`ui_map_quest*`、`spell_scripts` |

**→ TDB 343.24081 的 world schema 與今天的 `cata_classic` 只差 9 張表（3 + 6）。** 這不是「重建整個資料庫」，這是**一次可控的 schema migration**。

**「把 WotLK 內容 port 到現代 world schema」實際上是什麼：** 舊 lineage 已經示範了作法——逐表 `TRUNCATE` + 從 `3.3.5` 分支的對應表重灌，並補上現代 schema 新增的欄位（例：`gameobject_template` 直接搬 3.3.5 的、`VerifiedBuild=12340`；`quest_template` 加 `MinLevel` 欄位後重灌 quest/poi/objective；`creature_template` 21,780 條 `UPDATE`）。

**repo 內有沒有 migration 工具？** **沒有。** `sql/` 只有 base dump + `sql/updates/` 的順序套用機制（`src/server/database/Updater/`，比對 SHA1 後套用）。所謂「工具」就是**手寫一次性的大 SQL 檔**，這正是舊 lineage 那 43k / 94k 行檔案的來歷。

**Northrend 腳本**（前一篇的重點）維持成立：`3.3.5` 193 檔、`cata_classic` / `master` / `wotlk_classic` 各 **191** 檔。差的兩個是征服之島（已移到 `Battlegrounds/`）。

**仍然沒解決的、也是最硬的一項——1–60 舊世界：**

- Cataclysm 重畫了東部王國與卡林多。**3.4.x client 自己的地形資料（ADT/WDT）是災變前的。**
- 舊 lineage 的 world DB 是從 **`master`（retail，災變後）** 的 TDB 演化來的，只是把「3.3.5 沒有的 creature/gameobject **template**」刪掉。**`creature` / `gameobject` 這兩張 spawn 表的座標是否也換成 3.3.5 的版本——本次調查未找到對應的 commit，判定為未驗證，且傾向「沒有」。**
- 若沒有，症狀會是：**副本與諾森德正常（Cata 沒動這兩塊），但 1–60 的舊世界會出現 NPC 站在錯的地形上 / 懸空 / 卡在地底 / 任務目標對不上。**
- 這是**內容資料問題，不是 DB schema 問題**，而且是三種東西的交叉（client 的災變前地形 × server 的災變後 spawn × 任務鏈的版本）。**這是整個專案剩下最大的一塊未知量。**
- 驗證方式（一旦你有 client 與 DB）：把 `3.3.5` TDB 與 TDB 343.24081 的 `creature` 表在 map 0 / 1 上抽樣比對座標；或直接進遊戲跑幾條 1–20 的任務鏈。

### 4.5 Spell / Talent

見 §2.2 的表。要點：

- **`cata_classic` 已經是 TalentTab 模型**，所以「天賦樹」這個大結構不用重建——但 Cata 的天賦樹是 31 點 + Mastery，WotLK 是 51 點三系。差異落在：`TalentTabEntry::MasterySpellID[2]`（要停用）、每級可用點數（`DB2Manager::GetNumTalentsAtLevel`，`wotlk_classic` 已經改過一次以移除 Demon Hunter 分支）、雙天賦（`character_talent_group` 已存在）。
- **法術等級（spell rank）**：`3.3.5` 有 `spell_ranks` / `spell_bonus_data` 兩張 world 表，現代 core 兩張都沒有（Cataclysm 在遊戲設計上移除了法術等級）。**但 WotLK 有。** 舊 lineage 的處理方式寫在 commit 裡：`Core/Spells: restore loading talent ranks` 與 `Core/Players: no longer rely on artificially created spell ranks and manually manage talent spell ranks` —— 也就是**只在天賦層面恢復 rank，不重建整套 `spell_ranks`**。這是一個已經做過的設計決策，可以直接沿用。
- **符文（Glyph）**：`Core/DataStores: load GlyphSlot.db2` + `Core/Players: downgraded the glyph system`（舊 lineage）。`cata_classic` 的符文是 Cata 的 prime/major/minor 三型，WotLK 是 major/minor——差異存在但不大。
- **DK 符文（rune）**：舊 lineage 的 commit 明說 `disabled Death Knight rune regeneration mechanics for the time being` → **這是一個已知的未完成項。**

---

## 5. 分階段計畫

每階段標明「完成的定義」與「難點」。**Stage 0–1 不需要 client；Stage 2 之後需要。**

### Stage 0 — 先確認前置條件（半天）

- **做什麼**：確認本機是否已有 3.4.4.61581（或任何 3.4.x）的 CASC 資料夾。若沒有，先讀 §1.4 決定要不要繼續、或改目標 build。
- **完成的定義**：你能明確回答「我有/沒有可用的 3.4.x client 資料」。
- **難點**：無，但這是唯一一個「答錯就整條路線歸零」的階段。

### Stage 1 — 把 31 個 commit rebase 到現在的 `cata_classic`（1–2 週）

- **做什麼**：`git rebase --onto origin/cata_classic af8de3493f origin/wotlk_classic`（在自己的分支上），解 15 個月、1264 個 commit 的漂移。
- **衝突熱點**（依 diffstat 推斷）：`DB2Metadata.h`（19,874 行）、`DB2LoadInfo.h`（6,152 行）、`Opcodes.h`（3,754 行）、`UpdateFields.cpp/.h`。這三個檔在 `cata_classic` 上也一直在動。**實務上「rebase」對這幾個檔沒有意義，應該是「以 3.4.4 版本整檔取代，再手動 replay `cata_classic` 期間的結構修正」。**
- **完成的定義**：`worldserver` / `bnetserver` / 五個 extractor **編得過**，`auth` DB 的 `build_info` 有 `(61581,3,4,4,NULL)`，`realmlist.gamebuild = 61581`。
- **難點**：`DB2Structure.h` ↔ `DB2LoadInfo.h` ↔ `DB2Metadata.h` ↔ `hotfixes` schema 四者必須一致，而 `DB2LoadInfo.h` 原本是自動產生的（產生器不在 repo）。

### Stage 2 — 抽資料 + 登入畫面（1–2 週，需 client）

- **做什麼**：用 local 模式跑 `mapextractor` / `vmap4extractor` / `vmap4assembler` / `mmaps_generator`（`contrib/extractor.sh`）；`bnetserver` 起來、client 走 Battle.net REST/HTTPS 登入。client 端需要 patcher 把連線導向自架服務（見 §6）。
- **完成的定義**：3.4.4 client 走完 `LoginREST`（`bnetserver.conf.dist:77`，port 8081）+ Battle.net protobuf（port 1119）到達角色/realm 選單。
- **難點**：`build_auth_key`（`auth_database.sql` 已有 61581 的七組 Mac/Win × A64/x64 × WoW/WoWC 金鑰）；`SMSG_ENTER_ENCRYPTED_MODE` 的 ed25519 簽章 + 新增的 `RegionGroup` 欄位（`wotlk_classic` 已改）；DB2 版本檢查（`DB2Stores.cpp`）必須通過，否則 `worldserver` 直接 `TC_LOG_FATAL` 退出。
- **`wotlk_classic` 在這一階段已經做完的**：allowed build ×7、`SMSG_ENTER_ENCRYPTED_MODE`、`FeatureSystemStatus` / `FeatureSystemGlueScreen`。

### Stage 3 — Realm list + 角色列表（1–3 週）

- **做什麼**：`GetRealmListTicket` / `JoinRealm`（`src/server/bnetserver/Services/GameUtilitiesService.cpp:88`、`:251`）；`SMSG_ENUM_CHARACTERS_RESULT`；角色建立（種族/職業限制）。
- **完成的定義**：能建立一個角色並在角色選單看到它（含正確的模型、裝備外觀）。
- **難點**：`EnumCharactersResult` 的欄位在 3.4.4 與 4.4.2 之間有實際差異（`Flags4`、`AvgEquippedItemLevel`、`RaceID` `int32`→`int8`、`WarbandGroup` 加 `WarbandSceneID`/`Name`）——**`wotlk_classic` 已經全部改好**（`d8b7964112`、`CharacterPackets.h` +17）。種族/職業裁剪也已做（`RaceMask.h`、`SharedDefines.h`）。
- **這一階段基本上是「把 31 個 commit 的成果驗收一遍」。**

### Stage 4 — 進世界（1–3 個月）

- **做什麼**：`SMSG_UPDATE_OBJECT` / `BuildMovementUpdate` / `SMSG_AURA_UPDATE` / `SMSG_SPELL_START` / `SMSG_SPELL_GO` / `SMSG_ON_MONSTER_MOVE` / 各種 `SMSG_QUERY_*_RESPONSE` 逐一對齊 3.4.4。
- **完成的定義**：角色進入世界、能移動、能看到 NPC、能施法、能接任務。
- **難點**：**這是最耗時的一段，而且沒有捷徑。** `wotlk_classic` 只做到 `BuildMovementUpdate` 與 `AuraDataInfo` 就停了。**但舊 lineage 已經做完過一次**（`Core/Packets: fixed SM SMSG_UPDATE_OBJECT packet structure`、`fixed SMSG_AURA_UPDATE, SMSG_SPELL_START, SMSG_SPELL_GO packet structures`、`fixed SMSG_ON_MONSTER_MOVE packet structure`、`re-enabled SMSG_QUERY_PLAYER_NAMES_RESPONSE`、`enable SMSG_QUERY_GAME_OBJECT_RESPONSE`、`enable SMSG_QUERY_NPC_TEXT_RESPONSE`…）——**把 `git show <sha>` 當成參考解答，而不是從零開始。**
- 工具：WowPacketParser 可以把你自己的 session 錄下來解析比對（見 §6）。

### Stage 5 — 遊戲系統降級（2–4 個月）

- **做什麼**：cherry-pick / 重寫舊 lineage 的天賦、符文、屬性公式、物品、任務欄位、taxi node、動作條、背包格數等降級。
- **完成的定義**：天賦樹是 WotLK 的 51 點三系；HP/MP/MP5 公式對；DK 從 55 級開始；等級上限 80。
- **難點**：舊 lineage 是從 **`master`** 降級，你是從 **`cata_classic`** 降級——**很多 commit 會不適用（因為 cata 本來就沒有 Trait 系統），另一些會需要重寫（因為 cata 的起點跟 master 不同）。** 這裡不能無腦 cherry-pick，要逐條判斷。好消息是**判斷的成本遠低於重新設計**。
- 已知未完成項：DK rune regeneration（舊 lineage 自己標了 `for the time being`）。

### Stage 6 — 內容資料庫（持續，沒有終點）

- **做什麼**：以 **TDB 343.24081**（`TDB_full_343.24081_2024_08_17.7z`，84 MB）為起點；把它的 schema 往前 migrate 到你 Stage 1 之後的版本（差 9 張表，§4.4）；replay `cata_classic` 自 2024-08 以來的 world update 檔（`sql/updates/world/cata_classic/`，注意其中有些是 Cata 專屬、必須跳過）。
- **完成的定義**：`worldserver` 能載入 world + hotfixes DB 而不報錯，且諾森德 + 副本可玩。
- **難點**：
  1. **hotfixes DB 的資料要重新產生**：TDB 343 的 hotfixes 是 3.4.3 的 DB2 版面，你的目標是 3.4.4/3.4.5 → 需要從你自己的 client 重新抽 DB2 再灌入。`wotlk_classic` 的 `2025_05_13_00_hotfixes.sql` 給了 schema，資料要自己來。
  2. **1–60 舊世界的地形/spawn 錯位**（§4.4 末段）——**最大的未知，且可能沒有乾淨解。** 最務實的降級目標是：**把 1–60 當成「已知有問題」，把驗收標準放在 68–80 的諾森德與全部 WotLK 副本**（Cataclysm 沒動這兩塊，腳本覆蓋率 191/193）。

### 時間感（誠實的估計，標為推估）

Stage 0–3 若一切順利，一個人**數週到兩個月**可以到角色選單。Stage 4–5 是**數個月**。Stage 6 沒有終點。**這是一個「永遠處於 80% 完成」的專案**——但因為有兩條 lineage 當參考解答，它不是白紙。**推估值未驗證。**

---

## 6. 工具與參考

### 第一方（TrinityCore 官方）

| 資源 | 是什麼 | 對本專案的用處 |
|---|---|---|
| **`TrinityCore/WowPacketParser`** | C# / .NET 10、GPL-3.0、★518、最後 push **2026-09-02**。README 自述 "World of Warcraft Packet Parser"，把 `.pkt`/`.bin` 解析成文字與 SQL | **本專案最重要的外部工具。** 有 `Enums/Version/V3_4_4_59817/Opcodes.cs`（1709 行 / 1679 個 opcode）與 `V3_4_5_61815/Opcodes.cs`；`ClientVersionBuild.cs` 涵蓋 `V3_4_4_61581`；`WowPacketParserModule.V3_4_0_45166/` 內有 `Parsers/` 與 `UpdateFields/`（含 `V3_4_4_59817` 子目錄）。**opcode 表不用自己 sniff。** 它也能把 sniff 直接產生 world DB 的 SQL |
| `src/tools/`（本 repo） | `extractor_common` / `map_extractor` / `vmap4_extractor` / `vmap4_assembler` / `mmaps_generator` | client 資料抽取 |
| `contrib/`（本 repo） | `extractor.sh`/`.bat`、`enumutils_describe.py`（產生 `enuminfo_*.cpp`）、`protoc-bnet`、`merge_updates_*`、`check_updates.sh`、`check_codestyle.sh` | `enumutils_describe.py` 在你改 `SharedDefines.h` / `RaceMask.h` 之後要重跑 |
| GitHub Releases | `TDB343.23121`、`TDB343.24081`（badge 標明 `branch-wotlk_classic`） | **Stage 6 的起點資料庫** |
| `trinitycore.info` | 官方 wiki | 注意它把 `cata_classic` 也寫成 abandoned，與 git 事實矛盾（見前一篇 §3.3）；`Client-Setup` 頁註明現代分支需要 custom launcher |

### 社群 / 第三方（明確標示，不背書）

- **`wowdev.wiki`** — WoW 檔案格式（DB2/ADT/WMO/M2/CASC/TACT）的**社群維護、事實上的規格書**。本次嘗試以 WebFetch 取用回 **HTTP 403**，故本文未直接引用其內容；列在此僅因它是這個領域唯一的格式參考。**未驗證。**
- **`wowemulation-dev/wow-patcher`** — Rust、Apache-2.0、最後 commit 2026-07-15。README 支援矩陣自述 **3.4.x–3.4.4 為 "Verified"**（來源見全景調查筆記 §6）。這是 Stage 2 的 client 端前提。**本文僅事實陳述，不背書。**
- **`wago.tools/api/builds`** — 社群維護的 build/CDN config 索引。本文僅用它取 build config hash；所有 200/404 判定來自 Blizzard 自家 CDN。

---

## 7. 驗證指令（全部唯讀，未切換 working tree）

```bash
# 分支拓樸
git merge-base origin/master origin/cata_classic          # d397b636d4 (2024-03-07)
git merge-base origin/cata_classic origin/wotlk_classic   # af8de3493f (2025-05-11)

# 新 lineage
git log --oneline origin/cata_classic..origin/wotlk_classic          # 31
git diff --stat af8de3493f origin/wotlk_classic                      # 57 files, +32696 -12013
git diff af8de3493f origin/wotlk_classic -- src/server/game/Miscellaneous/SharedDefines.h

# 舊 lineage（關鍵：它只被 tag 釘住，不在任何分支上）
git tag -l "TDB343*"                                                  # TDB343.23121 TDB343.24081
git rev-parse TDB343.24081                                            # 92796557f9...
git merge-base 92796557f9 origin/master                               # e72bde5236 (2023-11-14)
git rev-list --count e72bde5236..92796557f9                           # 257
git diff --stat e72bde5236 92796557f9 | tail -1                       # 1040 files, +1040716 -58843
git log --format='%s' e72bde5236..92796557f9 | grep -iE '^DB/|talent'

# 規模指標（zsh 會把 "$b:src/..." 當 history modifier，請用 bash）
bash -c 'for b in master cata_classic wotlk_classic; do
  echo -n "$b opcodes: "; git show "origin/$b:src/server/game/Server/Protocol/Opcodes.h" | wc -l
  echo -n "$b db2 stores: "; git show "origin/$b:src/server/game/DataStores/DB2Stores.cpp" | grep -c "^DB2Storage<"
done'
bash -c 'for b in 3.3.5 cata_classic master; do echo -n "$b world tables: ";
  git show "origin/$b:sql/base/dev/world_database.sql" | grep -c "^CREATE TABLE"; done'

# world schema 距離
bash -c 'git show 92796557f9:sql/base/dev/world_database.sql | grep "^CREATE TABLE" \
  | sed "s/CREATE TABLE .\([a-z_0-9]*\).*/\1/" | sort > /tmp/w343
git show origin/cata_classic:sql/base/dev/world_database.sql | grep "^CREATE TABLE" \
  | sed "s/CREATE TABLE .\([a-z_0-9]*\).*/\1/" | sort > /tmp/wcata
comm -23 /tmp/w343 /tmp/wcata; echo ---; comm -13 /tmp/w343 /tmp/wcata'

# TDB releases
gh api repos/TrinityCore/TrinityCore/releases --paginate \
  --jq '.[]|select(.tag_name|startswith("TDB343"))|"\(.tag_name) \(.published_at)"'
gh api repos/TrinityCore/TrinityCore/releases/tags/TDB343.24081 --jq '{body,assets:[.assets[]|{name,size}]}'

# WowPacketParser 的 3.4.4 opcode 表
gh api repos/TrinityCore/WowPacketParser/contents/WowPacketParser/Enums/Version --jq '.[].name' | grep V3_4
gh api repos/TrinityCore/WowPacketParser/contents/WowPacketParser/Enums/Version/V3_4_4_59817/Opcodes.cs \
  --jq '.content' | base64 -d | grep CMSG_ACCEPT_GUILD_INVITE      # → 0x3A0029

# Blizzard TACT / CDN（§1 的全部數字）
curl -s "http://us.patch.battle.net:1119/wow_classic/versions"
curl -s "http://us.patch.battle.net:1119/wow_classic/cdns"
# build config 探測；hash 取自 wago.tools（社群），200/404 來自 Blizzard
curl -s -o /dev/null -w '%{http_code}\n' \
  "http://us.cdn.blizzard.com/tpr/wow/config/c2/b6/c2b611183fb96dfbde88c8f781dc5b4e"   # 3.4.4.61581 → 404
curl -s -o /dev/null -w '%{http_code}\n' \
  "http://us.cdn.blizzard.com/tpr/wow/config/a9/18/a918d337491e3ffe961373f1a48df50c"   # live      → 200
```

---

## 8. 對前兩篇筆記的修正

| 位置 | 原文 | 修正 |
|---|---|---|
| `wotlk-classic-on-modern-client.md` §3.2 第 3 點 | 「沒有官方 TDB release（未驗證，需查 GitHub Releases）」 | **錯。** 有兩個：`TDB343.23121`（2023-12-20）、`TDB343.24081`（2024-08-17，84 MB，release body 明確標 `branch-wotlk_classic`） |
| 同上 §3.1 / §4 Path C | 把 `wotlk_classic` 描述為「只有 31 個 commit 的 spike」 | **不完整。** 那是 2025 年 reset 之後的分支狀態。被 tag `TDB343.24081` 保留的舊 lineage 有 **257 個 commit / 1040 檔 / +1,040,716 行**，且完成了天賦、符文、屬性、物品、任務的 WotLK 降級 |
| 同上 §4 Path C 第 6 點 | 「world DB schema 幾乎不相容 … 等於重建整個內容資料庫」 | **過度悲觀。** TDB343 lineage 的 world schema 與今日 `cata_classic` 只差 9 張表。真正的難題不是 schema，是 **1–60 舊世界的災變前地形 × 災變後 spawn** |
| `classic-client-emulator-landscape.md` §6 末段 | 「3.4.4.61581 就是 WotLK Classic 的終點 build」（引 `tavern` 的 cutoff 表推論） | **不成立。** `wow_classic` 上最後一個 3.4.x 是 **3.4.5.63697（2025-10-09）**；WowPacketParser 亦有 `V3_4_5_61815` opcode 表與 3.4.5 build 清單 |
| 兩篇皆未涵蓋 | client 取得 | **新增阻斷性前提**：3.4.4.61581 已從 Blizzard CDN 清除（404，對照組 200）；`wow_classic` product 現指向 5.5.4.69585 |

---

## 9. 實際取用過的來源

**本 repo（唯讀 git）**
- `origin/master` / `origin/cata_classic` / `origin/wotlk_classic` / `origin/3.3.5`
- tags `TDB343.23121`、`TDB343.24081`（commit `92796557f9`、`f5c8b53b2e`）
- `src/server/game/{Server/Protocol/Opcodes.h, DataStores/*, Miscellaneous/*, Server/Packets/*, Handlers/*}`
- `src/tools/{map_extractor/System.cpp, extractor_common/CascHandles.cpp}`、`dep/CascLib/src/{CascLib.h,CascCommon.h}`
- `sql/base/auth_database.sql`、`sql/base/dev/{world,hotfixes}_database.sql`、`sql/updates/*/wotlk_classic/*`、`sql/old/3.4.x/**`
- `revision_data.h.in.cmake`、`contrib/`

**TrinityCore 官方 GitHub**
- `https://github.com/TrinityCore/TrinityCore/releases`（TDB343.23121 / TDB343.24081 的 asset 與 body）
- `https://github.com/TrinityCore/WowPacketParser`（repo metadata、`Enums/ClientVersionBuild.cs`、`Enums/Version/V3_4_4_59817/Opcodes.cs`、`Enums/Version/V3_4_5_61815/`、模組目錄清單）

**Blizzard 第一方端點（實測）**
- `http://us.patch.battle.net:1119/{wow,wow_classic,wow_classic_era,wow_classic_ptr,wow_classic_beta,wow_classic_era_ptr,wowz,wowt,wow_beta,wowdev,wowv,wowv2}/versions`
- `http://us.patch.battle.net:1119/wow_classic/cdns`
- `http://{us.cdn,level3}.blizzard.com/tpr/wow/config/<xx>/<yy>/<hash>`（build/CDN config 探測，含 live 對照組）

**社群（明確標示）**
- `https://wago.tools/api/builds`（僅取 build config hash）

**取用失敗**：`https://wowdev.wiki/Main_Page`（HTTP 403）、`https://trinitycore.info/en/install/Client-Setup`（WebFetch 只取回標題，無內文）、`https://trinitycore.info/en/install/Installation-Guide/linux-core-installation`（HTTP 404）。故本文未引用這三處內容。
