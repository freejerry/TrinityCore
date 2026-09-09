# 3.3.5a 的**原生 Mac client**，有沒有任何辦法在 Apple Silicon 上跑起來？（研究筆記）

> 撰寫日期：2026-09-03
> 相關筆記：[macOS / Apple Silicon 上玩 WotLK 內容](./macos-client-options.md)（**前置閱讀**）、[TrinityCore 專案總覽](./trinitycore-overview.md)
> 來源限定 primary sources：Apple（developer.apple.com / support.apple.com / apple.com newsroom）、各工具自己的文件與 repo（UTM、QEMU、Sikarugir/Wineskin、WoWSilicon）。
> 凡未經實際驗證者，一律明確標示「**未驗證**」。本文**不記錄任何 game client 的下載連結**——這是「技術上存不存在」的問題，不是「怎麼拿到」的問題。

---

## 0. 前提（不重新推導）

[macos-client-options.md](./macos-client-options.md) 第 1 節已用第一方來源確立：

- 3.3.5a **Mac** client 是 **PPC/Intel 32-bit universal binary**（Blizzard 官方 WotLK 系統需求最低列 "PowerPC G5 1.6 GHz or **Intel Core Duo**"，而 Core Duo 是 32-bit only）。
- Apple `https://support.apple.com/en-us/103076`：*"Starting with macOS Catalina 10.15, 32-bit apps are no longer compatible with macOS."*

本文接著問：**既然這個 Mac client 確實存在，有沒有任何技術路徑能逼它在 M 系列 Mac 的現行 macOS 上跑起來？**

---

## 1. 總表：每條路的裁決

| # | 路徑 | 裁決 | 一句話理由 |
|---|---|---|---|
| 1 | Rosetta 2 直接翻譯 32-bit Mach-O | **Impossible** | Apple 明文只寫 "apps that contain **x86_64** instructions"；且 32-bit 執行環境自 Catalina 起就不存在，Rosetta 之前的 loader 就已經失敗 |
| 2a | 在 Apple Silicon 上**虛擬化** macOS 10.14 | **Impossible** | Apple Virtualization 的 macOS guest 平台設定明文是「booting macOS on **Apple silicon**」；虛擬化不改架構，10.14 沒有 arm64 版本 |
| 2b | 用 UTM/QEMU **模擬** x86_64 跑 macOS 10.14 | **Impossible in practice**（近乎 Impossible） | UTM 的 macOS guest 只走 Apple 虛擬化、只支援 macOS 12+ ARM guest；就算硬用 QEMU 模擬 x86，3D 加速（VirGL）官方明文「Linux only」，且多核模擬「以正確性為代價」 |
| 2c | 用 QEMU **模擬 PowerPC** 跑 Mac OS X 10.4/10.5，執行 universal binary 的 ppc slice | **Impossible in practice** | QEMU PowerMac 板子只模擬 "PCI VGA compatible card with VESA Bochs Extensions"，**沒有 3D GPU**；純 TCG 解譯的 PPC-on-ARM |
| 3 | 32-bit Mach-O 的翻譯／相容層 | **Impossible**（無可用方案） | 唯一找到的專案 `nmosier/86x64` 自述 "highly experimental… some **simple** 32-bit programs"，2022-03 後停更 |
| 4 | 社群的「64-bit 3.3.5a Mac client」 | **不存在**（未找到任何證據） | client 是封閉原始碼；社群流傳的 `.app` 是 Wine wrapper 或無法驗證的宣稱 |
| 5 | Wineskin / Porting Kit / Whisky 類 wrapper | **Works — 但跑的是 Windows client** | 這些工具自述就是「wine wrapped ports of **Windows** software」，與原生 Mac client 無關 |

**結論一句話：原生 3.3.5a Mac client 在 Apple Silicon 上沒有任何可行路徑。** 唯一能玩的是「**Windows** 版 3.3.5a client + 翻譯層」，那已經在 [macos-client-options.md 第 2 節](./macos-client-options.md)。本文唯一的**新增可行選項**是 §5.2 的 WoWSilicon。

---

## 2. Rosetta 2 與 32-bit（已驗證，且比前一篇更精確）

Apple 官方文件 `https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment`（以 `developer.apple.com/tutorials/data/...json` 取得完整內文）：

> "Rosetta is a translation process that allows users to run Mac apps that contain **x86_64** instructions on Apple silicon."

不翻譯清單（**同樣沒有列出「32-bit」**，這點與前一篇筆記一致）：

