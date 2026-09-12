# skill_tiers 驗證(wotlk_classic / TrinityCore 3.4.x)

驗證日期:2026-09-12
分支:`wotlk_classic`(HEAD `5b82ea0170`)
方法:直接讀 `src/server/` 原始碼 + git 歷史 + 一項 web 佐證。所有結論都附 file:line 或 commit。

---

## TL;DR / 建議

- **直接原封匯入 TDB343 的 `skill_tiers`(58 rows)是正確作法。** 它是 3.4.x core 唯一的資料來源,core 不會、也無法用 client 檔案去校驗或覆蓋它。
- **目前不需要對 raw TDB343 做任何 delta 修正**(前提見下方「未能驗證」段)。TDB343 是 3.4.3 core 的官方配套 world DB,其 `skill_tiers` 就是為此 client 版本策劃的權威值。
- **這張表是硬需求,不能留空、不能缺 row。** 有數個消費點對 tier 指標**沒有做 null 檢查**(見 §4),client 端 `SkillRaceClassInfo.db2` 若引用到某個 `SkillTierID` 而 `skill_tiers` 沒有對應 row,玩家學該技能時會 **null 解參考直接 crash**。

三個原始假設的裁定:
- (a) 3.3.5 讀 DBC、3.4 移到 DB 表 → **證實**(§2)。
- (b) TDB343 的 rows 是 3.4.3 client `SkillTiers.db2` 的鏡像 → **證偽**:3.4.3 client 根本沒有 `SkillTiers.db2`(WoD 6.x 已從 client 移除)。這些值是 TrinityCore 在 world DB 端維護的伺服器權威資料(§2、§3)。
- (c) core 會拿 DB 表跟 client 檔案對齊/校驗 → **證偽**:純從 DB 表載入,無任何 cross-check、無 fallback(§1)。

---

## §1. `skill_tiers` 在 core 裡怎麼載入、怎麼被消費

**結論:純 DB 表載入(選項 i)。沒有 `SkillTiersStore` 這種 client DB2/DBC store;DB 表也不是任何 client store 的 hotfix/override。**

### Loader
- `src/server/game/Globals/ObjectMgr.cpp:8761` `ObjectMgr::LoadSkillTiers()`
- SELECT 欄位(`ObjectMgr.cpp:8765-8766`):
  ```
  SELECT ID, Value1..Value16 FROM skill_tiers
  ```
  來源是 `WorldDatabase`(world DB),存進 `_skillTiers`(`ObjectMgr.h:1891`,`std::unordered_map<uint32, SkillTiersEntry>`)。
- 空表行為(`ObjectMgr.cpp:8768-8772`):log error `DB table skill_tiers is empty.` 然後 **直接 return**,沒有任何 client fallback。
- 載入時機:`src/server/game/World/World.cpp:2157` `sObjectMgr->LoadSkillTiers();`

### Struct
- `src/server/game/Globals/ObjectMgr.h:973-979` `struct SkillTiersEntry { uint32 ID; uint32 Value[16]; ... }`,`MAX_SKILL_STEP = 16`(`ObjectMgr.h:971`)。
- `SkillTiersEntry::GetValueForTierIndex(tierIndex)`(`ObjectMgr.cpp:7788-7797`):clamp 到 `MAX_SKILL_STEP-1`,並在該格為 0 時往前找到最後一個非 0 值。
- Getter:`ObjectMgr::GetSkillTier(skillTierId)`(`ObjectMgr.cpp:7782-7786`)—— 查不到回傳 `nullptr`。

### 有沒有 client 端的 SkillTiers store?(關鍵問題)
**沒有。** 全 `src/server/game/DataStores/` 只出現 `SkillTierID`(是別的 store 的欄位),沒有 `SkillTiersStore` / `SkillTiersLoadInfo` / `SkillTiers` 的 db2 meta。
- Client 端真正存在的是 **`SkillRaceClassInfo.db2`**(client store,經 `sDB2Manager.GetSkillRaceClassInfo(...)` 取用),其 struct 有 `int16 SkillTierID` 欄位:
  - `src/server/game/DataStores/DB2Structure.h:3088`
  - `src/server/game/DataStores/DB2LoadInfo.h:4014`
  - hotfix SELECT:`src/server/database/.../HotfixDatabase.cpp:1181`
