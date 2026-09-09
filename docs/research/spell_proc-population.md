# spell_proc 資料表填充與啟動警告處理

**日期**：2026-09-09
**目標**：釐清自架 WotLK Classic（3.4.3）伺服器上 `spell_proc` 世界表該如何正確填充，以及 worldserver 啟動時「needs an entry in `spell_proc`」兩類警告是否需要處理。
**相關筆記**：[[tdb343-data-defects]]、[[wotlk-classic-completion-assessment]]、[[trinitycore-overview]]

> **重要前置**：本 repo（`/Users/shinichi/Works/side-project/TrinityCore`）目前是 **master（retail）分支**，`spell_proc` 有 `ProcFlags2` 欄、範例 spell 是 BFA 的 280270。3.4.3 WotLK Classic 是另一條分支/fork，欄位與 proc 程式碼語意**與此處一致**（3.4.3 亦有完整的 `SpellMgr::LoadSpellProcs` + 自動生成路徑），因此下述 file:line 之邏輯可直接套用；只是實際行號在 3.4.3 tree 可能略有差異。

---

## 結論（先講重點）

1. **這兩類訊息在程式裡都是 `TC_LOG_ERROR("sql.sql", …)`，但實質是「載入期諮詢性提示」，不是啟動失敗**。worldserver 照常啟動、遊戲照常運作。核心對「沒有 `spell_proc` row 的法術」有一條**自動生成路徑**（從 DBC ProcFlags 推導 proc 資料）；兩類警告只是這條路徑「無法/拒絕」自動生成時發出的。
2. **兩類警告嚴重度不同**：
   - **A 類「probably needs an entry」（264 筆）** 多屬良性。發生在「有 ProcFlags 但沒有任何可觸發 aura 效果」時，核心不生成 proc 資料。這些法術往往是（i）由專屬 C++ `AuraScript` 自行處理 proc、或（ii）根本不該用通用 proc 系統、或（iii）是 WotLK 用不到的後期資料。**通常不影響 3.4.3 遊戲行為**。
   - **B 類「required for it to function!」（56 筆）** 才是真正需要注意的。這是核心為了避免「無限 proc 迴圈」而**主動放棄自動生成**（`SPELL_ATTR3_CAN_PROC_FROM_PROCS` 守衛）。這些法術若在 3.4.3 內容中實際會被玩家/生物使用，且**沒有 `spell_proc` row，就完全不會 proc**（功能失效，但不會 crash）。
3. **建議做法（見文末）**：匯入官方 **TDB343 的 `spell_proc`**、接受剩餘警告；**不要**去手填那 ~293 筆。只針對「B 類且確為 WotLK 時代、且遊戲內實測壞掉」的少數法術，逐一手寫 `spell_proc` row。這正是 TC 維護者的實際做法——他們**不會**去清零這些警告。

---

## 一、警告從哪來、程式如何運作

所有相關邏輯集中在 `SpellMgr::LoadSpellProcs()`，`src/server/game/Spells/SpellMgr.cpp:1497-1911`。流程分兩段：

### 1a. 讀 DB 表（`SpellMgr.cpp:1497-1658`）

SQL（`SpellMgr.cpp:1504-1506`）：

```sql
SELECT SpellId, SchoolMask, SpellFamilyName, SpellFamilyMask0, SpellFamilyMask1, SpellFamilyMask2, SpellFamilyMask3,
       ProcFlags, ProcFlags2, SpellTypeMask, SpellPhaseMask, HitMask, AttributesMask, DisableEffectsMask,
       ProcsPerMinute, Chance, Cooldown, Charges FROM spell_proc
```

重點行為：

