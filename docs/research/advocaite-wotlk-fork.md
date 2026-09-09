# `advocaite/HermesProxy-WOTLK` 逐位元比對：它能不能解掉我們的 `reason 24`？

> 撰寫日期：2026-09-04
> 相關筆記：[`Xian55/HermesProxy` 決策級評估](./hermesproxy-evaluation.md)（本篇的母文件）、[RaGEZONE 論壇調查](./community-forum-findings.md)（此 repo 首次出現的地方）、[macOS client 取得與執行](./macos-client-options.md)、[client 設定與憑證](./tc-client-setup-and-certs.md)
> 來源限定 primary sources：`gh api` 對 `advocaite/HermesProxy-WOTLK` 的 repo metadata / branches / releases / issues / commits，`git clone --depth 1` 的完整原始碼樹（放在 scratchpad，未進入使用者專案目錄），以及本機 `~/Works/side-project/wotlk-stack/hermesproxy`（branch `feature/wotlk-classic-v3.4.3`）的 `AuthenticationPackets.cs` / `WorldSocket.cs` / `ShaHmac.cs`。全部於 2026-09-04 實測。
> 凡未實際驗證者一律標示「**未驗證**」。未使用瀏覽器自動化，未修改任何 tracked 檔案。

---

## 0. TL;DR — 先回答那個問題

**在 encrypted-mode 這條路徑上，兩邊沒有任何一個位元組不同。** Ed25519 私鑰 32 bytes、Ed25519 context 16 bytes、`EnableEncryptionSeed` 16 bytes、HMAC 構造、簽章輸入、封包欄位順序、version gate —— **逐一比對，全部相同**。連 `WorldSocket.cs` 的 `AuthCheckSeed` / `SessionKeySeed` / `ContinuedSessionSeed` / `EncryptionKeySeed` 四個 seed 與 `_encryptKey` 推導的 HMAC 呼叫順序也完全相同。**這個 repo 不含任何可以直接修掉 `reason 24` 的常數或版面差異。這是一個乾淨的否定結果。**

**但這趟不是空手而回，有三個實質收穫：**

1. **一個被留在原始碼裡、從未被呼叫的死常數**：`EnableEncryptionSeedEd25519`（32 bytes，`66 BE 29 79 …`）。它與 repo 內另一份參考檔 `tmp_certs/tc_auth.cpp`（**TrinityCore master 的 `AuthenticationPackets.cpp`**）中的 `EnableEncryptionSeed` **完全相同**。TC master 的正解是 **HMAC-SHA512 + 這個 32-byte seed + 封包開頭多一個 `int32 RegionGroup`**；`advocaite` 與 `Xian55` 兩邊實際送出的都是 **HMAC-SHA256 + 16-byte 舊 seed + 沒有 RegionGroup**。→ **這是目前唯一一條有原始碼證據支撐的替代構造假設**（詳見 §2.4，並附明確的但書：TC master 那段是 retail/3.4.4+ 的程式碼，**未驗證**是否適用於 3.4.3.54261）。
2. **repo 內附的 WowPacketParser 快照 `tmp_certs/wpp_auth_343.cs` 把 Ed25519 版本的 `SMSG_ENTER_ENCRYPTED_MODE` parser gate 在 `ClientVersionBuild.V3_4_4_59817`**，而不是 3.4.3。字面上這暗示 Ed25519 是 3.4.4 才進來的（3.4.3 仍是 RSA）。但**這與實測證據矛盾**：`advocaite` 的使用者確實用這份 Ed25519 程式碼在 3.4.3.54261 上登入成功並進到世界（issue #11）。兩者的張力見 §2.5。
3. **launcher 與設定面的社群實務**：README 指定的仍是 Arctium `--staticseed --version=Classic`（與 `Xian55` 相同），而且 README 自己寫「For WOLTK you will need a updated version repo yet to be added.」—— **它沒有提供任何我們拿得到的替代 launcher**。不過 issue #3 有一條對我們有直接意義的社群回報：**「for older CPU's Arctium Launcher can be emulated through Intel SDE」**（見 §4.2）—— 這是我們「required instruction sets are not supported by the current CPU」的同一類問題。

---

## 1. Repo 事實（`gh api` 實測）

