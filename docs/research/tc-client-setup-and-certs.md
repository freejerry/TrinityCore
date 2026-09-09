# TrinityCore 官方文件：現代架構（bnetserver / Battle.net）的 client 設定與憑證

> 撰寫日期：2026-09-03
> 相關筆記：[HermesProxy 決策級評估](./hermesproxy-evaluation.md)、[在 TrinityCore 上跑「WotLK Classic」](./wotlk-classic-on-modern-client.md)、[TrinityCore 專案總覽](./trinitycore-overview.md)、[RaGEZONE 論壇調查](./community-forum-findings.md)、[macOS client 取得與執行](./macos-client-options.md)
> 來源限定 primary sources：本機 `master` checkout（`/Users/shinichi/Works/side-project/TrinityCore`，唯讀 git）、官方 wiki `trinitycore.info`（Wiki.js，實際抓取渲染後 HTML 與其 GraphQL 搜尋 API）、GitHub repo 檔案。
> 未能取得：官方論壇 `https://community.trinitycore.org/` 於 2026-09-03 回傳 **HTTP 500**，WebFetch 與 curl 皆失敗，本篇不引用任何論壇內容。

---

## 0. 最具決策價值的一條事實（先講結論）

TrinityCore 內建的 BNet leaf 憑證 **完全沒有 `subjectAltName` 擴充欄位**，唯一的身分資訊是 `CN=*.*`。

實測（`openssl x509 -text`，本機檔案 `src/server/bnetserver/bnetserver.cert.pem` 第 1 張憑證）：

```
X509v3 extensions:
    X509v3 Basic Constraints:
        CA:FALSE
    Netscape Cert Type:
        SSL Server
    Netscape Comment:
        OpenSSL Generated Server Certificate
    X509v3 Subject Key Identifier: ...
    X509v3 Authority Key Identifier: ...
    X509v3 Key Usage: critical
        Digital Signature, Key Encipherment
    X509v3 Extended Key Usage:
        TLS Web Server Authentication
```

沒有 `X509v3 Subject Alternative Name`。任何走「作業系統 trust store 正常驗證」路徑的 TLS client（Windows Schannel、Go `crypto/tls`、瀏覽器、.NET 的 `SslStream` 預設驗證）自 2017 年起一律 **忽略 CN、只看 SAN**；缺 SAN 的憑證會直接被判定為 name mismatch 而中止 handshake——**即使你把 `TrinityCore Battle.net Aurora Root CA` 匯入系統信任區也一樣救不回來**。

因此：若 client 端是被 `wowemulation-dev/wow-patcher` 這種「改成走系統 trust store 驗證」的 patch 處理過，重用 TrinityCore 內嵌憑證（HermesProxy 的 embedded pfx，subject `CN=*.*`）**在原理上不可能通過 handshake**。唯一可行方向是自簽一張帶 `subjectAltName = DNS:<你在 portal cvar 裡用的 hostname>` 的憑證、用自己的 CA 簽發並把該 CA 放進系統 trust store，再透過 `ProxyNetworkOptions:CertificatePfxPath` 餵給 HermesProxy。這與 HermesProxy 原始碼註解說的「for setups validating against the system trust store (e.g. wowpatch)」完全一致。

> 注意這是我從 repo 內憑證實測推導出的結論，**TrinityCore 自己的文件對此一字未提**（見第 4 節）。

---

## 1. 憑證在 repo 裡的位置、內容與設定入口

### 1.1 檔案位置

| 路徑 | 說明 |
|---|---|
| `/Users/shinichi/Works/side-project/TrinityCore/src/server/bnetserver/bnetserver.cert.pem` | 憑證鏈（**3 張** PEM 憑證） |
| `/Users/shinichi/Works/side-project/TrinityCore/src/server/bnetserver/bnetserver.key.pem` | 私鑰，`-----BEGIN RSA PRIVATE KEY-----` |
| `/Users/shinichi/Works/side-project/TrinityCore/src/server/bnetserver/CMakeLists.txt` | 第 51–52 / 64 / 74 行，把兩個 `.pem` 複製 / 安裝到執行檔目錄 |

`CMakeLists.txt:51-52`：

```
  COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/bnetserver.cert.pem ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/bnetserver.cert.pem
  COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/bnetserver.key.pem ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/bnetserver.key.pem
```

repo 內 **沒有** `.pfx` 檔；PKCS#12 只是 conf 支援的「可以由你自備」的格式（見 1.3）。

### 1.2 憑證鏈的 subject / issuer（實測 `openssl x509`）

