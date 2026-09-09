# `Xian55/HermesProxy`（`feature/wotlk-classic-v3.4.3`）決策級評估

> 撰寫日期：2026-09-03
> 相關筆記：[zhTW 中文化能做到哪裡](./zhtw-localization.md)、[hotfix DB2 中文化深度評估](./hotfix-db2-localization.md)（本專案 hotfix 機制的原始碼級剖析）、[RaGEZONE 論壇調查](./community-forum-findings.md)（本篇的起點，第 2.1 / 3 節首次發現此專案）、[WotLK Classic 移植路線圖](./wotlk-classic-port-roadmap.md)（Path C 的工程量）、[macOS client 取得與執行](./macos-client-options.md)（client 取得牆與 Apple Silicon 執行路徑）
> 來源限定 primary sources：`gh api` 對 `Xian55/HermesProxy` / `WowLegacyCore/HermesProxy` / `advocaite/HermesProxy-WOTLK` 的 repo metadata、branches、compare、releases、issues、PR、原始碼檔案，以及該分支根目錄的 `wotlk.md`（597 行 / 159,792 bytes，全文取得）與 `README.md`（265 行，全文取得）。全部於 2026-09-03 實測。
> 凡未實際驗證者一律標示「**未驗證**」。本文不背書、不評估安全性，也不記錄任何 game client 下載途徑。
> 未使用瀏覽器自動化。

---

## 0. TL;DR

1. **這個專案比前一篇筆記所描述的還要成熟。** `wotlk.md` 的狀態矩陣有 **99 列子系統**，其中在 TrinityCore 3.3.5a 後端上標 ✅ 的有 **78 列**；戰場、競技場、Dungeon Finder、拍賣場、Master Looter、飛艇/船、冬擁湖、DK 起始任務鏈全部是 ✅。明確 ❌ 的只有 **4 列**（理髮店、行事曆、寵物法術書的 Pet 分頁、以及一個 client 端偶發 DC）。
2. **最重大的新發現：proxy 原生跑在 Apple Silicon 上，而且是 first-class 支援。** CI 的 build matrix 含 `macos`，且 macOS 這一格會 `dotnet publish --runtime osx-arm64` + `osx-x64` 再 `lipo -create` 成 **universal binary**；每一個 release（含這條 3.4.3 分支的 pre-release）都附 `HermesProxy-MacOS-*.zip`。專案並且為了 macOS 修過真實 bug（issue **#29「M1 MacOS: AesGcm not supported」**、PR **#60「macOS AES-GCM fallback」**）。→ **整條 stack 裡唯一需要翻譯層執行的元件只剩 client 本身。**
3. **但它釘死在 `3.4.3.54261`，而且只有這一個 build。** `ClientVersionBuild.cs` 的 WotLK Classic 區段只有一行 `V3_4_3_54261 = 54261`。**沒有 3.4.4，沒有 3.4.5.63697。** 而 3.4.3.54261 的 CDN build config 在 [macOS 筆記](./macos-client-options.md)§3.3 已實測 **HTTP 404**。
4. **後端零改動。** 它連公開營運的 AzerothCore 衍生服（ChromieCraft、tavernwlk）與 Warmane 都當成後端在測 —— 這是「stock 3.3.5a server 即可、不需 patch/module」最強的證據。AzerothCore 那一格 `wotlk.md` 自己註明是 "upstream, no modules"，而且**跑在一台 Mac mini 的 Docker 上**。
5. **結論先講：對「現在就想玩」而言是 no-go，理由只有一個 —— client。** 工程面它是四條路裡最成熟、成本最低的一條；阻斷點 100% 落在 3.4.3.54261 的取得，而那與這個專案無關、也不是它能解的。**如果使用者手上已經有一份 3.4.3.54261 安裝，這條路立刻變成第一名。**

---

## 1. 血統與來源

### 1.1 三個 repo 的關係（`gh api` 實測）

| Repo | 與上游關係 | 定位 | License | ★ | fork | 建立 | 最後 push | 狀態 |
|---|---|---|---|---|---|---|---|---|
| `WowLegacyCore/HermesProxy` | 根 | 原始專案 | GPL-3.0 | 358 | 153 | 2022-01-24 | 2024-07-03 | **archived（唯讀）** |
| **`Xian55/HermesProxy`** | **`parent` = `WowLegacyCore/HermesProxy`（真 GitHub fork）** | 延續 + 新增 3.3.5a 後端與 3.4.3 client | GPL-3.0 | 54 | 20 | 2025-09-20 | **2026-09-02** | **活躍** |
| `advocaite/HermesProxy-WOTLK` | `parent` = **null**（非 fork，是 code snapshot 另開的 repo） | 先做 3.4.3↔3.3.5a 的分支 | GPL-3.0 | 43 | 17 | 2026-04-03 | 2026-05-20 | 停滯 3.5 個月 |

### 1.2 上游做了什麼、fork 加了什麼

上游 `WowLegacyCore/HermesProxy` 的 README **支援表全文只有兩列**：

```
| Modern Versions | Legacy Versions |
| 1.14.0          | 1.12.1          |
| 2.5.2           | 2.4.3           |
```

repo description 也寫得很清楚：`"A World of Warcraft connection Proxy for VMaNGOS & CMaNGOS."` —— **上游只做 Classic Era ↔ Vanilla、TBC Classic ↔ TBC，後端只認 MaNGOS 系，完全沒有 3.x 這一半。**

`Xian55/HermesProxy` 的 description 是 `"... for VMaNGOS & CMaNGOS & TrinityCore."`，README 支援表多出第三列 `3.4.3 | WotLK Classic | 51505 - 54261 | Experimental`，legacy 表多出 `3.3.5a | WotLK | 12340 | TrinityCore, AzerothCore, CMaNGOS`。

`wotlk.md` 的 "Done so far" 第一列直接寫出這件事的起點：

> `| 2026-04-22 | Phase 0 — un-gate V3_3_5a legacy backend | PR #45 |`

**也就是說：「3.3.5a 當後端」這件事本身就是 `Xian55` 加的，不是上游能力。** 這是 fork 的核心增量，不是微調。

**是延續還是分歧？—— 是延續，而且是唯一活著的延續。** 證據：(a) 它是真 fork（`parent` 欄位），(b) `WowLegacyCore/HermesProxy master ... Xian55:master` compare 為 **ahead 243 / behind 0**，也就是純粹疊加、沒有分岔，(c) 上游 archived、無法再接受 PR。至於 `advocaite/HermesProxy-WOTLK`，`wotlk.md` 有一節 **"Fork copy-cat policy"** 明確定義了對它的態度：

> "When cherry-picking from `HermesProxy-WOTLK`, take only V3_4_3-specific fixes. Do **not** regress the upstream perf/trim posture. The fork's snapshot stripped: `Directory.Packages.props` … ~384 lines of `BnetTcpSession.cs` pooled-buffer perf work … `PublishTrimmed=true` + trimmer root config. These stay in upstream."

→ **`advocaite` 先跑出 3.4.3 的概念驗證，`Xian55` 把它當參考實作重做在維護良好的 codebase 上。** 現在領先的是 `Xian55`（338 commits vs 對方停在 2026-05-20）。

---

## 2. 目前的實際能力 —— 核心問題

以下 **99 列**狀態矩陣**逐字取自** `wotlk.md` 的 `| Subsystem | TC 3.3.5a | cMangos 3.3.5a | AzerothCore 3.3.5a | Notes |` 表（Notes 欄過長，本文省略，僅在下方摘引關鍵句）。文件自述日期為 **2026-09-03**。

### 2.1 文件對狀態標記的自我定義（原文）

文件沒有給正式 legend，但兩處把 ❓ 的語意講得很死，這正是任務要的「implemented vs verified」區分：

> "**2026-09-01 — 15 never-tested subsystems added at the bottom of the table.** … They are `❓` on all three backends because **nobody has ever driven them, not because they are known broken** — most are already wired end-to-end and simply need a playtest. Three (barber shop, GM ticket, calendar) are genuinely unbridged and marked `❌`."