| 欄位 | 值 |
|---|---|
| `full_name` | `advocaite/HermesProxy-WOTLK` |
| `fork` | **`false`**；`parent` = `null`、`source` = `null` → **不是 GitHub fork，是另開的 code snapshot repo**（複驗前一篇筆記的結論，**成立**） |
| License | GPL-3.0 |
| 語言 | C# |
| default branch | `master`（另有 `main`，共 2 條分支） |
| ★ / fork 數 | 43 / 17 |
| 建立 / 最後 push | 2026-04-03 / **2026-05-20**（停滯 3.5 個月，複驗**成立**） |
| 最後 commit | `765681a9dc086094afb373a52fae8c0e3ceef627` — `Merge pull request #12 from DrUlysses/master`（2026-05-20 20:51 +0800） |
| commit 總數 | **53**（`Link` header 的 `rel="last"` page=53，per_page=1） |
| 貢獻者 | `advocaite` 42、`DrUlysses` 10、`Co0lDoge` 1 |
| open issues | 15（含 PR 則 API 回報 15） |
| issue / PR 全表 | **22 筆**：18 個 issue（**14 open / 4 closed**）+ 4 個 PR（**全部 closed**，其中 #1/#9/#12/#15 已合併路徑） |
| releases | **11 個**，全部是 `build-YYYYMMDD-HHMMSS` 形式的 CI 產物，最後一個 `build-20260520-125346` |
| release assets | 每個 release 六個檔：**`HermesProxy-macos-universal-{Debug,Release}.zip`**、`HermesProxy-ubuntu-*.tar.gz`、`HermesProxy-windows-*.zip` |

**→ 它確實有 macOS universal 產物**（與 `Xian55` 同型），但 repo 已停在 2026-05-20，`Xian55` 在那之後又疊了數百個 commit。

### 1.1 一個影響「可信度」判讀的觀察（推論，證據強）

這份 code snapshot **看起來是反編譯（decompile）出來的，不是原始碼**：全檔案 `this.` 前綴、`new byte[16] { 144, 156, … }` 這種**十進位**常數陣列、`enabled: true` 具名引數、以及 `Log.Print(...)` 被展開成三個位置引數（原始碼裡那兩個是 `[CallerMemberName]` / `[CallerFilePath]`）。

**決定性的一條**：`HermesProxy/World/Server/Packets/EnterEncryptedMode.cs` 裡的 log 呼叫，第三個引數字面值是 `"Packets\\AuthenticationPackets.cs"` —— **檔案自己承認它原本住在 `AuthenticationPackets.cs`**。也就是說這個 repo 的「一個 class 一個檔」是反編譯工具切出來的，不是作者的檔案配置。

**這對我們的意義**：`Xian55` 的註解說「Values match the advocaite/HermesProxy-WOTLK fork」—— 這句話在**位元組層級成立**（§2 驗證），但 `advocaite` 這一份本身也不是常數的原始出處，它同樣是從某個 3.4.3 伺服器實作抄來的。**真正的上游是 `tmp_certs/` 裡那份 TrinityCore `AuthenticationPackets.cpp`**（§2.4）。

---

## 2. `SMSG_ENTER_ENCRYPTED_MODE` —— 逐位元組比對（本篇核心）

比對對象：

- **A**：`advocaite/HermesProxy-WOTLK@765681a`，`HermesProxy/World/Server/Packets/EnterEncryptedMode.cs`（92 行）
- **B**：本機 `~/Works/side-project/wotlk-stack/hermesproxy`，branch `feature/wotlk-classic-v3.4.3`，`HermesProxy/World/Server/Packets/AuthenticationPackets.cs` 的 `class EnterEncryptedMode`（L463–523）

（A 用十進位、B 用十六進位，下表已換算並用 Python 逐元素比對確認。）

### 2.1 四組常數

