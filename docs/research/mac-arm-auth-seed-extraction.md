# Mac ARM（`MacA` / A64）auth seed —— 從 macOS binary **靜態抽取的實作嘗試與結論**

> 撰寫日期：2026-09-06
> 相關筆記：[Mac ARM auth seed 有沒有公開值、怎麼挖](./mac-arm-auth-seed.md)（**本篇是它 §4.2「路線 A：靜態」的實作報告**，回填該篇標為「未驗證：本篇沒有實際跑完這條路線」的那一步）、[維護中的 3.4.3 forks 盤點](./maintained-343-forks.md)、[macOS client 選項](./macos-client-options.md)、[wow-patcher runtime 模式](./wow-patcher-runtime-mode.md)（Windows 端 Arxan `.text` 加密的旁證）
> **本篇只回答一個問題：** 能不能用**純靜態分析**、不執行 client，從手上的 macOS arm64 binary 把 16-byte `MacA` seed 挖出來？
> 來源限定 primary sources：對**原始通用二進位備份**（`wow-universal-original.bak`，含 x86_64 + arm64，未修改、簽章完整）的直接靜態檢查——`lipo` 抽 slice、`otool -l/-tV`、`nm`，以及自寫的 Python Mach-O / arm64 指令解碼器與位元組/熵值掃描，**全部唯讀**。凡未實跑者標「**未驗證**」。未使用瀏覽器自動化。未記錄任何 client 下載點。

---

## 0. TL;DR —— 直說成功與否

**No。靜態抽取失敗，而且是「原理上被擋死」，不是「還沒找到」。**

一句話總結：**這顆 macOS binary 的 `__TEXT,__text`（可執行碼）在磁碟上是整段加密的（實測熵值 = 8.000，滿格），arm64 與 x86_64 兩個 slice 都是。** 產生 seed 的那個函式住在這段密文裡，靜態反組譯只會得到亂碼；而 seed 值本身（若以常數存在）就算躺在明文的 `__const` 裡，也因為「引用它的 code 是密文、我們又沒有已知答案可比對」而**無法指認是哪一塊**。所以連 1 個 byte 都無法從磁碟推導出來。

五點裁決：

1. **`__text` 是密文。** arm64 slice 的 `__text`（file off `0x195c`、vmaddr `0x10000195c`、size `0x1ca81bc`≈30 MB）前 1 MB 熵值 = **8.000**；把整段切成 4 KB 窗掃描，**沒有任何一個窗低於 6.5**（唯一的例外是 section 尾端 padding）。`otool -tV` 對它反組譯出的是不可能的指令流（隨機 `.long`、亂七八糟的 SVE mnemonic）。x86_64 slice 的 `__text` 同樣是亂碼（`otool` 出 `bad opcode` / `adcb` 之類）。（§2.1）
2. **明文資料段可讀，但不含可指認的 seed。** `__cstring`（熵 5.574）、`__TEXT,__const`（熵 5.909）、`__DATA_CONST,__const`（熵 3.720）都是明文。既定前提給的四個共用常數確實在 `__TEXT,__const`：arm64 slice off `0x1e0ce20`（vmaddr `0x101e0ce20`）、x86_64 slice off `0x219cc30`（fat file `0x21a0c30`），**逐 byte 對上**（§2.2）。**但 per-platform / per-build 的 auth seed 不在這張表裡**（前後鄰居已於前篇排除），也無法在其餘明文 `__const` 中指認。
3. **xref 追不到，因為根本沒有真正的 code 可追。** 我在整段 `__text` 掃 arm64 的 `ADRP`＋`ADD`/`LDR` 位址對（取字串／常數位址的標準 idiom）：共匹配 117,520 個「像 `adrp`」的字，但其中 **117,073 個指向 image 外**（不可能是真指令），只有 447 個落在 image 內、其中僅 15 個指到 `__cstring`、20 個指到 `__TEXT,__const`、12 個指到 `__DATA_CONST,__const`。這個比例證明那些 `adrp` 幾乎全是密文裡的巧合位元組，**不是指令**——也就是說 `WoW\0` FourCC anchor / `MacA` 字串的交叉參照在磁碟上**不存在可解析的形式**（§2.3）。
4. **Windows 已知答案無法拿來驗證。** `25FD812475DCF26F9F1383AED37FC99E` 是 **Windows `.exe`** 的 seed，本 macOS binary 兩個 slice 都 NOT FOUND（前篇已測，本篇未再重覆），而且它的產生函式在 Windows `.exe` 裡、同樣被 Arxan 加密。**沒有一個「已知答案」的函式活在這顆 binary 的明文裡可供對照**，既定步驟 5 的「用 Windows slice 同一函式驗證解讀」在這顆 binary 上不成立（§2.4）。
5. **看得到加殼器的骨架。** binary 內有非標準 section `__INIT1`（熵 6.739）、`__INITC`（熵 2.151）、`__mod_init_func`（熵 4.307）——這是在載入時（透過 `__mod_init_func`）把 `__text` 就地解密的 runtime bootstrap。**沒有 `LC_ENCRYPTION_INFO`**（所以不是 FairPlay，是應用層加殼；與前篇「沒有 FairPlay 但仍可能有 Arxan」的懸念一致，本篇把它**證實**了）（§2.5）。