> "**The AzerothCore column is not re-ticked for rows we fixed afterwards** — kasper's pass predates those merges, so those cells read ⚠️ until someone re-runs them."

> "AzerothCore column added 2026-08-24. **It is marked ❓ rather than assumed-equal-to-TC: only the rows actually exercised there are ticked.**"

**→ 讀法：✅ = 有人實際玩過並通過；⚠️ = 部分／有已知缺陷；❌ = 已知未橋接；❓ = 沒人測過，不等於壞掉。** 這份文件把「已實作」與「已驗證」分得很乾淨，是可信度的強訊號。

還有一條方法論警告值得記：

> "**a `0u` entry in the modern opcode enum is not by itself evidence of a gap.** The enum carries dead legacy-named aliases next to the live modern names … Always confirm against the `[PacketHandler]` registration before filing a gap."

### 2.2 完整狀態矩陣（99 列，忠實重現）

| Subsystem | TC 3.3.5a | cMangos 3.3.5a | AzerothCore 3.3.5a |
|---|---|---|---|
| Auth + char-select | ✅ | ✅ | ✅ |
| World-enter + walk + camera | ✅ | ✅ | ✅ |
| New-char first login (post-cinematic movement) | ✅ | ❓ | ✅ |
| Player render (incl. equipped items) | ✅ | ✅ | ✅ |
| Combat — auto-attack | ✅ | ✅ | ✅ |
| Player Armor + magical resistances | ✅ | ❓ | ✅ |
| Combat — special abilities | ✅ | ❌ | ✅ |
| Channel spells (cast bar / kneel anim / ESC unblock) | ✅ | ❓ | ✅ |
| Channel spells (loop animation) | ✅ | ❓ | ✅ |
| Spell-failure error text (e.g. NotShapeshift) | ✅ | ❓ | ✅ |
| Flying projectiles (arrows / fireball / missiles) | ✅ | ✅ | ✅ |
| Death Knight character create | ✅ | ❓ | ✅ |
| Death Knight runes + runic power | ✅ | ❓ | ✅ |
| **Death Knight starter quest chain (full)** | ✅ | ❓ | ✅ |
| Battle Shout / self-aura | ✅ | ✅ | ✅ |
| Shapeshift / form cancel (Bear Form verified) | ✅ | ❓ | ✅ |
| Action bar — main bar populated on login | ✅ | ✅ | ✅ |
| Action bar — drag spell / macro / item to any bar | ✅ | ❓ | ✅ |
| Action bar — Always Show Action Bars persistence | ✅ | ✅ | ✅ |
| Action bar — Bar 2/3/4/5 visibility persistence | ✅ | ❓ | ✅ |
| Sporadic V3_4_3 client `CMSG_LOG_DISCONNECT(reason=7)` | **❌** | ❓ | ❓ |
| Inventory equip / unequip / drag-drop | ✅ | ✅ | ✅ |
| Gem socketing — apply gem, socket bonus, prismatic | ❓ | ❓ | ✅ |
| Inventory — "on use" items | ✅ | ❌ | ✅ |
| Vendor — buy | ✅ | ✅ | ✅ |
| Vendor — sell | ✅ | ❌ | ✅ |
| Professions — secondary train + skinning use | ✅ | ❓ | ✅ |
| Looting (items + money) | ✅ | ❓ | ✅ |
| Group loot — Need / Greed / Pass + roll numbers | ❓ | ❓ | ✅ |
| Quest log + tracker | ✅ | ⚠️ | ✅ |
| Quest pickup + completion | ✅ | ✅ | ✅ |
| Quest map markers (mini-map + world-map dots) | ✅ | ✅ | ✅ |
| Quest area highlight on world map (POI blob mesh) | ✅ | ❓ | ✅ |
| Gossip POI direction marker | ✅ | ❓ | ✅ |
| Hotfix data | ✅ | ✅ | ✅ |
| Static GameObjects | ✅ | ✅ | ✅ |
| Quest-objective GameObject interaction | ✅ | ❓ | ✅ |
| Spell-click NPCs ("right-click to ride") | ✅ | ❓ | ✅ |
| Vehicles — mount + dismount + seat-change + action bar | ✅ | ❓ | ✅ |
| Trajectory casts (cannons / arc projectiles) | ✅ | ❓ | ✅ |
| Active-mover handover (vehicle / charm / Eye of Acherus) | ✅ | ❓ | ✅ |
| Flightmaster — discover node + Taxi window + fly route | ✅ | ❓ | ✅ |
| Auras / aura ticks | ✅ | ✅ | ✅ |
| Spellbook (incl. trainer learning) | ✅ | ✅ | ✅ |
| Pet — summon, portrait, attack/follow/stay | ✅ | ❓ | ✅ |
| Pet — spellbook + action bar | ⚠️ | ❓ | ✅ |
| Pet — character-sheet stats | ✅ | ❓ | ✅ |
| Pet — spellbook "Pet" tab in player UI | **❌** | ❓ | ✅ |
| Talent panel — unspent point counter + tree populate | ✅ | ✅ | ✅ |
| Talent panel — dual-spec switch | ✅ | ✅ | ✅ |
| Pet talents | ✅ | ❓ | ✅ |
| Glyphs — display + slot unlock | ✅ | ❓ | ✅ |
| Glyphs — slot unlock at L15/30/50/70/80 mid-session | ✅ | ❓ | ✅ |
| Glyphs — apply (`CMSG_USE_ITEM`) | ✅ | ❓ | ✅ |
| Glyphs — remove (`CMSG_REMOVE_GLYPH`) | ✅ | ❓ | ✅ |
| Glyphs — dual-spec swap UnitData refresh | ✅ | ❓ | ✅ |
| Chat (`/say`, `/emote`) | ✅ | ✅ | ✅ |
| Party / raid (form, convert) | ✅ | ✅ | ✅ |
| Party chat / raid chat / raid warning | ✅ | ✅ | ✅ |
| Raid promote-to-assistant | ✅ | ❓ | ✅ |
| Raid kick (single member) | ❓ | ❌ | ✅ |
| Trade (between players) | ✅ | ✅ | ✅ |
| Char-list — auto-select newly created character | ✅ | ❓ | ✅ |
| Mail — open + inbox + attachments + COD + delete | ✅ | ❓ | ✅ |
| Achievement panel — earned + criteria progress | ✅ | ❓ | ✅ |
| Account heirloom panel — collection listing | ✅ | ❓ | ✅ |
| Toy Box — learn from bags + use from journal | ❓ | ❓ | ✅ |
| Spellbook fresh-login animations (`InitialLogin` flag) | ✅ | ✅ | ✅ |
| Pet spellbook tab + chat spam on login | ✅ | ✅ | ✅ |
| Flat / Pct spell modifier array shape | ⚠️ | ⚠️ | ✅ |
| repair | ✅ | ❓ | ✅ |
| Spirit healer — resurrect with sickness (gossip) | ✅ | ❓ | ✅ |
| Innkeeper — make this inn your home | ❓ | ❓ | ✅ |
| **Battlegrounds — list, queue, port, scoreboard** | ✅ | ❓ | ✅ |
| **Wintergrasp — join, capture, vehicles** | ❓ | ❓ | ✅ |
| Who / friends / ignore | ❓ | ❓ | ✅ |
| **Arena — skirmish queue + enter (2v2 / 3v3 / 5v5)** | ✅ | ❓ | ✅ |
| Arena — team assignment (friend vs foe) | ✅ | ❓ | ❓ |
| Titles — character-panel dropdown | ✅ | ❓ | ✅ |
| Master Looter — candidate list + assignment | ❓ | ❓ | ✅ |
| **Dungeon Finder — queue, proposal, enter, teleport, leave** | ✅ | ❓ | ✅ |
| **Auction House — open, search, bid, buyout, post, cancel** | ✅ | ❓ | ✅ |
| Transports — elevators, trams (GO type 11) | ✅ | ✅ | ✅ |
| Transports — zeppelins, boats (GO type 15 / MO_TRANSPORT) | ✅ | ❌ | ✅ |
| Ready check (raid) | ✅ | ❓ | ⚠️ |
| Raid target icons (skull / cross / …) | ✅ | ❓ | ⚠️ |
| Respec — talent wipe at trainer | ✅ | ❓ | ✅ |
| Reputation panel — standings, at-war, watched faction | ✅ | ❓ | ⚠️ |
| Currency / honor panel | ⚠️ | ❓ | ✅ |
| Tutorials (popup tips + reset) | ❓ | ❓ | ❓ |
| Send mail (compose + attach + postage) | ✅ | ❓ | ⚠️ |
| Feed pet / happiness | ❓ | ❓ | ❓ |
| Fishing — cast + bobber + catch | ❓ | ❓ | ❓ |
| Pick lock / open locked container | ❓ | ❓ | ❓ |
| **Barber shop** | **❌** | **❌** | **❌** |
| GM ticket / support UI | ⚠️ | ❓ | ⚠️ |
| **Calendar** | **❌** | **❌** | **❌** |
| Instance lockouts + heroic difficulty toggle | ✅ | ❓ | ⚠️ |
| Stable — revive dead pet | ⚠️ | ❓ | ⚠️ |