| 常數 | A（advocaite） | B（Xian55／本機） | 結果 |
|---|---|---|---|
| Ed25519 私鑰（32 B） | `08 BD C7 A3 CC C3 4F 3F 6A 0B FF CF 31 C1 B6 97 69 1E 72 9A 0A AB 2C 77 C3 6F 8A E7 5A 9A A7 C9` | 同左 | **完全相同** |
| Ed25519 context（16 B） | `A7 1F B6 9B C9 7C DD 96 E9 BB B8 21 39 8D 5A D4` | 同左 | **完全相同** |
| `EnableEncryptionSeed`（16 B，實際被用的那個） | `90 9C D0 50 5A 2C 14 DD 5C 2C C0 64 14 F3 FE C9`（A 命名為 `EnableEncryptionSeedRSA`） | 同左（B 命名為 `EnableEncryptionSeed`） | **完全相同** |
| `EnableEncryptionSeedEd25519`（32 B） | `66 BE 29 79 EF F2 D5 B5 61 53 F6 5F 45 AE 81 CB 32 EC 94 EC 75 B3 5F 44 6A 63 43 67 17 20 44 34` | **不存在** | **A 獨有 —— 但 A 自己也沒用它**（見 §2.4） |

### 2.2 HMAC 構造與被簽的東西

**A（`WriteEd25519()`，L77–80）：**

```csharp
HmacSha256 hash = new HmacSha256(this.EncryptionKey);
hash.Process(BitConverter.GetBytes(this.Enabled), 1);
hash.Finish(EnterEncryptedMode.EnableEncryptionSeedRSA, 16);   // ← 16-byte 舊 seed
byte[] toSign = hash.Digest;
```

**B（`Write()`，L495–499）：**

```csharp
HmacSha256 hash = new(EncryptionKey);
hash.Process(BitConverter.GetBytes(Enabled), 1);
hash.Finish(EnableEncryptionSeed, 16);
byte[] toSign = hash.Digest!;
```

**→ 同一個 key、同一個 1-byte `Enabled`、同一個 16-byte seed、同一個 HMAC-SHA256。`toSign` 是 32 bytes。完全相同。**
（B 把 HMAC 提到 `Write()` 共用給 RSA/Ed25519 兩條路，A 在兩個方法裡各寫一次 —— **純重構，輸出位元組不變**。）

### 2.3 簽章與封包版面

| 項目 | A | B |
|---|---|---|
| signer | `new Ed25519ctxSigner(EnableEncryptionContext)` | `new Ed25519ctxSigner(Ed25519Context)` |
| 私鑰載入 | `new Ed25519PrivateKeyParameters(Ed25519PrivateKey, 0)` | 同左 |
| `BlockUpdate` | `(toSign, 0, toSign.Length)` | 同左 |
| 寫入順序 | `WriteBytes(signature)` → `WriteBit(Enabled)` → `FlushBits()` | 同左 |
| version gate | `if (ModernVersion.ExpansionVersion >= 3) WriteEd25519(); else WriteRSA();` | `if (ModernVersion.ExpansionVersion >= 3) WriteEd25519(toSign); else WriteRsa(toSign);` |
| RSA fallback | `RsaCrypt.RSA.SignHash(..., SHA256, Pkcs1).Reverse()` | 同左 |

**→ 線上位元組完全一致：64 bytes Ed25519 簽章 + 1 bit `Enabled` + padding。沒有 `RegionGroup`，兩邊都沒有。**

A 多的只有兩行 `Log.Print` debug 輸出（印 `toSign` 前 16 bytes 與 signature 前 16 bytes），不影響封包。

### 2.4 ★ 唯一的實質發現：那個沒被用到的 32-byte seed

A 定義了 `EnableEncryptionSeedEd25519`（32 bytes）卻**在整個 repo 裡從未被引用一次**（`grep` 全樹確認：只有宣告處）。`WriteEd25519()` 用的是 16-byte 的 `EnableEncryptionSeedRSA`。

**它從哪來？repo 自己給了答案。** `tmp_certs/tc_auth.cpp` 是一份 **TrinityCore（master／retail 線）的 `WorldPackets::Auth` 實作**（檔頭是 TC 的 GPL-2.0 header，內容含 `PacketOperators.h`、`Bits<1>` 等 retail 寫法）。其中：

