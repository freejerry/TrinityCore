# BlizzardBrowser 是否為 x86_64-only、是否需要 Rosetta 2，以及它與 in-game Battle.net 登入流程的關係

> 撰寫日期：2026-09-06
> 相關筆記：[macOS client 取得與執行](./macos-client-options.md)、[3.3.5a Mac client 在 Apple Silicon 上](./mac-client-3.3.5a-on-apple-silicon.md)、[bnetserver client 設定與憑證](./tc-client-setup-and-certs.md)、[CASC 打包與 mirror](./casc-packaging-and-mirrors.md)、[在 TrinityCore 上跑「WotLK Classic」](./wotlk-classic-on-modern-client.md)
> 本機環境：Apple M3 Max（`uname -m` = `arm64`），Rosetta 2 **已安裝**（`pkgutil --pkgs` 有 `com.apple.pkg.RosettaUpdateAuto`，`/Library/Apple/usr/libexec/oah/` 存在）
> 受測對象：
> - A = 我們自 CASC install manifest 抓下的 WoW Classic `3.4.3.54261`（`/Users/shinichi/World of Warcraft 3.4.3.54261/`）
> - B = Battle.net 正式安裝的 WoW Classic `5.5.4.69585`（MoP Classic，`/Applications/World of Warcraft/`，`.build.info` 實測）
> 一手來源：本機二進位檔實測（`lipo` / `file` / `otool` / `codesign` / `strings` / `arch` / `PlistBuddy`）、Apple Developer Documentation、Apple Support、TrinityCore `master` checkout 原始碼。社群來源一律標記。
> 未取得一手來源者：Blizzard 官方**從未**發布過「哪些元件是 native、哪些不是」的說明頁（見第 2 節），本篇該部分只能以二進位實測 + 社群回報呈現。

---

## 0. 三句話結論

1. **是的，BlizzardBrowser 是 x86_64-only，在 Apple Silicon 上必然透過 Rosetta 2 執行。** 這不只是 `lipo` 的判讀——它內嵌的是 **CEF 83.0.0.0（Chromium branch 4103）**，而 CEF 要到 M87 才能 cross-compile arm64、M93 才能在 Apple Silicon 上原生建置，**CEF 83 在時間上根本不可能有 arm64 版本**。
2. **arm64 parent 生 x86_64 child 完全合法。** Apple 的限制是「同一個 *process* 內不能混 arm64 與 x86_64」，而非跨 process。實測 `arch -x86_64` 從 arm64 shell 生出的 child `sysctl.proc_translated` = `1`。
3. **BlizzardBrowser 壞掉 / 不存在，不會擋住 TrinityCore 的登入。** 決定性證據：SRP/JSON 登入協定的字串（`srp_url`、`LOGIN_FORM`、`server_evidence_M2`、`public_B`、`account_name`…）**全部在遊戲主程式裡**，**完全不在** BlizzardBrowser 或 CEF framework 裡。登入表單是遊戲自己的 Glue UI 畫的。

---

## 1. 實測：架構、版本、簽章

### 1.1 `lipo -info` 全表（本機實測）

| 檔案 | Install A（3.4.3.54261） | Install B（5.5.4.69585） |
|---|---|---|
| `World of Warcraft Classic.app/Contents/MacOS/World of Warcraft Classic` | **Non-fat: `arm64`**（純 arm64，連 x86_64 都沒有） | fat: `x86_64 arm64` |
| `Utils/BlizzardBrowser.app/Contents/MacOS/BlizzardBrowser` | **Non-fat: `x86_64`** | **Non-fat: `x86_64`** |
| `.../Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework` | （同下）`x86_64` | **Non-fat: `x86_64`** |
| `.../Frameworks/BlizzardBrowser Helper.app/Contents/MacOS/BlizzardBrowser Helper` | `x86_64` | **Non-fat: `x86_64`** |

`file` 的輸出一致：`Mach-O 64-bit executable x86_64`。四個 CEF helper（`Helper`、`Helper (GPU)`、`Helper (Renderer)`、`Helper (Plugin)`）皆同。

> **值得單獨標記的一條**：Install A（我們用 CASC OSX tag 抓的 3.4.3）的遊戲主程式是 **arm64 non-fat**，不是 universal。也就是說在這個 install 上，**一定**是 arm64 parent 去 spawn x86_64 child——不存在「整個 app 一起被 Rosetta 翻譯」這種可能性。

