// 键盘提交流程编排 — KeypadRequest → 交易构建 + 兜底描述（不变量⑤/ADR-0008）→ 落库 → 结果提示。
// 四个手势、长按菜单、流水页入口都汇到这里；UI 不直接调仓库，仓库不弹提示。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../copy.dart';
import 'keypad_models.dart';
import 'keypad_sheet.dart';

/// 打开数字键盘，确认后按动作语境构建交易并落库。返回是否成功提交。
///
/// [context] 必须是页面级 context（键盘弹出/关闭后仍有效，用于提示）。
Future<bool> runKeypadFlow(
  BuildContext context,
  WidgetRef ref,
  KeypadRequest request,
) async {
  final repo = ref.read(repoProvider);
  final ledger = ref.read(activeLedgerProvider);
  if (ledger == null) return false;
  final ledgerId = ledger.id;
  // 异步间隙前先拿好 messenger，回调里不再持有 context
  final messenger = ScaffoldMessenger.of(context);

  final ok = await showKeypadSheet(
    context,
    request,
    onConfirm: (amount, note) async {
      // 提交瞬间重新读一次状态，保证兜底描述里的信封名是当前的
      final state = ref.read(ledgerStateProvider);

      // 信封名只用于兜底描述与提示文案（不变量⑤：写入那一刻定型，之后不随改名而变）
      String envName(String? id) => id == null
          ? unknownEnvelope
          : (state.envelopes[id]?.name ?? unknownEnvelope);

      switch (request.action) {
        case KeypadAction.assign:
          // 待规划 → 信封（不变量②唯一执行点，键盘里已硬阻超额）
          await submitAssign(
            messenger,
            ref,
            ledgerId: ledgerId,
            envelopeId: request.envelopeId!,
            amount: amount,
            note: note,
          );

        case KeypadAction.unassign:
          // 信封 → 待规划
          await repo.addTransaction(
            ledgerId: ledgerId,
            fallback: fallbackDescription(
              type: TxType.transfer,
              fromName: envName(request.envelopeId),
              toName: '待规划',
            ),
            txn: Txn(
              id: repo.newTxnId(),
              type: TxType.transfer,
              amount: amount,
              description: note,
              at: DateTime.now(),
              fromId: request.envelopeId,
              toId: kToBudget,
            ),
          );
          _toast(messenger, toastUnassigned(amount));

        case KeypadAction.transfer:
          // 信封 → 信封：零和，不计收支（不变量③）
          await repo.addTransaction(
            ledgerId: ledgerId,
            fallback: fallbackDescription(
              type: TxType.transfer,
              fromName: envName(request.fromId),
              toName: envName(request.envelopeId),
            ),
            txn: Txn(
              id: repo.newTxnId(),
              type: TxType.transfer,
              amount: amount,
              description: note,
              at: DateTime.now(),
              fromId: request.fromId,
              toId: request.envelopeId,
            ),
          );
          _toast(
            messenger,
            toastTransferredOut(envName(request.fromId), amount),
          );

        case KeypadAction.expense:
          // 落库后的透支额可以直接算：available − amount（负数即透支，照记不拦截，不变量①）
          final e = state.envelopes[request.envelopeId];
          final overdraft = e == null ? 0.0 : round2(e.available - amount);
          await repo.addTransaction(
            ledgerId: ledgerId,
            fallback: fallbackDescription(
              type: TxType.expense,
              envelopeName: envName(request.envelopeId),
            ),
            txn: Txn(
              id: repo.newTxnId(),
              type: TxType.expense,
              amount: amount,
              description: note,
              at: DateTime.now(),
              envelopeId: request.envelopeId,
            ),
          );
          _toast(
            messenger,
            overdraft < 0
                ? toastExpenseOverspent(e?.name, -overdraft)
                : toastExpense(e?.name, amount),
          );

        case KeypadAction.income:
          // 收入只进 toBudget（不变量④）
          await repo.addTransaction(
            ledgerId: ledgerId,
            fallback: fallbackDescription(type: TxType.income),
            txn: Txn(
              id: repo.newTxnId(),
              type: TxType.income,
              amount: amount,
              description: note,
              at: DateTime.now(),
            ),
          );
          _toast(messenger, toastIncome(amount));

        case KeypadAction.editAmount:
          // 不变量⑥：撤销旧的 + 施加新的；原型行为——填了描述则一并更新
          final tx = request.editTx!;
          await repo.editTransactionAmount(
            ledgerId: ledgerId,
            oldTxn: tx,
            newAmount: amount,
          );
          if (note.isNotEmpty) {
            await repo.editTransactionDescription(tx.id, note);
          }
          _toast(messenger, toastAmountEdited(amount));
      }
    },
  );
  return ok;
}

/// 分配提交（待规划 → 信封，不变量④收入进待规划后的唯一出口）。
/// 供键盘流程与长按面板「快捷分配」共用；提交瞬间重读状态定型兜底描述（不变量⑤）。
/// 超额校验在入口 UI（键盘/面板确定键置灰）执行，这里不再拦截。
Future<void> submitAssign(
  ScaffoldMessengerState messenger,
  WidgetRef ref, {
  required String ledgerId,
  required String envelopeId,
  required double amount,
  String note = '',
}) async {
  final repo = ref.read(repoProvider);
  // 提交瞬间重新读一次状态，保证兜底描述里的信封名是当前的
  final state = ref.read(ledgerStateProvider);
  final envName = state.envelopes[envelopeId]?.name ?? unknownEnvelope;
  await repo.addTransaction(
    ledgerId: ledgerId,
    fallback: fallbackDescription(
      type: TxType.transfer,
      fromName: '待规划',
      toName: envName,
    ),
    txn: Txn(
      id: repo.newTxnId(),
      type: TxType.transfer,
      amount: amount,
      description: note,
      at: DateTime.now(),
      fromId: kToBudget,
      toId: envelopeId,
    ),
  );
  _toast(messenger, toastAssigned(amount, envName));
}

/// 轻提示 — 对齐原型的 toast：短文案、自动消失、不打断操作。
void appToast(BuildContext context, String text) {
  _toast(ScaffoldMessenger.of(context), text);
}

// 用 messenger 直接弹提示（供已跨 async 的回调使用，避免持有 context）
void _toast(ScaffoldMessengerState messenger, String text) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(milliseconds: 1800),
      ),
    );
}
