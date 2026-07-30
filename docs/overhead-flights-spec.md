# 頭頂航班（Overhead Flights）規格書 v1.0

一個極簡的環境顯示器：電腦閒置或手機立在桌上時，安靜顯示正飛過你頭頂的航班。

---

## 產品形態

1. **macOS 螢幕保護程式（主路徑）**：`OverheadFlights.saver`（ScreenSaver + WKWebView 載入同一套 HTML）
2. **網頁／PWA（開發與手機）**：瀏覽器全螢幕或加入主畫面

顯示壽命 **S1**：符合條件的最近航班在範圍內**持續顯示**；離開範圍或無航班才全黑。無 15 秒限時、無「同班不再亮」。

---

## 畫面規格

- 純黑背景（`#000`，OLED 友善）
- 一次只顯示**最近的一班**飛機
- 顯示欄位：
  - 航班號（callsign）
  - 航空公司（由航班號前綴推得，adsbdb 查到後可覆蓋）
  - 起訖（best effort）：起飛地與目的地都查到 → `起飛地 → 目的地`；只查到一邊 → 只顯示該邊；都查不到 → 不顯示，不留空位
  - 高度（公尺與英呎並列，或擇一，開發時定）
  - 方位（相對使用者位置，如「東北方」）
- P1 動畫（有意識升級）：
  - 允許且僅允許：
    - 新航班一次方位流星線
    - 資訊分層淡入（含 monogram）
    - 換班／離開時整卡 out-then-in 淡出淡入
    - 防烙印極慢漂移
  - 禁止：地圖、粒子、常駐循環表演、每輪詢重播入場、雙層真 crossfade、外連航司 logo、航向/track 線語意
  - 同 callsign 的高度／方位／晚到目的地更新：零動畫
- **防烙印**：整塊文字每 3–5 分鐘緩慢漂移數個像素（CSS 動畫）
- 完全無航班時：純黑，不顯示任何東西
- 任何錯誤（API 失敗、定位失敗）：靜默處理，永不彈出錯誤訊息

### P1 動畫細則

- **同航班**（callsign 相同）：
  - 只更新高度／方位，以及晚到的 airline / destination
  - 不重劃線、不重播分層入場
  - 只要仍在範圍內就持續顯示；不做顯示壽命倒數
- **新航班**（callsign 與上一筆不同，或從無到有）：
  - 先有一次安靜的方位流星線，再分層出字
  - 流星固定由左往右掠過，像片頭弧線，不承載真實方位語意
  - 線置中附近掠過並消失，不保留殘影
  - monogram + callsign 同時
  - airline 約 +120ms
  - destination 約 +120ms
  - meta（高度／方位）約 +150ms
  - `translateY` 不超過 6px；easing 使用 `cubic-bezier(0.22,1,0.36,1)`
- **換班或無航班**：
  - `crossfade` 定義為 out-then-in：整卡（線 + 字）先淡出約 1 秒，可短暫全黑，再進新內容
  - 單一 `#card` 即可；不要雙層 DOM 真疊加
  - 無航班時：退場後清空，純黑；仍在範圍內則持續顯示
- **reduced-motion**：
  - 無 `translateY` stagger；可短 opacity 或瞬切
  - 防烙印 drift 也關閉

---

## 資料層

### 位置

- **螢保**：原生 Core Location 注入 `window.__OVERHEAD_FIXED_POS__ = { lat, lon }`（優先）
- **網頁**：Geolocation API 抓一次；localStorage 快取
- 拒絕／失敗 → 快取 → 預設倫敦市中心
- 網頁需 https 或 localhost

### 航班資料：airplanes.live（v1 實作）