**統計（我自己數的，不是文件自述）**：全表 **99 列**。TC 3.3.5a 欄 —— **✅ 78、⚠️ 5、❌ 4、❓ 12**。

### 2.3 依任務指定的子系統逐項回答

| 子系統 | 現況（TC 後端） | 依據 |
|---|---|---|
| **Login / realm list / character list** | ✅ 全通 | `Auth + char-select` ✅ 三後端；`Char-list — auto-select newly created character` ✅ |
| **進入世界** | ✅（含新角色過場動畫後可動，2026-05-03 修好）。**唯一保留的 caveat**：「skipping the cinematic too early can still disconnect」 | `New-char first login` ✅ + Notes |
| **移動** | ✅ `World-enter + walk + camera`；載具、飛行點、電梯/地鐵/飛艇/船皆 ✅ | 多列 |
| **戰鬥** | ✅ 自動攻擊、特殊技能、引導法術、飛行投射物、護甲/抗性 | 5 列 ✅ |
| **施法** | ✅ 但**職業技能仍有已知 pattern 級缺口**，見 2.4 | `Class ability gaps` 節 |
| **任務** | ✅ 接取/完成/任務日誌/小地圖與世界地圖標記/POI 區塊/守衛指路；**DK 完整起始任務鏈 ✅** | 6 列 |
| **拾取 Loot** | ✅ 物品+金錢；Need/Greed/Pass 與 Master Looter 在 **AzerothCore 已驗證 ✅**，TC 欄仍 ❓ | 3 列 |
| **商人 Vendor** | ✅ 買 + 賣（TC/AC）；cMaNGOS 賣東西 ❌ | 2 列 |
| **郵件 Mail** | ✅ 收信、附件、COD、刪除、寄件（2026-09-02 修好信件開啟） | 2 列 |
| **拍賣場 AH** | ✅ **end-to-end，TC 與 AzerothCore 皆驗證**（開啟/搜尋/分類過濾/出價/一口價/上架/取消） | 2026-05-30 + 2026-08-27 條目 |
| **公會 Guild** | **矩陣中沒有這一列。** 有 `GuildDefines.cs`、`CMSG_ACCEPT_GUILD_INVITE` 等 opcode 存在，但 `wotlk.md` 從未列出公會狀態 → **未驗證，且文件本身沒有涵蓋** | 矩陣缺席 |
| **隊伍 / 團隊** | ✅ 組隊、轉團隊、隊伍/團隊頻道、團隊警告、升助理、準備確認、團隊標記；`Raid kick` TC ❓ / cMaNGOS ❌ / AC ✅ | 7 列 |
| **副本 Instances** | ✅ 副本鎖定 + 英雄難度切換（TC ✅ / AC ⚠️）；`SMSG_INSTANCE_DIFFICULTY` 曾無 handler，2026-09-02 由 #223/#231 處理 | 1 列 + Open issues |
| **戰場 Battlegrounds** | ✅ 列表、排隊、傳送、**計分板**；冬擁湖在 AC ✅；競技場 skirmish 2v2/3v3/5v5 ✅ | 4 列 |
| **聊天 Chat** | ✅ `/say`、`/emote`、隊伍/團隊頻道、團隊警告 | 3 列 |
| **Addons** | **矩陣中沒有 addon 專屬列。** 全文只有兩處提到 addon：一處是把 `FasterLooting` 當成 bug 重現工具（已 obsolete），一處是拍賣搜尋封包裡的 `AddOnInfo` 欄位。→ **addon 相容性完全未被記錄，視為未驗證。**（推論：addon 是純 client 端 Lua，proxy 不介入，但 addon 依賴的資料若來自 proxy 未橋接的封包就會失效 —— 例：Quest Helper 的點擊導航就是這種缺口，見下。） | 全文 grep |

### 2.4 開發者自己列的「還卡著」（Open issues 節，逐項）

**A. 職業技能 pattern（承接 `advocaite/HermesProxy-WOTLK#14`，`kasperfriend` 於 2026-04-18 提交的全職業測試矩陣）** —— 文件把散落症狀歸納成 8 個 pattern，並附上重要但書：

> "**These results predate our 2026-04-29 → 2026-05-03 work; re-verify against current HEAD before treating each as open.**"

| Pattern | 症狀 | 現況 |
|---|---|---|
| A | 自身施放的驅散/淨化被拒，錯誤訊息卻是「can't mount here」（5+ 職業） | **Paladin Purify 已解（2026-05-16）**；其餘（Cleanse / Dispel Magic / Cure Disease / Purge / Cleanse Spirit / Cure Toxins / Remove Curse / Cure Poison）**待複驗** |
| B | 地面指定 AOE 被拒，訊息「item is not ready yet」（4+ 職業） | **DK Death and Decay 已解**；但「DnD 的地面漩渦視覺不 render」是**新開的子問題**；其餘（Mass Dispel / Lightwell / Hurricane / Force of Nature / Flamestrike / Blizzard / Shadowfury）**待複驗** |
| C | 連擊點終結技被拒「requires combo points」 | **已解 2026-05-16**。根因很有代表性：V3_4_3 把 `ComboTarget` descriptor 從 `ActivePlayerData` 搬到 `UnitData` |
| D | 熊形態怒氣技能被拒「not enough rage」 | **已解**（`DisplayPower` 欄寬 `UInt32`→`UInt8`） |
| E | 變形／取消變形壞掉（角色卡在形態裡） | **Bear Form 已解 2026-05-06**；其餘形態 / Stealth / Shadowform / Metamorphosis / Ghost Wolf **待複驗** |
| F | 寵物／召喚物法術面板版面壞掉（功能可用、UI 壞） | 仍列為 open |
| G | 職業級阻斷 | **Hunter 進世界必 DC → 已解 2026-05-03**（根因是 `WriteCreateItemData` 每個 Item descriptor 多寫 7 bytes）；**DK 無法建角 → 已解 2026-05-03/05**；**Warlock 把靈魂碎片放進背包會 DC → 仍 open** |
| H | 雜項 | Slow Fall 已解；**聖騎士 Greater Blessings「你已經學過該法術」、薩滿武器附魔「item is already enchanted」、Holy Wrath / Holy Shock 有動畫但無傷害/治療 → 仍 open** |

**B. 架構天花板 —— 這一項最能說明 proxy 路線的結構性成本**（復活虛弱不顯示紅字 / `*75%`，2026-05-31 起未解）：

> "The native 3.4.3 *server* computes **derived display fields that a legacy 3.3.5a server never populates** (`ModDamageDonePercent` is 0.25 native versus 1.0 through the proxy, and native Attack Power goes negative), and the red text keys off those. … Closing it properly means **synthesizing the derived fields** from the aura's `MOD_PERCENT_STAT` / `MOD_DAMAGE_PERCENT_DONE` effects — a real feature, deferred."

