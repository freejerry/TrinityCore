# `origin/wotlk_classic` 完工評估：程式碼層級的實地盤點

> 撰寫日期：2026-09-04
> 相關筆記：[在 TrinityCore 上跑 WotLK Classic](./wotlk-classic-on-modern-client.md)、[WotLK Classic 移植路線圖](./wotlk-classic-port-roadmap.md)、[TrinityCore 專案總覽](./trinitycore-overview.md)
> **本篇的定位：** 前兩篇問「可不可行 / 工程範圍多大」。本篇只問一件事——**上游那個 `wotlk_classic` 分支本身，到底完成了什麼、沒完成什麼，把它「做完」具體要動哪些檔案。** 逐項對照本 repo 的 git 物件與上游 GitHub API。
> **不涵蓋：** 「該不該換 backend」「TDB343 vs 現行 stack 的整體得失」——那是 `cata-classic-backend-option.md` 的題目。
> 來源限定 primary sources：本 repo 唯讀 git（未切換分支、未修改任何追蹤檔案）、TrinityCore / WowPacketParser 的 GitHub API。凡未驗證者一律標示「**未驗證**」。
> **既有前提（視為事實）：** 使用者目前有一套**能跑**的 stack——WoW Classic client **3.4.3.54261** → `Xian55/HermesProxy`（`feature/wotlk-classic-v3.4.3`）→ TrinityCore **`3.3.5`** + MariaDB in Docker；登入、建角、進世界、任務、戰鬥皆正常。其上已完成大量 zhTW 在地化：12 張伺服器端 `*_locale` 表，加上約 28 張 client DB2 表以 hotfix 形式下發（在 HermesProxy 內新寫約 28 支 C# loader，逐一依 WoWDBDefs 的 3.4.3.54261 版面產生，並經 client 回 `VALIDATION_RESULT_VALID` 驗證）。

---

## 0. TL;DR — 一句話結論

**`wotlk_classic` 不是「差最後一哩」的專案，而是「只做了第一哩」的專案，而且它那一哩瞄準的是 3.4.4.61581，不是你手上的 3.4.3.54261——換靶不是改常數，是重新推導整份 DB2 metadata（749 個共同 store 的 LayoutHash 抽樣 15/15 全不同）與整張 opcode 表（3.4.3 是 16-bit 平坦編號，3.4.4 是 32-bit group 編號，連 `UNKNOWN_OPCODE` 的型別都不同）。**

但有三個比路線圖那篇樂觀得多的發現：

1. **rebase 幾乎沒有成本。** 路線圖推測 `DB2Metadata.h`（19,874 行）、`DB2LoadInfo.h`（6,152 行）、`UpdateFields.h` 是衝突熱點。**實測：這三個檔在 `cata_classic` 上自 merge-base 至今一行都沒動過。** 真正有漂移的只有 4 個檔、合計約 85 行。見 §5.1。
2. **3.4.3.54261 的 opcode 表現成存在。** WowPacketParser 有 `V3_4_3_51666/Opcodes.cs`（1,643 行），且 `Enums/Version/Opcodes.cs` 的 build→表對映**明文列出 `V3_4_3_54261 → V3_4_3_51666`**。不用 sniff。見 §2.2。
3. **3.4.3.54261 的 client auth key 也現成存在**，就在本 repo 的 tag `TDB343.24081` 裡。見 §2.4。
4. **在地化工作幾乎全部可以帶走。** hotfixes schema 的 79 張 `*_locale` 表**原生就帶 `zhTW` 分區**，`HotfixDatabase.cpp` 有 79 條 `PREPARE_LOCALE_STMT`，`LOCALE_zhTW = 5` 是 core 的一等公民。你那 ~28 支 C# loader 的**知識**（欄位版面）100% 可用，**程式碼**要換成 SQL 資料列 + C++ 結構。見 §4。

**誠實的判定在 §6。**

---

## 1. 分支到底做了什麼（逐檔分類）

### 1.1 規模

```
git merge-base origin/cata_classic origin/wotlk_classic   → af8de3493f  (2025-05-11)
git rev-list --count origin/cata_classic..origin/wotlk_classic  → 31
git rev-list --count origin/wotlk_classic..origin/cata_classic  → 1264
git diff --stat af8de3493f origin/wotlk_classic  → 57 files changed, 32696 insertions(+), 12013 deletions(-)
```

分支 tip（GitHub API 實測，與本地 remote-tracking 一致）：

```
gh api repos/TrinityCore/TrinityCore/branches/wotlk_classic
  → 12c81a6f86cddbd47710b4e27aeff3f4eb7c4ced
    2025-07-02T01:49:56Z
    "Core/PacketIO: Fix FeatureSystemGlueScreen structure"
```

`cata_classic` tip：`3bc146f58a`（**committer date** 2026-08-31，`DB/Spells: fix feign death scriptname`）。
（注意：`%ad`（author date）會顯示 2025-02-07，那是 cherry-pick 保留的原始作者日期。判斷分支活躍度要用 `%cd`。）

31 個 commit 的完整清單見路線圖筆記 §3.1，此處不重複。以下只做**子系統分類與「做完了 vs 只是動了一下」的判定**。

### 1.2 逐子系統：完成度判定

| 子系統 | 檔案（行數為 diffstat 實測） | 狀態判定 |
|---|---|---|
| **版本/build 常數** | `sql/base/auth_database.sql`(73) + 7 個 `sql/updates/auth/wotlk_classic/*.sql` | **完成。** 但**沒有任何 C++ 常數**——build 完全由 DB 驅動（`build_info` / `build_auth_key` / `realmlist.gamebuild`）。見 §2.4 |
| **CASC product code** | — | **不用做。** `cata_classic` 的 `map_extractor/System.cpp` 已是 `CONF_Product = "wow_classic"`，分支沒動它 |
| **Opcode 表** | `Opcodes.h`(3754：+1889 / −1867) | **整表換掉，完成。** 外加 `Core/PacketIO: Change UNKNOWN_OPCODE to uint32`（`f31319912b`）——這是**表示法的結構性改變**，見 §2.2 |
| **protobuf / bnet 登入** | — | **一行都沒動。** `src/server/proto/`、`src/server/bnetserver/` 在 57 個檔案的清單中完全不存在。分支直接沿用 `cata_classic` 的 Battle.net 登入層 |
| **DB2 結構 / metadata** | `DB2Metadata.h`(19874)、`DB2LoadInfo.h`(6152)、`DB2Structure.h`(70)、`DB2Stores.cpp`(16)、`DB2Meta.h`(6)、`ExtractorDB2LoadInfo.h`(204) | **對 3.4.4 而言完成。** `DB2Metadata.h` 從 12,525 行（cata）長到 19,945 行，並改用 designated initializer 寫法。`DB2Stores.cpp` 的哨兵值改成 3.4.4（見 §3.1） |
| **封包 / UpdateFields 結構** | `UpdateFields.cpp`(446)/`.h`(319)、`CharacterPackets`(17+27)、`AuthenticationPackets`(1+3)、`SystemPackets`(17+16)、`QueryPackets`(4+4)、`SpellPackets`(3+3)、`PerksProgramPacketsCommon`(8+8)、`MovementInfo.h`(14)、`Object.cpp`(11) | **只做了 8 個封包。** 8 個 `Core/PacketIO:` commit 涵蓋 `SMSG_ENUM_CHARACTERS_RESULT`、`SMSG_ENTER_ENCRYPTED_MODE`、`FeatureSystemStatus`、`FeatureSystemGlueScreen`、`QueryCreatureResponse`、`AuraDataInfo`、`BuildMovementUpdate`、`PerksProgram`。**其餘上千個封包未經驗證** |
| **角色建立 / 種族職業裁剪** | `SharedDefines.h`(14)、`RaceMask.h`(15)、`enuminfo_*`(12+6)、`CharacterHandler.cpp`(8)、`ObjectMgr.cpp`(52)/`.h`(3) | **半成品，見 §3.2。** 值得注意：`ObjectMgr::LoadPlayerInfo()` 裡的資料片過濾條件是被**註解掉**而非刪除 |
| **屬性 / GameTables** | `StatSystem.cpp`(17)、`Unit.cpp`(28)/`.h`(61)、`GameTables.cpp`(14)/`.h`(83)、`Player.cpp`(111)、`PlayerTaxi.cpp`(15) | **完成一小塊：** basehp 與 stamina→HP 改回 3.3.5 公式，資料來源從 GameTable 換成 world DB 欄位 |
| **SQL** | 7×auth、2×hotfixes（11,759 + 2 行）、2×world（419 + 802 行） | **schema 有、資料沒有。** 見 §1.3 |
| **其他** | `CollectionMgr.cpp`(5)、`SpellAuras.cpp`(2)/`.h`(4)、`AuthHandler.cpp`(2)、`cs_learn.cpp`(4)、`spell_generic.cpp`(6)、`map_extractor/System.cpp`(23) | 配合 enum / GameTable 變動的機械性修正 |