### 1.2 BlizzardBrowser 的 Info.plist（兩個 install 完全相同）

```
CFBundleIdentifier    = com.blizzard.bnl.browser
CFBundleShortVersionString = 5.2.9
CFBundleVersion       = 5.2.9
NSHumanReadableCopyright = (C) 2017-2020 Blizzard Entertainment, Inc. All rights reserved.
DTSDKName             = macosx10.15
DTSDKBuild            = 19G68
DTXcode               = 1170   (Xcode 11.7)
BuildMachineOSBuild   = 19H2   (macOS 10.15.7)
LSMinimumSystemVersion = 10.7
LSBackgroundOnly      = true
LSUIElement           = true
```

**2020 年用 macOS 10.15 SDK + Xcode 11.7 建的東西，一路原封不動被塞進 2026 年的 client**。Apple Silicon 於 2020-11 上市；這顆 binary 的建置環境早於或緊貼那個時間點，且此後沒有再 rebuild 過。

`LSBackgroundOnly` / `LSUIElement` 皆為 `true`：它是無 Dock icon 的背景 helper，由遊戲主程式啟動、以 shared memory 溝通（見 1.4）。

### 1.3 內嵌的 CEF 版本（決定性）

`Contents/Frameworks/Chromium Embedded Framework.framework/Resources/Info.plist`：

```
CFBundleShortVersionString = 83.0.0.0
SCMRevision  = ce7134bb3d95141cd18f1e65772a4247f282d950-refs/branch-heads/4103@{#694}
DTSDKName    = macosx10.15
DTXcode      = 1131   (Xcode 11.3.1)
CFBundleIdentifier = org.chromium.ContentShell.framework
```

`branch-heads/4103` = **Chromium M83**。

CEF 專案自己記錄的 macOS arm64 時程（社群/專案 issue tracker，非 Apple 一手；原 Bitbucket issue `chromiumembedded/cef#2981` 現已 404，內容經搜尋結果彙整）：

| 能力 | 最早支援的 milestone |
|---|---|
| 在 M1 上以 Rosetta 2 執行 | M86 |
| 在 M1 + DTK 上以 Rosetta 2 執行 | M87 |
| 自 Intel host cross-compile `target_cpu="arm64"` | M87（需 macOS 11 SDK + Xcode 12.2） |
| 在 Apple Silicon 上原生建置 | M93 |

**CEF 83 < M86**。所以 BlizzardBrowser 內嵌的這份 CEF **連「在 Apple Silicon 上跑」都不是它當初的設計目標**，遑論 arm64 原生。這是本篇最硬的一條技術結論：不是 Blizzard 「還沒轉」，而是這顆 5.2.9 helper 從 2020 起就凍結在那裡。

### 1.4 遊戲主程式怎麼用它（`strings` 實測，Install B）

遊戲主程式內有 Blizzard 內部 build server 的原始碼路徑，直接洩漏了模組結構：

```
/Volumes/Data/BuildServer2/PremakePackageCache/bnl_scene_browser/5.2.9-wow1/source/client/BrowserClientDesktopImpl.cpp
/Volumes/Data/BuildServer2/PremakePackageCache/bnl_checkout/5.3.6/source/client/CheckoutWindow.cpp
/Volumes/Data/BuildServer2/PremakePackageCache/bnl_scene/3.2.1/source/client/SceneWindowOutImpl.cpp
/Volumes/Data/BuildServer2/PremakePackageCache/bnl_scene/3.2.1/source/shared/MessageShmem.cpp
/Volumes/Data/BuildServer2/PremakePackageCache/bnl_shmem/3.0.4/src/Shmem.cpp
/Volumes/Data/BuildServer2/checkouts/0/Engine/Source/Frame/CSimpleBrowser.cpp
/Volumes/Data/BuildServer2/checkouts/0/Engine/Source/WowBrowser/DomainAccess.cpp
```

注意 `bnl_scene_browser/**5.2.9**-wow1`——與 BlizzardBrowser.app 的 `CFBundleShortVersionString = 5.2.9` 完全對上，證明兩者是同一組件的 client / helper 兩端。

其他相關字串：

