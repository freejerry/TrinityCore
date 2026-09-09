# WoW 3.3.5a 在 Whisky/Wine 下的 ERROR #132：到底缺哪些 Wine 依賴？（研究筆記）

> 撰寫日期：2026-09-03
> 相關筆記：[macOS / Apple Silicon 上玩 WotLK 內容](./macos-client-options.md)（**前置閱讀**，第 2 節是 CrossOver / Wine / GPTK 的裁決）、[3.3.5a 原生 Mac client 能不能在 Apple Silicon 上跑？](./mac-client-3.3.5a-on-apple-silicon.md)（§5.2 首次記錄 WoWSilicon）、[TrinityCore 官方 client 設定與憑證](./tc-client-setup-and-certs.md)
> 來源限定 primary sources：本機檔案實測（crash dump、`Logs/*.log`、Whisky 的 Wine 執行檔與 `.so`、prefix 的 `*.reg`）、WineHQ AppDB／Bugzilla（經 Wayback 快照，見「取用失敗」）、Blizzard 支援文件、各專案自己的 repo 與原始碼（WoWSilicon、DXVK、D9VK、MTLd3D、MoltenVK、Wine）、CodeWeavers 官方 blog。
> 凡未經驗證者一律標示「**未驗證**」。本文所有本機指令皆為唯讀，未修改 prefix、未執行 Wow.exe。

---

## 0. 一句話結論（TL;DR）

**這台機器的問題不是「少裝了某個 winetricks verb」。缺的東西只有一樣：一條能用的 D3D9 路徑，以及「不要用全螢幕」。**

檢查 prefix 後可以直接排除「缺 runtime」的假說 —— `msvcr80.dll` / `msvcp80.dll` / `d3dx9_24`～`d3dx9_43` / `wininet.dll` / `mshtml.dll` / `crypt32.dll` / `rsaenh.dll` / `bcrypt.dll` / `schannel.dll` **Wine 的 builtin 版本全部都在**（`~/.wow335-prefix/drive_c/windows/system32/`），而 `DllOverrides` 登錄機碼是**空的**。WineHQ AppDB 的 3.3.5a 條目**從頭到尾沒有提到任何一個 winetricks verb**。

真正的兩個問題，各自對應兩次執行：

| 執行 | 設定 | 失敗點 | 本機證據 |
|---|---|---|---|
| 第 1 次 | `GxApi: D3D9` | wined3d → macOS OpenGL，崩在 `ntdll` 的**堆疊探測迴圈**，回報 ERROR #132 | crash dump EIP `7BC24AB0` 的位元組是 `83 EC 04 / EB F3` |
| 第 2 次 | `SET gxApi "opengl"` | **全螢幕**的 WGL pixel format 談不攏 → `no output device available!` → 正常結束（所以沒有 crash dump） | `Logs/gx.log`（見 §1.2） |

**最省事、最可能直接解掉第 2 次失敗的一步**（且有第一方出處）：在 `WTF/Config.wtf` 加

```
SET gxWindow "1"
SET gxMaximize "1"
```

出處是 WoWSilicon 原始碼裡的一行註解 —— 它對**所有** client、**無條件**這樣寫：

> `// Display — gxWindow always 1 (true fullscreen causes issues on macOS); gxMaximize drives windowed vs borderless`
> `set("gxWindow", "1")`
> （`Sources/WoWSiliconSwift/Services/ConfigService.swift`，第 39–41 行）

**而長期正解是：不要繼續修 Whisky 的 prefix，改用 WoWSilicon。** 理由在 §7：Whisky 這份 Wine 是 **7.7（2022 年 4 月）**，它的 32-bit 側**既沒有 D3DMetal、也沒有 DXVK 的 `d3d9.dll`**，只剩 wined3d→OpenGL 一條路；WoWSilicon 則是 Wine **11.13** 加上自家 patch、外帶兩套 D3D9 translation layer。這不是「調參數」能補的差距。

---

## 1. 本機證據（全部可自行複驗）

### 1.1 第一次執行：crash dump 的真正訊息

`~/World of Warcraft 3.3.5a/Errors/2026-09-03 19.21.19 Crash.txt`：

```
ERROR #132 (0x85100084) Fatal Exception
Exception:  0x00000000 (unknown exception) at 0107:7BC24AB0
```

`7BC24AB0` 落在 `ntdll.dll`（載入於 `7BC00000`）。dump 裡附了該處的位元組：

```
7BC24AB0: 83 EC 04 EB  F3 ...
```

反組譯：`83 EC 04` = `sub esp, 4`；`EB F3` = `jmp` 回到 `7BC24AA8`。**這是一個不斷把 ESP 往下推的緊迴圈。**

> **推論（非引用，標示為推論）：** 這種形狀是 MSVC/`ntdll` 的**堆疊探測（stack probe，`__chkstk` / `_alloca_probe`）**迴圈 —— 逐頁碰觸堆疊以觸發 guard page 成長。崩在這裡代表**堆疊成長失敗**，而不是「某個 DLL 找不到」。`Exception: 0x00000000 (unknown exception)` 也是 WoW 自己的處理常式無法歸類的意思，不是真的例外碼。
> 佐證（但**不是同一個 bug**）：WineHQ Bugzilla **43656** 的標題就是 *"32-bit World of Warcraft client reports 'Game Initialization Failed!' or crashes on startup with **stack overflow**"*，component 是 **ntdll**，多位回報者提到 **error #132**（`https://bugs.winehq.org/show_bug.cgi?id=43656`）。**但那是 2017 年 Legion 7.3 的反除錯 TLS callback 問題，已於 Wine 3.4 修掉（SHA1 `2f870c1801c8d455faadd6c301aad318f287713b`），與 12340 無關。** 不要把它當成本案的原因。

### 1.2 使用者提到的 `hisky/Libraries/` 字串 —— 是什麼、以及為什麼它不是主因

dump 的 stack memory 區段確實有這兩段 ASCII（位址相鄰）：

```
0367E990: 6F 27 20 28  6E 6F 20 73  75 63 68 20  66 69 6C 65   o' (no such file
0367E9A0: 68 69 73 6B  79 2F 4C 69  62 72 61 72  69 65 73 2F   hisky/Libraries/
```

`(no such file or directory)` 是 POSIX `strerror(ENOENT)`，而 `…W|hisky/Libraries/` 是 Whisky 的
`~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/` 被 16-byte 對齊切斷後的後半。合起來就是一則 **dyld `dlopen()` 失敗訊息**（dyld 會把每個嘗試過的路徑逐一列出 `'…' (no such file or directory)`）。第一段結尾是 `o'`，最可能是某個 **`*.so`** 的路徑。

