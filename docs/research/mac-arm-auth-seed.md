# Mac ARM（`MacA` / A64）client auth seed —— 3.4.3.54261 有沒有公開值，以及怎麼自己挖出來

> 撰寫日期：2026-09-06
> 相關筆記：[維護中的 3.4.3 forks 盤點](./maintained-343-forks.md)（本篇沿用它對 `xHashii` / `haphert` / `RioMcBoo` / `alseif0x` 的盤點結論）、[TDB343.24081 資料缺陷](./tdb343-data-defects.md)（同一個 tag / 同一個 54261 client）、[macOS client 選項](./macos-client-options.md)、[Apple Silicon 上的 3.3.5a Mac client](./mac-client-3.3.5a-on-apple-silicon.md)、[HermesProxy 評估](./hermesproxy-evaluation.md)（本篇在它的 `BuildAuthSeeds.csv` 裡找到唯一公開的 `MacA` 值）
> **本篇問兩個問題：**（1）3.4.3.54261 的 Mac ARM auth seed 有沒有人公開過？（2）沒有的話，**我們自己怎麼從手上的 macOS binary 把它挖出來**？
> 來源限定 primary sources：本 repo 的**唯讀** git（未切分支、未修改任何追蹤檔）、`gh api` code search、`curl` 取得的 raw 原始碼與 SQL，以及**對本機 macOS client binary 的直接靜態檢查**（`file` / `otool` / `nm` / `codesign` / Python byte scan，全部唯讀）。凡未實跑者標示「**未驗證**」。未使用瀏覽器自動化。未記錄任何 client 下載點。

---

## 0. TL;DR —— 直說 Yes/No

**No。3.4.3.54261 的 Mac ARM seed 公開世界上不存在；任何 3.4.x build 的 Mac seed（不分 x64 / A64）也都不存在。**
但**有一個公開的 `MacA` seed**（別的資料片），而且**有一條不必挖 seed 的繞路**。

七點裁決：

1. **上游 TrinityCore 確實有出 Mac A64 key，但最早只到 build `56196`（11.0.2 retail）。** 本機 `sql/` 樹裡 248 筆 `('Mac','A64',...)` 全部落在 56196–69497，**3.4.x 一筆都沒有**（§1.1）。所以「上游 ships no seed values」這個前提**是錯的**——上游每個 build 都在發，只是**從來沒發過 WotLK Classic 這條線的**。
2. **`origin/wotlk_classic` 分支的 `build_auth_key` 裡連 `54261` 這個 build 都不存在**，更沒有任何 Mac row；該表在 50000–55999 區間**只有 `Win`/`x64`/`WoW`**（§1.2）。
3. **唯二公開 54261 seed 的 repo（`haphert`、`d23monkey`）只給了 Windows x64**，`mac64AuthSeed` 欄位是 `NULL`，而且那條分支的 schema **根本沒有 `macArmAuthSeed` 欄位**（§1.3）。兩者都佐證了我們手上的 `25FD812475DCF26F9F1383AED37FC99E`。
4. **★ 唯一公開的 `MacA` seed 在 HermesProxy：`3B31A4F4C25382131A8FB95A1317412B`（build `42597`，Classic Era 1.14.2）。** 同檔還有 `7528AB80D693E149907757BC9540A6A6`（build `40618`，註解寫 "1.14.0 on MacOS ARM" 但 platform 欄位標 `Mc64`）。**證明 `MacA` 這個 platform 字串是真的、有人真的挖過 Mac ARM seed、格式就是 16 bytes hex**——但**跟 3.4.3 無關，不能拿來用**（§2）。
5. **★ 最有價值的發現不是某個值，而是 Arctium 的 `--use-static-auth-seed`：不挖 seed，改成「把 client 產生 seed 的那個函式整個換掉」，讓它回傳一個我們自己指定的常數（Arctium 用的是 `179D3DC3235629D07113A9B3867F97A7`），再把那個常數寫進 `build_auth_key`。** 這條路 Windows 上已經是成熟且有人在用的作法（§4.3）。
6. **我們手上的 macOS binary 對挖 seed 極度友善——比 Windows 友善得多。** 實測：**沒有 `LC_ENCRYPTION_INFO`**（沒被加密，靜態分析可行）、**client 直接呼叫 Apple CommonCrypto 的 `_CC_SHA256_Init/Update/Final`**（可以 symbol hook）、**沒有 `_CCHmac`**（HMAC 是自己刻在 CC_SHA256 上的）、binary 內確實有 `MacA` 這個 FourCC 字串（§3）。
7. **建議路線：先做 §4.4 的 runtime hook（一次 login 就拿到值），失敗再走 §4.3 的 static-seed patch。** 兩條都不需要打敗 Arxan。