```
BNL_Browser        BNL_Checkout       BNL_Scene       BNL_Scene_Checkout
BlizzardBrowser    BlizzardBrowser/   BlizzardBrowser Count = %d
failed to create browser.       failed to create content browser.
failed to create navbar browser.
[onBrowserDisconnectReason] callback not assigned.
bnl::browser::CertificateInfo   bnl::browser::Cookie   bnl::browser::JSVariable
WowBrowser::CDomainAccess::{AccessTableEntry,DomainIndexEntry,SchemeIndexEntry,PortIndexEntry,...}
CSimpleBrowser::Context::AllowlistEntry
BrowserEvents::SimpleBrowserSocialCallbackInvokedEvent
```

可讀出的架構（部分為我的推論，已標記）：

- 溝通機制是 **shared memory + message frame**（`bnl_shmem`、`MessageShmem`、`FrameReader`、`BufferWriter`、`SceneWindowOutImpl`）——CEF 以 offscreen rendering 把畫面寫進 shmem，遊戲當成一張貼圖（`browserTile`）畫在 UI 上。**（推論，但字串組合幾乎不留其他解釋空間）**
- `BNL_Checkout` / `CheckoutWindow` / `navbar browser` / `content browser` → **遊戲內商城（in-game shop）** 是它的主要消費者。
- `WowBrowser::CDomainAccess` + `CSimpleBrowser::Context::AllowlistEntry`（含 scheme / port / domain / directory / filename 五種 index）→ 存在一套 **URL allowlist**，可載入的網域受限。**（一手：字串存在；allowlist 實際內容無法由 `strings` 靜態取出）**
- `SimpleBrowserSocialCallbackInvokedEvent` → 社群分享 / 招募好友類功能。

---

## 2. Blizzard 官方說了什麼、沒說什麼

**一手（Blizzard 自己）**：
- WoW 於 **patch 9.0.2（2020-11-17，與 M1 MacBook Air 同日）** 取得 Apple Silicon 原生支援，Blizzard 表示 *"We're pleased to have native day one support for Apple Silicon."* 並提醒這是 day-one 支援、請回報問題。這是**針對遊戲主程式**的敘述。

**明確的空白（重要）**：
- 我**找不到任何** Blizzard 一手頁面（support KB、patch notes、Battle.net release notes）說明 `Utils/` 下的 helper（BlizzardBrowser、Blizzard Error）是否為 native。Blizzard 從未逐元件揭露。
- Battle.net 桌面應用程式本身是否 native，同樣**沒有**官方聲明。

**社群回報（明確標記為非一手）**：
- Blizzard 官方論壇 *Mac Technical Support* 上（2026-06 前後）有玩家指出 Battle.net app 仍為 Intel/x86、需經 Rosetta 2 執行；**該串無任何 blue post 回覆**，Blizzard 未表態。
- 2024-12 有媒體（blizzardwatch）以「Blizzard 悄悄地棄養 Mac 支援」為題報導，屬評論性二手來源。
- 2026-01 有回報指出某次 Blizzard 更新在 M4 上觸發 Rosetta 2 deadlock（CodeWeavers 判定為 Rosetta 翻譯層問題）。與本題相關但非同一元件。

> 結論：**「BlizzardBrowser 是 x86_64-only」這件事有一手證據（本機二進位），但那是我們自己量的，不是 Blizzard 說的。** 任何宣稱「Blizzard 官方承認 XX 不是 native」的說法都應視為未經證實。

---

## 3. x86_64-only helper 在 Apple Silicon 上到底發生什麼事

### 3.1 Apple 的規則（一手：Apple Developer Documentation）

*About the Rosetta translation environment*：

> "If a macOS binary contains only Intel instructions, macOS automatically launches Rosetta and begins the translation process. When translation finishes, the system launches the translated executable in place of the original."

> "The system prevents you from mixing `arm64` code and `x86_64` code in the same process. Rosetta translation applies to an entire process, including all code modules that the process loads dynamically."

同頁另載明 Rosetta 的存續期程：

> "Rosetta was designed to make the transition to Apple silicon easier, and will be available through macOS 27 — as a general-purpose tool for Intel apps to help developers complete the migration of their apps."
> "Beyond this timeframe, we will keep a subset of Rosetta functionality aimed at supporting older unmaintained gaming titles, that rely on Intel-based frameworks."
> "macOS 27 directly integrates support for Intel binary translation, without needing to install Rosetta."