- 也就是說:**`SkillRaceClassInfo`(client db2)提供 `SkillTierID` → 用這個 id 去 world DB `skill_tiers` 查實際數值。** 兩者是「client 提供索引、world DB 提供數值」的關係,不是 override 疊加,也沒有 cross-check。

### 全部消費點(都走 `GetSkillTier(rcEntry->SkillTierID)`)
- `src/server/game/Spells/SpellEffects.cpp:2337`(EffectSkillStep,**有** null 檢查 `if (!tier) return;`,line 2338-2339)
- `src/server/game/Spells/SpellEffects.cpp:4568`
- `src/server/game/Entities/Player/Player.cpp:2730`(SKILL_RANGE_RANK,**無** null 檢查,直接解參考 line 2731)
- `src/server/game/Entities/Player/Player.cpp:3004`(SKILL_RANGE_RANK,**無** null 檢查,line 3005)
- `src/server/game/Entities/Player/Player.cpp:5304`(`if (tier)` 有守衛)
- `src/server/game/Entities/Player/Player.cpp:5433`(SKILL_RANGE_RANK,**無** null 檢查)
- `src/server/game/Entities/Player/Player.cpp:23644`(SKILL_RANGE_RANK,**無** null 檢查)
- `src/server/game/Entities/Player/Player.cpp:25713`(`if (tier)` 有守衛)
- Reference 驗證器:`ObjectMgr.cpp:8858`(SkillRaceClassInfo 載入時檢查 `GetSkillTier(rcEntry->SkillTierID)` 是否存在)

---

## §2. 3.3.5 對照:當年是 DBC,不是 DB 表(證實假設 a)

- Git 決定性證據:commit **`d454df54d1`**,作者 Shauren,2015-07-05,標題:
  > *Core/DataStores: Moved SkillTiers to database - it no longer exists in dbc form*
- 該 commit 從 core 移除了 client DBC store(`git show d454df54d1` 可見):
  - `DBCStores.h`:刪掉 `extern DBCStorage<SkillTiersEntry> sSkillTiersStore;`
  - `DBCStructure.h`:刪掉 `struct SkillTiersEntry { uint32 ID; uint32 Value[16]; }`(與現行 DB struct 完全同布局)
  - `DBCfmt.h`:刪掉 `SkillTiersfmt = "niiiiiiiiiiiiiiii"`(= 1 個 id + 16 個 int,對應 ID + Value1..16)
  - 同時新增 `ObjectMgr::LoadSkillTiers()` + world DB 表 + 一支 34-row 的 migration(`sql/updates/world/2015_07_05_00_world.sql`)。
- Web 佐證:`SkillTiers.dbc` 與 `SkillRaceClassInfo.dbc` 都列在 TrinityCore 3.3.5a DBC 清單中,且 3.3.5 的 `SkillRaceClassInfo.dbc` 帶有 `skillTierID` 欄位(指向 `SkillTiers.dbc`)。WoD(6.0.1)client 才把 `SkillTiers.dbc` 移除。

**重要脈絡:** 這個 2015 commit 走的是 retail/master 主線(當時進到 6.x/WoD)。`wotlk_classic`(3.4.x)繼承的是 **master 主線的設計(DB 表)**,不是舊 3.3.5 分支的設計(DBC)。所以在 3.4.x 上,`skill_tiers` DB 表是**唯一**來源——3.4.3 client 內並沒有可供讀取或校驗的 `SkillTiers.db2`。

---

## §3. 數值的權威來源

- **這些值是伺服器端權威資料(server-authored,由 TDB 維護),不是 client 檔案的鏡像。** 因為 3.4.3 client 沒有 `SkillTiers.db2` 可對(§2)。
- 但語意上仍受 client 約束:`skill_tiers` 的 **ID 集合必須涵蓋 3.4.3 client `SkillRaceClassInfo.db2` 所引用到的每一個 `SkillTierID`**,否則 §4 的無守衛消費點會 crash。數值(Value1..16)則代表遊戲各技能各 tier 的上限,由 TC 依內容策劃並凍結在 world DB。
- **TDB343 是 3.4.x core 的官方配套 world DB**,它的 `skill_tiers` 就是針對 3.4.3 client 策劃好的權威值。因此「原封匯入 TDB343」等同採用官方權威值。
- core 不把它當成可任意調整的純伺服器 config——它必須與 client `SkillRaceClassInfo.db2` 的引用對齊(ID 面向),數值面向則以 TDB 為準。