> "Rosetta can translate most Intel-based apps, including apps that contain just-in-time (JIT) compilers. However, Rosetta doesn't translate the following executables:"
> - "Kernel extensions"
> - "**Virtual Machine apps that virtualize x86_64 computer platforms**"

指令集範圍：

> "Rosetta translates all [x86_64] instructions, including ones from the AVX and AVX2 instruction set, but it doesn't support the execution of AVX512 vector instructions."

**Rosetta 終止時程（現在已寫進這份文件本身，不只在 developer news）：**

> "Rosetta was designed to make the transition to Apple silicon easier, and will be available **through macOS 27** — as a general-purpose tool for Intel apps… Beyond this timeframe, we will keep a subset of Rosetta functionality aimed at supporting **older unmaintained gaming titles, that rely on Intel-based frameworks**."

> **新發現，且對第 2 節很重要：** 同一份文件另寫
> > "**macOS 27 directly integrates support for Intel binary translation**, without needing to install Rosetta. This enables support for **Intel Linux binaries running in ARM virtual machines (VMs) as well as Intel Linux containers.**"
>
> 注意它明說的是 **Intel Linux**。Apple 對「在 ARM VM 內跑 Intel 程式碼」的支援範圍是 Linux，**不是 macOS guest**。這反過來證實 §3 的結論。

### 裁決：**Impossible**

**推論鏈（誠實標註，非 Apple 明文）：**

1. Apple 對 Rosetta 的範圍描述一律是 **x86_64**，從未出現 i386 / 32-bit。
2. 32-bit Mach-O 在 Catalina 以後根本無法被 `dyld` 載入 —— 執行失敗發生在 **loader 層**，比 Rosetta 有機會介入還早。
3. 因此「Rosetta 2 不翻譯 32-bit Intel 執行檔」在**結果上**是確定的，但**不能當成 Apple 的引用句**。這與 [macos-client-options.md §1.2](./macos-client-options.md) 的標註一致。

---

## 3. 跑一個還支援 32-bit 的舊 macOS

必須支援 32-bit → 最新只能到 **macOS 10.14 Mojave**（Apple 支援文件 `https://support.apple.com/en-us/103076`：*"in 2018 Apple informed them that macOS Mojave 10.14 would be the last version of macOS to run 32-bit apps."*）。

### 3.1 虛擬化（Virtualization framework）—— **Impossible**（已驗證）

Apple `VZMacPlatformConfiguration` 文件（`https://developer.apple.com/documentation/virtualization/vzmacplatformconfiguration`）的 abstract 只有一句，但足夠決定性：

> "The platform configuration for booting macOS **on Apple silicon**."

（metadata：`introducedAt: 12.0`，即 macOS 12 Monterey 起。）

Virtualization framework 總覽（`https://developer.apple.com/documentation/virtualization`）：

> "The Virtualization framework provides high-level APIs for creating and managing virtual machines (VM) on Apple silicon and Intel-based Mac computers."

**關鍵在於「虛擬化」的定義本身：它直接在宿主 CPU 上執行 guest 指令，不做架構轉換。** 佐證來自 Apple 自己在 Rosetta 文件裡的那句排除條款——*"Rosetta doesn't translate… Virtual Machine apps that **virtualize x86_64 computer platforms**"*：Apple 明確把「在 Apple Silicon 上虛擬化 x86_64 平台」列為不支援。

再加上時間線（Apple newsroom，`https://www.apple.com/newsroom/2020/11/apple-unleashes-m1/`，2020-11-10）：

> "**macOS Big Sur** Optimized for M1"
> "This is the beginning of a transition to a new family of chips designed specifically for the Mac."

**推論（清楚可靠）：** 首批 Apple Silicon Mac 隨 **macOS 11 Big Sur** 出貨；**macOS 10.14（2018）比 Apple Silicon 早兩年，根本不存在 arm64 build**。所以無論宿主端是 Apple 的 Virtualization、Parallels 還是 VMware Fusion（三者在 Apple Silicon 上都建立於同一個「guest 架構＝宿主架構」前提），**macOS 10.14 guest 是不可能的**。

### 3.2 模擬（UTM / QEMU）—— **Impossible in practice** （已驗證）

UTM 是 QEMU 的前端，其文件是該工具的 primary source。

**(a) UTM 的 macOS guest 只有一條路，而且是 ARM 的：**

`https://docs.getutm.app/guest-support/macos/`：