**對本題的意義**：Rosetta 以 **process** 為單位。BlizzardBrowser 是獨立 process，被整包翻譯；遊戲主程式仍原生跑 arm64。兩者互不影響。而 Apple 明講會為「依賴 Intel framework 的舊遊戲」保留部分 Rosetta 功能——WoW 的這顆 helper 正好落在那個描述裡。

### 3.2 Rosetta 沒裝會怎樣（一手：Apple Support HT / 102527）

Apple Support *Using Intel-based apps on a Mac with Apple silicon*：

> 連上網路後開啟任一 Intel app；若 Rosetta 尚未安裝，系統會**詢問是否安裝**。按「安裝」並輸入 macOS 使用者名稱與密碼即可。若當下選「稍後」，下次再開啟需要 Rosetta 的 app 時會**再次詢問**。Rosetta 不是使用者會去互動的 app，它在背景自動運作。

也就是 **macOS 會提示，不會靜默失敗**——前提是走 GUI 啟動路徑。

**但**：BlizzardBrowser 不是使用者點開的，是遊戲主程式在背景 spawn 的。若翻譯不可用，spawn 端拿到的是 **`EBADARCH`**。本機可直接複現這個錯誤（強制以 arm64 執行）：

```
$ arch -arm64 ".../BlizzardBrowser.app/Contents/MacOS/BlizzardBrowser"
arch: posix_spawnp: .../BlizzardBrowser: Bad CPU type in executable
```

「Bad CPU type in executable」正是 Rosetta 缺席時該 spawn 會得到的訊息。屆時遊戲端會落到 `failed to create browser.` 這條路徑（字串已在主程式中，見 1.4）——**遊戲不會崩，只是 browser 功能失效**。**（後半句為推論：字串存在證明有錯誤處理路徑，但無法靜態證明它一定不致命；第 4 節會用另一條證據補上。）**

### 3.3 arm64 parent 能不能 spawn x86_64 child——實測

```
$ uname -m
arm64
$ /usr/sbin/sysctl -n sysctl.proc_translated          # 原生 shell
0
$ arch -x86_64 /usr/sbin/sysctl -n sysctl.proc_translated   # 從同一個 arm64 shell 生出的 child
1
$ arch -x86_64 /usr/bin/true ; echo $?
0
```

**可以。** `arch(1)` 內部即以 `posix_spawn` 搭配 `POSIX_SPAWN_SETEXEC` + `cpu_type` attribute（`posix_spawnattr_setbinpref_np`）指定 child 的 CPU type；child 是全新 process，因此不違反「同 process 不得混架構」。Rosetta daemon `oahd` 在本機常駐（`pgrep -l oahd` → `712 oahd`）。

實際啟動 BlizzardBrowser 本體（Install B）在本機可成功 `exec`（不因架構失敗；它因缺少 parent 傳入的 shmem/IPC 參數而立即自行結束，stdout/stderr 皆空）。

---

## 4. 登入流程：表單到底是誰畫的

### 4.1 TrinityCore 端做了什麼（一手：本 repo `master`）

`src/server/bnetserver/Services/AuthenticationService.cpp:241`（V1）與 `:335`（V2）——logon 成功後送出 external challenge：

```cpp
externalChallenge.set_payload_type("web_auth_url");
externalChallenge.set_payload(Trinity::StringFormat("http{}://{}:{}/bnetserver/login/",
    !SslContext::UsesDevWildcardCertificate() ? "s" : "",
    sLoginService.GetHostnameForClient(_session->GetRemoteIpAddress()), sLoginService.GetPort()));
```

client 拿著這個 URL 去打 `LoginRESTService`。`REST/LoginRESTService.cpp:169-178` 的 `HandleGetForm`：

```cpp
JSON::Login::FormInputs form = _formInputs;
form.set_srp_url(Trinity::StringFormat("http{}://{}:{}/bnetserver/login/srp/", ...));
context.response.set(boost::beast::http::field::content_type, "application/json;charset=utf-8");
context.response.body() = ::JSON::Serialize(form);
```

回的是 **`application/json`**，不是 HTML。表單定義在 `LoginRESTService.cpp:107-125`：

| `input_id` | `type` | `label` | `max_length` |
|---|---|---|---|
| `account_name` | `text` | `E-mail` | 320 |
| `password` | `password` | `Password` | 128 |
| `log_in_submit` | `submit` | `Log In` | — |

