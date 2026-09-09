# WoW client 的 per-build 16-byte auth key —— client 到底怎麼存、emu 開發者怎麼挖出來

> 撰寫日期：2026-09-06
> 相關筆記：[Mac ARM auth seed 有沒有公開值、怎麼挖](./mac-arm-auth-seed.md)（Mac/A64 專篇；本篇把它的結論一般化到「所有平台的 per-build key 機制」）、[Mac ARM auth seed 靜態抽取實作與結論](./mac-arm-auth-seed-extraction.md)（證實磁碟 `__text` 熵值 8.000）、[WoW client 逆向公開資源盤點](./wow-client-re-resources.md)（工具/writeup 存在性）、[wow-patcher runtime 模式](./wow-patcher-runtime-mode.md)（Windows 端 Arxan `.text` 加密的旁證）
> **本篇回答的五個問題（見文末逐條裁決）：**（1）現代 client 把這把 key 存在哪、明文常數／加密 blob／runtime 產生？（2）emu 開發者拿到新 build key 的**實際方法**（工具/repo/技術）？（3）同一 build+type 下，各 (platform,arch) 的 key 是同一把還是各自不同？（4）client 儲存形式與最終 16-byte key 之間有沒有已知 transform（能不能拿已知 Windows key 當 oracle 定位）？（5）macOS ARM64 加殼 client 有沒有公開 unpack/dump writeup、key 在哪浮現？
> 來源限定 primary sources：本 repo **唯讀** git（含 `origin/master` / `origin/wotlk_classic` / `origin/cata_classic`）、`gh api` / `gh search` 取得的一手原始碼、raw 原始檔、WebSearch/WebFetch 取得的 repo README 與論壇串。凡未實證者標「**未驗證**」，凡屬分析／推論者明白標示。未使用瀏覽器自動化。未記錄任何 client 下載點。

---

## 0. TL;DR —— 一句話回答

**這把 key 在 client 裡不是明文常數，而是「一個 per-build 函式在 runtime 寫進 caller buffer 的 16 bytes」；那個函式住在加殼／自解密的 code 段（Windows Arxan、macOS 熵值 8.000 的 `__text`）裡。所以 raw byte scan 找不到，唯一可行的抽取法是「先讓 client 自己在記憶體裡解密，再對解密後的 code 動手」。**

五點裁決（詳見 §6）：

1. **儲存形式：runtime 產生，非明文常數、非可掃描 blob。** 三個獨立一手證據互相印證（§1）。
2. **實際方法：公開世界幾乎沒有人「讀真值」，主流是 Arctium 的 static-seed patch（把函式換成回傳 client RSA modulus 的 16 bytes，得固定值 `179D3DC3235629D07113A9B3867F97A7`）。** 要拿 Blizzard 真值只能 runtime dump（§2、§5）。**TrinityCore 上游那 248 把公開 key 的取得方法零記錄。**
3. **per-(platform,arch,type)：genuinely 各自不同。** build 56421 一次 7 把，兩兩皆異（§3，硬證據）。
4. **transform：最終 key = 函式 raw 輸出，client 裡不存明文，故已知 Windows key `25FD8124…` 無法當 byte-scan oracle。** 唯一有文件的 transform 是 static-seed 那條（key = RSA modulus 前 16 bytes），但那是 patch 後的替身值，不是真 key（§4）。
5. **macOS ARM64：有通用 unpacker（namreeb dumper 支援 FAT Mach-O x86_64/arm64）與專門討論串（ownedcore "arm-mah-gerd"），但沒有任何公開 writeup 展示 key 在 macOS 上浮現。** ownedcore 目前 Cloudflare 擋 WebFetch，只能引用搜尋摘要（§5）。

---

## 1. client 把 key 存在哪 —— runtime 產生的函式輸出，不是常數

三條互相獨立的一手證據，共同指向「**per-build key 是一個函式的輸出，不是資料段裡的常數**」。

### 1.1 反面證據：raw scan 找不到（既定前提）

