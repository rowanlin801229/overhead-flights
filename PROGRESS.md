# Overhead Flights — 進度紀錄

**日期：** 2026-07-28（收工快照）  
**作者：** Rowan（作品集）  
**狀態：** 本機可用、已選為系統螢保、真飛機 + AppKit 字 + Etheral Shadow 風格背景  
**下次第一優先：推上 GitHub，整理成可分享給朋友的安裝路徑**  

---

## 一句話產品

**頭頂航班：** 極簡環境顯示——安靜秀出正飛過你頭頂的最近一班飛機。  
產品定位是 **替換螢保「內容」**；**啟動等待時間**由使用者在系統設定自行決定（本機目前 `idleTime = 60` 秒）。

**使用位置：** 英國倫敦 **Wembley Park**（無 GPS 時 fallback 同座標）。

---

## 下次開工必讀（給 AI / 自己）

> **使用者 2026-07-28 交代：**  
> 1. **下次要推上 GitHub，分享給朋友** —— 優先於動畫微調  
> 2. **文字大小／排版已滿意，不要再改文字**（除非使用者再說）  
> 3. 背景已對齊 Etheral Shadow 方向；可再微調，但分享路徑優先  

分享成功定義見文末。

---

## 架構定案（重要）

螢保全螢幕採 **雙層原生**，**不要**改回「純 WebView 畫字／畫背景」當主路徑：

| 層 | 技術 | 職責 |
|----|------|------|
| 底 | **`OFEtherealBGView`（AppKit + Core Image）** | Etheral Shadow 風格：灰 mask 形狀 + 扭曲流動 + noise 貼圖 |
| 上 | **AppKit `NSTextField`** | monogram / callsign / airline / meta |
| 資料 | **原生 `NSURLSession`** | airplanes.live，90 秒輪詢，半徑 40 km |

### 為什麼（踩過的坑）

1. WebView `fetch` 在 `legacyScreenSaver` 不可靠 → 資料用原生  
2. WebView 能 inject 但文字 rAF／opacity 卡死 → **字用 AppKit**  
3. WebView 背景（HTML／Canvas／遠端 mask）在螢保裡常 **完全不畫** → **背景也改原生 CI**  
4. 定位服務列表通常 **沒有** legacyScreenSaver → **不依賴 GPS**；fallback Wembley  
5. 系統設定 **小預覽格** = 假 stub；真資料只在全螢幕螢保  

### 文字（凍結）

> **2026-07-28：文字大小很剛好，不要改到文字。**

含：字級比例（約高度 × 10%）、字重、銀白層級、字距、垂直位置、間距。  
可動：背景、資料、文件、建置／GitHub／分享文案。

### 背景（Etheral Shadow）