> **對前篇的一個更正：** [mac-arm-auth-seed.md](./mac-arm-auth-seed.md) §3.3 把四個共用常數的位置寫成 `__DATA_CONST`。實測它們在 **`__TEXT,__const`**（arm64 vmaddr `0x101dbc100`–`0x101ef2aa2`，含 `0x101e0ce20`）。值與 offset 都正確，只是 section 歸屬更正。

---

## 1. 方法與素材

- 素材：`/Users/shinichi/Works/side-project/wow343-archive/wow-universal-original.bak`（73,037,104 bytes，`lipo -info` = `x86_64 arm64`，未改動）。
- 用 `lipo -thin arm64` / `-thin x86_64` 抽出兩個乾淨 slice 到暫存區分析。
- 工具現況（實測 `which`）：`otool`、`nm`、`objdump`（Apple LLVM 21.0.0）、`lipo` 有；**`llvm-objdump` / radare2 / rabin2 / rizin / IDA / Ghidra 全無**。
- 自寫工具：Python Mach-O section 解析、arm64 `ADRP`/`ADD`/`LDR` 解碼器、位元組搜尋、Shannon 熵掃描（滑動窗）。

**踩到的坑（記錄以免重工）：** `objdump -d --macho --arch=arm64 --start-address=… --stop-address=…` 對這顆 binary **不吐指令**（只印 section 標頭就結束）。Mac 上要對某位址範圍反組譯，`otool -tV` 較可靠，但它只能全段輸出、無法指定範圍（需自行 `sed`/`awk` 過濾）。本篇的位址級分析因此改用自寫的 Python 解碼器，不依賴 `objdump` 的範圍功能。

---

## 2. 實測結果

### 2.1 `__text` 是密文（核心證據）

arm64 slice 各段熵值（每段取前 ≤1 MB）：

| section | file off | size | 熵值 | 判讀 |
|---|---|---|---|---|
| `__TEXT,__text` | `0x195c` | `0x1ca81bc` | **8.000** | **密文／加殼** |
| `__TEXT,__cstring` | `0x1cb6d5c` | `0xfb0fb` | 5.574 | 明文字串 |
| `__TEXT,__const` | `0x1dbc100` | `0x1369a2` | 5.909 | 明文常數 |
| `__DATA_CONST,__const` | `0x1f190c0` | `0xf6778` | 3.720 | 明文常數 |

把整段 `__text` 切成 4 KB 窗逐一算熵，**最小值 4.921 只出現在 section 尾端**（`0x1ca995c`，緊鄰 `__stubs` 起點 `0x1ca9b18` 的 padding），其餘全部 ≥6.5、絕大多數貼近 8.0。**沒有任何一段可讀的明文 code。**

`otool -tV wow-arm64` 開頭實錄（vmaddr `0x10000195c` 起）：

```
000000010000195c	.long	0x63b00a57
0000000100001960	.long	0xfa71df25
0000000100001964	bl	0xfc3e6884            ← 跳到 image 外，不可能
0000000100001968	stnt1h { z19.h, z27.h }, pn8, [x7, ...]  ← SVE，Apple Silicon 根本不支援
...
```

