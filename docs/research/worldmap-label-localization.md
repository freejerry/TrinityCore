# 世界地圖上的區域名還是英文：有沒有現成 addon，以及兩條自建路線

> ⚠️ **更正（2026-09-04）**
>
> 本篇的核心結論**已被實測推翻**：地圖底圖可以用鬆散檔案替換，2,699 個中文貼圖已實際生效。「地形與文字是同一批像素」的敘述本身正確，但由此推出的「無解」不成立。另，本篇對 WoWInterface「Atlas World Map WOTLK Classic」插件的懷疑不成立，該插件的說法是對的。
>
> 詳見 [實作記錄與更正](./zhtw-implementation-and-corrections.md)。


> 撰寫日期：2026-09-04
> 相關筆記：[用 addon 中文化 UI 框架字串](./ui-localization-addon.md)（本篇**修正**該篇 §8「未找到任何 zhTW/zhCN UI 字串翻譯 addon」的結論 —— 找到了兩個，見 §5）、[hotfix DB2 中文化深度評估](./hotfix-db2-localization.md)（本篇處理該篇整套 hotfix 通道**打不到的最後一格**：烘進美術貼圖的字）、[zhTW 中文化能做到哪裡](./zhtw-localization.md)（本篇對該篇「CASC 無 loose-file override」的判斷提出一個**反例證據**，見 §6.1）
>
> 前提（承接前三篇，視為已知事實，本篇不重驗）：
> - client = Windows 版 WoW Classic **`3.4.3.54261`**（Wine / Apple Silicon），後端 TrinityCore 3.3.5 經 `Xian55/HermesProxy`。
> - zhTW 已經透過兩個通道生效：伺服器 `*_locale` 表，以及 proxy 推送的 **DB2 hotfix**（新寫的 loader：`GlobalStrings` 18,205 列、`AreaTable` 2,373、`UiMap` 261、`AreaPOI` 621，加上 `SpellName` 49,352、`Spell` 33,179、`SkillLine` 152），全部在 client 的 `Logs/Hotfix.log` 拿到 `VALIDATION_RESULT_VALID`。
> - 結果：法術名／描述、UI 框架字串、「你在這裡」的區域文字、世界地圖 **hover 標籤**、地圖 POI 名稱都已經是中文。
> - **剩下的問題**：畫在**世界地圖底圖本身**上的區域／地區名仍是英文 —— 也就是**烘進 `Interface/WorldMap/**/*.blp` 美術貼圖裡的字**。
>
> 來源限定 primary sources：`Gethe/wow-ui-source` 的 **`3.4.3` tag**（Blizzard 自家 FrameXML，本篇最重要的來源）、`gh api`（repo metadata / code search / raw 檔案）、CurseForge 專案頁、WoWInterface 專案頁（帶 UA 的 `curl`）、`nfuwow.com` 的分類列表、各 addon 的 repo 原始碼全文。
> 未使用瀏覽器自動化。未安裝、未執行任何 addon，未登入遊戲。凡未實測者一律標示「**未驗證**」。

---

## 0. TL;DR

1. **★ 直接回答：沒有現成的 addon 可以直接解決。** 沒有任何 addon 會「遮掉底圖上烘死的英文區域名、改畫資料驅動的中文名」。這件事在 3.4.x 上**技術上做不到「遮掉」**——原因見 §3.3。
2. **★ 但有一個比 addon 更好的東西：`Interface/WorldMap/` 這條 loose-file 覆蓋路徑，在 WotLK Classic 上有一個現成的、非本地化用途的實證專案。** WoWInterface 上的 **`Atlas World Map WOTLK Classic`**（作者 `KaptajnGejl`、95 MB、2022-07-28 更新、3,491 下載、相容性欄標 **WOTLK (3.4.0)** 與 TBC 2.5.4）的安裝說明逐字寫著：
   > "To install, place the WorldMap folder in your interface folder of your wow installation, so the structure becomes this: `World of Warcraft/_classic_/Interface/WorldMap`"

   **這是「有人在 3.4.x 上換過世界地圖貼圖」的第一手證據**，而且它不是 addon（不放進 `AddOns/`）。這對 [zhtw-localization.md](./zhtw-localization.md) 的「CASC 不能改、沒有 loose-file override」是一個需要正面處理的反例 —— 但**它有一個很硬的技術疑點，見 §6.2，我沒有能力在不登入遊戲的前提下判定它到底有沒有效。**
3. **★ 3.4.3 的世界地圖是「現代 map canvas」，不是 WotLK 的舊 WorldMapFrame。** 從 Blizzard 自己的 `3.4.3` tag 實測：底圖是 `Blizzard_MapCanvasDetailLayer.lua:55` 的 `C_Map.GetMapArtLayerTextures(mapID, layerIndex)` 拿到**一組 FileDataID**，再 `detailTile:SetTexture(textures[i], nil, nil, "TRILINEAR")`。**底圖是用 FDID 載的，不是用路徑載的** —— 這正是 §6.2 那個疑點的來源。
4. **★ 最大的意外收穫：`ZoneLabelDataProviderMixin` 這段程式碼已經在 3.4.3 的 client 裡了，只是沒有被掛上世界地圖。** `Blizzard_SharedMapDataProviders_Wrath.toc` **有列** `ZoneLabelDataProvider.xml`（實測），但 `Interface_Wrath/AddOns/Blizzard_WorldMap/Blizzard_WorldMap.lua:135-184` 的 `WorldMapMixin:OnLoad` 裡**沒有** `AddDataProvider(CreateFromMixins(ZoneLabelDataProviderMixin))`。而它的內容正是我們要的東西：
   ```lua
   local mapChildren = C_Map.GetMapChildrenInfo(mapID, Enum.UIMapType.Zone);
   for i, childMapInfo in ipairs(mapChildren) do
       local left, right, top, bottom = C_Map.GetMapRectOnMap(childMapInfo.mapID, mapID);
       self:AddZone(childMapInfo.mapID, childMapInfo.name, left, right, top, bottom);
   end
   ```
   **`childMapInfo.name` 對我們來說已經是中文了（`UiMap` hotfix 已生效）。** → 一行 `WorldMapFrame:AddDataProvider(CreateFromMixins(ZoneLabelDataProviderMixin))` 就有機會拿到中文區域標籤（**未驗證**，見 §4.2）。