```
--- leaf
subject=C=US, O=TrinityCore, OU=Developers, CN=*.*
issuer=C=US, O=TrinityCore, OU=TrinityCore Certificate Authority, CN=TrinityCore Battle.net Aurora CA
notBefore=Feb 28 13:11:28 2016 GMT
notAfter=Feb 23 13:11:28 2036 GMT
Signature Algorithm: sha256WithRSAEncryption
Public-Key: (2048 bit)
CA:FALSE

--- intermediate
subject=C=US, O=TrinityCore, OU=TrinityCore Certificate Authority, CN=TrinityCore Battle.net Aurora CA
issuer=C=US, O=TrinityCore, OU=TrinityCore Certificate Authority, CN=TrinityCore Battle.net Aurora Root CA
Public-Key: (4096 bit)
CA:TRUE, pathlen:0

--- root（self-signed）
subject=C=US, O=TrinityCore, OU=TrinityCore Certificate Authority, CN=TrinityCore Battle.net Aurora Root CA
issuer=C=US, O=TrinityCore, OU=TrinityCore Certificate Authority, CN=TrinityCore Battle.net Aurora Root CA
Public-Key: (4096 bit)
CA:TRUE
```

**是的，是自簽的**：三張憑證的根是 `CN=TrinityCore Battle.net Aurora Root CA` 自簽 root，2016 年產生、2036 年到期。演算法（SHA-256 / RSA-2048、root 4096）本身沒問題，問題只在缺 SAN。

`bnetserver.cert.pem` 的 blob hash 為 `f556bcf80b8941e2b02f58c25352f3307df5a392`；**`origin/wotlk_classic`（即 3.4.x 分支）的同一路徑是同一顆 blob**，master / wotlk_classic 共用完全相同的憑證與相同的 SSL 程式碼路徑。

### 1.3 是否支援自備憑證：支援，且 conf.dist 明講

`src/server/bnetserver/bnetserver.conf.dist:99-119`（逐字）：

```
#
#    CertificatesFile
#        Description: Certificates file. Both PEM (.crt) and PKCS#12 (.pfx) formats are supported
#        Example:     "/etc/ssl/certs/bnetserver.cert.pem"
#        Default:     "./bnetserver.cert.pem"

CertificatesFile = "./bnetserver.cert.pem"

#
#    PrivateKeyFile
#        Description: Private key file.
#        Example:     "/etc/ssl/private/bnetserver.key.pem"
#                     Leave empty if you have a certificate in PKCS#12 format
#        Default:     "./bnetserver.key.pem"

PrivateKeyFile = "./bnetserver.key.pem"

#
#    PrivateKeyPassword
#        Description: Password used to encrypt private key.
#        Default:     ""

PrivateKeyPassword = ""
```

程式碼對應在 `src/server/bnetserver/Server/SslContext.cpp`：

- 第 71 行 `std::string certificateChainFile = sConfigMgr->GetStringDefault("CertificatesFile", "./bnetserver.cert.pem");`
- 第 83 行 用 OpenSSL `OSSL_STORE_open` 開檔（所以 `.pem` / `.pfx` 都吃）
- 第 155–156 行 只有在 store 沒帶出私鑰時才讀 `PrivateKeyFile`

註：`PrivateKeyPassword` 這個選項在 conf.dist 有，但同一目錄的 `SslContext.cpp` 是用 boost.asio 的 password callback（第 73 行）取得——這與 HermesProxy 的 `CertificatePfxPassword` 是同一個概念層級。

### 1.4 隱藏但關鍵：TrinityCore 自己會偵測「dev wildcard 憑證」並降級成 HTTP

`SslContext.cpp:118-145` 會掃 leaf 憑證的所有 `commonName`，若其中任何一個等於字面字串 `"*.*"`，就把靜態旗標設為 true：

```cpp
_usesDevWildcardCertificate = [&]
{
    ...
        if (std::string_view(reinterpret_cast<char const*>(utf8Text.get()), utf8Length) == "*.*")
            return true;
    ...
}();
```

`SslContext.h:32` 對外暴露 `static bool UsesDevWildcardCertificate()`。這個旗標在 4 個地方決定 **login REST 走 http 還是 https**：

- `REST/LoginHttpSession.cpp:121-123`：真正決定 8081 埠的 socket 型別
  ```cpp
  LoginHttpSession::LoginHttpSession(Trinity::Net::IoContextTcpSocket&& socket)
      : _socket(!SslContext::UsesDevWildcardCertificate()
          ? std::shared_ptr<AbstractSocket>(std::make_shared<LoginHttpSocketImpl<Trinity::Net::Http::SslSocket>>(std::move(socket), *this))
          : std::shared_ptr<AbstractSocket>(std::make_shared<LoginHttpSocketImpl<Trinity::Net::Http::Socket>>(std::move(socket), *this)))
  ```
