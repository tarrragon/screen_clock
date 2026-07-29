<!-- 注意：本文件禁止使用 emoji（交接文件規範） -->
<!--
UC 白名單 SSOT（Single Source of Truth）。
本檔為所有合法 UC 編號的權威來源，`doc uc list` / `uc verify` / `uc trace` / `uc context`
四個子命令皆依此解析。每個 UC 以 `## UC-XX: 標題` 標記，含 `### 主要成功場景` 區塊。
解析規則與豁免範圍定義於 docs/spec/uc-numbering-convention.md 第 3、5 節。
詳細內容（替代場景、例外場景、驗收條件）見對應的 docs/usecases/UC-XX-*.md。
-->

# 應用程式用例總表（UC 白名單 SSOT）

本檔登錄所有合法 UC 編號與主流程摘要。新增 UC 時須同步在此註冊，並確保主流程內容與
`docs/usecases/UC-XX-*.md` 完整用例文件一致，不可各自漂移。

---

## UC-01: 啟動透明時鐘遮罩

**來源提案**：PROP-001
**對應規格**：SPEC-001、SPEC-002
**詳細用例**：`docs/usecases/UC-01-launch-overlay-clock.md`

### 主要成功場景

1. **啟動 app**
   - 使用者於 Launchpad / Finder 雙擊 screen_clock app
   - 系統載入 Flutter runtime 並執行 `main.dart`

2. **初始化視窗**
   - app 呼叫 `windowManager.ensureInitialized()`
   - app 完成 frameless / transparent / always-on-top / shadow-off / ignore-mouse-events 屬性設定
   - app 設定視窗尺寸為主螢幕尺寸並定位至 `(0, 0)`

3. **顯示遮罩**
   - app 呼叫 `windowManager.show()`
   - 螢幕上出現透明全螢幕遮罩
   - 中央顯示當前時間（HH:mm:ss）

4. **背景持續更新**
   - 內部 timer 每秒觸發 `setState`，時鐘文字逐秒更新
   - 使用者可繼續操作底下的任何應用，遮罩不阻擋任何輸入

---

## UC-02: 在遮罩下繼續操作底下程式

**來源提案**：PROP-001
**對應規格**：SPEC-001
**詳細用例**：`docs/usecases/UC-02-click-through-interaction.md`

### 主要成功場景

1. **點擊底下視窗**
   - 使用者在遮罩任意位置點擊
   - macOS 將事件路由到底下視窗（因 `IgnoreMouseEvents` 將遮罩標為非命中目標）
   - 底下視窗 active 並接收 click 事件

2. **拖曳檔案**
   - 使用者從 Finder 拖曳檔案
   - 拖曳軌跡可穿過遮罩
   - 放到底下視窗時被該視窗接收

3. **使用鍵盤輸入**
   - 使用者在底下應用打字
   - 因遮罩 app 不持有 key window 狀態，鍵盤事件直接到底下應用
   - 文字正確輸入到底下應用

4. **捲動內容**
   - 使用者於遮罩任意位置捲動 trackpad / 滑鼠滾輪
   - 捲動事件到達底下視窗
   - 底下視窗內容正確捲動

5. **Hover 操作**
   - 使用者將滑鼠停在底下視窗的可 hover 元素上
   - hover 提示框正常顯示

---

## UC-03: 退出遮罩

**來源提案**：PROP-001
**對應規格**：SPEC-001
**詳細用例**：`docs/usecases/UC-03-exit-overlay.md`

### 主要成功場景

1. **觸發退出**
   - 使用者按下 Cmd+Q
   - 或於 Dock app icon 右鍵 → Quit
   - 或從 macOS Activity Monitor 結束 process

2. **取消 timer**
   - app 的 Clock widget `dispose()` 被呼叫
   - `Timer.periodic` 被 cancel

3. **關閉視窗**
   - `window_manager` 關閉視窗
   - 視窗從螢幕消失

4. **結束 process**
   - Flutter runtime 退出
   - 所有資源釋放

---

## UC-04: 綁定拖曳滾動

**來源提案**：PROP-002
**對應規格**：SPEC-007
**詳細用例**：`docs/usecases/UC-04-bind-drag-to-scroll.md`

### 主要成功場景

1. **按下綁定鍵**
   - 使用者按下已綁定為拖曳滾動動作的滑鼠側鍵
   - 原生端記錄起始游標 Y 座標，進入拖曳狀態；該次按下事件被消費，原按鍵的系統預設動作不觸發

2. **垂直拖曳合成捲動**
   - 使用者垂直移動滑鼠
   - 原生端以 `Δy = 當前Y − 上次Y` 乘上 sensitivity 合成垂直滾輪事件（換算結果為 0 時取最小單位）
   - 捲動事件注入游標下方目標 app，內容依設定方向（natural / inverted）捲動；該次移動事件同時被消費，游標圖示視覺上不隨之位移

3. **放開結束**
   - 使用者放開綁定鍵
   - 原生端離開拖曳狀態，消費該次放開事件，停止合成捲動事件

---

## UC-05: 綁定按鍵快捷鍵

**來源提案**：PROP-002
**對應規格**：SPEC-007
**詳細用例**：`docs/usecases/UC-05-bind-mouse-button-hotkey.md`

### 主要成功場景

1. **按下綁定鍵**
   - 使用者按一下已綁定為快捷鍵動作的滑鼠側鍵
   - 原按鍵的原生動作（如上一頁/下一頁）被消費，不觸發

2. **合成組合鍵事件**
   - 原生端依 `HotkeyAction` 的 keyCode 與修飾鍵合成 keyDown + keyUp
   - 組合鍵事件送往前景 app

3. **前景 app 接收**
   - 前景 app 收到並執行對應的快捷鍵動作（如複製、螢幕截圖）

4. **放開綁定鍵**
   - 使用者放開該側鍵
   - 原生端未消費該次放開事件（僅拖曳滾動綁定的放開事件會被消費），依原樣放行

---

## UC-06: 快速定位滑鼠游標

**來源提案**：PROP-003
**對應規格**：SPEC-008
**詳細用例**：`docs/usecases/UC-06-locate-cursor.md`

### 主要成功場景

1. **觸發**
   - 使用者按下 `Cmd + Option + L`
   - 前景為任何 app 皆可觸發；不需要操作滑鼠或觸控板

2. **判定目標螢幕**
   - 原生層讀取 `NSEvent.mouseLocation`
   - 於 `NSScreen.screens` 中找出 `frame` 涵蓋該座標的螢幕

3. **建立特效視窗**
   - 於目標螢幕建立透明、置頂、不接收滑鼠事件的原生視窗
   - 視窗層級高於全螢幕應用

4. **播放特效**
   - 聚光燈遮罩淡入，螢幕壓暗，游標周圍保留明亮圓形區域
   - 螢幕四周邊框以使用者設定的主色調閃爍三次
   - 游標位置向外擴散三圈波紋
   - 播放期間圓心與波紋中心跟隨游標移動

5. **結束**
   - 依使用者設定的特效時長（預設 1.5 秒）後整層淡出
   - 特效視窗釋放

6. **使用者找到游標**
   - 使用者繼續原本的操作