### 1.3 SQL 的實際內容（決定「內容資料」狀態）

```
git diff --name-status af8de3493f origin/wotlk_classic -- sql
```

- **auth（7 檔）** — 純粹是 `build_info` + `build_auth_key` 加入 60430 / 60842 / 60892 / 61075 / 61187 / 61256 / **61581**，並把 `realmlist.gamebuild` 預設值改成 61581。每個 build 有 7 組金鑰（Mac/Win × A64/x64 × WoW/WoWC）。
- **hotfixes（2 檔）** — `2025_05_13_00_hotfixes.sql` 11,759 行 = **343 組 `DROP TABLE` + `CREATE TABLE`**，即依 3.4.4 的 DB2 欄位把整份 hotfixes schema 重新產生。**`INSERT` 為零筆。**
- **world（2 檔，1,221 行）** — `creature_classlevelstats` 重建 + 3.3.5 數值；`player_classlevelstats` 加 `basehp` 欄位 + 800 條 `UPDATE`。
- **`revision_data.h.in.cmake` 仍指向 Cataclysm 的 TDB：**

  ```
  origin/wotlk_classic: DATABASE_FULL_DATABASE  "TDB_full_world_442.25051_2025_05_11.sql"
  origin/cata_classic:  DATABASE_FULL_DATABASE  "TDB_full_world_442.26081_2026_08_14.sql"
  ```

  → **這個分支預期你灌的是 4.4.2 的 world + hotfixes 資料庫。**
- `README.md` 第一行仍是 `# ... TrinityCore (cata_classic)`。

### 1.4 「作者做到了什麼」的證據強度

**必須誠實：repo 裡沒有任何「跑起來了」的直接證據。** 沒有 CI 針對此分支、沒有測試、沒有 issue 回報成功。可推論的間接證據只有兩項：

1. **commit 的因果順序合理。** `SMSG_ENUM_CHARACTERS_RESULT`（05-11）→ `SMSG_ENTER_ENCRYPTED_MODE`（05-15）→ `FeatureSystemStatus`（06-30）→ `BuildMovementUpdate`（06-30）→ `AuraDataInfo`（06-30）→ `QueryCreatureResponse`（06-30）→ `FeatureSystemGlueScreen`（07-02）。**這是一條「登入 → 角色列表 → 進世界 → 看到 NPC → 看到光環」的實跑路徑。** 你不會在沒進世界的情況下去修 `BuildMovementUpdate`。
2. **Shauren（首席維護者）連續 7 次 bump allowed build**（60430 → 61581），每次都附上 7 組 auth key。這代表**有人真的在拿新 client 連這個 server**。

**判定：作者大概率把 client 帶進了世界，並開始撞 update object / aura / query 這一層。** 但這是**推論，未驗證**——沒有任何一手陳述說「進世界了」。

---

## 2. Build target：從 3.4.4.61581 改打 3.4.3.54261 要付什麼代價

**這是本篇最重要的一節。** 路線圖筆記已證實 3.4.4.61581 的 CDN build config 回 404，所以「retarget 到你手上真的有的 3.4.3.54261」不是選項之一，是**唯一**選項。

### 2.1 好消息：build 號完全由 DB 驅動，沒有硬編常數

```
git grep -n "61581" origin/wotlk_classic -- '*.h' '*.cpp' '*.cmake' '*.conf.dist'
  → 只命中 dep/CascLib/src/CascDecrypt.cpp 與 dep/zlib/crc32.h 兩處巧合的十六進位字串
```

**C++ 裡沒有任何 `61581`。** 驗證流程在 `src/server/game/Server/WorldSocket.cpp`：

```cpp
ClientBuild::Info const* buildInfo = ClientBuild::GetBuildInfo(account.Game.Build);
if (!buildInfo) { SendAuthResponseError(ERROR_BAD_VERSION); ... }

ClientBuild::VariantId buildVariant = { .Platform = joinTicket->platform(),
                                        .Arch = joinTicket->clientarch(),
                                        .Type = joinTicket->type() };
auto clientBuildAuthKey = std::ranges::find(buildInfo->AuthKeys, buildVariant, &ClientBuild::AuthKey::Variant);
if (clientBuildAuthKey == buildInfo->AuthKeys.end()) { SendAuthResponseError(ERROR_BAD_VERSION); ... }

Trinity::Crypto::SHA512 digestKeyHash;
digestKeyHash.UpdateData(account.Game.KeyData.data(), account.Game.KeyData.size());
digestKeyHash.UpdateData(clientBuildAuthKey->Key.data(), clientBuildAuthKey->Key.size());
```

而 `src/server/shared/Realm/ClientBuildInfo.cpp:161` 從 `build_auth_key` 表載入。

→ **改 build 號本身是三筆 SQL：** `build_info` 一列、`build_auth_key` 若干列、`realmlist.gamebuild` 一個值。**這部分確實是「小編輯」。**

### 2.2 壞消息之一：opcode 表要整張換，且表示法不同

WowPacketParser 有 3.4.3 的表，且**明確涵蓋 54261**：

```
gh api .../Enums/Version --jq '.[].name' | grep V3_4
  → V3_4_0_45166  V3_4_1_47014  V3_4_2_50129  V3_4_3_51666  V3_4_4_59817  V3_4_5_61815

Enums/Version/Opcodes.cs:
    case ClientVersionBuild.V3_4_3_53788:
    case ClientVersionBuild.V3_4_3_54261:
        return ClientVersionBuild.V3_4_3_51666;
```

`V3_4_3_51666/Opcodes.cs` 1,643 行；`V3_4_4_59817/Opcodes.cs` 1,709 行。

**但兩者的編號方案根本不同**（實測抽樣）：

| opcode | 3.4.3（51666 表） | 3.4.4（59817 表） |
|---|---|---|
| `CMSG_AUTH_SESSION` | `0x3765` | `0x3B0001` |
| `SMSG_AUTH_CHALLENGE` | `0x3048` | `0x430000` |
| `CMSG_ACCEPT_GUILD_INVITE` | `0x35FE` | `0x3A0029` |
| `CMSG_ACTIVATE_TAXI` | `0x34AB` | `0x360036` |
| `SMSG_ENUM_CHARACTERS_RESULT` | `0x2583` | `0x3C0018` |
| `SMSG_UPDATE_OBJECT` | `0x27CB` | `0x4C0000` |

