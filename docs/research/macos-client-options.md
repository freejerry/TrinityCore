# macOS / Apple Silicon 上玩 WotLK 內容：client 取得與執行方式（研究筆記）

> 撰寫日期：2026-09-03
> 相關筆記：[TrinityCore 專案總覽](./trinitycore-overview.md)、[在 TrinityCore 上跑「WotLK Classic」](./wotlk-classic-on-modern-client.md)、[3.3.5a 原生 Mac client 能不能在 Apple Silicon 上跑？](./mac-client-3.3.5a-on-apple-silicon.md)（本文第 1 節結論的完整追查：五條路徑逐一裁決）
> 來源限定 primary sources：Apple（developer.apple.com / support.apple.com / apple.com newsroom）、Blizzard（news.blizzard.com / support.blizzard.com / us.forums.blizzard.com）、CodeWeavers、WineHQ AppDB、Microsoft Learn、本 repo 原始碼、以及各專案自己的 repo。
> 凡未經實際驗證者，一律明確標示「**未驗證**」。本文不對任何私服做排名或推薦。

---

## 0. 一句話結論（TL;DR）

**使用者的前提 (a) 正確，但前提 (b) 是錯的。**

- (a) **正確**：2010 年的 WoW 3.3.5a **Mac** client 是 PPC/Intel 32-bit universal binary，macOS Catalina 10.15 起完全不能執行，Apple Silicon 上更不可能。這條路真的死了。
- (b) **錯誤**：「所以必須改用現代架構 client」不成立。**Windows 版的 3.3.5a client（同樣是 32-bit x86）今天在 Apple Silicon 上跑得起來** —— CrossOver 26.x 的 32-bit bottle 仍然可用，Wine AppDB 的 3.3.5a 條目在 Wine 11.0 上是 **Silver**。你要的是 Windows client，不是 Mac client。

但這條路**有明確的到期日**：CodeWeavers 已公告 CrossOver 27 完全移除 32-bit bottle，Apple 也已公告 macOS 27 是最後一版支援 Rosetta 的系統。長期解是 **Parallels + Windows 11 ARM64**，因為 Windows on ARM 的 Prism/WOW64 原生模擬 32-bit x86，不依賴 Rosetta，也不受 CrossOver 的期限影響。

**而「改用現代 Classic client」這條路，卡在一個本文新發現的硬問題：client 根本弄不到。** TrinityCore `cata_classic` 釘死在 build `4.4.2.60895`，但 Battle.net 只安裝當前 build（`wow_classic` 現在是 `5.5.4.69585`，MoP Classic），而 Blizzard CDN 上 `4.4.2.60895` 的 build config **已經被清掉（實測 HTTP 404）**。TrinityCore 自己的 remote CASC 也**不能指定 build**（見第 3 節，這是本文最關鍵的原始碼發現）。

---

## 1. 驗證前提 (a)：3.3.5a Mac client 的架構

### 1.1 macOS 移除 32-bit 支援（已驗證）

Apple 支援文件 `https://support.apple.com/en-us/103076`：

> "Starting with macOS Catalina 10.15, 32-bit apps are no longer compatible with macOS."

同頁並回溯說明：

> "in 2018 Apple informed them that macOS Mojave 10.14 would be the last version of macOS to run 32-bit apps."

### 1.2 Rosetta 2 與 32-bit（**部分未驗證，需誠實說明**）

Apple 的 `https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment` 寫：

> "Rosetta can translate most Intel-based apps, including apps that contain just-in-time (JIT) compilers."
> "However, Rosetta doesn't translate the following executables:" — Kernel extensions、Virtual Machine apps that virtualize x86_64 computer platforms。

**注意：這份清單裡並沒有列出「32-bit」。** Apple 的安全指南 `https://support.apple.com/guide/security/rosetta-2-on-a-mac-with-apple-silicon-secebb113be1/web` 只說 Rosetta 2 是：

> "capable of running code compiled for the **x86_64** instruction set using a translation mechanism called Rosetta 2"

> **誠實標註：** 「Rosetta 2 不翻譯 32-bit Intel 執行檔」是由「只支援 x86_64」＋「Catalina 已移除 32-bit 執行環境」**推論**而來，**不是 Apple 的一句明文**。結論本身可靠（32-bit Mach-O 在 Catalina+ 根本無法載入，遑論翻譯），但不要把它當成引用。

### 1.3 3.3.5a Mac client 的實際架構（已驗證，經由系統需求反推）

Blizzard 官方 WotLK 系統需求（Datth 的 blue post，2008-10-07；同一段文字也在 client 隨附的 ReadMe 內）：

> "Mac OS X 10.4.11 or newer"
> "Minimum: **PowerPC G5 1.6 GHz or Intel Core Duo** processor"

推論鏈（清楚可靠）：

- 支援 **PowerPC G5** → 必須是 PPC/Intel **universal（fat）binary**。
- 最低 CPU 是 **Intel Core Duo** → Core Duo 是 **32-bit only**（沒有 EM64T），所以 binary **必須**含 i386 slice，且不可能只有 x86_64 slice。
- 2010 年的 3.3.5a 因此是含 32-bit slice 的 universal binary → **Catalina 之後無法執行，Apple Silicon 更不行**。
- 佐證時序：PowerPC 支援是在 **patch 4.0.1（2010-10）** 才被移除，也就是**在 3.3.5a 之後** —— 3.3.5a 仍在 PPC universal binary 的時代之內。