schema 見 `src/server/proto/Login/Login.proto`：`FormType.LOGIN_FORM = 1`、`FormInputs{type, inputs, srp_url, srp_js}`、`SrpLoginChallenge{version, iterations, modulus, generator, hash_function, username, salt, public_B, ...}`、`LoginResult{authentication_state, error_code, error_message, url, login_ticket, server_evidence_M2, next_url}`。

也就是說：**TC 給的是一份「請你自己畫這三個欄位」的 JSON 描述 + 一個做 SRP 的 endpoint**，不是一頁網頁。若 client 端只有 CEF 一條路可走，這份 JSON 會被當成純文字顯示——不可能形成可用的登入畫面。

### 4.2 決定性的二進位證據

在 Install B 的遊戲主程式 vs BlizzardBrowser / CEF 中，逐字（`strings -a | grep -x`）比對這組協定字串：

| 字串 | 遊戲主程式 | BlizzardBrowser | CEF framework |
|---|:--:|:--:|:--:|
| `srp_url` | ✅ | ❌ | ❌ |
| `LOGIN_FORM` | ✅ | ❌ | ❌ |
| `server_evidence_M2` | ✅ | ❌ | ❌ |
| `login_ticket` | ✅ | ❌ | ❌ |
| `public_B` | ✅ | — | — |
| `hash_function` | ✅ | — | — |
| `authentication_state` | ✅ | — | — |
| `account_name` / `password` | ✅ | — | — |
| `input_id` / `inputs` | ✅ | — | — |
| `platform_id` / `error_code` / `next_url` | ✅ | — | — |

**整套 `Battlenet.JSON.Login` 協定的欄位名，只存在於遊戲主程式；BlizzardBrowser 與 CEF 一個都沒有。**

結論（一手證據支撐）：**in-game Battle.net 登入表單是遊戲自己的 Glue UI 渲染的，SRP 也是遊戲自己算的。** BlizzardBrowser 在這條路徑上不參與。

### 4.3 那 BlizzardBrowser 到底負責什麼

依 1.4 的字串證據：**遊戲內商城 / checkout（`BNL_Checkout`、`CheckoutWindow`、`navbar browser`、`content browser`）、社群分享、以及其他受 allowlist 限制的網頁內容**。

**推論（非一手）**：在對接 Blizzard 正式伺服器時，`web_auth_url` 若回的是真正的 Battle.net 網頁登入頁（含 Sign in with Apple、雙因素、Cloudflare 挑戰等），client 很可能改走 CEF 渲染；native 表單路徑則是 content-type 為 JSON 時的分支。這解釋了為何兩條路徑同時存在。**我無法以靜態分析證實這個 content-type 分支**，但它是唯一能同時解釋「JSON 協定在主程式」與「CEF 仍被隨包附上」的模型。

**對私服的實際意義**：TrinityCore（以及任何沿用其 LoginREST 形狀的 emulator）只會走 JSON / native 表單那條。因此——

> **BlizzardBrowser 損毀、缺檔、簽章失效，甚至整個 `Utils/BlizzardBrowser.app` 被刪除，都不會阻止你登入 TrinityCore。** 代價是遊戲內商城與網頁類 UI 失效，而那些在私服上本來就不會運作。

---

## 5. 已知問題與簽章狀態

### 5.1 本機複現的簽章問題（原創發現，未見公開回報）

Install **B**（Battle.net 正式安裝的 5.5.4.69585）：

```
$ codesign -dv --verbose=4 ".../BlizzardBrowser.app"
Identifier=com.blizzard.bnl.browser
Format=app bundle with Mach-O thin (x86_64)
Authority=Developer ID Application: Blizzard Entertainment, Inc. (G847MC6JZ5)
Authority=Developer ID Certification Authority
Authority=Apple Root CA
Timestamp=Jun 9, 2023 at 1:15:57
TeamIdentifier=G847MC6JZ5

$ codesign --verify --deep --strict --verbose=2 ".../BlizzardBrowser.app"
... a sealed resource is missing or invalid
In subcomponent: .../Chromium Embedded Framework.framework
file missing: .../Chromium Embedded Framework.framework/Resources/devtools_resources.pak
```