---

## 1. 公開值盤點 —— 全部落空

### 1.1 上游 TrinityCore：有 Mac A64，但最早只到 11.0.2

`build_auth_key` 這張表是 commit `842e1b6c9b` / `e94558d078`（2024-08-30，"Refactor build_info structure to support any client variants"）引進的。migration 檔 `sql/old/11.x/auth/24051_2024_09_03/2024_08_30_00_auth.sql` 把舊欄位搬過去：

```sql
CREATE TABLE `build_auth_key` (
  `build` int NOT NULL,
  `platform` char(4) ..., `arch` char(4) ..., `type` char(4) ...,
  `key` binary(16) NOT NULL,
  PRIMARY KEY (`build`,`platform`,`arch`,`type`)
);
INSERT INTO `build_auth_key` SELECT `build`,'Mac','A64','WoW',UNHEX(`macArmAuthSeed`) FROM `build_info` WHERE LENGTH(`macArmAuthSeed`)=32;
```

注意它是從**舊的 `macArmAuthSeed` 欄位**搬的——也就是說舊 schema 早就有這個欄位，只是 3.4.x 那些列全是 `NULL`。

本機 `master` 的 `sql/` 樹實測（唯讀 grep，248 筆去重）：

```
Mac/A64 row 總數：248
build 範圍：56196 … 69497
低於 56000 的 Mac/A64row：0 筆
```

而 `56196` 在 `build_info` 裡是 `(56196,11,0,2,NULL)` —— **11.0.2，The War Within retail**。換句話說：

> **上游發 Mac A64 key 是 2024-08 之後才開始的事，而 WotLK Classic 這條線 2024-08 就凍結了。兩條時間線剛好錯開。**

最早幾筆長這樣（`sql/base/auth_database.sql`）：

```
(56196,'Mac','A64','WoW',0x778F6A5DF79A4EF1B86F651F3B303CE7)
(56288,'Mac','A64','WoW',0x41710C793EF021721F14B06EC1896D3F)
(56311,'Mac','A64','WoW',0x412D3200715AAFDC0522DF031A941F0E)
```

近期的 build 一次發 7 把（`sql/old/12.x/auth/26011_2026_02_06/2026_02_04_01_auth.sql`，build 65727）：

```sql
(65727,'Mac','A64','WoW', 0xDFBCE4A4A707A6E40B826BC765CFD2C3),
(65727,'Mac','A64','WoWC',0xB592E8CC636F8C8D0942273CBD888ED3),
(65727,'Mac','x64','WoW', 0xA2DD238DF367395ADB4218369057E9AF),
(65727,'Mac','x64','WoWC',0x6B0B37F8F3D87736FA9C82009ACD0CFB),
(65727,'Win','A64','WoW', 0xEFAB5EAAC583CBF8D5B1F78E3FEB7004),
(65727,'Win','x64','WoW', 0xC2D8FE2AB89A557A0700B53B04B2E152),
(65727,'Win','x64','WoWC',0xC25BCE27CE4DC62302FAC67BB2ABCF2A);
```

**上游 commit message 從來沒有記錄這些值是怎麼取得的。**（例如 Shauren 的 `05fdb6a82a`，2024-09-05，只寫 "Core: Add auth keys for all types for build 11.0.2.56421"。）

### 1.2 `origin/wotlk_classic` 分支：連 54261 都沒有

該分支 `sql/base/auth_database.sql` 的 `build_auth_key` 實測：

```
54261 出現次數：0
50000–55999 區間的 'Mac' row：0 筆（全部只有 Win/x64/WoW）
該分支最早的 Mac/A64：build 56489
表內最大 build：61581
```

分支 tip 打的是 3.4.4.61581（見[維護中的 3.4.3 forks](./maintained-343-forks.md) §1.1），**它連我們在跑的 54261 都沒收**。