- **負 `SpellId` = 套用到全等級**（`allRanks`）：`SpellId` 為負時取絕對值，並要求它是該法術的第一階（`SpellMgr.cpp:1517-1541`）。
- **DB row 可留 0，欄位自動繼承 DBC 值**（「take defaults from dbcs」，`SpellMgr.cpp:1573-1581`）：`ProcFlags`、`Charges`、`Chance`、`Cooldown` 若為 0，會分別回填 `spellInfo->ProcFlags / ProcCharges / ProcChance / ProcCooldown`。→ 手寫 row 時只需填「與 DBC 不同或需額外限制」的欄位。
- 一連串驗證（`SpellMgr.cpp:1584-1643`）會對不合理的欄位組合再各自吐 `sql.sql` ERROR（例如設了 `SpellTypeMask` 但 `ProcFlags` 用不到、`SpellPhaseMask` 缺失但 ProcFlags 需要它等）。這些是**填 row 時的檢查**，與本次兩類警告不同。

### 1b. 從 DBC 自動生成缺漏的 proc（`SpellMgr.cpp:1660-1910`）

先建立一張 `isTriggerAura[TOTAL_AURAS]` 表，列舉「哪些 aura 型別本身能觸發 proc」（`SpellMgr.cpp:1679-1727`，例如 `SPELL_AURA_PROC_TRIGGER_SPELL`、`SPELL_AURA_DUMMY`、`SPELL_AURA_MOD_DAMAGE_DONE` …）。接著對每個 `SpellInfo`：

1. **已有 DB row → 跳過**（DB 優先，`SpellMgr.cpp:1761-1762`）。
2. **沒有 ProcFlags → 跳過**（無事可做，`SpellMgr.cpp:1765-1766`）。
3. 掃描各效果，累積 `procSpellTypeMask`；非觸發型 aura 記入 `nonProcMask`（避免自我 proc 掉層，`SpellMgr.cpp:1780-1785`）。

#### A 類警告：`SpellMgr.cpp:1807-1820`

```cpp
if (!procSpellTypeMask) {
    for (SpellEffectInfo const& spellEffectInfo : spellInfo.GetEffects())
        if (spellEffectInfo.IsAura()) {
            TC_LOG_ERROR("sql.sql", "Spell Id {} has DBC ProcFlags 0x{:X} 0x{:X}, but it's of non-proc aura type, "
                "it probably needs an entry in `spell_proc` table to be handled correctly.", …);
            break;
        }
    continue;   // ← 不生成 proc 資料
}
```

**觸發條件**：法術有 `ProcFlags`，但**沒有任何一個效果的 aura 型別落在 `isTriggerAura` 白名單裡**（因此 `procSpellTypeMask == 0`），而至少有一個效果是 aura。結果是**不生成 proc 資料**。這代表核心認為「這個 proc 若真要生效，得靠 DB row 明確描述」——但很多情況下該法術的 proc 其實由專屬 C++ script 處理，或根本不需要通用 proc。**→ 多數良性。**

#### B 類警告：`SpellMgr.cpp:1888-1902`（無限迴圈守衛）

若一路走到生成 `SpellProcEntry`（代表**有**觸發型 aura，本來就會被生成），但滿足以下**全部**條件：

- 帶 `SPELL_ATTR3_CAN_PROC_FROM_PROCS`（可被其他 proc 再觸發）
- 沒有 `SpellFamilyMask` 限制（不限定哪些法術能觸發它）
- `Chance >= 100`、`ProcBasePPM <= 0`、`Cooldown <= 0`、`Charges <= 0`（毫無節流）
- `ProcFlags` 命中一組「造成傷害/治療的動作」旗標
- 且該 aura 會 `TriggerSpell`

則核心判定「這會造成無限 proc 迴圈」，**放棄生成**：

```cpp
TC_LOG_ERROR("sql.sql", "Spell Id {} has SPELL_ATTR3_CAN_PROC_FROM_PROCS attribute and no restriction on what spells "
    "can cause it to proc and no cooldown. This spell can cause infinite proc loops. Proc data for this spell was not "
    "generated, data in `spell_proc` table is required for it to function!", spellInfo.Id);
continue;   // ← 不生成
```