```cpp
std::array<uint8, 32> constexpr EnableEncryptionSeed = { 0x66, 0xBE, 0x29, 0x79, 0xEF, 0xF2, 0xD5, 0xB5, 0x61, 0x53, 0xF6, 0x5F, 0x45, 0xAE, 0x81, 0xCB,
    0x32, 0xEC, 0x94, 0xEC, 0x75, 0xB3, 0x5F, 0x44, 0x6A, 0x63, 0x43, 0x67, 0x17, 0x20, 0x44, 0x34 };
std::array<uint8, 16> constexpr EnableEncryptionContext = { 0xA7, 0x1F, 0xB6, 0x9B, 0xC9, 0x7C, 0xDD, 0x96, 0xE9, 0xBB, 0xB8, 0x21, 0x39, 0x8D, 0x5A, 0xD4 };

WorldPacket const* EnterEncryptedMode::Write()
{
    std::array<uint8, 64> toSign = Trinity::Crypto::HMAC_SHA512::GetDigestOf(EncryptionKey,
        std::array<uint8, 1>{uint8(Enabled ? 1 : 0)},
        EnableEncryptionSeed);

    Trinity::Crypto::Ed25519 ed25519(*EnterEncryptedModeSigner);
    std::vector<uint8> signature;
    ed25519.SignWithContext(toSign, { EnableEncryptionContext.begin(), EnableEncryptionContext.end() }, signature);

    _worldPacket << int32(RegionGroup);
    _worldPacket.append(signature.data(), signature.size());
    _worldPacket << Bits<1>(Enabled);
    _worldPacket.FlushBits();
    return &_worldPacket;
}
```

同檔 L258–264 的 `EnterEncryptedModePrivateKey` 與兩份 proxy 的私鑰 **位元組完全相同**；`EnableEncryptionContext` 也完全相同。**唯獨三件事不同：**

| | TC master `tc_auth.cpp` | 兩份 HermesProxy 實際送出的 |
|---|---|---|
| HMAC 演算法 | **HMAC-SHA512**（`toSign` = **64 bytes**） | HMAC-SHA256（`toSign` = 32 bytes） |
| seed | **32-byte `66 BE 29 79 …`** | 16-byte `90 9C D0 50 …` |
| 封包開頭 | **`int32 RegionGroup`** 在簽章之前 | 沒有這個欄位 |

**這是我們手上唯一一條「有原始碼支撐、且會導致 client 驗章失敗」的假設。** 而且它完美解釋 `reason 24` 的症狀形態：TLS、SRP6、realm list、`CMSG_AUTH_SESSION`、legacy world auth 全過 —— 因為那些都不碰這條路徑 —— 卡在唯一一個要 client **驗證伺服器簽章**的封包上。

**必須同時記下的但書（否則會誤導）：**

- `tc_auth.cpp` 是 **TrinityCore master（retail）** 的程式碼。`RegionGroup` 是 retail 欄位。**未驗證**它是否適用於 3.4.3.54261。
- repo 內的 `tmp_certs/wpp_auth_343.cs`（WowPacketParser 快照）把 **64-byte Ed25519 版本的 parser gate 在 `ClientVersionBuild.V3_4_4_59817`**，且該 parser 的讀取順序是 **signature(64) → `RegionGroup` int32 → bit `Enabled`**，**與 `tc_auth.cpp` 的寫入順序（RegionGroup 在前）相反**。兩份參考自相矛盾，**兩者我都只是讀到，沒有能力判定哪一份對應 3.4.3.54261**。
- 兩份 HermesProxy 的 `Framework/Cryptography/ShaHmac.cs` **都只有 `Sha256` 與 `HmacSha256`，沒有任何 SHA512 類別**（A: L25/L115；B: L25/L53）。也就是說 **HMAC-SHA512 這條路兩邊從來沒有被實作過，不只是沒被啟用**。

**→ 這是一個值得做的實驗，不是一個已知答案。** 若要試，最小改動是：在本機 `AuthenticationPackets.cs` 加一條 `HmacSha512` 並改 `WriteEd25519` 用 32-byte seed；`RegionGroup` 則是另一個獨立變因（先不加，失敗再加 `int32 0` 於簽章前）。**本文不代表這會成功。**

### 2.5 一個必須誠實面對的矛盾

如果 3.4.3.54261 真的是 RSA（依 WPP 的 3.4.4 gate 推論），或真的需要 SHA512+32-byte seed（依 `tc_auth.cpp`），那 **`advocaite` 現行這份 Ed25519 + SHA256 + 16-byte seed 的程式碼應該對誰都不會動** —— 但事實不是這樣：