> **注意 code 版本差異：** `origin/wotlk_classic` tip 的 `WorldSocket.cpp:735-743` 已經改用 `Trinity::Crypto::SHA512` / `HMAC_SHA512`，且 seed 常數是 `std::array<uint8,32>`。**我們跑的 `TDB343.24081` tag 才是既定前提裡的 SHA256 + 16-byte seed 版本。** 本篇的 client 端分析對應的是後者（client binary 裡的常數確實是 16 bytes，見 §3.3）。

### 1.3 其他 core 與 fork：全部落空

| 專案 | 檢查對象 | 結果 |
|---|---|---|
| `haphert/TrinityCore_wotlk_classic_continued` | `sql/updates/auth/wotlk_classic/2024_04_17_00_auth.sql` | 只有 `win64AuthSeed`，`mac64AuthSeed` = `NULL` |
| `d23monkey/TrinityCore343` | 同上（逐字相同） | 同上 |
| `RioMcBoo/CypherCoreClassicWOTLK` | `sql/base/auth_database.sql` | 124 筆 Mac/A64，**最早 56196**，無 54261 |
| `xHashii/3.4.3_Source` | `sql/base/auth_database.sql` | 舊 schema，**無 `build_auth_key`**，無 54261 mac seed |
| `Frostshake/TrinityCoreClassic`、`TrinityCoreClassic/core` | `sql/base/auth_database.sql` | 無 `build_auth_key` |
| `CypherCore/CypherCore`（retail） | `sql/base/auth_database.sql` | 有 Mac/A64，但全 retail build |
| `cmangos/mangos-wotlk` | `sql/base/realmd.sql` | `build_auth_key` / `A64` / `54261` 命中 **0**（3.3.5 線本來就沒有這套機制） |
| `azerothcore/azerothcore-wotlk` | — | 3.3.5a-only，無 per-build auth seed 機制（**未驗證**：未取得其 auth SQL 實體路徑，僅依 3.3.5 線通則判斷） |

`haphert` 那筆 54261 seed 的 commit message 是 `"Add files via upload"`（2024-09-09）——**網頁批次上傳，沒有任何來源說明**。

### 1.4 GitHub code search 結果

- `25FD812475DCF26F9F1383AED37FC99E` → **4 個命中**，全是上面 `haphert` / `d23monkey` 的兩個檔。**沒有人在同一個檔／同一個 commit 裡一起公開 Mac seed。**
- `C5C69895763F1DCDB6A13728B312FF8A`（AuthCheckSeed）→ **0 命中**（它在 server 端是 byte array 形式，不是 hex 字串）。
- `macArmAuthSeed` → 30 命中，**全部是 TrinityCore 那個 migration SQL 的複本**。
- `0x25FD812475DCF26F9F1383AED37FC99E`、`54261 build_auth_key` → **0 命中**。

---

## 2. 唯一公開的 `MacA` seed（別的資料片，不能用）

`WowLegacyCore/HermesProxy`，`HermesProxy/CSV/BuildAuthSeeds.csv`（實抓，HTTP 200，全檔 12 行）：

```csv
build,platform,seed,comment
# Vanilla
31650,Wn64,82CC71696814948331AC5B996E02BE5D, 1.13.2 on windows x86_64
40618,Wn64,1278EB34F243ED7898D614C0E278EAC0, 1.14.0 on windows x86_64
40618,Mc64,7528AB80D693E149907757BC9540A6A6, 1.14.0 on MacOS ARM
41794,Wn64,91D3C1D62CD20FCCD4D0A71E051CE7CA, 1.14.1 on windows x86_64
42597,Wn64,2C76A6CDD32F651E940B5F682D8E15CE, 1.14.2 on windows x86_64
42597,MacA,3B31A4F4C25382131A8FB95A1317412B, 1.14.2 on MacOS ARM

# TBC
40892,Wn64,5795B965E273C19ADD2164D098F0595A, 2.5.2 on windows x86_64
42328,Wn64,395EA5F21B05DC0D022141E5C71B1141, 2.5.3 on windows x86_64
```

三個可用的推論：

