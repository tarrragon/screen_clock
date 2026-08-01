---
id: IMP-SCLK-001
title: macOS bash 3.2 將裸 $VAR 後緊鄰的全形標點吃進變數名，set -u 下崩在只有錯誤路徑才走到的分支
category: implementation
severity: medium
created: 2026-08-01
source_ticket: 1.4.0-W2-033
---

# IMP-SCLK-001: bash 3.2 裸 `$VAR` 緊鄰全形標點在 `set -u` 下崩潰

## 症狀

shell 腳本平常執行正常，但在某條**錯誤處理分支**被觸發時，以 `<VARNAME>\xef: unbound variable` 之類的訊息中止，變數名尾端帶不可見位元組。訊息指向的變數明明已在上方賦值。

典型現場：

```bash
set -u
CODE=7
echo "失敗（exit $CODE）"
# → line 3: CODE?: unbound variable
```

## 根因

三個條件同時成立才觸發，缺一不會發生：

| 條件 | 說明 |
|------|------|
| bash 3.2 | macOS 內建 `/bin/bash` 停在 3.2.57，Apple 因 GPLv3 授權不再隨系統升級。**`#!/usr/bin/env bash` 不是逃生路**——未另裝新版時 `env bash` 解析到的仍是同一支 3.2 |
| 裸 `$VAR` 後緊鄰全形標點 | bash 3.2 判定變數名邊界時只認 ASCII 字元類別，全形標點（`）`、`：`、`，`、`。` 等，UTF-8 多位元組）的首位元組被當作變數名的一部分，於是 `$CODE）` 解析為變數 `CODE\xef` |
| `set -u` | 未定義變數由靜默展開為空字串，升級為中止執行 |

bash 4.x/5.x 已修正變數名邊界判定，同一腳本不會重現——這使問題在開發者本機（可能裝了 homebrew bash）與 CI／他人 macOS 之間表現不一致。

## 為何特別隱蔽

含全形標點的字串最常出現在**錯誤訊息**裡（「失敗（exit $CODE）」「錯誤：$MSG」）。這些行只在失敗分支執行，正常路徑永遠碰不到。結果是：

- 所有測試通過時，腳本看起來完全正常
- 真正有東西失敗、最需要看清楚失敗原因時，腳本自己先崩，且退出碼與訊息都與真正的失敗無關

錯誤處理路徑本身有錯誤，是這個 pattern 的核心危害——它把「診斷工具」變成「第二個故障源」。

## 偵測

```bash
# 掃描裸 $VAR 緊鄰全形標點（涵蓋常見中文標點）
grep -rnP '\$[A-Za-z_][A-Za-z0-9_]*[（）：，。、；！？「」]' --include='*.sh' .

# 確認執行期的 bash 版本（別假設 env bash 是新版）
/bin/bash --version | head -1
command -v bash | xargs -I{} {} --version | head -1
```

## 修正

一律用 `${VAR}` 大括號界定變數名邊界：

```bash
echo "失敗（exit ${CODE}）"   # 正確
echo "失敗（exit $CODE）"     # 3.2 下崩潰
```

大括號使變數名邊界顯式，與後續任何字元都無歧義，且對所有 bash 版本行為一致。

## 預防

| 措施 | 說明 |
|------|------|
| 腳本內變數展開一律加大括號 | 不區分「這裡後面接的是不是全形字元」——判斷成本高於一律加，且漏判只在錯誤路徑顯形 |
| 錯誤路徑必須被實際執行過 | 以 mock 或注入失敗替身跑過每一條失敗分支，不能只驗證 happy path 就宣稱腳本可用 |
| 專案語言規則為中文時風險加倍 | 專案若要求訊息使用繁體中文（如本專案 CLAUDE.md 語言約束），全形標點會出現在幾乎每一條錯誤訊息裡，此 pattern 的觸發面遠大於英文專案 |

## 適用範圍

任何在 macOS 上以 `/bin/bash` 或 `env bash` 執行、且訊息含 CJK 全形標點的 shell 腳本。與專案語言、框架無關；替換專案名稱與檔案路徑後仍成立。

## 相關

- 來源：`1.4.0-W2-033`（建立 `scripts/run-tests.sh` 時由 sumac-system-engineer 於實測失敗分支時發現並修正）
- `.claude/rules/core/language-constraints.md` 規則 1（繁體中文要求）——與本 pattern 的觸發條件直接相關
- `.claude/rules/core/observability-rules.md` 規則 1（錯誤路徑必須有可見輸出）——本 pattern 使該輸出反而成為故障源
