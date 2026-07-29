---
id: DOC-UC-NUMBERING
title: "UC 編號治理規範"
status: draft
created: "2026-07-29"
updated: "2026-07-29"
version: "1.0"
owner: tarrragon
---

# UC 編號治理規範

本文件定義 UC（Use Case）編號的格式、SSOT 解析規則與豁免範圍，供 `doc uc list` /
`uc verify` / `uc trace` / `uc context` 四個子命令與 PreToolUse 寫入驗證 hook 共用。

**唯一實作**：`.claude/skills/doc/doc_system/core/uc_registry.py` 是本規範的唯一程式碼實作，
所有消費端（CLI 子命令、hook）一律複用該模組，禁止各自實作規則副本（防止規則漂移）。**本文件
描述實作行為；實作與文件不一致時，以實作為準，並在此標註待修正處。**

---

## 1. 編號格式

UC 編號採兩位數零填充格式：`UC-XX`（`X` 為數字），如 `UC-01`、`UC-06`。

| 規則 | 說明 |
|------|------|
| 合法格式 | 恰兩位數字，如 `UC-01`、`UC-12` |
| 禁止三位數 | `UC-001` 不合法（須是兩位數，非三位數） |
| 禁止偽子樹 | `UC-01.4`、`UC-01.4.20` 等帶點號子編號一律視為格式違規 |
| 大小寫 / 全形不敏感 | `uc-01`、`ＵＣ－０１` 等變體先正規化（大寫 + 全形轉半形）後再判定，與 `UC-01` 視為同一 token |

實作依據：`VALID_UC_FORMAT_RE = re.compile(r"^UC-\d{2}$")`；正規化邏輯見 `normalize_token()`。

---

## 2. Token 掃描與正規化規則

掃描文字時，以下列規則找出所有疑似 UC 編號的 token（含合法、格式違規與偽子樹），供後續違規判定使用：

| 項目 | 規則 |
|------|------|
| 掃描樣式 | `UC_TOKEN_RE`：`U`/`C` 大小寫不敏感、連字號含全形變體（`－`/`﹣`/`―`）、編號含全形數字/字母，並允許以點號延伸的子編號（供偽子樹偵測） |
| 正規化 | `normalize_token()`：全形連字號轉半形 `-`、全形英數字轉半形、統一轉大寫 |
| 判定依據 | 違規判定一律以正規化後的形式為準，確保 `uc-99`、`ＵＣ－99`、`UC-99` 判定一致 |

正規化是為了讓「同一個編號的不同書寫變體」在違規判定與訊息輸出時得到一致結果，避免同一問題因書寫方式不同而被重複回報或遺漏。

---

## 3. SSOT 解析規則

**SSOT 檔案位置**：`docs/app-use-cases.md`（本專案適配路徑，見第 6 節跨專案適配表）。

**標題行格式**：合法 UC 標題行須符合 `## UC-XX: 標題`（兩個井號 + 空格 + `UC-XX` + 冒號 +
空格 + 標題文字），例如：

```
## UC-01: 啟動透明時鐘遮罩
```

不符合此格式的行（層級錯誤、缺冒號、編號格式錯誤等）不會被解析為合法 UC 定義。

**主流程摘要解析**：SSOT 檔案中 UC 標題行之後，若出現 `### 主要成功場景`（三個井號），其後
每一行符合「數字 + 點 + 空格 + 兩個星號開頭」（如 `1. **啟動 app**`）的行會被視為主流程步驟，
供 `doc uc summary` 與 Context Bundle 自動注入摘要使用。若 UC 區塊內找不到「主要成功場景」，
解析器 fallback 收集區塊內所有 `### ` 章節標題作為摘要（適用於不採標準主流程結構的 UC）。

**單一來源原則**：所有消費端（`uc list`/`verify`/`trace`/`context`/`summary` 五個 CLI
子命令、PreToolUse 寫入驗證 hook）一律呼叫 `uc_registry.py` 提供的 `parse_ssot()` /
`get_valid_uc_map()` 等函式取得白名單，禁止任何消費端自行讀檔案、自行寫正則解析 SSOT。新增
消費端時，先確認 `uc_registry.py` 是否已提供對應函式，未提供才擴充該模組（而非在消費端內複製解析邏輯）。