> **必須誠實說明三件事：**
> 1. 這是**殘留的堆疊垃圾**，不是當下的 faulting frame。同一份 dump 裡 `0367E9B0` 之後 16 bytes 與 `0367E720` 完全相同，證明這塊記憶體是被重複使用過的舊資料。
> 2. **無法從 dump 判定是哪一個 `.so`。** 不要猜。
> 3. **但這條路徑確實有一個可複驗的斷點**：Whisky 的 `lib/wine/x86_64-unix/d3d11.so` 依賴 `@rpath/libd3dshared.dylib`，而它的 `LC_RPATH` 只有 `@loader_path`（即 `lib/wine/x86_64-unix/`），實際檔案卻在 `lib/external/libd3dshared.dylib` —— 直接 `wine64` 啟動（不經 Whisky.app 設定 `DYLD_*`）時，這個 dlopen **必然**得到 ENOENT。**但那是 64-bit D3DMetal 的路徑，對一個 32-bit D3D9 遊戲根本不會走到**（見 §7.1）。所以它可以解釋字串從哪來，**不能**解釋這次崩潰。

### 1.3 第二次執行（OpenGL）：`Logs/gx.log` 說得非常清楚

```
CGxDevice::DeviceAdapterID(): RET: 1, VID: 10de, DID: 191, DVER: 90010.d0fd4
ValidateFormatMonitor(): unable to find monitor refresh
CGxDeviceOpenGl::DeviceSetFormat():
	Format 1512 x 982 @ 120 Fullscreen, ArgbX888, Ds24X, multisample 1
SetupPixelFormatWGL(): pixelFormat does not match requested
	Format 1512 x 982 @ 120 Fullscreen, ArgbX888, Ds160, multisample 1
SetupPixelFormatWGL(): pixelFormat does not match requested
	Format 1512 x 982 @ 120 Fullscreen, Rgb565, Ds160, multisample 1
SetupPixelFormatWGL(): pixelFormat does not match requested
ConsoleDeviceInitialize(): no output device available!
```

三個關鍵事實：

1. **它試的三次全部是 `Fullscreen`。** `Config.wtf` 裡沒有 `gxWindow`。
2. **`SetupPixelFormatWGL(): pixelFormat does not match requested` 三次全滅** → `no output device available!` → client 自己乾淨結束（所以沒有第二份 crash dump，與使用者觀察一致）。
3. `1512 x 982` 是 Retina 的**邏輯**解析度（實機面板為 `3024 x 1964`，剛好兩倍），本來就不是一個真實的顯示模式；`unable to find monitor refresh` 亦與此吻合。

而 pixel format 的挑選是 `winemac.drv` 用 CGL 做的 —— 可從該模組的字串表直接看到：

```
$ strings -a .../x86_32on64-unix/winemac.drv.so | grep -i pixel
CGLChoosePixelFormat() failed with error %d %s
mismatched pixel format draw_hdc %p %u context %p %u
Invalid pixel format %d, expect problems!
```

> **推論（標示為推論）：** 「全螢幕 + 非真實模式的 Retina 邏輯解析度」是 `CGLChoosePixelFormat` 談不攏的最合理原因。**這一點沒有 Wine 官方 bug 可引用**，但 WoWSilicon 無條件寫 `gxWindow "1"` 並在註解裡明講 *"true fullscreen causes issues on macOS"*（§7.2），是目前能找到最接近第一方的佐證。

### 1.4 這個 prefix 到底缺什麼？—— 幾乎什麼都不缺

| 檢查 | 結果 |
|---|---|
| `Software\Wine\DllOverrides` | **完全空白**（`user.reg`），沒有任何 override |
| `d3dx9_24` ～ `d3dx9_43` | **全部存在**（Wine builtin，`system32/`） |
| `msvcr80.dll` / `msvcp80.dll` | **存在**（builtin）。dump 顯示載入的 `MSVCR80.dll` 時間戳為 `1737046761`（2025-01-17），與 `msvcrt.dll`／`ole32.dll` 等 Wine builtin **完全相同** → 用的是 **Wine builtin**，不是遊戲目錄那份 2010-07-12 的原廠檔 |
| `wininet.dll` / `jsproxy.dll` / `mshtml.dll` / `ieframe.dll` | **存在**（builtin） |
| `crypt32.dll` / `rsaenh.dll` / `bcrypt.dll` / `schannel.dll` / `secur32.dll` | **存在**（builtin），且 dump 顯示全數成功載入 |
| 字型 | prefix 已把 macOS 的 `Songti.ttc` / `Arial Unicode.ttf` / `AppleSDGothicNeo.ttc` 註冊為 External Fonts；`share/wine/fonts` 亦有 `tahoma.ttf` 等 |
| **Wine Gecko** | **沒有安裝**。`system32/gecko/` 底下只有 `plugin/npmshtml.dll` 這個 stub，沒有 Gecko 引擎本體 |
| Wine 版本 | **`wine-7.7`**（`wine64 --version`），2022 年 4 月的版本 |
| 架構 | `wine64`、所有 `.so`、`D3DMetal.framework`、`libMoltenVK.dylib` **一律 x86_64**（`lipo -archs`）→ 全程跑在 Rosetta 2 上。`Logs/cpu.log` 亦印出 `vendor id string= GenuineIntel` / `processor brand string= VirtualApple @ 2.50GHz` |

**唯一真正缺席的 Windows 元件是 Wine Gecko**（即 `mshtml` 的 HTML 渲染引擎）。這與 §5 的 `Battle.net.dll` 角度有關，但**它不是本次崩潰的原因**：dump 裡 `WININET.dll` 那條 thread（ID 460）停在一般的 worker 等待點，沒有例外。

### 1.5 其他值得記錄的觀察

- crash dump 的 `GxInfo` 顯示 **`Adapter Count: 2`**，兩個都叫 `NVIDIA GeForce 8800 GTX`，driver `nvd3dum.dll`。實機是 **Apple M3 Max，只有一個內建螢幕**（`system_profiler SPDisplaysDataType`）。所以這是 wined3d 回報給 client 的**假造資訊**。
  > **未驗證：** 找不到 Wine 的第一方文件說明這個字串從何而來（社群常說是 wined3d 的 default card fallback，**無出處，本文不採信**）。
- 遊戲目錄裡本來就附了 **`Large Address Aware.exe`** —— 這對應 AppDB 的一則測試建議（§3）。
- 這是一份 **zhTW 重打包**：`Data/` 底下同時有 `zhTW/`（2.5 GB）與 `enTW/`（1.9 GB）兩套 locale，另有 `WOWTW.bat` 會把三個 locale 的 `realmlist.wtf` 一起改寫。