5. **★ 需要的 API 全部在 3.4.3 的 Blizzard 原始碼裡確認存在**（不是從 wiki 抄的）：`C_Map.GetMapChildrenInfo`、`C_Map.GetMapRectOnMap`、`C_Map.GetMapInfo`、`C_Map.GetMapArtLayers`、`C_Map.GetMapArtLayerTextures`、`MapCanvasMixin:AddDataProvider` / `:GetCanvas()`（= `self.ScrollContainer.Child`）/ `:GetMapID()` / `:AcquireAreaTrigger()`、`MapUtil.GetMapParentInfo`。逐項出處見 §4.1。
6. **候選 addon 逐個查完，沒有一個做這件事**：`ClassicWorldMapEnhanced` 只改「hover 標籤」的內容（加等級區間），`Mapster` / `Leatrix Maps` 做的是縮放／座標／迷霧，`Cromulent` / `ZoneInfo` / `ZoneDetails` 是側邊資訊面板。明細見 §2。
7. **★ 順帶推翻前一篇的一個結論：zhCN 的 UI 翻譯 addon 是存在的，前一篇的「未找到」是搜尋面不夠廣。** 兩個第一手證據：CurseForge 的 **`Interface Translator - Chinese`**（作者 `qqytqqyt`，2026-08-28 更新，All Rights Reserved）與 GitHub 的 **`husandro/WoWTools_Chinese`**（**MIT**，2026-04-24 push）。**但兩者都幫不上這裡的忙**：前者沒有 3.4.x 檔案、後者 `## Interface: 120005`（純 retail），而且**兩者都不含任何地圖美術**。詳見 §5。
8. **一句話裁決**：**沒有現成品；兩條自建路線裡，文字疊加（text overlay）風險低得多，應該先做。** 貼圖替換的最大問題不是工作量，而是「3.4.3 用 FDID 載底圖」這個未解的疑點 —— 但它可以用**十分鐘、零程式碼**的測試一票定生死（§7.3）。

---

## 1. 問題的形狀：到底是哪一層的字

先把三種「地圖上的字」分開，因為它們的解法完全不同。這一節全部依據 `Gethe/wow-ui-source@3.4.3`（Blizzard 自家 FrameXML）。

| 層 | 由誰畫 | 資料來源 | 我們現在的狀態 |
|---|---|---|---|
| **hover 標籤**（滑鼠移到某區域，地圖上方顯示的名字） | `AreaLabelDataProvider` | `C_Map.GetMapInfoAtPosition()` → `UiMap`/`AreaTable` | ✅ **已經中文**（hotfix 生效） |
| **POI 名稱**（城鎮、地標的圖示與提示） | `AreaPOIDataProvider` | `AreaPOI` DB2 | ✅ **已經中文** |
| **底圖上烘死的字**（畫在 `.blp` 上的「Elwynn Forest」「Stormwind City」） | `MapCanvasDetailLayerMixin` 直接貼圖 | **FileDataID → CASC 的 `.blp`** | ❌ **本篇的題目** |

**第三層不是文字，是像素。** 它沒有任何 Lua 介面可以讀、改、或關掉 —— 它就是底圖的一部分。

### 1.1 底圖是怎麼載的（實測，決定性）

`Interface/AddOns/Blizzard_MapCanvas/Blizzard_MapCanvasDetailLayer.lua`（3.4.3 tag）：

```lua
local textures = C_Map.GetMapArtLayerTextures(self.mapID, self.layerIndex);
...
detailTile:SetTexture(textures[textureIndex], nil, nil, "TRILINEAR");
```

`GetMapArtLayerTextures` 回的是**一組數字（FileDataID）**，不是路徑字串。`SetTexture(<number>)` 走的是 FDID 查詢。

**這一句話同時決定了兩件事：**
1. **addon 不可能「覆蓋」底圖**（addon 只能提供 `Interface\AddOns\...` 這種**路徑**，而 client 根本沒在用路徑）。
2. **`Interface/WorldMap/` 的 loose file 能不能生效，取決於 client 在 FDID 查詢失敗前／後有沒有回頭去查「FDID 對應的檔名」的磁碟檔** —— 這是 §6.2 的核心疑點。

---

## 2. 逐一查證候選 addon（全部沒中）

全部從 repo / 專案頁第一手取得，不採信描述文案。

| 專案 | 來源 | 最後更新 | License | 支援 3.4.x？ | 它到底做什麼 | 對本題有用嗎 |
|---|---|---|---|---|---|---|
| **`GoldpawsStuff/ClassicWorldMapEnhanced`** | GitHub + CurseForge | **2024-07-10** push，★2 | `LICENSE.md` = **Custom**（自訂條款，內文為 MIT 風格的授權句 + 附加條件） | ✅ **有 `ClassicWorldMapEnhanced_Wrath.toc`，`## Interface: 30403`**（實測） | 改寫**既有 hover 標籤**（`OnUpdate_MapAreaLabel`，1016 行的 `Main.lua`）加上等級區間與陣營；玩家／游標座標；迷霧移除（`C_MapExplorationInfo.GetExploredMapTextures`）；移動時淡出 | ❌ **不畫任何新標籤。** 它接管的 `provider.Label` 就是我們**已經中文**的那一格 |
| `GoldpawsStuff/MapShrinker` | GitHub | 2024-08-17 | — | 專案描述自述為 **retail** 全螢幕地圖 | 置中、縮小、加座標、美化 | ❌ 與文字無關 |
| `Nevcairiel/Mapster` | GitHub | 2026-03-08，★21 | **無 LICENSE 檔**（repo metadata `license: null`） | **未驗證**（未逐一讀 `.toc`） | 檔案清單：`BattleMap.lua`、`Coords.lua`、`FogClear.lua`、`GroupIcons.lua` | ❌ 縮放／座標／迷霧，不碰標籤 |
| `Leatrix Maps` | CurseForge 專案頁 | 現役 | — | Classic 系列現役 | 揭圖、迷霧、副本圖示、座標、縮放、飛行點 | ❌ 專案頁列的功能裡**沒有區域名標籤** |
| `Cromulent` / `ZoneInfo Classic` / `ZoneDetails` / `Extended Map Zone Info` | CurseForge / WowAce 專案頁 | — | — | 各異 | **側邊／角落的資訊面板**（等級區間、旅行建議）。CurseForge 的 Cromulent 頁面明載 8.0 之後改成「點選區域後在左下角顯示」 | ❌ 都是面板，不是地圖上的位置標籤 |
| `Atlas World Map WOTLK Classic` | **WoWInterface `info26375`** | **2022-07-28** | **未標示** | 相容性欄：**WOTLK (3.4.0)**、TBC 2.5.4 | **95 MB 的貼圖替換**：用小地圖資料重繪世界地圖，裝進 `_classic_/Interface/WorldMap` | ⚠️ **不是本地化，但它是「貼圖路線」唯一的實證前例** —— 見 §6 |
| `husandro/WoWTools_Chinese` | GitHub | 2026-04-24 | **MIT** | ❌ `## Interface: 120005`（retail 12.0.5） | zhCN 全 UI 中文化；**有 `Data/Map_Data_UiMap.lua`（47 KB）與 `Data/AreaPOI.lua`（176 KB）**；用 `hooksecurefunc(ZoneLabelDataProviderMixin, 'EvaluateBestAreaTrigger', ...)` 換掉 ZoneLabel 文字 | ⚠️ **手法可抄（§4.3），資料不需要**（我們的 `UiMap` 已經是中文），**且完全不含美術** |

### 2.1 `ClassicWorldMapEnhanced` 值得多說兩句

它是唯一一個**確定支援 3.4.3**（`## Interface: 30403`，與 [ui-localization-addon.md](./ui-localization-addon.md) §6.2 的兩個獨立佐證同一個數字）而且**真的動世界地圖**的專案。它的 `ns.SetUpZoneLevels` 用的手法是：