既定前提已測：`25FD812475DCF26F9F1383AED37FC99E` 在 `WowClassic.exe` 裡以 raw、byte-reversed、單/多-byte XOR mask 全部掃過，**零命中**；在 macOS 兩個 slice 也 NOT FOUND（[mac-arm-auth-seed.md](./mac-arm-auth-seed.md) §3.3）。對照之下，四個**共用** HMAC 種子常數（AuthCheckSeed 等）卻是明文相鄰躺在 `__TEXT,__const`（[extraction 篇](./mac-arm-auth-seed-extraction.md) §2.2）。**「共用常數是明文、per-build key 卻掃不到」這個落差本身就是證據**：per-build key 走的是另一條路。

### 1.2 正面證據：Arctium/wow-patcher 的 anchor 指向一個「函式」，不是一塊資料

emu 世界定位這把 key 的**唯一公開 anchor**是 build-type FourCC `"WoW\0"` 緊接一個 `call`。兩個一手來源逐字一致：

- **Arctium（現行家 `ModernWoWTools/Launcher`），`src/Patterns/Windows.cs:22-23`**（`gh api` 實抓 base64 解碼）：
  ```csharp
  // Auth seed function.
  public static short[] AuthSeed = { 0x57, 0x6F, 0x57, 0x00, 0xE8, -1, -1, -1, -1, 0x48, 0x8D };
  ```
  即 ASCII `"WoW\0"` + `E8 rel32`（`call`）+ `48 8D`（`lea`）。註解直接寫 **"Auth seed function"** —— anchor 指的是**函式**。

- **`wowemulation-dev/wow-patcher`，`src/patterns/runtime/windows.rs`**（raw 實抓）：
  ```rust
  /// Auth-seed function entry. The string `"WoW\0"` followed by a
  /// `call` instruction is the canonical anchor.
  /// Used by the static-auth-seed feature (planned, not yet ported).
  pub fn auth_seed_pattern() -> Pattern {
      vec![0x57, 0x6F, 0x57, 0x00, 0xE8, WC, WC, WC, WC, 0x48, 0x8D]
  }
  ```
  註解明寫 **"Auth-seed function entry … canonical anchor"**，且用途是 **static-auth-seed feature**。同檔頂註還記錄此 pattern 針對 **recent retail `Wow.exe`；Classic 1.13.x / 2.5.x / 3.4.x / 4.4.x 可能要 build-specific 變體**。

### 1.3 決定性證據：Arctium 的替換函式洩漏了 ABI —— 16 bytes 寫進 `rdx` buffer

Arctium 不去讀 key，而是把那個函式**整個換掉**。`src/Patches/Windows.cs:14`（實抓）：

```csharp
public static byte[] AuthSeed = { 0x0F, 0x28, 0x05, 0xEF, 0xBE, 0xAD, 0xDE, 0x0F, 0x11, 0x02, 0xC3 };
```

反組譯：`0F 28 05 <rel32>` = `movaps xmm0, [rip+disp32]`；`0F 11 02` = `movups [rdx], xmm0`；`C3` = `ret`。**這證明 x64 ABI 下，get-seed 函式的契約就是「把 16 bytes 寫進 `rdx` 指向的 buffer」。** 值是被函式「產出」的，不是躺在資料段——這正好解釋 §1.1 為什麼掃不到。

`src/Launcher.cs:419-436`（實抓）顯示要穿兩層 indirection 才會到真正的函式：

```csharp
var authSeedLoadOffset  = memory.Data.FindPattern(Patterns.Windows.AuthSeed);   // "WoW\0"+call+lea
var leaStartOffset      = authSeedLoadOffset + 9;
var leaValue            = Unsafe.ReadUnaligned<int>(ref memory.Data[leaStartOffset + 3]);
var authSeedWrapperOffset = leaStartOffset + leaValue + 7;                        // → wrapper
var jmpValue            = Unsafe.ReadUnaligned<uint>(ref memory.Data[authSeedWrapperOffset + 6]);
var authSeedFunctionOffset = authSeedWrapperOffset + 5 + jmpValue + 5;            // → 真正的 get-seed 函式
```

`"WoW\0"` → `call` → `lea`(rel32) → wrapper → `jmp`(rel32) → 真正的 get-seed function。