x86_64 slice `__text`（vmaddr `0x1000041a0` 起）同樣是亂碼：`adcb`、`.byte 0xfe #bad opcode`、`outb %al, $0xba` …。**兩個 slice 的可執行碼都在磁碟上加密。**

### 2.2 四個共用常數確實在明文 `__TEXT,__const`

arm64 slice off `0x1e0ce20`（vmaddr `0x101e0ce20`）起，逐 byte dump：

```
0x1e0ce00  631633BF447398A4B489B4C26FBC03AD   ← 前鄰
0x1e0ce10  A71FB69BC97CDD96E9BBB821398D5AD4   ← 前鄰
0x1e0ce20  C5C69895763F1DCDB6A13728B312FF8A   ← AuthCheckSeed
0x1e0ce30  16AD0CD446F94FB2EF7DEA2A17664D2F   ← ContinuedSessionSeed
0x1e0ce40  58CBCF40FE2ECEA65A90B801686C280B   ← SessionKeySeed
0x1e0ce50  E9753C50909361DA3B07EEFAFF9D41B8   ← EncryptionKeySeed
0x1e0ce60  909CD0505A2C14DD5C2CC06414F3FEC9   ← 後鄰
```

x86_64 slice 同一組常數在 slice off `0x219cc30`（fat file `0x4000 + 0x219cc30 = 0x21a0c30`，與前篇一致），四個值逐 byte 相同。**這證明明文資料段完全可讀——問題不在讀不到資料，而在讀不到「產生 seed 的邏輯」。**

### 2.3 FourCC / 字串的 xref 在磁碟上不存在可解析形式

在整段 `__text` 掃 `ADRP` 指令並解出目標頁，再看緊接的 `ADD`/`LDR` 是否湊出目標位址：

- 匹配 `adrp` 位樣（`(ins & 0x9f000000) == 0x90000000`）的字：**117,520 個**。
- 目標落在 image 內（`0x100000000`–`0x102000000`）：僅 **447 個**；其餘 **117,073 個指向 image 外**（如 `0x1d9000`、`0x201963000`），**不可能是真指令**。
- 447 個之中，指到 `__cstring` 的 15、`__TEXT,__const` 的 20、`__DATA_CONST,__const` 的 12。

一顆 30 MB 的正常 arm64 binary，對字串／常數的 `adrp`＋`add` 參照應有數萬筆。這裡近乎於零，且 99.6% 的「`adrp`」指向 image 外——**結論：那些位樣是密文裡的隨機巧合，`__text` 裡沒有可解析的指令。** 因此：

- 既定步驟 3（追 `MacA` / `Wn64` / `Mc64` 字串的 xref 到選種子分支）——**無法執行**：字串在（`MacA` @ `0x1d61fd4` 等），但引用它的 code 是密文。
- 既定步驟 4（`WoW\0` FourCC anchor → seed 產生函式）——**無法執行**：`WoW\0` FourCC 在（`0x1d18a90` 的 build-type 表等），但 Arctium 的 anchor 是「字串／FourCC **緊接 `call`**」，而這裡 anchor 之後的 code 是密文，追不到 callee。
- 既定步驟 5（從 `mov`/`movk` 立即數序列解出 16 bytes）——**無法執行**：那串立即數在密文裡。

### 2.4 Windows 已知答案無法用於驗證

`25FD812475DCF26F9F1383AED37FC99E` 是 Windows `WowClassic.exe` 的 seed；它（a）不在這顆 macOS binary（前篇兩 slice 皆 NOT FOUND），（b）其產生函式在 Windows `.exe` 裡、被 Arxan 加密。**這顆 binary 的明文區裡沒有任何「已知答案的函式」可拿來校準解讀**，所以「先用 Windows 分支重現 `25FD8124…` 再讀 Mac 分支」這條驗證迴路在純靜態、只有這顆 binary 的條件下**不成立**。（要有對照，唯一可行的是拿一顆**已知 `MacA` 值**的舊資料片 client——例如前篇 §2 記到的 1.14.2 build 42597 `3B31A4F4C25382131A8FB95A1317412B`——但那要另一顆 binary，且同樣會遇到 `__text` 加密。）