```lua
for provider in next, WorldMapFrame.dataProviders do
    if provider.setAreaLabelCallback then
        provider.Label:SetScript("OnUpdate", OnUpdate_MapAreaLabel)
    end
end
```

**「遍歷 `WorldMapFrame.dataProviders`，用特徵欄位認出想改的那一個」** —— 這是在 3.4.x 上接管地圖行為的可抄樣板，§7.2 的最小 addon 會用到同一個入口（`WorldMapFrame`）。

但它處理的 `MAP_AREA_LABEL_TYPE.AREA_NAME` 就是**我們已經是中文的那一格**。它對本題**零幫助**，而且如果裝了它，它還會把中文名後面接上 `(15-25)` 這種等級區間 —— 那是加值，不是解法。

---

## 3. 為什麼「遮掉烘死的字」做不到

任務問的關鍵題是：**有沒有 addon 把底圖上烘死的英文標籤蓋掉、改畫資料驅動的？** 答案是沒有，而且原因是結構性的。

### 3.1 那些字沒有獨立圖層

`C_Map.GetMapArtLayers(mapID)` 回的是「縮放層級」（layer，不同解析度的同一張圖），不是「內容圖層」。每個 layer 底下 `GetMapArtLayerTextures` 回的是把整張圖切成方格的貼圖 —— **地形、河流、地名全部在同一組像素裡。**

### 3.2 所以「隱藏」只有兩種形式，兩種都不能用

| 做法 | 結果 |
|---|---|
| `detailTile:Hide()` / `SetAlpha(0)` | **整張底圖消失**，剩下空白畫布 |
| 在文字位置蓋一塊不透明色塊 | 要蓋掉地名就得蓋掉它底下的地形，**而且每個 mapID、每個 layer、每個地名的座標都要人工標** —— 上百張圖、上千個位置 |

### 3.3 結論（本篇最實用的一句）

> **在 3.4.x 上，「不換貼圖就讓底圖上的英文消失」是不可能的。**
> 因此「文字疊加」路線的正確目標不是**取代**那些字，而是**在它們旁邊／上面多畫一份中文**。視覺上會是「英文地名 + 中文地名並存」。這是一個要事先接受的取捨 —— 如果不能接受，那就只剩貼圖路線（§6）。

---

## 4. 路線 A：文字疊加（不動任何美術）

### 4.1 3.4.3 上**已確認存在**的 API（全部出自 Blizzard 的 `3.4.3` tag）

這一節刻意只列「我在 3.4.3 的 Blizzard 原始碼裡親眼看到被呼叫」的東西。**沒有一項來自 wiki 或記憶。**

| API / 成員 | 出處（`Gethe/wow-ui-source@3.4.3`） |
|---|---|
| `WorldMapFrame`（`WorldMapMixin`，`MapCanvasMixin` 的衍生） | `Interface_Wrath/AddOns/Blizzard_WorldMap/Blizzard_WorldMap.lua:97` `WorldMapMixin:OnLoad` → `MapCanvasMixin.OnLoad(self)` |
| `MapCanvasMixin:AddDataProvider(dataProvider)` | `Interface/AddOns/Blizzard_MapCanvas/Blizzard_MapCanvas.lua:84` |
| `MapCanvasMixin:GetCanvas()` → **`self.ScrollContainer.Child`** | 同上 `:501-503` |
| `MapCanvasMixin:GetCanvasContainer()` | 同上 `:505` |
| `MapCanvasMixin:AcquireAreaTrigger` / `SetAreaTriggerEnclosedCallback` / `SetAreaTriggerPredicate` / `ReleaseAreaTriggers` | 同上 `:230 / :247 / :257 / :262` |
| `MapCanvasMixin:AcquirePin(pinTemplate, ...)` | 同上 `:130` |
| `MapCanvasMixin:GetCanvasZoomPercent()` | 同上 `:562` |
| **`C_Map.GetMapChildrenInfo(mapID, Enum.UIMapType.Zone)`** | `Blizzard_SharedMapDataProviders/ZoneLabelDataProvider.lua:RefreshAllData` |
| **`C_Map.GetMapRectOnMap(childMapID, mapID)`** → `left, right, top, bottom`（正規化） | 同上 |
| `C_Map.GetMapInfo(mapID)` | `Blizzard_MapCanvas.lua:726`、`Blizzard_WorldMap.lua:278,533`、`FrameXML/MapUtil.lua:5,11,20` |
| `MapUtil.GetMapParentInfo(mapID, Enum.UIMapType.Continent)` | `FrameXML/MapUtil.lua:9`，被 `ZoneLabelDataProvider:AddContinent` 呼叫 |
| `C_Map.GetMapArtLayers(mapID)` | `MapExplorationDataProvider.lua:94` |
| `C_Map.GetMapArtLayerTextures(mapID, layerIndex)` | `Blizzard_MapCanvasDetailLayer.lua:55` |
| `C_MapExplorationInfo.GetExploredMapTextures(mapID)` | `MapExplorationDataProvider.lua:91` |
| `C_Map.GetMapInfoAtPosition(uiMapID, x, y)` | `ClassicWorldMapEnhanced/Main.lua:492`（第三方，但目標明確是 30403） |

**未確認**：`C_Map.GetMapHighlightInfoAtPosition` 在 3.4.3 的行為（`MapHighlightDataProvider` 有被掛上 `WorldMapFrame`，`Blizzard_WorldMap.lua:136`，但我沒有讀它的內文）。

### 4.2 ★ 最省力的一發：把 client 自己的 `ZoneLabelDataProvider` 掛上去

**實測到的事實**（兩個檔案交叉）：

- `Interface/AddOns/Blizzard_SharedMapDataProviders/Blizzard_SharedMapDataProviders_Wrath.toc` **列出了 `ZoneLabelDataProvider.xml`** → 這個 mixin 在 3.4.3 的 client 裡**被載入、存在於 `_G`**。
- `Interface_Wrath/AddOns/Blizzard_WorldMap/Blizzard_WorldMap.lua:135-184` 的 `AddDataProvider` 清單裡**沒有它**（清單裡有一大批被 `--` 註解掉的 provider，`ZoneLabelDataProviderMixin` 連註解都沒有）。

它做的事（原始碼全文讀過）：對當前地圖的每一個子地圖（zone）建一個 `AreaTrigger`，範圍取自 `C_Map.GetMapRectOnMap`；當畫面中心落在某個 zone 上、且 `GetCanvasZoomPercent() > 0.85` 時，把 `self.ZoneLabel.Text:SetText(areaTrigger.name)` 並淡入，位置由 `CalculateAnchorsForAreaTrigger` 挑地圖的某個角落；縮小時改顯示大陸名（`MapUtil.GetMapParentInfo(..., Enum.UIMapType.Continent)`）。

**對我們的意義**：`childMapInfo.name` 來自 `UiMap`，而 `UiMap` 的 261 列已經被 hotfix 換成中文。所以：

```lua
WorldMapFrame:AddDataProvider(CreateFromMixins(ZoneLabelDataProviderMixin))
```

**理論上一行就有中文區域標籤。** 三個必須講清楚的保留：