---

## §4. Bottom line + WotLK 合理性 sanity check

**「原封匯入 TDB343 的 `skill_tiers` 是否正確?」→ 是。** 且目前**不需要**對 raw TDB343 做任何 delta。理由:
1. 它是 3.4.3 core 的唯一資料來源,core 不做 client 校驗、不做 override 疊加(§1)。
2. 它是官方配套 DB,值已為 3.4.3 client 策劃(§3)。
3. `wotlk_classic` 分支的 `sql/updates/world/wotlk_classic/` 底下**沒有**任何 `skill_tiers` 的修正檔(已 grep 確認),表示連 TC 自己都沒對這張表做 WotLK delta——與「原封沿用」一致。

**為什麼不能省略或裁剪 rows(硬需求):**
Player.cpp 的 SKILL_RANGE_RANK 路徑(`2730-2731`、`3004-3005`、`5433`、`23644` 附近)**直接解參考 `tier` 而無 null 檢查**。只要某 WotLK race/class 的技能在 client `SkillRaceClassInfo.db2` 引用了某 `SkillTierID`,而 `skill_tiers` 缺該 row,學技能時就會 **server crash**。所以要保留完整 58 rows,不要為了「看起來像 Cata 才有」而刪。

**WotLK 合理性(概念層,數值形狀):**
- 專業技能上限的呈現方式是「每個 tier step 一格上限值」,實際生效的是哪一格,取決於玩家學到的 skill step(由 `SpellEffect SkillStep` 的 `damage`/`step` 決定,再 `GetValueForTierIndex(step-1)`)。
- 2015 retail migration 的樣本(可視為同族資料的形狀)顯示典型專業 tier(如 ID 2)= `75,150,225,300,375,450,525,600,700,800,900,1000,...`。WotLK 專業封頂在 Grand Master = **450**(= 第 6 格,step 6)。450 之後的格子(525=Cata、600=MoP...)雖然存在於表中,但 WotLK 內容不會授予那些 step,所以**多出來的高階格子是無害的**(永遠不會被 `GetValueForTierIndex` 取到)。
- 其他常見形狀也合理:武器/防禦類 level-based(不走這張表)、語言/雜項技能封頂 300 或 1(如 ID 21=300、ID 24=1)。
- 因此 58 rows「值看起來 WotLK-appropriate」在形狀上成立:WotLK 需要的低階格子都在,額外的後期格子不影響 WotLK 行為。

---

## 未能從 checkout 驗證的部分(誠實聲明)

1. **無法逐 row 核對 TDB343 的 58 rows 的實際數值**:TDB343 的 `.sql`/dump 不在此 checkout 內(repo 只有 `sql/base` 結構 + `sql/updates`,沒有 TDB full dump)。我驗證的是**機制**與 **3.3.5-vs-3.4 的來源變遷**,以及數值「形狀」的合理性;逐格數值需拿 TDB343 dump 本身核對。
2. **無法枚舉 3.4.3 client `SkillRaceClassInfo.db2` 實際引用了哪些 `SkillTierID`**:client db2 檔不在 checkout 內。因此「58 rows 是否剛好覆蓋所有被引用的 id」無法在此就地證明——但這正是「用官方配套 TDB343 原封匯入」能保證對齊的原因(兩者同屬 3.4.3 配套)。若你手上有 client db2,可用 `SELECT DISTINCT SkillTierID` 對照 `skill_tiers.ID` 做最終落地驗證。

---

## Sources(web)

- [DBC_3_3_5_12340 — SkillTiers (dbdocs.io)](https://dbdocs.io/Kaev/DBC_3_3_5_12340?table=SkillTiers&schema=DBC&view=table_structure)
- [DBCs (3.3.5a) — TrinityCore Wiki](https://trinitycore.info/en/files/DBC/335/DBC)
- [SkillRaceClassInfo.dbc — TrinityCore Wiki](https://trinitycore.info/files/DBC/335/skillraceclassinfo)
- [DB/SkillRaceClassInfo — wowdev.wiki](https://wowdev.wiki/DB/SkillRaceClassInfo)