> **函式內部那 16 bytes 究竟是 `mov`/`movk` 立即數拼出來、XOR 白化、還是查表 —— 公開世界零記錄（未驗證/speculative）。** 但因為它在 Windows 上被 Arxan 加密、macOS 上在熵值 8.000 的 `__text` 裡（[extraction 篇](./mac-arm-auth-seed-extraction.md) §2.1），「raw scan 掃不到」不需要額外的混淆假設就能解釋。

### 1.4 macOS 上這個函式在密文裡

[extraction 篇](./mac-arm-auth-seed-extraction.md) §2 實測：macOS arm64 slice 的 `__TEXT,__text`（file off `0x195c`、size `0x1ca81bc`≈30 MB）熵值 = **8.000**，`otool -tV` 反出的是不可能的指令流；有 `__INIT1`/`__INITC`/`__mod_init_func` 這組**載入時就地解密 `__text` 的 bootstrap**，且**無 `LC_ENCRYPTION_INFO`**（不是 FairPlay，是應用層加殼）。**所以 §1.2 的 `"WoW\0"` anchor 與 §1.3 的函式，在磁碟上都在密文裡，靜態追不到（[extraction 篇](./mac-arm-auth-seed-extraction.md) §2.3 實測 xref 不存在可解析形式）。**

---

## 2. 拿到新 build key 的實際方法 —— 兩條路，主流是「不挖真值」

### 2.1 ★ 主流路線：static auth seed patch（Arctium）——「不挖、改成回傳一個固定值」

**這是公開世界實際在用的路，不是「讀真值」。** `src/Launcher.cs:319-330`（實抓）：

```csharp
if (commandLineResult.HasOption(LaunchOptions.UseStaticAuthSeed))   // --staticseed
{
    Console.WriteLine("Static auth seed used. Be sure that the server you are connecting to supports it.");
    // Generates a patch for the auth seed so we don't have to update them on each build.
    var authSeedFunctionOffset = GenerateAuthSeedFunctionPatch(memory, modulusOffset);
    ...QueuePatch(authSeedFunctionOffset, Patches.Windows.AuthSeed, "CustomAuthSeedFunction")
}
```

**關鍵細節（比既定前提多一層，且是本篇最有價值的發現）：這個「固定值」不是憑空的常數，而是 client 自己的 RSA modulus 的前 16 bytes。** `src/Launcher.cs:248-249, 419-436`（實抓）：

```csharp
// We need to cache this here since we are using our RSA modulus as auth seed.
var modulusOffset = memory.Data.FindPattern(Patterns.Common.SignatureModulus);
...
// Write the modulus offset to our custom get seed functions.
// Resulting static auth seed is: 179D3DC3235629D07113A9B3867F97A7
Unsafe.WriteUnaligned(ref Patches.Windows.AuthSeed[3], (uint)(modulusOffset - authSeedFunctionOffset - 7));
```

`Patterns.Common.SignatureModulus`（`src/Patterns/Common.cs:9`，實抓）= `{ 0x35, 0xFF, 0x17, 0xE7, 0x33, 0xC4, 0xD3, 0xD4 }` —— 這是「定位 client 內建 RSA 簽章 modulus」的 anchor。§1.3 那個替換函式的 `movaps xmm0,[rip+disp32]` 的 `disp32` 就被改寫成指向這個 modulus，於是函式改成「把 modulus 前 16 bytes 複製到 `[rdx]`」。**因為 RSA modulus 是 build-independent 的內建常數，所以這個「seed」跨 build 固定 = `179D3DC3235629D07113A9B3867F97A7`**，server 端只要一次性把這個值塞進 DB 即可（見下）。

**多個一手來源交叉佐證這個值與用法**（`gh search code` 實查）：
- `ModernWoWTools/Launcher:src/Launcher.cs` → `// Resulting static auth seed is: 179D3DC3235629D07113A9B3867F97A7`
- `ModernWoWTools/Launcher:README_OLD.md` 與 `huahuacn/…:README.md` → *"On server side add `179D3DC3235629D07113A9B3867F97A7` as auth seed in the database."*
- `advocaite/HermesProxy-WOTLK:HermesProxy.config` → `<add key="ClientSeed" value="179D3DC3235629D07113A9B3867F97A7" />`（default `(static)`）