1. **`MacA` 是真的 platform FourCC**，且 TrinityCore `src/server/shared/Realm/ClientBuildInfo.h:48` 有對應定義 `static constexpr Id Mac_arm64 { "MacA"_fourcc };`。我們 client 回報 `MacA` 完全合理。
2. **`Mc64` → `MacA` 的切換就發生在 1.14.0 → 1.14.2 之間**：40618 那筆註解寫 "MacOS ARM" 卻標 `Mc64`，42597 才標 `MacA`。這解釋了為什麼舊 schema 的欄位叫 `mac64AuthSeed`（Intel）而 ARM 要另開 `macArmAuthSeed`。
3. **格式就是 16 bytes / 32 hex chars，每個 build 各自獨立**，沒有跨 build 規律可推——**所以 42597 的值對 54261 毫無用處**，列在這裡只作為「有人挖得出來」的存在證明。

該值由 `_BLU` 於 commit `b2d040ff`（2023-10-18，"Add seed for 1.14.2 on MacOS ARM"）加入，**commit message 同樣沒有記錄方法**。

---

## 3. 我們手上這顆 macOS binary 的實測體檢

檢查對象：`/Users/shinichi/Works/side-project/wow343-archive/mac-client/World of Warcraft Classic.app/Contents/MacOS/World of Warcraft Classic`（73,238,928 bytes，全部唯讀操作）。

### 3.1 基本結構

```
Mach-O universal binary with 2 architectures:
  x86_64  slice @ file 0x4000    size 0x24d2260
  arm64   slice @ file 0x24d8000 size 0x2100990
```

arm64 slice 的 `__TEXT` vmaddr `0x100000000` / vmsize `0x1f10000`；`__DATA_CONST` vmaddr `0x101f10000`。
binary 內含字串 `3.4.3.54261` 與 `Mozilla/5.0 (Macintosh; U; %s) WorldOfWarcraft/3.4.3.54261`，以及 `darwin-ARM64-clang-release` —— **確認是對的那顆**。

### 3.2 保護狀態 —— 比 Windows 好挖

| 檢查 | 結果 | 意義 |
|---|---|---|
| `LC_ENCRYPTION_INFO` | **兩個 slice 都是 0 筆** | **沒有 FairPlay 加密，靜態分析可行** |
| `codesign` flags | `0x10000(runtime)` | 有 hardened runtime，要 hook 得重簽（我們控制 ad-hoc 簽章，可加 `get-task-allow` / `disable-library-validation`） |
| client 自己的 entitlements | `com.apple.security.cs.allow-jit`、`allow-unsigned-executable-memory`、**`disable-executable-page-protection`** | client **自己就要求可寫可執行的頁面**——這正是 Arxan 那類 runtime 自解密 / 自修改 code 的特徵 |
| Team ID | `G847MC6JZ5`，`com.blizzard.worldofwarcraft`，簽章時間 2024-04-13 | — |

> **關於 Arxan：** `wow-patcher` 的文件明講 Windows 端 `.text` 被 Arxan TransformIT 加密、要靠 PE 的 TLS callback 在 runtime 解密（`src/cmd/dump.rs`、`AGENTS.md:9-10`），而它的 `dump-text` / `dump-sections` 子命令 **`#[cfg(target_os = "windows")]` only**，macOS 端只做 `codesign --remove-signature`。
> **macOS 這顆沒有 `LC_ENCRYPTION_INFO`，且 `wow-patcher` 有在 macOS 的 `__DATA` / `__DATA_CONST` / `__TEXT.__const` 直接做靜態 patch**，代表**至少 data 段是明文的**（我們下面 §3.3 也直接讀到了）。`__TEXT.__text` 本身有沒有等價保護 —— **未驗證**，公開資料沒有任何一方說過。

### 3.3 那四個共用常數確實在 `__DATA_CONST`，而且 seed 不在旁邊

在 arm64 slice 內以 raw bytes 搜尋，**完全命中既定前提給的 offset**：

```
AuthCheckSeed        arm64-relative 0x1e0ce20  (fat file 0x42e4e20)
ContinuedSessionSeed                0x1e0ce30
SessionKeySeed                      0x1e0ce40
EncryptionKeySeed                   0x1e0ce50
```

（既定前提裡寫的 `0x1e0ce20` 是 **arm64 slice 相對 offset**；在 fat binary 裡要加 `0x24d8000`。x86_64 slice 的同一張表在 fat file `0x21a0c30`。）

把整張表前後 dump 出來：

