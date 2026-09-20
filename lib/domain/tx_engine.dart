// 交易引擎 — 不变量③④⑥的核心：把「一笔交易对状态的影响」施加（+1）与撤销（−1）。
// 删除 = 撤销；编辑 = 撤销旧的 + 施加新的。全部为纯函数，便于单测。
import 'models.dart';

/// 金额的符号：施加 +1 / 撤销 −1
const double kApply = 1;
const double kRevert = -1;

/// 把一笔交易的影响施加到状态上，返回新状态。
///
/// ⚠️ 不变量⑥警告：如果数据库里预置了演示流水，那些流水已反映在初始余额里，
/// 加载时**不要**重放；只在「新增 / 编辑 / 删除」时调用本函数。
LedgerState applyTx(LedgerState s, Txn t, double sign) {
  var toBudget = s.toBudget;
  final envs = Map.of(s.envelopes);

  // 按需改某个信封的已规划/已使用，round2 防浮点漂移
  void plan(String? id, double Function(double) f) {
    final e = envs[id];
    if (e != null) envs[id!] = e.copyWith(planned: round2(f(e.planned)));
  }

  switch (t.type) {
    case TxType.expense:
      // 支出只影响 used；照记不拦截（不变量①），透支合法
      final e = envs[t.envelopeId];
      if (e != null) {
        envs[t.envelopeId!] = e.copyWith(
          used: round2(e.used + sign * t.amount),
        );
      }
    case TxType.income:
      // 收入只进 toBudget（不变量④）
      toBudget = round2(toBudget + sign * t.amount);
    case TxType.transfer:
      final from = t.fromId, to = t.toId;
      // 待规划 → 信封：分配
      if (from == kToBudget) {
        toBudget = round2(toBudget - sign * t.amount);
        plan(to, (v) => v + sign * t.amount);
      }
      // 信封 → 待规划：撤销分配
      else if (to == kToBudget) {
        plan(from, (v) => v - sign * t.amount);
        toBudget = round2(toBudget + sign * t.amount);
      }
      // 信封 → 信封：转移，零和、toBudget 不动（不变量③）
      else {
        plan(from, (v) => v - sign * t.amount);
        plan(to, (v) => v + sign * t.amount);
      }
    case TxType.refund:
      // 结转退回（ADR-0016）：信封 → 待规划，按转移语义处理（零和，不变量③）。
      // 与「撤销分配」数据同构但类型可区分——引擎侧同样是「信封扣减、待规划增加」。
      plan(t.fromId, (v) => v - sign * t.amount);
      toBudget = round2(toBudget + sign * t.amount);
  }
  return LedgerState(toBudget: toBudget, envelopes: envs);
}

/// 删除一笔交易是否安全：撤销之后 toBudget 不允许变成负数（不变量⑦）。
/// 只有「收入」「撤销分配」「结转退回」的撤销会减少 toBudget
/// （结转退回不可从 UI 撤销，但引擎层面守卫保持一致）。
bool deleteKeepsToBudgetNonNegative(LedgerState s, Txn t) {
  if (t.type == TxType.expense) return true;
  if (t.type == TxType.transfer && !t.isUnassign) return true;
  return round2(s.toBudget - t.amount) >= 0;
}

/// 编辑（revert 旧 + apply 新）之后 toBudget 是否仍非负（不变量⑦在编辑路径的延伸）。
/// [newAmount] 是改后的金额；类型 / 信封 / 时间在编辑时不变。
bool editKeepsToBudgetNonNegative(LedgerState s, Txn oldTx, double newAmount) {
  final reverted = applyTx(s, oldTx, kRevert);
  final newTx = Txn(
    id: oldTx.id,
    type: oldTx.type,
    amount: newAmount,
    description: oldTx.description,
    at: oldTx.at,
    envelopeId: oldTx.envelopeId,
    fromId: oldTx.fromId,
    toId: oldTx.toId,
  );
  final applied = applyTx(reverted, newTx, kApply);
  return applied.toBudget >= 0;
}