`LaunchOptions.cs:17`（實抓）：`public static Option<bool> UseStaticAuthSeed = new("--staticseed");`。

> **對本 repo 的實務意義：** 這條路對「讓 client 能登入」是充分的——不需要 Blizzard 真 key，只要 server 認得 `179D3DC3…`。但**它是 Windows-only patch generator**（`Patterns.Windows`/`Patches.Windows`），macOS/arm64 沒有現成版本（[mac-arm-auth-seed.md](./mac-arm-auth-seed.md) §4.3）。且本 repo 跑的 `TDB343.24081` server 未必內建這個值，要自己插一列。

### 2.2 Arctium 怎麼對付加殼：launch → 等 client 自己解密 → 掃記憶體 patch（不是靜態）

這回答了「為什麼能繞過 Arxan」。Arctium **不碰磁碟上的密文**，而是操作**啟動後的 process 記憶體**：`src/Launcher.cs:439-461` 的 `WaitForUnpack`（實抓）先輪詢一個 `Init` pattern（`Patterns.Windows.Init`），確認 **client 自己的 bootstrap 已把 code 在記憶體裡解密**後，才對**解密後的記憶體**做 `FindPattern` 定位 §1.2 的 anchor 並下 patch：

```csharp
// Wait for client initialization.
var initOffset = memory.Read(...)?.FindPattern(Patterns.Windows.Init) ?? 0;
while (initOffset == 0) { ... Console.WriteLine("Waiting for client initialization..."); }
```

**這就是通用打法：「讓 packer 自己解密，再從記憶體抓」**——Windows 靠 PE 的 TLS callback（[wow-patcher 篇](./wow-patcher-runtime-mode.md)），macOS 靠 `__mod_init_func`（[extraction 篇](./mac-arm-auth-seed-extraction.md) §2.5）。同源，只差平台。

### 2.3 若要「讀真值」：runtime dump/hook（無現成工具，需開荒）

要拿 Blizzard **真** per-build key（而非 static 替身），公開世界**沒有逐步 writeup、沒有現成 extractor**（[wow-client-re-resources.md](./wow-client-re-resources.md) §4 負面結論）。可行方向皆為 runtime：

1. **對解密後記憶體做 §2.2 的 anchor 追蹤到 get-seed 函式，直接 `call` 它、讀回 `[rdx]` 的 16 bytes**（分析，未見公開實作）。
2. **hook client 的雜湊輸入**：macOS client 用 dynamic symbol `_CC_SHA256_Update`，一次登入即可 dump 到 `sessionKey ‖ seed`，末 16 bytes 就是答案（[mac-arm-auth-seed.md](./mac-arm-auth-seed.md) §4.4，**建議路線**，本機未實跑）。
3. **通用 unpacker 先把解密後 image dump 成檔，再靜態分析**（§5 的 namreeb dumper / [wow-client-re-resources.md](./wow-client-re-resources.md) §1 的 Timac destructor / lldb `process save-core`）。

> **TrinityCore 上游那 248 把 Mac/A64 + 各平台 key 是怎麼來的？零記錄。** commit message 一律只寫 "Add auth keys for … build N"（例：Shauren `05fdb6a82a` "Core: Add auth keys for all types for build 11.0.2.56421"；`b50b32a1d7` "DB: Add Mac and ARM auth keys for 4.4.0.56489"，本 repo `git log` 實查）。**方法從未公開**——合理推論是維護者用上述 runtime 手段跑真函式取真值（推論，未驗證）。

### 2.4 工具/repo 清單（一手）