1. **未驗證**：Blizzard 把它從 Wrath 的 provider 清單裡拿掉，可能正是因為它在 Wrath 的地圖上不работ／有問題。`.toc` 有列它只代表**檔案被載入**，不代表**它在 3.4.3 的 canvas 上能跑**。
2. 它是**一次只顯示一個**、會淡入淡出的大標籤，**不是每個區域各一個標籤**。它不會蓋住底圖上的英文，只是多一個中文名。
3. 它需要 `ZoneLabelDataProvider_ZoneLabelTemplate` 這個 XML 模板存在（`.toc` 有列 `ZoneLabelDataProvider.xml`，所以應該在，**未驗證**）。

**但這是整份筆記裡「投資報酬率最高的一次嘗試」：一行程式碼，五分鐘，失敗完全可逆。**

### 4.3 退一步：自己畫每個區域一個 FontString

如果 §4.2 的一行不成立（或想要「每個區域都常駐一個中文名」而不是「一次一個」），自己畫是完全在射程內的：

```lua
-- 全部 API 已在 §4.1 確認存在於 3.4.3
local canvas = WorldMapFrame:GetCanvas()          -- = WorldMapFrame.ScrollContainer.Child
local mapID  = WorldMapFrame:GetMapID()
local w, h   = canvas:GetWidth(), canvas:GetHeight()

for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID, Enum.UIMapType.Zone)) do
    local l, r, t, b = C_Map.GetMapRectOnMap(child.mapID, mapID)   -- 正規化 0..1
    local fs = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetText(child.name)                                          -- 已經是中文
    fs:SetPoint("CENTER", canvas, "TOPLEFT", (l + r) * .5 * w, -(t + b) * .5 * h)
end
```

**要處理的四件事（都不難，但都要做）：**
- **重建時機**：地圖切換時要重畫。正解是照 Blizzard 的架構寫一個 `CreateFromMixins(MapCanvasDataProviderMixin)` 並實作 `RefreshAllData` / `RemoveAllData`，再 `WorldMapFrame:AddDataProvider(...)` —— 這樣 canvas 會替你管生命週期。`ZoneLabelDataProvider.lua` 就是逐字的樣板。
- **縮放**：`canvas` 會隨縮放改變大小，用 `CENTER` + 正規化比例定位在縮放時仍然正確（因為 `w`/`h` 要在每次刷新時重讀）。
- **字型**：`GameFontNormalLarge` 在我們的 client 上能不能出中文 —— 取決於 `Fonts/615974.slug` (`ARKai_T`) 是否掛在這個 Font 物件上。若出方塊，照 [ui-localization-addon.md](./ui-localization-addon.md) §3.1 的 `font:SetFont` 處理。**未驗證。**
- **視覺**：會和底圖上的英文名重疊。實務上把中文往下偏移 20-30 px、加陰影或半透明底就可讀了。

**taint**：這條路**只讀不寫全域、只建立自己的 FontString**，不碰 secure 程式碼，[ui-localization-addon.md](./ui-localization-addon.md) §6.1 的 taint 風險在這裡**不適用**。

---

## 5. ★ 補查：中文 UI 中文化 addon 到底存不存在（推翻前一篇的「未找到」）

[ui-localization-addon.md](./ui-localization-addon.md) §8 寫的是「**未找到**任何 zhTW 或 zhCN 的 WoW UI 框架字串翻譯 addon」，並自己註明「未找到不是不存在」。**那個保留是對的：擴大搜尋面之後找到了兩個。**

### 5.1 找到的兩個（第一手）

| 專案 | 來源 | 語言 | 最後更新 | License | 支援版本（專案頁／`.toc` 實測） | 它翻什麼 | **有地圖美術嗎** |
|---|---|---|---|---|---|---|---|
| **`Interface Translator - Chinese`**（檔名前綴 `WoWeuCN-Interface`） | **CurseForge 專案頁**（作者 `qqytqqyt` —— 與前一篇 §3 表格裡的 Quest / Tooltips Translator **同一位作者**） | **zhCN** | **2026-08-28** | **All Rights Reserved** | Retail 12.1.0、MoP Classic 5.5.4、Classic 1.15.9、**TBC Classic 2.5.6**。**檔案頁 12 個檔全部是這四個 flavor，沒有任何 3.4.x** | 專案頁自述：視窗標題、按鈕、選單、選項、系統彈窗、ESC 遊戲選單等，**不改 client 語言**（= `GlobalStrings` 覆寫路線）。單檔 6.9–7.0 MB。下載數 139 | ❌ **專案頁完全沒有提到世界地圖或美術** |
| **`husandro/WoWTools_Chinese`** | **GitHub repo**（描述：「WoW UI 中文化，仅限欧服」） | **zhCN** | **2026-04-24** push，★0，建立 2024-06-21 | **MIT** | **`## Interface: 120005`** → 純 retail 12.0.5，**完全不支援任何 Classic flavor** | 大量 `Data/*.lua` 對照表（`Map_Data_UiMap.lua` 47 KB、`AreaPOI.lua` 176 KB、`EncounterJournal_Data_Instance.lua` 73 KB、`ScenarioStepData.lua` 320 KB…），資料來源在檔頭寫明是 **`https://wago.tools/db2/UiMap?&locale=zhCN`**；手法是 `hooksecurefunc` 到各 provider | ❌ **repo 內沒有任何 `.blp` / `.tga` 地圖美術** |

**`WoWTools_Chinese/Data/AreaPOI.lua:3872` 的那一段值得記下來**，因為它就是 §4.2 那條路的第三方實證（雖然是 retail）：

```lua
hooksecurefunc(ZoneLabelDataProviderMixin, 'EvaluateBestAreaTrigger', function(self)
    if self.ZoneLabel then
        WoWTools_ChineseMixin:SetLabel(self.ZoneLabel.Text)
    end
```

**有人在真的靠 `ZoneLabelDataProviderMixin` 把地圖區域標籤換成中文。** 差別是：他要自備一張 `UiMap` 中文表（因為他的 client 是英文的），**我們不用 —— 我們的 client 端 `UiMap` 已經是中文了**。

### 5.2 這對我們**沒有用**，講清楚為什麼

> **不要為了這件事去裝 UI 翻譯 addon。**
>
> 我們的 UI 字串**已經全部是中文**了 —— 走的是自己寫的 `GlobalStrings` DB2 hotfix loader（18,205 列，`Hotfix.log` 已驗證）。這比 addon 路線**更乾淨**（[ui-localization-addon.md](./ui-localization-addon.md) §5.3 早就指出這條路「完全沒有 Lua taint 問題」），而且涵蓋率更高。
>
> 這兩個 addon 對我們唯一的價值是**方法論參考**（§5.1 那段 `hooksecurefunc`）。而在本篇真正的題目 —— **地圖美術** —— 上，**兩者都是零**。

### 5.3 「完整中文化整合包」：查了，沒有

