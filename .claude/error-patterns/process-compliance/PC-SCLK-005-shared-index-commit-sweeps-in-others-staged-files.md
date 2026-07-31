---
id: PC-SCLK-005
title: 共享 working tree 下無 pathspec 的 git commit 會夾帶他人已 staged 的檔案
severity: medium
---

# PC-SCLK-005: 共享 working tree 下無 pathspec 的 git commit 會夾帶他人已 staged 的檔案

---

## 分類資訊

| 項目 | 值 |
|------|------|
| 編號 | PC-SCLK-005 |
| 類別 | process-compliance |
| 風險等級 | 中（本次未造成損害——執行代理人在 commit 前自行發現並改用精準 pathspec 攔截；若未察覺會造成他人未完成工作被夾帶進錯誤 commit，屬 PC-SCLK-001 姊妹風險） |
| 首發時間 | 2026-07-31（1.4.0-W2-016 修正 CursorLocatorBridge 時發現） |
| 姊妹模式 | PC-SCLK-001（並行 agent 的 `--amend` 改寫他人 commit，同屬「共享 HEAD/index 心智模型失效」家族，但 001 是寫入面直接破壞、本模式是暫存面夾帶）、PC-019（worktree 派發前的未 commit 變更防護，見下方適用條件） |

---

## 症狀

多個 agent 在同一 working tree（非 worktree 隔離）並行作業時，各自對自己負責的檔案執行 `git add <path>`。此步驟本身安全——`git add` 只把指定路徑的變更加入 index，不影響其他路徑。真正的風險點在**下一步的 commit**：若此時執行不帶 pathspec 的 `git commit -m "..."`，git 會提交 index 當下的**全部**內容，包含其他 agent 早於自己 add、且尚未 commit 完成的檔案——即使自己從未對那些檔案下過任何指令。

危險點在於：index 是整個 working tree 唯一共享的暫存區，不是每個 agent 各自的私有暫存區。`git add` 的路徑範圍限制只保護「加入」這一步，不保護「提交」這一步；commit 若省略 pathspec，範圍預設是整個 index，而非「我這次 add 的東西」。

---

## 實例（2026-07-31，1.4.0-W2-016）

事件序列：

| 步驟 | 動作 | 觀察到的結果 |
|------|------|------|
| 1 | 執行 `git add macos/Runner/MainFlutterWindow.swift`（僅此一個路徑） | 命令本身成功，只操作了指定路徑 |
| 2 | 執行 `git status --porcelain` 確認 add 結果 | 除了預期的 `M macos/Runner/MainFlutterWindow.swift`，同時看到 `M  lib/app_constants.dart`、`M  lib/main.dart`、`A  lib/platform/cursor_locator_hotkey_controller.dart`、`M  test/fullscreen_clock_visibility_test.dart`、`A  test/platform/cursor_locator_hotkey_controller_test.dart`、`M  test/widget_test.dart` 六個檔案的 staged 標記——這些檔案我從未 add 過，是另一個並行 agent（負責 W2-005 hotkey 相關 ticket）先前已 stage、尚未 commit 完成的工作 |
| 3 | 意識到若直接 `git commit -m "..."`（不帶 pathspec）會把上述 6 個他人檔案一併提交，改用 `git commit -m "..." -- macos/Runner/MainFlutterWindow.swift` | commit 只包含 1 個檔案、99 行變更；`git status --porcelain` 確認其餘 6 個檔案維持原 staged 狀態未被觸碰 |

發現方式：commit 前對照 `git status --porcelain` 的檔案清單與自己實際修改的範圍是否一致，而非信任「我只 add 了一個檔案，commit 應該也只有一個檔案」的直覺推論。

未造成損害的關鍵：commit 前檢查這一步是可控環節，且本次是在 add 之後、commit 之前多做了一次 `git status` 核對才發現落差；若省略核對直接 `git commit -m`，他人 6 個檔案（含 2 個尚在編輯中的新檔案）會被夾帶進與己無關的 commit，造成他人半成品被提前定格、commit 訊息與實際內容不符、且該 agent 後續 commit 時會因這些檔案已不在 unstaged 狀態而混亂。

---

## 根因

「`git add` 範圍限定 = commit 範圍限定」是單一執行體心智模型下的合理直覺，因為沒有其他人會在自己 add 和 commit 之間插入 stage 動作。並行執行體共用同一 index 時此等價關係破裂：

三個條件同時成立即觸發：

1. 多個 agent 共用同一 working tree（非 worktree 隔離）
2. 其中一個 agent 已 `git add` 了自己的檔案、尚未 commit
3. 另一個 agent 在此期間執行 `git commit -m "..."` 時未加 pathspec

第 3 點是可控環節——commit 命令本身有明確語法差異（帶 `-- <path>` vs 不帶），不需猜測他人狀態即可規避。第 1、2 點是並行派發的常態，不是異常，也不該要求所有 agent「不要提前 add」（那只是把風險延後到 commit 當下才 add，仍會撞上同一問題）。