**3.4.3 是 16-bit 平坦編號；3.4.4 是「高 16 位 = handler group、低 16 位 = index」的 32-bit 編號。** 這正是分支那個 commit `f31319912b Core/PacketIO: Change UNKNOWN_OPCODE to uint32` 的由來（`0xBADD` → `0xBBAADD`）。

→ **改打 3.4.3 要：(a) 用 WPP 的 3.4.3 表重新產生整份 `Opcodes.h`；(b) 把 `UNKNOWN_OPCODE` 的型別改回 `uint16`（等於 revert `f31319912b`）；(c) 檢查 `Opcodes.cpp` 的 handler 表有無因 group 概念消失而失效。** 這是機械性工作但**不是小編輯**。

### 2.3 壞消息之二（最硬）：DB2 metadata 要整份重新推導

`DB2Metadata.h` 內每個 store 有 `FileDataId / IndexField / ParentIndexField / FieldCount / FileFieldCount / **LayoutHash** / Fields`。**LayoutHash 與 FieldCount 綁 client build**：對不上，`DB2Manager::LoadStores()` 直接 `TC_LOG_FATAL` 退出。

實測三份 metadata（`git show <ref>:src/server/game/DataStores/DB2Metadata.h`）：

| | 行數 | 解析出的 `*Meta` 結構數 |
|---|---|---|
| tag `TDB343.24081`（3.4.3 lineage） | 12,067 | 788 |
| `origin/cata_classic`（4.4.2） | 12,525 | 815 |
| `origin/wotlk_classic`（3.4.4） | 19,945 | 818 |

LayoutHash 逐一比對（腳本見 §7）：

| 比較 | 共同 store | LayoutHash 相同 | **不同** |
|---|---|---|---|
| `cata_classic`(4.4.2) vs `wotlk_classic`(3.4.4) | 799 | 729 | **70** |
| **`TDB343.24081`(3.4.3) vs `wotlk_classic`(3.4.4)** | 749 | **0** | **749** |

「0 相同」這個數字太極端，所以另做 15 個具名 store 的手動抽樣交叉驗證——**15/15 全部不同**：

```
Item        343=0x72A6F1C2  344=0x62FE3B1A   Spell       343=0xE2395468  344=0xE3D134FB
SpellEffect 343=0x6B64DD7A  344=0x7F31EDF7   Faction     343=0x767B5394  344=0xE3A94265
Talent      343=0x8384964D  344=0x50A76955   SkillLine   343=0x5CB7F941  344=0x1123150E
AreaTable   343=0x19CA1DC6  344=0x705C911D   ChrClasses  343=0x3F74F8D7  344=0x7F76B35B
Map         343=0xBFC078A9  344=0x32401DC5   SpellName   343=0xB0DD8F60  344=0x782EE721
...（Emotes / ItemSparse / ItemEffect / CreatureDisplayInfo / Achievement / QuestSort /
    GameObjects / Vehicle / CurrencyTypes / Difficulty / BattlemasterList 同樣全不同）
```

對照組成立：`Map`、`SpellName`、`Emotes` 在 4.4.2 與 3.4.4 之間**相同**（`0x32401DC5` / `0x782EE721` / `0x590311E0`），證明比對方法沒問題——**是 3.4.3 這一代真的整批不一樣。**

另外 `FieldCount` 在 63 個共同 store 上也不同。

> **但書（重要）：** 3.4.3 那份 metadata 來自 tag `TDB343.24081`，它是 2023-11 從 `master` 分出的獨立 lineage，欄位順序可能是**該 lineage 自己的手寫版本**，未必等於「3.4.3 client 的權威版面」。`DB2Stores.cpp` 的註解自述對齊到 **3.4.3 (51943)**，而你的 client 是 **54261**。**「TDB343 lineage 的 metadata 能否直接用於 54261」——未驗證。**

→ **這是 retarget 的真正成本。** 你有兩條路：
- **(A) 拿 `TDB343.24081` 的 `DB2Metadata.h` / `DB2LoadInfo.h` / `DB2Structure.h` 三件套整組搬過來**，再手動 replay 3.4.4 分支在其上做的 30 處欄位修正。快，但正確性未經驗證，且 51943→54261 的差異未知。
- **(B) 從你自己的 3.4.3.54261 client 重新推導**——**這正是你在 HermesProxy 上已經做過一次的事**（依 WoWDBDefs 的 54261 layout 寫 28 支 loader）。你已經證明自己會做這件事，只是規模從 ~28 張表變成 ~265 張。

**判定：retarget 不是小編輯，是一次 DB2 層的再推導。** 但它是**你已經示範過的那類工作**，不是未知領域。

### 2.4 意外的好消息：3.4.3.54261 的 auth key 就在本 repo 裡

```
git show 92796557f9:sql/base/auth_database.sql | grep 54261
  → (54261,3,4,3,NULL,NULL,'25FD812475DCF26F9F1383AED37FC99E',NULL,NULL,NULL);
```

舊 lineage 的 `build_info` schema 是：
`build, majorVersion, minorVersion, bugfixVersion, hotfixVersion, winAuthSeed, **win64AuthSeed**, mac64AuthSeed, winChecksumSeed, macChecksumSeed`

→ 第 7 欄 = `win64AuthSeed` = **`25FD812475DCF26F9F1383AED37FC99E`**（16 bytes）。

舊 lineage 的 `WorldSocket.cpp` 這樣用它：

```cpp
Trinity::Crypto::SHA256 digestKeyHash;
digestKeyHash.UpdateData(account.Game.KeyData...);
if (account.Game.OS == "Wn64") digestKeyHash.UpdateData(buildInfo->Win64AuthSeed...);
```

新 schema 的等價寫法會是：
`INSERT INTO build_auth_key VALUES (54261,'Win','x64','WoW',0x25FD812475DCF26F9F1383AED37FC99E);`

repo 內同時還有 51943 / 52237 / 53622 / 53788 的對應金鑰。

> **兩個未驗證點：**
> 1. **`type` 該填 `'WoW'` 還是 `'WoWC'`。** 舊 schema 沒有這個維度；3.4.4 的每個 build 都同時有兩者。
> 2. **雜湊演算法。** 舊 lineage 用 `SHA256` / `HMAC_SHA256`，現行 `cata_classic` / `wotlk_classic` 用 `SHA512` / `HMAC_SHA512`。**3.4.3.54261 的 client 期望哪一種——未驗證。** 若它期望 SHA256，`WorldSocket::HandleAuthSessionCallback` 就必須降級，這是 §5 Stage 2 的第一個要撞的牆。金鑰材料本身（16 bytes）兩者共用，所以最壞情況是改演算法，不是重找金鑰。

### 2.5 小結

| 項目 | 3.4.4 → 3.4.3 的成本 |
|---|---|
| build 常數 | **小編輯**（3 筆 SQL），金鑰現成 |
| CASC product code | **零**（已是 `wow_classic`；且只有 local 模式有意義） |
| opcode 表 | **整表重生 + revert uint32 表示法**（WPP 有現成資料） |
| DB2 metadata / LoadInfo / Structure | **整份再推導**（749/749 LayoutHash 不同） |
| hotfixes schema | **跟著 DB2 重生**（343 組 `CREATE TABLE`） |
| 已修的 8 個封包結構 | **要逐一重判**——例如 `EnumCharactersResult` 的 `Flags4` / `AvgEquippedItemLevel` 是 3.4.4 加的，3.4.3 未必有 |
| auth 雜湊演算法 | **未驗證**，可能要 SHA512 → SHA256 |

**→ 答案：retargeting 是 re-derivation，不是 small edit。** 唯一真正「小」的部分是 build 號本身。

---

## 3. 「未完成」在實務上是什麼

### 3.1 那句「very raw and DB is no updated yet (crashes)」的一手來源

實際取得（`gh api graphql`，discussion 28324「Will we update to 3.4.0?」）：