| 搜尋面 | 可達性 | 結果 |
|---|---|---|
| **CurseForge**（`/wow/search?...&search=chinese`） | ✅ 可讀（WebFetch 200） | 命中 8 個中文相關 addon：Quest / Tooltips / **Interface** Translator（`qqytqqyt`）、`WoWTools_Chinese`、`MultiLanguage` 的 zhCN 與 **zhTW** 語言包、`DandersFrames 中文化`、`ItemNameLocalized` 的簡繁模組。**全部是文字，沒有一個提到地圖美術。** 專案頁本身對 `MultiLanguage` / `ItemNameLocalized` 我**未逐一開啟查證**（**未驗證**） |
| **WoWInterface** | ⚠️ **WebFetch 一律 403**（Cloudflare）；改用帶 UA 的 `curl` 可取得**個別專案頁**（`info26375` 成功、36 KB）；但**搜尋頁 `downloads/search.php` 只回 27 KB 的框架**，抓不到結果列表 | 只能透過搜尋引擎間接命中專案頁。已知的中文專案就是 `qqytqqyt` 的 Quest(`info25954`) / Tooltips(`info25955`) 兩支（前一篇已記） |
| **`nfuwow.com`（NFU 玩家社區）** | ✅ **可達**（`/plugin/lists.html` 回 200，伺服器端渲染，可解析） | 它有 **`WLK3.4`（catid 6）** 分類與 **`任務·地圖`（typeid 6）**、**`懒人整合包`（typeid 1）** 兩個相關子類。**兩類都抓下來逐條看過，沒有任何中文化／漢化／地圖美術包** —— 清單是 `Dominos`、`Plater`、`TSM`、`GatherMate2`、`Auctionator` 這類通用 addon 的適配版。**這個負面結果是合理的：NFU 服務的是簡中玩家，他們的 client 本來就是中文的，不需要漢化。** |
| **Gitee** | ❌ **不可達**：`https://gitee.com/explore` 回 **HTTP 405**（不接受本次的請求方式）。**沒有查。** |
| **GitHub repo search（中文關鍵字）** | ❌ **技術失敗**：`gh api "search/repositories?q=wow+addon+汉化"` 回 `invalid character '<'`（[ui-localization-addon.md](./ui-localization-addon.md) §10 記過同一個坑：含非 ASCII 的 query 必須用 `-X GET -f q=`）。**本次沒有改用正確形式重試 —— 這是本篇搜尋覆蓋率的一個已知缺口。** |
| **GitHub code search** | ✅ 用 `ZoneLabelDataProviderMixin` 反查，**就是這樣撈到 `WoWTools_Chinese` 的** |

**負面結論的誠實版本：**

> **在 CurseForge 與 nfuwow 這兩個可完整讀取的來源上，沒有任何「完整中文化整合包」，也沒有任何中文 addon 附帶世界地圖美術。**
> **WoWInterface 的搜尋頁抓不到、Gitee 回 405、GitHub 的中文 repo search 因為 query 編碼失敗而沒跑成** —— 這三個面是**沒查到**，不是**查了沒有**。

---

## 6. 路線 B：貼圖替換 —— 有前例，但有一個沒解決的疑點

### 6.1 前例是真的（第一手，WoWInterface 專案頁）

`https://www.wowinterface.com/downloads/info26375.html`（帶 UA 的 `curl` 取得，200）：

| 欄位 | 值 |
|---|---|
| 名稱 | **Atlas World Map WOTLK Classic** |
| 作者 | `KaptajnGejl` |
| 版本 | `3.4.*` |
| 大小 | **95 MB** |
| 相容性 | **WOTLK (3.4.0)**、TBC Patch (2.5.4) |
| 建立 / 更新 | 2022-07-26 / **2022-07-28** |
| 下載 | **3,491** |
| License | **未標示** |
| 留言 | **0 則** |

安裝說明（逐字）：

> "To install, place the WorldMap folder in your interface folder of your wow installation, so the structure becomes this: `World of Warcraft/_classic_/Interface/WorldMap`"

**這對前面筆記的意義**：[zhtw-localization.md](./zhtw-localization.md) §2.5 的結論是「CASC 沒有第三方寫入路徑」。**那句話仍然正確** —— 這個專案沒有改 CASC，它是把檔案放在 CASC **旁邊**的 `Interface/` 目錄，走的是 client 的 loose-file 覆蓋機制，跟 addon 一樣是官方留的口。**[ui-localization-addon.md](./ui-localization-addon.md) §1 實測「`_classic_/Interface/` 底下只有 `AddOns/`」也仍然正確** —— 只是那代表「目前沒人放東西進去」，不代表「放了不會生效」。

### 6.2 ★ 但有一個我沒能解決的疑點：FDID vs. 路徑

§1.1 的實測擺在那裡：3.4.3 的底圖是 `SetTexture(<FileDataID>)` 載的。

**loose-file 覆蓋是以「路徑」為 key 的機制。** 所以：

| 情況 | 後果 |
|---|---|
| client 在解析 FDID 時會先把 FDID 映回 CASC 的檔名（`interface/worldmap/azeroth/azeroth1.blp`），再檢查磁碟上有沒有同路徑的 loose file | ✅ 貼圖路線成立，而且**完全不需要寫 addon** |
| client 對 FDID 直接走 CASC 索引，不經過檔名 | ❌ 貼圖路線在 3.4.x 上**根本不成立**，`Atlas World Map WOTLK Classic` 對 3.4.x 其實是無效的 |

**我沒有辦法在不登入遊戲的前提下判定是哪一種。** 而 `Atlas World Map WOTLK Classic` 這個證據**比看起來弱**：

- 更新日期是 **2022-07-28**，正是 **3.4.0 beta 期間**（專案頁自己寫「Obviously the Northrend maps can only be viewed with beta access at the moment」）。
- **0 則留言** —— 沒有任何使用者回報它在正式版 3.4.x 上有效或無效。
- 相容性欄的 `WOTLK (3.4.0)` 是**作者自填的**，不是平台驗證的。

> **判讀：這是「有人試過」的證據，不是「有效」的證據。**

### 6.3 zhTW 3.3.5a 的美術來源（未驗證）

前提裡提到本機有一套 zhTW 3.3.5a client，`Data/zhTW/` 有 2.5 GB。**理論上**繁中的世界地圖美術就在裡面（3.3.5a 的 locale 美術放在 `Data/<locale>/locale-<locale>.MPQ` 與 `patch-<locale>-*.MPQ`）。

**全部未驗證：**
- **未驗證**：那 2.5 GB 裡真的有 `Interface\WorldMap\**\*.blp`（我沒有列過那台機器的 MPQ 內容）。
- **未驗證**：3.3.5a 的分割方式（每張區域圖切成幾塊、每塊多大）與 3.4.3 的 `GetMapArtLayerTextures` 回的張數是否一致。3.4.x 引入了**多 layer（多解析度）**，3.3.5a 只有一層 —— **這幾乎可以確定是不一致的**，也就是說即使路徑機制成立，也還要重新切圖。
- **未驗證**：`mapID`（3.4.x 的 UiMapID）與 3.3.5a 的地圖檔名目錄結構的對應。
- **未找到**：任何專案／文章記載「從本地化的 3.3.5a client 抽出 `Interface/WorldMap` 美術、拿到現代 Classic client 上用」。搜尋只命中 3.3.5a **自身**的美術替換教學（Warmane 論壇的 HD remaster 系列）與 `BLPConverter`（WoWInterface `info14110`）。**這件事沒有前例。**