- 參考：[Etheral Shadow — Jatin Yadav / 21st.dev](https://21st.dev/@jatin-yadav05/components/etheral-shadow)  
- Demo 參數：`color rgba(128,128,128,1)`、`animation scale 100 speed 90`、`noise opacity 1 scale 1.2`、`sizing fill`  
- 資產：`macos/Assets/etheral-mask.png`、`etheral-noise.png` → 建置進 `Web/`  
- 實作：Core Image mask + 雙重 displacement + soft 疊加（非 WebView）  
- `shader-bg.html` 仍在 repo（實驗／網頁參考），**螢保主路徑不依賴它**  

### 顯示壽命（給朋友說明用）

| 問題 | 答案 |
|------|------|
| 多久出現？ | **使用者**在系統設定設「啟動螢幕保護程式」 |
| 有飛機時？ | **持續顯示**，約 90 秒更新；不是 15 秒就關 |
| 沒飛機？ | **全黑**（仍在螢保裡，不是結束） |
| 螢幕關電？ | 系統「關閉顯示器」設定，與本專案無關 |

---

## 已完成 ✅

### 核心網頁（`index.html`）

- [x] airplanes.live + adsbdb  
- [x] 半徑 ~40 km、高度 ≥ 500 m、90 秒輪詢  
- [x] S1 長駐、prologue、換班、WebGL 背景（網頁版）  
- [x] 原生 feed 橋接 API（給實驗／網頁）  

### macOS 螢保（`macos/`）— **主路徑**

- [x] `.saver` + `build-and-install.sh` → `~/Library/Screen Savers/`  
- [x] 系統已選 **Overhead Flights**  
- [x] 原生拉飛機 + **AppKit 字**（已驗證多班真 callsign）  
- [x] Fallback **Wembley Park** `51.5578, -0.2795`  
- [x] 半徑 **40 km**  
- [x] 設定頁 stub 預覽  
- [x] 縮圖 thumbnail  
- [x] Log：`/tmp/OverheadFlights.log` + 容器路徑  
- [x] impeccable：`PRODUCT.md` / `DESIGN.md`  
- [x] **Etheral Shadow 風格原生背景**（mask + noise 資產 + CI）  

### 文件

- [x] `overhead-flights-spec.md`、`README.md`、`SKILL.md`、`PROGRESS.md`  
- [x] `PRODUCT.md`、`DESIGN.md`  

### 備援

- [x] `macos-app/` 全螢幕 App（非正式主路徑）  

---

## 明確不做／已撤回 ❌

| 項目 | 原因 |
|------|------|
| 閒置 LaunchAgent 開 App | 只要替換螢保內容 |
| 強制改使用者 idle 時間 | 尊重系統設定 |
| 純 WebView 當螢保主 UI | 字／背景都不穩 |
| 要求使用者在定位服務找 legacyScreenSaver | 系統常不顯示 |

---

## 已知限制 ⚠️

1. 第三方螢保在「自訂」區  
2. **未簽名** → 朋友安裝可能遇 Gatekeeper（`xattr -dr com.apple.quarantine …`）  
3. 無 GPS → 用 Wembley／預設座標（分享時應說明可改）  
4. 原生層航司多靠 ICAO 前綴；adsbdb 航線網頁版較完整  
5. 僅 macOS `.saver`  
6. 無機 = 全黑（設計如此）  
7. **尚未 `git init` / 未推 GitHub**（下次主線）  

---

## 本機狀態（2026-07-28）

| 項目 | 狀態 |
|------|------|
| 安裝 | `~/Library/Screen Savers/OverheadFlights.saver` |
| 系統選中 | Overhead Flights |
| idle | **60 秒**（使用者可改） |
| 文字 | **凍結—勿改** |
| 背景 | 原生 Etheral（bundle 內含 mask/noise） |
| Git | **尚無 `.git`** |

### 重裝／除錯

```bash
cd "/Users/linyuxian/Desktop/新作品集/overhead flights/macos"
./build-and-install.sh

cat /tmp/OverheadFlights.log | tail -30
```

成功示例：`etheral assets loaded`、`ethereal bg native installed`、`UI show …`、`nearest=…`

---

## 目錄結構（分享前）

```
overhead flights/
├── index.html                 # 網頁完整版
├── shader-bg.html             # 舊／實驗用 Web 背景（螢保主路徑不用）
├── PRODUCT.md / DESIGN.md
├── PROGRESS.md                # 本檔
├── SKILL.md / README.md / overhead-flights-spec.md
├── macos/
│   ├── build-and-install.sh   # 朋友安裝入口
│   ├── Assets/                # etheral-mask.png, etheral-noise.png
│   ├── OverheadFlightsView.m  # 主邏輯
│   ├── OverheadFlights.xcodeproj/
│   └── Web/                   # 建置時產生，勿手改當源、勿提交
└── macos-app/                 # 備援 App
```

**勿提交：** `macos/build/`、`macos/Web/`、`macos-app/build/`、`macos-app/dist/`、`.DS_Store`

---

## 下次工作：推 GitHub 分享朋友（優先序）

1. [ ] 確認／補齊 `.gitignore`（build、Web 產物、dist）  
2. [ ] 清理實驗殘留說明（idle-watch 等標註或移出主線）  
3. [ ] **README** 改成「朋友 3 步驟」：  
   - 需要 Mac + Xcode  
   - `git clone` → `cd macos` → `./build-and-install.sh`  
   - 系統設定 → 自訂 → Overhead Flights；**自己設啟動時間**  
   - Gatekeeper：`xattr -dr com.apple.quarantine ~/Library/Screen\ Savers/OverheadFlights.saver`  
4. [ ] **SKILL.md** 對齊現架構（AppKit 字 + 原生 Etheral 背景 + 原生 fetch；勿再教純 WebView 螢保）  
5. [ ] `git init` → 首 commit → **推 GitHub**（public 或 private）  
6. [ ] 分享文案：一句話產品 + clone URL + 給 AI 的短指令  
7. [ ]（可選）截圖／GIF  
8. [ ]（可選）Vercel 網頁預覽、開發者簽名  

### 建議給朋友／AI 的短指令

```text
請讀 SKILL.md 與 PROGRESS.md，幫我在這台 Mac 安裝 Overhead Flights 螢保。
跑 macos/build-and-install.sh，不要改我的螢保等待時間，只安裝 .saver 並告訴我怎麼在「自訂」裡選中它。
```

---

## 成功定義（分享給朋友時）

朋友在 Mac 上：

1. 有 Xcode  
2. clone 後跑 `macos/build-and-install.sh`  
3. **系統設定 → … → 自訂 → OverheadFlights**  
4. **啟動時間自己設**  
5. 螢保出現：**Etheral 風格暗底流動 + 真實 callsign**（不是風景圖；無機時可全黑）  

---

## 決策備忘

- 產品 = 經典 `.saver` 內容替換，不是第二套 idle  
- 螢保字 = AppKit；螢保底 = 原生 CI Etheral；資料 = URLSession  
- 分享優先於繼續打磨動畫  
- 合作模式見 `../COOPERATION.md`（若存在）  
