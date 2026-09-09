# `wowemulation-dev/wow-patcher` runtime mode 評估 —— 兼 `reason 24` 斷線根因定位

> 撰寫日期：2026-09-04
> 相關筆記：[TrinityCore 現代架構的 client 設定與憑證](./tc-client-setup-and-certs.md)、[HermesProxy 決策級評估](./hermesproxy-evaluation.md)
> 來源限定 primary sources：本機 `wow-patcher` clone（`3be782f`，唯讀）、`Burralis/Game-Launcher`（原 Arctium，**MIT，開源**）的 GitHub 原始碼、本機 TrinityCore `origin/wotlk_classic` 與 `origin/master`（唯讀 git）、本機 HermesProxy `feature/wotlk-classic-v3.4.3` 原始碼、**本機 3.4.3.54261 client 二進位實測**（唯讀，`WowClassic.exe`，50,589,832 bytes）、`gh api`、Microsoft 官方文件。
> 未使用瀏覽器自動化。凡未實測者一律標示「**未驗證**」。

---

## 0. 裁決先講

**`wow-patcher` 是對的工具，但要用的不是 `launch`（runtime mode），而是它預設的靜態 `execute` 路徑——而且它的 `ed25519` patch group 正是我們缺的那一塊。**

三條互相獨立、全部實測過的證據串起來：

1. **TrinityCore 用來簽 `SMSG_ENTER_ENCRYPTED_MODE` 的 Ed25519 私鑰是 `08 BD C7 A3 … A7 C9`**（`origin/wotlk_classic` 與 `origin/master` 同一顆）。我用 Python `cryptography` 由該私鑰推導出的公鑰是：
   ```
   02596F0D 0C061A8B 30745988 FD72C59E 29EC367F B0F341F2 8E0F08D0 37BAFC69
   ```
2. **這顆公鑰逐位元組等於 `wow-patcher` 的 `CRYPTO_ED25519_PUBLIC_KEY`**（`src/trinity/mod.rs:20`），也逐位元組等於 **Arctium/Burralis 的 `Patches.Common.CryptoEdPublicKey`**（`src/Patches/Common.cs`）。
3. **我們手上的 3.4.3.54261 client 裡烤的是 Blizzard 原廠公鑰，不是這顆。** 實測 `WowClassic.exe`：
   | 常數 | 檔案 offset | section | RVA |
   |---|---|---|---|
   | Ed25519ctx context `A71FB69B C97CDD96 E9BBB821 398D5AD4` | `0x27B2D48` | `.rdata` | `0x27B4348` |
   | **Blizzard 原廠 Ed25519 public key `15D618BD 7DB577BD 9A8D4576 9C59E4FC 631633BF 447398A4 B489B4C2 6FBC03AD`** | **`0x27B2D58`** | **`.rdata`** | `0x27B4358` |
   | `EnableEncryptionSeed`（16 bytes）`909CD050 5A2C14DD 5C2CC064 14F3FEC9` | `0x27B2DC8` | `.rdata` | `0x27B43C8` |
   | ConnectTo RSA modulus 前 8 bytes `91D59BB7D4E183A5` | `0x27221B0` | `.rdata` | `0x27237B0` |

   而 TrinityCore 的 `02596F0D…` 在整個 binary 中出現 **0 次**。

**結論**：HermesProxy 用 TrinityCore 的私鑰簽章，client 卻拿 Blizzard 的公鑰去驗——**Ed25519 驗證必定失敗**，client 立刻送 `CMSG_LOG_DISCONNECT`。這就是 `reason 24`。這不是 opcode、不是 seed、不是 TLS、不是 build seed 的問題，是**一顆 32 bytes 的公鑰沒被換掉**。

**修法**：把 `.rdata` offset `0x27B2D58` 起的 32 bytes 改寫成 `02596F0D…37BAFC69`。這正是 `wow-patcher --patches ed25519`（或 `all`）做的事，也正是 Arctium 唯一真正跟這個 bug 有關的動作。