---

## 7. 裁決與下一步

### 7.1 裁決

> ## **沒有現成 addon。兩條自建路線裡，先做「文字疊加」。**
>
> | 路線 | 工作量 | 最大風險 | 可逆性 | 結果長什麼樣 |
> |---|---|---|---|---|
> | **A. 文字疊加**（本篇推薦） | **§4.2 一行；§4.3 約 60 行** | 字型能不能出中文（有已知解法）；`ZoneLabelDataProvider` 在 3.4.3 是否可用（未驗證） | 刪一個資料夾 | 底圖英文**仍在**，旁邊多一份中文 |
> | **B. 貼圖替換** | **高**：抽 MPQ + 重新切圖 + 對 mapID/layer 映射；且 §6.3 全部未驗證 | **§6.2 的 FDID 疑點可能讓整條路歸零**，而且是在做完所有工作之後才會知道 | 刪 `Interface/WorldMap/` | 底圖英文**被換成中文**（真正的解） |
>
> **為什麼 A 是低風險的那一條，三個理由：**
> 1. **所有需要的 API 都在 Blizzard 自己的 3.4.3 原始碼裡確認過**（§4.1），不是推測。
> 2. **它沒有二元的成敗**：就算 `ZoneLabelDataProvider` 不能用，§4.3 自己畫 FontString 是純 addon 標準操作，不依賴任何未驗證的 client 行為。
> 3. **B 的關鍵未知在最後才會揭曉**。§6.2 那個疑點如果是壞的一邊，抽 MPQ、切圖、對映射的工作全部作廢。
>
> **但 A 有一個必須先接受的取捨（§3.3）：它不能讓底圖上的英文消失。** 如果「地圖上必須只有中文」是硬需求，那 A 不合格，只能賭 B —— 而在那之前，**一定要先跑 §7.3 的十分鐘測試**。

### 7.2 路線 A 的最小 addon

```
~/World of Warcraft 3.4.3.54261/_classic_/Interface/AddOns/zhTWMapLabels/
├── zhTWMapLabels.toc
└── main.lua
```

**`zhTWMapLabels.toc`**（`30403` 的兩個獨立佐證見 [ui-localization-addon.md](./ui-localization-addon.md) §6.2）：
```
## Interface: 30403
## Title: zhTW Map Labels
## Version: 0.1

main.lua
```

**`main.lua` —— 先試最省力的那一行，失敗才走自己畫：**
```lua
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    -- ① Blizzard 自己的 provider（3.4.3 的 .toc 有載入它，但沒掛上 WorldMapFrame）
    if ZoneLabelDataProviderMixin and WorldMapFrame then
        WorldMapFrame:AddDataProvider(CreateFromMixins(ZoneLabelDataProviderMixin))
        DEFAULT_CHAT_FRAME:AddMessage("zhTWMapLabels: ZoneLabelDataProvider attached")
    else
        DEFAULT_CHAT_FRAME:AddMessage("zhTWMapLabels: ZoneLabelDataProviderMixin missing")
    end
end)
```

**② 若 ① 沒有畫出任何東西**，把 `main.lua` 換成 §4.3 的樣子，但**照 Blizzard 的架構包成 provider**（這樣地圖切換時 canvas 會自動呼叫你）：

```lua
local Labels = CreateFromMixins(MapCanvasDataProviderMixin)   -- 3.4.3 有此 mixin

function Labels:RemoveAllData()
    if self.pool then for _, fs in ipairs(self.pool) do fs:Hide() end end
end

function Labels:RefreshAllData()
    self:RemoveAllData()
    self.pool = self.pool or {}

    local map    = self:GetMap()
    local canvas = map:GetCanvas()                    -- = ScrollContainer.Child
    local mapID  = map:GetMapID()
    local w, h   = canvas:GetWidth(), canvas:GetHeight()
    local n      = 0

    for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID, Enum.UIMapType.Zone) or {}) do
        local l, r, t, b = C_Map.GetMapRectOnMap(child.mapID, mapID)
        if l and (r - l) > 0 and (b - t) > 0 then
            n = n + 1
            local fs = self.pool[n]
            if not fs then
                fs = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                self.pool[n] = fs
            end
            fs:SetParent(canvas)
            fs:ClearAllPoints()
            -- 往下偏 24px，避開底圖上烘死的英文名（§3.3：蓋不掉，只能並排）
            fs:SetPoint("CENTER", canvas, "TOPLEFT",
                        (l + r) * .5 * w, -((t + b) * .5 * h) - 24)
            fs:SetText(child.name)                     -- UiMap hotfix → 已是中文
            fs:Show()
        end
    end
end

WorldMapFrame:AddDataProvider(Labels)
```

### 7.3 ★ 路線 B 的十分鐘生死測試（做 B 之前必跑）

> **不要先去抽 2.5 GB 的 MPQ。先花十分鐘證明 loose-file 對「底圖」有沒有效。**
>
> 1. 用 `wago.tools` 的檔案索引查一張已知的世界地圖底圖 tile 的**檔名與 FileDataID**（例如艾爾文森林的第一塊）。**這一步本篇未做，索引查得到 —— [ui-localization-addon.md](./ui-localization-addon.md) §9 有可重跑的 `wago.tools/files` 解析腳本。**
> 2. 隨便做一張**顏色鮮豔到不可能看錯**的 `.blp`（用 `BLPConverter`，WoWInterface `info14110`），存到 `~/World of Warcraft 3.4.3.54261/_classic_/Interface/WorldMap/<那個檔名>`。
> 3. 進遊戲，開世界地圖到該區域。
>
> | 結果 | 意義 | 下一步 |
> |---|---|---|
> | **看到那塊鮮豔色塊** | **loose-file 覆蓋對 FDID 載入的底圖有效** → §6.2 的疑點結案為「好的那一邊」，路線 B 成立，而且**完全不需要寫 addon** | 去抽 3.3.5a zhTW 的 `Interface\WorldMap`，處理 §6.3 的切圖／layer 映射 |
> | **底圖沒變** | **client 對 FDID 不查磁碟** → **路線 B 在 3.4.x 上死亡**，`Atlas World Map WOTLK Classic` 對 3.4.x 是無效的 | 只做路線 A，接受「中英並排」 |
> | 地圖破圖 / client 崩潰 | 檔案格式或尺寸不對 | 刪檔即復原；先確認 `.blp` 的壓縮格式與 mipmap |
>
> **代價：刪一個檔。** 這一步應該排在**任何**貼圖工作之前 —— 它用十分鐘決定要不要投入好幾天。

### 7.4 建議的執行順序

1. **§7.2 的 ①（一行）** —— 五分鐘，可能直接就有中文區域標籤。
2. **§7.3 的貼圖生死測試** —— 十分鐘，決定路線 B 的命運。
3. 視 1 的結果決定要不要寫 §7.2 的 ②。
4. 只有在 2 是「好的那一邊」、而且不能接受中英並排時，才投入 §6.3 的抽圖工程。

---

## 8. 明確記錄「未驗證」