- `REST/LoginRESTService.cpp:173`、`Services/AuthenticationService.cpp:242,336`：組 URL 時決定要不要加 `s`
  ```cpp
  Trinity::StringFormat("http{}://{}:{}/bnetserver/login/", !SslContext::UsesDevWildcardCertificate() ? "s" : "", ...)
  ```

**語意翻譯**：TrinityCore 官方立場是「內建這張 `CN=*.*` 憑證只是 dev 用途，拿它就不要對 REST 端點做 TLS，直接走明文 HTTP」；只有當你換上一張真正的（非 `*.*`）憑證，8081 才會升級成 HTTPS。這條 dev-wildcard 偵測是 commit `ac5aee6a98`（`Core: Updated to 10.2.6.53840`，Shauren，2024-03-21）引入的。

**但 1119 埠不受此影響**：`src/server/bnetserver/Server/Session.h:139` 寫死

```cpp
using Socket = Trinity::Net::Socket<Trinity::Net::SslStream<>>;
```

也就是 **Battle.net 主連線（1119）永遠是 TLS**，無論用哪張憑證。這正是你目前卡住的那個 handshake。

`SslContext::instance()`（`SslContext.cpp:164-167`）只做 `boost::asio::ssl::context context(boost::asio::ssl::context::tls);`——**沒有** `set_options`、**沒有** `set_verify`（不驗 client 憑證）、沒有指定 cipher list。所以 server 端不會是 handshake 失敗的一方；失敗必然發生在 client 的憑證驗證。

---

## 2. wiki 對「玩家 / client 要做什麼」的完整說法

### 2.1 Client Setup（唯一直接相關的頁）

<https://trinitycore.info/en/install/Client-Setup>

master / cata_classic 段落全文（逐字）：

> ### Master, cata_classic (wow 4.4.x)
> Change Config.wtf: `SET portal "IP address used in realmlist table"`
> The IP in the Config.wtf file should be exactly the same as the IP address you entered in the - realmlist table above. (Example: `SET portal "127.0.0.1"`)
> Note: you will need a custom client launcher to connect to master, cata_classic branches servers, i.e. https://arctium.io/wow
> **Supported Version**
> Check https://github.com/TrinityCore/TrinityCore to find the exact client version supported by master branch.
> NOTE don't use localhost for address, if you need to connect to localhost use 127.0.0.1

（同頁 3.3.5a 段落講的是 `realmlist.wtf` 的 `set realmlist`，與 bnetserver 無關。）

重點：
- **官方唯一點名的 patcher/launcher 是 Arctium（`https://arctium.io/wow`）**，措辭是「you will need a custom client launcher」。`wow-patcher` / `wowemulation-dev` 從未出現在官方 wiki（GraphQL 全站搜尋 `patcher` / `wowpatch` 皆無命中，見 2.3）。
- **官方明確要求 `portal` 填 IP，不是 hostname**：頁面三次強調「IP address used in realmlist table」，並且反過來禁止 `localhost` 這個 hostname（`don't use localhost for address, if you need to connect to localhost use 127.0.0.1`）。這與 wow-patcher README 要求「hostname, not an IP」**方向相反**——因為 Arctium launcher 走的是繞過憑證驗證的路線，而 wow-patcher 走的是系統 trust store 路線。
- 整頁 **完全沒有提到憑證、TLS、CA、信任區**。

### 2.2 Networking / Final Server Steps

<https://trinitycore.info/en/install/Networking>：

> | Version / Branch | Service Type | Required Ports |
> | Master (Current) | Bnetserver | 1119, 8081 |
> | Master (Current) | Worldserver | 8085 |

以及 realmlist table 的 `address` 欄位要填 LAN IP / `127.0.0.1` / External IP——同樣 **全部以 IP 表述**，沒有 hostname 選項、沒有憑證段落。

<https://trinitycore.info/en/install/Final-Server-Steps>：

> Log in through a Custom Client Launcher (Not provided).:
> E-mail: `test@test`
> Password: `test`

master 分支的登入一律預設「透過第三方 custom launcher」，官方不提供、也不解釋它做了什麼。

<https://trinitycore.info/en/install/Server-Setup>：只講 extractor 與 `LoginDatabaseInfo` 等 DB 連線字串，憑證零字。

<https://trinitycore.info/en/install/Core-Installation/Docker>：docker-compose 只 expose `1119:1119` 與 `8081:8081`，沒有任何憑證掛載說明。

### 2.3 全站搜尋佐證（Wiki.js GraphQL API）

