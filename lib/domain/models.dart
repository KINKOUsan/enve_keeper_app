// 领域模型 — 与 IMPLEMENTATION.md §1 数据模型一一对应。
// 纯 Dart 类，不依赖 drift / Flutter，方便单测。
import 'package:flutter/foundation.dart';

/// 转移的 fromId/toId 用这个常量表示「待规划」
const String kToBudget = 'toBudget';

/// 默认货币符号（ADR-0017）：schema 列默认值与显示兜底的唯一出处。
/// 符号仅为显示偏好，按账本独立存储，不换算、不追溯历史金额。
const String kDefaultCurrency = '¥';

/// 交易类型：支出 / 收入 / 转移 / 结转退回。
/// 注意：分配（待规划→信封）与撤销（信封→待规划）在数据上都走 transfer，
/// 以 fromId/toId 是否为 kToBudget 区分（见原型 confirmSheet 的实现）。
/// refund（结转退回，ADR-0016）与 transfer 的「撤销分配」（信封→待规划）
/// 数据同构但类型可区分——详情页不会把撤销按钮错挂到系统行为上。
enum TxType { expense, income, transfer, refund }

/// 交易类型 ↔ 存库字符串
TxType txTypeFromDb(String v) => TxType.values.byName(v);
String txTypeToDb(TxType t) => t.name;

/// 金额运算统一保留 2 位小数，避免浮点漂移
double round2(double v) => (v * 100).roundToDouble() / 100;

/// 信封 — App 里唯一的资金容器（ADR-0001）。
/// 信封没有删除，只有停用与恢复（ADR-0012）：archivedAt 非空 = 已停用。
@immutable
class Envelope {
  const Envelope({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.planned,
    required this.used,
    this.target,
    required this.carryover,
    this.archivedAt,
  });

  final String id;
  final String name;

  /// 图标 id（见 lib/theme/envelope_icons.dart 的目录）
  final String icon;

  /// 颜色 id（见 lib/theme/tokens.dart 的 8 色目录）
  final String color;

  /// 本期被分配到的金额
  final double planned;

  /// 本期已发生的支出
  final double used;

  /// 可选目标额，只用于卡片上的进度条
  final double? target;

  /// 本期结余是否带入下一期
  final bool carryover;

  /// 停用时间；null = 在用（ADR-0012：停用≠删除，同名重建即恢复）
  final DateTime? archivedAt;

  /// 是否已停用
  bool get isArchived => archivedAt != null;

  /// 派生量，不落库：剩余 = 已规划 − 已使用。允许为负（透支合法，不变量①）。
  double get available => round2(planned - used);

  Envelope copyWith({
    String? name,
    String? icon,
    String? color,
    double? planned,
    double? used,
    double? target,
    bool? carryover,
    DateTime? archivedAt,
    bool clearTarget = false,
    bool clearArchived = false,
  }) {
    return Envelope(
      id: id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      planned: planned ?? this.planned,
      used: used ?? this.used,
      target: clearTarget ? null : (target ?? this.target),
      carryover: carryover ?? this.carryover,
      archivedAt: clearArchived ? null : (archivedAt ?? this.archivedAt),
    );
  }
}

/// 交易 — 流水里的一条记录，可修改可删除（不是只追加日志）
@immutable
class Txn {
  const Txn({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    required this.at,
    this.envelopeId,
    this.fromId,
    this.toId,
  });

  final String id;
  final TxType type;

  /// 恒为正数，方向由 type / fromId / toId 决定
  final double amount;

  /// 主标题。用户没填时兜底值在写入时定型，之后不随信封改名而变（不变量⑤）
  final String description;
  final DateTime at;

  /// type == expense 时必填
  final String? envelopeId;

  /// type == transfer / refund 时必填，可以是 kToBudget（即「分配」）
  final String? fromId;

  /// 同上
  final String? toId;

  Txn copyWith({
    double? amount,
    String? description,
    DateTime? at,
    String? envelopeId,
  }) {
    return Txn(
      id: id,
      type: type,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      at: at ?? this.at,
      envelopeId: envelopeId ?? this.envelopeId,
      fromId: fromId,
      toId: toId,
    );
  }

  /// 是否为「分配」记录（待规划 → 信封）
  bool get isAssign => type == TxType.transfer && fromId == kToBudget;

  /// 是否为「撤销分配」记录（信封 → 待规划）
  bool get isUnassign => type == TxType.transfer && toId == kToBudget;
}

/// 兜底描述（不变量⑤）。在写入交易的那一刻调用并落库，之后不再改。
String fallbackDescription({
  required TxType type,
  String? envelopeName,
  String? fromName,
  String? toName,
}) {
  switch (type) {
    case TxType.expense:
      return envelopeName ?? '一笔支出';
    case TxType.income:
      return '一笔收入';
    case TxType.transfer:
      return '${fromName ?? '未知'} → ${toName ?? '未知'}';
    case TxType.refund:
      // 结转退回（ADR-0016）：写入时定型「结转退回 · 信封名」
      return '结转退回 · ${envelopeName ?? '未知'}';
  }
}

/// 这笔流水涉及的已停用信封名（ADR-0012）。
/// 返回 null = 不涉及停用信封（正常走引擎撤销）；
/// 返回名字 = 撤销该笔时**不应改动任何余额**（停用信封账面已清零、钱已在停用时结算），
/// 只从流水档里移除这一条。
String? archivedEnvelopeNameOf(Txn t, List<Envelope> allEnvelopes) {
  final ids = <String?>[t.envelopeId, t.fromId, t.toId].whereType<String>();
  for (final id in ids) {
    if (id == kToBudget) continue;
    for (final e in allEnvelopes) {
      if (e.id == id && e.isArchived) return e.name;
    }
  }
  return null;
}

/// 账本内的一份状态快照：待规划金额 + 全部信封。
/// tx_engine 的施加/撤销都以它为输入、返回新快照（不可变风格）。
@immutable
class LedgerState {
  const LedgerState({required this.toBudget, required this.envelopes});

  /// 尚未分配到任何信封的钱，不允许为负（不变量②）
  final double toBudget;
  final Map<String, Envelope> envelopes;
}