**→ 現代 client 期待的某些欄位，3.3.5a 伺服器根本不計算。翻譯層必須自己「合成」。這類缺口沒有上限，是 Path D 永遠會有的長尾。**

**C. 其他仍 open**

- **仍無 handler 的封包**：`SMSG_LEARNED_DANCE_MOVES`（`/dance` 變化）。（原本五個，2026-09-01 複查後 `SMSG_THREAT_UPDATE` / `SMSG_LOAD_EQUIPMENT_SET` / `SMSG_UPDATE_TALENT_DATA` 已補上 handler。）
- **2306 筆 `ItemSparse` 資料列被丟棄** —— `sbyte→short` 欄寬 loader bug，「Raid-tier WotLK gear with stats > 127 is silently dropped from the modern hotfix slot」。目前靠 legacy `SMSG_ITEM_QUERY_SINGLE_RESPONSE` 這條舊路徑補救 tooltip。
- **Flat/Pct spell modifier 陣列形狀** —— 原生 TC 3.4.3 一律送 40 列（~204 B），proxy 只送有值的（~14 B）。文件誠實寫：「Whether the V3_4_3 client requires the canonical shape is **unknown, and the symptom is speculative** — no user-visible failure has been tied to it.」
- **隨機附魔（"of the …"）後綴屬性不顯示在 tooltip** —— 純外觀，屬性有正確套用到角色面板。
- **預設 Quest Helper 的「點任務追蹤器自動開地圖」不作用** —— 根因不在 proxy：「TC 3.3.5 `quest_template` has these zeroed for most quests」（`POIContinent`/`POIx`/`POIy` 在後端就是 0）。**這是 addon/UI 體驗會踩到的第一個坑。**
- **`PlayerBusy` 交易拒絕會把 client 卡死，非重登不能再交易**（issue #228，2026-09-02 open）。
- **客服視窗無限轉圈**（issue #230，2026-09-02 open）—— 但文件註明 "native does the same"，也就是**原生 3.4.3 伺服器也一樣**，不是 proxy 的錯。

### 2.5 cMaNGOS 是明顯落後的後端

文件自己說：

> "**cMangos** works for world-enter and most gameplay but is no longer routinely tested; its column in the matrix below is mostly `❓` for that reason."

cMaNGOS 專屬 ❌：特殊技能（"invalid target"）、商人賣出（格子變永久灰色）、可使用物品不觸發、團隊踢人會解散整團、飛艇/船完全不 render（一場 session 記錄 **16 次 `Skipping MOTransport` vs 2 次 `Forwarding`**）。

**→ 使用者若走這條路，後端請用 TrinityCore 3.3.5a 或 AzerothCore，不要用 cMaNGOS。**

---

## 3. 精確的 client build

### 3.1 原始碼的答案：只有 `3.4.3.54261`

`Framework/Constants/ClientVersionBuild.cs`（分支 `feature/wotlk-classic-v3.4.3`）的 WotLK Classic 區段**全文就是兩行**：

```csharp
    // WotLK Classic
    V3_4_3_54261 = 54261,
```

同一個 enum 裡 1.14.x 有 **26 個 build**、2.5.x 有 **28 個 build**（`V2_5_1_38598` … `V2_5_3_42598`）。**WotLK Classic 只有一個。**

README 的支援表寫 `Build Range 51505 - 54261`，但 enum 裡沒有 51505 這個值 —— 合理解讀是「這個範圍的 client 都被接受，但實作只針對 54261 驗證過」。**未驗證：51505 是否真的能跑。**

`appsettings.json` 的 `ClientOptions:ClientBuild` **預設值是 `V2_5_2_40892`（TBC Classic）**，允許值列表為 `V1_14_0_40618`、`V1_14_1_41794`、`V1_14_2_42597`、`V2_5_2_40892`、`V2_5_3_42328`、`V3_4_3_54261 (experimental)`。→ **要跑 WotLK 必須手動改 config，這不是預設路徑。**

`LegacyServerOptions:Build` 允許值：`auto`、`V1_12_1_5875`、`V2_4_3_8606`、`V3_3_5a_12340`。

### 3.2 能不能指向 `3.4.5.63697`？—— 不能，而且不是加一行 enum 就好

**不能。** 理由是架構性的，`wotlk.md` 自己解釋得最清楚：

| Client | `ObjectUpdateBuilder` LOC | Update format |
|---|---|---|
| V1_14_1_40688（Classic Era） | ~1,720 | Legacy DWORD-indexed UpdateFields + update-mask bitmap |
| V2_5_3_41750（TBC Classic） | ~1,720 | 同上 |
| **V3_4_3_54261（WotLK Classic）** | **~3,419** | **Descriptor-based change-set system（matches retail Legion+）** |

> "Blizzard modernized the object-update protocol for WotLK Classic to match current retail … Each object type has a **hand-written** `WriteCreate{Object,Unit,Player,ActivePlayer,Item,…}Data` that walks a hierarchical tree of fields, emitting nested bit-masks … **Off-by-one errors in any `WriteBits(mask, N)` corrupt the entire object stream**, so capture-based byte-level validation … is the only reliable check."

也就是說：整棵 descriptor 欄位樹是**手寫**的、綁死在 54261 這個 build 的欄位順序上。3.4.4 / 3.4.5 只要有任何欄位增刪或位移，就要重新逐 bit 對過。程式碼裡到處是 `ModernVersion.Build == V3_4_3_54261` 的 version gate（例：拍賣場那六層修正「All fixes version-gated on `ModernVersion.Build == V3_4_3_54261`」）。

**→ 指向 3.4.5 = 重做一次 3,419 行的 descriptor 對齊 + 整張 opcode 表 + 18 張 hotfix CSV 重新產生。這是幾個月的工作，不是設定值。**（本段為工程量判斷，**推估未驗證**；但 enum 只有一個 build、descriptor 手寫、version gate 遍布，這三項都是實測。）

**這件事對使用者的意義**：[路線圖筆記](./wotlk-classic-port-roadmap.md)§1.4 已確認 WotLK Classic 的最終 build 是 3.4.5.63697、CDN 已 404。HermesProxy 針對的 **3.4.3.54261 同樣 404**（[macOS 筆記](./macos-client-options.md)§3.3 實測）。**兩個 build 都拿不到，而 HermesProxy 只認其中一個。**

---

## 4. 後端需求

### 4.1 支援哪些 core（README + `wotlk.md` 實際測試矩陣）

README legacy 表：`3.3.5a | WotLK | 12340 | TrinityCore, AzerothCore, CMaNGOS`。
`wotlk.md` 開宗明義：**"TrinityCore 3.3.5a is the primary backend and AzerothCore is the secondary."**

`wotlk.md` 的 Backend strategy 表列出**九個實際在用的後端**：

| Backend | 位址 | 備註（原文摘引） |
|---|---|---|
| **TrinityCore 3.3.5a**（local repack）— primary | `127.0.0.1:3724` | 有 GM 帳號，`.additem` / `.gm` 方便迭代 |
| **AzerothCore 3.3.5a** — secondary | `192.168.88.44:3724` | **"(Mac mini Docker, upstream, no modules)"** |
| AzerothCore + `mod-playerbots` | `:3725` | bot 是真的 `Player` |
| TrinityCore + NPCBots（patched build） | `:3724` | bot 是 `Creature` |
| CMaNGOS 3.3.5a | `192.168.88.55:3726` | 已不常態測試 |
| **ChromieCraft**（public, AC-derived） | `logon.chromiecraft.com:3724` | read-only |
| **tavernwlk.top**（public, AC-derived） | `login.tavernwlk.top:3724` | read-only |
| **Warmane**（custom core + Warden） | `logon.warmane.com:3724` | — |
| Wrathion native V3_4_3.23121 | — | **明確標註 "not a backend"**，是 wire-format oracle |