對 `https://trinitycore.info/graphql` 送 `{pages{search(query:"...")}}`，結果：

| 查詢字串 | 命中頁面 |
|---|---|
| `certificate` | **（空）** |
| `certificates` | **（空）** |
| `cert` | **（空）** |
| `TLS` | **（空）** |
| `CertificatesFile` | **（空）** |
| `trust store` | **（空）** |
| `wowpatch` | **（空）** |
| `portal` | `install/Client-Setup`（+ 3 個無關的 DB/DBC 頁） |
| `launcher` | `install/Final-Server-Steps`, `install/Client-Setup` |
| `arctium` | `install/Server-Setup` |
| `1119` | `install/Networking`, `install/Core-Installation/Docker` |
| `config.wtf` | `install/Client-Setup` |

**結論：TrinityCore 官方 wiki 全站沒有任何一頁提到 bnetserver 的憑證、TLS 或 CA 信任。**

---

## 3. `portal` cvar 的語意：TC 官方說了什麼、沒說什麼

**TC 官方文件說的**（僅此而已）：`SET portal "<IP>"`，值必須與 auth DB `realmlist.address` 一致，且不得使用 `localhost` 這個名字、要用 `127.0.0.1`。

**TC 官方文件沒說的**（不要從 TC 文件推論，這裡明確標示為「文件沉默」）：
- 沒有說明 client 對 `portal` 值的解析規則（例如「含 `.` 就逐字使用、否則當成 `<region>.actual.battle.net`」這條廣為流傳的規則，**不是** TC 文件的內容）。
- 沒有說 IP 在什麼條件下可行、什麼條件下不行。TC 只是無條件地要求填 IP，因為它預設你使用 Arctium 這類會停用憑證驗證的 launcher。
- 沒有討論 SNI、hostname 與憑證 CN/SAN 的關係。

repo 端唯一與 client 命令列相關的字串是 `bnetserver.conf.dist:74` 的

```
#                     When using client -launcherlogin feature it is recommended to set it to a high value (like a week)
```

除此之外 repo 全域 grep `portal` / `launcherlogin` 在文件與原始碼中沒有其他 client 端說明。

伺服器端與 `portal` 對應的是 `LoginRESTService::GetHostnameForClient()`（`REST/LoginRESTService.cpp:133-142`），它依來源 IP 在 `LoginREST.ExternalAddress` / `LoginREST.LocalAddress` 之間二選一，並用於：

- `HandleGetForm` 的 `srp_url`（第 173–174 行）
- `web_auth_url` external challenge（`Services/AuthenticationService.cpp:242,336`）
- 回給 client 的「連哪個 bnet 端點」字串（`LoginRESTService.cpp:233`）：
  ```cpp
  context.response.body() = Trinity::StringFormat("{}:{}", GetHostnameForClient(session->GetRemoteIpAddress()), sConfigMgr->GetIntDefault("BattlenetPort", 1119));
  ```

換言之：conf 裡填什麼字串，client 後續就會拿什麼字串去連 1119 / 8081。**若你要走 SAN 驗證路線，這兩個值必須填 hostname 而非 IP，且該 hostname 必須出現在憑證的 SAN 裡。** conf.dist 的註解卻只寫「IP address」（見第 5 節逐字引用）——這是 TC 預設部署形狀與 wow-patcher 需求衝突之處。

---

## 4. TrinityCore 有沒有教你把它的 CA 匯入 OS 信任區？

**沒有。TrinityCore 的官方文件對此完全沉默。**

- wiki 全站搜尋 `certificate` / `cert` / `TLS` / `trust store` 全部零命中（第 2.3 節）。
- repo 內 `README.md`、`doc/`（`COMPILATION_HELP.TXT`、`UnixInstall.txt`、`LoggingHOWTO.txt`、`HowToScript.txt`、`CharacterDBCleanup.txt`、`FileHeaders.txt`）皆無憑證/CA 相關說明。
- `bnetserver.conf.dist` 只說「你可以換憑證檔」，不說 client 端要怎麼信任它。

TC 實際採取的立場，只能從程式碼讀出來，而它 **兩者都不是**：

1. 它 **不** 期待你把它的 CA 匯入 OS trust store；
2. 它也 **不** 明說要 patch client 去信任它的鏈；
3. 它的實作選擇是「用內建 dev 憑證時，就把 REST 降級為明文 HTTP」（`LoginHttpSession.cpp:121`），並把 1119 的 TLS 驗證問題整個外包給第三方 launcher（wiki: 「you will need a custom client launcher」）。

所以官方預設路線 = **Arctium launcher 停用/繞過憑證驗證**，而不是任何形式的信任鏈修復。

