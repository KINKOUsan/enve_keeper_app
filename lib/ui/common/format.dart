// 金额与时间的展示格式化 — 全 App 统一从这里取。
// 金额规则：整数不带小数、非整数保留 2 位、千分位分隔；负号用 −（U+2212）。
// 货币符号（ADR-0017）由调用方传入当前账本设置（currencySymbolProvider）；
// moneySigned 的默认参数仅是共享默认常量（纯函数可测性兜底），业务调用方应显式传参。
import 'package:intl/intl.dart';

import '../../domain/models.dart' show kDefaultCurrency;

final _fmtInt = NumberFormat('#,##0');
final _fmtDec = NumberFormat('#,##0.00');

/// 金额正文：1520.5 → 「1,520.50」，1520 → 「1,520」
String money(double v) {
  final isInt = v == v.roundToDouble();
  return isInt ? _fmtInt.format(v) : _fmtDec.format(v);
}

/// 带符号金额：支出样式 −¥68（负号前置，金额恒显示绝对值时调用方自行处理）。
/// [symbol] 传当前账本的货币符号（currencySymbolProvider）。
String moneySigned(double v, {String symbol = kDefaultCurrency}) {
  if (v < 0) return '−$symbol${money(-v)}';
  return '$symbol${money(v)}';
}

/// 金额遮蔽形态（v1.2.0 票 03）：保留货币符号 + 固定圆点，如 ¥••••。
/// 只藏数字不藏符号；仅首页金额隐私用（纯展示层，不涉数据）。
String moneyMasked({String symbol = kDefaultCurrency}) => '$symbol••••';

/// 快捷取整到 2 位小数（输入侧兜底）
double parseMoney(String s) {
  final v = double.tryParse(s) ?? 0;
  return (v * 100).roundToDouble() / 100;
}

/// 跨年年份前缀：当年为空串，非当年带「yyyy年」（dayLabel / atLabel 共用此规则）
String _yearPrefix(DateTime d, DateTime now) =>
    d.year == now.year ? '' : '${d.year}年';

/// 流水分组日期标签：今天 · 9月15日 / 昨天 · 9月14日 / 9月12日 · 周五。
/// 非当年日期带年份（2025年12月31日 · 周三）——时间可补记到过去任意时刻后
/// （ADR-0019），跨年账本的组头不带年份会有同月日歧义。
String dayLabel(DateTime d, DateTime now) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  final sameDay =
      d.year == now.year && d.month == now.month && d.day == now.day;
  if (sameDay) return '今天 · ${d.month}月${d.day}日';
  final yesterday = now.subtract(const Duration(days: 1));
  final isYesterday =
      d.year == yesterday.year &&
      d.month == yesterday.month &&
      d.day == yesterday.day;
  if (isYesterday) return '昨天 · ${d.month}月${d.day}日';
  return '${_yearPrefix(d, now)}${d.month}月${d.day}日 · ${weekdays[d.weekday - 1]}';
}

/// 详情页「时间」行的值：9月15日 08:30；非当年带年份（2025年12月31日 20:05）。
/// 与 dayLabel 同一条跨年规则（ADR-0019）。
String atLabel(DateTime d, DateTime now) =>
    '${_yearPrefix(d, now)}${d.month}月${d.day}日 ${clockLabel(d)}';

/// 时间 HH:mm
String clockLabel(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