補充：Blizzard 確實在 **patch 4.3.2（2012 年初）** 提供過 64-bit Mac client，但那是 Cataclysm，比 3.3.5a 晚兩個資料片。**這是 SECONDARY 來源**（Engadget 引用一則現已失效的官方 blue post，`https://www.engadget.com/2012-02-28-world-of-warcraft-patch-4-3-3-64-bit-client.html`）。

> **未驗證：** 找不到 Blizzard 第一方、現仍可存取的頁面說明 Mac client 何時轉 64-bit。
> **修正一個常見說法：** 「64-bit client 是 patch 5.4.2（2013）」**不成立**。官方 5.4.2 PTR patch notes（`http://worldofwarcraft.blizzard.com/en-us/news/11874104/542-ptr-patch-notes-december-5`）通篇沒有 "64-bit" / "Mac" / "OS X"。不要引用這個版本號。

### 1.4 Blizzard 自己對 32-bit 的表態（已驗證）

`https://worldofwarcraft.blizzard.com/en-us/news/21788100/support-ending-for-world-of-warcraft-32-bit-client-this-summer`：

> "When the World of Warcraft: Battle for Azeroth pre-patch is live, we will no longer support the World of Warcraft game client for 32-bit operating systems."

（這是講 OS 位元數，不是專指 macOS。）另有一則直接點名 Catalina 的第一方發言，但對象是 Diablo II 而非 WoW（Jambrix，2021-01-06，`https://us.forums.blizzard.com/en/blizzard/t/diablo-ii-mac-support-update/14367`）：

> "Apple has announced that 32-bit application support is not available in macOS Catalina 10.15 and later."

**小結：前提 (a) 成立。** 但它只否定了 **Mac** client，沒有否定 Windows client。

---

## 2. 在 Apple Silicon 上跑 3.3.5a 的實際路徑

### 2.0 先確認：Windows 版 3.3.5a 也是 32-bit（已驗證，推論可靠）

- Blizzard 自己的公告證明 32-bit WoW client 長年是主流，直到 2018 BfA 才停止支援（見 1.4）。
- 64-bit Windows client 最早出現在 **patch 4.3.2（2012 年初）**，比 3.3.5a 晚（SECONDARY，見 1.3）。
- **可自行驗證：** 對 3.3.5a 的 `Wow.exe` 執行 `file Wow.exe`，預期輸出 `PE32 executable (GUI) Intel 80386`。

所以問題變成：**Apple Silicon 上的 Windows 相容層能不能跑 32-bit x86 執行檔？**

### 2.1 CrossOver —— 今天可以，但正在關門（已驗證）

**現況：可以。** CrossOver Mac 使用者手冊（`https://support.codeweavers.com/en_US/user-guides/crossover-mac-user-guide`）：

> "By default, CrossOver 26 creates new bottles as 64-bit. **Your 32-bit Windows applications will still run inside these 64-bit bottles.**"
> "You only need to enable this option if you already tried a 64-bit bottle and your application stopped working."
> 系統需求："Intel or Apple Silicon (M1 or newer) based Mac running macOS 10.15 or later"

最新版本為 **CrossOver 26.3.0（2026-07-21）**（`https://www.codeweavers.com/crossover/changelog`）。

**但 CodeWeavers 自己公告了終止時程。** Meredith Johnson，2026-06-11，*"What's in and what's out for CrossOver 27"*（`https://www.codeweavers.com/blog/mjohnson/2026/6/11/whats-in-and-whats-out-for-crossover-27`）：

> "CrossOver Mac 27 will only run on macOS Sonoma or newer, and only on Apple silicon Macs."
> "**32-bit bottles will no longer run, full stop.** We've been warning about this since CrossOver 26 was released, and you will need to create new 64-bit bottles to use CrossOver 27 and beyond. Almost all 32-bit applications run just fine in a 64-bit bottle."

以及機制與原因（這段解釋了為什麼 32-bit 在 Apple Silicon 上是靠 Rosetta 撐著）：

> "Apple silicon uses ARM architecture, and CrossOver Mac has been targeting ARM64 ever since the first M1 chips were released in 2020. **Currently, CrossOver requires the use of Rosetta 2 to translate x86_64 instructions to ARM64.** Rosetta 2 will be largely discontinued with macOS 28 in 2027…"
> "…it does mean the end of 32-bit bottle support. **We needed some very invasive hacks to get 32-bit bottles to work on even x86_64.** Trying to extend those hacks to ARM64 would be an unimaginable technological burden…"

CrossOver 26.2.0（2026-06-09）changelog：*"Added additional warnings for 32-bit bottles."*

**Apple 這邊的期限也已公告**（`https://developer.apple.com/news/?id=w5ngl9k2`）：