```
[funjoker 2022-10-04] https://github.com/TrinityCore/TrinityCore/tree/wotlk_classic
                      feel free to help :) Currently we are working on a fork
                      https://github.com/mdX7/TrinityCore/commits/wotlk_classic
[Aokromes 2022-10-04] 3.4.0 is not real wotlk, is a mix between 3.0 and 2.4.3
[funjoker 2024-01-13] https://github.com/TrinityCore/TrinityCore/tree/wotlk_classic supports 3.4.3.52237.
                      It's very raw and DB is no updated yet (crashes)
```

**重要的時序修正：這句話發表於 2024-01-13，指的是當時的 `wotlk_classic` = 3.4.3.52237，也就是後來被 tag `TDB343.24081` 保存的那條 257-commit 舊 lineage。** 它**不是**在講 2025 年重切的 31-commit 分支。

換句話說：**連那條做了完整 WotLK 降級（天賦/符文/屬性/物品/任務）的 lineage，作者自己都說會 crash。** 而現在的分支連那些降級都沒做。

其他佐證（PR / issue，實測）：

```
gh api "search/issues?q=repo:TrinityCore/TrinityCore+base:wotlk_classic+is:pr"
  → total_count: 13，最新 #30946「3.4: Remove non existent classes in gametable.h」（2025-05-14 closed）
```

13 個 PR 全數 closed，跨越 2023-01 到 2025-05。

### 3.2 從程式碼看：具體會撞哪些牆，以及在登入→進世界流程的哪一步

按流程順序：

**① `worldserver` 啟動 — DB2 版本檢查（硬性 fatal）**

`src/server/game/DataStores/DB2Stores.cpp::LoadStores()`：

```cpp
if (!sAreaTableStore.LookupEntry(14483) ||       // last area added in 3.4.4 (60340)
    !sCharTitlesStore.LookupEntry(757) ||
    !sGemPropertiesStore.LookupEntry(1629) ||
    !sItemStore.LookupEntry(242551) ||
    !sItemExtendedCostStore.LookupEntry(9184) ||
    !sMapStore.LookupEntry(2567) ||
    !sSpellNameStore.LookupEntry(1233554))       // last spell added in 3.4.4 (60340)
{ TC_LOG_FATAL("misc", "You have _outdated_ DB2 files..."); return 0; }
```

對照舊 lineage 的 3.4.3 (51943) 哨兵值：`AreaTable 14483`（相同）、`ItemSparse` 無、`Item 211851`、`ItemExtendedCost 8328`、`Map 2567`（相同）、`SpellName **429548**`（3.4.4 是 1233554 —— 差三個數量級，說明 3.4.4 client 的 SpellName.db2 是重新編號過的）。

→ **這是第一道牆，而且在載入 DB2 之前你已經被 LayoutHash 擋住了**（§2.3）。**用 3.4.3 client 抽出來的 DB2 餵給這個分支，`worldserver` 連啟動都到不了。**

**② `worldserver` 啟動 — world DB 期望 4.4.2 的 TDB**

`revision_data.h.in.cmake` 指向 `TDB_full_world_442.25051`。而分支自己的 SQL 又改了兩張表的欄位：

```cpp
// ObjectMgr::LoadPlayerInfo()
QueryResult result = WorldDatabase.Query("SELECT class, level, str, agi, sta, inte, spi, basehp FROM player_classlevelstats");
// ObjectMgr::LoadCreatureClassLevelStats()
QueryResult result = WorldDatabase.Query("SELECT level, class, basehp0, basehp1, basehp2, basemana, basearmor, "
                                         "attackpower, rangedattackpower, damage_base, damage_exp1, damage_exp2 "
                                         "FROM creature_classlevelstats");
```

→ **必須是「TDB 442 + 分支那兩個 world SQL」的組合**，缺一不可。灌 TDB343.24081 的 world DB 會在這裡 query 失敗。

**③ 種族/職業裁剪只做了一半**

`RaceMask.h`：`MAX_RACES` 23 → 12，`RACE_GOBLIN` / `RACE_WORGEN` 被註解。
`SharedDefines.h`：刪掉 `CLASS_MONK` / `CLASS_DEMON_HUNTER` / `CLASS_EVOKER` / `CLASS_ADVENTURER`——但 **`#define MAX_CLASSES 15` 沒有跟著改**。

而 `ObjectMgr::LoadPlayerInfo()` 裡的資料片過濾是被**註解掉**的：

```cpp
// if (sWorld->getIntConfig(CONFIG_EXPANSION) < EXPANSION_CATACLYSM && (race == RACE_GOBLIN || race == RACE_WORGEN))
//     continue;
// if (sWorld->getIntConfig(CONFIG_EXPANSION) < EXPANSION_LEGION && class_ == CLASS_DEMON_HUNTER)
//     continue;
// if (sWorld->getIntConfig(CONFIG_EXPANSION) < EXPANSION_DRAGONFLIGHT && class_ == CLASS_EVOKER)
//     continue;
```

**這不是「做完了所以拿掉」，是「enum 被刪掉編不過，所以先註解掉」**（配合 `06d7821e12 Core/Misc: Build fix`、`38acb46dc9 Misc: Fix 1 error` 兩個 commit 的命名）。TDB 442 的 `playercreateinfo` 仍含 Goblin(9) / Worgen(22) / Monk(10) / DH(12) 的資料列，這些列現在會落在無人維護的縫隙裡。**這是「已知會產生髒資料」的區域，不是已完成的功能。**

**④ 封包結構——真正的無底洞**

只有 8 個封包被驗證過（§1.2）。`Opcodes.h` 是 706 CMSG + 1151 SMSG。**其餘的結構正確性完全未知，而且只能靠實跑逐個撞出來。**

**⑤ 遊戲系統仍是 Cataclysm 的**

`cata_classic` 的天賦是 31 點 + Mastery，等級上限 85，法術是 Cata 平衡。分支只改了 basehp / stamina→HP 兩條公式，以及移除 taxi node。**天賦、符文、物品、任務欄位、DK 起始等級、等級上限——一項都沒動。**

### 3.3 一句話

> **`wotlk_classic` = 「把 `cata_classic` 的通訊層撞到 3.4.4 client 能連上」的 patch set。它不是一個 WotLK 伺服器，它是一個「講 3.4.4 方言的 Cataclysm 伺服器」。**

---

## 4. 在地化工作能不能帶走？——能，而且比預期好

這一節對你最有直接價值。**結論：那 ~28 支 loader 背後的知識 100% 可用；程式碼形態要換，但換的方向是「從自己寫 loader」變成「填 SQL 表」——工作量是往下走的。**

### 4.1 TrinityCore 原生的 hotfix 下發路徑（與 HermesProxy 做的事同構）

```
client 登入後 → WorldSession::SendAvailableHotfixes()  (WorldSession.cpp:1232)
             → SMSG_AVAILABLE_HOTFIXES
client       → CMSG_HOTFIX_REQUEST
server       → WorldSession::HandleHotfixRequest()  (Handlers/HotfixHandler.cpp:75)
             → SMSG_HOTFIX_CONNECT，內含依 DB2Metadata 版面序列化的 DB2 record blob
```

`Opcodes.cpp` 已註冊：`DEFINE_HANDLER(CMSG_HOTFIX_REQUEST, STATUS_AUTHED, PROCESS_THREADUNSAFE, &WorldSession::HandleHotfixRequest)`。

**這正是 HermesProxy 現在替你做的事——差別只在誰產生那個 blob。** 原生路徑用的版面來源是 `DB2Metadata.h`，也就是你已經從 WoWDBDefs 推導過的那份資訊。

### 4.2 資料從哪來