```
0x1e0ce00  631633BF447398A4B489B4C26FBC03AD   ← 前鄰常數
0x1e0ce10  A71FB69BC97CDD96E9BBB821398D5AD4   ← 前鄰常數
0x1e0ce20  C5C69895763F1DCDB6A13728B312FF8A   ← AuthCheckSeed
0x1e0ce30  16AD0CD446F94FB2EF7DEA2A17664D2F   ← ContinuedSessionSeed
0x1e0ce40  58CBCF40FE2ECEA65A90B801686C280B   ← SessionKeySeed
0x1e0ce50  E9753C50909361DA3B07EEFAFF9D41B8   ← EncryptionKeySeed
0x1e0ce60  909CD0505A2C14DD5C2CC06414F3FEC9   ← 後鄰常數
0x1e0ce70  0900080F280005E50505DBE7E9E5EBE5   ← 已經不是 16-byte 常數了（別的資料）
```

**這張表就是 client 版的 `WorldSocket.cpp:55-62` 常數區**（server 端順序：AuthCheck / SessionKey / ContinuedSession / Encryption，client 端順序略有不同但同一組）。前後那三個鄰居很可能對應 `EnableEncryptionSeed` / `EnableEncryptionContext` 之類 —— **既定前提說已經測過三個鄰近常數都不是 MacA seed，這與此處觀察一致：per-build / per-platform 的 auth seed 根本不在這張唯讀常數表裡。**

`25FD812475DCF26F9F1383AED37FC99E`（Windows seed）在 arm64 與 x86_64 兩個 slice 都 **NOT FOUND** —— 與既定前提相符。

### 3.4 ★ 加密函式庫：CommonCrypto，而且沒有 CCHmac

arm64 slice 的 undefined symbols（共 1,012 個）中與加密相關的**全部**：

```
_CC_SHA256          _CC_SHA256_Final    _CC_SHA256_Init    _CC_SHA256_Update
_CCCrypt
_SecKeyCopyExternalRepresentation
_SSLClose _SSLHandshake _SSLRead _SSLWrite _SSLSetCertificate ...（Secure Transport，走 HTTPS 用，非遊戲協定）
```

x86_64 slice 相同（`_CC_SHA256*` + `_CCCrypt`）。

三個關鍵推論：

1. **client 沒有靜態連 OpenSSL，SHA-256 是呼叫 Apple CommonCrypto 的 `_CC_SHA256_Init/Update/Final`** —— **這是 dynamic symbol，可以被 `DYLD_INSERT_LIBRARIES` interpose 或 frida attach 攔截。**
2. **完全沒有 `_CCHmac`** —— HMAC-SHA256 是 Blizzard **自己刻在 `CC_SHA256` 之上**的（或 inline）。所以 hook `CCHmac` 沒用，**但 hook `CC_SHA256_Update` 反而更好**，因為 digest 的第一步 `SHA256(sessionKey ‖ seed)` 一定會把 seed 餵進 `CC_SHA256_Update`。
3. Ed25519 不在 CommonCrypto 裡，所以簽章驗證那部分應該另有 bundled 實作 —— 與本題無關。

### 3.5 FourCC 字串確實在 binary 裡

在 arm64 slice 搜尋 platform / type FourCC：

```
b'MacA'  -> 0x1d61fd4, 0x1db1e91, 0x1db1ebe
b'WoW\0' -> 0x1d18a90, 0x1d204fe, 0x1d20559, 0x1e5f86c
b'Win\0' -> 0x1cce626, 0x1d036f4
b'x64\0' -> 0x1dac4b6
b'Mc64'  -> NOT FOUND      b'A64\0' -> NOT FOUND      b'WoWC\0' -> NOT FOUND
```

其中兩個特別有價值：

- **`0x1d18a90` 是 build-type FourCC 表**：`...Launcher.app\0` `WoWT\0` `WoWB\0` `WoW\0` `WoWI\0` `UNDEFINED\0`。
  對照 `src/server/shared/Realm/ClientBuildInfo.h:80-85`：`Retail{"WoW"}` / `Beta{"WoWB"}` / `Ptr{"WoWT"}`。**完全對得上。**
- **`0x1d61fd4` 的 `MacA` 緊跟在 `semantic_version.pb.h\0` `6.2.0\0` 之後**，屬於 BattleNet 那組字串。
- **`0x1e5f86c` 是 build metadata blob**：`WoW\0` 後面接一串數值，再接 `darwin-ARM64-clang-release\0`。