---

## 2. 問題本身：AppDB 到底有沒有列必裝依賴？—— **沒有，一項都沒有**

### 2.1 取用狀況（必須先講）

**`appdb.winehq.org` 與 `bugs.winehq.org` 目前都掛著 Anubis / Cloudflare 反爬蟲挑戰頁**，WebFetch 與帶 UA 的 `curl` 都只拿得到 "Making sure you're not a bot!" 而非內容。本節資料改由 **Wayback Machine 的 pre-Anubis 快照（2025-01-01）** 取得，頁面本身仍是 AppDB 原始 HTML。

> **與[前一篇筆記](./macos-client-options.md) §2.2 的差異，必須說明：** 前一篇在 2026-09-03 直接抓到的是 **6 筆**測試，最新一筆是 **Zorin OS / 2026-04-23 / Wine 11.0 / Silver**。本次只能取得 2025-01-01 的快照，因此只看得到 **5 筆**（最新為 Manjaro 21.0 / 2021-04-29 / Wine 6.5 / Platinum）。兩者不衝突 —— 快照較舊而已。**下面的「沒有提到任何 winetricks verb」這個結論只能保證涵蓋這 5 筆 + 版本頁 + 應用頁；2026 那筆 Zorin 測試的內文本次無法重新取得。**

### 2.2 測試結果（Wayback 2025-01-01 快照，`objectManager.php?sClass=version&iId=32890`）

| # | OS | 日期 | Wine | 評級 | testData |
|---|---|---|---|---|---|
| 1 | Ubuntu 14.04 amd64 | 2015-11-12 | 1.6.2 | Platinum | `iTestingId=91315` |
| 2 | Arch Linux x86_64 | 2017-02-14 | 2.1 | Platinum | `iTestingId=97045` |
| 3 | Antergos x86_64 | 2017-03-14 | 2.3 | Gold | `iTestingId=97429` |
| 4 | Debian 10 Buster | 2020-05-28 | 5.9 | Garbage | `iTestingId=108435` |
| 5 | Manjaro Linux 21.0 | 2021-04-29 | 6.5 | Platinum | （版面內嵌） |

- 版本描述："Latest version of **Wrath of The Lich King** expansion"；Maintainer 只有一位（`spaceman`）。
- **HowTo / Notes 區塊是空的**，**Comments 區塊也是空的**（版本頁與 4 個測試詳情頁皆然）。
- 母條目 `sClass=application&iId=1922` 的版本清單裡，**`3.3.5a` 是唯一的 3.3.x 條目**。

### 2.3 全部「像是安裝需求」的敘述，逐字照抄

**測試 #1（Ubuntu 14.04 / Wine 1.6.2 / Shin）** — `objectManager.php?iTestingId=91315&sClass=version&iId=32890`

> What works: *"Everything using **OpenGL** adding the following configuration to the **WTF/Config.wtf** file: **SET gxApi "OpenGL"** **SET ffxDeath "0"** **SET ffxGlow "0"** **SET M2UseShaders "0"**"*
> What does not: *"Sometimes it doesn't work well if you don't use the configuration shown above."*
> Additional Comments: *"You should install wine using --install-recommends param: sudo apt-get install wine --install-recommends"*

**測試 #3（Antergos / Wine 2.3 / Keenan）** — `iTestingId=97429`

> *"Note, I had to set the **LAA ( Large Address Aware ) flag** on the wow.exe otherwise I would get **out of memory crashes**."*

**測試 #4（Debian Buster / Wine 5.9）** — `iTestingId=108435`：一則 5.9 的滑鼠視角回歸 bug，workaround 是降回 5.8。與本案無關。

### 2.4 明確的「不存在」清單

在這 5 筆測試 + 版本頁 + 母條目裡，**以下字眼一次都沒有出現**：

`winetricks`、任何 winetricks verb、winecfg Libraries tab / DLL override、native DLL、regedit 登錄修改、任何**命令列**啟動旗標（`SET gxApi` 是 `Config.wtf` 變數，**不是** `-opengl` 旗標）、`DXVK`、`D9VK`、`vcrun2005`、`msvcr80`、`d3dx9`、`corefonts`、`ie8`、`crypt32`、`rsaenh`、`Battle.net.dll`、`ERROR #132`。

> **而且（承襲[前一篇](./macos-client-options.md) §2.2 的但書並再次確認）：這 5 筆測試全部在 Linux 上。AppDB 的 3.3.5a 條目沒有任何一筆 macOS 或 Apple Silicon 紀錄。**

---

## 3. 逐一裁決那些「常見必裝元件」候選

規則：**沒有 primary source 建議它給 3.3.5a，就不寫「需要」。**

| 候選 | 有沒有第一方來源建議給 WoW 3.3.5a？ | 本機現況 | 裁決 |
|---|---|---|---|
| `vcrun2005`（`msvcr80` / `msvcp80` / `mfc80`） | **沒有。** AppDB 未提；WineHQ Bugzilla 也找不到把 WoW 崩潰歸因於 `MSVCR80.dll` 的 bug | Wine builtin 已存在並實際被載入（§1.4） | **不需要**。若真要換成原廠版，winetricks 20250102 的 verb metadata 是 `vcrun2005 dlls title="Visual C++ 2005 libraries (mfc80,msvcp80,msvcr80)"`（本機 `Libraries/winetricks` 第 12439 行）。**但沒有來源說它能修這個崩潰。** |
| `d3dx9` | **沒有。** | builtin `d3dx9_24`～`d3dx9_43` 全在 | **不需要** |
| `corefonts` | **沒有。** | prefix 已註冊 macOS 系統字型；zhTW 文字用的是 client 自帶字型 | **不需要**（若中文顯示異常再說，**未驗證**） |
| `ie8` / `wininet` | **沒有來源說 3.3.5a 需要。** | `wininet` / `mshtml` builtin 在，但 **Wine Gecko 未安裝** | **不需要**用來修這個崩潰。詳見 §5 |
| `crypt32` / `rsaenh` | **沒有。** | builtin 在，且 dump 顯示已成功載入 | **不需要** |
| `dxvk`（含 `d3d9.dll`） | **這是唯一有實質理由的一項**，但理由來自 D3D9 的架構缺口（§7），不是來自任何一份 WoW 的測試報告 | Whisky 自帶的 32-bit DXVK **只有 `d3d10core.dll` / `d3d11.dll` / `dxgi.dll`，沒有 `d3d9.dll`** | **可以試，但風險高**，見 §6.3 |

