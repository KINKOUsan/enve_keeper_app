// 流水筛选与排序 — 纯逻辑（无 Flutter 依赖），流水页与信封详情页共用。
// 筛选 = 类型（可空=全部）+ 日期（单日 或 起止区间，二者只生效其一）。
import 'models.dart';
import 'period_logic.dart' show dateOnly;

/// 排序方向：新→旧（默认）/ 旧→新
enum TxnSort { newest, oldest }

/// 筛选条件（不可变）。面板编辑通过 withXxx 生成新对象。
class TxnFilter {
  const TxnFilter({
    this.type,
    this.day,
    this.rangeStart,
    this.rangeEnd,
    this.showTransfers = true,
  });

  /// 类型条件；null = 全部类型
  final TxType? type;

  /// 单日筛选（设置时清掉区间，见 [withDay]）
  final DateTime? day;

  /// 区间起（含，日历口径）
  final DateTime? rangeStart;

  /// 区间止（含，日历口径）
  final DateTime? rangeEnd;

  /// 是否显示转移行（v1.2.0 票 04）：流水页默认隐藏转移以聚焦收支，
  /// 由页面级的「显示转移项」开关驱动；默认 true 保证信封详情页等
  /// 既有用法行为不变。这不是筛选条件——不计入 [isActive]。
  final bool showTransfers;

  /// 是否有任何激活的筛选条件
  bool get isActive => type != null || day != null || rangeStart != null;

  /// 是否未设日期条件（只有类型在生效）
  bool get noDate => day == null && rangeStart == null;

  /// 换类型条件（null = 恢复全部），其余条件保持
  TxnFilter withType(TxType? t) =>
      TxnFilter(
        type: t,
        day: day,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        showTransfers: showTransfers,
      );

  /// 设单日条件——单日与区间互斥，设置时清掉区间
  TxnFilter withDay(DateTime? d) =>
      TxnFilter(
        type: type,
        day: d,
        rangeStart: null,
        rangeEnd: null,
        showTransfers: showTransfers,
      );

  /// 设区间条件——单日与区间互斥，设置时清掉单日
  TxnFilter withRange(DateTime? start, DateTime? end) =>
      TxnFilter(
        type: type,
        day: null,
        rangeStart: start,
        rangeEnd: end,
        showTransfers: showTransfers,
      );

  /// 清单日条件，其余保持
  TxnFilter withoutDay() =>
      TxnFilter(
        type: type,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        showTransfers: showTransfers,
      );

  /// 清区间条件，其余保持
  TxnFilter withoutRange() =>
      TxnFilter(
        type: type,
        day: day,
        rangeStart: null,
        rangeEnd: null,
        showTransfers: showTransfers,
      );

  /// 换转移显隐（v1.2.0 票 04），其余条件保持
  TxnFilter withShowTransfers(bool show) =>
      TxnFilter(
        type: type,
        day: day,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        showTransfers: show,
      );

  /// 是否命中该笔流水（类型 + 日期 + 转移显隐同时满足才算）
  bool match(Txn t) {
    // 结转退回（refund，ADR-0016）与转移同类管理：同归「显示转移项」显隐组
    if (!showTransfers &&
        (t.type == TxType.transfer || t.type == TxType.refund)) {
      return false;
    }
    if (type != null && t.type != type) return false;
    final d = dateOnly(t.at);
    if (day != null && d != dateOnly(day!)) return false;
    if (rangeStart != null && d.isBefore(dateOnly(rangeStart!))) return false;
    if (rangeEnd != null && d.isAfter(dateOnly(rangeEnd!))) return false;
    return true;
  }
}

/// 按排序方向返回新列表（不改入参）：新→旧 / 旧→新。
/// 同时刻流水按 id 定序作次级键——Dart sort 不稳定，防止方向切换时同行抖动。
List<Txn> sortTxns(List<Txn> txns, TxnSort sort) {
  int cmp(Txn a, Txn b) {
    final byTime = a.at.compareTo(b.at);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  }

  final list = [...txns];
  if (sort == TxnSort.newest) {
    list.sort((a, b) => cmp(b, a));
  } else {
    list.sort(cmp);
  }
  return list;
}
