// 数字键盘的请求模型 — 四个手势 + 长按菜单 + 交易编辑都汇到这里（ADR-0002：三入口同一个键盘）。
import '../../domain/models.dart';

// 键盘的动作语境
enum KeypadAction {
  assign, // 待规划 → 信封（不变量②唯一执行点）
  unassign, // 信封 → 待规划
  transfer, // 信封 → 信封
  expense, // 信封 → 外界
  income, // 外界 → 待规划
  editAmount, // 改一笔交易的金额
}

// 一次键盘调用的全部上下文：动作 + 参与的信封 + 要编辑的交易。
class KeypadRequest {
  const KeypadRequest({
    required this.action,
    this.envelopeId,
    this.fromId,
    this.editTx,
    this.initialExpr,
    this.okLabel = '确定',
    this.titleOverride,
    this.subtitleOverride,
  });

  final KeypadAction action;

  /// assign/expense/unassign：目标（来源）信封 id；transfer：接收方信封 id
  final String? envelopeId;

  /// transfer 的来源信封 id
  final String? fromId;

  /// editAmount 时必须给
  final Txn? editTx;

  /// 键入框的初始表达式（编辑金额时预填当前值）
  final String? initialExpr;

  /// 确定键文案（引导第 1 屏用「下一步」）
  final String okLabel;

  /// 覆盖上下文标题（腾挪流程用「腾挪到「医疗」」，DESIGN.md §10）
  final String? titleOverride;

  /// 覆盖上下文副标题（腾挪流程用「从「娱乐」支出 · 剩 ¥X」）
  final String? subtitleOverride;
}
