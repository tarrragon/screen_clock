/// 解析 CLI 引數 `--screen=N`（SPEC-003 FR-02）。
///
/// - 未提供 / 格式錯誤 / 非數字 / 負數 → 回 null（由呼叫端 fallback 主螢幕）
/// - 多次出現只取最後一次（CLI 慣例：後者覆寫前者）
///
/// 範例：
/// ```dart
/// parseScreenArg(['--screen=1']);    // 1
/// parseScreenArg(['--screen=0']);    // 0
/// parseScreenArg(['--screen=abc']);  // null
/// parseScreenArg([]);                // null
/// ```
int? parseScreenArg(List<String> args) {
  const String prefix = '--screen=';
  int? result;
  for (final String arg in args) {
    if (!arg.startsWith(prefix)) {
      continue;
    }
    final String value = arg.substring(prefix.length);
    final int? parsed = int.tryParse(value);
    if (parsed == null || parsed < 0) {
      continue;
    }
    result = parsed;
  }
  return result;
}