三層（`DB2Manager::LoadHotfixData` / `LoadHotfixBlob` / `LoadHotfixOptionalData`，`DB2Stores.cpp:1418` / `:1492` / `:1547`）：

| 表 | 用途 |
|---|---|
| `hotfix_data` (`Id, UniqueId, TableHash, RecordId, Status, VerifiedBuild`) | 索引：告訴 client「這筆記錄有 hotfix」 |
| **每個 DB2 各自的鏡像表**（如 `item_sparse`、`creature_display_info`…） | 完整記錄的欄位資料 |
| **每個可在地化 DB2 的 `*_locale` 表**（如 `item_sparse_locale`） | **只有語系字串** |
| `hotfix_blob` | 給 core 不認識的 DB2 store 用的原始 blob 逃生門 |

### 4.3 zhTW 是一等公民（實測）

`src/common/Common.h`：

```cpp
enum LocaleConstant : uint8 {
    LOCALE_enUS = 0, LOCALE_koKR = 1, LOCALE_frFR = 2, LOCALE_deDE = 3,
    LOCALE_zhCN = 4, LOCALE_zhTW = 5, LOCALE_esES = 6, LOCALE_esMX = 7,
    LOCALE_ruRU = 8, LOCALE_none = 9, LOCALE_ptBR = 10, LOCALE_itIT = 11,
    TOTAL_LOCALES
};
```

`wotlk_classic` 的 `2025_05_13_00_hotfixes.sql` 內，**79 張 `*_locale` 表全部原生帶 `zhTW` 分區**：

```sql
CREATE TABLE `item_sparse_locale` (
  `ID` int unsigned NOT NULL DEFAULT '0',
  `locale` varchar(4) NOT NULL,
  `Description_lang` text, `Display3_lang` text, `Display2_lang` text,
  `Display1_lang` text, `Display_lang` text,
  `VerifiedBuild` int NOT NULL DEFAULT '0',
  PRIMARY KEY (`ID`,`locale`,`VerifiedBuild`)
) ... PARTITION BY LIST COLUMNS(locale)
(PARTITION deDE ..., PARTITION esES ..., PARTITION esMX ..., PARTITION frFR ...,
 PARTITION itIT ..., PARTITION koKR ..., PARTITION ptBR ..., PARTITION ruRU ...,
 PARTITION zhCN VALUES IN ('zhCN') ENGINE = InnoDB,
 PARTITION zhTW VALUES IN ('zhTW') ENGINE = InnoDB);
```

（`grep -c "^CREATE TABLE .*_locale."` → **79**；`grep -c zhTW` → 78，差的 1 筆是 `hotfix_blob` 之類非 `_locale` 表的引用差異。343 張表中 79 張可在地化。）

而 `src/server/database/Database/Implementation/HotfixDatabase.cpp` 有 **79 條 `PREPARE_LOCALE_STMT`**，格式固定：

```cpp
PREPARE_LOCALE_STMT(HOTFIX_SEL_ACHIEVEMENT,
    "SELECT ID, Description_lang, Title_lang, Reward_lang FROM achievement_locale"
    " WHERE (`VerifiedBuild` > 0) = ? AND locale = ?", CONNECTION_SYNCH);
```

載入端：`DB2Stores.cpp:507` `storage->LoadStringsFromDB(i)`（逐 locale）。

### 4.4 所以那 ~28 支 loader 的下場

| 你現在有的東西 | 在原生 stack 裡的下場 |
|---|---|
| **每張表在 build 54261 的欄位版面**（由 WoWDBDefs 推導、經 client `VALIDATION_RESULT_VALID` 驗證） | **完全保留，而且是最有價值的部分。** 它就是你要拿去修 `DB2Structure.h` / `DB2LoadInfo.h` / `DB2Metadata.h` 的權威依據 |
| **zhTW 字串資料本身**（wago.tools） | **完全保留。** 改成 `INSERT INTO <table>_locale (ID, locale, <X>_lang, ..., VerifiedBuild) VALUES (..., 'zhTW', ..., 54261)` |
| **~28 支 C# loader 的程式碼** | **丟棄。** 但取代它的不是「重寫 28 支 loader」，而是「填表 + 讓既有的 `PREPARE_LOCALE_STMT` 讀」 |
| **12 張伺服器端 `*_locale` 表**（quest / creature / gameobject …） | **完全保留。** 這些是 world DB 的表，`cata_classic` / `wotlk_classic` 的 world schema 同樣有 `*_locale` 系列 |
| **HermesProxy 那一層** | 整層消失（這正是換 backend 的重點） |

**但有一個不能忽略的前提：`*_locale` 表的欄位名（`Description_lang`、`Display_lang` …）是由 `DB2Structure.h` 自動產生的。** 所以在地化能不能落地，**完全取決於 §2.3 那份 3.4.3 DB2 結構推導有沒有做對**。**在地化不是獨立工作項，它是 DB2 層的下游。**

**判定：在地化這條路是通的，而且原生路徑比 HermesProxy 那條乾淨。但它排在整個工程的最後——你要先讓 DB2 層對齊 3.4.3.54261，在地化才有地方放。**

---

## 5. 完工計畫（每階段附「完成的定義」）

> 與路線圖筆記 §5 的差別：那邊是「從 `cata_classic` 打造 3.4.4 伺服器」的通用計畫；**這裡是「以現有 31-commit 為起點、目標 build 改成 3.4.3.54261」的具體版本，並修正該篇對 Stage 1 難度的估計。**

### Stage 1 — rebase 到現在的 `cata_classic`（**比想像中便宜非常多**）

路線圖筆記 §5 Stage 1 說：「衝突熱點：`DB2Metadata.h`（19,874 行）、`DB2LoadInfo.h`（6,152 行）、`Opcodes.h`（3,754 行）、`UpdateFields.cpp/.h`。這三個檔在 `cata_classic` 上也一直在動。」

**實測推翻了這個推測：**

```
git diff --stat af8de3493f origin/cata_classic -- \
    DB2Metadata.h DB2LoadInfo.h DB2Structure.h Opcodes.h UpdateFields.cpp UpdateFields.h
  → src/server/game/DataStores/DB2Structure.h                    | 10 ++++
    src/server/game/Entities/Object/Updates/UpdateFields.cpp     |  4 +-
    src/server/game/Server/Protocol/Opcodes.h                    | 61 +++++++++------
    3 files changed, 51 insertions(+), 24 deletions(-)
```

**`DB2Metadata.h`、`DB2LoadInfo.h`、`UpdateFields.h` 三個檔，自 merge-base 至今在 `cata_classic` 上一行都沒改過。**

觸及次數（`git rev-list --count af8de3493f..origin/cata_classic -- <path>`，總 1264 個 commit）：

| 路徑 | commit 數 |
|---|---|
| `src/server/game/DataStores/` | 11 |
| `src/server/game/Server/Protocol/Opcodes.h` | 3 |
| `src/server/game/Entities/Object/Updates/` | 1 |
| `sql/updates/world/cata_classic/` | **499** |

→ **1264 個 commit 裡，絕大多數是 world DB 內容與腳本修正，不是通訊層。** rebase 的機械衝突面極小。

- **做什麼**：`git rebase --onto origin/cata_classic af8de3493f <你的分支>`。預期只在 `Opcodes.h`（cata 新增的 opcode，如 `CMSG_ARENA_TEAM_*`）與 `DB2Structure.h`（+10 行）撞到。
- **完成的定義**：`worldserver` / `bnetserver` / 五個 extractor 編得過。
- **難點**：低。**這一階段是本專案唯一一個「比預期簡單」的地方。** 順帶白拿 499 個 world DB commit 與所有 Northrend 腳本修正。
- **注意**：`cata_classic` 期間新增的 opcode 要在你的 3.4.3 表裡找到對應值（WPP 3.4.3 表若沒有，就是該 build 不存在該功能，直接砍掉 handler）。