- issue **#11**（`1825679767`，2026-04-16）：改 `SET portal "localhost"` 之後**登入成功**，接著是「選角進遊戲後崩潰」，並附上進到 world 之後的 log。
- issue **#4**（`DrUlysses`，2026-04-10）：一路走到 `SMSG_CONNECT_TO`、`CMSG_PLAYER_LOGIN`、卡在 loading screen 刷 `SMSG_SET_PROFICIENCY` —— **遠在 encrypted mode 之後**。
- issue **#16**（`yungkai7`）：進遊戲 30 秒後才斷線。

**→ 這份完全相同的常數與構造，在別人的 3.4.3.54261 client 上是通得過 encrypted-mode 握手的。** 所以「常數錯了」不足以解釋我們的 `reason 24`，除非我們的 client 二進位與他們的不同（同 build 號、不同區域／不同 CDN 版本？**未驗證**），或差異來自 launcher／執行環境。§4 是這個方向。

---

## 3. `WorldSocket` 的金鑰推導 —— 同樣逐項比對

| 常數（16 B） | advocaite（L116–132，十進位換算） | 本機 Xian55（L62–64） | 結果 |
|---|---|---|---|
| `AuthCheckSeed` | `C5 C6 98 95 76 3F 1D CD B6 A1 37 28 B3 12 FF 8A` | 同左（L61） | **相同** |
| `SessionKeySeed` | `58 CB CF 40 FE 2E CE A6 5A 90 B8 01 68 6C 28 0B` | 同左 | **相同** |
| `ContinuedSessionSeed` | `16 AD 0C D4 46 F9 4F B2 EF 7D EA 2A 17 66 4D 2F` | 同左 | **相同** |
| `EncryptionKeySeed` | `E9 75 3C 50 90 93 61 DA 3B 07 EE FA FF 9D 41 B8` | 同左 | **相同** |
| `ClientConnectionInitialize` | `"WORLD OF WARCRAFT CONNECTION - CLIENT TO SERVER - V2"` | 同左 | **相同** |
| `ServerConnectionInitialize` | `"WORLD OF WARCRAFT CONNECTION - SERVER TO CLIENT - V2"` | 同左 | **相同** |
| `AuthChallenge.DosZeroBits` | `1` | `1`（L672） | **相同** |

**推導鏈（`HandleAuthSessionCallback`，A L5076–5090 / B L761–781）逐行相同：**

```
Sha256(SessionKey) → digest
HmacSha256(digest).Process(_serverChallenge,16).Process(LocalChallenge,16).Finish(SessionKeySeed,16)
SessionKeyGenerator(digest, 32).Generate(_sessionKey, 40)
HmacSha256(_sessionKey).Process(LocalChallenge,16).Process(_serverChallenge,16).Finish(EncryptionKeySeed,16)
_encryptKey = digest[0..16]
```

**注意順序**：`sessionKeyHmac` 是「先 `_serverChallenge` 後 `LocalChallenge`」，`encryptKeyGen` 是「先 `LocalChallenge` 後 `_serverChallenge`」—— 這個看起來像 bug 的顛倒，**兩邊一模一樣**（也與 TC 一致）。`HandleAuthContinuedSessionCallback`（A L5145–5163 / B L853–876）同樣逐行相同。

**唯二的差異（都不影響位元組）：**

1. **seed 檢查失敗後的處理**：A 無條件印 warn 並繼續（`- BYPASSING for testing`）；B 只在 `ModernVersion.Build >= V3_4_3_54261` 時 bypass，舊 build 仍嚴格斷線。**對 3.4.3 而言行為相同。**
2. A 在送出 `EnterEncryptedMode` 後多呼叫一次 `base.AsyncRead()`；B 沒有（B 的讀取迴圈在別處續行 —— B 的 `AsyncRead()` 出現在 L250/L316 的 handler 尾端）。**這一項我沒有實測 B 是否會漏收 ACK**，但我們的症狀是 client 主動送 `CMSG_LOG_DISCONNECT`（proxy 有收到並印出 reason），代表讀取迴圈是活的 —— **B 不缺這個 `AsyncRead`**。

**兩邊的 `CMSG_LOG_DISCONNECT` handler 也相同**（A L4850–4870）：只是 `packet.ReadUInt32()` 讀出 reason、印 log、關掉 AuthClient/WorldClient。**兩份 codebase 都沒有任何 reason 碼的對照表**，24 這個數字在整個 repo 裡沒有語意。