注意 `MacA` 在 `__cstring` 裡是**獨立的 C 字串**，不像 Windows 那樣「字串後面緊接 `call`」——因為 arm64/Mach-O 的字串與 code 分屬不同 section。**這直接決定了 §4.2 的靜態路線必須改用 ADRP/ADD xref，不能照抄 Arctium 的 byte pattern。**

---

## 4. 怎麼挖 —— 方法論（本篇重點）

### 4.1 seed 在 client 裡到底長什麼樣？

**它不是一個可以掃出來的常數，而是「一個函式寫進 caller 給的 16-byte buffer」。**

最硬的證據來自 Arctium 系 launcher —— 它根本不去讀 seed，而是**把產生 seed 的那個函式整個換掉**。`Worlgun/WoW-Launcher`（Arctium/WoW-Launcher 的 mirror），`src/Patterns/Windows.cs`：

```csharp
// Auth seed function.
public static short[] AuthSeed = { 0x57, 0x6F, 0x57, 0x00, 0xE8, -1, -1, -1, -1, 0x48, 0x8D };
```

即 ASCII `"WoW\0"` + `E8 rel32`（`call`）+ `48 8D`（`lea`）。**anchor 是 build-type FourCC。**

`src/Launcher.cs:360-378` 顯示要穿兩層 indirection 才會到真正的函式：

```csharp
var authSeedLoadOffset = memory.Data.FindPattern(Patterns.Windows.AuthSeed);
var leaStartOffset = authSeedLoadOffset + 9;
var leaValue = Unsafe.ReadUnaligned<int>(ref memory.Data[leaStartOffset + 3]);
var authSeedWrapperOffset = leaStartOffset + leaValue + 7;
var jmpValue = Unsafe.ReadUnaligned<uint>(ref memory.Data[authSeedWrapperOffset + 6]);
var authSeedFunctionOffset = authSeedWrapperOffset + 5 + jmpValue + 5;
```

`"WoW\0"` → `call` → `lea`(rel32) → wrapper → `jmp`(rel32) → 真正的 get-seed function。

而它替換上去的函式本體（`src/Patches/Windows.cs`）洩漏了 ABI：

```csharp
public static byte[] AuthSeed = { 0x0F, 0x28, 0x05, 0xEF, 0xBE, 0xAD, 0xDE, 0x0F, 0x11, 0x02, 0xC3 };
// movaps xmm0, [rip+disp32] ; movups [rdx], xmm0 ; ret
```

→ **x64 上 seed function 把 16 bytes 寫進 `rdx` 指向的 buffer。** 這解釋了為什麼 raw scan 找不到：值是被函式「產出」的，而且那個函式住在 Windows 上被 Arxan 加密的 `.text` 裡。

同一個 anchor 被 `wowemulation-dev/wow-patcher` 獨立記錄，`src/patterns/runtime/windows.rs`：

```rust
/// Auth-seed function entry. The string `"WoW\0"` followed by a
/// `call` instruction is the canonical anchor.
/// Used by the static-auth-seed feature (planned, not yet ported).
pub fn auth_seed_pattern() -> Pattern {
    vec![0x57, 0x6F, 0x57, 0x00, 0xE8, WC, WC, WC, WC, 0x48, 0x8D]
}
```

**函式體內那 16 bytes 究竟是 `mov` 立即數拼出來、XOR 白化、還是查表 —— 公開資料沒有任何一方說過（未驗證）。** 但因為它在 Arxan 加密的 `.text` 裡，「raw scan 找不到」不需要額外的混淆假設就能解釋。

另外 `key` 是 `(build, platform, arch, type)` 四元組定址（見 §1.1 的 schema 與 build 65727 一次七把），代表 client 端很可能是**一張以 FourCC 為 key 的表／switch**，而不是單一常數。

### 4.2 路線 A：靜態 —— FourCC anchor + xref（arm64 版）

Windows 的 byte pattern **不能直接搬到 arm64**（§3.5）。等價作法：

1. 在 `__TEXT,__cstring` 找 `WoW\0` / `MacA`（我們已經有 offset：`0x1d18a90` 的 type 表、`0x1d61fd4` 的 `MacA`）。
2. 把 file offset 換成 vmaddr（arm64 `__TEXT` vmaddr base `0x100000000`），再在 `__TEXT,__text` 掃 **`ADRP xN, page` + `ADD xN, xN, #off`** 這組指令對，找出所有引用該字串的位置——這是 arm64 上取字串位址的標準 idiom，等同 x64 的 `lea rip+disp32`。
3. 從 xref 往下走到被 `BL` 呼叫的 callee，讀出它往 `x0`/`x1`/`x8` 指向的 buffer 寫進去的 16 bytes。