### Stage 2 — 改靶到 3.4.3.54261（**最硬的一步**）

- **做什麼**（依序，有嚴格相依）：
  1. `sql/base/auth_database.sql` + 一個新的 `sql/updates/auth/` 檔：`build_info` 加 `(54261,3,4,3,NULL)`、`build_auth_key` 加 `(54261,'Win','x64','WoW',0x25FD812475DCF26F9F1383AED37FC99E)`（金鑰見 §2.4）、`realmlist.gamebuild = 54261`。
  2. `src/server/game/Server/Protocol/Opcodes.h`：從 WPP `V3_4_3_51666/Opcodes.cs`（1,643 行）重生整表；revert `f31319912b`（`UNKNOWN_OPCODE` 回 `uint16`）；清理 `Opcodes.cpp` 的 handler 表。
  3. `src/server/game/DataStores/DB2Structure.h` → `DB2LoadInfo.h` → `DB2Metadata.h` → `sql/base/dev/hotfixes_database.sql` + `HotfixDatabase.cpp`，**四者必須一致**。這是 §2.3 的再推導。起點二選一：搬 `TDB343.24081` 的三件套，或從你自己的 54261 client 推。
  4. `src/server/game/DataStores/DB2Stores.cpp`：哨兵值改成 54261 client 實際的最後一筆（3.4.3(51943) 的參考值：`AreaTable 14483` / `CharTitles 757` / `GemProperties 1629` / `Item 211851` / `ItemExtendedCost 8328` / `Map 2567` / `SpellName 429548`）。
  5. `src/tools/extractor_common/ExtractorDB2LoadInfo.h` 跟著改。
  6. `src/tools/map_extractor/System.cpp`：`Storage::Open()` local 模式指向你已安裝的 54261 CASC 目錄（product code 不用動）。跑 `contrib/extractor.sh`。
- **完成的定義**：`worldserver` 通過 `DB2Manager::LoadStores()` 的版本檢查而不 `TC_LOG_FATAL`。
- **難點**：**這是全案最硬的一步，理由是三件套的自動產生器不在 repo 內**（`DB2LoadInfo.h` 檔頭寫著 `// DO NOT EDIT! // Autogenerated from DB2Structure.h`，`HotfixDatabase.cpp` 同樣；`contrib/` 只有 `enumutils_describe.py` / `protoc-bnet` / SQL 腳本）。**你要嘛手改 ~265 個 store，要嘛自己寫一支從 `DB2Structure.h` 產生另外三份的 parser。後者是正解，也是你在 HermesProxy 上做過的同一類事。**

### Stage 3 — 登入畫面 / realm list / 角色列表

- **做什麼**：`bnetserver`（LoginREST port 8081 + Battle.net protobuf port 1119）；client 端需 patcher 導向自架服務。`GetRealmListTicket` / `JoinRealm`（`src/server/bnetserver/Services/GameUtilitiesService.cpp`）。**驗證 §2.4 的 SHA512 vs SHA256 問題**——若 client 拒絕，改 `WorldSocket::HandleAuthSessionCallback` 的雜湊。
- **重判分支已改的封包**：`SMSG_ENUM_CHARACTERS_RESULT`（`CharacterPackets.h/.cpp`）——3.4.4 加的 `Flags4` / `AvgEquippedItemLevel` / `WarbandSceneID` 在 3.4.3 未必存在，`RaceID` 的 `int32`↔`int8` 也要重判；`SMSG_ENTER_ENCRYPTED_MODE`（`AuthenticationPackets.h/.cpp`）的 `RegionGroup` 欄位同理；`FeatureSystemStatus` / `FeatureSystemGlueScreen`（`SystemPackets.h/.cpp`）。
- **完成的定義**：能建一個角色並在角色選單看到它。
- **難點**：中。這裡有 HermesProxy 當「參考解答」——**你已經有一份能與 54261 client 正確對話的實作**，可以直接比對封包版面。這是你相對上游作者的**獨有優勢**。

### Stage 4 — 進世界

- **做什麼**：`SMSG_UPDATE_OBJECT` / `BuildMovementUpdate`（`Object.cpp`、`MovementInfo.h`、`UpdateFields.cpp/.h`）、`SMSG_AURA_UPDATE`、`SMSG_SPELL_START` / `SMSG_SPELL_GO`、`SMSG_ON_MONSTER_MOVE`、各種 `SMSG_QUERY_*_RESPONSE`（`QueryPackets.h/.cpp`）逐一對齊 3.4.3。
- **完成的定義**：進世界、移動、看到 NPC、施法、接任務。
- **難點**：**最耗時。** 但同樣有兩份參考解答：舊 lineage 已針對 3.4.3 做過一次（`git show 92796557f9:...`），以及你自己的 HermesProxy。

### Stage 5 — WotLK 遊戲系統降級

- **做什麼**：從 tag `TDB343.24081` 的 257 個 commit 裡挑天賦（`TalentTab`）、符文、屬性公式、物品、任務欄位、DK 起始等級、等級上限。
- **難點**：舊 lineage 是從 `master` 降級，你是從 `cata_classic` 降級——不能無腦 cherry-pick。詳見路線圖筆記 §5 Stage 5。
- **已知未完成項**（舊 lineage 自述）：DK rune regeneration。

### Stage 6 — 內容資料庫 + 在地化

- **做什麼**：world DB 用 TDB 343.24081 或 TDB 442 二選一（見 `cata-classic-backend-option.md`）；hotfixes DB 從你自己的 54261 client 重抽 DB2 灌入；**最後才是把 zhTW 資料填進 79 張 `*_locale` 表**（§4）。
- **難點**：1–60 舊世界的災變前地形 × 災變後 spawn（路線圖 §4.4 末段），這是全案最大未知。

### 最硬的一步是哪一個

**Stage 2。** 理由：
1. 它是**唯一沒有現成參考解答的階段**。Stage 3/4 你有 HermesProxy 對照，Stage 5 你有舊 lineage 對照，Stage 1 幾乎免費。Stage 2 的 3.4.3 DB2 版面既不在 `wotlk_classic`（那是 3.4.4）、也不確定在 `TDB343.24081`（那是 51943，你的是 54261）。
2. **它是硬阻斷。** 沒過就是 `TC_LOG_FATAL` 退出，後面全部階段歸零。
3. 它的產生器不在 repo，且四份檔案必須完全一致。

---

## 6. 誠實的判定

### 6.1 這是不是一個現實的個人專案？

**分階段回答：**

| 階段 | 現實嗎 | 為什麼 |
|---|---|---|
| Stage 1（rebase） | **是。** 幾天 | 實測衝突面極小（§5.1） |
| Stage 2（改靶 3.4.3） | **是，但很累。** 推估數週 | 沒有參考解答，但**這正是你在 HermesProxy 上做過 28 次的同一件事**，只是規模放大到 ~265 張表，且要順帶寫一支 code generator |
| Stage 3（登入 → 角色列表） | **是。** 推估數週 | 有 HermesProxy 當對照組——這是決定性的優勢 |
| Stage 4（進世界 + 封包對齊） | **勉強。** 推估數月 | 上千個封包，只能實跑撞。上游兩位維護者做到第 8 個就停了 |
| Stage 5（WotLK 系統降級） | **勉強。** 推估數月 | 有 257 個 commit 當參考解答，但要逐條重判 |
| Stage 6（內容 + 在地化） | **沒有終點** | 1–60 舊世界的地形錯位可能沒有乾淨解 |

**（所有時間推估未驗證。）**

**總判定：Stage 1–3 是現實的個人專案；Stage 4 之後不是。** 而 Stage 1–3 的產出是「一個能讓 3.4.3 client 走到角色選單的 Cataclysm 伺服器」——**它在遊戲體驗上不如你現在跑得起來的 stack。**