- **未驗證**：`ZoneLabelDataProviderMixin` 在 3.4.3 的 `WorldMapFrame` 上實際能不能跑。已證的只有「`Blizzard_SharedMapDataProviders_Wrath.toc` 有列 `ZoneLabelDataProvider.xml`」與「`WorldMapMixin:OnLoad` 沒有掛它」兩件事。**Blizzard 把它拿掉可能就是因為它在 Wrath 地圖上有問題。**
- **未驗證（本篇最重要的一項）**：3.4.3 client 對 `SetTexture(<FileDataID>)` 是否會回頭檢查 `Interface/` 底下的 loose file。整條路線 B 押在這一題上（§6.2）。
- **未驗證**：`Atlas World Map WOTLK Classic` 在 **3.4.3.54261 正式版**上是否真的有效。專案頁的相容性欄是作者自填、更新於 3.4.0 beta 期間、0 則留言。
- **未驗證**：本機 zhTW 3.3.5a client 的 `Data/zhTW/` 裡是否真的有 `Interface\WorldMap` 美術；以及 3.3.5a 的分割方式與 3.4.x 的 layer/tile 結構是否相容（**幾乎確定不相容**，3.4.x 有多 layer）。
- **未驗證**：`GameFontNormalLarge` 等 Font 物件在本機 client 上能否直接渲染中文（若不行，照 [ui-localization-addon.md](./ui-localization-addon.md) §3.1 的 `font:SetFont` 處理）。
- **未驗證**：`C_Map.GetMapHighlightInfoAtPosition` 在 3.4.3 的行為（`MapHighlightDataProvider` 確實有被掛上 `WorldMapFrame`，但我沒讀它的內文）。
- **未驗證**：`Mapster` 是否支援 3.4.x（沒有逐一開它的 `.toc`）；CurseForge 上的 `MultiLanguage` 語言包與 `ItemNameLocalized` 中文模組的專案頁細節（只從搜尋結果摘要看到名稱與一句描述）。
- **未查（搜尋覆蓋率的已知缺口，三項）**：
  - **Gitee** —— `https://gitee.com/explore` 回 **HTTP 405**，完全沒查。
  - **WoWInterface 的搜尋頁** —— WebFetch 403、帶 UA 的 `curl` 只回 27 KB 框架，抓不到結果列表；只能經搜尋引擎間接命中個別專案頁。
  - **GitHub 的中文關鍵字 repo search** —— `gh api` 對含非 ASCII 的 query 回 `invalid character '<'`，**本次沒有改用 `-X GET -f q=` 重試**。
- **未做**：沒有安裝或執行任何 addon；沒有登入遊戲；沒有下載或開啟任何 `.blp`；沒有列過 zhTW 3.3.5a client 的 MPQ 內容；沒有查任何一張地圖 tile 的 FileDataID。
- **未評估**：把 Blizzard 的 zhTW 地圖美術從一個 client 抽出、放進另一個 client 的授權問題。**個人本機使用與公開再散布是兩回事**（同前三篇的一貫立場）。

---

## 9. 驗證指令（可重跑，全部唯讀）

```bash
# ---- ★ 本篇的骨幹：Blizzard 自己的 3.4.3 FrameXML ----
R=https://raw.githubusercontent.com/Gethe/wow-ui-source/3.4.3
gh api "repos/Gethe/wow-ui-source/tags?per_page=100" --jq '.[].name' | grep '^3\.4'
#   → 3.4.3 / 3.4.2 / 3.4.1

# 底圖是用 FileDataID 載的（§1.1，決定性）
curl -sL "$R/Interface/AddOns/Blizzard_MapCanvas/Blizzard_MapCanvasDetailLayer.lua" \
  | grep -n "GetMapArtLayerTextures\|SetTexture"
#   55: C_Map.GetMapArtLayerTextures(self.mapID, self.layerIndex)
#   62: detailTile:SetTexture(textures[textureIndex], nil, nil, "TRILINEAR")

# ZoneLabelDataProvider 有被載入…
curl -sL "$R/Interface/AddOns/Blizzard_SharedMapDataProviders/Blizzard_SharedMapDataProviders_Wrath.toc" \
  | grep -n ZoneLabel
# …但沒有被掛上 WorldMapFrame
curl -sL "$R/Interface_Wrath/AddOns/Blizzard_WorldMap/Blizzard_WorldMap.lua" \
  | sed -n '130,190p' | grep -n "AddDataProvider"
curl -sL "$R/Interface_Wrath/AddOns/Blizzard_WorldMap/Blizzard_WorldMap.lua" \
  | grep -c "ZoneLabelDataProviderMixin"        # → 0

# 它內部用的正是我們要的兩個 API
curl -sL "$R/Interface/AddOns/Blizzard_SharedMapDataProviders/ZoneLabelDataProvider.lua" \
  | sed -n '/RefreshAllData/,/AddContinent()/p'

# MapCanvasMixin 的入口（§4.1 逐項）
curl -sL "$R/Interface/AddOns/Blizzard_MapCanvas/Blizzard_MapCanvas.lua" -o mc.lua
grep -n "function MapCanvasMixin:\(AddDataProvider\|GetCanvas\|AcquireAreaTrigger\|AcquirePin\|GetCanvasZoomPercent\)" mc.lua
curl -sL "$R/Interface/FrameXML/MapUtil.lua" | grep -n "GetMapParentInfo\|C_Map.GetMapInfo"

# ---- 候選 addon（§2）----
gh api repos/GoldpawsStuff/ClassicWorldMapEnhanced \
  --jq '{pushed_at,license:.license.spdx_id,stars:.stargazers_count}'
C=https://raw.githubusercontent.com/GoldpawsStuff/ClassicWorldMapEnhanced/master/ClassicWorldMapEnhanced
curl -sL $C/ClassicWorldMapEnhanced_Wrath.toc | head -1     # ## Interface: 30403
curl -sL $C/Main.lua | grep -n "OnUpdate_MapAreaLabel\|GetMapInfoAtPosition\|setAreaLabelCallback"
gh api repos/Nevcairiel/Mapster --jq '{pushed_at,license:.license.spdx_id}'

# ---- ★ 貼圖路線的前例（§6.1）----
curl -s -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
     "https://www.wowinterface.com/downloads/info26375.html" -o atlas.html
python3 - <<'EOF'
import re,html
t=open('atlas.html',encoding='utf-8',errors='replace').read()
t=re.sub(r'<script.*?</script>|<style.*?</style>','',t,flags=re.S)
t=html.unescape(re.sub(r'<[^>]+>','\n',t))
i=t.find('To install'); print(t[i:i+260])
EOF
#   → "place the WorldMap folder in your interface folder ... _classic_/Interface/WorldMap"

# ---- ★ 中文 UI addon 是存在的（§5，推翻前一篇）----
gh api "search/code?q=%22ZoneLabelDataProviderMixin%22+language:lua&per_page=20" \
  --jq '.items[]|"\(.repository.full_name) \(.path)"' | grep -i chinese
#   → husandro/WoWTools_Chinese Data/AreaPOI.lua
gh api repos/husandro/WoWTools_Chinese \
  --jq '{description,license:.license.spdx_id,pushed_at,created_at}'
#   → MIT, 2026-04-24, "WoW UI 中文化，仅限欧服"
H=https://raw.githubusercontent.com/husandro/WoWTools_Chinese/main
curl -sL $H/WoWTools_Chinese.toc | head -3                  # ## Interface: 120005（retail）
curl -sL $H/Data/AreaPOI.lua | sed -n '3872,3876p'          # hooksecurefunc(ZoneLabelDataProviderMixin, ...)
curl -sL $H/Data/Map_Data_UiMap.lua | head -8               # 資料來源 = wago.tools/db2/UiMap?&locale=zhCN
# CurseForge 專案頁（WebFetch，200）
#   https://www.curseforge.com/wow/addons/interface-translator-chinese
#   https://www.curseforge.com/wow/addons/interface-translator-chinese/files   ← 12 檔，無 3.4.x

# ---- nfuwow：可達，但沒有中文化／地圖包（§5.3）----
curl -s -A "Mozilla/5.0" "https://www.nfuwow.com/plugin/lists.html" -o nfu.html   # 200
#   catid 6 = WLK3.4；typeid 1 = 懒人整合包，typeid 6 = 任务·地图
curl -s -A "Mozilla/5.0" "https://www.nfuwow.com/plugin/lists/catid/6/typeid/6.html" | \
  grep -oE 'href="/plugin/detail/artid/[0-9]+\.html"[^>]*>[^<]{1,60}'

# ---- 取用失敗的來源（如實記錄）----
curl -s -o /dev/null -w "%{http_code}\n" -A "Mozilla/5.0" "https://gitee.com/explore"   # 405
curl -s -o /dev/null -w "%{http_code}\n" -A "Mozilla/5.0" "https://www.curseforge.com/wow/addons/mapster"  # 403
gh api "search/repositories?q=wow+addon+汉化"     # invalid character '<'（需 -X GET -f q=）
```