/// 「从待规划分配」的校验（不变量②唯一执行点）：
/// 上限就是 toBudget 当前值。返回 null 表示通过，否则返回不可用原因。
/// [symbol] 为当前账本货币符号（ADR-0017），仅用于文案显示。
String? validateAssign(
  LedgerState s,
  double amount, {
  String symbol = kDefaultCurrency,
}) {
  if (amount > s.toBudget) {
    return '待规划只有 $symbol${_fmt(s.toBudget)}，分配不能超过它';
  }
  return null;
}

/// 支出的软警告：超出部分会把信封花成负数——照记，不拦截（不变量①）
String? warnExpense(
  LedgerState s,
  String envelopeId,
  double amount, {
  String symbol = kDefaultCurrency,
}) {
  final e = s.envelopes[envelopeId];
  if (e == null) return null;
  if (amount > e.available) {
    return '记完后「${e.name}」会透支 $symbol${_fmt(amount - e.available)}，到流水里补上就行';
  }
  return null;
}

// 转移的软警告：来源信封余额不足
String? warnTransfer(
  LedgerState s,
  String fromId,
  double amount, {
  String symbol = kDefaultCurrency,
}) {
  final e = s.envelopes[fromId];
  if (e == null) return null;
  if (amount > e.available) {
    return '「${e.name}」只剩 $symbol${_fmt(e.available)}，超出部分会把它花成负数';
  }
  return null;
}

/// 撤销分配的软警告：planned 扣到负数即信封透支
String? warnUnassign(
  LedgerState s,
  String envelopeId,
  double amount, {
  String symbol = kDefaultCurrency,
}) {
  final e = s.envelopes[envelopeId];
  if (e == null) return null;
  if (amount > e.available) {
    return '「${e.name}」只剩 $symbol${_fmt(e.available)}，超出部分会把它花成负数';
  }
  return null;
}

/// 编辑金额的硬阻判断 + 提示文案（编辑校验统一走「revert 旧 + apply 新」）。
/// [symbol] 为当前账本货币符号（ADR-0017），仅用于文案显示。
({bool hard, String? warn}) validateEditAmount(
  LedgerState s,
  Txn oldTx,
  double newAmount, {
  String symbol = kDefaultCurrency,
}) {
  final hard = !editKeepsToBudgetNonNegative(s, oldTx, newAmount);
  if (hard) {
    // 分两种情形给文案：收入被分配出去 / 分配金额改大会掏空待规划
    if (oldTx.type == TxType.income) {
      return (hard: true, warn: '这笔收入已经分配出去了，再改待规划会变成负数');
    }
    return (hard: true, warn: '待规划会变成负数');
  }
  // 软警告：改完后受影响的信封可能透支
  switch (oldTx.type) {
    case TxType.expense:
      final e = s.envelopes[oldTx.envelopeId];
      if (e == null) return (hard: false, warn: null);
      final after = round2(e.available + oldTx.amount - newAmount);
      if (after < 0) {
        return (hard: false, warn: '改完后「${e.name}」会透支 $symbol${_fmt(-after)}');
      }
    case TxType.income:
      break;
    case TxType.transfer:
      final fromId = oldTx.fromId;
      if (fromId == null || fromId == kToBudget) break;
      final f = s.envelopes[fromId];
      if (f == null) return (hard: false, warn: null);
      final after = round2(f.available + oldTx.amount - newAmount);
      if (after < 0) {
        return (hard: false, warn: '改完后「${f.name}」会透支 $symbol${_fmt(-after)}');
      }
    case TxType.refund:
      // 结转退回不可从 UI 编辑（系统行为），此处仅为引擎穷尽性兜底：
      // 语义与「信封 → 待规划」的转移一致，按来源信封给软警告
      final f = s.envelopes[oldTx.fromId];
      if (f == null) return (hard: false, warn: null);
      final after = round2(f.available + oldTx.amount - newAmount);
      if (after < 0) {
        return (hard: false, warn: '改完后「${f.name}」会透支 $symbol${_fmt(-after)}');
      }
  }
  return (hard: false, warn: null);
}

/// 金额格式化（校验文案内使用，不带货币符号前缀的裸数字见 UI 层）
String _fmt(double v) {
  final abs = v.abs();
  final isInt = abs == abs.roundToDouble();
  final s = isInt ? abs.toStringAsFixed(0) : abs.toStringAsFixed(2);
  return s;
}