**唯一的障礙是 `wow-patcher` 自己的一個錯誤判斷**（第 2.2 節）：它把 `ClientType::Classic` 硬編碼為「不使用 Ed25519」，所以在我們的路徑上直接跳過，印出 `Ed25519 public key not used by Classic clients`。這個判斷是從 **1.13.2.31650**（2019 年的 build）逆向得到的，對 **3.4.3.54261 是錯的**——上表的實測直接反證。繞過方式有兩種，都不需要改它的原始碼（第 2.3 節）。

---

## 1. `launch` subcommand 的解剖

### 1.1 它做什麼（`src/cmd/launch.rs`，1,037 行，整檔包在 `#[cfg(target_os = "windows")] pub mod win`）

檔頭註解逐字：

> Runtime patcher: launch Wow.exe suspended, wait for Arxan to decrypt the .text section, apply patches via WriteProcessMemory, resume.
> …
> Apply order is taken from Arctium-WoW-Launcher's `Launcher.cs`

流程（`launch_and_patch()`）：

1. `CreateProcessA(..., CREATE_SUSPENDED, ...)`
2. `NtResumeProcess`（讓 kernel 把 PE image map 進來）
3. `wait_for_memory_init()`：輪詢 `VirtualQueryEx` 直到 image base region 的 `RegionSize > 0x1000`
4. `NtSuspendProcess`
5. **Phase A**：掃 base 起 256 MiB 的已 commit region，對命中處 `WriteProcessMemory`
6. `NtResumeProcess`（讓 Arxan 的 TLS callback 跑）
7. **Phase B**（僅 `--legacy-cert-mode`）：等 Arxan 解密 `.text` → 再 suspend → 對 `.text` 打 code patch → 最終 resume

### 1.2 逐項 patch 清單

**Phase A（`.rdata` 資料槽，永遠套用，不受 `--patches` 控制）**

| label | pattern（前 8 bytes） | 寫入內容 |
|---|---|---|
| `RSA ConnectToModulus` | `91 D5 9B B7 D4 E1 83 A5` | 256-byte RSA modulus（預設 TrinityCore 的） |
| `Ed25519 public key` | `15 D6 18 BD 7D B5 77 BD` | 32-byte Ed25519 公鑰（預設 TrinityCore 的） |
| `BGS portal suffix` | `.actual.battle.net\0` | `--bgs-portal-domain` 指定的 domain |
| `Cert bundle URL` | `http://nydus.battle.net/Bnet/zxx/client/bgs-key-fingerprint` | `--cert-bundle-url`（有給才做） |

**Phase A 額外項（僅 `--legacy-cert-mode`）**：`RSA SignatureModulus`（`35FF17E733C4D3D4`）、`RSA CryptoRsaModulus`（`71FDFA60140DF205`）、`Cert bundle envelope`（`{"Created":`，≤32,761 bytes）。

**Phase B（`.text` code patch，僅 `--legacy-cert-mode`）** —— 這些就是「停用檢查」的部分：

| label | 動作 |
|---|---|
| `Integrity (primary encoding)` / `(alt encoding)` | `replace_prologue_with_ret0`：把函式序言改成 `ret 0`，整個 integrity check 廢掉 |
| `CertBundle branch (NOP JZ)` | `replace_first2_with_nop_pair`：把 JZ 換成兩個 NOP |
| `CertCommonName (force AL=1)` | `replace_jne_pair_with_movb_al_1`：強制 CN 比對回傳 true |
| `CertChain (force BL=1)` | `replace_first6_with_movb_bl_1`：強制憑證鏈驗證回傳 true |