> "**macOS 12+** macOS guests are supported on **Apple Silicon hosts** running macOS 12 or higher."
> "In the new VM wizard, select **“Virtualization”** and then **“macOS 12+”** to install macOS as a guest. If either option is not available, your system does not support macOS guests."
> "The **Apple Virtualization backend** used to virtualize macOS does not support many UTM features."

→ UTM **沒有提供任何「模擬 x86 跑 macOS guest」的選項**；它的 macOS guest 完全建立在 Apple Virtualization 之上，最低 guest 版本是 **macOS 12**，遠高於需要的 10.14。

**(b) 就算硬走 QEMU 的 x86_64 模擬，UTM 自己說了會發生什麼：**

`https://docs.getutm.app/settings-qemu/system/`：

> "**Virtualization requires the guest architecture to match the host.** That means x86_64 for Intel Macs and aarch64 for Apple Silicon. If the guest architecture does not match the host, virtualization will not be used even if enabled in the QEMU settings."
> "A typical example of strong-on-weak is attempting to emulate **x86_64/i386 on an ARM host**. In these cases, **QEMU does not guarantee the correctness of the emulation.**"

`https://docs.getutm.app/guides/windows/`（講的是 Windows，但描述的是同一個 x86-on-ARM 模擬機制）：

> "if you are installing x86_64 Windows on an Apple Silicon Mac, the default setting is to use **only a single core**. This is because due to memory ordering requirements, **emulating multiple x86_64 cores on an ARM64 system will be done on a single core** and thus reduce performance. **At the cost of correctness**, you can force multiple cores…"

**(c) 3D 加速：對 3D 遊戲而言這一條就直接判死刑。**

`https://docs.getutm.app/settings-qemu/devices/display/`：

> "The devices labeled “(GPU Supported)” support VirGL hardware accelerated rendering… **Currently, the drivers to support this feature are Linux only.** VirGL is an experimental feature and not all applications are supported. **Some 3D games and applications may crash or freeze up the VM.**"

UTM FAQ（`https://getutm.app/faq/`，該頁語境是 iOS 版，但陳述的是同一套 QEMU 限制）：

> "There is also **no support for GPU virtualization so that means no DirectX or OpenGL. This makes most modern games non-playable.**"

### 裁決：**Impossible in practice**

- **理論上**：QEMU 能模擬 i386/x86_64 機器。
- **實際上**：(i) UTM 根本沒有 macOS-on-x86 guest 的安裝路徑；(ii) 即使自己拼裝出一個 x86 macOS guest，**單核指令模擬 + 零 3D 加速 + 官方明說不保證正確性**。3.3.5a 是 3D 遊戲，圖形要走 OpenGL → 而 guest 端的 OpenGL 只有軟體 rasteriser。
- **直說：這不是「會很慢」，是「連可玩的邊都摸不到」。** 別把時間花在這條路上。

> **未驗證：** 沒有實測過。本節純粹是「工具自己的文件說它不支援 / 沒有加速」，不是量測數據。任何「幾 FPS」的說法都是捏造。

### 3.3 順帶一提：ppc slice + QEMU PowerPC —— **Impossible in practice**

3.3.5a Mac client 是 **PPC/Intel universal binary**（見前一篇 §1.3），所以理論上可以繞過 Intel 完全不談，改跑 **ppc slice**：QEMU 有 PowerMac 模擬，Mac OS X 10.4/10.5 是 PPC 系統。

QEMU 官方文件 `https://www.qemu.org/docs/master/system/ppc/powermac.html`（QEMU 11.1.50）列出 `g3beige` / `mac99` 模擬的周邊：

> "PCI **VGA compatible card with VESA Bochs Extensions**"

**沒有任何 3D GPU。** 一張 VGA/Bochs 框架緩衝區不可能跑 2010 年的 3D 遊戲；再加上 PPC-on-ARM 是純 TCG 動態翻譯。

> **未驗證：** QEMU 文件並未把 Mac OS X 列為支援的 PowerMac guest（Missing devices 一欄寫的是 "To be identified"）。本節只論證「就算裝得起來，圖形也不可能」。

---

## 4. 有沒有 32-bit Mach-O 的翻譯／相容層？ —— **沒有可用的**

誠實搜尋後，**唯一找到的專案**是 `https://github.com/nmosier/86x64`。其 README（primary，該專案自己的話）：

> "Convert 32-bit i386 executables to 64-bit x86_64 executables. With macOS 10.15, Apple dropped support for running 32-bit executables under 64-bit macOS."
> "## Development Status
> 86x64 is still in a **highly experimental** stage. It can currently translate **some simple 32-bit programs** to 64 bits -- for examples, see the `tests/` directory."

