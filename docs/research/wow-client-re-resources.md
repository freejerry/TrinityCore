# WoW client 逆向的公開資源盤點 —— 特別針對「執行期 dump 解密後的 macOS `__TEXT`」與 auth seed 萃取

> 撰寫日期：2026-09-06
> 相關筆記：[Mac ARM auth seed 有沒有公開值、怎麼挖](./mac-arm-auth-seed.md)（本篇是它 §4「怎麼挖」的**外部資源佐證篇**——把「有沒有現成工具與 writeup」查清楚）、[Mac ARM auth seed 靜態抽取實作與結論](./mac-arm-auth-seed-extraction.md)（該篇證實磁碟上 `__text` 熵值 8.000、有 `__INIT1`/`__INITC`/`__mod_init_func` bootstrap、無 `LC_ENCRYPTION_INFO`——本篇接續「必須先在記憶體裡解密」這條線）、[BlizzardBrowser / Rosetta](./blizzardbrowser-rosetta.md)（同一顆 client 的架構與簽章實測）、[wow-patcher runtime 模式](./wow-patcher-runtime-mode.md)（Windows 端 Arxan `.text` 加密的旁證）
> **本篇回答五個問題：**（1）有沒有公開、文件化的方法「在執行期 dump 出解密後的 WoW `__TEXT`」，特別是 macOS / Apple Silicon？（2）WoW client 逆向的社群與資源有哪些、哪些涵蓋 3.4.x？（3）auth seed 萃取有沒有公開 writeup？（4）Arxan / 類 Arxan 加殼在 macOS 上的已知 dump 點？（5）有沒有人做過「native macOS arm64 client 連 TrinityCore」並記錄認證怎麼過？
> 來源限定 primary sources：一手 repo README／原始碼、部落格作者原文、wiki 頁面、論壇原串（透過 WebFetch/WebSearch 取得）。凡屬「社群傳聞／推測」一律標記，與「有文件佐證」明確區分。未使用瀏覽器自動化。未記錄任何 client 下載點或受版權 dump。**本篇不臆造任何 hex 值／版本號／日期。**

---

## 0. TL;DR —— 直說有沒有現成路子

**（Q1）「執行期 dump 解密後的 macOS `__TEXT`」——有現成、文件化的方法，但沒有一個是為 WoW／arm64 現成寫好的，全部要移植。** 最貼合我們這顆 binary 的是 **Timac 的 `DYLD_INSERT_LIBRARIES` + destructor** 手法（§1.1）：注一個 dylib、在程式收尾時把記憶體裡**已解密**的 `__TEXT,__text` `memcpy` 回檔案、並把 `__mod_init_func` 清零防止重新加密——**這正好對上我們 binary 的 `__mod_init_func` bootstrap**（[extraction 篇](./mac-arm-auth-seed-extraction.md) §2.5）。但原文明說「只支援 64-bit **Intel**」，arm64 要自己補（作者稱「fairly simple」）。此外 `lldb process save-core`（skinny corefile，§1.2）、`frida` / `fridump`（§1.3）都是通用可用手段。

**（Q3 / Q5）沒有人公開過任何 macOS（x64 或 arm64）seed，也沒有人公開過「從 client 萃取 seed 值」的逐步 writeup——不分平台。** 存在的最接近物是 Arctium／wow-patcher 的 **pattern anchor（`"WoW\0"` 緊接 `call`）**，那是「定位 seed 函式」而非「讀出值」，且 Windows-only；這條已在 [mac-arm-auth-seed.md §4.1](./mac-arm-auth-seed.md) 記錄。**native macOS arm64 client 連 TrinityCore 的認證 writeup 也不存在**——公開世界的共識路線是 Arctium 的 **static auth seed patch**（把函式換成回傳常數），不是萃取真值；我們用「繞過 digest」達成同一目的，等價且更省事。

**（Q4）Arxan 的公開 dump 手法是 Windows-only（`fix-arxan`：斷在解密routine → dump 記憶體 → 合併修復），但它的原理（等 bootstrap 解完再從記憶體抓）與 §1.1 的 macOS 手法完全同源。** WoW 特定的「解密完成時機／可下斷點的位置」——**公開世界零記錄**（未驗證）。