---

## 4. 它文件的 launcher / client 設定

### 4.1 README（53 行，全文取得）

- 支援表：`1.14.2 ↔ 1.12.1`、`2.5.3 ↔ 2.4.3`、**`3.4.3 ↔ 3.3.5a`**。**沒有 3.4.4、沒有 3.4.5**（`Framework/Constants/ClientVersionBuild.cs` L528 也只有 `V3_4_3_54261 = 54261` 一行，與 `Xian55` 相同）。
- 設定：`WTF/Config.wtf` → `SET portal "127.0.0.1"`；遊戲內 `System → Network → Optimize Network for Speed` 必須開啟。**與 `Xian55` README 完全相同的兩條。**
- launcher：**Arctium WoW-Launcher**，`--staticseed --version=ClassicEra`（vanilla）或 **`--staticseed --version=Classic`（TBC 與 WotLK）**。**與 `Xian55` 完全相同。**
- 但緊接著一句原文：

  > "For WOLTK you will need a updated version repo yet to be added."

  **→ 作者自己知道 stock Arctium 對 WotLK 不夠，說要放一個更新版 launcher 的 repo —— 但那個 repo 從未出現**（repo 樹內沒有任何 launcher，11 個 release 的 asset 全是 proxy 本身）。**這條路是死的。**
- **憑證：README 完全沒有提到憑證。** 但 repo 樹裡有 `tmp_certs/`，內含自簽的 `CN=HermesProxy CA` + `CN=localhost` 伺服器憑證，SAN 是 `DNS:*.bgs.battle.net, DNS:*.actual.battle.net, DNS:localhost, IP:127.0.0.1`（`srv_ext.cnf` 原文）。內嵌的 `HermesProxy/BNetServer.pfx` 與我們本機那顆**不同檔**（3,213 vs 6,125 bytes，SHA-256 `37d9affa…` vs `bf8ec2aa…`）。**這一項對我們無關**：我們的 BNet TLS 握手已經成功。

### 4.2 ★ issue 裡對我們最有用的兩條社群回報

**(a) Arctium 與 CPU 指令集** —— issue **#3**，`kasperfriend` 留言原文：

> "Also side note, for older CPU's Arctium Launcher can be emulated through Intel SDE, using command `sde.exe -hsw sde.exe --path\to\arctium\exe --staticseed --version=Classic`
> Guess that should be mentioned in readme"

**→ 這與我們實測的「The required instruction sets are not supported by the current CPU」是同一個問題**（Arctium 需要較新的 x86 指令集，`-hsw` 是 SDE 的 Haswell 模擬旗標）。**但它對我們是否可用，完全未驗證**：Intel SDE 是 x86 的動態二進位翻譯器，我們的路徑是 `Apple Silicon → Rosetta 2 → Whisky/wine-7.7 → Win x86-64`。「在 Rosetta 底下再疊一層 SDE」是否可行、Rosetta 是否支援 SDE 自己需要的指令 —— **本文沒有測，不做任何承諾**。這是一條線索，不是一個解法。

**(b) `portal` 要填 `localhost` 而不是 `127.0.0.1`** —— issue **#11**、**#4**、**#22** 三處，多位使用者與 `kasperfriend` 反覆確認：

> "set portal to localhost, it worked for me and other people" — issue #11
> "for me after some testing, setting set portal to localhost in WTF helped, I think even 127.0.0.1 didn't work" — issue #4

**這與 README 自己寫的 `SET portal "127.0.0.1"` 相反，且從未被寫回 README。** issue #4 的 log 顯示 `127.0.0.1` 的失敗形態是：TLS handshake succeeded → **client 送 0 bytes 就關連線** → 立刻 "you have been disconnected"。**那不是我們的症狀**（我們的 TLS 之後一路走到 encrypted mode），但**這是零成本的一次嘗試**，值得試。憑證的 SAN 同時含 `DNS:localhost` 與 `IP:127.0.0.1`，理論上兩者都該過，但 client 的主機名比對邏輯**未驗證**。

### 4.3 其他社群 workaround（記錄，非背書）