| repo / 工具 | 平台 | 對 key 的角色 |
|---|---|---|
| **`ModernWoWTools/Launcher`**（Arctium 現行家） | Windows | ★ 定位 get-seed 函式的 anchor（§1.2）；`--staticseed` 把它換成回傳 RSA modulus（§2.1）。**patch generator Windows-only。** |
| **`wowemulation-dev/wow-patcher`** | Windows | 同一 anchor 的 Rust 移植 + 文件（§1.2）；runtime 解密 `.text`（TLS callback）。 |
| **`namreeb/dumper`**（ownedcore 稱之，見 §5） | Windows + macOS FAT | 通用 unpacker，吃 WoW 執行檔、dump 解密後 image；ownedcore 摘要稱支援 FAT Mach-O（x86_64/arm64）。**repo 於 `gh api repos/namreeb/dumper` 目前回 404（可能已改名/下架，未驗證）。** |
| **`namreeb/wowreeb`** | Windows | 多版本 launcher（`gh api` 實查 description）。 |
| **`WowLegacyCore/HermesProxy`** | — | `CSV/BuildAuthSeeds.csv` 是唯一公開列出 `MacA` seed 之處（別的資料片，[mac-arm-auth-seed.md](./mac-arm-auth-seed.md) §2）；`ClientSeed` 預設即 static `179D3DC3…`。 |
| **`agatho/ida-wow-analyzer`** | IDA | ~80 analyzer，但**無 auth-seed extractor**（[wow-client-re-resources.md](./wow-client-re-resources.md) §3）。 |

---

## 3. 同一 build+type，各 (platform,arch) 的 key —— genuinely 各自不同（硬證據）

**是各自不同的，不是同一把。** `origin/master` 的 `sql/base/auth_database.sql`，build 56421 一次七把（`git show` + grep 實抓，逐字）：

```
(56421,'Mac','A64','WoW', 0x5892FFABAEFDCECB0CFFAAA55D2F9B13)
(56421,'Mac','A64','WoWC',0x629666D6D9EFFE4B73C1EDD74638DEAA)
(56421,'Mac','x64','WoW', 0x4F0FCD1113F783C484BF45C98327DE62)
(56421,'Mac','x64','WoWC',0x4B61E4F4F3B220FF5B48A6988F0FFB42)
(56421,'Win','A64','WoW', 0x178888C71560707CC9C1C1D6B45B4838)
(56421,'Win','x64','WoW', 0x3BDFA9AA4B70041F2C8B8CDE3C8DC255)
(56421,'Win','x64','WoWC',0x0DDB8F8738647F3CD8FD585A3A78ED1B)
```

**七個值兩兩皆異。** 同 type（`WoW`）跨平台/架構比較：`Mac/A64 = 5892FFAB…`、`Mac/x64 = 4F0FCD11…`、`Win/A64 = 178888C7…`、`Win/x64 = 3BDFA9AA…` —— 全不同。build 65727 的七把亦然（[mac-arm-auth-seed.md](./mac-arm-auth-seed.md) §1.1，同檔另一列，同樣兩兩皆異）。

**結論：key 是 per-(build, platform, arch, type) 四元組定址、各自獨立的值，沒有跨平台/架構的推導規律。** 這與 §1.3「client 端很可能是一張以 FourCC 為 key 的表/switch，各變體回不同 16 bytes」一致（DB schema `PRIMARY KEY (build,platform,arch,type)` 也對稱地反映這點，見 [mac-arm-auth-seed.md](./mac-arm-auth-seed.md) §1.1 的 migration SQL）。

> **實務推論：** 因此手上 Windows x64 的 `25FD8124…` **無法**推得同 build 的 Mac/A64 值——各平台要各自挖（[mac-arm-auth-seed.md](./mac-arm-auth-seed.md) §0 的整篇前提）。

---

## 4. 儲存形式 ↔ 最終 key 的 transform —— 沒有可當 oracle 的已知 transform

### 4.1 server 端怎麼消費這把 key（確立「最終 key」的角色）

`origin/master` `WorldSocket.cpp:691-703`（`git show` 實抓，master 是 SHA512 版）：

```cpp
Trinity::Crypto::SHA512 digestKeyHash;
digestKeyHash.UpdateData(account.Game.KeyData.data(), account.Game.KeyData.size());   // session key
digestKeyHash.UpdateData(clientBuildAuthKey->Key.data(), clientBuildAuthKey->Key.size()); // ← 這把 16-byte key
digestKeyHash.Finalize();
Trinity::Crypto::HMAC_SHA512 hmac(digestKeyHash.GetDigest());
hmac.UpdateData(authSession->LocalChallenge);
hmac.UpdateData(_serverChallenge);
hmac.UpdateData(AuthCheckSeed);
hmac.Finalize();
// memcmp(hmac, authSession->Digest) —— client 必須算出一模一樣的東西
```