winetricks 的 `dxvk` verb 確實會裝 `d3d9.dll` —— 本機 `Libraries/winetricks`（版本 `20250102`）第 7587–7596 行：

```
w_metadata dxvk dlls \
    title="Vulkan-based D3D8/D3D9/D3D10/D3D11 implementation for Linux / Wine (latest)" \
    installed_file1="${W_SYSTEM32_DLLS_WIN}/d3d8.dll" \
    installed_file2="${W_SYSTEM32_DLLS_WIN}/d3d9.dll" \
    ...
```

---

## 4. Blizzard 自己怎麼定義 ERROR #132

Blizzard 支援文件 **8288**（`https://eu.support.blizzard.com/en/article/8288`）：

> "World of Warcraft crashes with an **Error 132: Fatal Exception!** message. **Error 132 is a generic error code** that may be caused by out-of-date addons, corrupted files, incompatible drivers, or hardware issues."

其建議步驟全是「更新驅動／重設 UI／關閉防毒／檢查過熱／重灌」。**Blizzard 完全沒有提到 Wine 或 Linux。**

> **這就是最重要的一句話：#132 是一個「泛用」錯誤碼。** 網路上任何「#132 的原因是 X」的斷言，如果沒有配一份 dump，都是猜的。本文對本案的判讀完全建立在 §1 的 dump 位元組與 `gx.log` 上。

---

## 5. `Battle.net.dll` / 登入 web view 這條線

### 5.1 有文件記載的部分

**WineHQ Bugzilla 23323** — *"World of Warcraft crashes upon login after 3.3.5 patch. [NOT WINE BUG]"*（`https://bugs.winehq.org/show_bug.cgi?id=23323`，**CLOSED INVALID**，2010-06-22 開票 —— 正好就是 3.3.5 的年代）。原始回報：

> *"Immediately after entering login information, a illegal instruction error occurs. This may be related to the introduction of Blizzard's 'RealID' system, which uses a **'Battle.net.dll' that is known from Starcraft 2 Beta to have anti-debugging measures in it**."*

**已確立的原因與 workaround（comment 184 及後續確認）：** 那是 **Linux 核心**的 ptrace 回歸（`08d6832` 引入、`a1e80fa` 修復、`f7809da` 再壞），與 `Battle.net.dll` 的反除錯檢查衝突；解法是 `echo 0 > /proc/sys/kernel/yama/ptrace_scope`。

> **對本案的意義：這條線在 macOS 上不適用**（沒有 Yama / `ptrace_scope`）。但它確立了一件事：**`Battle.net.dll` 內含反除錯機制，而且在 3.3.5 這個 build 上確實製造過麻煩。**

**WineHQ Bugzilla 40432** — *"Battle.net crashes"*（`https://bugs.winehq.org/show_bug.cgi?id=40432`，CLOSED DUPLICATE of 32342）：backtrace 落在 **`libcef`**（Chromium Embedded Framework），也就是**新版 Battle.net 啟動器**的 web view。**那是現代 launcher，不是 12340 的 `Battle.net.dll`。** 不要混為一談。

### 5.2 WoWSilicon 提供的第一方佐證：舊 client 真的會發那個 HTTP 請求

WoWSilicon 對 Wine 打的第 8 號 patch 檔名就叫 `0008-wininet-skip-legacy-game-alert-requests.patch`（`Packaging/WineRuntime/patches/`），改的是 `dlls/wininet/http.c`：

```c
+    /* Legacy game clients request /alert or /<locale>/alert. Ignore a query
+     * string when matching, but leave every other game request untouched. */
...
+    if (is_legacy_game_alert_request(request))
+    {
+        WARN("skipping legacy game alert request %s\n", debugstr_w(request->path));
+        return ERROR_INTERNET_NAME_NOT_RESOLVED;
+    }
```

由環境變數 `WOWSILICON_BLOCK_LEGACY_ALERTS=1` 啟用（`LaunchService.swift` 第 327 行的 `baseEnv` 就帶著它）。

**這證明：2006–2010 年代的 client 確實會透過 `WININET` 去打一個 `/alert` 端點，而且值得專門 patch 掉。** 這與本機 dump 中 `WININET.dll` / `jsproxy.dll` 被載入、且有一條專屬 thread 完全吻合。

### 5.3 明確標為未經證實的說法

- **「把 `Battle.net.dll` 刪掉／改名就能避開崩潰」** —— **未找到任何 primary source。** 私服論壇廣泛流傳，但 Bugzilla 23323 給的解法是**核心設定**，不是動這個 DLL。**列為未經證實的民間偏方，本文不建議。**
- **「有官方旗標可以跳過 launcher / 登入 web view」** —— **未找到任何 primary source。** 同樣列為未經證實。

---

## 6. D3D9 在 Apple Silicon 上到底有沒有路？

### 6.1 D3DMetal **不做 D3D9** —— 這次可以拿出證據了

[前一篇筆記 §2.4](./macos-client-options.md) 把「D3DMetal 支援哪些 D3D 版本」列為未驗證。本次補上兩項證據。

**(a) 本機二進位實測（最直接）。** Whisky 隨附的 `Libraries/Wine/lib/external/D3DMetal.framework/D3DMetal` 共匯出 3336 個符號，其中包含：

```
_D3D11CreateDevice   _D3D11CreateDeviceAndSwapChain
_D3D12CreateDevice   _D3D12GetDebugInterface
_CreateDXGIFactory   _CreateDXGIFactory1   _CreateDXGIFactory2
```

**而 `nm -gU | grep -i -E 'd3d9|Direct3DCreate9'` 的結果是零。D3DMetal 沒有任何 D3D9 進入點。**

**(b) CodeWeavers 官方 blog（Meredith Johnson，"CrossOver 23.5 is a real game changer"）：**

> "New D3DMetal option. This release offers an alternate way to run **DirectX 11 and DirectX 12** games through CrossOver, using components from the Apple game porting toolkit."

**(c) MTLd3D 專案自己的 README（`https://github.com/athei/mtld3d`）也這樣講：**

> "mtld3d aims to be the fastest Direct3D 9 implementation for Wine on macOS… **Every other Direct3D version is a non-goal; D3D10/11/12 are already well served on macOS by Apple's D3DMetal and by DXMT.**"

> **仍然未驗證：Apple 自己從未在任何頁面寫出 D3DMetal 支援哪些 D3D 版本。** GPTK 官方頁面搜尋 "Direct3D" / "D3D" 都是零命中。上面 (b)(c) 是 CodeWeavers 與第三方專案的話，不是 Apple 的話。(a) 則是本機二進位的客觀事實。