- issue #8 / #3：這份 snapshot **不是完整可執行包**，正確用法是「下載原始 `WowLegacyCore/HermesProxy` release，再把本 repo 的 exe/pdb/config 覆蓋上去，CSV 與 Hotfix 目錄也覆蓋」。**與我們無關**（我們是自行 build `Xian55` 的完整分支）。
- issue #11：`kasperfriend` 建議把 `_classic_wrath_` 目錄改名為 `_classic_`。**未驗證**。
- issue #11 有一則留言貼出 3.4.3.54261 client 的 Google Drive 直連。**依既有筆記界線，不記錄、不追蹤任何 client 下載途徑。**

---

## 5. 它有沒有記錄我們這個失敗？—— 沒有

全樹 `grep`（`*.cs` / `*.md`）搜尋 `LOG_DISCONNECT`、`reason 24`、`ENTER_ENCRYPTED`、`EnterEncryptedMode`：

| 命中位置 | 性質 |
|---|---|
| `HermesProxy/World/Enums/*/Opcode.cs` | 純 opcode 定義（`CMSG_ENTER_ENCRYPTED_MODE_ACK = 14183`、`CMSG_LOG_DISCONNECT = 14185`、`SMSG_ENTER_ENCRYPTED_MODE = 12361`，**與我們觀察到的數字一致**） |
| `newopcodes.md` / `opcode_comparison.md` | 自動產生的 opcode 對照表（`tmp_certs/gen_opcode_lists.py` 產） |
| `packet_structures.md`（22,996 行處） | 自動產生的欄位摘要，`EnterEncryptedMode` 那節只抄了 `if (ExpansionVersion >= 3)` 這個 gate，**沒有任何說明文字** |
| `WorldSocket.cs` L4850 | reason 只是印出來，**無語意對照** |

- **issue 全表 22 筆，沒有任何一筆提到 encrypted mode、握手、簽章或 reason 碼。**
- `research/` 目錄下 5 份筆記（`creature_health_visual_updates` / `death_revive_visual` / `player_values_update_crash` / `transport_crash_investigation` / `update_fields_audit`）**全部是進入世界之後的 gameplay 問題**，無一觸及 auth 路徑。
- 順帶複驗（`gh api search/issues`）：**`Xian55/HermesProxy` 也沒有任何 `reason 24` 的討論**（搜尋只命中 issue 編號 #24 與含 "reason" 一字的無關 issue）。

**→ 這個失敗模式在兩個 repo 的公開紀錄裡都不存在。我們是第一個踩到的（或至少是第一個寫下來的）。**

---

## 6. 裁決

**這個 repo 不含任何能直接修掉 `reason 24` 的東西。**

- **常數**：Ed25519 私鑰、context、`EnableEncryptionSeed`、四個 `WorldSocket` seed —— **逐位元組相同**。`Xian55` 註解裡那句「Values match the advocaite fork」是**準確的**。
- **封包版面**：相同（signature → bit → flush，無 `RegionGroup`）。
- **version gate**：相同（`ModernVersion.ExpansionVersion >= 3`）。
- **金鑰推導**：相同（含那個先後顛倒的 challenge 順序）。
- **launcher**：相同（Arctium `--staticseed --version=Classic`），而且它自承需要一個「更新版」launcher **但從未提供**。
- **文件化的 workaround**：**沒有**針對 encrypted-mode 的任何一條。

**它唯一給出的、有價值的新東西，是它自己沒用的那些檔案：**

1. **`EnableEncryptionSeedEd25519`（32 B）+ `tmp_certs/tc_auth.cpp` 揭露的 TC master 構造（HMAC-SHA512 + 32-byte seed + `int32 RegionGroup`）** —— 目前唯一有原始碼證據的替代假設。**適用性未驗證**（那是 retail/3.4.4+ 的碼），且與 §2.5 的實測矛盾（別人用現行構造在 3.4.3 上是通的）。
2. **`tmp_certs/wpp_auth_343.cs` 把 Ed25519 parser gate 在 `V3_4_4_59817`** —— 暗示 3.4.3 可能根本是 RSA。同樣與 §2.5 矛盾。
3. **Intel SDE 模擬 Arctium** 的社群提示（§4.2）—— 對我們的 Apple Silicon + Rosetta + Whisky 疊層是否可行，**完全未驗證**。
4. **`SET portal "localhost"`**（§4.2b）—— 零成本、與 README 相反、被多位使用者確認過的設定差異。

