import 'app_constants.dart';

/// 即時年齡格式化（生命計時模式）。
///
/// 將出生日期與當下時間換算成年齡，輸出「兩位數一組、空格分隔、無標點」的字串：
/// `{年齡補2位} {小數2位} {小數2位} {小數2位} {小數2位}`，例如 `18 15 97 91 75`。
///
/// 設計約束：
/// - 一年長度採平均西曆年（[AppAge.daysPerYear]），避免個別閏年造成跳動。
/// - 小數取 [AppAge.decimalPlaces] 位（8 位 → 4 組兩位數，配對無餘數）。
/// - 整數年齡至少補成兩位；百歲以上自然成三位，不影響後方小數配對。
/// - 出生日在未來（年齡為負）時夾為 0。
class AgeFormatter {
  AgeFormatter._();

  /// 把 [birthDate] 到 [now] 的間隔換算為年齡字串。
  static String format(DateTime birthDate, DateTime now) {
    final int elapsedMicros = now.difference(birthDate).inMicroseconds;
    final double microsPerYear =
        AppAge.daysPerYear * Duration.microsecondsPerDay;

    double ageYears = elapsedMicros / microsPerYear;
    if (ageYears < 0) {
      ageYears = 0;
    }

    final int years = ageYears.floor();
    final double fraction = ageYears - years;

    final int scale = _pow10(AppAge.decimalPlaces);
    int fractionDigits = (fraction * scale).floor();
    // 浮點邊界保護：避免進位溢出成多一位。
    if (fractionDigits >= scale) {
      fractionDigits = scale - 1;
    }

    final String yearsText = years.toString().padLeft(2, '0');
    final String fractionText =
        fractionDigits.toString().padLeft(AppAge.decimalPlaces, '0');

    return '$yearsText ${_groupIntoPairs(fractionText)}';
  }

  /// 10 的 [exponent] 次方（小數位縮放用）。
  static int _pow10(int exponent) {
    int result = 1;
    for (int i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  /// 把數字字串每兩位切一組、以空格連接（[digits] 長度須為偶數）。
  static String _groupIntoPairs(String digits) {
    final List<String> pairs = <String>[];
    for (int i = 0; i < digits.length; i += 2) {
      pairs.add(digits.substring(i, i + 2));
    }
    return pairs.join(' ');
  }
}