> **macOS 27:** "Final release to support Rosetta — Intel-only apps will no longer run on Mac computers with Apple silicon after this update."
> "Please note that Rosetta functionality for older, unmaintained gaming titles that rely on Intel-based frameworks will continue to be supported."

> 注意最後那句「for older, unmaintained gaming titles… will continue to be supported」語意模糊，**Apple 沒有說明它涵蓋什麼範圍**，不能據此斷定 Wine/CrossOver 的 32-bit bridge 會被保留。**未驗證。**

**CrossOver 相容性資料庫的 WoW 條目要小心解讀。** `https://www.codeweavers.com/compatibility/crossover/world-of-warcraft`（App Id 7714，最後修改 2022-02-17）Mac 評級是 **"Will Not Install"**，Last Tested 26.0.0。**但這個條目指的是現行零售版 WoW（Battle.net 安裝流程），不是 3.3.5a。** CrossOver 資料庫**沒有** 3.3.5a 專屬條目。不要把這個評級套到 3.3.5a 上。

### 2.2 Wine AppDB：3.3.5a 有專屬條目，評級 Silver（已驗證）

- 母條目：`https://appdb.winehq.org/objectManager.php?sClass=application&iId=1922`
- **3.3.5a 版本條目**：`https://appdb.winehq.org/objectManager.php?sClass=version&iId=32890`
  - 描述 "Latest version of Wrath of The Lich King expansion"，**Latest Rating: Silver**，**Latest Wine Version Tested: 11.0**，6 筆測試結果。

測試紀錄：

| OS | 日期 | Wine | 可執行 | 評級 |
|---|---|---|---|---|
| Zorin OS | 2026-04-23 | 11.0 | 是 | **Silver** |
| Manjaro 21.0 | 2021-04-29 | 6.5 | 是 | Platinum |
| Debian 10 | 2020-05-28 | 5.9 | 是 | Garbage |
| Antergos | 2017-03-14 | 2.3 | 是 | Gold |
| Arch Linux | 2017-02-14 | 2.1 | 是 | Platinum |
| Ubuntu 14.04 | 2015-11-12 | 1.6.2 | 是 | Platinum |

2026 那筆 Silver 的原文：

> What works: "Everything. Addons, login, character creation, auctions, dungeons, raids, custom patches."
> What does not: "I'm getting crash when in heavily populated area (dalaran) with running out of memory area"

> **重要但書：所有 6 筆測試都是 Linux，沒有任何一筆 macOS 紀錄。** AppDB 的 Silver 不能直接當成 Apple Silicon 上的保證。這是本題最大的證據缺口。
> 另注意 CodeWeavers 頁面上連往 AppDB 的網址已失效（指向不相干的條目）。

### 2.3 Whisky —— 已停止維護，不建議（已驗證）

`https://github.com/Whisky-App/Whisky`：

> "This repository was archived by the owner on **May 11, 2025**. It is now read-only."
> "**Whisky is no longer actively maintained.** Apps and games may break at any time."

存在社群 fork `https://github.com/frankea/Whisky`（自述 "Active community fork of the archived whisky-app/whisky"），但**非原作者背書**，本文不評估其品質。

### 2.4 Apple Game Porting Toolkit / D3DMetal（部分未驗證）

- 現行版本為 **Game Porting Toolkit 4**，"The evaluation environment now supports Metal 4."（`https://developer.apple.com/games/game-porting-toolkit/`、`https://developer.apple.com/games/whats-new/`）。
- WWDC23 session 10123（`https://developer.apple.com/videos/play/wwdc2023/10123/`）：

  > "The environment of the Game Porting Toolkit **translates your game's Intel instructions** and its use of Windows APIs for keyboard, mouse, and controller input; for audio playback; for networking and file system use; and of course, **for graphics**."

- CodeWeavers changelog 顯示 CrossOver 內含 **D3DMetal 2.1**（CrossOver 25.0.0，2025-03-11）與 **D3DMetal 3.0**（CrossOver 26.0.0，2026-02-10），CrossOver 26 另含 **DXMT v0.72**（"a Metal-based implementation of D3D11 on macOS"）。

> **未驗證（且對 3.3.5a 很關鍵）：** Apple 沒有任何文件說明 D3DMetal 支援哪些 Direct3D 版本。GPTK 頁面、What's New 頁、WWDC23 逐字稿都沒點名 D3D9/11/12（WWDC 範例只講 DirectX 12）。「D3DMetal 只做 DX11/DX12，D3D9 要走 DXVK」這個廣為流傳的說法來自 AppleGamingWiki 與論壇，**不是 Apple 的話**。由於 **3.3.5a 用的是 D3D9（或 OpenGL）**，這個缺口直接影響它的圖形路徑會走到哪一層，但無法用 primary source 確認。
> **未驗證：** Apple 亦未說明 GPTK 環境是否接受 32-bit Windows 執行檔。GPTK 建構於 CrossOver/Wine 之上，因此實際受制於 CrossOver 的 bottle 架構 —— 也就是 2.1 節那條期限。

### 2.5 Parallels + Windows 11 ARM64 —— 最耐久的路（已驗證）

