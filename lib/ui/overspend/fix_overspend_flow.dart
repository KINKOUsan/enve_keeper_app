// 透支补救腾挪流程（DESIGN.md §10 / ADR-0003）：
// 提示条「去补上」→（多个透支时先选目标）→ 选来源信封 → 数字键盘（transfer 语境，文案换为「腾挪」）→ 落库。
// 完全复用数字键盘，只换上下文文案；补完后提示条随数据流自动消失。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../theme/envelope_icons.dart';
import '../../theme/tokens.dart';
import '../common/format.dart';
import '../copy.dart';
import '../keypad/keypad_flow.dart';
import '../keypad/keypad_models.dart';

/// 当前透支中的信封（available < 0，不变量①：透支合法，事后补）
List<Envelope> overspendingEnvelopes(List<Envelope> envelopes) =>
    envelopes.where((e) => e.available < 0).toList();

/// 缺口总额
double totalShortfall(List<Envelope> overs) =>
    overs.fold(0.0, (acc, e) => round2(acc - e.available));

/// 打开腾挪流程入口。
/// 单个透支 → 直接选来源；多个 → 先弹透支列表选目标。
Future<void> runFixOverspendFlow(BuildContext context, WidgetRef ref) async {
  final envelopes = ref.read(envelopesProvider).value ?? const <Envelope>[];
  final overs = overspendingEnvelopes(envelopes);
  if (overs.isEmpty) return;
  if (!context.mounted) return;

  var target = overs.first;
  if (overs.length > 1) {
    // 多个透支：先选要补哪个
    final picked = await showModalBottomSheet<Envelope>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x57000000),
      builder: (_) => _EnvelopePickSheet(
        title: fixOverspendPickTargetTitle,
        hint: fixOverspendPickTargetHint,
        envelopes: overs,
        rowBuilder: (e) => money(-e.available),
      ),
    );
    if (picked == null || !context.mounted) return;
    target = picked;
  }
  await _pickSourceAndFix(context, ref, target);
}

// 选来源信封 → 打开腾挪键盘
Future<void> _pickSourceAndFix(
  BuildContext context,
  WidgetRef ref,
  Envelope target,
) async {
  final envelopes = ref.read(envelopesProvider).value ?? const <Envelope>[];
  // 来源候选：其他信封（不能用待规划补，也不能补给自己——原型 onPick('__fix__')）
  final sources = envelopes.where((e) => e.id != target.id).toList()
    ..sort((a, b) => b.available.compareTo(a.available));
  if (!context.mounted) return;
  // 当前账本货币符号（ADR-0017）：候选行剩余金额文案用
  final symbol = ref.read(currencySymbolProvider);

  final source = await showModalBottomSheet<Envelope>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x57000000),
    builder: (_) => _EnvelopePickSheet(
      title: fixOverspendPickSourceTitle(target.name),
      hint: fixOverspendPickSourceHint,
      envelopes: sources,
      rowBuilder: (e) => '剩 $symbol${money(e.available)}',
    ),
  );
  if (source == null || !context.mounted) return;

  // 打开数字键盘：transfer 语境，只换上下文文案（DESIGN.md §10）
  await runKeypadFlow(
    context,
    ref,
    KeypadRequest(
      action: KeypadAction.transfer,
      fromId: source.id,
      envelopeId: target.id,
      titleOverride: fixOverspendPickSourceTitle(target.name),
      subtitleOverride: fixOverspendSourceSubtitle(
        source.name,
        source.available,
        symbol: symbol,
      ),
    ),
  );
}

// ── 信封选择弹层 ────────────────────────────────

// 通用选择列表：标题 + 提示 + 信封行（右值由 rowBuilder 定制）
class _EnvelopePickSheet extends StatelessWidget {
  const _EnvelopePickSheet({
    required this.title,
    required this.hint,
    required this.envelopes,
    required this.rowBuilder,
  });

  final String title;
  final String hint;
  final List<Envelope> envelopes;

  // 行右侧数值文案
  final String Function(Envelope) rowBuilder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: T.surface,
        borderRadius: BorderRadius.circular(20),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: T.typeMd,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                  child: Text(
                    hint,
                    style: const TextStyle(
                      fontSize: T.typeXs,
                      color: T.textTertiary,
                    ),
                  ),
                ),
                for (final e in envelopes)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(context, e),
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          // 32dp 信封图标块
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: envelopeColorById(e.color).tint,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Icon(
                              envelopeIconById(e.icon),
                              size: 16,
                              color: envelopeColorById(e.color).main,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              e.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: T.typeBase,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            rowBuilder(e),
                            style: TextStyle(
                              fontSize: T.typeSm,
                              fontWeight: FontWeight.w500,
                              // 透支目标行显示红色缺口；来源行显示普通剩余
                              color: e.available < 0
                                  ? T.overspend
                                  : const Color(0xFF6E675C),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