**下一步的優先序（我的建議，非驗證結果）**：先試 §4.2b 的 `localhost`（一分鐘，零風險）；再試 §2.4 的 SHA512 + 32-byte seed 實驗（需加一個 `HmacSha512` class，本機改動，可回復）；`RegionGroup` 當成第二個獨立變因分開試。**Arctium/SDE 那條先擱著，代價最高、把握最低。**

---

## 7. 驗證方式（可重跑，全部唯讀）

```bash
# Repo 事實
gh api repos/advocaite/HermesProxy-WOTLK \
  --jq '{fork,parent:.parent.full_name,license:.license.spdx_id,default_branch,stars:.stargazers_count,created_at,pushed_at}'
gh api "repos/advocaite/HermesProxy-WOTLK/commits?per_page=1" -i | grep -i '^link'   # rel="last" = commit 數
gh api repos/advocaite/HermesProxy-WOTLK/contributors --jq '.[]|"\(.login) \(.contributions)"'
gh api repos/advocaite/HermesProxy-WOTLK/releases --jq '.[]|"\(.tag_name) \([.assets[].name]|join(","))"'
gh api "repos/advocaite/HermesProxy-WOTLK/issues?state=all&per_page=100" \
  --jq '.[]|"\(.number) \(if .pull_request then "PR" else "IS" end) \(.state) \(.title)"'

# 本篇 §2 的兩個檔案（不要 clone 進專案目錄）
curl -sS https://raw.githubusercontent.com/advocaite/HermesProxy-WOTLK/master/HermesProxy/World/Server/Packets/EnterEncryptedMode.cs
curl -sS https://raw.githubusercontent.com/advocaite/HermesProxy-WOTLK/master/HermesProxy/World/Server/WorldSocket.cs | sed -n '110,135p;5070,5110p'

# §2.4 的 TC master 參考實作
curl -sS https://raw.githubusercontent.com/advocaite/HermesProxy-WOTLK/master/tmp_certs/tc_auth.cpp | sed -n '255,265p;355,380p'
curl -sS https://raw.githubusercontent.com/advocaite/HermesProxy-WOTLK/master/tmp_certs/wpp_auth_343.cs | sed -n '113,123p'

# 本機對照（唯讀）
sed -n '463,523p' ~/Works/side-project/wotlk-stack/hermesproxy/HermesProxy/World/Server/Packets/AuthenticationPackets.cs
sed -n '58,64p;755,800p' ~/Works/side-project/wotlk-stack/hermesproxy/HermesProxy/World/Server/WorldSocket.cs
grep -n 'class Hmac\|class Sha' ~/Works/side-project/wotlk-stack/hermesproxy/Framework/Cryptography/ShaHmac.cs
```

---

## 8. 明確記錄「沒做 / 拿不到」

- **未驗證**：HMAC-SHA512 + 32-byte seed（+/- `RegionGroup`）是否為 3.4.3.54261 的正解。本文只證明了「兩份 proxy 都沒用它」與「TC master 用它」。
- **未驗證**：`tmp_certs/tc_auth.cpp` 與 `tmp_certs/wpp_auth_343.cs` 的來源與版本 —— 它們是 fork 作者放進 repo 的第三方快照，**我沒有回頭去 TrinityCore / WowPacketParser 上游核對過對應 commit**。
- **未驗證**：Intel SDE 能否在 Rosetta 2 + Whisky 下跑起 Arctium。
- **未驗證**：`SET portal "localhost"` 對我們這一段（已經走到 encrypted mode）是否有任何影響。
- **未驗證**：advocaite 使用者的 3.4.3.54261 client 二進位是否與我們手上這份逐位元組相同。
- **未做**：沒有 build 或執行 `advocaite` 的任何產物；沒有改動本機 `wotlk-stack` 或 TrinityCore 的任何檔案；沒有切換任何分支。
- **不記錄**：issue #11 留言中出現的 client 下載連結（依既有筆記界線）。
- 本文**不背書**此第三方專案，未評估其安全性與授權合規性（GPL-3.0，與 TrinityCore 的 GPL-2.0-or-later 單向相容問題見[全景調查](./classic-client-emulator-landscape.md)）。