**重要**：`--legacy-cert-mode` 這一整塊的效果是**繞過 TLS 憑證驗證**（等同我們用 SAN 自簽憑證 + 匯入 CA 已經解掉的問題），**不是**繞過 `SMSG_ENTER_ENCRYPTED_MODE` 的簽章驗證。**整個 repo 裡沒有任何一處碰 `SMSG_ENTER_ENCRYPTED_MODE` 的 handler 或連線 state machine**（全域 grep `EnterEncryptedMode` / `12361` / `14183` 零命中）。它處理該封包的唯一方式，就是把 client 用來驗簽的那顆 Ed25519 公鑰換掉——這在 Phase A，不在 Phase B。

### 1.3 `--patches` 對 `launch` 無效（實測）

`src/cli.rs:495-509`：`parse_patch_groups(&cli.patches)` 只在**預設的靜態 patch 分支**被讀取。`Commands::Launch` 分支從不引用 `cli.patches`。也就是說 `launch` 一律套用它自己那組固定清單，`--patches ed25519` 在 `launch` 上是空操作（但也不會擋掉 Ed25519，因為 Phase A 無條件掃它）。

### 1.4 `launch` 在 Wine 上能不能跑

**需要的一切都只是普通的 Win32 user-mode API**，沒有 debugger privilege、沒有 `SeDebugPrivilege` 提權、沒有 `ptrace` 概念、不用 driver：

- `kernel32`：`CreateProcessA`、`CloseHandle`、`TerminateProcess`
- `Win32_System_Diagnostics_Debug`：`ReadProcessMemory`、`WriteProcessMemory`
- `Win32_System_Memory`：`VirtualQueryEx`、`VirtualProtectEx`
- `ntdll`（直接 `#[link(name = "ntdll")]`）：`NtSuspendProcess`、`NtResumeProcess`

Arctium/Burralis 用的是完全相同的一組（`src/Misc/NativeWindows.cs` + `src/IO/WinMemory.cs`），而 Arctium 在 Wine 上是被驗證過的既有實務。**推論（未實測）**：wow-patcher 的 `launch` 在 Wine 下應可運作。

**ISA 需求：沒有 AVX 疑慮，這是它相對 Arctium 的關鍵優勢。**

- `Cargo.toml`、`build.rs`、`.cargo/config.toml`、`.mise.toml` 全部**沒有** `target-feature` / `target-cpu` / `RUSTFLAGS` 設定（實測 `cat` 四個檔）。Rust 的 `x86_64-*` 預設 baseline 只到 **SSE2**。
- 全域 grep `avx` / `target_feature` / `is_x86_feature` 在 `src/` **零命中**。
- 相依樹（`Cargo.lock`）只有 `hex`、`goblin`、`bitflags`、`clap`、`windows-sys`（+ build-dep `chrono`、dev-dep `tempfile`），沒有 `ring` / `sha2-asm` / 任何 SIMD crate。
- **最重要的是：它是原生 Rust，不需要 .NET runtime。** Arctium 在本機失敗的訊息 `The required instruction sets are not supported by the current CPU` 是 **.NET runtime 的自檢**，不是 Arctium 自己的程式碼；wow-patcher 完全不經過那條路。

### 1.5 `dump-text` / `dump-sections` 不是前置條件

兩者都是**逆向分析輔助**：把 Arxan 解密後的 `.text`（或任意 section）從 process memory 讀出來存檔，供丟進 disassembler 用（`src/cmd/dump.rs`，732 行）。`launch` 不依賴它們——`launch` 自己內建 `wait_for_decryption()` 啟發式。對我們的目標（換一顆 `.rdata` 裡的公鑰）它們**完全無關**，可以不理。

---

## 2. `ed25519` patch group 到底做什麼

### 2.1 它就是簽章驗證那條路

`src/patterns/runtime/common.rs:30` 註解：

> First 8 bytes of the stock Ed25519 public key. Newer clients use this in addition to the RSA moduli

`docs/src/patches.md` 的說法含糊（只寫 `**Purpose**: Alternative signature verification`），但把三方原始碼並排就毫無疑義：