### 6.2 和「繼續擴充 HermesProxy stack」比

必須說清楚兩者不是同一種東西：

| | 現行 stack（3.4.3 client → HermesProxy → `3.3.5`） | 完工後的 `wotlk_classic` |
|---|---|---|
| **現在的狀態** | **跑得起來**，登入 / 建角 / 進世界 / 任務 / 戰鬥皆正常 | 連 `worldserver` 都啟動不了（DB2 版本檢查） |
| 遊戲內容 | 完整的 3.3.5a（`3.3.5` 分支 + 官方 TDB，最成熟的內容資料庫） | Cataclysm 4.4.2 的內容，除非再做 Stage 5–6 |
| 職業 / 天賦手感 | **真正的 WotLK**（3.3.5 分支原生） | Cataclysm 的，直到 Stage 5 完成 |
| 1–60 舊世界 | **正確**（3.3.5 資料 + client 災變前地形，兩邊一致） | **這是全案最大的未解問題** |
| zhTW 在地化 | **已完成並經 client 驗證** | 要重做一次（知識可帶走，程式碼不行） |
| 架構代價 | 多一層 translating proxy | 無 proxy |
| 上游支援 | `3.3.5` 分支官方積極維護、有 issue 範本、有 TDB release | `wotlk_classic` 停滯 14 個月、wiki 標 abandoned、GitHub 標 stale、issue 範本不收 |
| 剩餘工作量 | 增量（想加什麼加什麼） | Stage 1–6 |

**要點：完成 `wotlk_classic` 不會讓你「得到現在沒有的東西」，它會讓你「用不同的方式重新得到你已經有的東西，並在中途失去 1–60 舊世界的正確性」。** 你付出的是數月到數年，換掉的是一層 proxy。

### 6.3 明確建議

1. **不要以「取代現行 stack」為目標去做 `wotlk_classic`。** 投入產出比是負的：你會用數月換掉一層 proxy，同時把 1–60 舊世界從「正確」變成「已知有問題」，還要重做在地化。
2. **如果你想做，把它當成獨立的技術專案，範圍鎖在 Stage 1–3，並明確接受「終點是角色選單」。** 這個範圍是現實的、有明確驗收標準的、而且能讓你完整掌握 TrinityCore 的現代 DB2 / bnet 層。**Stage 2 完成的那份「3.4.3.54261 DB2 三件套 + code generator」本身就是有價值的產出**——它是這個生態裡目前不存在的東西，而你剛好是**最有資格做出來的人**（你已經為 28 張表做過同樣的推導並經 client 驗證）。
3. **不要期待 Stage 4 之後。** 上游兩位維護者（含首席）花七週做到第 8 個封包就停了；更早那條 257-commit 的 lineage 做完了整套降級，作者自己說「crashes」。這不是能力問題，是規模問題。
4. **在地化不用擔心會白做。** 版面推導的知識、zhTW 資料、12 張 world `*_locale` 表都能帶走；只有 28 支 C# loader 的程式碼形態要換，而換過去的目標（填 79 張現成的 `*_locale` 表）比你現在做的事簡單。**但它排在 Stage 2 之後——DB2 層沒對齊，在地化就沒有地方放。**
5. **務實的中間路線**（如果你想要「無 proxy」而不想付全額）：見 `cata-classic-backend-option.md`。本篇不重複那個題目。

---

## 7. 驗證指令（全部唯讀，未切換 working tree、未修改任何追蹤檔案）

```bash
# --- 分支狀態 ---
git merge-base origin/cata_classic origin/wotlk_classic          # af8de3493f
git rev-list --count origin/cata_classic..origin/wotlk_classic   # 31
git rev-list --count origin/wotlk_classic..origin/cata_classic   # 1264
git log -1 --format='%h %cd %an %s' --date=short origin/cata_classic    # 3bc146f58a 2026-08-31
git log -1 --format='%h %cd %an %s' --date=short origin/wotlk_classic   # 12c81a6f86 2025-07-02
git diff --stat af8de3493f origin/wotlk_classic                  # 57 files, +32696 -12013
git diff --name-status af8de3493f origin/wotlk_classic -- sql
gh api repos/TrinityCore/TrinityCore/branches/wotlk_classic \
  --jq '.commit.sha, .commit.commit.committer.date, .commit.commit.message'

# --- Stage 1 成本：cata 側漂移 ---
bash -c 'git diff --stat af8de3493f origin/cata_classic -- \
  src/server/game/DataStores/DB2Metadata.h \
  src/server/game/DataStores/DB2LoadInfo.h \
  src/server/game/DataStores/DB2Structure.h \
  src/server/game/Server/Protocol/Opcodes.h \
  src/server/game/Entities/Object/Updates/UpdateFields.cpp \
  src/server/game/Entities/Object/Updates/UpdateFields.h'
git rev-list --count af8de3493f..origin/cata_classic -- src/server/game/DataStores          # 11
git rev-list --count af8de3493f..origin/cata_classic -- sql/updates/world/cata_classic      # 499

# --- build 常數在哪 ---
bash -c "git grep -n 61581 origin/wotlk_classic -- '*.h' '*.cpp' '*.cmake' '*.conf.dist'"   # 只有巧合命中
git show origin/wotlk_classic:sql/updates/auth/wotlk_classic/2025_06_23_00_auth.sql
git show origin/wotlk_classic:src/server/game/Server/WorldSocket.cpp | sed -n '710,745p'

# --- 3.4.3.54261 的 auth key（在舊 lineage 裡）---
git show 92796557f9:sql/base/auth_database.sql | grep 54261
git show 92796557f9:sql/base/auth_database.sql | grep -A14 'CREATE TABLE .build_info.'
git show 92796557f9:src/server/game/Server/WorldSocket.cpp | sed -n '705,725p'   # SHA256 vs SHA512

# --- opcode 表 ---
gh api repos/TrinityCore/WowPacketParser/contents/WowPacketParser/Enums/Version --jq '.[].name' | grep V3_4
gh api repos/TrinityCore/WowPacketParser/contents/WowPacketParser/Enums/Version/Opcodes.cs \
  --jq '.content' | base64 -d | grep -A3 'V3_4_3_54261'        # → return V3_4_3_51666
gh api repos/TrinityCore/WowPacketParser/contents/WowPacketParser/Enums/Version/V3_4_3_51666/Opcodes.cs \
  --jq '.content' | base64 -d | grep CMSG_AUTH_SESSION          # 0x3765（16-bit）
gh api repos/TrinityCore/WowPacketParser/contents/WowPacketParser/Enums/Version/V3_4_4_59817/Opcodes.cs \
  --jq '.content' | base64 -d | grep CMSG_AUTH_SESSION          # 0x3B0001（32-bit）

# --- DB2 LayoutHash 比對（§2.3 的核心數字）---
bash -c '
git show 92796557f9:src/server/game/DataStores/DB2Metadata.h            > /tmp/meta343.h
git show origin/wotlk_classic:src/server/game/DataStores/DB2Metadata.h  > /tmp/meta344.h
git show origin/cata_classic:src/server/game/DataStores/DB2Metadata.h   > /tmp/metacata.h
for s in Item Spell Talent AreaTable Map SpellName Emotes; do
  a=$(awk "/^struct ${s}Meta/,/^};/" /tmp/meta343.h  | grep -oE "0x[0-9A-F]{8}" | head -1)
  b=$(awk "/^struct ${s}Meta/,/^};/" /tmp/meta344.h  | grep -oE "LayoutHash *= *0x[0-9A-F]{8}" | grep -oE "0x[0-9A-F]{8}" | head -1)
  c=$(awk "/^struct ${s}Meta/,/^};/" /tmp/metacata.h | grep -oE "0x[0-9A-F]{8}" | head -1)
  echo "$s  343=$a  344=$b  cata=$c"
done'
# 注意：舊 lineage / cata 用 DB2Meta Instance{...} 位置初始化，
#       wotlk_classic 用 .LayoutHash = ... designated initializer，兩者要用不同 regex 解析

# --- DB2 版本檢查哨兵值 ---
git show origin/wotlk_classic:src/server/game/DataStores/DB2Stores.cpp | grep -A12 'Check loaded DB2 files proper version'
git show 92796557f9:src/server/game/DataStores/DB2Stores.cpp          | grep -A12 'Check loaded DB2 files proper version'

# --- 半成品的種族/職業裁剪 ---
git diff af8de3493f origin/wotlk_classic -- src/server/game/Globals/ObjectMgr.cpp | grep -B2 -A10 'skip expansion races'
git show origin/wotlk_classic:src/server/game/Miscellaneous/SharedDefines.h | grep -A3 'max+1 for player class'   # MAX_CLASSES 15

# --- 在地化管線 ---
git show origin/wotlk_classic:src/common/Common.h | grep -A16 'enum LocaleConstant'
bash -c "git show origin/wotlk_classic:sql/updates/hotfixes/wotlk_classic/2025_05_13_00_hotfixes.sql | grep -c '^CREATE TABLE'"          # 343
bash -c "git show origin/wotlk_classic:sql/updates/hotfixes/wotlk_classic/2025_05_13_00_hotfixes.sql | grep -c '^CREATE TABLE .*_locale.'" # 79
bash -c "git show origin/wotlk_classic:src/server/database/Database/Implementation/HotfixDatabase.cpp | grep -c PREPARE_LOCALE_STMT"       # 79
git show origin/wotlk_classic:sql/updates/hotfixes/wotlk_classic/2025_05_13_00_hotfixes.sql | grep -A24 'CREATE TABLE .item_sparse_locale.'
git grep -n 'SendAvailableHotfixes\|HandleHotfixRequest' origin/wotlk_classic -- src/server/game
git show origin/wotlk_classic:src/server/game/DataStores/DB2Stores.cpp | sed -n '1418,1490p'

# --- TDB / README ---
git show origin/wotlk_classic:revision_data.h.in.cmake | grep -i DATABASE_
git show origin/cata_classic:revision_data.h.in.cmake  | grep -i DATABASE_
git show origin/wotlk_classic:README.md | head -1

# --- funjoker 的原話 ---
gh api graphql -f query='{repository(owner:"TrinityCore",name:"TrinityCore"){
  discussion(number:28324){title url comments(first:50){nodes{author{login} createdAt body}}}}}'
gh api "search/issues?q=repo:TrinityCore/TrinityCore+base:wotlk_classic+is:pr" --jq '.total_count'   # 13
```