Install **A**（我們用 CASC manifest 抓的 3.4.3.54261）：

```
$ codesign --verify --deep --strict --verbose=2 ".../BlizzardBrowser.app"
... : valid on disk
... : satisfies its Designated Requirement
```

**反直覺但實測如此**：**Battle.net 官方安裝的那份 deep 驗證失敗，我們自 CASC 抓的那份反而完整通過。** 成因（推論）：Battle.net 安裝器依 tag 過濾檔案，把 CEF 的 devtools 資源檔略去以省空間，而該檔在 2023-06 的簽章 seal 內；我們從 install manifest 全量拉取則無此裁切。

同時注意簽章 timestamp 是 **2023-06-09**——bundle 內容自那時起未變（binary 本身則是 2020 年建的）。

搜尋結果中**找不到**任何針對 BlizzardBrowser / `devtools_resources.pak` 的公開回報；`a sealed resource is missing or invalid` 本身是常見的 macOS 簽章錯誤（見 Apple Developer Forums 與 eclecticlight 的通論文章），但與此 bundle 的關聯是本機首次記錄。

### 5.2 「ad-hoc 重簽」值不值得做

**推論，非文件事實**：不值得，且在本專案脈絡下沒有必要。理由：

1. deep 驗證失敗的是 `devtools_resources.pak` 這種純資源檔，**不影響 `exec`**——Gatekeeper 在首次啟動時做的是 bundle 的 primary signature 檢查，而 primary signature（如 5.1 所示）是有效的；本機也確實成功啟動了它。
2. `codesign -f -s -` ad-hoc 重簽會**丟掉 Developer ID 與 notarization**，把一個 Apple 公證過的 bundle 降級成 ad-hoc。在 Gatekeeper 更嚴的情境下反而更容易被擋。
3. 依第 4 節，這個 helper 對 TrinityCore 登入毫無影響。**為它做任何修補都是在解一個不存在的問題。**
4. 若真的想要「乾淨」：把缺的 `devtools_resources.pak` 從 CASC 全量 install（Install A）補回去，即可讓 deep 驗證通過，且**不動簽章**。這比重簽安全得多。

### 5.3 其他已知 Apple Silicon 相關回報（皆為社群來源）

- Blizzard 官方論壇有「Apple Silicon — WoW Crashing on connect under macOS Sonoma (14.0)」等串；成因未經官方確認。
- 2026-01 前後回報：某次 Blizzard 更新於 M4 觸發 Rosetta 2 deadlock，CodeWeavers 判定為翻譯層問題。此為 Rosetta 本身的 bug，非 BlizzardBrowser 特有。
- 舊 WoW client（3.3.5a 等）在 Apple Silicon 上的獨立議題見 [3.3.5a Mac client 在 Apple Silicon 上](./mac-client-3.3.5a-on-apple-silicon.md)，與本篇不同層次（那是整包 x86_64 遊戲，本篇是 arm64 遊戲 + x86_64 helper）。

---

## 6. 對本專案的可執行結論

1. **不要把 BlizzardBrowser 列入 client 部署檢查清單。** 它與 TrinityCore 登入無關（第 4 節，一手證據）。
2. **不要為它 ad-hoc 重簽。** 見 5.2。若強迫症發作，補檔（`devtools_resources.pak`）優於重簽。
3. **Rosetta 2 仍需保留在開發機上**——不是為了 BlizzardBrowser，而是為了 Battle.net 桌面應用程式（社群回報仍為 x86_64）與其他 x86_64 工具鏈。Apple 已宣告 Rosetta 一般用途支援至 **macOS 27**，之後只保留「支援依賴 Intel framework 的舊遊戲」的子集（第 3.1 節，一手引文）。
4. **若目標 client 是 Install A 那種 arm64-only 主程式**，任何 x86_64 helper 都必然跨架構 spawn。這在技術上完全合法（第 3.3 節實測），但也代表：**Rosetta 一旦缺席，這些 helper 一律 `EBADARCH`，而遊戲本體照跑**。這對我們是好消息——私服路徑的相依性更少了。
5. **待驗證（本篇未能證實）**：real-server 情境下 client 是否依 `Content-Type` 在 native 表單與 CEF 網頁登入之間分支（4.3 的推論）。要證實需動態分析或抓包對接正式伺服器，超出本次唯讀範圍。