| 來源 | 值 | 角色 |
|---|---|---|
| TrinityCore `wotlk_classic` `AuthenticationPackets.cpp:250` `EnterEncryptedModePrivateKey` | `08BDC7A3…A7C9` | **簽 `SMSG_ENTER_ENCRYPTED_MODE` 的私鑰** |
| （由上式推導） | `02596F0D…FC69` | 對應公鑰 |
| `wow-patcher` `src/trinity/mod.rs:20` `CRYPTO_ED25519_PUBLIC_KEY` | `02596F0D…FC69` | **寫進 client 的替換值** |
| Arctium `src/Patches/Common.cs` `CryptoEdPublicKey` | `02596F0D…FC69` | 同上 |
| HermesProxy `AuthenticationPackets.cs` `Ed25519PrivateKey` | `08BDC7A3…A7C9` | 同 TrinityCore |

**`ed25519` group 的唯一用途，就是讓 client 接受 TrinityCore（以及照抄它的 HermesProxy）簽出來的 `SMSG_ENTER_ENCRYPTED_MODE`。** 它正對我們的失敗點。

**順帶更正 HermesProxy 原始碼的一句註解**（`AuthenticationPackets.cs`）：

> Private key and context are Blizzard constants; the client has the matching public key + context baked in.

**前半句是錯的。** `08BDC7A3…` 是 **TrinityCore 的模擬器金鑰**，不是 Blizzard 常數（Blizzard 不會外流私鑰）。context `A71FB69B…` 倒是真的 Blizzard 常數（實測存在於 client `.rdata` `0x27B2D48`）。這句錯誤註解正是「以為不用 patch client」的來源。

### 2.2 為什麼它在我們身上被跳過

`src/platform/mod.rs:43-50`（逐字）：

```rust
pub fn uses_ed25519(&self) -> bool {
    match self {
        ClientType::Retail | ClientType::Unknown => true,
        // Classic (1.13.x, 2.5.x, 3.4.x) and Classic Era do not embed
        // an Ed25519 public key. Verified via RE of Classic 1.13.2.31650:
        // the pattern (15 D6 18 BD...) is absent from the binary.
        ClientType::Classic | ClientType::ClassicEra => false,
    }
}
```

而 `detect_client_type()`（同檔 64-90 行）是**純字串比對**：路徑含 `_retail_` → Retail、含 `_classic_era_` → ClassicEra、含 `_classic_` → **Classic**、檔名含 `wowclassic` → **Classic**。

我們的路徑是 `…/World of Warcraft 3.4.3.54261/_classic_/WowClassic.exe`——**兩個條件都中**，判成 `Classic` → `uses_ed25519() == false` → `execute.rs:645` 印出 `ℹ Ed25519 public key not used by Classic clients` 並跳過。

**這個註解對 1.13.2 也許成立，對 3.4.3.54261 是錯的**：上面第 0 節的實測顯示 `15 D6 18 BD 7D B5 77 BD` 在 `.rdata` 出現 **恰好 1 次**。註解自己也承認來源只有一個 build 的 RE。Arctium 的做法可以佐證：它的 `Launcher.cs` 對 `CryptoEdPublicKey` 的 patch **不做任何 `GameVersion` 判斷**，五種 GameVersion 一律套用。

### 2.3 兩條繞過方式（都不用改 wow-patcher 原始碼）

**(a) 靜態 `execute`，騙過 `detect_client_type`** —— 最簡單，推薦先試：

把 `WowClassic.exe` 複製到一個**路徑不含 `_classic_`、檔名不是 `wowclassic*`** 的位置，例如 `/tmp/patch/Wow.exe`。`detect_client_type` 會走到「檔名 == `wow.exe`」→ 回傳 `Retail` → `uses_ed25519() == true` → Ed25519 patch 生效。輸出檔再改回 `WowClassic.exe` 放回原位。

註：patch 落在 `.rdata`，屬於 `docs/src/patches.md` 明列的 PE 可 patch section（`.rdata`, `.data`），不會被 section 檢查擋下。