### 4.2 需要 patch / module 嗎？—— 不需要

**三項獨立證據：**

1. AzerothCore 那一列自己註明 **"upstream, no modules"**。
2. 它把**三個外部公開伺服器**（ChromieCraft、tavernwlk、Warmane）當後端在測 —— 這些伺服器不可能為 HermesProxy 打 patch。
3. 架構上 proxy 扮演的是一個普通 3.3.5a client：README 的四元件描述裡，`AuthClient` 「will in turn login to the remote authentication server (realmd)」、`WorldClient`「communicates with the remote world server」。

**bot 是唯一的例外**：`Trinity-Bots` 需要 patched TC build，`mod-playerbots` 需要 AzerothCore 裝模組 —— 但那是**開發測試需求，不是遊玩需求**。

### 4.3 設定需求

**後端側**：什麼都不用改。用你平常 `SET REALMLIST` 會填的位址與 port（`LegacyServerOptions:Address` / `:Port`，預設 `127.0.0.1:3724`），用你平常的帳號密碼登入（SRP6 由 proxy 的 `AuthClient` 代跑）。

**client 側**（README "Usage Instructions"）：
- 改 `WTF/Config.wtf`：`SET portal "127.0.0.1"`。
- 需要 **Arctium Launcher**，WotLK 用 `--staticseed --version=Classic`（README 註明「Arctium reuses the same flag as TBC」）。
  → 這與 [macOS 筆記](./macos-client-options.md)§3.6 記錄的「現代架構 client 需要 custom launcher」一致；該專案現已更名為 `Burralis/Game-Launcher`。
- 遊戲內設定：`System → Network → Optimize Network for Speed` **必須開啟**，否則會週期性被踢。

**TLS**：預設內嵌 TrinityCore 開發憑證（`CN=*.*`）。README 明講「**Leave the default alone unless you know you need something else.**」Arctium 啟動的 client 直接跳過憑證驗證。

**DB2 / hotfix 資料**：**使用者不需要自己從 client 抽 DB2。** proxy 內建 18 張 V3_4_3 hotfix CSV（repo 內 `HermesProxy/CSV/Hotfix/`，由 `wago.tools` 以 `?build=3.4.3.54261` 產生，約 70 萬筆記錄），在 `.csproj` 裡以 `<Content Include="CSV\Hotfix\*.*">` 隨 build 複製。**這正是 HermesProxy 相對於 Path C 最大的成本優勢 —— 不用重建 world DB，也不用跑 extractor。**

---

## 5. Runtime 與 macOS / Apple Silicon 可行性 ★ 本篇最重要的一節

### 5.1 Target framework：`.NET 10`

`Directory.Packages.props`（分支根目錄）：

```xml
<PropertyGroup>
  <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  <TargetFramework>net10.0</TargetFramework>
  <Nullable>enable</Nullable>
  <WarningsAsErrors>nullable</WarningsAsErrors>
</PropertyGroup>
```

CI 的 `DOTNET_VERSION` 是 `10.0.x` 加一個 `11.0.100-preview.3.26207.106` 的 pin（給 `feature/dotnet11` 分支用）。相依套件全部是跨平台 NuGet：`Microsoft.Extensions.Hosting`、`Serilog`、`Google.Protobuf`、`BouncyCastle.Cryptography`、`Sep`。**沒有任何 Windows-only 套件（沒有 WinForms、WPF、`Microsoft.Win32.*`）。**

### 5.2 macOS arm64 是 CI 一等公民（實測 workflow 原文）

`.github/workflows/Build_Proxy.yml` 與 `Release.yml` 的 build matrix：`os: ['windows', 'ubuntu', 'macos']`，而 macOS 那一格是**專門處理過的**：

```yaml
- name: Publish (MacOS x86_64 and arm64)
  if: matrix.os == 'macos'
  run: |
    dotnet publish HermesProxy --configuration Release --runtime osx-arm64 -p:UsePublishBuildSettings=true
    dotnet publish HermesProxy --configuration Release --runtime osx-x64  -p:UsePublishBuildSettings=true
    lipo ./HermesProxy/bin/Release/osx-arm64/publish/HermesProxy \
         ./HermesProxy/bin/Release/osx-x64/publish/HermesProxy \
         -create -output ./HermesProxy/bin/Release/osx-x64/publish/HermesProxy_universal
```

→ **它產出的是 macOS universal binary（arm64 + x64 用 `lipo` 合併）。** 加上 `.csproj` 的 `SelfContained=true` + `PublishSingleFile=true` + `PublishTrimmed=true` —— **使用者不需要安裝 .NET SDK 或 runtime，下載解壓就能跑，且在 Apple Silicon 上是原生 arm64 執行。**

**這條 3.4.3 分支自己就有 Mac 產物**（pre-release `v4.3.0-feature-wotlk-classic-v3-4-3-e495721`，2026-09-02）：

| asset | 大小 | 下載數 |
|---|---|---|
| `HermesProxy-MacOS-*.zip` | 28,968,908 bytes | 0 |
| `HermesProxy-Ubuntu-arm64-*.tar.gz` | 18,458,459 bytes | 0 |
| `HermesProxy-Windows-*.zip` | 18,816,319 bytes | 2 |

### 5.3 macOS 使用不是推論 —— 有實際的 bug 與修正 ★

**這一點必須說清楚：任務要求區分「從 framework 推論」與「有人實測過」。答案是後者，但要分兩層。**

**已驗證（有真實 issue / PR）：proxy 本體在 Apple Silicon 上跑得起來，而且踩過並修好了 Apple 平台專屬的 bug。**

| # | 標題 | 開啟者 | 日期 | 狀態 |
|---|---|---|---|---|
| **#29** | **"M1 MacOS: AesGcm not supported (OpenSSL fallback needed)"** | Xian55 | 2026-04-06 | closed |
| **#60** | "fix(crypto): macOS AES-GCM fallback + Framework.Cryptography rewrite" | Xian55 | 2026-05-08 | closed |
| #64 | "[macOS] Game crash on login loading screen" | trickscode | 2026-05-13 | closed |
| #75 | "[macos] Hermes crash when quitting game without waiting 20 sec" | b4bass | 2026-05-17 | closed |
| #87 | "Dispell macos crash" | HgGamer | 2026-05-24 | closed |

issue **#29** 原文：

> "On Apple Silicon (M1/M2) Macs, AES-GCM encryption fails despite OpenSSL 3 being installed. Requires manually setting `DYLD_LIBRARY_PATH=/opt/homebrew/opt/openssl@3/lib` as a workaround."

而 `Directory.Packages.props` 裡 BouncyCastle 的註解，就是這個問題的最終修法（**原始碼層級的 macOS 一等公民證據**）：

> "BouncyCastle — two consumers: … 2. **AES-GCM fallback in `Framework.Cryptography.WorldCrypt` for platforms where `System.Security.Cryptography.AesGcm` rejects the 12-byte (96-bit) tag the WoW protocol uses (notably macOS / Apple's CommonCrypto backend).**"

另一條同樣重要的原始碼證據，在 `HermesProxy.csproj` 裡：

> "`_WINDOWS` gates the Windows-only console/CTRL-handler blocks in `Program.cs`. **APPEND to `$(DefineConstants)` — never assign.** A plain assignment here silently discarded the SDK-provided TRACE define, so every `Trace.Assert` compiled away on Windows **while staying live (and process-fatal) on macOS/Linux**. That divergence hid the opcode-0 abort reported in **#111** from every Windows contributor for as long as the line existed."

→ **維護者不只讓它能編過 macOS，還為此加了一個 build-time 的 `VerifyTraceDefine` 迴歸守衛。** 這是「跨平台是設計目標」而非「碰巧能編」的行為。

**採用度（客觀數字）**：最新穩定版 `v4.3.29`（2026-06-11，master 線）—— MacOS 52 次下載、Windows 1,058 次、Ubuntu 20 次。**Mac 使用者確實存在，約佔 5%。**