**→ 這類法術若真該在 3.4.3 運作，必須手寫 `spell_proc` row**（加上 `SpellFamilyMask` 限制或 `Cooldown` 之類的節流），否則守衛永遠擋掉自動生成。

### 1c. 生成結果併回主表（`SpellMgr.cpp:1908`）

`mSpellProcMap.merge(generatedSpellProcMap)` —— DB row 已在 map 裡，`merge` 不覆蓋既有鍵，故 **DB row 恆優先於生成值**。

---

## 二、「沒有 entry」在執行期實際代表什麼

runtime 取用點在 `Aura::GetProcEffectMask`，`src/server/game/Spells/Auras/SpellAuras.cpp:1836-1839`：

```cpp
SpellProcEntry const* procEntry = sSpellMgr->GetSpellProcEntry(GetSpellInfo());
// only auras with spell proc entry can trigger proc
if (!procEntry)
    return 0;
```

**沒有 proc entry（DB 或生成皆無）→ 該 aura 的 proc 效果遮罩回 0 → 永遠不 proc**。不會 crash、不會噴 runtime log，只是「這個被動/觸發效果靜默失效」。這就是為什麼：

- **A 類**：若該效果本就不靠通用 proc（有專屬 script 或不需 proc），靜默失效無感 → 良性。
- **B 類**：若該法術真的靠這個 aura 去 proc trigger spell，靜默失效 = 功能壞掉 → 需要 row。

`GetSpellProcEntry` 的查表本體在 `SpellMgr.cpp:503`。

---

## 三、各欄位定義（一手來源）

結構 `struct SpellProcEntry`：`src/server/game/Spells/SpellMgr.h:278-293`。DB schema：`sql/base/dev/world_database.sql:4462-4482`。列舉皆在 `SpellMgr.h`。

| 欄位 | 型別/來源 | 意義 |
|---|---|---|
| `SpellId` | int（負值=全階） | 目標法術 ID；負值套用第一階起所有階（`SpellMgr.cpp:1517-1541`） |
| `SchoolMask` | tinyint（`SPELL_SCHOOL_MASK_*`） | 非 0 時：依「觸發來源法術的 school」做 proc 條件比對（`SpellMgr.h:280`） |
| `SpellFamilyName` | smallint（`SpellFamilyNames`） | 非 0 時：依觸發來源的 SpellFamilyName 比對（`SpellMgr.h:281`） |
| `SpellFamilyMask0-3` | int×4（`flag128`） | 非 0 時：依觸發來源的 SpellClassMask 比對——**這是把 proc 限定在「某些具體法術」上的關鍵**（`SpellMgr.h:282`） |
| `ProcFlags` | int（`enum ProcFlags`，`SpellMgr.h:90-183`） | 非 0 時**覆寫** DBC 的 procFlags；定義「什麼事件」能觸發（近戰/遠程/施法/週期/擊殺…） |
| `ProcFlags2` | int（`enum ProcFlags2`，`SpellMgr.h:187-197`） | 額外事件位（`CAST_SUCCESSFUL`、`TARGET_DIES`、`KNOCKBACK`…）。**注意**：3.4.3/WotLK 分支不一定有此欄，master 才有 |
| `SpellTypeMask` | int（`ProcFlagsSpellType`，`SpellMgr.h:210-217`） | 觸發來源的「傷害/治療/其他」型別：`DAMAGE=1 / HEAL=2 / NO_DMG_HEAL=4` |
| `SpellPhaseMask` | int（`ProcFlagsSpellPhase`，`SpellMgr.h:221-228`） | 在施法哪個階段 proc：`CAST=1 / HIT=2 / FINISH=4` |
| `HitMask` | int（`ProcFlagsHit`，`SpellMgr.h:232-251`） | 依命中結果 proc：`NORMAL / CRITICAL / MISS / DODGE / PARRY / BLOCK / ABSORB / REFLECT …`。0 = 預設（見 `PROC_HIT_NONE` 註解） |
| `AttributesMask` | int（`ProcAttributes`，`SpellMgr.h:255-276`） | 額外行為/條件：`REQ_EXP_OR_HONOR / TRIGGERED_CAN_PROC / REQ_POWER_COST / REQ_SPELLMOD / USE_STACKS_FOR_CHARGES / REDUCE_PROC_60 / CANT_PROC_FROM_ITEM_CAST` |
| `DisableEffectsMask` | int（bitmask） | 位 `1<<effIndex`：停用該效果索引的 proc（避免掉層）。效果須為 aura，否則報錯（`SpellMgr.cpp:1616-1618`） |
| `ProcsPerMinute` | float | 非 0 時 chance = PPM × 武器速度 / 60（`SpellMgr.h:289`）；設了就不看 `Chance` |
| `Chance` | float（百分比） | 非 0 時覆寫 DBC procChance（`SpellMgr.h:290`） |
| `Cooldown` | int（**毫秒**，`SpellMgr.cpp:1560`） | proc 的內部冷卻（ICD）。0 = 繼承 DBC ProcCooldown |
| `Charges` | tinyint | 可 proc 次數上限，0 = 無限（`SpellMgr.h:292`） |