實作依據：`USE_CASES_SPEC_RELATIVE_PATH = "docs/app-use-cases.md"`、
`UC_HEADING_RE = re.compile(r"^## (UC-\d{2}): (.+)$")`、`MAIN_FLOW_HEADING = "### 主要成功場景"`、
`MAIN_FLOW_STEP_RE = re.compile(r"^\d+\.\s+\*\*")`。

---

## 4. 違規判定規則

一個 token 被判定為「違規」須同時滿足：非豁免（見第 5 節）且符合下列任一條件：

| 條件 | 說明 |
|------|------|
| 格式合法但不在白名單 | 符合 `UC-\d{2}` 格式，但正規化後的編號未出現在 SSOT 白名單中（如引用了未定義的 `UC-99`） |
| 格式本身不合法 | 三位數（`UC-001`）、偽子樹（`UC-01.4`）等不符 `UC-\d{2}` 的形態，一律視為違規（不論是否恰巧存在對應白名單項） |

判定前一律先套用第 5 節的兩類豁免（路徑豁免、UC-Pattern token 豁免），豁免範圍內一律視為
非違規，不進入上述條件判斷。

實作依據：`is_violation_token()`。

---

## 5. 豁免範圍

以下情況不受「必須存在於 SSOT 白名單」的約束：

### 5.1 路徑類豁免

| 路徑前綴 | 理由 |
|---------|------|
| `docs/work-logs/` | 工作日誌記錄歷史決策與過程引用，非正式規格引用 |
| `test/fixtures/`、`tests/fixtures/` | 測試固定資料，UC 編號可能是測試假資料非真實引用 |
| `docs/spec/` | 規格文件可能引用草稿階段或跨版本討論中的 UC 編號 |

精確相符豁免：SSOT 檔案自身（`docs/app-use-cases.md`）不受此約束（其標題行必然包含 UC
編號，屬定義而非「引用」）。

路徑比對採雙錨點：優先以相對 `project_root` 的路徑前綴比對（一般情況）；當檔案不在
`project_root` 之下（如 worktree 派發情境），改以絕對路徑的路徑片段比對，避免 worktree
鏡射主 repo 目錄結構時誤判。

### 5.2 UC-Pattern 設計模式標註豁免

`UC-` 後接大寫字母（非純數字）的 token，如 `UC-Pattern`、`UC-Base`，視為設計模式標註用語而非
UC 編號引用，一律豁免，不受白名單約束。

實作依據：`EXEMPT_PATH_PREFIXES`、`EXEMPT_PATH_EXACT`、`UC_PATTERN_EXEMPT_RE = re.compile(r"^UC-[A-Z][a-zA-Z]")`、
`is_exempt_path()`、`is_pattern_exempt_token()`。

### 5.3 掃描範圍差異（CLI 與 Hook）

CLI（`uc verify`/`uc trace`，離線批次稽核）與 PreToolUse Hook（即時攔截新寫入程式碼）掃描的
副檔名範圍不同：

| 使用場景 | 掃描副檔名 | 理由 |
|---------|-----------|------|
| CLI（`CLI_SCANNABLE_EXTENSIONS`） | `.dart` `.py` `.md` `.yaml` `.yml` `.ts` `.js` | 離線批次稽核工具，範圍越完整越能發現漂移，含文件與設定檔 |
| Hook（`HOOK_SCANNABLE_EXTENSIONS`） | `.dart` `.js` `.ts` `.py` | 即時攔截目標是「新寫入的程式碼」，文件類編輯多屬規格本身或說明性文字，不適合即時 WARNING |

---

## 6. 跨專案適配表

本規則與 `uc_registry.py` 實作可套用於任何採用相同 `.claude/skills/doc` 框架的專案，唯一
需依專案調整的是 SSOT 檔案路徑：

| 專案 | SSOT 路徑 |
|------|----------|
| screen_clock（本專案） | `docs/app-use-cases.md` |

新專案導入本規則時，只需調整 `uc_registry.py` 內 `USE_CASES_SPEC_RELATIVE_PATH` 常數指向
該專案實際的 UC 彙總檔路徑，其餘解析邏輯與豁免規則無需變動。

---

## 變更歷史

| 版本 | 日期 | 變更內容 |
|------|------|---------|
| 1.0 | 2026-07-29 | 初始版本（1.4.0-W1-004，補齊 uc_registry.py 缺失的規範文件） |