**(b) `launch` runtime mode** —— Phase A 的 Ed25519 掃描**沒有任何 `ClientType` gate**（`launch.rs:237-249`，只檢查 `ed_key.len() == 32`），所以 `launch` 天生就會做這件事。代價是需要一顆 Windows 執行檔（第 3 節），且要在 Wine 裡跑（未實測）。

**不要加 `--legacy-cert-mode`**：那組 patch 是為了繞過 TLS 憑證驗證，而我們已經用 SAN 自簽憑證 + CA 匯入正規解掉了（見[憑證筆記](./tc-client-setup-and-certs.md)§6）。加上去只會多引入 `.text` 寫入與 Arxan 等待的風險。

---

## 3. 交叉編譯 Windows 執行檔

### 3.1 沒有官方預編譯產物（重新實測確認）

`gh api` 實測（2026-09-04）：

| 查詢 | 結果 |
|---|---|
| `repos/wowemulation-dev/wow-patcher/releases` | **`0`**（零筆） |
| `repos/wowemulation-dev/wow-patcher/tags` | **空** |
| `repos/wowemulation-dev/wow-patcher/actions/workflows` | **空**（repo 內也**沒有 `.github/workflows/` 目錄**，只有 `ISSUE_TEMPLATE/`） |
| repo metadata | `default_branch: main`、`license: Apache-2.0`、`stars: 20`、`archived: false`、`pushed_at: 2026-07-15T02:11:43Z` |

**這個專案完全沒有 CI、沒有 tag、沒有 release。** 只能自己編。README 也只教 `cargo build --release`。

### 3.2 本機已經編出來了

實測：`target/x86_64-pc-windows-gnu/release/wow-patcher.exe` **已存在**，且 `x86_64-w64-mingw32-gcc` 在 `/opt/homebrew/bin/`。所以 `x86_64-pc-windows-gnu` 這條路在本機已驗證可行。

沒有任何相依套件會擋 cross-compile：`windows-sys` 官方同時支援 `-gnu` 與 `-msvc`；唯一的 build-dependency `chrono` 跑在 host 端（`build.rs` 只用它產生 build 日期字串）；`goblin` / `hex` / `bitflags` / `clap` 皆為 pure Rust。

> 若要重編：`rustup target add x86_64-pc-windows-gnu` + `cargo build --release --target x86_64-pc-windows-gnu`（本機 `rustup target list --installed` 目前只顯示 `aarch64-apple-darwin`，但產物已在，推測是先前以 `cross` 或已移除的 target 編出的——**未驗證**編出當下的具體指令）。

---

## 4. Arctium 到底做什麼（一手來源，且它其實是開源的）

### 4.1 更正一個前提：Arctium 現在是 MIT 開源

`arctium.io/wow` 以 **HTTP 301** 轉址到 `burralis.io`。對應的 GitHub repo：

| 欄位 | 值（`gh api repos/Arctium/WoW-Launcher`，會自動導向） |
|---|---|
| `full_name` | **`Burralis/Game-Launcher`** |
| `license` | **MIT** |
| `stars` | 340 |
| `pushed_at` | 2026-08-30 |
| `archived` | false |

**所以「Arctium 是 closed-source」這個前提不成立**，我們可以直接讀它做了什麼。（`burralis.io` 首頁本身確實沒有文件化任何 flag，只寫 "Windows 10 and 11"、"Development and education only"。）

### 4.2 它實際套用的 patch：只有四項

`src/Launcher.cs` 的 `LaunchGame()`，`Task.WaitAll` 區塊逐字：

```csharp
memory.PatchMemory(Patterns.Common.ConnectToModulus, Patches.Common.RsaModulus, "ConnectTo RsaModulus"),
memory.PatchMemory(Patterns.Common.CryptoEdPublicKey, Patches.Common.CryptoEdPublicKey, "GameCrypto Ed25519 PublicKey"),
memory.PatchMemory(Patterns.Common.Portal, Patches.Common.Portal, "Login Portal"),
memory.PatchMemory(Patterns.Windows.LauncherLogin, Patches.Windows.LauncherLogin, "Launcher Login Registry")
```