### 2.5 加殼器骨架（為什麼沒有 `LC_ENCRYPTION_INFO` 卻是密文）

- 非標準 section：`__TEXT,__INIT1`（熵 6.739）、`__TEXT,__INITC`（熵 2.151，多為結構化資料／解密表）、`__DATA_CONST,__mod_init_func`（熵 4.307，一串 init 函式指標）。這組是**在載入時就地解密 `__text` 的 runtime bootstrap**。
- `LC_ENCRYPTION_INFO(_64)`：**0 筆**（不是 Apple FairPlay，是應用層加殼；與 Windows 端 Arxan TransformIT 對稱）。
- `LC_MAIN` 存在（`entryoff` 入口）。

也就是說：**磁碟上的 `__text` 是密文，要等 process 起來、`__mod_init_func` 跑完解密後，記憶體裡才有明文 code。** 這正是靜態路線的死穴，也是為什麼前篇一路推薦 runtime 手段。

---

## 3. 卡在哪、下一步需要什麼

**卡點（單一且致命）：`__text` 磁碟加密。** 產生 seed 的函式、以及它引用的立即數／常數存取邏輯，全部在密文裡；seed 值即使以明文常數存在於 `__const`，也因缺「引用它的 code」與「已知答案」兩個錨而無法指認。純靜態、只讀磁碟，**推不出任何一個 byte**。

**下一步（把靜態變成「先 runtime dump、再靜態」——這條會成功）：**

1. **在記憶體裡取得解密後的 `__text`。** 用 lldb attach（或啟動後 attach），等 `__mod_init_func` 解密完成（下在主邏輯的某個斷點、或 login 前），把 arm64 `__TEXT` segment 的 vmaddr 範圍（`0x100000000` 起、`__text` 到 `0x101ca9b18`）`memory read`/`process save-core` dump 到檔案。**此時 dump 出來的 `__text` 應該是明文 arm64 code。**
2. **對 dump 重跑本篇已寫好的掃描器。** 我寫的 `ADRP`＋`ADD`/`LDR` xref 解碼器與 FourCC 立即數搜尋，對**明文** `__text` 就會生效：屆時 `MacA` @ `0x101d61fd4`、`WoW\0` build-type 表 @ `0x101d18a90`、以及常數表頁 `0x101e0c000` 的 xref 會浮現，即可依既定步驟 3–5 追到 seed 函式、讀出它寫進 caller buffer 的 16 bytes。
3. **或者直接跳過反組譯，走前篇 [§4.4 的 `CC_SHA256_Update` hook](./mac-arm-auth-seed.md#44-路線-c-runtime-hook-cc_sha256_update-建議先試這條)。** client 的 SHA-256 是 dynamic symbol `_CC_SHA256_Update`，一次登入即可 dump 到 `sessionKey ‖ platformSeed`，末 16 bytes 就是答案，且能用 server 已知的 session key 當場閉環驗證。**這條仍是投入產出比最高的一條。**
4. 需要而目前沒有的東西：一個能 attach／注入的簽章環境（重簽 + `get-task-allow`，前篇 §4.4 已列步驟），以及（若走反組譯路）一顆真正的反組譯器或就用本篇的 Python 解碼器擴充。**磁碟端已無可再榨取的資訊——後續一定得讓 code 先在記憶體裡解密。**

---

## 4. 明確的負面結論（同樣重要）

- **無法從磁碟上的 macOS binary 靜態抽出 `MacA` seed 的任何 byte**——因 `__text` 全段加密。此點對 arm64 與 x86_64 兩 slice 皆成立。
- **前篇「`__TEXT.__text` 是否另有保護——未驗證」的懸念，本篇證實：有，整段加密（熵 8.000）。**
- 磁碟上**不存在**可解析的 `WoW\0` / `MacA` xref、也不存在可讀的 seed 產生函式。
- 本篇未嘗試 runtime dump／hook（依任務限定純靜態）；那屬於前篇 §4.4 的範疇，且為目前唯一可行的前進方向。