Microsoft Learn，*"How emulation works on Arm"*（`https://learn.microsoft.com/en-us/windows/arm/apps-on-arm-x86-emulation`）：

> "**Windows 11 on Arm supports emulation of both x86 and x64 apps.** Performance is enhanced with the introduction of the new emulator **Prism** in Windows 11 24H2. Windows 10 on Arm also supports emulation, but only for x86 apps."
> "For x86 apps, **the WOW64 layer of Windows allows x86 code to run on the Arm64 version of Windows**, just as it allows x86 code to run on the x64 version of Windows."

**意義：** 32-bit x86 模擬由 Windows 自己提供，**不經過 Rosetta 2，也不受 CrossOver 27 的 32-bit 移除影響**。這是唯一沒有已知到期日的 3.3.5a 執行路徑。

> **未驗證：** 未找到任何第一方或可靠技術來源實測 3.3.5a 在 Parallels/Windows ARM64 上的表現。Prism 仍是指令翻譯，圖形也要再經 Parallels 的虛擬 GPU，效能未知。

### 2.6 有沒有 64-bit 的自製 3.3.5a client？

**沒有找到任何證據。** 本次調查未發現任何 emulator 社群散布「64-bit / ARM64 原生的 3.3.5a client」。這在技術上也極不合理：client 是 Blizzard 的封閉原始碼二進位檔，社群無法重新編譯成 64-bit，只能做 binary patch（改 realmlist、繞過版本檢查），那不會改變架構。

> **標註：** 這是「未找到證據」而非「已證明不存在」。若看到任何此類宣稱，應要求提供可驗證的來源，並注意執行來路不明的遊戲執行檔的安全風險。

---

## 3. 現代 Classic client 從哪裡來？（本節是真正的關鍵）

這一節回答「就算你想走現代架構，client 弄得到嗎」。**答案目前是：弄不到 4.4.2.60895。**

### 3.1 合法取得管道：Battle.net（已驗證）

Blizzard 支援文件 000369636 *"Current World of Warcraft Modes and Versions"*（`https://us.support.blizzard.com/en/article/369636`）：

> "World of Warcraft game modes and versions are only listed below if they are **currently active**."
> "Unless otherwise noted, all versions and game modes require an active World of Warcraft subscription."

其列出的 Classic 版本為：**Classic Era、Season of Discovery、Anniversary Classic、Mists of Pandaria Classic**。

> **注意缺席者：沒有 Wrath Classic，也沒有 Cataclysm Classic。**

安裝方式，支援文件 000243509（`https://us.support.blizzard.com/en/article/243509`）：

> "Click the World of Warcraft icon on the left side of the app. **Select World of Warcraft Classic from the version dropdown.** Click Install. World of Warcraft Classic requires active game time and is not available to Starter Edition accounts."

**一份訂閱涵蓋所有現行 Classic 版本**（見上引「all versions and game modes require an active World of Warcraft subscription」）。

### 3.2 Battle.net 現在實際會裝到什麼（已驗證，實測 Blizzard 官方 endpoint）

查詢 Blizzard 自己的版本端點 `https://us.version.battle.net/v2/products/<product>/versions`：

| product | 目前 live build |
|---|---|
| `wow_classic` | **5.5.4.69585**（MoP Classic） |
| `wow_classic_era` | 1.15.9.69547 |
| `wow_classic_ptr` | 5.5.4.67849 |
| `wow` | 12.1.0.69587 |

**結論：`wow_classic` 這條產品線已經從 Wrath → Cata → MoP 一路推進，只供應當前 build。`4.4.2` 無法透過 Battle.net 安裝，`3.4.x` 產品則根本不存在。**

### 3.3 釘死的 build 問題：TACT / NGDP / CASC（已驗證）

架構定義（`https://wowdev.wiki/NGDP`，這是社群維護的規格 wiki，是最接近規格書的來源，**非 Blizzard 官方**）：

> "**Ribbit** (discovery) provides the API endpoints that clients query to find available product versions, CDN server lists, and build configurations… **TACT** (content transfer) handles content encoding, decoding, and CDN distribution… **CASC** (local storage) manages on-disk archives, index files, and content extraction."

端點（`https://wowdev.wiki/TACT`）：

> `http://us.patch.battle.net:1119/(product)/versions` → `https://us.version.battle.net/v2/products/(product)/versions` — "**current version**, buildconfig, cdnconfig, productconfig and optionally keyring per region"

CDN 檔案佈局為 `http://(cdnsHost)/(cdnsPath)/(pathType)/(前兩碼)/(次兩碼)/(完整 hash)`。

**關鍵：舊 build 不會永久留在 CDN 上。** TACT 頁原文：

> "**Blizzard regularly cleans old builds from the CDN** so any example files mentioned in this article might be unavailable at the time of reading."

**實測驗證（2026-09-03）：** 以社群記錄的 build config hash，對 `wow_classic` 的 cdns（`Path = tpr/wow`）發 HTTP GET `/tpr/wow/config/xx/yy/<hash>`：

| build | build config | `us.cdn.blizzard.com` |
|---|---|---|
| 5.5.4.69585（當前） | `a918d337…` | **200**（44982 bytes） |
| **4.4.2.60895** | `dae7ca8b…` | **404** |
| 3.4.3.54261 | `c91609c6…` | **404** |