### 6.2 Whisky 這份 runtime 的 32-bit 側，D3D9 只剩 wined3d

本機 `Libraries/Wine/lib/wine/` 底下：

| 目錄 | 有沒有 `d3d10.so` / `d3d11.so` / `d3d12.so` / `dxgi.so`（D3DMetal 的 unix 側） |
|---|---|
| `x86_64-unix/`（36 個檔） | **有** |
| `x86_32on64-unix/`（30 個檔） | **完全沒有** |

`Libraries/DXVK/` 底下：

| 目錄 | 內容 |
|---|---|
| `x64/` | `d3d10core.dll`、`d3d11.dll`、`dxgi.dll` |
| `x32/` | `d3d10core.dll`、`d3d11.dll`、`dxgi.dll` —— **沒有 `d3d9.dll`** |

**結論（本機事實，非推論）：在 Whisky 這份 runtime 裡，一個 32-bit D3D9 遊戲既拿不到 D3DMetal，也拿不到 DXVK 的 d3d9。它唯一的實作就是 `i386-windows/d3d9.dll`（Wine builtin）→ `wined3d.dll` → `winemac.drv` → macOS OpenGL。** 這正是第一次執行走的路。

### 6.3 那 wined3d→OpenGL 這條路本身合不合格？

Wine 自己的原始碼（`dlls/wined3d/adapter_gl.c`）定義了硬性下限：必須有 `ARB_fragment_shader`、`ARB_shading_language_100`、`ARB_vertex_shader`、`EXT_framebuffer_object`、`ARB_texture_non_power_of_two`，且

```c
if (gl_info->glsl_version < MAKEDWORD_VERSION(1, 20))
    ERR("GLSL version %s is too low; 1.20 is required.\n", ...);
```

**GLSL 1.20 的門檻，macOS 那套（已棄用但仍在的）OpenGL 綽綽有餘。** Apple 官方只確認了棄用這件事（`https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/OpenGL-MacProgGuide/…`：*"OpenGL was deprecated in macOS 10.14"*）。

> **未驗證：** 廣為流傳的「macOS 的 OpenGL 上限是 4.1 Core Profile」這個數字，**在 Apple 的頁面上找不到明文**。本文不引用該數字。

**所以 wined3d 的能力門檻不是問題；問題在 `winemac.drv` 這一層的視窗／pixel format 行為（§1.3），以及 Wine 7.7 本身的年紀。**

### 6.4 DXVK / D9VK / MTLd3D 的現況（第一方）

- **DXVK**（`https://github.com/doitsujin/dxvk`）README：*"A Vulkan-based translation layer for **Direct3D 8/9/10/11** which allows running 3D applications on Linux using Wine."* 安裝說明明列 `d3d9: d3d9.dll`，也明講純 32-bit prefix 時 DLL 放 `system32`。
  > **重要但書：DXVK 的 README 與 wiki 全文搜尋 "macOS" 與 "MoltenVK" 皆為零命中。** 上游 DXVK **不宣稱**支援 macOS。「DXVK 跑在 MoltenVK 上」是社群整合路線，不是上游文件。
- **D9VK**（`https://github.com/misyltoad/d9vk`）：repo 已 **archived**，README 第一行：*"# This work has been upstreamed and is continuing development there … https://github.com/doitsujin/dxvk"*。**D9VK 已併入 DXVK，不再是獨立專案。**（WoWSilicon 使用的是 `Sikarugir-App/d9vk` 這個 macOS 向的分支，見 §7.1。）
- **MoltenVK**（`https://github.com/KhronosGroup/MoltenVK`）README：*"MoltenVK is a layered implementation of **Vulkan 1.4** graphics and compute functionality, that is built on Apple's Metal…"*
  > **未驗證：** MoltenVK 的實際限制清單在 `Docs/MoltenVK_Runtime_UserGuide.md#limitations`，本次未取得該檔內容。但 §7.1 的 WoWSilicon patch 0002 間接揭露了一部分（見下）。
- **MTLd3D**（`https://github.com/athei/mtld3d`）：*"mtld3d replaces Wine's built-in `d3d9.dll` with an implementation that translates D3D9 calls through Wine's PE/Unix boundary into Metal command buffers on the host."* 並自述以 **`d3d9=native` 的 per-game override** 使用，*"which is what CrossOver bottles use"*；平台範圍 *"Apple Silicon is what is developed and tested today."*

---

## 7. WoWSilicon 捆了什麼 —— 這份清單本身就是「缺什麼」的答案

`https://github.com/WoWSilicon/WoWSilicon`（GitHub API 實測）：**GPL-3.0**、Swift、110 stars、`created_at 2026-05-01`、`pushed_at 2026-09-03`、未封存。**有預編 binary**：最新 release **`v3.0.2`（2026-08-19）**，資產為 `WoWSilicon-3.0.2.dmg`；Wine runtime 另以 `wine-runtime-rN` tag 發佈（`WoWSilicon-WineRuntime-r6.tar.xz`，61 MB）。README 明講 build 未簽章：

> "If macOS blocks the app because the build is unsigned, remove the quarantine attribute after moving it: `xattr -dr com.apple.quarantine /Applications/WoWSilicon.app`"

需求：*"Apple Silicon Mac / macOS 15 or newer / A legally acquired local World of Warcraft client folder"*。支援 client 明列 **Wrath of the Lich King 3.3.5a**。

### 7.1 它捆了什麼（來源：repo 檔案）

**Wine 本體**（`Packaging/WineRuntime/runtime-lock.json`）：

```json
"wine": {
  "version": "11.13",
  "repository": "https://github.com/WineAndAqua/wine.git",
  "branch": "wine-11.13-macos",
  "commit": "37540b5d94ac1c86e2599ef55d7f3a15e3237ce8"
},
"mtld3d": { "version": "v0.7.0" }
```

**→ Wine 11.13，對比 Whisky 的 wine-7.7。這是本案最大的單一落差。**

同一份 lock 檔列出的 overlay：`lib/wine/i386-windows/d3d9.dll`、`lib/wine/i386-windows/mtld3d.dll`、`lib/wine/x86_64-unix/mtld3d.so`、`lib/mtld3d.conf`，以及 `lib/external/libMoltenVK.dylib`（另有 SDL2 / freetype / gnutls / gmp 等）。

**遊戲目錄側的資源**（`Sources/WoWSiliconSwift/Resources/Patching/`）：