**未驗證（誠實界線，這一點很關鍵）：**

- **沒有找到任何一筆「在 macOS 上跑 3.4.3 WotLK 路徑」的紀錄。** 上述所有 macOS issue 的 `Modern Client` 欄位都是 **1.14.0 Classic Era**（#64、#75 明確填寫），後端是 VMaNGOS / cMaNGOS / Solocraft。
- **`wotlk.md` 的開發環境是 100% Windows**：路徑全是 `X:\Programming\...`、`F:\Game\...`，測試迴圈是 PowerShell（`test-loop2.ps1`）、`.claude/skills/` 下全是 `.ps1`，crash dump 指示是 WinDbg / Visual Studio。**這條 3.4.3 分支的所有 ✅ 都是在 Windows 上打勾的。**
- **macOS 的 3.4.3 client 是否存在、能否被 Arctium/Burralis launcher 啟動 —— 完全未驗證**，且受制於 [macOS 筆記](./macos-client-options.md)§3 的取得牆。
- **推論（未驗證）**：GitHub Releases 的 zip 未經 Apple 公證（notarization），首次執行會被 Gatekeeper 隔離，需手動放行。這是 CI workflow 沒有任何 `codesign` / `notarytool` 步驟所推得，**未實測**。

### 5.4 這對整體架構的意義 ★

**如果 3.4.3 client 本身是原生 arm64（[macOS 筆記](./macos-client-options.md)§4.1：Blizzard 對 Classic client 有 M1 系統需求的間接證據，但無明文），那麼整條 stack 沒有任何一個元件需要 Rosetta 2 / CrossOver / Parallels：**

| 元件 | 語言 / 架構 | 在 Apple Silicon 上 |
|---|---|---|
| 3.4.3 Classic client | Blizzard 二進位 | **原生 arm64（間接證據，未驗證）** |
| **HermesProxy** | **C# / .NET 10，self-contained universal binary** | **原生 arm64（已驗證：CI 產物 + macOS issue）** |
| TrinityCore 3.3.5a / AzerothCore 後端 | C++ | **原生 arm64**（[macOS 筆記](./macos-client-options.md)§6 已驗證 `3.3.5` 分支有 `macos-arm-build.yml`；`wotlk.md` 的 AzerothCore 就跑在 **Mac mini Docker** 上） |
| MySQL / MariaDB | — | 原生 arm64 |

**→ 與 [macOS 筆記](./macos-client-options.md)§6 的第 1/2 名（3.3.5a Windows client 疊 Prism/WOW64 或 Rosetta+Wine）相比，這條路把「三層翻譯」降到「零層翻譯」，同時保有 100% 正統 3.3.5a 的內容（因為後端就是 3.3.5a）。** 這是本次調查發現的最有價值的一件事 —— **它同時解決了 macOS 筆記結論裡那個「內容最完整的路徑綁在效能最差的執行路徑上」的張力。**

**唯一的代價，也是唯一的阻斷點：client。**

---

## 6. 專案健康度（全部 `gh api` 實測，無估算）

### 6.1 commit 節奏（`feature/wotlk-classic-v3.4.3`，2025-09-01 起）

| 月份 | commits |
|---|---|
| 2025-09 | 19 |
| 2025-10 / 11 / 12 | **0 / 0 / 0** |
| 2026-01 | 42 |
| 2026-02 | **0** |
| 2026-03 | 8 |
| 2026-04 | 104 |
| 2026-05 | **208** |
| 2026-06 | 17 |
| 2026-07 | **0** |
| 2026-08 | **164** |
| 2026-09（至 09-02） | 19 |

**讀法**：這是一個**個人專案的爆發式節奏**，不是穩定的團隊 cadence。有三個完全空白的月份（2025 Q4、2026-02、2026-07）。但兩次爆發（2026-04/05 的 312 個、2026-08 的 164 個）都很深，而且**最近一次爆發就是上個月**，最後一個 commit 是**昨天**（2026-09-02 23:16 UTC，`e495721c docs(wotlk): record the 2026-09-02/03 playtest pass`）。

**作者分布**（同期間）：`Xian55` 411、`Xii` 113（同一人的另一個 git identity，其 commit 全部是 "Merge pull request #N from Xian55/..."）、`Radu Ursache` 55、`Ivan` 2。→ **實質是單人專案 + 一位常態貢獻者。**

### 6.2 issue / PR 數字

| 指標 | 數值 |
|---|---|
| open issues | **30** |
| closed issues | **72** |
| open PRs | **0** |
| closed PRs | **132** |
| **merged PRs** | **125**（merge 率 94.7%） |

**PR 的 base branch 分布**：`feature/wotlk-classic-v3.4.3` **77 個**、`master` 45 個、`feature/dotnet10` 10 個。

**→ 決定性的一項：這條 3.4.3 分支不是側邊實驗，它是主力開發線。** 專案 61% 的 PR 都是往這條分支合的，而且是走正式 PR review 流程（不是直接 push）。

### 6.3 維護者回應

- issue 開啟者分布：`Xian55` 67、`kasperfriend` 6、`b4bass` 5、`trickscode` 4、`wyy000111` 3、`Thorsten42` 3，另有 8 位各 1–2 個。→ **大部分 issue 是維護者自己開來當工作項追蹤的**，但外部回報確實存在且被處理（#64 / #74 / #75 / #79 都有對應的 fix PR：#68 / #81 / #92）。
- **回應速度**：2026-09-02 一天之內，#210 / #211 / #212 / #213 / #216 / #221 / #223 六個 issue 被關閉，各自對應 PR #225–#233。當天 `wotlk.md` 也更新了。
- `wotlk.md` 記錄了社群測試者的角色：`@kasperfriend` 在 2026-09-02/03 對 AzerothCore 跑了一輪 playtest，「filed results on every `needs-playtest` issue」，其中 7 項需要修正、respec 不需要。

### 6.4 有沒有往 default branch 合？—— 沒有

- `master` 最後一個 commit：**2026-06-11**（`a51a7563 Merge pull request #100 ...`）—— **停了將近三個月。**
- `master...feature/wotlk-classic-v3.4.3` = **ahead 338 / behind 0 / 300 files**。
- **open PR 為 0**，也就是**目前沒有任何把 3.4.3 合回 master 的計畫在進行中**。
- 分支清單（9 條）：`master`、`feature/wotlk-classic-v3.4.3`、`feature/fix/73`、`feature/fix/73-2`、`perf/v343-minimise-login-hotfixes`、`perf/union-*`（4 條）。

**→ 風險判讀：所有 WotLK 價值都集中在一條未合併的 feature branch 上，穩定版 release（`v4.3.29`，master 線）不含 3.4.3 支援。使用者要用的是 pre-release 產物。** 好消息是 CI 有 `PreRelease.yml` 專門為 `feature/**` 分支產出可下載的 pre-release，這條分支因此每次 push 都有二進位可用 —— 這是刻意設計，不是意外。

### 6.5 工程品質訊號（客觀事實，非背書）

- 測試：`wotlk.md` 自述 "the suite has **296 tests** covering the legacy paths"；CI 在 `ubuntu-latest` 上跑 `dotnet test`。
- 有 source generator（`HermesProxy.SourceGen`）產生 opcode / update-field 表。
- 有 benchmark 專案（BenchmarkDotNet）、`--metrics` 的 per-opcode 延遲與配置量測。
- `PublishTrimmed=true` + trimmer root 設定，`.csproj` 裡有大段解釋為什麼每個 root 是必要的。
- 有 `checksums-sha256.txt` + `verify-checksums.sh` / `.ps1` 隨 release 發布。
- README 自述 `ISpanWritable` 覆蓋率 84.7%（272 / 321 server packets）。

---

## 7. 使用者實際要跑的 end-to-end stack

### 7.1 元件清單（全部可在同一台 Mac 上）