**最務實下一步不變：先做 [mac-arm-auth-seed.md §4.4 的 `CC_SHA256_Update` hook](./mac-arm-auth-seed.md#44-路線-c-runtime-hook-cc_sha256_update-建議先試這條)**——它完全繞開「dump 解密 `__text` + 反組譯」這整條難路，一次登入就閉環拿到值。§1 這些 dump 手法是「若一定要看懂函式」時的備援。

---

## 1. 執行期 dump 解密後 `__TEXT` —— 文件化的方法（macOS / Apple Silicon）

前提回顧（[extraction 篇](./mac-arm-auth-seed-extraction.md) 已證實）：磁碟上 `__text` 是密文（熵 8.000），`LC_ENCRYPTION_INFO` = 0 筆（**不是 FairPlay，是應用層加殼**），bootstrap 是 `__INIT1`/`__INITC` + `__mod_init_func`。所以「等 process 起來、init 跑完解密，再從記憶體抓明文」是唯一物理可行的方向。以下方法都在做這件事。

> **一個重要的來源性質提醒：** 下面多數 writeup 原本是為 **iOS FairPlay DRM**（`LC_ENCRYPTION_INFO` + `cryptid`）寫的。**我們這顆 binary 不是那種加密**——它沒有 `cryptid`，是自解密的應用層加殼。差別在於：FairPlay 的解密由 **dyld/kernel** 在載入時自動完成，工具只要「等 load 完就 dump」；我們的解密由 **binary 自己的 `__mod_init_func`** 完成，所以「dump 的時機」要**晚於**那些 init 跑完（理論上 `main` 進入點之後就好）。手法可移植，時機要自己抓。**此段為分析，非某來源原話。**

### 1.1 ★ Timac：`DYLD_INSERT_LIBRARIES` + destructor，把解密後的 `__text` memcpy 回檔案（最貼合本案）

**來源（一手，作者原文）：** Timac, *"Dump decrypted mach-o files"*, blog.timac.org, 2016-08-04。

手法（不需 debugger，靠 app 自身生命週期）：

1. 寫一個小 dylib，含一個 `__attribute__((destructor))` 函式（程式收尾前執行——此時 `__text` 早已被 init 解密完畢）。
2. destructor 內：`_dyld_get_image_header()` 找主 image、`_NSGetExecutablePath()` + `realpath` 取路徑、`fopen`/`fread` 把**磁碟原檔**讀進 buffer。
3. 解析 load command 找 `(__TEXT,__text)`，把**記憶體裡已解密**的那段覆蓋回 buffer：`memcpy(fileBuffer + section->offset, (uint8_t*)machHeader + section->offset, section->size)`。
4. **把 `(__DATA,__mod_init_func)` 清零**，避免產出的檔案再次觸發自解密／自我修改。
5. 寫出成新的 mach-o。

**為什麼這條對我們最貼切：** 步驟 4 清的正是我們 binary 有的 `__mod_init_func`（[extraction 篇](./mac-arm-auth-seed-extraction.md) §2.5）——原理完全對上。**限制（作者明說）：「it only supports 64-bit intel Mach-O files」，arm64 未含，需自補（作者評估「fairly simple」）。** 我們要 dump 的是 arm64 slice，所以這段 mach-o 解析要改成 arm64 + 處理 fat binary slice offset。用 `DYLD_INSERT_LIBRARIES` 注入需先重簽並加 `disable-library-validation`（見 §1.4）。

### 1.2 lldb `process save-core`（skinny corefile）

**來源（一手）：** LLVM review D88387（"Create skinny corefiles for Mach-O with process save-core"）；HackTricks *macOS Memory Dumping*。

- `sudo lldb --attach-pid <pid>` → `(lldb) process save-core /tmp/x.core`。預設產出 **skinny core**（只含 dirty pages），因為 Darwin 的系統庫是共享的，full core 會是好幾 GB 幾乎全是未改動頁。
- 對我們的用途：attach 到已解密的 process，把 `__TEXT` 的 vmaddr 範圍（arm64 base `0x100000000`、`__text` 至 `0x101ca9b18`，見 extraction 篇）用 `memory read` 或整包 `process save-core` 抓出來，再對 dump 重跑 [extraction 篇](./mac-arm-auth-seed-extraction.md) §3 已寫好的 ADRP/xref 掃描器（那些掃描器對**明文** `__text` 才會生效）。
- 缺點：core 檔要自己對回 section offset；skinny core 只含 dirty page——**自解密後的 `__text` 頁一定是 dirty（被寫過），所以會被收進 skinny core**（此點為推論，未實測）。

### 1.3 frida / fridump —— 通用記憶體 dumper

**來源（一手 repo）：** `Nightbringer21/fridump`（"A universal memory dumper using Frida"）；OWASP MASTG `frida-ios-dump`；`DerekSelander/symbol-interposing`。

- `fridump` 用 Frida 列舉可讀記憶體區段並整包 dump，跨 Windows/Linux/macOS，可 dump iOS/Android/其他 process 的記憶體。對我們：attach 後 dump `__TEXT` range 即可。
- `frida-ios-dump` / MASTG 那類**專為「重建解密 mach-o」**設計的工具，是讀 `LC_SEGMENT` 找 `__TEXT`、把記憶體內容寫回新 mach-o——**邏輯與 §1.1 相同**，但它們鎖定 iOS FairPlay 的 `cryptid`，直接搬到我們這顆自解密 binary 上不會「認得」加密（因為沒有 `cryptid`），所以要改成「無條件覆蓋 `__text`」。**（分析）**
- Frida 也可以完全不 dump，直接 `Interceptor.attach` 到 export——這就是 §3 的 `CC_SHA256_Update` hook 路線，見 [mac-arm-auth-seed.md §4.4](./mac-arm-auth-seed.md)。

### 1.4 前置條件：hardened runtime 下的注入（有文件佐證，且我們控制簽章）

**來源（一手）：** AFINE *"To Allow or Not to get-task-allow"* 與 *"Task Injection on macOS"*；`malwarewerewolf.com` *Inject code in macOS processes with Frida*；HackTricks *macOS Dyld Hijacking & DYLD_INSERT_LIBRARIES*。

- `com.apple.security.get-task-allow` entitlement 會**繞過 hardened runtime 對 task port 的保護**，同 user 的 process 即可取得目標 task port（frida attach 的前提），**且不需 root**。
- 重簽加 entitlement：`codesign -f -s - --entitlements ent.plist ./target`，plist 內 `get-task-allow = true`（要 attach frida）／`disable-library-validation = true`（要 `DYLD_INSERT_LIBRARIES` 注非同簽 dylib）。
- **這正好落在我們的能力範圍：** 我們自簽這顆 client（[BlizzardBrowser 篇](./blizzardbrowser-rosetta.md) 記錄了簽章實測），可自由加這兩個 entitlement，且 client 本身已帶 `allow-jit`/`allow-unsigned-executable-memory`/`disable-executable-page-protection`（[mac-arm-auth-seed.md §3.2](./mac-arm-auth-seed.md)），注入阻力比一般 app 低。
- 已知限制：SIP 保護的**系統／Apple binary** 無法用這招（與我們無關，我們注的是自簽 client）；macOS 10.14+ 第三方 app 的 hardened runtime 預設會擋 `DYLD_INSERT_LIBRARIES`——**但那是「未重簽」的情況；重簽解除即可**。

---

## 2. Arxan / 類 Arxan 加殼在 macOS 上的 dump 點

### 2.1 公開的 Arxan unwrap 手法 —— 全部 Windows-only，但原理同源

| 來源（一手） | 平台 | 手法要點 |
|---|---|---|
| `pr701/fix-arxan`（GitHub README） | **Windows PE only** | 靜態定位解密 loader → debugger **斷在解密 routine** → 解密完成後 **dump 記憶體** → 工具把 dump 與原檔合併、修復 IAT/headers。明說「**不**自動關閉 integrity check、**不**反混淆 code」。實測過 GTA V / RDR2 / AoE III / CoD。 |
| me3（FromSoftware mod loader）*"Reversing Arxan (GuardIT)"* | Windows | Arxan 會把函式的指令用 `jmp` 打散、隱藏 call site、破壞 IDA；偵測到 debugger 或 checksum 不符就**終止 process**。（RE 難點記錄，非 dump 步驟。） |

**共同結論（有文件佐證）：** Arxan 的通用打法就是「**等 bootstrap 把 code 在記憶體解完，再從記憶體抓 image**」——與 §1 的 macOS 手法**完全同源**，差別只在平台工具。fix-arxan 的「斷在解密 routine 後 dump」= §1.1 的「destructor 時 memcpy 記憶體」= §1.2 的「解密後 save-core」。

### 2.2 WoW 特定的解密完成時機 / 可下斷點位置 —— 零公開記錄

- **Windows 端：** [wow-patcher 篇](./wow-patcher-runtime-mode.md) 記錄的 `wow-patcher` 靠 **PE 的 TLS callback** 在 runtime 解密 `.text`，其 `dump-text`/`dump-sections` 子命令 `#[cfg(target_os="windows")]` only——這是**唯一**半公開的「WoW + Arxan dump」實作，但它 (a) Windows-only、(b) 針對 TLS callback 這個 Windows 專屬機制。
- **macOS 端：** 沒有任何一方公開過「WoW macOS binary 的 `__text` 何時解密完成、該下哪個 breakpoint」。我們自己的 [extraction 篇](./mac-arm-auth-seed-extraction.md) 是目前（本 repo 內）唯一把「`__INIT1`/`__INITC`/`__mod_init_func` 是自解密 bootstrap」寫下來的資料。**斷點位置：理論上任何在 `LC_MAIN` entry 之後、且 login 邏輯之前的點，`__text` 就已是明文**（此為分析／推論，**未驗證**——需實際 attach 確認）。

---

## 3. WoW client 逆向的社群與資源 —— 涵蓋度盤點

> 判準：對「**現代 client（3.4.x / retail）的 auth seed 或加殼**」有沒有幫助。多數 WoW RE 資源鎖定的是 **3.3.5a/12340 或更早**的明文 client，與我們這顆加殼的 3.4.3 客戶端關聯有限。

| 資源（一手） | 現況 / 涵蓋 | 對本案的用處 |
|---|---|---|
| **wowdev.wiki**（`CMD_AUTH_LOGON_CHALLENGE` Client/Server 等頁） | 活躍。內容偏 **WotLK/3.3.5a/12340 或 WoD/6.0.1**。 | 記錄的是 **logon（SRP6）**協定，**不是** world 端 `HandleAuthSession` 的 platform seed digest；對挖 seed **幫助有限**。 |
| **Arctium**（`arctium.io`；`WowLegacyCore/WoW-Launcher` 等多個 mirror／fork） | 活躍，涵蓋現代 retail/classic。 | ★ 提供 **`--use-static-auth-seed`（值 `179D3DC3235629D07113A9B3867F97A7`）** 與 `"WoW\0"`+`call` 的 seed 函式 anchor。**patch 產生器 Windows-only**，arm64 要自寫。詳見 [mac-arm-auth-seed.md §4.1/§4.3](./mac-arm-auth-seed.md)。 |
| **`WowLegacyCore/HermesProxy`**（`CSV/BuildAuthSeeds.csv`） | 活躍。 | 唯一公開 `MacA` seed（1.14.2 build 42597 `3B31A4F4C25382131A8FB95A1317412B`）之處，**與 3.4.3 無關**。詳見 [mac-arm-auth-seed.md §2](./mac-arm-auth-seed.md)。 |
| **`wowemulation-dev/wow-patcher`** | 活躍。 | 唯一半公開的「WoW + Arxan runtime dump」實作，**Windows-only**（§2.2）。 |
| **`agatho/ida-wow-analyzer`**（IDA plugin，~80 analyzer） | 活躍。 | **沒有 auth-seed extractor**（[mac-arm-auth-seed.md §4.2](./mac-arm-auth-seed.md) 已確認）；`auth_lifecycle.py` 復原的是 opcode/phase FSM，不是加密常數。 |
| **OwnedCore → WoW Memory Editing 版**（pattern maker / verifier / IDA pattern fixer 等 thread） | 長青，社群活躍。 | 提供 **signature/pattern 製作**的通用工具與方法（x86 為主）；沒有現成 seed extractor。屬「手法可借鏡」而非「現成答案」。**（社群論壇來源）** |
| **`samwhosung/wow-1121-client-internals`** | repo 存在。 | 針對 **1.12.1/5875** 的 client 行為（渲染／wire protocol／移動碰撞），**不涵蓋 auth 加密／seed 計算**（實查確認）。 |
| **`Kelsidavis/WoWee`** | repo 存在。 | clean-room 自製 client（不含 Blizzard 資產），**不是** dumper/deobfuscator，與萃取 seed 無關。 |
| **`WowDevTools`（GitHub org）** | 存在。 | modding/RE 工具集合；未見專門的 client dumper / auth-seed extractor。 |
| RE Discord（`Reverse Engineering` 伺服器等） | 活躍社群。 | 一般 RE 交流，非 WoW seed 專門；**（社群，無文件佐證）**。 |

**GitHub 上「WoW client dumper / deobfuscator / auth seed extractor」專案：** 查無任何專門、維護中、涵蓋 3.4.x / 現代客戶端**且針對 macOS** 的專案。最接近的三個（Arctium / wow-patcher / ida-wow-analyzer）都 (a) Windows-only 或 (b) 不含 seed 萃取。**（此為負面結論，見 §5。）**

---

## 4. auth seed 萃取的公開 writeup —— 存在什麼、缺什麼

**存在（有文件佐證）：**

- **「定位 seed 函式」的 pattern**：Arctium `src/Patterns/Windows.cs` 的 `{0x57,0x6F,0x57,0x00,0xE8,-1,-1,-1,-1,0x48,0x8D}`（`"WoW\0"`+`call`+`lea`），以及 wow-patcher `src/patterns/runtime/windows.rs` 的同一 anchor（明注 "canonical anchor … used by the static-auth-seed feature (planned, not yet ported)"）。→ 這告訴你**函式在哪**、以及 x64 ABI 下它把 16 bytes 寫進 `rdx` buffer（Arctium `src/Patches/Windows.cs` 的替換函式洩漏）。**全文已抄錄在 [mac-arm-auth-seed.md §4.1](./mac-arm-auth-seed.md)。**
- **「不挖、改用固定值」的 writeup**：Arctium `--use-static-auth-seed` 的說明字串與固定值 `179D3DC3235629D07113A9B3867F97A7`；server 端做法（在 DB 加這個 seed）也有社群說明。

**不存在（負面結論）：**

- **「讀出 seed 真值」的逐步 writeup —— 不分平台皆無。** 沒有任何部落格／論壇串／repo README／issue 記錄「怎麼把 client 產生的 16 bytes 實際 dump 出來並對照驗證」。Windows 也沒有（大家都改用 static seed，繞過了「讀真值」這件事）。
- **任何 macOS（x64/arm64）seed 值、任何 macOS seed 萃取腳本**（IDA/Ghidra/frida/lldb 皆無）——與 [mac-arm-auth-seed.md §5](./mac-arm-auth-seed.md)、[extraction 篇 §4](./mac-arm-auth-seed-extraction.md) 的結論一致。
- **TrinityCore 維護者每個 build 發 Mac/A64 key 的取得方法**——248 筆值公開，方法零記錄（[mac-arm-auth-seed.md §1.1](./mac-arm-auth-seed.md)）。

> **手法可移植性：** Windows 的「`"WoW\0"`+`call` anchor → 追 indirection → seed 函式」在 arm64 上不能照抄 byte pattern（字串與 code 分屬不同 section），要改用 ADRP/ADD xref——這條路 [extraction 篇 §2.3/§3](./mac-arm-auth-seed-extraction.md) 已寫好掃描器，**但前提是先有解密後的 `__text`（即本篇 §1）**。

---

## 5. native macOS arm64 client 連 TrinityCore —— 別人怎麼過認證？

**查無任何公開 writeup 記錄「native macOS arm64 WoW client 連 TrinityCore 並通過 world-auth digest」。** 現況拼圖：

- **TrinityCore 論壇有 "Arctium Launcher (Mac)" 串**，但實查到的內容是**歷史性的 `task_for_pid` 失敗**（早年 Intel Mac、2019 MacBook 情境），**沒有** Apple Silicon 上成功連線＋通過認證的記錄。**（論壇來源，且非 arm64 成功案例。）**
- **公開世界的共識路線是 Arctium 的 static auth seed patch**：不萃取真 seed，而是把 client 的 seed 函式換成回傳一個雙方約定的常數，server 端 DB 塞同一常數。這是「讓認證能過」而非「拿到 Blizzard 真值」——**Windows-only 實作**。
- **我們的做法（繞過 digest）與 static-seed 路線在效果上等價**：兩者都不需要 Blizzard 的真 seed，都只需要「server 認得 client 送來的東西」。差別是 static-seed 要 patch client（arm64 patch 得自寫），繞過 digest 只動 server——**我們的路線在 macOS/arm64 上其實更省，因為避開了「在 arm64 加殼 `__text` 裡定位並改寫函式」這個最難的步驟。**

**結論：別人沒有比我們更好的路。** 真正萃取 macOS 真 seed 是「開荒」（沒有前人 writeup、沒有現成工具、還要先破 §1 的 dump 關卡）；static-seed / 繞過 digest 才是所有人實際在走的路。

---

## 6. 最務實的下一步（收斂到單一建議）

1. **先做 [mac-arm-auth-seed.md §4.4 的 `CC_SHA256_Update` hook](./mac-arm-auth-seed.md#44-路線-c-runtime-hook-cc_sha256_update-建議先試這條)。** 它**完全繞過本篇 §1–§2 的整條 dump/反組譯難路**：不必解密 `__text`、不必反組譯 arm64、不必寫 pattern。前置只需 §1.4 的重簽（加 `get-task-allow` + `disable-library-validation`），然後 `frida -f` attach 或 `DYLD_INSERT_LIBRARIES` 注一個 interpose dylib，攔 `_CC_SHA256_Update`，一次登入就能 dump 到 `sessionKey ‖ platformSeed`，末 16 bytes 即答案，且能用 server 已知 session key 當場閉環驗證。**投入產出比壓倒性最高。**
2. **若一定要看懂函式（例如要做 static-seed patch 或存證真值），才走 dump 路線**：用 **§1.1 的 Timac destructor 手法**（改 arm64 + fat slice）或 **§1.2 的 lldb `process save-core`** 取得解密後的 `__text`，再對 dump 重跑 [extraction 篇 §3](./mac-arm-auth-seed-extraction.md) 的 ADRP/xref 掃描器定位 `"WoW\0"`/`MacA` 的引用與 seed 函式。**這條需要一顆真正的反組譯器**（本機目前只有 `objdump`）。
3. **不要期待撿現成**：本篇已確認**沒有**任何 macOS WoW dumper / seed extractor / 萃取 writeup 可直接套用；能借的只有「手法」（Timac dump 流程、Arctium/wow-patcher 的 anchor 概念、fix-arxan 的 unwrap 原理），移植工作全部要自己做。
4. **拿到值以後**，比照 [mac-arm-auth-seed.md §6](./mac-arm-auth-seed.md) 寫進 `build_auth_key` 並在本 repo 記來源與方法——**因為公開世界沒有這個值，我們挖到就是第一手。** 若只是要「能登入」，繞過 digest 已達標，萃取真值屬 optional 的存證性工作。

---

## 7. 來源清單（本篇實際引用者）

**執行期 dump / 注入（macOS）：**
- Timac, *"Dump decrypted mach-o files"*, blog.timac.org, 2016-08-04.
- HackTricks, *macOS Memory Dumping* / *macOS Dyld Hijacking & DYLD_INSERT_LIBRARIES*.
- LLVM code review **D88387**（skinny corefiles for `process save-core`）.
- `Nightbringer21/fridump`；OWASP MASTG **MASTG-TOOL-0050**（frida-ios-dump）；`DerekSelander/symbol-interposing`.
- AFINE, *"To Allow or Not to get-task-allow"* / *"Task Injection on macOS"*；`malwarewerewolf.com`, *Inject code in macOS processes with Frida*.

**Arxan / 加殼：**
- `pr701/fix-arxan`（GitHub README）.
- me3, *"Reversing Arxan (GuardIT)"*, me3.help.

**WoW 社群 / 工具：**
- wowdev.wiki（`CMD_AUTH_LOGON_CHALLENGE` 等）；`arctium.io` 與 Arctium/WoW-Launcher mirrors；`WowLegacyCore/HermesProxy`；`wowemulation-dev/wow-patcher`；`agatho/ida-wow-analyzer`；`samwhosung/wow-1121-client-internals`；`Kelsidavis/WoWee`；`WowDevTools`；OwnedCore *WoW Memory Editing* 版。
- TrinityCore 社群論壇, *"Arctium Launcher (Mac)"* 串（歷史性 `task_for_pid` 記錄）。

> 社群論壇（OwnedCore、TrinityCore forum、RE Discord）之陳述已於文中標記為社群來源；其餘為 repo 原始碼／README／作者部落格／wiki 等一手來源。