GitHub API metadata：`created_at 2020-03-26`、**`pushed_at 2022-03-28`（三年半未更新）**、38 stars、**無 license**、C++。

### 裁決：**Impossible**

- 這是一個學術性質的靜態改寫實驗，目標是「簡單的 32-bit 程式」，不是一個 300 MB、含 D3D/OpenGL、有自我完整性檢查的商業遊戲二進位檔。
- 而且它處理的是 **Intel slice**，就算成功產出 x86_64 binary，在 Apple Silicon 上仍要再過一層 Rosetta 2 —— 而 Rosetta 2 已公告 macOS 27 到期。
- **沒有找到任何商業產品**做這件事。

> **標註：** 這是「已盡力搜尋後未找到可用方案」，不是「已證明不可能存在」。但考量 Apple 自 2019 年就移除了 32-bit 執行環境，六年來沒有任何專案填補這個缺口，這個空白本身就是強訊號。

---

## 5. 「64-bit 3.3.5a Mac client」的社群宣稱

### 5.1 裁決：**不存在**（未找到任何證據，且技術上不合理）

**技術論證（與前一篇 §2.6 一致）：** client 是 Blizzard 的封閉原始碼二進位檔。要產生「真正的 64-bit Mach-O」必須**重新編譯**，而重新編譯需要原始碼。社群只能做 binary patch（改 realmlist、繞版本檢查），那**不會改變 Mach-O 的架構欄位**。從 32-bit 改成 64-bit 涉及指標寬度、ABI、呼叫慣例、結構佈局全面改變，不是能靠 patch 完成的事。

**社群自己的說法也一致**（Warmane 官方論壇，**SECONDARY / 論壇發言，僅作為「社群共識」的紀錄**，不作為技術權威）：

- `https://forum.warmane.com/showthread.php?t=401398`（標題就叫 "64-bit client for WotLK 3.3.5a (Mac)"，2019-04 開串）：
  > "**Unless Blizzard releases 3.3.5 source there's no way of "updating" it to 64bit.** Don't update. Use Bootcamp. Use a VM or install Linux."
- `https://forum.warmane.com/showthread.php?t=412281`：
  > "**There is no 64 bit wotlk client.**"
- `https://forum.warmane.com/showthread.php?t=409145`：
  > "No, you can not simply convert and/or modify the file to suddenly make it "64bit."… Warmane has stated in the past that they **have no intention on modifying the client**"

**三分法（依原始問題要求）：**

| 類別 | 是否找到？ | 說明 |
|---|---|---|
| **(a) 真正的 64-bit Mac 原生二進位檔** | **否** | 未找到任何證據。技術上需要 Blizzard 原始碼。 |
| **(b) 包裝 Windows client 的 wrapper（Wineskin / Porting Kit 風格）** | **是，且確實存在** | 這是社群流傳的 `.app` 的真實身分。見 §5.2。**它不是 Mac client。** |
| **(c) 無法驗證的宣稱** | **是** | 例：上述 401398 串中有人自述 "I was collecting 64-bit client .app files which I found. The problem is, that **every of this .app files has different bug**" —— 沒有來源、沒有雜湊、沒有架構證據。**本文不記錄、不追查、不提供任何此類檔案的連結**；執行來路不明的遊戲執行檔有實質安全風險。 |

**驗證任何此類宣稱的方法（一行指令）：** 對聲稱的 `.app` 執行

```
file <App>.app/Contents/MacOS/<binary>
lipo -archs <App>.app/Contents/MacOS/<binary>
```

若輸出含 `x86_64` 且**不是** Wine/Wineskin 的 launcher stub，才值得繼續談。實務上：`.app` 內若出現 `drive_c`、`wineskin`、`wswine.bundle` 之類的目錄，那就是 (b)。

### 5.2 **本次調查唯一的新可行選項：WoWSilicon（跑 Windows client）**

`https://github.com/WoWSilicon/WoWSilicon`（GPL-3.0，110 stars，`created_at 2026-05-01`，**`pushed_at 2026-09-03`，積極開發中**）。README 自述：

> "WoWSilicon is a macOS launcher for older World of Warcraft clients on Apple Silicon Macs."
> "It bundles a customized **Wine** runtime alongside **RosettaX87**, **DX9 translation**, and game patching so clients from the 2006-2010 era can run efficiently on modern macOS hardware."

支援 client：