| # | 元件 | 具體是什麼 | 跑在哪 | 狀態 |
|---|---|---|---|---|
| 1 | **Client** | WoW WotLK Classic **3.4.3.54261** | macOS（原生 arm64，間接證據） | **🔴 取得不到** |
| 2 | **Launcher** | `Burralis/Game-Launcher`（原 Arctium），`--staticseed --version=Classic` | macOS | ⚠️ macOS 支援未驗證 |
| 3 | **Proxy** | HermesProxy pre-release `HermesProxy-MacOS-*.zip`（universal binary，self-contained） | macOS **原生 arm64** | 🟢 |
| 4 | **後端 core** | TrinityCore `3.3.5` 分支（本 repo，官方維護中）**或** AzerothCore | macOS 原生 arm64，或 Docker | 🟢 |
| 5 | **後端 DB** | 官方 TDB 3.3.5 world/hotfixes + auth/characters | MySQL / MariaDB arm64 | 🟢 |
| 6 | **設定** | `Config.wtf` → `SET portal "127.0.0.1"`；`appsettings.json` → `ClientBuild=V3_4_3_54261`、`LegacyServerOptions:Address/Port` | — | 🟢 |

**注意 port 配置**：proxy 預設佔用 `1119`（BNet）、`8081`（REST）、`8084`（Realm）、`8086`（Instance）；後端 realmd 在 `3724`。同機共存沒有衝突（`wotlk.md` 特別提到的衝突是 proxy vs Wrathion 原生伺服器，與本 stack 無關）。

### 7.2 剩餘的未知與阻斷點（依嚴重度排序）

| # | 項目 | 嚴重度 | 說明 |
|---|---|---|---|
| **1** | **取得 3.4.3.54261 client** | **🔴 阻斷** | CDN build config 實測 404（[macOS 筆記](./macos-client-options.md)§3.3）；Battle.net 的 `wow_classic` 現在只供應 5.5.4.69585。**這一項沒解決，後面全部不用談。** 本文不提供任何取得途徑。 |
| **2** | **macOS 3.4.3 client + launcher 組合從未被任何人驗證** | 🟠 高 | 分支的所有測試都在 Windows；macOS 的 proxy 使用紀錄全部是 1.14 Classic Era。**第一個踩雷的人會是使用者本人。** |
| 3 | Warlock 靈魂碎片入包導致 DC | 🟠 高 | 職業級阻斷，`wotlk.md` 列為 open |
| 4 | 偶發 `CMSG_LOG_DISCONNECT(reason=7)` | 🟠 高 | TC 欄位標 ❌；另有「過場動畫跳太快會 DC」的 caveat |
| 5 | Pattern A/B/E/F/H 的職業技能殘留缺口 | 🟡 中 | 多數已由 `557310f` 一次修好，但**大量法術從未複驗** |
| 6 | 公會系統完全未記錄 | 🟡 中 | 矩陣沒有這一列 → 未驗證 |
| 7 | Addon 相容性完全未記錄 | 🟡 中 | 已知 Quest Helper 的點擊導航不作用（根因在後端 `quest_template` POI 為 0） |
| 8 | 2306 筆 raid-tier 裝備 `ItemSparse` 被丟棄 | 🟡 中 | tooltip 靠 legacy 路徑補救，但影響高階裝 |
| 9 | 理髮店 / 行事曆 ❌ | 🟢 低 | 明確未橋接 |
| 10 | Gatekeeper 公證 | 🟢 低 | 未驗證，但可手動放行 |
| 11 | 全部價值集中在未合併的 feature branch | 🟢 低 | 專案風險，非技術阻斷 |

### 7.3 一件重要的「其實不需要」

**使用者不需要**：跑 extractor、抽 CASC、建 DB2/hotfix 資料、改任何一行後端程式碼、重建 world database。這些正是 [路線圖筆記](./wotlk-classic-port-roadmap.md) Stage 1–6（估數月到無終點）的全部內容。**HermesProxy 把它們整批消掉。**

---

## 8. 誠實的裁決

### 8.1 三條路正面對比

| | **(a) `3.3.5` 分支 + Windows 12340 client + CrossOver/Parallels** | **(b) DIY `cata_classic`→3.4.x port** | **(c) HermesProxy + 3.4.3 client + 3.3.5a 後端** |
|---|---|---|---|
| **client 取得** | 🟢 **可行**（12340 是 2010 年的舊 client，不依賴 Blizzard CDN） | 🔴 3.4.4.61581 CDN 404 | 🔴 3.4.3.54261 CDN **同樣 404** |
| **內容完整度** | 🟢 **100%** 正統 3.3.5a，官方維護中，官方 TDB | 🟠 未知；1–60 舊世界的災變前地形 × 災變後 spawn 是**最大未解問題** | 🟢 **100%**（後端就是 3.3.5a，world DB 原封不動） |
| **Apple Silicon 執行** | 🔴 三層翻譯（32-bit x86 → WOW64/Rosetta → arm64；D3D9 → Metal），且 CrossOver 27 / macOS 27 有到期日 | 🟢 原生（若 client 原生） | 🟢 **原生，零翻譯層**（若 client 原生） |
| **需要投入的工程量** | 🟢 幾乎 0（照裝） | 🔴 **數月到無終點**（[路線圖](./wotlk-classic-port-roadmap.md) Stage 1–6） | 🟢 **幾乎 0**（下載 pre-release、改兩個設定檔） |
| **成熟度** | 🟢 十餘年、數百萬人跑過 | 🔴 上游 `wotlk_classic` 停在 2025-07-02 | 🟠 **experimental**，但 99 列矩陣中 78 列 ✅ |
| **維護狀態** | 🟢 官方分支，2026-08-30 仍有 commit | 🔴 停滯 | 🟠 單人專案，爆發式節奏，最後 commit 昨天 |
| **成本** | Parallels + Windows 授權，或 CrossOver 授權 | 你的時間 | **0** |

### 8.2 明確建議

**HermesProxy 在工程上是這四條路裡最好的一條 —— 但它現在不能當使用者的主要路徑，理由只有一個，而且不是它的錯。**

**它真正贏在哪（不誇大）：**
- 它是唯一一條**同時**給出「原生 Apple Silicon 執行」與「100% 正統 WotLK 內容」的路。前三篇筆記反覆描述的那個張力（[macOS 筆記](./macos-client-options.md)§6 結語：「內容最完整的 WotLK 綁在效能最差的執行路徑上」）—— **這條路把它解掉了。**
- 它把 [路線圖筆記](./wotlk-classic-port-roadmap.md) 的 Stage 1–6 整批消掉：不改 core、不重建 world DB、不跑 extractor。
- 它的文件誠實度異常高（明確區分「已驗證」「從未測過」「已知未橋接」，甚至寫 "the symptom is speculative"、"the AzerothCore column is deliberately not re-ticked"），而且是活的（最後 commit 昨天）。

**它為什麼還是 no-go：**
1. **client 拿不到。** 3.4.3.54261 的 CDN build config 實測 404，Battle.net 沒有這個產品線。**這是硬阻斷，而且 HermesProxy 幫不上忙 —— 它明確假設你「已經」有一份 3.4.3 安裝。**
2. **就算拿得到，macOS 上的 3.4.3 路徑零驗證。** 分支的所有 ✅ 都在 Windows 上打的；macOS 的 proxy 實證全是 1.14 Classic Era。使用者會是全世界第一個測這個組合的人。
3. **它自我標註 experimental**，且有兩個職業級 / 連線級的 open 問題（Warlock 靈魂碎片 DC、偶發 reason=7 DC）。

**所以，實際建議：**