| 檔案 | 用途（依 repo 路徑與 README Credits） |
|---|---|
| `d9vk/d3d9.dll` | D9VK（`Sikarugir-App/d9vk`）— "Direct3D 9 translation through Vulkan" |
| `winerosetta/winerosetta.dll`、`winerosetta/libDllLdr.dll` | DLL 注入與遊戲檔 patch 的載入器 |
| `rosettax87/rosettax87`、`rosettax87/libRuntimeRosettax87` | `Lifeisawful/rosettax87_jit` — "accelerated x87 translation for Rosetta 2" |
| `x87sidecar/x87sidecar` | `athei/x87sidecar` — "isolated, cooperative x87 acceleration" |
| `libSiliconPatch/wotlk/libSiliconPatch.dll` | README：*"libSiliconPatch mod (reducing x87-heavy runtime paths)"* |
| `vanilla-tweaks/vanilla-tweaks.exe` | 僅 Vanilla |

**它對 Wine 打的 8 個 patch**（`Packaging/WineRuntime/patches/`）—— 這是 Whisky 完全沒有的東西：

```
0001-winemac-convert-client-surface.patch
0002-wined3d-relax-moltenvk-feature-level.patch
0003-ntdll-add-x87sidecar-cooperative-attach.patch
0004-winemac-normalize-toplevel-client-surface-origin.patch
0005-winemac-use-input-source-language-in-hkl.patch
0006-dsound-follow-default-playback-device.patch
0007-winecoreaudio-add-spatialized-stereo.patch
0008-wininet-skip-legacy-game-alert-requests.patch
```

**patch 0002 特別有價值** —— 它把 `dlls/wined3d/adapter_vk.c` 的 feature level 檢查放寬：

```diff
-            && info->features2.features.geometryShader
-            && info->features2.features.pipelineStatisticsQuery
-            && info->features2.features.shaderCullDistance
```

**這等於用程式碼證明：MoltenVK 不提供 `geometryShader` / `pipelineStatisticsQuery` / `shaderCullDistance`，因此未經修改的 wined3d-vulkan 在 macOS 上過不了 feature level 檢查。** 這是本次找到、關於「MoltenVK 限制」最具體的第一方證據（§6.4 的未驗證項目部分補上了）。

**注意 patch 0001 / 0004 都在動 `winemac.drv` 的 client surface** —— 也就是 §1.3 出問題的那一層。

### 7.2 它「設定」了什麼（Whisky 空 prefix 完全沒有的）

**啟動環境變數**（`Sources/WoWSiliconSwift/Services/LaunchService.swift`，第 327 行 `baseEnv`）：

```
WINEPREFIX=… DYLD_LIBRARY_PATH=… WINE_LARGE_ADDRESS_AWARE=1
WINEDLLOVERRIDES="<backend>" WOWSILICON_BLOCK_LEGACY_ALERTS=1
… MTL_HUD_ENABLED=… MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=1 DXVK_ASYNC=1
```

（另一條啟動路徑第 532 行還多帶 `WINE_D3D_CONFIG=renderer=vulkan`。）

**DLL override 的實際值**（`Tests/WoWSiliconSwiftTests/GraphicsBackendTests.swift`，測試即規格）：

```swift
XCTAssertEqual(settings.backend, .d9vk)                              // 預設後端 = D9VK
XCTAssertEqual(settings.backend.wineDLLOverride, "d3d9=n")           // D9VK → native
XCTAssertEqual(GraphicsBackend.mtld3d.wineDLLOverride, "d3d9=b")     // MTLd3D → builtin（因為它替換掉 runtime 內的 builtin d3d9）
XCTAssertEqual(GraphicsBackend.d9vk.wineDLLOverrideWithBuiltinFallback, "d3d9=n,b")
```

**`Config.wtf` 的寫入**（`Services/ConfigService.swift`）：

```swift
// Display — gxWindow always 1 (true fullscreen causes issues on macOS); gxMaximize drives windowed vs borderless
set("gxWindow", "1")
set("gxMaximize", gs.windowMode == .fullscreen ? "1" : "0")
```

**注意：它從不設定 `gxApi`。** 它讓 client 走預設的 **D3D9**，然後把 `d3d9.dll` 換掉。**它不是靠 OpenGL 解決問題的。**

**遊戲檔案 patch**（`Services/PatchService.swift`）：把 `d3d9.dll`（D9VK）與 `mtld3d.conf` 放進遊戲根目錄、`winerosetta.dll` / `libSiliconPatch.dll` 放進 `mods/`、維護一份 `dlls.txt`，並以

```swift
arguments: ["rundll32", "libDllLdr.dll,PatchDivxDecoder", gameURL.path]
```

就地 patch **`DivxDecoder.dll`** 與 `DivxTac.dll`（若存在）。

> **值得注意：本機這份 client 的 dump 裡，`DivxDecoder.dll`（時間戳 2004-02-11，原廠檔）確實被載入。** WoWSilicon 認為它需要 patch。
> **未驗證：** repo 沒有說明 `PatchDivxDecoder` 具體改了什麼、以及不 patch 會有什麼後果。

### 7.3 Whisky vs WoWSilicon：差距總表

| 項目 | Whisky（本機現況） | WoWSilicon |
|---|---|---|
| Wine | **7.7**（2022-04） | **11.13** + 8 個自家 patch |
| 32-bit D3D9 實作 | 只有 wined3d builtin → OpenGL | **D9VK（Vulkan/MoltenVK）或 MTLd3D（Metal），二選一** |
| MoltenVK feature level | 未處理 | patch 0002 放寬 |
| `winemac.drv` | 未處理 | patch 0001 / 0004 |
| x87 加速（Rosetta 2 的最大痛點） | **無** | rosettax87_jit + x87sidecar + `libSiliconPatch` |
| LAA | 未設定（遊戲目錄有 `Large Address Aware.exe` 但未用） | `WINE_LARGE_ADDRESS_AWARE=1` |
| `gxWindow` | 未設定（→ 全螢幕 → §1.3 失敗） | **強制 `1`** |
| 舊 client 的 `/alert` 請求 | 未處理 | patch 0008 + `WOWSILICON_BLOCK_LEGACY_ALERTS=1` |
| `DivxDecoder.dll` | 原廠未 patch | 自動 patch |

**這張表就是「缺什麼依賴」的誠實答案：缺的不是 winetricks verb，是一整套針對 32-bit D3D9 + Rosetta 2 + macOS 視窗系統的工程。**