---

## 5. `bnetserver.conf.dist` 相關區塊逐字引用（與 HermesProxy `ProxyNetworkOptions` 對照）

檔案：`/Users/shinichi/Works/side-project/TrinityCore/src/server/bnetserver/bnetserver.conf.dist`

第 51–78 行：

```
#
#    BattlenetPort
#        Description: TCP port to reach the auth server for battle.net connections.
#        Default:     1119

BattlenetPort = 1119

#
#    LoginREST.Port
#        Description: TCP port to reach the REST login method.
#        Default:     8081
#
#    LoginREST.ExternalAddress
#        Description: IP address sent to clients connecting from outside the network where bnetserver runs
#                     Set it to your external IP address
#
#    LoginREST.LocalAddress
#        Description: IP address sent to clients connecting from inside the network where bnetserver runs
#                     Set it to your local IP address (common 192.168.x.x network)
#                     or leave it at default value 127.0.0.1 if connecting directly to the internet without a router
#
#    LoginREST.TicketDuration
#        Description: Determines how long the login ticket is valid (in seconds)
#                     When using client -launcherlogin feature it is recommended to set it to a high value (like a week)
#

LoginREST.Port = 8081
LoginREST.ExternalAddress=127.0.0.1
LoginREST.LocalAddress=127.0.0.1
LoginREST.TicketDuration=3600
```

第 80–86 行：

```
#
#    BindIP
#        Description: Bind auth server to IP/hostname
#                     Using IPv6 address (such as "::") will enable both IPv4 and IPv6 connections
#        Default:     "0.0.0.0" - (Bind to all IPs on the system)

BindIP = "0.0.0.0"
```

憑證三選項見第 1.3 節。

**與 HermesProxy 的對照**：

| TrinityCore `bnetserver.conf` | HermesProxy `ProxyNetworkOptions` 對應概念 |
|---|---|
| `BattlenetPort = 1119` | proxy 的 bnet 監聽埠（永遠 TLS） |
| `LoginREST.Port = 8081` | login REST 埠（TC 用 dev 憑證時是 **明文 HTTP**） |
| `LoginREST.ExternalAddress` / `LocalAddress` | 回給 client 的位址字串——決定 client 之後拿什麼名字去連、也就決定憑證必須為哪個名字簽發 |
| `BindIP` | 監聽介面 |
| `CertificatesFile`（PEM 或 **PKCS#12 `.pfx`**） | `CertificatePfxPath` |
| `PrivateKeyFile`（PKCS#12 時留空） | （含在 pfx 內） |
| `PrivateKeyPassword` | `CertificatePfxPassword` |

TC 支援 `.pfx` 且「PKCS#12 時 `PrivateKeyFile` 留空」，與 HermesProxy 只吃 pfx 的設計完全同構；**TC 官方確實把「自備憑證」視為受支援的部署形狀**，只是從未說明 client 端該如何信任它。

---

## 6. 對本專案（HermesProxy + wow-patcher + 3.4.3 client）的可執行推論

以下為我從上述一手事實推導的結論，**不是 TC 文件的主張**，已明確標示：

1. 重用 TC 內嵌憑證（`CN=*.*`，無 SAN）在 wow-patcher 這種「走系統 trust store」的 client 上 **必定** 在憑證驗證階段失敗——現象正是 TCP 連上 1119 後未完成 TLS 即斷線。
2. 正解是自簽一條 CA → 簽一張帶 `subjectAltName = DNS:<hostname>` 的 server 憑證 → CA 匯入 Windows「受信任的根憑證授權單位」→ 匯出成 pfx 餵給 `ProxyNetworkOptions:CertificatePfxPath` / `CertificatePfxPassword`。
3. `Config.wtf` 的 `SET portal` 必須填該 hostname（而非 IP），並確保該 hostname 在 client 機器上可解析到 proxy（hosts 檔即可）。**這一步直接違反 TC wiki 的「用 IP、別用名字」指示**——因為 TC 那句話是為 Arctium launcher 寫的。
4. 若哪天改走 Arctium launcher 路線，則反過來：內嵌 `CN=*.*` 憑證可用、portal 填 IP 即可，不需要碰 trust store。兩條路線互斥，不要混用。
5. 另可留意：TC 在使用 dev wildcard 憑證時把 8081 降級為 **明文 HTTP**（`LoginHttpSession.cpp:121`）。若 HermesProxy 換上自訂憑證但仍以明文提供 login REST（或反之），client 端 `web_auth_url` 的 scheme 會對不上。這條 scheme 切換邏輯在 `master` 與 `origin/wotlk_classic` 完全相同。