延伸：同源風險存在於所有「以當前 index 為隱含範圍」的 git 操作——`git commit`（無 pathspec）、`git stash`（無 `--` 限定路徑時預設打包整個 working tree）、`git diff --cached`（用於檢視而非寫入，風險較低但同樣會顯示他人內容造成誤讀）。

---

## 解決方案

### 有效防護：commit 一律帶精準 pathspec

```bash
# 危險：省略 pathspec，提交 index 當下全部內容
git commit -m "..."

# 安全：無論 index 當下還有什麼其他人的暫存內容，只提交指定路徑的變更
git commit -m "..." -- macos/Runner/MainFlutterWindow.swift
```

這比「約定不要用 `git add -A` / `git add .`」更根本，因為它不依賴每個 agent 自律避免寬範圍 add——即使自己全程只 `git add <path>`，只要commit 時漏了 pathspec，仍會被他人已 stage 的內容拖下水。`git commit -- <path>` 從 commit 這一步本身就繞過已 staged 的 index 內容，不管 index 裡還有什麼。

### 事前預防（agent 側）

| 情境 | 措施 |
|------|------|
| commit 前 | 一律 `git commit -m "..." -- <自己負責的路徑>`，不依賴「我只 add 了自己的東西」的假設 |
| add 後、commit 前 | 執行 `git status --porcelain` 核對 staged 清單是否只有自己預期的檔案；出現非預期項目時，優先假設是他人並行工作，不隨意 `git reset` 清空 |
| commit 後 | 再次 `git status --porcelain` 確認自己 commit 前看到的「他人 staged 檔案」仍維持原狀未被觸碰，驗證 commit 範圍未外溢 |

### 事前預防（PM 側）

| 情境 | 措施 |
|------|------|
| 派發涉及 git commit 的並行 agent | Context Bundle 明載「commit 一律帶 `-- <path>` pathspec，不可依賴僅 add 自己檔案即安全」 |
| 檔案修改型並行派發 | 優先採 worktree 隔離（ARCH-015），從根本消除共用 index；但注意下方「適用條件」的互斥限制 |

---

## 預防措施

| 層級 | 措施 | 狀態 |
|------|------|------|
| Agent 自律 | Context Bundle 加入「commit 一律 `-- <path>` pathspec」的並行安全約束 | 可立即施行 |
| PM 派發 | 檔案修改型並行任務優先 worktree 隔離 | 既有 ARCH-015 規範，但受下方適用條件限制 |
| Hook 強制 | PreToolUse 偵測共用 working tree 下 `git commit -m` 未帶 `--` pathspec 且當前有 2+ 進行中 ticket 時警告 | 待評估（WARNING 級即可，單一執行體省略 pathspec 是合法且常見的操作，不應硬擋） |

---

## 適用條件（與 worktree 隔離互斥）

Worktree 隔離可從根本避免本模式——每個 agent 各自的 index 天生互不干擾。但當共享 working tree 上已有其他 agent 進行中、尚未 commit 的變更時，`worktree-commit-before-dispatch-hook`（`.claude/skills/worktree/hooks/worktree-commit-before-dispatch-hook.py`）會依 PC-019 的防護邏輯**阻擋**新的 worktree 派發（未 commit 的 tracked 變更可能在 worktree 操作的 stash/checkout 中丟失）。

換言之：兩種並行隔離手段在同一時間窗口互斥——

- 共享 tree 上有他人未 commit 的進行中變更時 → 無法派發新的 worktree agent（PC-019 擋）→ 只能繼續在共享 tree 上派發 → 承擔本模式（PC-SCLK-005）的暫存夾帶風險
- 想用 worktree 隔離消除本模式的風險 → 前提是共享 tree 先清乾淨（全部 commit）→ 但這正是本模式描述的、最容易在多 agent 並行時做不到的狀態

**結論**：本模式的防護不能指望「改用 worktree 就不用管」，因為觸發本模式的時間窗口（他人有未 commit 變更）恰好是 worktree 派發被 PC-019 擋住的同一時間窗口。共享 tree 情境下的 commit pathspec 紀律是**必要**防線，不是 worktree 隔離普及前的過渡措施。

---

## 相關規則

- `.claude/rules/core/bash-tool-usage-rules.md` 規則三 — 禁止串接 git 寫入操作（同源的共享 git 狀態問題，但聚焦 `index.lock` 競爭而非 staged 內容範圍）
- `.claude/error-patterns/process-compliance/PC-SCLK-001-parallel-agent-amend-rewrites-foreign-commit.md` — 姊妹模式：共享 HEAD 心智模型在並行下失效的另一種表現（寫入面直接改寫 vs 本模式的暫存面夾帶）
- `.claude/error-patterns/process-compliance/PC-019-worktree-merge-state-loss.md` — worktree 隔離的前置條件與本模式的互斥關係
- `.claude/skills/worktree/hooks/worktree-commit-before-dispatch-hook.py` — PC-019 的 Hook 強制層，決定本模式的適用時間窗口
- `.claude/pm-rules/parallel-dispatch.md` — 並行派發規範

---

## 關聯 Ticket

- `1.4.0-W2-016`（發現本模式並自行以 `git commit -- <path>` 攔截的 ticket）
