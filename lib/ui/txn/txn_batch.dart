// 流水多选与批量撤销 — 流水页 / 信封详情页共用（ADR-0012）。
// 多选：长按进入，点行切换，支持全选与按日组选择；撤销：整批预检、原子执行。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../domain/tx_engine.dart';
import '../../state/providers.dart';
import '../../theme/tokens.dart';
import '../common/format.dart';
import '../keypad/keypad_flow.dart';

/// 多选状态机：选中集合 + 是否处于多选模式
class TxnSelection extends ChangeNotifier {
  final Set<String> _ids = {};
  bool _mode = false;

  bool get mode => _mode;
  Set<String> get ids => Set.unmodifiable(_ids);
  int get count => _ids.length;

  // 进入多选并选中第一笔（长按触发）
  void enter(String id) {
    _mode = true;
    _ids.clear();
    _ids.add(id);
    notifyListeners();
  }

  // 退出多选并清空
  void exit() {
    _mode = false;
    _ids.clear();
    notifyListeners();
  }

  // 切换一笔
  void toggle(String id) {
    if (!_mode) return;
    if (_ids.contains(id)) {
      _ids.remove(id);
      if (_ids.isEmpty) _mode = false; // 全取消时自动退出多选
    } else {
      _ids.add(id);
    }
    notifyListeners();
  }

  // 全选 / 全不选
  void toggleAll(List<Txn> pool) {
    if (_ids.length >= pool.length) {
      _ids.clear();
      _mode = false;
    } else {
      _ids
        ..clear()
        ..addAll(pool.map((t) => t.id));
    }
    notifyListeners();
  }

  // 切换一组（按日区间选择）：组内全在则取消，否则全选
  void toggleGroup(List<Txn> group) {
    if (!_mode) return;
    final allIn = group.every((t) => _ids.contains(t.id));
    if (allIn) {
      _ids.removeAll(group.map((t) => t.id));
    } else {
      _ids.addAll(group.map((t) => t.id));
    }
    notifyListeners();
  }

  // 从选中集合里取交易对象（保持传入顺序）
  List<Txn> pick(List<Txn> pool) =>
      pool.where((t) => _ids.contains(t.id)).toList();
}

/// 批量撤销确认：整批预检（不变量⑦）+ 后果文案。返回是否确认。
/// 涉及停用信封的笔不参与预检与余额计算（ADR-0012 分流），文案单独说明。
Future<bool> confirmBatchRevert(
  BuildContext context,
  WidgetRef ref,
  List<Txn> txns,
) async {
  final state = ref.read(ledgerStateProvider);
  final all = ref.read(allEnvelopesProvider).value ?? const <Envelope>[];

  // 关键步骤：整批预检引擎笔——任何一笔会破坏待规划非负就指出它（不弹确认框）
  var sim = state;
  var archivedCount = 0;
  String? archivedName;
  for (final t in txns) {
    final name = archivedEnvelopeNameOf(t, all);
    if (name != null) {
      // 停用信封的笔：不碰余额，跳过预检
      archivedCount++;
      archivedName ??= name;
      continue;
    }
    if (!deleteKeepsToBudgetNonNegative(sim, t)) {
      if (!context.mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('有记录撤不掉'),
          content: Text(
            '「${t.description}」撤销后待规划会变成负数。'
            '把它从选择里去掉，或先单独处理它。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return false;
    }
    sim = applyTx(sim, t, kRevert);
  }

  // 后果汇总：支出/收入合计 + 待规划变化
  final expense = txns
      .where((t) => t.type == TxType.expense)
      .fold(0.0, (a, t) => round2(a + t.amount));
  final income = txns
      .where((t) => t.type == TxType.income)
      .fold(0.0, (a, t) => round2(a + t.amount));

  if (!context.mounted) return false;
  // 当前账本货币符号（ADR-0017）：后果汇总文案用
  final symbol = ref.read(currencySymbolProvider);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('撤销这 ${txns.length} 笔流水？'),
      content: Text(
        '${expense > 0 ? '合计支出 $symbol${money(expense)}；' : ''}'
        '${income > 0 ? '合计收入 $symbol${money(income)}；' : ''}'
        '${archivedCount > 0 ? '其中 $archivedCount 笔属于已停用的「$archivedName」，不会改变任何余额；' : ''}'
        '相关信封余额会自动重算，待规划会从 $symbol${money(state.toBudget)} '
        '变为 $symbol${money(sim.toBudget)}。\n撤销后这些流水会从列表移除，不能恢复。',
      ),
      // 注意：actions 是 OverflowBar（非 Flex），不能放 Expanded
      actionsAlignment: MainAxisAlignment.spaceEvenly,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          style: TextButton.styleFrom(
            backgroundColor: T.surfaceSubtle,
            foregroundColor: T.textSecondary,
            minimumSize: const Size(110, 44),
          ),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(
            backgroundColor: T.overspend,
            foregroundColor: Colors.white,
            minimumSize: const Size(110, 44),
          ),
          child: const Text('撤销'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// 执行批量撤销（确认已在 confirmBatchRevert 完成）
Future<void> executeBatchRevert(
  BuildContext context,
  WidgetRef ref,
  List<Txn> txns,
) async {
  final ledger = ref.read(activeLedgerProvider);
  if (ledger == null) return;
  final blocked = await ref
      .read(repoProvider)
      .revertTransactions(ledgerId: ledger.id, txns: txns);
  if (!context.mounted) return;
  if (blocked != null) {
    appToast(context, '「${blocked.description}」撤不掉，其余未动');
  } else {
    appToast(context, '已撤销 ${txns.length} 笔，余额已重算');
  }
}