**成本高**：需要真正的反組譯器。本機**沒有** radare2 / rabin2 / Ghidra / IDA（實測 `which` 全部落空），只有 Apple LLVM 的 `objdump`。用 `objdump -d --start-address/--stop-address` 對 32 MB 的 `__TEXT` 做全域 ADRP 掃描可行但很笨重。**未驗證：本篇沒有實際跑完這條路線。**

另外 `agatho/ida-wow-analyzer`（IDA plugin，約 80 個 analyzer）**沒有 auth-seed extractor** —— 它的 `auth_lifecycle.py` 復原的是 opcode/phase FSM，不是加密常數。

### 4.3 ★ 路線 B：根本不挖 —— static auth seed patch

**Arctium 的 `--use-static-auth-seed`。** `src/LaunchOptions.cs` / `Launcher.cs:278-291` 的說明字串：

> *"Generates a patch for the auth seed so we don't have to update them on each build."*
> *"Static auth seed used. Be sure that the server you are connecting to supports it."*

得到的固定值是 **`179D3DC3235629D07113A9B3867F97A7`**（同一個值也出現在 HermesProxy 的 `ClientSeed` 設定，見其 issue #84）。

**這條路對我們特別合適**，因為：

- 我們**只需要自己的 server 認得**這個值 —— 在 `build_info` / `build_auth_key` 插一列 `(54261,'Mac','A64','WoW', 0x179D…)` 即可。
- 不必打敗任何保護，只要能在 client 啟動後把那個函式改成「回傳我們指定的常數」。
- macOS 端我們**控制 ad-hoc 簽章**，可以加 `get-task-allow`；且 client 自己就帶 `disable-executable-page-protection`（§3.2），寫 `__TEXT` 的阻力比一般 app 低。

**未驗證**：Arctium 的 patch 產生器是 Windows-only（`Patterns.Windows` / `Patches.Windows`），**沒有 macOS/arm64 版本**，我們得自己寫 arm64 的等價 patch（大致是 `ADRP x8,#page` + `ADD x8,x8,#off` + `LDP q0,[x8]` + `STR q0,[x1]` + `RET` 之類），而且仍需先用 §4.2 找到函式入口。**所以路線 B 並沒有省掉「找到函式」這一步，只省掉「看懂函式內部」。**

### 4.4 ★ 路線 C：runtime hook `CC_SHA256_Update` —— 建議先試這條

這是 §3.4 那個發現的直接應用，**也是 macOS 相對 Windows 最大的優勢**。

server 端 `WorldSocket.cpp`（`TDB343.24081` tag，SHA256 版）算的是：

```
digestKeyHash = SHA256( sessionKey ‖ platformSeed )
```

client 端必須算出**一模一樣**的東西才能通過驗證。而 client 的 SHA-256 是呼叫 **dynamic symbol `_CC_SHA256_Update`**。所以：

> **在一次真實 login 期間攔截 `CC_SHA256_Update(ctx, data, len)`，把每次呼叫的 `(data, len)` dump 出來。
> 其中會出現一個 56 bytes 的 buffer：前 40 bytes 是 session key，後 16 bytes 就是 `MacA` auth seed。**

（若 client 分兩次 `Update` 餵，就會看到一個 40-byte 呼叫緊接一個 **16-byte** 呼叫 —— 那 16 bytes 直接就是答案，更好認。）

具體步驟（**未驗證：本篇未實跑，本機也未安裝 frida**）：

1. 複製 app bundle，`codesign --remove-signature`，再用自己的 ad-hoc 身分重簽，entitlements 加上
   `com.apple.security.cs.disable-library-validation` 與 `com.apple.security.get-task-allow`
   （原有的 `allow-jit` / `allow-unsigned-executable-memory` / `disable-executable-page-protection` 要保留）。