- **主要路徑維持 [macOS 筆記](./macos-client-options.md)§6 的第 1／2 名不變**：`3.3.5` 分支 + **Windows 版** 12340 client + CrossOver 26.x（先試，成本最低）或 Parallels + Windows 11 ARM64（長期）。**這是唯一 client 拿得到、內容 100%、今天就能玩的組合。**
- **HermesProxy 升格為「條件觸發的第一名」**。觸發條件只有一個：**手上出現一份 3.4.3.54261 的安裝**（例如舊 Battle.net 安裝目錄還在）。條件一旦成立，它立刻超越前兩名，因為它同時給原生 arm64 與完整內容。→ **具體行動：先去確認 `~/Applications/World of Warcraft/_classic_/` 或任何舊備份裡有沒有 3.4.3 的資料。這一步成本是十分鐘，決定了整件事的走向。**
- **DIY port（路線 b）在有了 HermesProxy 之後應該正式降級。** 它要付出數月工程量，換到的東西（3.4.4 原生協定）比 HermesProxy 差 —— 因為 HermesProxy 的後端是成熟的 3.3.5a，內容完整度反而更高，而 DIY port 還要獨自面對「1–60 舊世界地形錯位」這個沒有乾淨解的問題。**除非目的本身就是工程練習，否則不建議。**
- **不要為了 HermesProxy 去追 3.4.5.63697。** 它只認 54261，descriptor 樹是手寫的，換 build 等於重做核心工作。

**一句話：go 的是「花十分鐘確認手上有沒有 3.4.3 client」；在那之前，HermesProxy 是 no-go 作為主要路徑。**

---

## 9. 明確記錄「沒做 / 拿不到 / 未驗證」

- **未實測執行**：本文沒有下載、編譯或執行 HermesProxy 的任何版本。所有能力陳述都來自 repo 文件與原始碼。
- **未驗證**：`wotlk.md` 狀態矩陣的正確性 —— 這是開發者與其測試者的自述。
- **未驗證**：macOS 上跑 3.4.3 路徑（client + launcher + proxy）—— **找不到任何一筆紀錄**。
- **未驗證**：README 支援表寫的 client build 下限 `51505` 是否真的可用（enum 裡沒有這個值）。
- **未驗證**：release 的 macOS 二進位是否經 Apple 公證。
- **未驗證**：3.4.3 Classic client 是否為原生 arm64（[macOS 筆記](./macos-client-options.md)§4.1 只有間接證據）。
- **未涵蓋**：**公會（Guild）系統** —— `wotlk.md` 矩陣完全沒有這一列。
- **未涵蓋**：**Addon 相容性** —— 全文 grep 只有兩處提及 addon，皆非狀態陳述。
- **未評估**：安全性、GPL-3.0 授權合規性、以及第三方二進位的信任問題。**注意 GPL-3.0 與 TrinityCore GPL-2.0-or-later 的單向相容性。**
- **未做**：任何 client / repack / 檔案空間連結的蒐集或記錄。
- **未做**：瀏覽器自動化。
- **未取得**：`wotlk.md` 引用的本機路徑（`X:\Programming\...`、`F:\Game\...`）與封包側錄檔 —— 那些是維護者本機的東西。

---

## 10. 驗證指令（可重跑，全部唯讀）

```bash
# 血統：三個 repo 的關係
for r in WowLegacyCore/HermesProxy Xian55/HermesProxy advocaite/HermesProxy-WOTLK; do
  gh api repos/$r --jq '{full_name,parent:.parent.full_name,desc:.description,
    license:.license.spdx_id,stars:.stargazers_count,archived,pushed_at,default_branch}'
done
gh api repos/WowLegacyCore/HermesProxy/readme --jq '.content' | base64 -d | sed -n '11,18p'  # 只有 1.14/2.5
gh api repos/WowLegacyCore/HermesProxy/compare/master...Xian55:HermesProxy:master \
  --jq '"ahead=\(.ahead_by) behind=\(.behind_by)"'                                # 243 / 0

# 分支拓樸
B=feature/wotlk-classic-v3.4.3
gh api "repos/Xian55/HermesProxy/compare/master...$B" \
  --jq '"\(.status) ahead=\(.ahead_by) behind=\(.behind_by) files=\(.files|length)"'  # ahead 338 / 300 files
gh api repos/Xian55/HermesProxy/branches --jq '[.[].name]|join(", ")'
gh api "repos/Xian55/HermesProxy/commits?sha=master&per_page=1" \
  --jq '.[0]|"\(.commit.author.date) \(.sha[0:8])"'                                # master 停在 2026-06-11

# 本文第 2 節的全部內容來源
gh api "repos/Xian55/HermesProxy/contents/wotlk.md?ref=$B" --jq '.content' | base64 -d > wotlk.md
awk '/^\| Subsystem \| TC 3.3.5a/,/^$/' wotlk.md | awk -F'|' '{print $2,$3,$4,$5}'  # 99 列狀態矩陣

# client build（第 3 節）
gh api "repos/Xian55/HermesProxy/contents/Framework/Constants/ClientVersionBuild.cs?ref=$B" \
  --jq '.content' | base64 -d | grep -A2 "WotLK Classic"          # 只有 V3_4_3_54261 = 54261

# runtime / macOS（第 5 節）
gh api "repos/Xian55/HermesProxy/contents/Directory.Packages.props?ref=$B" \
  --jq '.content' | base64 -d | grep -A2 TargetFramework          # net10.0
gh api "repos/Xian55/HermesProxy/contents/.github/workflows/Release.yml?ref=$B" \
  --jq '.content' | base64 -d | grep -B2 -A6 "MacOS x86_64"       # osx-arm64 + osx-x64 + lipo
gh api "search/issues?q=repo:Xian55/HermesProxy+macos" \
  --jq '.items[]|"#\(.number) [\(.state)] \(.title)"'             # #29 / #60 / #64 / #75 / #87

# 專案健康度（第 6 節）
gh api "repos/Xian55/HermesProxy/commits?sha=$B&per_page=100&since=2025-09-01T00:00:00Z" \
  --paginate --jq '.[].commit.author.date[0:7]' | sort | uniq -c
for q in "is:issue+is:open" "is:issue+is:closed" "is:pr+is:open" "is:pr+is:closed" "is:pr+is:merged"; do
  gh api "search/issues?q=repo:Xian55/HermesProxy+$q&per_page=1" --jq '.total_count'
done                                                              # 30 / 72 / 0 / 132 / 125
gh api "repos/Xian55/HermesProxy/pulls?state=all&per_page=100" --paginate \
  --jq '.[].base.ref' | sort | uniq -c                            # 77 往 wotlk 分支

# release 產物
gh api "repos/Xian55/HermesProxy/releases/tags/v4.3.0-feature-wotlk-classic-v3-4-3-e495721" \
  --jq '.assets[]|"\(.name) \(.size) dl=\(.download_count)"'
```

---

## 11. 實際取用過的來源

**`Xian55/HermesProxy`（一手，全部實際取得）**
- repo metadata、branches（9 條）、`master...feature/wotlk-classic-v3.4.3` compare
- `wotlk.md`（分支根目錄，597 行 / 159,792 bytes，**全文**）
- `README.md`（分支，265 行，全文）
- `Directory.Packages.props`、`HermesProxy/HermesProxy.csproj`（全文）
- `Framework/Constants/ClientVersionBuild.cs`
- `.github/workflows/Build_Proxy.yml`、`Release.yml`、`PreRelease.yml`
- `docs/known-issues.md`
- `HermesProxy/World/Enums/`（目錄清單，含 `V3_4_3_54261/`）
- issues #29 / #64 / #75 / #87 / #210–#233（清單）、issue 與 PR 統計、PR base branch 分布
- releases（含 `v4.3.0-feature-wotlk-classic-v3-4-3-e495721` pre-release 與 `v4.3.20`–`v4.3.29` 的 asset 下載數）
- commit 歷史（`sha=feature/wotlk-classic-v3.4.3`，2025-09-01 起，逐月）與作者分布

**`WowLegacyCore/HermesProxy`（一手）**
- repo metadata（archived / stars / pushed_at）、README 全文（支援表只有 1.14 / 2.5）
- `master...Xian55:master` compare

**`advocaite/HermesProxy-WOTLK`（一手）**
- repo metadata（`parent` 為 null → 非 GitHub fork）

**取用失敗**：無。本次所有目標皆成功取得。