**當前 build 拿得到，兩個 pinned 目標都已被清除。** 與官方文件描述的清理行為一致。

> **未驗證：** 只測了 `us.cdn.blizzard.com`（另一台 `level3.blizzard.com` 對所有 hash 都回 403，包含當前 build，結果不具鑑別力）。eu/kr/tw/cn 區域未測試。

**社群 build 索引存在，但救不了你。** `https://wago.tools/builds` 提供 `https://wago.tools/api/builds`，收錄 `wow_classic` 280 筆歷史 build（可回溯到 1.13.0.28211，2018-10-23），含每個 build 的 `build_config` / `cdn_config` / `product_config` hash 與日期 —— 包含 `4.4.2.60895`（2025-05-20，`bc=dae7ca8b…`）與 `3.4.3.54261`（2024-04-13，`bc=c91609c6…`）。**這是第三方社群的 metadata 存檔，不是 Blizzard 服務**；而且**拿到 hash 也沒用，因為物件本身已被 CDN 清除**（見上表 404）。

### 3.4 TrinityCore 自己的 remote CASC 能不能指定 build？——**不能**（已驗證，原始碼）

這是本次調查最有價值的第一方發現。

`map_extractor` 確實支援 remote CASC，但看它的 usage（`src/tools/map_extractor/System.cpp:161-175`）：

```
-p which installed product to open (wow/wowt/wow_beta)
-c use remote casc
-r set remote casc region - standard: eu
```

**只有 product 與 region，沒有任何 build 參數。** 實作也吻合 —— `src/tools/extractor_common/CascHandles.cpp:210-222` 的 `Storage::OpenRemote()` 只填了四個欄位：

```cpp
args.szLocalPath = strPath.c_str();
args.szCodeName  = strProduct.c_str();
args.szRegion    = strRegion.c_str();
args.dwLocaleMask = localeMask;
```

而 build 號碼在 TrinityCore 這邊是**被偵測、不是被指定**的：`src/tools/map_extractor/System.cpp:1519-1526` 呼叫 `CascStorage->GetBuildNumber()` 後只是 `printf("Detected client build: %u\n\n", build)`。

**所以：TrinityCore 的 remote CASC 永遠抓「該 product 當前的 live build」。** 對 `cata_classic`（需要 4.4.2.60895）而言，remote CASC 今天只會抓到 `wow_classic` 的 5.5.4.69585 —— 完全錯誤的資料。

**但底層函式庫其實支援釘 build。** TrinityCore 內附的 CascLib（`dep/PackageList.txt:60-62`，版本 `5dafc4c5a53faecfe269e525d37cf977cfa818b1`）在 `dep/CascLib/src/CascLib.h:383-386` 定義：

```c
LPCTSTR szBuildKey;   // If non-null, this will specify a build key (aka MD5 of build config
                      // that is different that current online version)
LPCTSTR szCdnHostUrl; // If non-null, specifies the custom CDN URL...
```

且 `dep/CascLib/src/CascOpenStorage.cpp:1320-1356` 顯示參數字串格式依序為 `localPath * cdnHostUrl * codeName * region * buildKey`。

**歸納出三層結論：**

1. **CascLib 支援釘特定 build**（`szBuildKey`）—— 這證實了「舊 build 在協定上是可用 build config hash 取回的」。
2. **TrinityCore 沒有把這個能力接出來** —— `OpenRemote()` 未設定 `szBuildKey`，CLI 也沒有對應選項。要用它得自己改一小段程式碼。
3. **但即使改了也沒用**，因為 4.4.2.60895 的 build config 在 CDN 上已是 404（3.3 節實測）。**這條路今天是死的，不是「麻煩」而是「不通」。**

### 3.5 必須區分的兩件事（重要）

| | 伺服器端**資料檔**（maps / vmaps / mmaps / DB2） | 可執行的**client 二進位檔** |
|---|---|---|
| 來源 | CASC 抽取（本機安裝 或 remote CASC） | 只能由 Battle.net 安裝 |
| 舊 build 可得性 | 協定上可用 build config hash 取回，**但 4.4.2 物件已被 CDN 清除（實測 404）** | **無任何管道**；Battle.net 只裝當前 build |
| 現況 | 不通 | 不通 |

**即使 CDN 還留著舊資料，它也只解決「伺服器的資料檔」，永遠不會給你一個可執行的舊版 client。** 這兩個問題是分開的，而現在**兩個都沒解**。

TrinityCore wiki 自己也把責任推回使用者（`https://trinitycore.info/en/install/Server-Setup`）：

> "**TrinityCore does not provide any Client Version for download. It is up to the user to get them themselves for master e.g. via Battle.Net.**"
> "master branch, wotlk_classic, cata_classic needs the version pointed near the top of github repository."
> "you cannot use cata_classic to extract wow 4.3.4 files or 4.3.4 files to run cata_classic server"

> **這段 wiki 指示對 `cata_classic` 已經過時**：Battle.net 的 `wow_classic` 下拉現在裝的是 5.5.4，不是 4.4.2。