---

## 10. 實際取用過的來源

**`Gethe/wow-ui-source` 的 `3.4.3` tag（第一手，Blizzard 自家 FrameXML —— 本篇最重要的來源）**
- `Interface/AddOns/Blizzard_MapCanvas/Blizzard_MapCanvasDetailLayer.lua:55,62`（底圖 = FDID + `SetTexture`）
- `Interface/AddOns/Blizzard_MapCanvas/Blizzard_MapCanvas.lua`（798 行；`AddDataProvider:84`、`AcquirePin:130`、`AcquireAreaTrigger:230`、`SetAreaTriggerEnclosedCallback:247`、`SetAreaTriggerPredicate:257`、`ReleaseAreaTriggers:262`、`GetCanvas:501`、`GetCanvasContainer:505`、`GetCanvasZoomPercent:562`、`C_Map.GetMapInfo:726`）
- `Interface/AddOns/Blizzard_SharedMapDataProviders/ZoneLabelDataProvider.lua`（**全文**）
- `Interface/AddOns/Blizzard_SharedMapDataProviders/Blizzard_SharedMapDataProviders_Wrath.toc`（**全文**；含 `ZoneLabelDataProvider.xml`）
- `Interface/AddOns/Blizzard_SharedMapDataProviders/MapExplorationDataProvider.lua:91,94`
- `Interface_Wrath/AddOns/Blizzard_WorldMap/Blizzard_WorldMap.lua`（723 行；`OnLoad:97`、`AddDataProvider` 清單 `:135-184`）
- `Interface/AddOns/Blizzard_WorldMap/Blizzard_WorldMap_Wrath.toc`（全文）
- `Interface/FrameXML/MapUtil.lua`（`GetMapParentInfo:9`、`GetDisplayableMapForPlayer:56`）
- 檔案樹（`git/trees/3.4.3?recursive=1`，1,782 筆）

**`GoldpawsStuff/ClassicWorldMapEnhanced`（第一手）**
- `ClassicWorldMapEnhanced_Wrath.toc`（`## Interface: 30403`）、`Main.lua`（1,016 行；`OnUpdate_MapAreaLabel:483`、`ns.SetUpZoneLevels:831`、overlay 貼圖處理 `:363-478`）、`LICENSE.md`（Custom）、repo metadata（pushed 2024-07-10、★2、`NOASSERTION`）

**`husandro/WoWTools_Chinese`（第一手）**
- repo metadata（**MIT**、pushed 2026-04-24、created 2024-06-21、★0）、檔案樹、`WoWTools_Chinese.toc`（`## Interface: 120005`）、`Data/AreaPOI.lua:3872`（`hooksecurefunc(ZoneLabelDataProviderMixin, 'EvaluateBestAreaTrigger', ...)`）、`Data/Map_Data_UiMap.lua`（檔頭註明資料來自 `wago.tools/db2/UiMap?&locale=zhCN`）

**`Nevcairiel/Mapster`（第一手）**
- repo metadata（pushed 2026-03-08、★21、`license: null`）、檔案清單

**專案頁（first-party listing）**
- `https://www.wowinterface.com/downloads/info26375.html` —— **Atlas World Map WOTLK Classic**（95 MB、WOTLK 3.4.0、2022-07-28、3,491 下載、0 留言、安裝到 `_classic_/Interface/WorldMap`）
- `https://www.curseforge.com/wow/addons/interface-translator-chinese` 與 `/files` —— **Interface Translator - Chinese**（`qqytqqyt`、2026-08-28、All Rights Reserved、139 下載、四個 flavor 無 3.4.x）
- `https://www.curseforge.com/wow/search?...&search=chinese` —— 中文 addon 清單（8 個命中）
- `https://www.wowinterface.com/downloads/info14110-BLPConverter.html` —— `.blp` ↔ `.png` 轉換工具（僅記錄存在，未使用）
- `https://www.nfuwow.com/plugin/lists.html` 與 `/plugin/lists/catid/6/typeid/{1,6}.html` —— WLK3.4 的整合包與任務·地圖分類（**無中文化／地圖包**）

**GitHub code search（第一手，`gh api`）**
- `"ZoneLabelDataProviderMixin" language:lua` → 撈到 `husandro/WoWTools_Chinese`
- `"C_Map.GetMapRectOnMap"` / `"C_Map.GetMapChildrenInfo"` → 佐證 `Questie`（支援 Classic 系列）的 `Libs/HereBeDragons-2.0.lua` 也在用這兩個 API

**取用失敗（如實記錄）**
- `gitee.com` —— `/explore` 回 **HTTP 405**，**完全沒查**。
- `wowinterface.com/downloads/search.php` —— 帶 UA 的 `curl` 只回 27 KB 的頁框，抓不到結果列表；WebFetch 一律 **403**（Cloudflare）。個別專案頁（`info26375`）帶 UA 可取。
- `curseforge.com` 對帶 UA 的 `curl` 回 **403**；改用 WebFetch 可取（200）。
- `gh api "search/repositories?q=wow+addon+汉化"` → `invalid character '<'`。含非 ASCII 的 query 必須用 `-X GET -f q=`（[ui-localization-addon.md](./ui-localization-addon.md) §10 記過同一個坑），**本次未重試**。