（另有 `--versionurl` + `--cdnsurl` 同時給定時才做的 Version/CDN URL 改寫。）

**沒有 integrity NOP、沒有 cert chain / CommonName NOP、沒有任何 `.text` code patch。** 現行版本的 Arctium 比 wow-patcher 的 `--legacy-cert-mode` **少做**很多——它只改四個資料槽。

**而且它明確不繞過 TLS 驗證**：`Launcher.cs` 在啟動前自己用 `SslStream` 對 portal 做一次 TLS 預檢，憑證不受信任就印：

> Server with host name {HostName}:{Port} does not have a trusted certificate attached.
> If you are the server owner be sure to generate one and replace the default bnet server certificate.

→ **HermesProxy README 第 169 行那句「Arctium-launched clients skip certificate validation entirely」是錯的。** 我們先前做的 SAN 自簽憑證 + CA 匯入工作是必要且正確的方向，不是繞路。

### 4.3 `--staticseed` 不存在（於現行版本）

`src/LaunchOptions.cs` 的完整選項清單：`--version`（`GameVersion` enum：Retail / Classic / ClassicEra / ClassicAnniversary / ClassicTitan）、`--path`、`--binary`、`--keepcache`、`--versionurl`、`--cdnsurl`、`--product`、`--region`、`--portal`、`-config`。

**沒有 `--staticseed`。** HermesProxy README 第 58-61 行寫的 `--staticseed --version=Classic` 是**過時指令**（`TreatUnmatchedTokensAsErrors = false`，所以多打不會報錯，只是被忽略）。同時這也印證：per-build seed 從來就不是這個 stack 的變數——與先前已排除的結論一致。

### 4.4 我們真正需要複製的能力

| Arctium 的 patch | 我們的狀態 |
|---|---|
| ConnectTo RsaModulus | ✅ 已由 wow-patcher 的 `rsa` group 處理（且證實與本次失敗無關） |
| **GameCrypto Ed25519 PublicKey** | **❌ 缺這一項——就是 `reason 24` 的原因** |
| Login Portal（`.actual.battle.net`） | ✅ 我們用 `SET portal "127.0.0.1"` + SAN 憑證走等效路線 |
| Launcher Login Registry | 與 `-launcherlogin` 免密登入有關，我們用不到 |

**只差一項，而且 `wow-patcher` 有現成實作。**

---

## 5. 替代方案

| 專案 | 授權 / 狀態 | patch 什麼 | 在本機可行性 |
|---|---|---|---|
| **`wowemulation-dev/wow-patcher`** | Apache-2.0 / MIT，`main` 最後 push 2026-07-15，**0 release / 0 CI**，20★ | RSA modulus、**Ed25519 公鑰**、portal、version/cdns URL、cert bundle（+`launch` 的 `.text` NOP） | 🟢 **原生 Rust，無 .NET、無 AVX**；macOS arm64 直接跑靜態模式；Windows exe 已在本機交叉編出 |
| **`Burralis/Game-Launcher`**（原 Arctium） | **MIT，開源**，最後 push 2026-08-30，340★ | 上述四項 memory patch | 🔴 .NET 應用；本機在 Rosetta 2 下被 .NET runtime 以 `The required instruction sets are not supported by the current CPU` 擋下（AVX 缺失） |

**未找到其他值得列入的一手候選。** 兩者在功能上高度重疊，而 wow-patcher 是唯一能在本機環境跑起來的。（此為本次調查範圍內的結論；不排除有未被搜尋到的專案，**未窮盡驗證**。）