### 3.6 自訂 launcher 是做什麼的（不背書，只陳述）

TrinityCore wiki Client Setup（`https://trinitycore.info/en/install/Client-Setup`）：

> "Master, cata_classic (wow 4.4.x): Change Config.wtf: `SET portal "IP address used in realmlist table"`"
> "**Note: you will need a custom client launcher to connect to master, cata_classic branches servers, i.e. https://arctium.io/wow**"

**該專案已更名：** `arctium.io/wow` 現導向 `burralis.io`；`https://api.github.com/repos/Arctium/WoW-Launcher` 以 301 導向 `Burralis/Game-Launcher`（MIT，C#，建立於 2021-08-03，最後 push 2026-08-30）。其網站自述：

> "A launcher that starts the World of Warcraft client **you already have installed** and connects it to a server of your choosing instead of the official one. It leaves your installation untouched."
> "**Development and education only.** We do not support playing on live private servers. Connecting to public networks with this launcher is strictly for education, testing and development, such as working on TrinityCore."

其 README 亦說明可 "Allow custom client version & cdn urls — Useful for launching older clients or serving data from your own CDN"。

**技術定位（純陳述）：** 現代架構的 client 走 Battle.net 登入與封包加密，無法像 12340 那樣只改 `realmlist.wtf` 就指向自架伺服器；這類 launcher 的作用就是接管啟動流程、改寫連線目標。**但注意關鍵限制：它啟動「你已經擁有的」client —— 它不能幫你取得一個 4.4.2 的 client。** 第 3.1–3.3 節的取得問題它一個都沒解決。

（`tc.burralis.io` 提供預先產生的資料，但只有 **3.3.5a 與 master**，沒有 3.4.x / 4.4.x 目錄。）

---

## 4. 效能與能耗：原生 ARM64 vs 翻譯層

### 4.1 現代 client 是否原生 Apple Silicon？（**部分未驗證**）

**零售版：已驗證。** Kaivax，2020-11-17（`https://us.forums.blizzard.com/en/wow/t/mac-support-update-november-16/722775/1`）：

> "With this week's patch 9.0.2, we're adding native Apple Silicon support to World of Warcraft. This means that the WoW 9.0.2 client will run natively on ARM64 architecture, rather than under emulation via Rosetta."

**Classic：只有間接證據。** Blizzard 支援文件 000243159（WoW Classic 系統需求，`https://us.support.blizzard.com/en/article/243159`）Mac 最低規格列出：

> CPU: "Intel® Core™ i5-750 or **Apple M1**"；GPU: "… or **Apple M1 / Metal capable GPU**"

零售版對照（文件 000353553，`https://us.support.blizzard.com/en/article/353553`）：CPU "Apple® M2 or Intel® Core™ Coffee Lake"，GPU "**Metal® capable** 4 GB GPU"。

> **未驗證：** 找不到 Blizzard 第一方明確說「Classic client 有原生 arm64 build」。Kaivax 的公告只涵蓋零售版 9.0.2。系統需求把 Apple M1 列為支援 CPU 是**最強的間接訊號**，但不是明文。
> **未驗證：** 也找不到 Blizzard 說明 WoW 何時在 macOS 上從 OpenGL 轉向 Metal。「Metal capable GPU」出現在現行系統需求中，是最強的第一方訊號。

### 4.2 3.3.5a 的圖形路徑

- Metal 於 **OS X El Capitan** 引入 Mac（`https://www.apple.com/newsroom/2015/06/08Apple-Announces-OS-X-El-Capitan-with-Refined-Experience-Improved-Performance/`，"Metal™, Apple's breakthrough graphics technology, is integrated into El Capitan"），2015-09-30 上市。**3.3.5a（2010）比 Metal 早約五年。**
- **未驗證：** 找不到 Blizzard 文件明說 3.3.5a Mac client 用 OpenGL（隨附 ReadMe 只列硬體需求）。OpenGL 是 2010 年 Mac client 唯一合理的選擇，但無第一方出處。

### 4.3 誠實的效能比較

> **沒有找到任何第一方或可靠的測量數據**比較 Apple Silicon 上原生 vs 翻譯（Rosetta 2 / Wine）的遊戲效能或功耗。**本節純屬架構層面的定性推論，不提供任何數字。**

架構上的層數差異是明確的：

| 路徑 | CPU | 圖形 API |
|---|---|---|
| 現代 Classic client（若為原生 arm64） | 原生 ARM64，**零翻譯** | 原生 **Metal** |
| 3.3.5a + CrossOver | 32-bit x86 → Wine 32-on-64 bridge → x86_64 → **Rosetta 2** → ARM64 | D3D9（或 OpenGL）→ 轉譯層 → Metal |
| 3.3.5a + Parallels/Win11 ARM64 | 32-bit x86 → **Prism/WOW64** → ARM64 | D3D9 → Parallels 虛擬 GPU → Metal |

**定性推論（不是測量）：** 每一層翻譯都要花 CPU 週期，而在筆電上，多花的 CPU 週期直接轉成更高功耗與更多發熱。原生 ARM64 + Metal 在效能與續航上**結構性地**佔優。**但這個優勢有多大，本文無法量化，任何具體百分比都會是捏造。**