---

## 8. 對前兩篇筆記的修正

| 位置 | 原文 | 修正 |
|---|---|---|
| `wotlk-classic-port-roadmap.md` §5 Stage 1 | 「衝突熱點：`DB2Metadata.h`（19,874 行）、`DB2LoadInfo.h`（6,152 行）、`Opcodes.h`（3,754 行）、`UpdateFields.cpp/.h`。這三個檔在 `cata_classic` 上也一直在動」 | **不成立。** 實測 `DB2Metadata.h` / `DB2LoadInfo.h` / `UpdateFields.h` 自 merge-base 起在 `cata_classic` 上**零改動**；有漂移的只有 `Opcodes.h`(+61/−24)、`DB2Structure.h`(+10)、`UpdateFields.cpp`(±4)。rebase 成本被高估 |
| `wotlk-classic-port-roadmap.md` §6 | 「WowPacketParser 有 `V3_4_4_59817` 與 `V3_4_5_61815` 的 opcode 表」 | **不完整。** 另有 **`V3_4_3_51666`**（1,643 行），且 `Enums/Version/Opcodes.cs` 明文把 `V3_4_3_54261` 對映到它。**3.4.3 的表現成存在，不用 sniff** |
| 兩篇皆未涵蓋 | opcode 編號方案 | **新增：3.4.3 是 16-bit 平坦編號、3.4.4 是 32-bit group 編號。** 改靶要 revert `f31319912b`（`UNKNOWN_OPCODE` 的 `uint32`） |
| 兩篇皆未涵蓋 | 3.4.3 的 client auth key | **新增：`25FD812475DCF26F9F1383AED37FC99E`（Win64）就在本 repo 的 tag `TDB343.24081` 裡**（連同 51943 / 52237 / 53622 / 53788）。但雜湊演算法（SHA256 vs SHA512）未驗證 |
| `wotlk-classic-on-modern-client.md` §3.4 | 把 funjoker 的「very raw and DB is no updated yet (crashes)」當成對「31-commit spike」的評語 | **時序錯置。** 該留言發表於 **2024-01-13**，指的是當時的 `wotlk_classic` = **3.4.3.52237**，即後來被 tag `TDB343.24081` 保存的 257-commit 舊 lineage。2025 年重切的 31-commit 分支從未被作者評論過 |
| 兩篇皆未涵蓋 | 在地化可攜性 | **新增：hotfixes schema 的 79 張 `*_locale` 表原生帶 `zhTW` 分區，`HotfixDatabase.cpp` 有 79 條 `PREPARE_LOCALE_STMT`，`LOCALE_zhTW = 5`。在地化的知識與資料可 100% 帶走** |

---

## 9. 實際取用過的來源

**本 repo（唯讀 git，未切換分支、未修改任何追蹤檔案）**
- refs：`origin/cata_classic`、`origin/wotlk_classic`、merge-base `af8de3493f`、tag `TDB343.24081`（`92796557f9`）
- `src/server/game/DataStores/{DB2Stores.cpp, DB2Metadata.h, DB2LoadInfo.h, DB2Structure.h}`
- `src/server/game/Server/{WorldSocket.cpp, Protocol/Opcodes.h, Protocol/Opcodes.cpp, Packets/*}`
- `src/server/game/{Globals/ObjectMgr.cpp, Miscellaneous/SharedDefines.h, Miscellaneous/RaceMask.h, Handlers/HotfixHandler.cpp}`
- `src/server/database/Database/Implementation/HotfixDatabase.cpp`
- `src/server/shared/Realm/ClientBuildInfo.cpp`、`src/common/Common.h`
- `sql/base/auth_database.sql`、`sql/base/dev/hotfixes_database.sql`、`sql/updates/{auth,hotfixes,world}/wotlk_classic/*`
- `revision_data.h.in.cmake`、`README.md`

**TrinityCore 官方 GitHub（`gh api` / `gh api graphql` 實際取得）**
- `repos/TrinityCore/TrinityCore/branches/wotlk_classic`
- `discussions/28324`（funjoker / Aokromes 原文，含時間戳）
- `search/issues?q=...base:wotlk_classic+is:pr`（13 個，全 closed）
- `repos/TrinityCore/WowPacketParser/contents/WowPacketParser/Enums/Version/`（目錄清單、`Opcodes.cs` 對映表、`V3_4_3_51666/Opcodes.cs`、`V3_4_4_59817/Opcodes.cs`、`ClientVersionBuild.cs`）

**未驗證項一覽（本文明確標示者）**
1. 作者是否真的把 client 帶進了世界（只有間接推論）
2. `TDB343.24081` 的 DB2 metadata 能否直接用於 build 54261（其自述對齊 51943）
3. 3.4.3.54261 client 期望的 auth 雜湊是 SHA256 還是 SHA512
4. `build_auth_key.type` 對 54261 該填 `'WoW'` 還是 `'WoWC'`
5. 所有時間估計