其中 `clientBuildAuthKey` 是用 client 上報的 `(platform,arch,type)` 三元組在 `buildInfo->AuthKeys` 裡查出來的（`WorldSocket.cpp:675-682`）。key 型別 `ClientBuild::AuthKey { std::array<uint8,16> Key; }`（`ClientBuildInfo.h:99-105`，`Size = 16`）。

> **注意版本差異：** master 用 SHA512 + `std::array<uint8,32>` seed；本 repo 跑的 `TDB343.24081` tag 才是既定前提的 **SHA256 + 16-byte seed** 版（[mac-arm-auth-seed.md](./mac-arm-auth-seed.md) §1.2）。但兩者對 key 的**角色**相同：`digest = HASH(sessionKey ‖ buildAuthKey ‖ …)`，client 必須內建同一把 `buildAuthKey`。**所以 `build_auth_key` 裡那 16 bytes = client get-seed 函式的 raw 輸出**——server 存的就是 client 會產出的東西，中間沒有再套 transform。

### 4.2 因此 `25FD8124…` 不能當 byte-scan oracle

- **最終 key = §1.3 函式的 raw 輸出，client 磁碟上不存明文**（§1.1 掃不到）。所以「拿已知 Windows key 去 binary 裡 raw/reversed/XOR 掃描定位」**原理上就不會命中**（既定前提已實測零命中，本篇解釋了為什麼）。
- **唯一有文件記載的 transform 是 static-seed 那條**：patch 後 `key = client RSA signature modulus 的前 16 bytes`（§2.1），得 `179D3DC3…`。但**那是替身值，不是真 per-build key**，且它反過來說明真函式**沒有**這種簡單 transform（否則 Arctium 直接算真值就好，不必整個換函式）。
- **能當 oracle 的唯一場景是 runtime**：拿已知 `25FD8124…` 去驗證你「call 真函式／hook 雜湊」dump 出來的東西對不對（[mac-arm-auth-seed.md](./mac-arm-auth-seed.md) §4.4 的閉環驗證），或拿 server 已知 session key 反查 dump 裡的 40-byte 段。**這是「驗證 oracle」，不是「定位 oracle」。**

**結論：不存在能用 `25FD8124…` 在 binary 裡定位 key 的已知 transform。**（未驗證是否存在私有/未公開 transform，但無任何一手資料指向它。）

---

## 5. macOS ARM64 加殼 client 的 unpack/dump —— 工具在、writeup 缺、key 未見浮現

### 5.1 專門討論串與通用工具（一手，但 ownedcore 被 Cloudflare 擋）

- **ownedcore "arm-mah-gerd (macOS since 10.2.6 53989)"**（`.../wow-memory-editing/1010261-…`）：WebSearch 摘要稱這是「討論把 WoW 工具移植到 macOS/ARM、含 pattern 轉換」的串。**WebFetch 實測回 HTTP 403（Cloudflare），無法取全文逐字引用（未驗證細節）。** 這是目前找到最貼近「Apple Silicon WoW RE」的專門串。
- **ownedcore "How to Dump Wow from Memory…"**（`.../640683-…`）與 **"[Release][Classic] WoW unpacker / deobfuscator"**（`.../886094-…`）：WebSearch 摘要稱 **namreeb 的 dumper 是通用 unpacker，吃 WoW 執行檔路徑、在同目錄產出 `<name>_dumped.exe`；並提到從 Universal Binary（FAT Mach-O，x86_64 / arm64）抽 slice、dump 解密後版本。** 同樣因 403 無法取原文（未驗證逐字）。
- **namreeb 的相關 repo（`gh api users/namreeb/repos` 實查）**：`wowreeb`（multi-versioned launcher）、`wowned`（auth **bypass** PoC，針對 1.12.1/2.4.3/3.3.5a 舊 auth server 漏洞，與 per-build key 無關）、`hots-unpack`、`WowPacketSniff`。**`namreeb/dumper` 本身 `gh api` 回 404**（可能改名/下架/移轉，未驗證）。

