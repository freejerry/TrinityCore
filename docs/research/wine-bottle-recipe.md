# 在 Apple Silicon / macOS 26.5.2 上用 Wine 11.13 從零建一個 bottle 跑 WoW Classic 3.4.3.54261（研究筆記）

> 撰寫日期：2026-09-04
> 相關筆記（**前置閱讀**，本文不重複其結論）：
> - [macOS / Apple Silicon 上玩 WotLK 內容](./macos-client-options.md) —— CrossOver / Rosetta 2 / macOS 27 到期日、client 取得問題
> - [3.3.5a 原生 Mac client 能不能在 Apple Silicon 上跑？](./mac-client-3.3.5a-on-apple-silicon.md) —— §5.2 首次記錄 WoWSilicon
> - [WoW 3.3.5a 在 Whisky/Wine 下的 ERROR #132](./wine-deps-wow335.md) —— Whisky 7.7 的 D3D9 缺口、WoWSilicon 的 8 個 patch、D3DMetal 無 D3D9 符號
>
> 來源限定 primary sources：Wine 原始碼樹（`wine-11.13` tag，經 GitHub 官方鏡像 `wine-mirror/wine`）、`wine(1)` / `wineboot(1)` man page 原始檔、Wine release ANNOUNCE、WineHQ wiki（經 Wayback，見 §8「取用失敗」）、Apple 的 `dyld(1)` man page 與 developer.apple.com、Homebrew formula/cask metadata（本機 `brew info --json`）、Gcenx / DXVK / vkd3d-proton / MoltenVK / WoWSilicon 各自的 repo 與原始碼、以及**本機唯讀實測**。
> 凡未經驗證者一律標示「**未驗證**」。**本文除了這個檔案本身，未修改磁碟上任何東西**：沒有建立 prefix、沒有執行 `wineboot`、沒有啟動任何 client。git 全程唯讀。

---

## 0. 一句話結論（TL;DR）

**是的，一個 stock upstream Wine 11.13 的 bottle 在架構上有一條完整的 D3D12 路徑可以跑 3.4.3 —— 而且不需要 GPTK/D3DMetal。** 這條路是：

```
WowClassic.exe (PE32+ x86-64)
  → Wine builtin d3d12.dll  == vkd3d 1.18（Wine 11.0 起隨附，含 DXIL/SM6 支援）
    → winevulkan.so → win32u.so 直接 dlopen("libMoltenVK.dylib")
      → Metal
```

每一段都有第一方證據（§3.1）。**這與前一篇筆記對 3.3.5a 的結論相反**，原因很單純：3.3.5a 需要的是 **D3D9**，而 upstream Wine 的 D3D9 只有 wined3d→OpenGL；3.4.3 需要的是 **D3D12**，而 upstream Wine 的 D3D12 是 vkd3d→Vulkan，**Wine 的 configure 明文支援用 MoltenVK 當 Vulkan**。

**但有三個必須誠實講的但書：**

1. **「架構上通」不等於「實測會跑」。本文沒有實測。** vkd3d 判定 feature level 11_0 時檢查的 `geometryShader`、`pipelineStatisticsQuery`、`shaderCullDistance` 三項，**MoltenVK 原始碼裡從頭到尾都沒有設成 true**（§3.1(d)）。好消息是 vkd3d 把 `max_feature_level` **無條件**設成 11_0，這三項只影響能不能升到 11_1，所以 `D3D12CreateDevice` 不會因此被拒絕；壞消息是遊戲若在執行期真的用到 geometry shader，就會踩到洞。**這是本題最大的未知數。**
2. **你拿不到「純上游」的 Wine 11.13 macOS binary —— WineHQ 自己不出 macOS 套件了。** 現實上的選項只有 **Gcenx 的 `wine-devel-11.13-osx64.tar.xz`**（WineHQ 官方 wiki 與 Homebrew cask 都指向它）或自己 build。而它是 **x86_64**，所以**整條路仍然跑在 Rosetta 2 上**，仍然繼承 macOS 27 的到期日。
3. **3.4.3 client 其實支援 `SET gxApi "d3d11"`**（本機從 `WowClassic.exe` 字串表實測，§3.2）。這給了第二條路，但 stock Wine 的 d3d11 走 wined3d，而 wined3d 的 Vulkan renderer 在 MoltenVK 上**被證明**只能到 feature level 9_x（§3.3），所以 d3d11 這條實際上只剩 wined3d→OpenGL，期望值比 D3D12 那條**低**。

**Recipe 標題句：** `brew install --cask --no-quarantine wine@devel`（或抓 Gcenx 11.13 tarball）→ `WINEARCH=win64 WINEPREFIX=~/.wow343 wineboot -i` → **不裝任何 winetricks verb**（沒有任何 primary source 為現代 WoW 推薦過任何一個）→ **不設任何 DLL override**（builtin d3d12=vkd3d 就是要用的東西）→ 憑證用 `security add-trusted-cert` 進 macOS keychain，讓 Wine 的 crypt32 自己匯入。完整版見 §6。

---

## 1. 上游 Wine 在 macOS 上到底需要什麼

### 1.1 Wine 自己的 `README.md`（`wine-mirror/wine` master，逐字）

```
## REQUIREMENTS

To compile and run Wine, you must have one of the following:
...
- macOS 10.15 or later
...
**macOS info**:
  You need Xcode/Xcode Command Line Tools or Apple cctools.
...
**Optional support libraries**:
  Configure will display notices when optional libraries are not found
  on your system. See https://gitlab.winehq.org/wine/wine/-/wikis/Building-Wine
  for hints about the packages you should install.
```

**注意 README 本身沒有列出具體的 library 清單** —— 它把責任推給 wiki 與 `configure` 的 notice。所以要知道「缺哪個會壞什麼」，只能直接讀 `configure.ac`。

### 1.2 `configure.ac`（`wine-11.13` tag）—— 缺了會怎樣，逐條

| 依賴 | `configure.ac` 的處置 | 缺了的後果（逐字） |
|---|---|---|
| **freetype** | `WINE_ERROR_WITH(freetype, ...)` | `FreeType development files not found. Fonts will not be built.` —— 這是 **ERROR**，configure 會直接失敗 |
| **gnutls** | `WINE_WARNING_WITH(gnutls, ...)` | `libgnutls development files not found, no schannel support.` —— **沒有 schannel 就沒有 TLS**，對要連 HTTPS 的 client 是致命的 |
| **vulkan / MoltenVK** | `WINE_NOTICE_WITH(vulkan, ...)` | `libvulkan and libMoltenVK development files not found, Vulkan won't be supported.` |
| **SDL2** | `WINE_NOTICE_WITH(sdl, ...)` | `libSDL2 development files not found, SDL2 won't be supported.`（影響 gamepad/HID） |

**最關鍵的一段（本題的核心證據）—— `configure.ac` 第 1940–1950 行：**

```
dnl *** Check for Vulkan ***
if test "x$with_vulkan" != "xno"
then
    WINE_CHECK_SONAME(vulkan, vkGetInstanceProcAddr)
    if test "x$ac_cv_lib_soname_vulkan" = "x"
    then
        WINE_CHECK_SONAME(MoltenVK, vkGetInstanceProcAddr, [AC_DEFINE_UNQUOTED(SONAME_LIBVULKAN,["$ac_cv_lib_soname_MoltenVK"])])
    fi
fi
```

> **這是 upstream Wine 官方原始碼，明文把 MoltenVK 當作 Vulkan loader 的 fallback。** 「Wine 在 macOS 上跑 Vulkan」不是社群 hack，是 upstream 支援的組態。

執行期的另一半在 `dlls/win32u/vulkan.c`：

```c
#ifdef SONAME_LIBVULKAN
    vulkan_handle = dlopen( SONAME_LIBVULKAN, RTLD_NOW );
    if (!vulkan_handle) ERR( "Failed to load %s\n", SONAME_LIBVULKAN );
#else
    ERR( "Wine was built without Vulkan support.\n" );
#endif
```

**本機實測佐證：** Homebrew 裝的 `wine-stable 11.0_1` 裡，**只有 `win32u.so` 這一個檔案含有字串 `libMoltenVK.dylib`**，而該 bundle 的 `lib/` 底下確實放著一份 `libMoltenVK.dylib`（`lipo -archs` = `x86_64`）。`winemac.so` 則連結了 `Metal.framework` 與 `OpenGL.framework`，且含有 `vkCreateMetalSurfaceEXT` / `Failed to create MoltenVK surface, res=%d` 字串 —— **winemac.drv 的 Vulkan surface 支援是 upstream 就有的**。

### 1.3 WineHQ wiki 的 macOS 依賴清單（**注意：已過時**）

`https://wiki.winehq.org/MacOS/Building`（Wayback `20240627185044`，頁面自述 *"This page was last edited on 4 May 2023"*，內文明講清單是給 **wine-8.x** 的）：

> **Build dependencies;**
> `brew install --formula bison mingw-w64 pkgconfig`
> **Runtime dependencies;**
> `brew install —-formula freetype gnutls molten-vk sdl2`
> Please note: Homebrew doesn't add bison to $PATH so this needs to be handled manually.

以及非常重要的一句（解釋了本題所有 dylib 找不到的問題）：

> "Wine uses standard **dlopen()** to find libraries meaning wine will only check standard location **/usr/local/lib & /usr/lib** so wine will have trouble finding the needed libraries when using macports and XQuartz."

同頁另外兩句對 Apple Silicon 讀者要打折扣看：

> "From macOS Catalina Apple removed 32-bit support, which makes it impossible to use 32-bit Wine."（✅ 仍然成立，但 §4 說明 new WoW64 已經繞過這件事）
> XQuartz 那一整節 —— 對 3.4.3 完全不需要，Gcenx 的 build 就是 `--without-x`。

**Gcenx 自己 README 的 runtime 依賴清單（比 wiki 新，且就是本機這份 binary 的來源）：**

> **Runtime dependencies**
> `freetype` / `gstreamer-runtime` / `gnutls` / `libinotify` / `libsdl2` / `moltenvk` / `vulkan-loader`

### 1.4 `wine(1)` man page 記載的環境變數（逐條，全部來自 `tools/wine/wine.man.in`）

| 變數 | man page 的原話（節錄） |
|---|---|
| `WINEPREFIX` | *"the name of the directory where Wine stores its data (the default is `$HOME/.wine`). This directory is also used to identify the socket which is used to communicate with the wineserver."* |
| `WINESERVER` | *"Specifies the path and name of the wineserver binary. If not set, Wine will look for a file named "wineserver" in the path and in a few other likely locations."* |
| `WINEDLLPATH` | *"Specifies the path(s) in which to search for builtin dlls and Winelib applications. This is a list of directories separated by ":". In addition to any directory specified in WINEDLLPATH, Wine will also look in the installation directory."* |
| `WINEDLLOVERRIDES` | *"Defines the override type and load order of dlls... native windows dlls (native) and Wine internal dlls (builtin). The type may be abbreviated with the first letter of the type (n or b). The library may also be disabled ('')."* 例：`WINEDLLOVERRIDES="comdlg32=b,n;shell32=b;comctl32=n;oleaut32="` |
| `WINEARCH` | *"It can be set to **win32** (support only 32-bit applications), to **win64** (support both 64-bit applications and 32-bit ones), or to **wow64** (support 64-bit applications and 32-bit ones, using a 64-bit host process in all cases)."* 並且：*"The architecture supported by a given Wine prefix is set at prefix creation time and cannot be changed afterwards. When running with an existing prefix, Wine will refuse to start if WINEARCH doesn't match the prefix architecture."* |
| `WINE_D3D_CONFIG` | *"Specifies Direct3D configuration options. It can be used instead of modifying the `HKEY_CURRENT_USER\Software\Wine\Direct3D` registry key."* 例：`WINE_D3D_CONFIG="renderer=vulkan;VideoPciVendorID=0xc0de"` |
| `WINEDEBUG` | 除錯訊息開關，`WINEDEBUG=warn+all` 等 |
| `WINEPATH` | 追加到 Windows `PATH` 前面的目錄（Windows 風格、`;` 分隔） |

> **必須點名的三件事：**
> 1. **`WINELOADER` 不在 `wine(1)` man page 裡。** 它確實存在於 Wine 原始碼中，但**沒有被 man page 記載**。本文不把它當成「有文件的」變數。
> 2. **`DYLD_FALLBACK_LIBRARY_PATH` 不是 Wine 的變數，是 Apple 的。** `dyld(1)` man page（本機 `man 1 dyld`）：*"This is a colon separated list of directories that contain libraries. If a dylib is not found at its install path, dyld uses this as a list of directories to search for the dylib. **For new binaries (Fall 2023 or later) there is no default.** For older binaries, there is a default fallback search path of: /usr/local/lib:/usr/lib."*
> 3. `WINEARCH` 的三值 `win32` / `win64` / `wow64` 是 §4 的關鍵。

### 1.5 **「怎麼從 shell 跑一個 bundled/relocatable 的 Wine」—— 有文件，但只涵蓋 WineHQ 自己的包**

WineHQ wiki macOS 頁（Wayback `20240828190806`）對**自家 tarball** 明文寫：

> "To install from a tarball archive, simply unpack it into any directory. **There is no need to set DYLD_\* environment variables; all paths are relative**, so it should work as long as the directory structure is preserved (you can skip the /usr prefix though using `--strip-components 1`)."

同頁對 Homebrew：

> `brew install --cask --no-quarantine (selected wine package)` —— `wine-stable`, `wine@devel` or `wine@staging`
> "**The advantage of installing via homebrew means wine is available from a standard terminal session.**"
> "The --no-quarantine line is to avoid brew adding the quarantine flag."

以及對第三方包的立場（**這就是本小節的答案**）：

> "**Third party versions of Wine, such as Wineskin, Winebottler, and PlayOnMac, are not supported by WineHQ.** If you are using one of those products, please retest in plain Wine before filing bugs..."

**→ 結論：對「像 WoWSilicon 或 Whisky 那樣的 bundle 怎麼從 shell 跑」，WineHQ 沒有、也不打算提供文件。這兩個專案的 repo 裡也沒有任何 shell wrapper 或說明。呼叫端只能自己複製 app 的環境。**

而 WoWSilicon 的環境長什麼樣，可以從它自己的原始碼精確讀出（`Sources/WoWSiliconSwift/Services/BundledWineRuntime.swift`，`makeEnvironment()`）：

```swift
result["WINEPREFIX"] = winePrefixURL.path
// externalURL = <Wine>/lib/external
result["DYLD_LIBRARY_PATH"] = existing.isEmpty ? externalURL.path
                                              : "\(externalURL.path):\(existing)"
```

同檔另有一個 escape hatch：`static let environmentOverride = "WOWSILICON_WINE_RUNTIME"`（可指定 runtime 根目錄）。

**這就完整解釋了使用者遇到的那則錯誤。** 它的字面出處是 Wine 的 `dlls/win32u/freetype.c`：

```c
ft_handle = dlopen(SONAME_LIBFREETYPE, RTLD_NOW);
if(!ft_handle) {
    WINE_MESSAGE(
  "Wine cannot find the FreeType font library.  To enable Wine to\n"
  "use TrueType fonts please install a version of FreeType greater than\n"
  "or equal to 2.0.5.\n"
  "http://www.freetype.org\n");
    return FALSE;
}
```

**→ 這是一則 `dlopen()` 失敗，不是「Wine 壞了」。** WoWSilicon 把 `libfreetype` 放在 `<Wine>/lib/external/`，那不是 dyld 的標準搜尋路徑；App 啟動時會設 `DYLD_LIBRARY_PATH` 指過去，**直接從 shell 呼叫它的 `bin/wine` 就沒有這一步**。要手動跑，就得自己補上（**未驗證**，本文未執行）：

```sh
WS=/Applications/WoWSilicon.app/Contents/Resources/Wine
DYLD_LIBRARY_PATH="$WS/lib/external:$DYLD_LIBRARY_PATH" \
WINEPREFIX=... "$WS/bin/wine" --version
```

> **對比：Homebrew 那份（Gcenx）不需要這樣做。** 本機 `otool -L .../bin/wine` 只依賴 `/usr/lib/libSystem.B.dylib`，`/opt/homebrew/bin/wine` 只是一個指向 `/Applications/Wine Stable.app/Contents/Resources/wine/bin/wine` 的 symlink，而 `wine --version` 直接在 shell 裡就印出 `wine-11.0`。**這正是 wiki 說的 "all paths are relative"。**

---

## 2. 在 Apple Silicon 上取得 Wine 11.13 的實際選項

### 2.1 Homebrew（**推薦，且 WineHQ wiki 自己就是這樣教的**）

**這裡有一個必須先澄清的誤解：Homebrew 沒有 wine formula，只有 cask，而 cask 內容就是 Gcenx 的包。** 本機 `brew info --json=v2 --cask` 實測（2026-09-04）：

| cask | version | url |
|---|---|---|
| `wine-stable` | **11.0_1** | `https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz` |
| `wine@devel` | **11.16** | `https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.16/wine-devel-11.16-osx64.tar.xz` |
| `wine@staging` | **11.16** | `https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.16/wine-staging-11.16-osx64.tar.xz` |

三者的 `homepage` 都是 `https://wiki.winehq.org/MacOS`，`depends_on` 都只有 `{"macos": {}, "cask": ["gstreamer-runtime"]}`。

> **`depends_on` 裡沒有 Rosetta。** cask metadata **完全沒有記載 Rosetta 需求**。唯一的第一方陳述在 WineHQ wiki macOS 頁：*"Only supports macOS Catalina (10.15.4) or later, **wine also works on Apple Silicon systems via Rosetta2**."*
> Gcenx README 也一樣沒提 Rosetta，只寫：*"these packages prove `wine` that works for 32 & 64-bit windows binaires."*

**Homebrew 拿不到 11.13。** cask 只追最新版；`wine@devel` 現在是 11.16。要精準拿 **11.13**，只能直接抓 Gcenx 的 release（**本次實測 HTTP 200**）：

```
https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.13/wine-devel-11.13-osx64.tar.xz     (189,855,828 bytes)
https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.13/wine-staging-11.13-osx64.tar.xz   (192,152,268 bytes)
```
（tag `11.13`，`published_at 2026-07-17T17:13:02Z`。）

### 2.2 本機這份 `wine-stable 11.0_1` 到底支援什麼（**全部唯讀實測**）

| 檢查 | 結果 |
|---|---|
| `wine --version` | `wine-11.0` |
| `lipo -archs .../bin/wine` | **`x86_64`** —— 純 Intel，**全程 Rosetta 2** |
| `wine64` 存在嗎？ | **不存在**。`bin/` 只有 `wine`（符合 Wine 11.0 release notes：*"The `wine64` loader binary is removed"*） |
| `lib/wine/` 底下的目錄 | `i386-windows/`（812 檔）、`x86_64-windows/`（761 檔）、`x86_64-unix/`（30 檔） |
| **有沒有 `x86_32on64-unix/`？** | **沒有。** → 這是 **new WoW64**，不是 Whisky/CrossOver 的 `win32on64`（見 §4） |
| D3D 相關 builtin DLL | `d3d8/9/10/10_1/10core/11/12/12core`、`dxgi`、`wined3d`、`vulkan-1`、`winevulkan`、`opengl32`、`d3dx9_24`～`d3dx9_43`、`d3dcompiler_33`～`_47` —— **32-bit 與 64-bit 兩側都齊全** |
| unix 側 `.so` | `winemac.so`、`winevulkan.so`、`opengl32.so`（**沒有** `d3d*.so` —— 因為 D3D 全在 PE 側，這正是 new WoW64 的架構） |
| Vulkan | `lib/libMoltenVK.dylib`（**x86_64**）；bundle 內**沒有** vulkan-loader，`win32u.so` 直接 dlopen `libMoltenVK.dylib` |
| `winemac.so` 連結的 framework | `Metal`、`OpenGL`、`AppKit`、`QuartzCore`、`CoreVideo`、`IOKit`、`Security`… |
| `d3d12.dll` 的實作 | strings 命中 `vkd3d_create_device` / `Failed to create vkd3d instance, hr %#lx.` / `Could not find Vulkan physical device for DXGI adapter.` → **就是 vkd3d** |
| gecko / mono | Gcenx README：*"`wine-gecko` & `wine-mono` are included within these custom `Wine-*` packages"* |

> **本機已有一個現成的旁證：`~/.wine` 這個 prefix（建立於 2026-09-03 21:13，非本次建立）。** 它的 `system.reg` 開頭是 `#arch=win64`，`drive_c/windows/` 底下 **`system32/` 是 x86-64 PE、`syswow64/` 是 i386 PE**（`file` 實測），`system32/d3d12.dll` 與 `syswow64/d3d12.dll` 都在。**這證明這份 Wine 在這台 M 系列機器上確實建得起一個含 32-bit 側的 win64 prefix。**

**Gcenx 公佈的 configure 選項（README，逐字節錄關鍵幾行）：**

```
--build=x86_64-apple-darwin \
--enable-archs=i386,x86_64 \
--with-freetype  --with-gnutls  --with-gstreamer  --with-sdl  --with-vulkan \
--with-coreaudio --with-inotify --with-ffmpeg --with-opencl --with-pcap \
--without-x --without-wayland --without-alsa --without-pulse --without-dbus \
--with-mingw=/opt/local/libexec/llvm-mingw/bin/clang
```

`--enable-archs=i386,x86_64` **就是 new WoW64**（Wine 9.0 release notes：*"The new WoW64 mode... can be enabled by passing the `--enable-archs=i386,x86_64` option to configure."`）。

> **一處必須標記的不一致：** README 的清單裡也有 `--without-opengl`，但本機 binary 的 `winemac.so` 明確連結了 `/System/Library/Frameworks/OpenGL.framework`，且 `lib/wine/x86_64-unix/opengl32.so` 存在。**兩者矛盾，本文以本機 binary 為準，並把 README 的該行標為可能過時。未驗證。**

### 2.3 WineHQ 官方 macOS 套件 —— **已經沒有了**

WineHQ wiki macOS 頁的該節標題就叫 **"Installing Deprecated WineHQ packages"**：

> "Official WineHQ packages of the development and stable branches are available for **macOS 10.8 to 10.14** (Wine won't work on macOS Catalina 10.15 as 32-bit x86 support is required)."

**→ WineHQ 官方最後的 macOS 套件停在 10.14，是 old-WoW64 時代的產物，與 Apple Silicon 完全無關。今天 WineHQ 自己的 wiki 就把使用者導向 Homebrew（= Gcenx）或 MacPorts。**

### 2.4 自己 build

依 §1.2/§1.3：Xcode CLT + `bison mingw-w64 pkgconfig`（build）+ `freetype gnutls molten-vk sdl2`（runtime），然後 `./configure --enable-archs=i386,x86_64 ... && make`。

> **兩個現實的坑（皆為本機事實）：**
> 1. Homebrew 在 Apple Silicon 上裝的是 **arm64** 的 `molten-vk`（本機 `lipo -archs /opt/homebrew/opt/molten-vk/lib/libMoltenVK.dylib` = `arm64`，版本 1.4.2）。**arm64 的 MoltenVK 餵不了 x86_64 的 Wine。** 這正是 Gcenx 要自己 bundle 一份 x86_64 `libMoltenVK.dylib` 的原因。
> 2. 若真要 build **arm64 原生**的 Wine，Wine 10.0 release notes 說 ARM64EC/ARM64X *"still requires an experimental LLVM toolchain"*，而且 x86 模擬得靠外掛（見 §4）。**本文不建議走這條。**

### 2.5 CrossOver / Whisky / WoWSilicon / GPTK 的 bundled Wine —— 能不能拿來重用？

**GPTK：Apple 自己的 Homebrew formula 是最好的證據。** 本機 `apple/apple` tap 裡的 `game-porting-toolkit.rb`（檔頭 `# Copyright (C) 2023 Apple, Inc.`）：

```ruby
version "1.1"
url "https://media.codeweavers.com/pub/crossover/source/crossover-sources-22.1.1.tar.gz"
depends_on arch: :x86_64
...
wine32_configure_options = ["--enable-win32on64", "--with-wine64=../wine64-build", ...]
ENV.append "LDFLAGS", "... -Wl,-rpath,@executable_path/../lib/external"
```

**三件事因此確立：**
1. **GPTK 的 evaluation environment 是 CrossOver 22.1.1 的 Wine**，不是 upstream Wine，更不是 11.13。
2. 它是 **`--enable-win32on64`（old-style / CrossOver 專有的 32-on-64）**，與 §4 的 new WoW64 是兩套完全不同的東西。
3. `@executable_path/../lib/external` 這個 rpath 就是 D3DMetal 那些 dylib 的擺放慣例 —— 與[前一篇筆記](./wine-deps-wow335.md) §1.2 觀察到的 Whisky `lib/external/libd3dshared.dylib` 完全吻合。

> **注意版本落差：** Apple 官網現在講的是 **Game Porting Toolkit 4**（`https://developer.apple.com/games/game-porting-toolkit/`），而 `apple/apple` tap 裡的 formula 還是 **1.1**。`apple/game-porting-toolkit` repo（Apache-2.0，created 2026-06-08）的 README 更寫著 prerequisites 是 **macOS 27 + Xcode 27** —— **本機是 macOS 26.5.2，不符**。
> **未驗證：** 「能不能把 GPTK 的 `D3DMetal.framework` 抽出來塞進一個 upstream Wine 11.13」——**沒有任何 Apple 文件說可以，本文不建議、也未嘗試**。Apple 的授權是 evaluation 用途，且 D3DMetal 是為 CrossOver 那套 Wine 的 unix/PE 邊界建的。

**CrossOver / Whisky / WoWSilicon：** 見[前一篇筆記](./wine-deps-wow335.md) §7.3 的對照表，本文不重複。就本題（3.4.3 + D3D12）而言，**Whisky 的 wine-7.7 + D3DMetal 已經被使用者實測跑起來了**（見 §3.4），所以「重用可行」是已知事實；問題只在於它是 **archived 專案 + 2022 年的 Wine**。

---

## 3. 圖形後端：3.4.3（D3D12/D3D11，64-bit）與 3.3.5a（D3D9，32-bit）逐一裁決

### 3.1 3.4.3 走 D3D12：stock Wine **開箱就有**，不需要另外裝東西

**(a) d3d12.dll 是 builtin，且就是 vkd3d。** Wine 11.0 release notes「Bundled libraries」節：

> "**Vkd3d is updated to the upstream release 1.18.**"

本機 `wine-stable 11.0_1` 的 `lib/wine/x86_64-windows/d3d12.dll` 含字串 `vkd3d_create_device`、`Failed to create vkd3d instance`。

**(b) SM 6.0 / DXIL 支援存在。** `wine-11.13` 原始碼樹裡有 `libs/vkd3d/libs/vkd3d-shader/dxil.c`（**418,797 bytes**）。本機 3.4.3 的 `Logs/gx.log` 顯示 client 要的是 `Using shader family dx_6_0` —— **DXIL**。

**(c) vkd3d 的 Vulkan 需求非常低，而且原始碼裡直接點名 MoltenVK。** `libs/vkd3d/libs/vkd3d/device.c`：

```c
static const char * const required_device_extensions[] =
{
    VK_KHR_MAINTENANCE1_EXTENSION_NAME,
    VK_KHR_MAINTENANCE2_EXTENSION_NAME,
    VK_KHR_SHADER_DRAW_PARAMETERS_EXTENSION_NAME,
};

/* In general we don't want to enable Vulkan beta extensions, but make an
 * exception for VK_KHR_portability_subset because we draw no real feature from
 * it, but it's still useful to be able to develop for MoltenVK without being
 * spammed with validation errors. */
```

instance 只要 `VK_API_VERSION_1_0`（有 1.1 就用 1.1）。

> **對比 vkd3d-proton（另一個專案，Wine 沒有用它）的 README：** *"Vulkan 1.3 / Descriptor indexing with at least 1000000 UpdateAfterBind descriptors... `VK_EXT_robustness2`, `VK_KHR_push_descriptor`"*，而且該 README **全文沒有出現 macOS / MoltenVK / Apple / Metal 任何一次**。**不要把 vkd3d-proton 的門檻套到 Wine 內建的 vkd3d 上，兩者差非常多。**

**(d) 唯一的隱憂，也講清楚：feature level 11_0 的檢查項目 MoltenVK 三缺。** 同一份 `device.c` 的 `vkd3d_init_feature_level()`：

```c
CHECK_FEATURE(geometryShader);
...
CHECK_FEATURE(pipelineStatisticsQuery);
...
CHECK_FEATURE(shaderCullDistance);
...
vk_info->max_feature_level = D3D_FEATURE_LEVEL_11_0;      /* ← 無條件 */

if (have_11_0 && d3d12_options->OutputMergerLogicOp && ...)
    vk_info->max_feature_level = D3D_FEATURE_LEVEL_11_1;
```

而 MoltenVK 的原始碼 `MoltenVK/MoltenVK/GPUObjects/MVKDevice.mm`（`main` 分支）裡，`_features.geometryShader`、`_features.pipelineStatisticsQuery`、`_features.shaderCullDistance` **各出現 0 次** —— 三者從未被設為 true。MoltenVK 的使用手冊也自己承認其中一項：

> "**Pipeline statistics query pool using `VK_QUERY_TYPE_PIPELINE_STATISTICS` is not supported.**"（`Docs/MoltenVK_Runtime_UserGuide.md`，Known MoltenVK Limitations）

> **精確的裁決：** `have_11_0` 會是 `false`，但因為 `max_feature_level` 是**無條件**設成 11_0，`D3D12CreateDevice(minimum_feature_level = 11_0)` **不會**在 `if (vulkan_info->max_feature_level < create_info->minimum_feature_level)` 這關被擋下。所以**裝置建得起來**；只是 11_1 拿不到，而且若遊戲執行期真的用 geometry shader 就會出事。
> **這正好也解釋了[前一篇筆記](./wine-deps-wow335.md) §7.1 的 WoWSilicon patch 0002** —— 它放寬的正是 `geometryShader` / `pipelineStatisticsQuery` / `shaderCullDistance` 三項，只是它動的是 **wined3d**（見 §3.3），不是 vkd3d。

**(e) 遊戲目錄自帶的 `d3d12.dll` 會不會蓋掉 Wine 的？** 本機 `_classic_/d3d12.dll` 是 `PE32+ x86-64`、1,906,768 bytes、時間戳 2023-11-15，含 `D3D12CoreCreateLayeredDevice` / `Software\Microsoft\Direct3D\Direct3D12` / `Microsoft Corporation` —— **這是 Microsoft 的 D3D12 Agility SDK redistributable**。

Wine 的載入順序邏輯（`dlls/ntdll/unix/loadorder.c`，`version_heuristics()`）：

```c
static const struct { WCHAR name[32]; enum loadorder lo; } vendors[] =
{
    { L"Microsoft",          LO_DEFAULT },
    { L"Twain Working Group", LO_BUILTIN },
    { L"",                    LO_NATIVE_BUILTIN }
};
```

> **推論（標示為推論）：** 該 DLL 的 version resource `CompanyName` 若是 `Microsoft Corporation`，Wine 會給它 `LO_DEFAULT`（= 走預設策略、偏好 builtin），而不是 `LO_NATIVE_BUILTIN`。**也就是說 Wine 應該會用自己的 vkd3d 版 `d3d12.dll`，而不是遊戲目錄那份 Agility SDK。** 這是好事 —— Agility SDK 需要真正的 D3D12 UMD 驅動，在 Wine 下沒有意義。
> **驗證方式（未執行）：** `WINEDEBUG=+module wine WowClassic.exe 2>&1 | grep -i d3d12`。
> **若真的被蓋掉，補救是明確 override：** `WINEDLLOVERRIDES="d3d12,d3d12core=b"`（`b` = builtin，出處：`wine(1)` man page）。

**(f) 結論：** **3.4.3 的 D3D12 在 stock upstream Wine 11.13 上，不需要安裝任何額外的 translation layer。** 不需要 DXVK（它根本不做 D3D12，見 §3.5），不需要 vkd3d-proton，不需要 D3DMetal。**你唯一需要確保的是「Wine 找得到一份 x86_64 的 `libMoltenVK.dylib`」** —— 而 Gcenx 的包已經 bundle 了。

### 3.2 3.4.3 到底支援哪些 gxApi？（本機實測，這是本文的新發現）

對 `~/World of Warcraft 3.4.3.54261/_classic_/WowClassic.exe`（`PE32+ executable (GUI) x86-64`）做 `strings`，精確比對整行等於某個 API 名稱的字串：

```
d3d11        D3D11
d3d11legacy
d3d12        D3D12
metal        Metal
Vulkan
```

**沒有 `d3d9`，沒有 `opengl`。** 另有 `D:\BuildServer\A\work-git\wow\Engine\Source\Gx\src\GxApi.cpp`、`<GxApi> %s`、`Setting GxApi to autodetect, pending GxRestart.`。本機 `WTF/Config.wtf` 目前是 `SET gxApi "D3D12"`。

> **意義：3.4.3 的 Windows client 有兩個可用後端 —— D3D12 與 D3D11（含 `d3d11legacy`）。** (`metal` / `Vulkan` 兩個字串屬於引擎的跨平台程式碼，Windows build 上用不到。**未驗證**其可觸發性。)
> **`SET gxApi "d3d11"` 因此是一條真實的備援路徑**，但見下一節 —— 在 stock Wine + MoltenVK 上它的期望值反而**比 D3D12 低**。

### 3.3 3.4.3 走 D3D11：wined3d 的兩條 renderer，都有問題

Wine 的 `d3d11.dll` → `wined3d.dll`，而 wined3d 有 GL 與 Vulkan 兩個 renderer。Wine 11.0 release notes：

> "the Vulkan renderer can be used by setting `renderer` to `vulkan` using the `Direct3D` registry key or `WINE_D3D_CONFIG` environment variable."
> "The Vulkan renderer is not yet at parity with the GL renderer, and is therefore **not yet the default**."

**(a) `renderer=vulkan` 在 MoltenVK 上被證明只能到 feature level 9_x。** `dlls/wined3d/adapter_vk.c`（`wine-11.13`）：

```c
static bool feature_level_10_supported(const struct wined3d_physical_device_info *info, unsigned int shader_model)
{
    return shader_model >= 4
            && info->features2.features.multiViewport
            && info->features2.features.geometryShader          /* ← MoltenVK: false */
            && info->features2.features.depthClamp
            && info->features2.features.depthBiasClamp
            && info->features2.features.pipelineStatisticsQuery /* ← MoltenVK: false */
            && info->features2.features.shaderClipDistance
            && info->features2.features.shaderCullDistance      /* ← MoltenVK: false */
            && ...;
}
```

> **這是「MoltenVK 三缺」第二次咬人，而且這次是硬的：** feature level 10 過不了，就更不可能到 11_0，D3D11 遊戲直接沒戲。**這就是 WoWSilicon patch 0002 存在的理由**，而 stock Wine 沒有這個 patch。

**(b) `renderer=gl`（預設）→ macOS OpenGL。** 這條沒有上面那道硬檢查，但 macOS 的 OpenGL 自 10.14 起已被 Apple 棄用（見[前一篇](./wine-deps-wow335.md) §6.3），而且 3.4.3 是 2023 年的 D3D11/12 引擎。
> **未驗證：wined3d 的 GL renderer 在 macOS 的 OpenGL 上能不能達到 D3D11 feature level 11_0。本文沒有實測，也找不到任何第一方文件宣稱它可以。不要假設它會動。**

### 3.4 對照組：Whisky + D3DMetal 走 D3D12（**已經實測會動**，本機 log）

`~/World of Warcraft 3.4.3.54261/_classic_/Logs/gx.log`（2026-09-03 19:15）：

```
World of Warcraft Retail x86_64 3.4.3.54261
Windows 10 (10.0.19043) (wine emulation) x86_64
VirtualApple @ 2.50GHz | Sockets:1 Cores:4 Threads:4
Adapter 0: "AMD Compatibility Mode" family:Unknown type:Discrete vendor:0x1002 device:0x66af ... dx11:true dx12:true
GpuInfo: sm:dx_6_0, rt:DXR 1.1, vrt:0, bary:0, mesh:1 pull:1
D3d12 Device Create
D3d12 Device Create Successful
Using shader family dx_6_0
Render Settings Changed. New Render Size: 1512x982
...
D3d12 Device Destroy
GxShutdown
```

> **三個可引用的事實：** (i) D3D12 device 建立成功、跑了約 5 分鐘後乾淨關閉；(ii) 適配器名稱 `"AMD Compatibility Mode"` 是 D3DMetal 回報的假身分；(iii) `VirtualApple @ 2.50GHz` 再次確認全程 Rosetta 2。
> **這是「已知可行」的基準線。** 本文提的 stock Wine 11.13 + vkd3d + MoltenVK 是**另一條路**，尚未在本機驗證。

### 3.5 3.3.5a 走 D3D9：stock Wine 只有 wined3d 一條，DXVK 要自己裝

- **DXVK 自己的 README（逐字）：** *"A Vulkan-based translation layer for **Direct3D 8/9/10/11** which allows running 3D applications on Linux using Wine."*
  - 安裝法（逐字）：*"copy or symlink the DLLs into the following directories as follows, then open `winecfg` and manually add **native** DLL overrides for `d3d8`, `d3d9`, `d3d10core`, `d3d11` and `dxgi` under the Libraries tab."*，以及 `cp x64/*.dll $WINEPREFIX/drive_c/windows/system32` / `cp x32/*.dll $WINEPREFIX/drive_c/windows/syswow64`。
  - DLL 需求：*"d3d9: `d3d9.dll`"*。
  - **DXVK README 全文提到 macOS / MoltenVK / Apple 的次數：0。**（本次 `grep -c -i` 實測）
  - **DXVK 完全不做 D3D12。** → **對 3.4.3 而言 DXVK 是錯的工具。**
- **wined3d → OpenGL**：stock Wine 的預設路徑，也是[前一篇筆記](./wine-deps-wow335.md) §1 那次崩潰走的路。
- **MTLd3D / D9VK**：只有 WoWSilicon 那種 bundle 才有，見[前一篇](./wine-deps-wow335.md) §6.4/§7.1。
- **D3DMetal 沒有任何 D3D9 進入點**（[前一篇](./wine-deps-wow335.md) §6.1，本機 `nm` 實測）。

> **對 3.3.5a 的裁決不變（沿用前一篇 §9）：stock Wine 11.13 對 D3D9 只有 wined3d→OpenGL；要 D9VK/MTLd3D 就得走 WoWSilicon。** 唯一的新增資訊是：**在 new WoW64 的 11.13 上，DXVK 的 32-bit `d3d9.dll` 要放進 `syswow64/`**（DXVK README 的第一段指示），因為你的 prefix 會是 `win64` 而不是純 32-bit —— 見 §4。

### 3.6 總表

| client / API | stock upstream Wine 11.13 開箱有嗎？ | 走哪條 | 裁決 |
|---|---|---|---|
| 3.4.3 / **D3D12** | ✅ **有**（builtin d3d12 = vkd3d 1.18） | vkd3d → winevulkan → MoltenVK → Metal | **架構上可行，未實測**。三個 FL11_0 檢查項 MoltenVK 缺，但不擋 device 建立 |
| 3.4.3 / **D3D11** | ✅ 有（builtin d3d11 = wined3d） | wined3d → GL（預設）／Vulkan | **Vulkan renderer 被證明在 MoltenVK 上只能到 FL 9_x**；GL 路徑未驗證。**期望值低於 D3D12** |
| 3.4.3 / D3D12 + **D3DMetal** | ❌ 要 GPTK/CrossOver 系的 Wine | D3DMetal → Metal | **已實測可行**（§3.4），但不是 upstream Wine |
| 3.3.5a / **D3D9** | ✅ 有（builtin d3d9 = wined3d） | wined3d → OpenGL | 見[前一篇](./wine-deps-wow335.md)，這是那次崩潰的路 |
| 3.3.5a / D3D9 + **DXVK** | ❌ 要自己裝 | DXVK d3d9 → MoltenVK | DXVK **不宣稱支援 macOS**；`d3d9=n` override |
| 任何 / **D3D12 + DXVK** | — | — | **不存在。DXVK 只做 D3D8/9/10/11。** |

---

## 4. Wine 11.x 的 32-bit 支援：new WoW64 是怎麼改變局面的

### 4.1 逐條引用 release notes

**Wine 9.0（new WoW64 首次登場，experimental）：**

> "All modules that call a Unix library contain WoW64 thunks to enable calling the 64-bit Unix library from 32-bit PE code. This means that it is possible to run 32-bit Windows applications on a purely 64-bit Unix installation. This is called the _new WoW64 mode_, as opposed to the _old WoW64 mode_ where 32-bit applications run inside a 32-bit Unix process."
> "The new WoW64 mode is not yet enabled by default. It can be enabled by passing the `--enable-archs=i386,x86_64` option to configure."
> **"The new WoW64 mode finally allows 32-bit applications to run on recent macOS versions that removed support for 32-bit Unix processes."**

**Wine 11.0（完成）：**

> "The main highlights are the NTSYNC support and **the completion of the new WoW64 architecture**."
> "The _new WoW64_ mode that was first introduced as experimental feature in Wine 9.0 is **considered fully supported**, and essentially has feature parity with the old WoW64 mode."
> "16-bit applications are supported in the new WoW64 mode."
> "It is possible to force an old WoW64 installation to run in new WoW64 mode by setting the variable `WINEARCH=wow64`. This requires the prefix to have been created as 64-bit (the default)."
> **"Pure 32-bit prefixes created with `WINEARCH=win32` are deprecated, and are not supported in new WoW64 mode."**
> "The `wine64` loader binary is removed, in favor of a single `wine` loader that selects the correct mode based on the binary being executed. For binaries that have both 32-bit and 64-bit versions installed, it defaults to 64-bit. The 32-bit version can then be launched with an explicit path, e.g. `wine c:\windows\syswow64\notepad.exe`."

### 4.2 對 macOS ARM64 的具體意義

| 問題 | 答案 | 出處 |
|---|---|---|
| `WINEARCH=win32` 的純 32-bit prefix 還能用嗎？ | **不能。** 在 new WoW64 build 上「deprecated 且不支援」 | Wine 11.0 notes |
| 那 32-bit 遊戲怎麼跑？ | 用**預設的 `win64` prefix**，32-bit PE 放在 `syswow64/`，`wine` loader 自己選模式 | Wine 11.0 notes + 本機 `~/.wine` 實測 |
| macOS 沒有 32-bit Unix process 了，怎麼辦？ | **這正是 new WoW64 解決的問題** —— 32-bit Windows 程式碼跑在 64-bit Unix process 裡 | Wine 9.0 notes 明文 |
| Apple Silicon 上還需要 Rosetta 嗎？ | **需要。** Gcenx 的 build 是 `osx64`（x86_64），整個 Wine 連同 32-bit PE 都在 Rosetta 2 上 | 本機 `lipo -archs` = `x86_64`；WineHQ wiki *"via Rosetta2"* |
| 有沒有 arm64 原生 Wine 跑 x86 Windows 程式的路？ | 有，但**還很生**：Wine 9.0/10.0 實作了 x86 模擬介面，但**不附模擬器** | 見下 |

**Wine 9.0 ARM64 節：**

> "The 32-bit x86 emulation interface is implemented. **No emulation library is provided** with Wine at this point, but an external library that exports the emulation interface can be used, by specifying its name in the `HKLM\Software\Microsoft\Wow64\x86` registry key. The FEX emulator implements this interface..."

**Wine 10.0 ARM64 節：**

> "The 64-bit x86 emulation interface is implemented... **No emulation library is provided with Wine at this point**, but an external library that exports the emulation interface can be used, by specifying its name in the `HKLM\Software\Microsoft\Wow64\amd64` registry key."
> "It should be noted that ARM64 support requires the system page size to be..."（Wine 11.0 補充：*"On ARM64, there is support for simulating a 4K page size on top of larger host pages (typically 16K or 64K). This works for simple applications, but... more demanding applications may not work correctly. **Using a 4K-page kernel is strongly recommended.**"`）

> **誠實裁決：** 「arm64 原生 Wine + FEX 跑 x86-64 的 WoW」在 upstream 是**有介面沒實作**的狀態，而且 macOS 的 page size 是 16K，正好踩在 Wine 11.0 那句警告上。**這條路今天不是選項。Apple Silicon 上跑 Wine，2026 年 9 月的現實答案仍然是 x86_64 Wine + Rosetta 2。**

### 4.3 winetricks 對 new WoW64 的態度（本機 `winetricks 20260125`）

它會偵測 WoW64 型態：

```sh
elif [ "${_W_wineserver_binary_arch}" = "${_W_wine_binary_arch}" ]; then
    _W_wow64_style="new"
else
    _W_wow64_style="classic"
fi
```

並對不相容的 package 警告：

> `"This package (${W_PACKAGE}) does not work on a new-style WoW64 prefix. See ${bug_link}. You must either use a 32-bit or old style WoW64 WINEPREFIX. Use --force to try anyway."`

**好消息：整份 winetricks 20260125 裡只有 `icodecs` 一個 verb 觸發這個警告**（指向 `https://bugs.winehq.org/show_bug.cgi?id=54670`）。**→ new WoW64 對 winetricks 的相容性很好，不是問題。**

---

## 5. 把自簽 root CA 匯進 prefix：哪個才是「有文件」的做法？

### 5.1 先講結論

**使用者原本用 `regedit /S` 寫 `HKLM\Software\Microsoft\SystemCertificates\Root\Certificates\<thumbprint>\Blob` 的做法，寫的正是 Wine 的 `crypt32` 自己在用的那把 key —— 所以它是對的，而且不會被 Wine 的自動匯入洗掉。但在 macOS 上有一個更省事、副作用更小的做法：把 CA 加進 macOS 的 keychain 並標為信任，Wine 會自己抓進來。**

### 5.2 證據：Wine 的 crypt32 在 macOS 上直接讀 Security framework

`dlls/crypt32/unixlib.c`（`wine-11.13`）：

```c
#ifdef __APPLE__
#include <Security/Security.h>
...
static void load_root_certs(void)
{
#ifdef __APPLE__
    const SecTrustSettingsDomain domains[] = {
        kSecTrustSettingsDomainSystem,
        kSecTrustSettingsDomainAdmin,
        kSecTrustSettingsDomainUser
    };
    ...
        status = SecTrustSettingsCopyCertificates(domains[domain], &certs);
```

**→ Wine 會把 macOS 三個 trust settings domain（System / Admin / User）的憑證全部撈出來。**

### 5.3 證據：它寫進哪把 registry key，以及會不會刪掉你手動加的

`dlls/crypt32/rootstore.c`：

```c
RegCreateKeyExW(HKEY_LOCAL_MACHINE, L"Software\\Microsoft\\SystemCertificates\\Root\\Certificates", ...)
```

它另外維護一把 `HKLM\Software\Wine\HostImportedCertificates`，用 SHA-1 thumbprint 記錄「哪些是我自己匯入的」。清理邏輯：

```c
if (RegQueryValueExW( import_key, hash_str, NULL, NULL, (BYTE *)&value, &size ))
{
    TRACE( "key %s is not imported, not deleting.\n", debugstr_w(hash_str) );
    continue;
}
```

> **→ 這行程式碼直接回答了問題：手動寫進 `Root\Certificates\<thumbprint>\Blob`、但沒有登記在 `HostImportedCertificates` 裡的憑證，Wine 明確地「不刪」。使用者的做法是安全的。**

**本機旁證：** `~/.wine/system.reg` 裡 `SystemCertificates` 出現 **174 次**，且 `HostImportedCertificates` 這把 key 確實存在。格式長這樣（實際內容節錄）：

```
[Software\\Microsoft\\SystemCertificates\\Root\\Certificates\\010C0695A6981914FFBF5FC6B0B695EA29E912A6] 1788441121
"Blob"=hex:03,00,00,00,01,00,00,00,14,00,00,00,01,0c,06,95,...
```

### 5.4 winetricks 有沒有 verb？—— **沒有**

本機 `winetricks 20260125` 全文搜尋：**沒有任何一個 verb 的名稱或 title 與 certificate / CA / root store 有關**（`grep -i cert` 在 `w_metadata` / `title=` 兩處皆 0 命中）。

### 5.5 兩種做法並列（都標出處）

**(A) 推薦：走 macOS keychain（讓 Wine 自己匯入）**

```sh
# 出處：dlls/crypt32/unixlib.c 讀 kSecTrustSettingsDomain{System,Admin,User}
sudo security add-trusted-cert -d -r trustRoot \
     -k /Library/Keychains/System.keychain /path/to/your-root-ca.crt
# 之後任何新建或既有的 prefix 在下次 crypt32 初始化時會自動撈進 Root store
```
> **未驗證：** 本文未實際執行 `security add-trusted-cert`，也未驗證 `-d -r trustRoot` 在 macOS 26.5.2 上的確切行為。指令形式取自本機 `security(1)`，**但 Wine 那一半（`SecTrustSettingsCopyCertificates` 會撈到它）是原始碼證實的**。
> **副作用要注意：加進 System keychain 是全機器信任，不只影響這個 prefix。若不想這樣，用 (B)。**

**(B) 只影響單一 prefix：直接寫 registry（使用者原本的做法，已證實可行且不會被洗掉）**

```sh
# thumbprint 就是憑證的 SHA-1，大寫無分隔
openssl x509 -in your-root-ca.crt -noout -fingerprint -sha1 | tr -d ':' | sed 's/.*=//'
# 產生 .reg（Blob 的二進位格式是 CERT_PROP serialization，非單純 DER —— 見下）
WINEPREFIX=~/.wow343 wine regedit /S ca.reg
```
> **必須誠實標註：`Blob` 的值**不是**裸 DER，是 Wine/Windows 的 serialized cert property 串（本機實測開頭是 `03,00,00,00,01,00,00,00,14,00,00,00,<20 bytes SHA1>,20,00,00,00,01,00,00,00,<len>,30,82,...`，最後才接 DER）。**要自己組這串，最可靠的做法是先在別處讓 Wine 匯入一次、再把 `Blob` 抄出來**，或用 `wine certutil` 之類的工具（**Wine 沒有內建 `certutil`，未驗證有無替代品**）。
> `regedit(1)` 的 `/S` 旗標出處：`programs/regedit/regedit.man.in`（Wine 原始碼樹，本文未逐字引用）。

---

## 6. Concrete bottle-build recipe（每一步都標出處）

> **前提：** Apple Silicon / macOS 26.5.2 / 已安裝 Rosetta 2（本機 `pgrep oahd` 有回應、`/Library/Apple/usr/libexec/oah/libRosettaRuntime` 存在）。目標 client：`~/World of Warcraft 3.4.3.54261/_classic_/WowClassic.exe`（`PE32+ x86-64`）。
> **本文未執行以下任何一步。** 全部標為「建議步驟」。

### Step 0 — 取得 Wine 11.13

```sh
# 出處：WineHQ wiki macOS 頁（"brew install --cask --no-quarantine ..."）
# 注意 wine@devel 現在是 11.16；要精準 11.13 就用下面的 tarball
brew install --cask --no-quarantine gstreamer-runtime      # cask 的唯一 depends_on
curl -L -o wine-devel-11.13-osx64.tar.xz \
  https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.13/wine-devel-11.13-osx64.tar.xz
tar -xf wine-devel-11.13-osx64.tar.xz          # 產生 "Wine Devel.app"
mv "Wine Devel.app" /Applications/
xattr -dr com.apple.quarantine "/Applications/Wine Devel.app"   # 若被 Gatekeeper 擋
export WINE="/Applications/Wine Devel.app/Contents/Resources/wine/bin/wine"
"$WINE" --version        # 應印出 wine-11.13
```
> 出處：Gcenx README（*"unpack, now move the `Wine *` bundle to /Applications and use as you would a Winehq release"*）；WineHQ wiki（tarball *"all paths are relative... no need to set DYLD_\* environment variables"*）。
> **不要**設 `DYLD_LIBRARY_PATH` / `DYLD_FALLBACK_LIBRARY_PATH` —— 這份包不需要（本機 `otool -L` 證實 `bin/wine` 只依賴 `libSystem`）。**只有 WoWSilicon / Whisky 那種 bundle 才需要**（§1.5）。

### Step 1 — 環境變數

```sh
export WINEPREFIX="$HOME/.wow343"     # wine(1): "the directory where Wine stores its data"
export WINEARCH=win64                 # wine(1): "support both 64-bit applications and 32-bit ones"
export WINEDEBUG=-all                 # 平時關掉；除錯時改 +module / +vkd3d / +d3d
unset WINEDLLOVERRIDES                # 預設不要任何 override —— builtin d3d12 就是我們要的
```
> **為什麼是 `win64` 而不是 `win32`：** Wine 11.0 release notes — *"Pure 32-bit prefixes created with `WINEARCH=win32` are deprecated, and are not supported in new WoW64 mode."*
> **為什麼不設 `WINEARCH=wow64`：** 那個值是給「把既有 old-WoW64 安裝強迫切到 new WoW64 模式」用的；Gcenx 的 build 本來就是 `--enable-archs=i386,x86_64`（= new WoW64），`win64` 即可。
> **架構在建 prefix 時就定死、之後改不了**（`wine(1)`：*"set at prefix creation time and cannot be changed afterwards"*）。

### Step 2 — 建立 prefix

```sh
"$WINE" wineboot --init          # wineboot(1): "-i, --init  Initialize the WINEPREFIX."
wineserver -w                    # 等 wineserver 收工（wineserver(1)）
```
> `wineboot(1)`：*"performs the initial creation and setup of a WINEPREFIX for wine(1)."*
> Gcenx 的包已內含 gecko 與 mono（README：*"`wine-gecko` & `wine-mono` are included within these custom `Wine-*` packages"`），所以**不會**跳出下載 .msi 的對話框。

### Step 3 — winetricks verbs：**一個都不要裝**

> **這是本文最重要的「不要做」。** 理由三條，全部有出處：
> 1. **沒有任何 primary source 為 3.4.3 / 現代 WoW 推薦過任何 winetricks verb。** WineHQ AppDB 的 WoW 條目在[前一篇筆記](./wine-deps-wow335.md) §2.4 已逐項確認：`winetricks`、任何 verb 名稱、DLL override、native DLL、regedit 修改，**一次都沒出現過**。（該次查核針對 3.3.5a 條目；**AppDB 沒有 3.4.x 的條目**，所以現代 client 連「有沒有人測過」都沒有紀錄。**未驗證。**）
> 2. **需要的 runtime 全部是 builtin 且已在 prefix 裡**（本機 `~/.wine` 實測：`d3d12`/`d3d12core`/`d3dcompiler_47`/`crypt32`/`bcrypt`/`schannel`/`wininet` 等在 `system32` 與 `syswow64` 兩側都有）。
> 3. 裝 native DLL 反而會**蓋掉** vkd3d —— 那是整個方案的核心。
>
> **明確地說：本文找不到任何第一方文件為現代 WoW client 推薦任何一個 winetricks verb。若有人叫你先跑 `vcrun2019` / `d3dcompiler_47` / `dxvk`，請要求出處。**

### Step 4 — 圖形後端：**什麼都不用做**

```sh
# 不需要 WINEDLLOVERRIDES。builtin d3d12.dll == vkd3d 1.18，就是要用的東西。
# 只有在確認遊戲目錄那份 Agility SDK d3d12.dll 蓋掉 builtin 時才加：
# export WINEDLLOVERRIDES="d3d12,d3d12core=b"     # b = builtin（wine(1) man page）
```

`WTF/Config.wtf`（本機該檔已是這個值）：

```
SET gxApi "D3D12"
```

備援（若 D3D12 起不來，**期望值較低**，理由見 §3.3）：

```
SET gxApi "d3d11"
```

> **不要**設 `WINE_D3D_CONFIG="renderer=vulkan"`：那個開關只影響 **wined3d**（d3d8/9/10/11），對走 vkd3d 的 d3d12 **完全沒有作用**；而且在 MoltenVK 上它會把 wined3d 卡在 feature level 9_x（§3.3(a)）。
> **視窗模式：** 沿用[前一篇筆記](./wine-deps-wow335.md) §9 第 0 步的建議 —— WoWSilicon `ConfigService.swift` 的註解 *"gxWindow always 1 (true fullscreen causes issues on macOS)"*。本機 3.4.3 的 `Config.wtf` 已有 `SET gxMaximize "1"` 但**沒有** `gxWindow`；建議補上 `SET gxWindow "1"`。**（這是 WoWSilicon 的話，不是 Blizzard 或 WineHQ 的話。）**

### Step 5 — 匯入自簽 root CA

見 §5.5。**推薦 (A) keychain 路線**；不想動全機器信任就用 (B) registry 路線（使用者原本的做法，已被 `rootstore.c` 證實不會被 Wine 洗掉）。

### Step 6 — 啟動與檢查

```sh
cd ~/"World of Warcraft 3.4.3.54261/_classic_"
"$WINE" WowClassic.exe
# 或先用 Arctium/Burralis launcher（見 macos-client-options.md §3.6）

# 檢查點（全部唯讀）
cat Logs/gx.log            # 期待 "D3d12 Device Create Successful" + "Using shader family dx_6_0"
# 若失敗，開 trace：
WINEDEBUG=+vkd3d,+module "$WINE" WowClassic.exe 2>&1 | tee /tmp/wow.log
grep -i -E 'vkd3d|MoltenVK|Failed to load|is not supported' /tmp/wow.log
```

**預期會看到、但不一定致命的 WARN**（來自 `vkd3d_init_feature_level()`，§3.1(d)）：

```
geometryShader is not supported.
pipelineStatisticsQuery is not supported.
shaderCullDistance is not supported.
```

### Step 7 —（3.3.5a，若同一台機器也要跑）

- prefix 一樣用 `win64`（**不要** `WINEARCH=win32`，§4.1）。
- D3D9 只有 wined3d→OpenGL 可用；要 DXVK 的話 **32-bit DLL 放 `syswow64/`**（DXVK README 第一段指示），並 `WINEDLLOVERRIDES="d3d9=n"`。
- 但[前一篇筆記](./wine-deps-wow335.md) §9 的結論不變：**要跑 3.3.5a，WoWSilicon 仍然是省事得多的答案**（它多了 x87 加速、winemac.drv patch、wininet patch、遊戲檔 patch，那些 stock Wine 一項都沒有）。

---

## 7. 已記載 vs 未知（誠實清單）

### ✅ 有第一方文件／原始碼支撐

- upstream Wine 的 configure **明文**用 MoltenVK 當 Vulkan（`configure.ac` 1940–1950）
- Wine 11.0 內建 **vkd3d 1.18**（release notes「Bundled libraries」）；`dxil.c` 存在 → 有 SM6/DXIL
- Wine 的 vkd3d 只需要 Vulkan 1.0/1.1 + 三個 KHR extension，且原始碼註解點名 MoltenVK
- vkd3d 的 `max_feature_level` **無條件**為 11_0 → device 建得起來
- MoltenVK **沒有** `geometryShader` / `pipelineStatisticsQuery` / `shaderCullDistance`（`MVKDevice.mm` 0 命中 + user guide 明文承認 pipeline statistics）
- stock wined3d 的 Vulkan renderer 因此在 MoltenVK 上**卡在 FL 9_x**（`adapter_vk.c` 的 `feature_level_10_supported()`）
- new WoW64 讓 32-bit Windows 程式能在沒有 32-bit Unix process 的 macOS 上跑（Wine 9.0 notes 明文）
- `WINEARCH=win32` 純 32-bit prefix 在 new WoW64 上**不支援**（Wine 11.0 notes 明文）
- `wine64` loader 已被移除（Wine 11.0 notes）
- WineHQ 自家 tarball **不需要** `DYLD_*`；第三方 bundle **不受 WineHQ 支援**（wiki macOS 頁）
- 「Wine cannot find the FreeType font library」是 `dlopen(SONAME_LIBFREETYPE)` 失敗（`freetype.c`）
- WoWSilicon 靠 `DYLD_LIBRARY_PATH=<Wine>/lib/external` 解決它（`BundledWineRuntime.swift`）
- Wine 的 crypt32 在 macOS 上讀 `SecTrustSettingsCopyCertificates`（`unixlib.c`），寫進 `HKLM\Software\Microsoft\SystemCertificates\Root\Certificates`，且**不刪**手動加的項目（`rootstore.c`）
- DXVK **不做 D3D12**、README **零** macOS/MoltenVK 字樣
- GPTK 的 evaluation environment = **CrossOver 22.1.1 的 Wine + `--enable-win32on64`，x86_64 only**（Apple 自己的 Homebrew formula）
- 3.4.3 client 支援 `d3d11` / `d3d11legacy` / `d3d12`，**不支援** d3d9/opengl（本機 `strings` 實測）

### ❓ 未驗證 / 未知（**不要當成已知**）

- **stock Wine 11.13 + vkd3d + MoltenVK 實際能不能把 3.4.3 跑起來 —— 本文沒有實測。** 這是最大的空白。
- 3.4.3 執行期會不會用到 geometry shader（若會，MoltenVK 缺這項就是硬傷）
- 遊戲目錄那份 Agility SDK `d3d12.dll` 會不會蓋掉 Wine builtin（§3.1(e) 是推論，需 `WINEDEBUG=+module` 驗證）
- wined3d 的 **GL** renderer 在 macOS OpenGL 上能否達到 D3D11 FL 11_0
- Gcenx 的 `wine-devel-11.13-osx64.tar.xz` 內容物（是否同樣 bundle x86_64 `libMoltenVK.dylib`、是否含 gecko/mono）—— **本文只檢查了本機已安裝的 `wine-stable 11.0_1`，未下載 11.13**
- Gcenx README 的 `--without-opengl` 與本機 binary 連結 `OpenGL.framework` 的矛盾
- `security add-trusted-cert -d -r trustRoot` 在 macOS 26.5.2 上的確切行為（Wine 那一半是原始碼證實的，macOS 那一半沒實測）
- 手工組 `Blob` 二進位格式的可靠做法（Wine 沒有內建 `certutil`）
- GPTK 4 的 D3DMetal 能否搭 upstream Wine 11.13（**Apple 沒有任何文件說可以；本文不建議嘗試**）
- 效能／功耗：**本文沒有任何測量數據，任何數字都會是捏造**

### ⚠️ 必須一起講的到期日

**這條路仍然 100% 依賴 Rosetta 2**（Gcenx 的 Wine 是 x86_64）。Apple 已公告 **macOS 27 是最後一版支援 Rosetta 的系統**（見[前一篇筆記](./macos-client-options.md) §2.1）。所以本文的 recipe 與 CrossOver / Whisky / WoWSilicon **共享同一個到期日**，沒有比較安全。唯一沒有已知期限的仍然是 Parallels + Windows 11 ARM64（同前一篇 §2.5）。

---

## 8. 驗證方式（全部唯讀，可自行複驗）

**本機**

```sh
# Homebrew 的 wine 到底是什麼
brew info --json=v2 --cask wine-stable | python3 -m json.tool | head -40
brew info --json=v2 --cask wine@devel  | python3 -m json.tool | head -40
W="/Applications/Wine Stable.app/Contents/Resources/wine"
"$W/bin/wine" --version                      # wine-11.0
lipo -archs "$W/bin/wine"                    # x86_64
ls "$W/bin" | grep -c wine64                 # 0 —— wine64 loader 已移除
ls -d "$W"/lib/wine/*/                       # i386-windows / x86_64-windows / x86_64-unix（無 x86_32on64-unix）
otool -L "$W/bin/wine"                       # 只依賴 libSystem → relocatable
otool -L "$W/lib/wine/x86_64-unix/winemac.so" | grep -E 'Metal|OpenGL'
strings -a "$W/lib/wine/x86_64-unix/win32u.so" | grep libMoltenVK   # libMoltenVK.dylib
lipo -archs "$W/lib/libMoltenVK.dylib"       # x86_64
strings -a "$W/lib/wine/x86_64-windows/d3d12.dll" | grep -i vkd3d   # vkd3d_create_device
lipo -archs /opt/homebrew/opt/molten-vk/lib/libMoltenVK.dylib       # arm64（餵不了 x86_64 wine）

# 既有 prefix（本次未建立、未修改）
grep -m1 '^#arch' ~/.wine/system.reg                                 # #arch=win64
file ~/.wine/drive_c/windows/syswow64/kernel32.dll                   # PE32 i386
file ~/.wine/drive_c/windows/system32/kernel32.dll                   # PE32+ x86-64
grep -c SystemCertificates ~/.wine/system.reg                        # 174
grep -c HostImportedCertificates ~/.wine/system.reg                  # 1

# 3.4.3 client
C=~/"World of Warcraft 3.4.3.54261/_classic_"
file "$C/WowClassic.exe"                                             # PE32+ x86-64
strings -a "$C/WowClassic.exe" | grep -x -i -E 'd3d9|d3d11|d3d11legacy|d3d12|opengl' | sort -u
file "$C/d3d12.dll"; strings -a "$C/d3d12.dll" | grep D3D12Core      # Agility SDK
cat "$C/Logs/gx.log"                                                 # D3d12 Device Create Successful
grep gxApi "$C/WTF/Config.wtf"                                       # SET gxApi "D3D12"

# winetricks
grep -n 'w_package_broken_wow64' /opt/homebrew/bin/winetricks        # 只有 icodecs 觸發
grep -i -c 'cert' /opt/homebrew/bin/winetricks | : ; grep -n 'w_metadata.*cert' /opt/homebrew/bin/winetricks  # 無

# Apple GPTK formula
sed -n '25,40p' /opt/homebrew/Library/Taps/apple/homebrew-apple/Formula/game-porting-toolkit.rb
man 1 dyld | col -b | grep -A8 DYLD_FALLBACK_LIBRARY_PATH
```

**外部（本次實際抓取）**

```sh
B=https://raw.githubusercontent.com/wine-mirror/wine
curl -sL $B/master/README.md
curl -sL $B/wine-11.0/ANNOUNCE.md   $B/wine-10.0/ANNOUNCE.md   $B/wine-9.0/ANNOUNCE.md   $B/wine-11.13/ANNOUNCE.md
curl -sL $B/master/tools/wine/wine.man.in
curl -sL $B/wine-11.13/programs/wineboot/wineboot.man.in
curl -sL $B/wine-11.13/configure.ac
curl -sL $B/wine-11.13/dlls/win32u/vulkan.c
curl -sL $B/wine-11.13/dlls/win32u/freetype.c
curl -sL $B/wine-11.13/dlls/wined3d/adapter_vk.c
curl -sL $B/wine-11.13/dlls/ntdll/unix/loadorder.c
curl -sL $B/wine-11.13/dlls/crypt32/{unixlib.c,rootstore.c}
curl -sL $B/wine-11.13/libs/vkd3d/libs/vkd3d/device.c
curl -sL https://raw.githubusercontent.com/Gcenx/macOS_Wine_builds/master/README.md
curl -sL https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases/tags/11.13
curl -sL https://raw.githubusercontent.com/doitsujin/dxvk/master/README.md
curl -sL https://raw.githubusercontent.com/HansKristian-Work/vkd3d-proton/master/README.md
curl -sL https://raw.githubusercontent.com/KhronosGroup/MoltenVK/main/Docs/MoltenVK_Runtime_UserGuide.md
curl -sL https://raw.githubusercontent.com/KhronosGroup/MoltenVK/main/MoltenVK/MoltenVK/GPUObjects/MVKDevice.mm
curl -sL https://raw.githubusercontent.com/WoWSilicon/WoWSilicon/main/Sources/WoWSiliconSwift/Services/BundledWineRuntime.swift
curl -sL https://api.github.com/repos/apple/game-porting-toolkit
```

**取用失敗（必須說明）**

- **`wiki.winehq.org` 與 `gitlab.winehq.org` 全站掛著 Anubis 反爬蟲挑戰**（v1.27.0）。`curl` 帶 UA 與 WebFetch 都只拿到 `"Making sure you're not a bot!"`（7,542 bytes，每個 URL 都一樣大小）。
  - 因此 **§1.3 / §1.5 / §2.1 / §2.3 的 wiki 引文全部來自 Wayback 快照**：`wiki.winehq.org/MacOS` → `20240828190806`；`wiki.winehq.org/MacOS/Building` → `20240627185044`。**兩份都是 2024 年的快照，且 Building 頁自述最後編輯於 2023-05-04，內文明講清單是給 wine-8.x 的 —— 對 11.13 已過時，本文已在對應位置標註。**
  - `gitlab.winehq.org/wine/wine/-/wikis/Building-Wine` 的 Wayback 快照（`20260820070545`）**本身就是 Anubis 挑戰頁**，等於沒有。**該頁內容本次無法取得。**
- Wine 原始碼一律改由 GitHub 官方鏡像 `wine-mirror/wine` 取得（`gitlab.winehq.org` 的 raw 端點同樣被擋）。**`loader/wine.man.in` 這個路徑已不存在**，man page 現在在 `tools/wine/wine.man.in`。
- WebFetch 對 `web.archive.org` 回 "unable to fetch"，Wayback 內容改用 `curl` + Wayback Availability API 取得。
- `developer.apple.com/games/game-porting-toolkit/` 的頁面經 WebFetch 取得，但**未列出 licensing 或 system requirements**；GPTK 的 README（dmg 內）本次未取得。
- **未使用任何瀏覽器自動化。**

---

## 9. 實際取用過的來源

**Wine 官方（PRIMARY，經 `wine-mirror/wine` 鏡像）**
- `README.md`（REQUIREMENTS / macOS info / Optional support libraries）
- `ANNOUNCE.md` @ `wine-9.0` / `wine-10.0` / `wine-11.0` / `wine-11.13`
- `tools/wine/wine.man.in`（`wine(1)`：WINEPREFIX / WINESERVER / WINEDLLPATH / WINEDLLOVERRIDES / WINEARCH / WINE_D3D_CONFIG / WINEDEBUG / WINEPATH）
- `programs/wineboot/wineboot.man.in`（`wineboot(1)`：`-i/--init`、`-u/--update` 等）
- `configure.ac`（freetype = ERROR、gnutls = WARNING、vulkan/MoltenVK = NOTICE）
- `dlls/win32u/vulkan.c`、`dlls/win32u/freetype.c`
- `dlls/wined3d/adapter_vk.c`（`feature_level_10_supported()`）
- `dlls/ntdll/unix/loadorder.c`（`version_heuristics()` 的 vendor 表）
- `dlls/crypt32/unixlib.c`、`dlls/crypt32/rootstore.c`
- `libs/vkd3d/libs/vkd3d/device.c`、`libs/vkd3d/libs/vkd3d-shader/dxil.c`（存在性）

**WineHQ wiki（經 Wayback，見 §8）**
- `https://wiki.winehq.org/MacOS`（Homebrew / MacPorts / tarball 不需 DYLD_* / 第三方不支援 / Rosetta2）
- `https://wiki.winehq.org/MacOS/Building`（build 與 runtime 依賴清單、dlopen 只找 /usr/local/lib 與 /usr/lib、DYLD_FALLBACK_LIBRARY_PATH）

**Apple**
- `man 1 dyld`（本機，`DYLD_FALLBACK_LIBRARY_PATH` 定義）
- `https://developer.apple.com/games/game-porting-toolkit/`（Game Porting Toolkit 4）
- `https://github.com/apple/game-porting-toolkit`（Apache-2.0，prerequisites: macOS 27 / Xcode 27）
- 本機 `apple/apple` tap 的 `game-porting-toolkit.rb`（Copyright Apple, Inc. — CrossOver 22.1.1 sources、`--enable-win32on64`、`depends_on arch: :x86_64`）

**Homebrew（本機 `brew info --json=v2`）**
- cask `wine-stable` 11.0_1 / `wine@devel` 11.16 / `wine@staging` 11.16（全部指向 Gcenx）
- formula `molten-vk` 1.4.2（arm64）
- `winetricks` 20260125（`w_package_broken_wow64`、`_W_wow64_style`、`dxvk` verb metadata、無 cert verb）

**各專案 repo（各自的 PRIMARY）**
- `https://github.com/Gcenx/macOS_Wine_builds`（README 的 configure 選項與 runtime 依賴；release `11.13` 資產清單）
- `https://github.com/doitsujin/dxvk`（README：D3D8/9/10/11、native override、x32→syswow64、零 macOS 字樣）
- `https://github.com/HansKristian-Work/vkd3d-proton`（README：Vulkan 1.3 等硬需求；零 macOS 字樣）
- `https://github.com/KhronosGroup/MoltenVK`（`MoltenVK_Runtime_UserGuide.md` 的 Limitations；`MVKDevice.mm` 的 `_features` 初始化）
- `https://github.com/WoWSilicon/WoWSilicon`（`BundledWineRuntime.swift` 的 `DYLD_LIBRARY_PATH`；`WOWSILICON_WINE_RUNTIME`）

**本機檔案（PRIMARY，可複驗）**
- `/Applications/Wine Stable.app/Contents/Resources/wine/`（binary、`lib/wine/*`、`libMoltenVK.dylib`）
- `~/.wine/`（`system.reg`、`drive_c/windows/{system32,syswow64}`）
- `~/World of Warcraft 3.4.3.54261/_classic_/`（`WowClassic.exe`、`d3d12.dll`、`WTF/Config.wtf`、`Logs/gx.log`）