另一個常被忽略的變數：**3.3.5a 是 2010 年的遊戲，本身負載極輕**。即使套上兩層翻譯，絕對效能未必成為體感瓶頸 —— 但功耗與發熱的代價是實打實的。**這一點同樣未經測量。**

---

## 5. 開源專案現況（簡短）

（依使用者要求大幅精簡；不列私服、不排名。）

| 專案 | 目標 build | 最後更新 |
|---|---|---|
| TrinityCore `cata_classic` | 4.4.2.60895 | 2026-08-31，積極維護 |
| TrinityCore `wotlk_classic` | 3.4.4.61581 | 2025-07-02，停滯（詳見[前一篇筆記](./wotlk-classic-on-modern-client.md)） |
| `alseif0x/rustycore` | 3.4.3.54261 | 2026-09-03（Rust 重寫，README 自述 "the full gameplay runtime is still under active migration"） |
| `wowemulation-dev/wooly-beast` | 4.4.2（60895） | 2026-05-06 |
| `mdX7/TrinityCore` (`wotlk_classic`) | 3.4.x | 2022-10-26，已死 |
| `haphert/TrinityCore_wotlk_classic_continued` | 3.4.3.54261 | 2024-11-11，已死 |

- **AzerothCore 僅支援 3.3.5a**（已驗證：組織下無任何 3.4.x/4.4.x 分支或 repo）。
- **CMaNGOS / MaNGOS / Ember 皆無 3.4.x 目標**（CMaNGOS 為 1.12 / 2.4.3 / 3.3.5；`cmangos/mangos-cata` 最後 push 2018-12-12）。

> 中立事實一則：以自架伺服器連線非官方 realm 屬於法律灰色地帶，Blizzard 歷來曾對公開營運的私服發出下架要求。使用者僅在自己機器上做技術研究，不涉及營運。

---

## 6. 結論：Apple Silicon 使用者的排序

排序權重依使用者宣告的優先序：**(i) 能在 Apple Silicon 上跑 → (ii) 效能／能耗 → (iii) WotLK 內容還原度**。

### 第 1 名：`3.3.5` 分支 + **Windows** 3.3.5a client + Parallels/Windows 11 ARM64

- **(i) 可行性：最高。** 32-bit x86 由 Windows 自己的 Prism/WOW64 模擬，**不依賴 Rosetta 2，不受 CrossOver 27 影響 —— 唯一沒有已知到期日的路徑。**
- **(ii) 效能：最差的一檔。** 指令翻譯 + 虛擬機 + 虛擬 GPU，三層開銷，筆電功耗代價最高。**未經測量。**
- **(iii) 內容：滿分。** 正統 3.3.5a，分支至今仍積極維護（最後 commit 2026-08-30），有官方 TDB。
- **成本：** Parallels 授權 + Windows 授權。

### 第 2 名：`3.3.5` 分支 + **Windows** 3.3.5a client + CrossOver 26.x

- **(i) 可行性：今天可以，但正在關門。** CrossOver 27 移除 32-bit bottle；Rosetta 2 於 macOS 27 終止。**不要升級到 CrossOver 27。**
- **(ii) 效能：比第 1 名少一層虛擬機，理論上較好；但同樣經過 Rosetta 2。未經測量。**
- **(iii) 內容：滿分。**
- **最大證據缺口：** Wine AppDB 的 Silver 評級**全部來自 Linux，沒有任何 macOS 測試紀錄**。
- **成本：** CrossOver 授權；不需要 Windows 授權。

### 第 3 名：`cata_classic` 分支 + 4.4.2 Classic client

- **(ii) 效能：理論上最好** —— 若 Classic client 確為原生 arm64（**僅有間接證據**）+ 原生 Metal，零翻譯層，筆電續航最佳。
- **(iii) 內容：八成。** 諾森德與全部 WotLK 副本／團隊本腳本幾乎完整（見[前一篇筆記](./wotlk-classic-on-modern-client.md)第 4 節），但 1–60 級是災變後的世界、職業是 Cata 設計。
- **(i) 可行性：這才是它掉到第 3 名的原因 —— client 現在弄不到。** Battle.net 只裝 5.5.4；CDN 上 4.4.2.60895 的 build config 已被清除（實測 404）；TrinityCore 的 remote CASC 不能指定 build。**除非你手上已經有一份 4.4.2.60895 的安裝，否則這條路不通。**

**這就是誠實的張力所在：內容最完整、維護最好的 WotLK（`3.3.5`）綁在效能最差的執行路徑上；而效能最好的執行路徑（`cata_classic`，原生 ARM64 + Metal）內容只有八成，而且 client 現在根本取得不到。**

### 不建議

- **原版 3.3.5a Mac client** —— 32-bit，Catalina 起無法執行（第 1 節）。
- **Whisky** —— 2025-05-11 封存，作者明言不再維護。
- **`wotlk_classic` 分支** —— 已停滯，且其 client（3.4.4.61581）取得問題比 4.4.2 更嚴重（`wow_classic` 產品線早已越過 3.4.x）。
- **「64-bit 自製 3.3.5a client」** —— 未找到任何證據，技術上也不合理（第 2.6 節）。