> 官方 wiki 對本表的欄位描述與上述一致（例如 SpellPhaseMask=「bitmask for matching phase of a spellcast on which proc occurs」、AttributesMask=「adds special behaviour to the proc」）。wiki 頁面：<https://trinitycore.atlassian.net/wiki/pages/viewpage.action?pageId=86835220>（Confluence，JS 渲染，需瀏覽器開啟）。

---

## 四、「正確」建立一筆 row 的方法

**沒有純機械式的推導法**——若能純推導，核心的自動生成（§1b）就已經做完了。需要手寫 row 的正是「自動生成做不到/會出錯」的案例，因此 row **本質是逐法術手工作者**，依據是：

1. **鏡射 DBC**：`SpellFamilyName` 與 `SpellFamilyMask0-3` 抄自該法術（或它要限定的觸發來源法術）的 DBC class mask —— 對 B 類尤其重要，因為加上 mask 就解除了「無限制」守衛。
2. **描述想要的觸發條件**：用 `ProcFlags`（事件）＋ `SpellTypeMask`（傷害/治療）＋ `SpellPhaseMask`（階段）＋ `HitMask`（命中結果）拼出「在什麼情況下 proc」。
3. **加節流以解 B 類守衛**：填 `Cooldown`（ICD）或 `ProcsPerMinute`/`Charges`，讓它不再符合「毫無節流」條件。
4. **其餘留 0**：留白欄位會自動繼承 DBC（§1a），不必重抄。

官方 update 檔就是這樣一筆筆手寫的，例如 `sql/updates/world/master/2026_02_28_00_world.sql:5-7`：

```sql
DELETE FROM `spell_proc` WHERE `SpellId` IN (280270);
INSERT INTO `spell_proc` (`SpellId`,…,`SpellPhaseMask`,…) VALUES
(280270,0x00,4,0x00000000,0x00000000,0x00000000,0x00000400,0x0,0x0,0x0,0x1,0x0,0x0,0x0,0,0,0,0); -- Always Angry
```

即：`SpellFamilyName=4`（Druid）＋ `SpellFamilyMask3=0x400` 把 proc 限定到某些德魯伊法術，`SpellPhaseMask=0x1`（CAST），其餘 0 繼承 DBC。標準 `DELETE`＋`INSERT` 慣例，一行一 `-- 註解`。

---

## 五、TDB 如何 seed、以及有無工具