**關於「Windows-on-ARM VM 跑 Arctium」這條退路**：Microsoft 官方的 [How emulation works on Arm](https://learn.microsoft.com/en-us/windows/arm/apps-on-arm-x86-emulation) 頁面（`ms.date` 2025-11-06）**完全沒有提到 AVX/AVX2**，只說 Prism 是 24H2 引入的新模擬器。AVX/AVX2 支援的說法出自 Microsoft Tech Community 的 [Windows on Arm runs more apps and games with new Prism update](https://techcommunity.microsoft.com/blog/windowsosplatform/windows-on-arm-runs-more-apps-and-games-with-new-prism-update/4475631)，內容為 Prism 擴充支援 AVX、AVX2 與 BMI/FMA/F16C 等延伸，已推送至 Windows 11 24H2 以上的所有 WoA 裝置，64-bit x86 app 預設啟用、32-bit 需以相容性設定 opt-in。**我未在本機驗證任何 VM 行為。** 無論如何，既然 §0 已定位到根因，這條退路現在沒有必要。

---

## 6. 建議的下一步（依序）

1. **先做這一步**：把 `WowClassic.exe` 複製到 `/tmp/patch/Wow.exe`，執行
   `wow-patcher -l /tmp/patch/Wow.exe -o /tmp/patch/Wow-patched.exe --dry-run -v`
   確認輸出裡出現 `✓ Ed25519 public key → TrinityCore Ed25519 key (32 bytes)`（而非 `ℹ … not used by Classic clients`）。
   再去掉 `--dry-run` 實際產出，改名放回 `_classic_/`（保留原檔備份）。
2. 用 patch 過的 client 重跑整條流程。預期 `SMSG_ENTER_ENCRYPTED_MODE` 之後收到 `CMSG_ENTER_ENCRYPTED_MODE_ACK`（14183）而非 `reason 24`。
3. 若 (1) 因 section 檢查或其他理由失敗，退而使用交叉編出的 `wow-patcher.exe` 在 Wine 裡跑 `launch`（**不要**加 `--legacy-cert-mode`）。
4. 兩者都成功之後，值得回饋兩個上游 issue：
   - **`wowemulation-dev/wow-patcher`**：`ClientType::Classic → uses_ed25519() == false` 對 3.4.x 是錯的，附上本文 §0 的 offset 實測。
   - **`Xian55/HermesProxy`**：README 第 58-61 行的 `--staticseed` 已不存在；第 169 行「Arctium skips certificate validation entirely」與 `Launcher.cs` 的 TLS 預檢矛盾；`AuthenticationPackets.cs` 中「Private key … are Blizzard constants」的註解應更正為 TrinityCore 金鑰，並在文件中明確要求 client 必須 patch Ed25519 公鑰——這正是 `reason 24` 沒有被記錄過的原因（所有 `reason=7` 的回報者都用 Arctium，而 Arctium 默默做了這件事）。

---

## 7. 留給下一位的未驗證清單

- `wow-patcher` 的 `launch` 在 Wine 7.7 / macOS ARM 下是否真的能跑（Win32 API 面看沒問題，**未實測**）。
- 3.4.3 client 是否除了 `SMSG_ENTER_ENCRYPTED_MODE` 之外，還有第二處會驗這顆 Ed25519 公鑰（`WardenUpdateKey` 字串就緊接在該槽之後，`0x27B2D88`，**未追**）。
- HermesProxy 的 `HmacSha256` + 16-byte `EnableEncryptionSeed` 與 TrinityCore `wotlk_classic` 的 `HMAC_SHA512` + 32-byte seed（`66BE2979…`）不一致；client binary 只找得到 16-byte 那顆，**傾向 HermesProxy 是對的**，但未做端到端驗證。若換完公鑰仍失敗，這是第二個要查的點。
- HermesProxy 的 `EnterEncryptedMode.Write()` 沒有寫入 `int32 RegionGroup` 欄位，而 TrinityCore `wotlk_classic` 的順序是 signature → `int32 RegionGroup` → 1 bit Enabled。**未驗證** client 是否要求該欄位。若換完公鑰仍失敗，這是第三個要查的點。