### 5.2 可移植的 macOS dump 手法（一手，[wow-client-re-resources.md](./wow-client-re-resources.md) 已詳列）

macOS 這顆的 `__text` 是自解密（無 FairPlay `cryptid`），所以要「等 `__mod_init_func` 解完再從記憶體抓」：
- **Timac `DYLD_INSERT_LIBRARIES` + destructor**：在 app 收尾時把記憶體裡已解密的 `__TEXT,__text` memcpy 回檔案、清零 `__mod_init_func`。原文限 64-bit **Intel**，arm64 要自補（[wow-client-re-resources.md](./wow-client-re-resources.md) §1.1）。
- **lldb `process save-core`（skinny corefile）** / **frida / fridump**（同篇 §1.2/§1.3）。
- 前置：hardened runtime 下重簽加 `get-task-allow` + `disable-library-validation`（同篇 §1.4；我們控制 ad-hoc 簽章）。

### 5.3 明確的負面結論

- **沒有任何公開 writeup／repo／論壇串展示「per-build key 在 macOS（x64 或 arm64）上被實際 dump 出來」**——不分 3.4.x 或 retail（[mac-arm-auth-seed.md](./mac-arm-auth-seed.md) §5、[wow-client-re-resources.md](./wow-client-re-resources.md) §4/§5 一致）。
- **沒有 macOS/arm64 版的 seed extractor 或 static-seed patch generator**（Arctium/wow-patcher 皆 Windows-only）。
- **key 在 macOS 上「浮現」的地方是 runtime**（解密後 `__text` 的函式輸出、或 `_CC_SHA256_Update` 的輸入），**不是磁碟上的任何 section**（[extraction 篇](./mac-arm-auth-seed-extraction.md) §4 實證磁碟推不出任何 byte）。

---

## 6. 五問逐條裁決

| # | 問題 | 裁決 | 信心 |
|---|---|---|---|
| 1 | client 把 key 存哪？明文/加密/runtime？ | **runtime 產生**：per-build 函式把 16 bytes 寫進 caller buffer（x64 = `[rdx]`）；函式住在加殼/自解密 code 段。非明文常數、非可掃描 blob。 | **confirmed**（§1，三獨立一手證據）。函式內部形式（立即數/XOR/表）**speculative**。 |
| 2 | 拿新 build key 的實際方法？ | **主流 = 不挖真值**：Arctium `--staticseed`，把 get-seed 函式換成回傳 client RSA modulus（`179D3DC3…`），server 塞同值。**挖真值 = runtime dump/hook，無現成工具、需開荒。** anchor = `"WoW\0"`+`call`。 | **confirmed**（§2，Arctium/wow-patcher 原始碼 + 多 repo 交叉）。「上游 248 把怎麼來的」**零記錄**。 |
| 3 | 各 (platform,arch) 同一把還是各自？ | **genuinely 各自不同。** build 56421 七把兩兩皆異；無跨平台推導規律。 | **confirmed**（§3，`auth_database.sql` 實抓）。 |
| 4 | 儲存形式 ↔ 最終 key 的 transform？能當 oracle？ | 最終 key = 函式 raw 輸出，client 不存明文 → **`25FD8124…` 無法當 byte-scan oracle**。唯一有文件的 transform 是 static-seed（key = RSA modulus 前 16B），但那是替身值。只能當 **runtime 驗證 oracle**。 | **confirmed 負面**（§4，server digest 邏輯 + 既定掃描結果）。「有無私有 transform」**未驗證**。 |
| 5 | macOS ARM64 有無 unpack/dump writeup，key 在哪浮現？ | 有通用 unpacker（namreeb dumper，稱支援 FAT Mach-O）與專門串（ownedcore "arm-mah-gerd"），**但無任何公開 writeup 展示 key 浮現**；key 只在 runtime（解密後 `__text` 函式輸出 / `CC_SHA256_Update` 輸入）出現。 | ownedcore 內容 **未驗證**（Cloudflare 403，僅搜尋摘要）；「無公開 key writeup」**confirmed 負面**。 |