- **完整 seed 在 TDB 世界 dump 本體**（下載得到的那顆 `TDBxxx.sql`），不在 repo 裡。repo 只放**增量 update**：`sql/updates/world/master/*.sql`，全是上述手寫 `DELETE`+`INSERT`。
- 舊時代的 `sql/old/**/*_spell_proc_event.sql` 是**另一張舊表 `spell_proc_event`**（TC 早期 proc 系統），**與現行 `spell_proc` 無關**，勿混用。
- **沒有官方「自動填 spell_proc」工具**。填表就是人工 + 遊戲內回歸測試。核心的自動生成（§1b）已經涵蓋大宗；DB 表只補「自動生成搞不定」的。

---

## 六、針對本專案現況的建議（WotLK Classic 3.4.3）

現況：world DB `spell_proc` 為空；worldserver 噴 320 條不重複警告（56 條 B 類 + 264 條 A 類）。TDB343 的 1086 row 只覆蓋其中 27 條；TDB335 的 848 row 覆蓋 43 條；~261 條兩者皆無。

**推薦 (a) + 針對性補 B 類，明確排除 (b)：**

1. **匯入官方 TDB343 的 `spell_proc`（全 1086 row），接受剩餘 ~293 條警告。** 這些 row 是官方測過的正確資料，且 DB row 恆優先於自動生成（§1c），只有好處沒有壞處。
2. **不要試圖手填那 ~293 條。** 原因：
   - 320 條裡有**大量是後期資料**（DBC 帶了 Cata/MoP…之後的法術）。3.4.3 內容根本不會施放它們 → 靜默失效無感 → 純噪音。
   - A 類（264 條）多由專屬 C++ script 處理或本不需 proc（§1b/§2）→ 良性。
   - 每筆正確 row 都要查 DBC＋設計觸發條件＋**遊戲內實測**，投報比極低。
3. **只補「B 類 ∩ 確為 WotLK 時代玩家/生物實際使用 ∩ 遊戲內實測壞掉」的少數法術。** 判斷法：把 56 條 B 類 SpellId 對照「3.4.3 內玩家職業/副本生物實際會用到的技能」清單，逐一在遊戲裡驗證該 proc 是否真的沒作用；只有真壞的才依 §4 手寫 row（記得加 `SpellFamilyMask` 或 `Cooldown` 以通過守衛）。
4. **維護者的實際做法**就是 3：**不清零警告**，只在有人回報某個 proc 壞掉時，透過 `sql/updates/world/…` 手寫一筆補上。啟動時看到成片的 `sql.sql` proc 警告在 TC 是**常態**，不是安裝錯誤。

> 一句話：**匯入 TDB343 spell_proc，把剩下的警告當背景噪音；只有當你在 3.4.3 遊戲裡實測到某個 proc 真的不作用、且它屬於 B 類時，才逐一手寫 row。**

---

## 附：一手來源索引

- 讀表 SQL 與欄位對應：`src/server/game/Spells/SpellMgr.cpp:1497-1658`
- DBC 預設回填：`src/server/game/Spells/SpellMgr.cpp:1573-1581`
- 自動生成路徑：`src/server/game/Spells/SpellMgr.cpp:1660-1910`
- A 類警告：`src/server/game/Spells/SpellMgr.cpp:1807-1820`
- B 類警告（無限迴圈守衛）：`src/server/game/Spells/SpellMgr.cpp:1888-1902`
- 生成併回主表：`src/server/game/Spells/SpellMgr.cpp:1908`
- 執行期「無 entry 即不 proc」：`src/server/game/Spells/Auras/SpellAuras.cpp:1836-1839`
- `SpellProcEntry` 結構：`src/server/game/Spells/SpellMgr.h:278-293`
- proc 列舉（Flags/SpellType/Phase/Hit/Attributes）：`src/server/game/Spells/SpellMgr.h:90-276`
- DB schema：`sql/base/dev/world_database.sql:4462-4482`
- 手寫 row 範例：`sql/updates/world/master/2026_02_28_00_world.sql:5-7`
- 官方 wiki（spell_proc）：<https://trinitycore.atlassian.net/wiki/pages/viewpage.action?pageId=86835220>