> **未驗證（沿用[前一篇](./mac-client-3.3.5a-on-apple-silicon.md) §5.2 的標註）：** 本文未實測 WoWSilicon 的效能、穩定性或安全性；其 DMG 未簽章。這是陳述其自述能力，**不是背書**。它同樣建立在 Rosetta 2 之上（`rosettax87`），因此繼承 macOS 27 的到期日。

---

## 8. `WoW.enTW.10958` 這個 build 不一致，有沒有關係？

`Logs/connection.log`：

```
Component WoW.Win.12340
Component WoW.base.12340
Component WoW.zhTW.12340
Component WoW.enTW.10958      ← 與其他不同
Component Tool.Win.347
```

本機追查結果：

- `Data/enTW/component.wow-entw.txt` 的內容其實寫著 `version="12340"`，但 client 從 MPQ 讀到的是 **10958**（3.2.2a 年代）。兩者不一致。
- 這份安裝同時保有 `Data/zhTW/`（2.5 GB）與 `Data/enTW/`（1.9 GB）兩套 locale，`Config.wtf` 的 `SET locale "zhTW"` 決定實際使用 zhTW。

> **未驗證：找不到任何 primary source（Blizzard 文件、WineHQ bug、專案文件）說明混合 locale 或 build 不一致的 locale 目錄會造成 client 崩潰。** 本文把它記錄為「這份 client 是重打包、內含一套過期的 enTW locale」的事實，**不宣稱它是原因**。
> 若日後要排除變因，最低風險的做法是把 `Data/enTW/` 暫時移到別處（**本文未執行**）。

---

## 9. 建議的執行順序（成本由低到高，每一項標出處）

### 第 0 步（免費，先做）：改成視窗模式

在 `WTF/Config.wtf` 加入 / 修改：

```
SET gxWindow "1"
SET gxMaximize "1"
```

**出處：** WoWSilicon `ConfigService.swift` 第 39–41 行的註解與程式碼 —— *"gxWindow always 1 (true fullscreen causes issues on macOS)"*。
**針對：** §1.3 的 `SetupPixelFormatWGL(): pixelFormat does not match requested` → `no output device available!`。這是唯一一個「有第一方註解直接對應本機 log」的修正。

順帶把解析度設成真實的面板模式或一個保守值（目前的 `1512x982` 是 Retina 邏輯解析度）。

### 第 1 步（免費）：套用 AppDB 唯一給過的 OpenGL 設定組合

```
SET gxApi "OpenGL"
SET ffxDeath "0"
SET ffxGlow "0"
SET M2UseShaders "0"
```

**出處：** AppDB testData `iTestingId=91315`（Ubuntu 14.04 / Wine 1.6.2 / Platinum）逐字引用。
**但書：** 該測試在 **Linux + Wine 1.6.2**，與本機（macOS + wine-7.7 + winemac.drv）不同。**未驗證是否適用。**

### 第 2 步（免費）：開 Large Address Aware

用環境變數 `WINE_LARGE_ADDRESS_AWARE=1` 啟動（WoWSilicon `LaunchService.swift` 第 327 行就是這樣做的），或使用遊戲目錄裡本來就附的 `Large Address Aware.exe`。

**出處：** AppDB testData `iTestingId=97429` — *"I had to set the LAA ( Large Address Aware ) flag on the wow.exe otherwise I would get out of memory crashes."*；以及 WoWSilicon 的 `baseEnv`。
**針對：** §1.1 那個堆疊/記憶體形狀的崩潰（**這是推論，不是已證實的因果**）。

### 第 3 步（需要下載，風險中等）：給 32-bit prefix 一個 `d3d9.dll`

Whisky 的 32-bit DXVK **沒有** `d3d9.dll`（§6.2）。若要走 D3D9→Vulkan：

```
winetricks dxvk        # verb metadata 明列會裝 d3d9.dll（本機 winetricks 20250102，第 7587 行起）
# 並設 d3d9=n（native），對照 WoWSilicon 的 GraphicsBackend.d9vk.wineDLLOverride == "d3d9=n"
```

**必須誠實說明的三個風險：**
1. **DXVK 上游從不宣稱支援 macOS**（README 全文無 "macOS" / "MoltenVK"，§6.4）。
2. **Whisky 的 wine 7.7 沒有 WoWSilicon 的 patch 0002**，而該 patch 的存在本身就證明未修改的 wined3d/Vulkan 路徑在 MoltenVK 上會卡 feature level（§7.1）。
3. Whisky 的 `libMoltenVK.dylib` 是 x86_64（Rosetta），而 `wine64` 直接啟動時 `DYLD_*` 未必被設好（§1.2）。

**→ 這一步「可以試」，但期望值不高。**

### 第 4 步（最誠實的答案）：改用 WoWSilicon

**這裡就直說：如果目標是「把 3.3.5a 跑起來」而不是「研究 Wine」，正確做法是用 WoWSilicon，因為它把上面全部（以及 Whisky 根本沒有的 x87 加速、winemac.drv patch、wininet patch、遊戲檔 patch）都包好了。** 清單見 §7.3。

代價與已知風險（全部標明）：
- DMG **未簽章**，需 `xattr -dr com.apple.quarantine`（其 README 自述）。
- **未驗證**其效能／穩定性／安全性，本文不背書。
- 它同樣依賴 Rosetta 2 → **繼承 macOS 27 的到期日**（見[前一篇](./macos-client-options.md) §2.1）。
- 需要 **macOS 15+**（本機為 **macOS 26.5.2**，符合）。

### 不建議做的事

- **裝 `vcrun2005` / `d3dx9` / `corefonts` / `ie8` / `crypt32`** —— builtin 全在，沒有任何 primary source 說 3.3.5a 需要它們（§3）。
- **刪掉或改名 `Battle.net.dll`** —— 未經證實的民間偏方（§5.3）。
- **繼續在 Whisky 上調 D3D9** —— 該 runtime 的 32-bit 側結構上就沒有 D3D9 translation layer（§6.2）。
- 順帶一提，**Whisky 本身已於 2025-05-11 封存、作者明言停止維護**（見[前一篇](./macos-client-options.md) §2.3）。

---

## 10. 驗證方式（全部唯讀，可自行複驗）

本機：