---

## 7. 對本 repo 的收斂建議

1. **要「能登入」**：不需要 Blizzard 真 key。走 static-seed 等價路——但因 patch generator 是 Windows-only，macOS/arm64 上更省的做法是 [mac-arm-auth-seed.md](./mac-arm-auth-seed.md) §4.4 的繞過/hook 路線（只動 server 或一次登入 hook）。
2. **要「存真值 54261 Mac/A64」（開荒）**：先跑 §2.3 / [mac-arm-auth-seed.md](./mac-arm-auth-seed.md) §4.4 的 `CC_SHA256_Update` hook，用 server 已知 session key 閉環驗證；拿到後比照 `haphert` 那筆寫進 `sql/updates/auth/wotlk_classic/`，並在本 repo 記來源與方法——**公開世界沒有這個值，挖到即第一手。**
3. **驗證流程正確性**：可先拿已知答案當對照組——Windows 用 `25FD8124…`、Mac 用 HermesProxy 那筆 1.14.2 build 42597 `MacA = 3B31A4F4C25382131A8FB95A1317412B`（[mac-arm-auth-seed.md](./mac-arm-auth-seed.md) §2），先確認「hook/dump→比對」的方法本身可行，再對 54261 下手。

---

## 8. 來源清單（本篇實際引用者）

**本 repo git（唯讀實查）：**
- `origin/master:src/server/shared/Realm/ClientBuildInfo.h:34-105`（FourCC 定義、`AuthKey{Size=16}` 結構）
- `origin/master:src/server/game/Server/WorldSocket.cpp:670-703`（key 查表 + digest 消費）
- `origin/master:sql/base/auth_database.sql`（build 56421 七把 key）
- commit `f80a05f805`（"Core: Update allowed build to 3.4.3.54261"，含 `win64AuthSeed='25FD8124…'`）、`2b8c5ad42d`/`8e15952659`（auth key storage refactor）、`05fdb6a82a`、`b50b32a1d7`（"Add auth keys …" 系列，方法零記錄）

**Arctium / wow-patcher（`gh api`/raw 實抓）：**
- `ModernWoWTools/Launcher`：`src/Patterns/Windows.cs:22-23`（AuthSeed anchor）、`src/Patches/Windows.cs:14`（替換函式 ABI）、`src/Patterns/Common.cs:9`（SignatureModulus anchor）、`src/Launcher.cs:248-249,319-330,419-436,439-461`（static-seed 產生 + WaitForUnpack）、`src/LaunchOptions.cs:17`（`--staticseed`）
- `wowemulation-dev/wow-patcher`：`src/patterns/runtime/windows.rs`（`auth_seed_pattern` 註解 "canonical anchor"）
- `gh search code "179D3DC3235629D07113A9B3867F97A7"`：`ModernWoWTools/Launcher`、`huahuacn/…`、`advocaite/HermesProxy-WOTLK`、`Novivy/HermesProxy` 等交叉佐證

**namreeb / 論壇（`gh api` + WebSearch；ownedcore WebFetch 403）：**
- `gh api users/namreeb/repos`（`wowreeb` / `wowned` / `hots-unpack` / `WowPacketSniff`）；`namreeb/wowned` README（auth **bypass** PoC，非 key 抽取）
- ownedcore threads（**Cloudflare 403，僅搜尋摘要**）："How to Dump Wow from Memory…"（`640683`）、"[Release][Classic] WoW unpacker / deobfuscator"（`886094`）、"arm-mah-gerd (macOS since 10.2.6 53989)"（`1010261`）

**姊妹篇（本 repo）：** [mac-arm-auth-seed.md](./mac-arm-auth-seed.md)、[mac-arm-auth-seed-extraction.md](./mac-arm-auth-seed-extraction.md)、[wow-client-re-resources.md](./wow-client-re-resources.md)、[wow-patcher-runtime-mode.md](./wow-patcher-runtime-mode.md)
</content>
</invoke>