2. 二選一：
   - **`DYLD_INSERT_LIBRARIES` interpose** —— 寫一個小 dylib，用 `__DATA,__interpose` 攔 `CC_SHA256_Update`，把 `len<=64` 的呼叫連同 hexdump 寫到檔案，再轉呼叫原函式。因為是 dynamic symbol，interpose 一定會生效。
   - **frida `Interceptor.attach(Module.findExportByName("libSystem.B.dylib","CC_SHA256_Update"), ...)`** —— 同樣的效果，但不必自己編 dylib。
3. 指向我們自己的 realm 跑一次登入（走到 `CMSG_AUTH_SESSION` 就夠，不需要登入成功）。
4. 在 dump 裡找那組 40+16 或單獨的 16 bytes。**用已知的 session key 交叉驗證**：server 端這時已經知道 session key，拿它去比對 dump 裡的 40 bytes，對上了就確定後面 16 bytes 是 seed。
5. 把值寫進 DB，重跑登入驗證。

**為什麼這條最好**：完全繞過 Arxan / 反組譯 / arm64 pattern 三個難點，只需要一次成功的握手；而且驗證迴路是閉合的（拿到值當場就能測）。

### 4.5 Windows vs macOS 難度對照

| 面向 | Windows (`WowClassic.exe`) | macOS arm64（本機實測） |
|---|---|---|
| 磁碟上加密 | `.text` 被 Arxan TransformIT 加密（`wow-patcher` 明載） | **無 `LC_ENCRYPTION_INFO`**；data 段確定明文；`__TEXT.__text` 是否另有保護 **未驗證** |
| 取得明文 code | 需 launch-suspended → 等 TLS callback 解密 → `dump-text`（工具已存在，Windows-only） | 可能直接靜態可讀 |
| 加密函式庫 | **未驗證**（公開資料未載） | **CommonCrypto dynamic symbol，可 hook** ★ |
| HMAC | — | **無 `CCHmac`，自己刻的** → 要 hook `CC_SHA256_Update` 而非 `CCHmac` |
| 注入阻力 | 需對抗 Arxan 完整性檢查 | hardened runtime，但**我們控制簽章**，可加 `get-task-allow` |
| 現成工具 | Arctium launcher、`wow-patcher`（均 Windows-only） | **沒有任何現成工具** |

**結論：靜態分析 macOS 比 Windows 容易（沒加密），runtime hook 更是壓倒性容易（CommonCrypto 是 dynamic symbol）；唯一劣勢是完全沒有現成工具，pattern 要自己寫。**

---

## 5. 明確找不到的東西（負面結論，同樣重要）

- **任何 3.4.x build 的 macOS auth seed**（x64 或 A64），任何來源。
- **任何公開的 macOS / arm64 auth-seed 抽取腳本**（IDA / Ghidra / frida / lldb 皆無）。
- **任何關於 seed 在函式內以何種形式儲存的說明**（立即數 / XOR / 查表）。
- **任何 macOS 端 Arxan 存在與否的確認。**
- **TrinityCore 維護者每個 build 發 Mac/A64 key 的取得方法**——248 筆值全部公開，**方法零記錄**。
- GitLab / Gitee / Codeberg / 中俄社群：本次以 GitHub code search + 針對性 raw 取檔為主，**未對非 GitHub 平台做窮盡搜尋（未驗證）**。考慮到連 GitHub 上都只有 HermesProxy 一筆 `MacA`，別處有 3.4.3 Mac seed 的機率極低，但不能說死。

---

## 6. 建議下一步

1. **先跑 §4.4 的 `CC_SHA256_Update` hook。** 這是投入產出比最高的一步：一個小 dylib 或一段 frida script + 一次登入。成功的話今天就有答案。
2. 若 hook 被擋（hardened runtime / 完整性檢查），退到 **§4.3 的 static-seed patch**，但要先用 §4.2 找到 seed function 入口 —— 這需要先裝一個反組譯器（本機目前只有 `objdump`）。
3. 無論走哪條，拿到值以後**寫成 `sql/updates/auth/wotlk_classic/` 下的一個 update 檔**，格式比照 `haphert` 那筆，並在本 repo 註記來源與方法 —— **因為公開世界目前沒有這個值，我們挖到就是第一手。**
4. 順帶把 §2 那兩筆 1.14.x `MacA` 值留檔：若日後要驗證抽取流程是否正確，可以拿 1.14.2 client 當**已知答案的對照組**跑一次 hook，先確認方法本身可行再對 54261 下手。**這是最穩的除錯路徑。**