```sh
sed -n '/Memory Dump/,$p' ~/"World of Warcraft 3.3.5a/Errors/2026-09-03 19.21.19 Crash.txt"
cat ~/"World of Warcraft 3.3.5a/Logs/gx.log"          # SetupPixelFormatWGL / no output device available
cat ~/"World of Warcraft 3.3.5a/Logs/cpu.log"         # VirtualApple @ 2.50GHz（Rosetta）

L=~/"Library/Application Support/com.isaacmarovitz.Whisky/Libraries"
"$L/Wine/bin/wine64" --version                        # wine-7.7
lipo -archs "$L/Wine/bin/wine64"                      # x86_64
ls "$L/DXVK/x32"                                      # 沒有 d3d9.dll
ls "$L/Wine/lib/wine/x86_32on64-unix" | grep -c d3d    # 0
ls "$L/Wine/lib/wine/x86_64-unix"    | grep    d3d     # d3d10/11/12 + dxgi
nm -gU "$L/Wine/lib/external/D3DMetal.framework/D3DMetal" | grep -ci 'Direct3DCreate9'   # 0
grep -n -A14 '^w_metadata dxvk dlls' "$L/winetricks"   # verb 會裝 d3d9.dll

grep -A2 'DllOverrides' ~/.wow335-prefix/user.reg      # 空的
ls ~/.wow335-prefix/drive_c/windows/system32/ | grep -E 'd3dx9|msvcr80|wininet|mshtml|crypt32|rsaenh'
find ~/.wow335-prefix/drive_c/windows/system32/gecko   # 只有 plugin/npmshtml.dll
```

外部（本次實際抓取）：

```sh
curl -sL https://api.github.com/repos/WoWSilicon/WoWSilicon
curl -sL https://api.github.com/repos/WoWSilicon/WoWSilicon/releases?per_page=3
curl -sL "https://api.github.com/repos/WoWSilicon/WoWSilicon/git/trees/HEAD?recursive=1"
curl -sL https://raw.githubusercontent.com/WoWSilicon/WoWSilicon/main/Packaging/WineRuntime/runtime-lock.json
curl -sL https://raw.githubusercontent.com/WoWSilicon/WoWSilicon/main/Packaging/WineRuntime/patches/0002-wined3d-relax-moltenvk-feature-level.patch
curl -sL https://raw.githubusercontent.com/WoWSilicon/WoWSilicon/main/Packaging/WineRuntime/patches/0008-wininet-skip-legacy-game-alert-requests.patch
curl -sL https://raw.githubusercontent.com/WoWSilicon/WoWSilicon/main/Sources/WoWSiliconSwift/Services/ConfigService.swift
curl -sL https://raw.githubusercontent.com/WoWSilicon/WoWSilicon/main/Tests/WoWSiliconSwiftTests/GraphicsBackendTests.swift
curl -sL https://gitlab.winehq.org/wine/wine/-/raw/master/dlls/wined3d/adapter_gl.c
```

**取用失敗（必須說明）：**

- **`appdb.winehq.org` 與 `bugs.winehq.org` 目前掛著 Anubis / Cloudflare 反爬蟲挑戰**，WebFetch 與帶 UA 的 `curl` 都只回挑戰頁。§2 與 §5 的 AppDB／Bugzilla 內容**改由 Wayback Machine 的 pre-Anubis 快照取得**（AppDB 為 2025-01-01 快照，因此比[前一篇筆記](./macos-client-options.md)少了 2026 那筆 Zorin/Wine 11.0 測試）。
- `codeweavers.com` 的 changelog 與支援論壇對非瀏覽器 client 回 **403**；§6.1(b) 的引用同樣來自 Wayback 快照。
- Apple `developer.apple.com/videos/play/wwdc2023/10123/` 的逐字稿本次無法直接取得，故 §6.1 不引用它。
- MoltenVK 的 `Docs/MoltenVK_Runtime_UserGuide.md#limitations` 本次未取得。
- **未使用任何瀏覽器自動化。**

---

## 11. 實際取用過的來源

**本機（PRIMARY，可複驗）**
- `~/World of Warcraft 3.3.5a/Errors/2026-09-03 19.21.19 Crash.txt`、`Logs/gx.log`、`Logs/cpu.log`、`Logs/connection.log`、`WTF/Config.wtf`、`Data/enTW/component.wow-entw.txt`
- `~/Library/Application Support/com.isaacmarovitz.Whisky/Libraries/`（Wine 7.7、DXVK x32/x64、`winetricks` 20250102、`verbs.txt`、`D3DMetal.framework`、`libMoltenVK.dylib`）
- `~/.wow335-prefix/`（`user.reg`、`system.reg`、`drive_c/windows/system32/`）

**WineHQ（經 Wayback 快照）**
- `https://appdb.winehq.org/objectManager.php?sClass=version&iId=32890`（5 筆測試、HowTo/Comments 皆空）
- `https://appdb.winehq.org/objectManager.php?sClass=application&iId=1922`
- testData `iTestingId=91315` / `97045` / `97429` / `108435`
- `https://bugs.winehq.org/show_bug.cgi?id=23323`（Battle.net.dll 反除錯，NOT WINE BUG）
- `https://bugs.winehq.org/show_bug.cgi?id=43656`（32-bit WoW / #132 / stack overflow / ntdll，Wine 3.4 修復）
- `https://bugs.winehq.org/show_bug.cgi?id=40432`（Battle.net launcher，libcef，DUPLICATE of 32342）
- `https://bugs.winehq.org/show_bug.cgi?id=31846`、`?id=51368`（WoW D3D9 繪圖 bug，皆 FIXED）
- `https://bugs.winehq.org/show_bug.cgi?id=52354`（winemac.drv 非 Metal GPU，FIXED；**與 Apple Silicon 無關**）
- `https://gitlab.winehq.org/wine/wine/-/raw/master/dlls/wined3d/adapter_gl.c`（GLSL 1.20 下限）

**Blizzard**
- `https://eu.support.blizzard.com/en/article/8288` — ERROR 132 是 generic error code

**CodeWeavers / Apple**
- CodeWeavers blog, Meredith Johnson, *"CrossOver 23.5 is a real game changer"* — D3DMetal = "DirectX 11 and DirectX 12"（Wayback）
- `https://developer.apple.com/library/archive/…/OpenGL-MacProgGuide/…` — OpenGL 於 macOS 10.14 棄用

**各專案 repo（各自的 PRIMARY）**
- `https://github.com/WoWSilicon/WoWSilicon`（README、`runtime-lock.json`、`artifact-lock.json`、`patches/0001`–`0008`、`LaunchService.swift`、`ConfigService.swift`、`PatchService.swift`、`DXVKConfigService.swift`、`GraphicsBackendTests.swift`、Releases API）
- `https://github.com/doitsujin/dxvk`（README）
- `https://github.com/misyltoad/d9vk`（已封存，README 指向 DXVK）
- `https://github.com/KhronosGroup/MoltenVK`（README，Vulkan 1.4 on Metal）
- `https://github.com/athei/mtld3d`（README）