- **為什麼不是 OpenSky：** OpenSky 匿名 API 的 `Access-Control-Allow-Origin` 僅允許 `opensky-network.org`，純前端跨域會被擋；免費 CORS proxy 亦不穩。
- **主資料源：** `https://api.airplanes.live/v2/point/{lat}/{lon}/{radius_nm}`（`Access-Control-Allow-Origin: *`）
- 查詢範圍：使用者座標半徑約 40 公里（≈ 21.6 nmi）
- **輪詢間隔：90 秒**（保守，降低對免費 API 的壓力）
- 過濾條件：
  - 剔除 `alt_baro === 'ground'` 或無法解析高度
  - 剔除高度 < 500 公尺（ADS-B 高度以英呎換算）
  - 剔除距離 > 40 km
- 從結果中取距離最近的一班

### 目的地查詢：adsbdb

- 用航班號查航線起訖（`https://api.adsbdb.com/v0/callsign/{cs}`，CORS `*`）
- **以航班號為 key 快取結果**（sessionStorage），同一班機不重複查詢
- 查不到目的地是正常情況，畫面直接省略該欄位
- 航司名稱優先用 adsbdb；失敗則用內建 ICAO 前綴表
- 有 `nearest` 後先用 callsign / altitude / bearing / monogram 前綴開動畫，不等待 adsbdb
- `fetchDestination` 發起時必須捕獲當下的 generation token 與 callsign；完成後只在「捕獲值仍等於目前顯示中的 callsign/token」時靜默補寫 airline / destination
- meta 方位文字永遠使用 user → plane bearing（North / Northeast / ...）
- 流星線不使用 `track` / `heading`，也不映射 user → plane bearing；僅作固定左到右的開場弧線

### 開工第一步（技術驗證）— 已完成

- OpenSky：HTTP 200 但 CORS 不可用（純前端）
- airplanes.live + adsbdb：CORS 可用，已接入 v1

---

## 手機專屬行為

- **PWA**：加 manifest.json（名稱、圖示、`display: standalone`、黑色主題色），可加入主畫面；iOS 以 `standalone` 較穩妥
- **Wake Lock**：頁面可見時申請 `navigator.wakeLock.request('screen')` 保持螢幕常亮
  - 支援門檻：iOS 16.4+ / Android Chrome
  - 更舊的 iOS 裝置 fallback（NoSleep.js）列 v2
- **背景管理**：監聽 `visibilitychange`
  - 切到背景 → 暫停輪詢、釋放 wake lock
  - 回到前景 → 立即抓一次資料、恢復輪詢、重新申請 wake lock
- 響應式排版：直式手機另調字級與間距（純 CSS）

---

## 技術架構

- **單一 HTML 檔**：HTML + CSS + JS 全部內含
- 無框架、無建置工具、無後端、無 API 金鑰
- 部署：Vercel 或 GitHub Pages（自帶 https，v1 必要項，因 Geolocation 與 Wake Lock 都要求 https）
- 手機取用方式：掃 QR code 開啟 → 加入主畫面
- 航班身分 key 只用 `cleanCallsign`（必要時退回 `hex`）；禁止把高度／目的地寫進「是否換班」判斷
- 動畫序列使用 generation token；每次新序列 `+1`，任何 `await` 後若 token 過期即中止，避免競態覆寫
- 本輪不使用 API `dst` / `dir` 欄位驅動畫面語意（可留 TODO，但不納入本版實作）

---

## 已知限制（接受，不解）

- 目的地查詢非 100% 命中
- iOS < 16.4 螢幕會自動熄滅
- 長時間常亮耗電，手機用法預設插電使用

---

## v2 待辦（先不做）

- Windows（.scr）
- 深夜閒置文案、機型、未充電調暗
- 舊 iOS wake lock fallback
- OpenSky 註冊帳號代理

---

## 驗收標準

1. 可安裝 `OverheadFlights.saver`，系統設定可選、可預覽、可作螢保
2. S1：同航班在範圍內持續顯示（超過 15 秒仍在）；90 秒可更新高度
3. 無航班／離開範圍：全黑
4. 換班 out-then-in；目的地晚到可靜默補
5. 螢保優先 `__OVERHEAD_FIXED_POS__`
6. 無 15 秒 dismiss 殘留；錯誤靜默