> "Vanilla 1.12.1 / The Burning Crusade 2.4.3 / **Wrath of the Lich King 3.3.5a** / … Other **32-bit Direct3D 9 games** through Non-WoW profiles"

需求：

> "Apple Silicon Mac / **macOS 15 or newer** / A **legally acquired** local World of Warcraft client folder"

其官網 `https://wowsilicon.github.io/` 標語：

> "Launch classic World of Warcraft on Apple Silicon—**without CrossOver**."

依賴的上游元件（README 的 Credits 段，全部是它自己列的）：

- `D9VK` — "Direct3D 9 translation through Vulkan"
- `MTLd3D` — "Direct3D 9 translation through Metal"
- `rosettax87_jit` — "**accelerated x87 translation for Rosetta 2**"
- `x87sidecar` — "isolated, cooperative x87 acceleration"
- `vanilla-tweaks`

**為什麼這對本文重要（三點）：**

1. **它跑的是 Windows client，不是 Mac client。** 「32-bit Direct3D 9」「Wine」「game folder」都指向 Windows 版。**它不構成原生 Mac client 的解法**，只是把前一篇的 CrossOver 路徑換了個免費、開源、專門為 3.3.5a 調校的實作。
2. **它補上了前一篇的一個空白：** [macos-client-options.md §2.4](./macos-client-options.md) 標註「D3DMetal 支援哪些 D3D 版本無第一方文件」。WoWSilicon 的做法直接回答了實務問題 —— 它**自己捆了 D3D9→Metal / D3D9→Vulkan 的translation layer**，不指望 Apple 的 D3DMetal。
3. **它同樣綁在 Rosetta 2 上。** `rosettax87_jit` 明說是 "for Rosetta 2"，所以它**繼承了 macOS 27 這個到期日**，跟 CrossOver 一樣（見 §2）。這一點不能忽略。

> **未驗證：** 本文未實測 WoWSilicon，未驗證其效能、穩定性或安全性。README 自述其 release 為 **unsigned build**（需 `xattr -dr com.apple.quarantine`）。這是陳述其存在與自述能力，**不是背書**。
> **未驗證：** 未確認 WoWSilicon 在 Rosetta 2 於 macOS 27 之後失效時是否有替代方案（Apple 那句「older, unmaintained gaming titles… will continue to be supported」語意仍然模糊，見前一篇 §2.1）。

---

## 6. Wineskin / Porting Kit / Whisky —— 澄清常見誤解

**這些工具跑的是 Windows 二進位檔，不是 32-bit Mac 二進位檔。** 用它們的自述來確認：

- **Wineskin 的官方後繼者是 Sikarugir**（`https://github.com/Sikarugir-App/Sikarugir`，原 `Gcenx/WineskinServer` 已 301 導向此處）：
  > "A tool used to make user-friendly **wine wrapped ports of Windows software** for macOS."
  > "**Sikarugir** — A wrapper project that's the **successor to Wineskin**. This project supports macOS 14 or later."
  > "**Apple Silicon systems also require Rosetta2** — `/usr/sbin/softwareupdate --install-rosetta --agree-to-license`"
  > "DirectX support: **WineD3D (default) Supports DirectX 11 and below.**"
  > ⚠ 其 README 亦有安全警語：*"If you came here from https://sikarugir.com scan your system for malware, that site is not affiliated, owned nor ran by the Sikarugir team!"*
- **Porting Kit**（`https://www.portingkit.com/`）網站標題就是：
  > "Porting Kit | **Install Windows apps in Mac**"
- **Whisky** —— 已於 2025-05-11 封存、作者明言停止維護（詳見 [macos-client-options.md §2.3](./macos-client-options.md)，此處不重複）。

### 裁決：**Works —— 但它解的是別的題目**

把 Windows 3.3.5a client 包進 wrapper 是可行的（Sikarugir 支援 DirectX 11 and below，涵蓋 3.3.5a 的 D3D9；且它明說 Apple Silicon 需要 Rosetta 2）。但**這整條路等同於 [macos-client-options.md §2.1–2.4](./macos-client-options.md) 的 CrossOver/Wine 路徑**：同樣的 Wine，同樣依賴 Rosetta 2，同樣有 macOS 27 的到期日。差別只在包裝與價格。

**因此本文不重複評估這條路。** 若要走它，看前一篇；若想要一個專為 3.3.5a 調校的免費實作，看 §5.2 的 WoWSilicon。

---

## 7. 誠實的最終答案

**原生 3.3.5a Mac client 在 Apple Silicon + 現行 macOS 上，沒有任何可行路徑。** 五條路全部走不通：