### 建議的下一步（成本最低的實驗順序）

1. 先確認手上是否已有任何 Classic client 安裝 —— 這一步決定第 3 名是否還在選項內。
2. 若沒有，**放棄現代 client 路線**，走第 1／2 名。
3. 取得 Windows 版 3.3.5a client（非 Mac 版），用 `file Wow.exe` 確認是 `PE32 … Intel 80386`。
4. 先試 CrossOver 26.x 的試用版（成本最低、層數最少）；若不理想或考慮長期，再轉 Parallels + Windows 11 ARM64。
5. 伺服器端不是問題：TrinityCore 在 `master` / `3.3.5` / `cata_classic` 三個分支都有 `.github/workflows/macos-arm-build.yml`（`runs-on: macos-14`，arm64），**server 原生跑在 Apple Silicon 上，完全沒有架構障礙**。

---

## 7. 驗證方式

本 repo 內（唯讀）：

```
sed -n '161,175p' src/tools/map_extractor/System.cpp          # usage：只有 -p / -c / -r，無 build 參數
sed -n '210,222p' src/tools/extractor_common/CascHandles.cpp   # OpenRemote 未設 szBuildKey
sed -n '1519,1526p' src/tools/map_extractor/System.cpp         # build 是「偵測」而非「指定」
sed -n '379,388p' dep/CascLib/src/CascLib.h                    # szBuildKey / szCdnHostUrl 定義
sed -n '1320,1356p' dep/CascLib/src/CascOpenStorage.cpp        # 參數字串順序含 buildKey
sed -n '60,62p' dep/PackageList.txt                            # CascLib 版本
git ls-tree --name-only origin/3.3.5:.github/workflows         # 含 macos-arm-build.yml
git log -1 --format='%ci %h %s' origin/<branch>
```

外部（實際抓取）：

```
https://us.version.battle.net/v2/products/wow_classic/versions
https://us.cdn.blizzard.com/tpr/wow/config/<xx>/<yy>/<buildconfig-hash>
```

---

## 8. 實際取用過的來源

**Apple**
- `https://support.apple.com/en-us/103076` — Catalina 起 32-bit app 不相容
- `https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment`
- `https://support.apple.com/guide/security/rosetta-2-on-a-mac-with-apple-silicon-secebb113be1/web`
- `https://developer.apple.com/news/?id=w5ngl9k2` — macOS 27 為最後支援 Rosetta 的版本
- `https://developer.apple.com/games/game-porting-toolkit/`、`https://developer.apple.com/games/whats-new/`
- `https://developer.apple.com/videos/play/wwdc2023/10123/`
- `https://www.apple.com/newsroom/2015/06/08Apple-Announces-OS-X-El-Capitan-with-Refined-Experience-Improved-Performance/`

**Blizzard**
- `https://worldofwarcraft.blizzard.com/en-us/news/21788100/support-ending-for-world-of-warcraft-32-bit-client-this-summer`
- `https://us.forums.blizzard.com/en/wow/t/mac-support-update-november-16/722775/1` — 9.0.2 原生 Apple Silicon
- `https://us.forums.blizzard.com/en/blizzard/t/diablo-ii-mac-support-update/14367`
- `https://us.support.blizzard.com/en/article/369636` — 現行 WoW 版本清單
- `https://us.support.blizzard.com/en/article/243509` — Classic 安裝方式
- `https://us.support.blizzard.com/en/article/243159`、`.../353553` — 系統需求
- `https://www.bluetracker.gg/wow/topic/us-en/10960856615-wrath-of-the-lich-king-system-requirements/` — WotLK 系統需求 blue post
- `https://us.version.battle.net/v2/products/*/versions`

**CodeWeavers / Wine**
- `https://www.codeweavers.com/blog/mjohnson/2026/6/11/whats-in-and-whats-out-for-crossover-27`
- `https://www.codeweavers.com/crossover/changelog`
- `https://support.codeweavers.com/en_US/user-guides/crossover-mac-user-guide`
- `https://www.codeweavers.com/compatibility/crossover/world-of-warcraft`
- `https://appdb.winehq.org/objectManager.php?sClass=version&iId=32890`
- `https://github.com/Whisky-App/Whisky`

**其他**
- `https://learn.microsoft.com/en-us/windows/arm/apps-on-arm-x86-emulation`
- `https://wowdev.wiki/NGDP`、`https://wowdev.wiki/TACT`（社群 wiki，非 Blizzard 官方）
- `https://wago.tools/builds`、`https://wago.tools/api/builds`（第三方社群存檔）
- `https://trinitycore.info/en/install/Server-Setup`、`.../Client-Setup`
- `https://burralis.io`、`https://github.com/Burralis/Game-Launcher`

**取用失敗：** `wiki.winehq.org` 與 `gitlab.winehq.org`（反爬蟲 403）、fandom 的 wowwiki-archive / wowpedia（Cloudflare 阻擋）—— 故本文不含這些來源的引用。