- Rosetta 2 只做 x86_64，32-bit 執行環境六年前就被移除了（§2）。
- 舊 macOS 這條，虛擬化不可能（沒有 arm64 的 10.14）、模擬不可玩（零 3D 加速）（§3）。
- 32-bit Mach-O 的翻譯層不存在可用實作（§4）。
- 64-bit 版的 Mac client 不存在，而且沒有 Blizzard 原始碼就不可能存在（§5）。
- Wineskin 家族跑的是 Windows 檔（§6）。

**唯一能玩的路是「Windows 版 3.3.5a client + 翻譯層」**，選項有三：CrossOver 26.x、WoWSilicon（免費開源，專為此調校）、或 Parallels + Windows 11 ARM64。**前兩者都依賴 Rosetta 2 因而共享 macOS 27 的到期日；只有 Parallels 那條沒有已知期限**（Windows on ARM 的 Prism/WOW64 自己模擬 32-bit x86）。完整比較見 [macos-client-options.md §2 與 §6](./macos-client-options.md)。

**給使用者的一句話：手上那份 Mac client 可以放下了 —— 你需要的是 Windows 版的檔案。**

---

## 8. 驗證方式

外部（皆為本次實際抓取；Apple 開發者文件經 `developer.apple.com/tutorials/data/documentation/<path>.json` 取得完整內文，一般 HTML 頁面因 JS 渲染會抓到空白）：

```
curl -sL https://developer.apple.com/tutorials/data/documentation/apple-silicon/about-the-rosetta-translation-environment.json
curl -sL https://developer.apple.com/tutorials/data/documentation/virtualization/vzmacplatformconfiguration.json
curl -sL https://docs.getutm.app/guest-support/macos/
curl -sL https://docs.getutm.app/settings-qemu/system/
curl -sL https://docs.getutm.app/settings-qemu/devices/display/
curl -sL https://www.qemu.org/docs/master/system/ppc/powermac.html
curl -s  https://api.github.com/repos/nmosier/86x64
curl -s  https://api.github.com/orgs/wowsilicon/repos
```

本機（若手上有任何聲稱是 64-bit 的 `.app`）：

```
file  <App>.app/Contents/MacOS/<binary>
lipo -archs <App>.app/Contents/MacOS/<binary>
ls    <App>.app/Contents/           # 出現 Resources/drive_c、wswine.bundle 即為 Wine wrapper
```

**取用失敗：** `https://docs.getutm.app/basics/basics/` 對 WebFetch 回 403（改用 curl 帶 UA 成功）；`https://forum.warmane.com/...` 對 WebFetch 回 403（同樣改用 curl 成功）。Apple 開發者文件的 HTML 版對 WebFetch 只回標題（JS 渲染），故一律改抓其 JSON API。

---

## 9. 實際取用過的來源

**Apple（PRIMARY）**
- `https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment` — Rosetta 範圍為 x86_64；不翻譯清單；macOS 27 到期；macOS 27 的 Intel-Linux-in-ARM-VM
- `https://developer.apple.com/documentation/virtualization/vzmacplatformconfiguration` — "booting macOS on Apple silicon"，macOS 12+
- `https://developer.apple.com/documentation/virtualization` — 框架總覽
- `https://developer.apple.com/documentation/virtualization/running-macos-in-a-virtual-machine-on-apple-silicon` — 官方 macOS guest 範例（全篇僅談 Apple Silicon）
- `https://support.apple.com/en-us/103076` — Catalina 起 32-bit 不相容；Mojave 為最後一版（**引用自前一篇**）
- `https://www.apple.com/newsroom/2020/11/apple-unleashes-m1/` — M1 隨 macOS Big Sur 出貨

**工具自己的文件 / repo（各自的 PRIMARY）**
- `https://docs.getutm.app/guest-support/macos/`、`.../settings-qemu/system/`、`.../settings-qemu/devices/display/`、`.../guides/windows/`、`https://getutm.app/faq/`
- `https://www.qemu.org/docs/master/system/ppc/powermac.html`
- `https://github.com/nmosier/86x64`（README + GitHub API metadata）
- `https://github.com/WoWSilicon/WoWSilicon`、`https://wowsilicon.github.io/`
- `https://github.com/Sikarugir-App/Sikarugir`（Wineskin 後繼者）
- `https://www.portingkit.com/`

**SECONDARY（僅作社群共識紀錄，非技術權威）**
- `https://forum.warmane.com/showthread.php?t=401398`、`?t=412281`、`?t=409145`
