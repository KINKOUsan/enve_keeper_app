// 信封管理页 — 推入页，无底部导航（DESIGN.md §13）。
// 长按行拖拽调整顺序；点行进入编辑弹层（改名/图标/颜色/结转/删除）；底部「新建信封」。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models.dart';
import '../../../state/providers.dart';
import '../../../theme/envelope_icons.dart';
import '../../../theme/tokens.dart';
import '../../common/app_route.dart';
import '../../envelope/create_envelope_sheet.dart';
import '../../envelope/envelope_edit_sheet.dart';
import '../../envelope/envelope_detail_page.dart';

class EnvelopeManagePage extends ConsumerWidget {
  const EnvelopeManagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final envelopes = ref.watch(envelopesProvider).value ?? const [];

    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 页头：返回 + 标题 + 「完成」 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: Material(
                        color: T.surfaceSubtle,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => Navigator.of(context).pop(),
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            size: 16,
                            color: T.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      '信封管理',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            // 提示行
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '长按拖动调整顺序；点任意一行可以改名称、图标、颜色和结转开关。',
                style: TextStyle(fontSize: T.typeXs, color: Color(0xFFB4AC9F)),
              ),
            ),
            const SizedBox(height: 12),
            // ── 管理行组：可拖拽排序 ──
            Expanded(
              child: envelopes.isEmpty
                  ? const Center(
                      child: Text(
                        '还没有信封',
                        style: TextStyle(fontSize: 14, color: T.textTertiary),
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      buildDefaultDragHandles: false,
                      proxyDecorator: _dragProxy,
                      itemCount: envelopes.length,
                      onReorderItem: (oldIndex, newIndex) =>
                          _reorder(ref, envelopes, oldIndex, newIndex),
                      itemBuilder: (context, i) => _ManageRow(
                        key: ValueKey(envelopes[i].id),
                        envelope: envelopes[i],
                        index: i,
                        onTap: () => _openEdit(context, ref, envelopes[i]),
                      ),
                    ),
            ),
            // ── 新建信封：暖黄描边按钮 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                height: 52,
                child: Material(
                  color: const Color(0xFFFFF3D1),
                  shape: StadiumBorder(
                    side: BorderSide(color: const Color(0xFFFFE49B), width: 1),
                  ),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => showCreateEnvelopeSheet(context, ref),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 18, color: T.primaryDeep),
                        SizedBox(width: 6),
                        Text(
                          '新建信封',
                          style: TextStyle(
                            fontSize: T.typeBase,
                            fontWeight: FontWeight.w600,
                            color: T.primaryDeep,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 拖拽中的代理装饰：轻微放大 + 阴影
  Widget _dragProxy(Widget child, int index, Animation<double> animation) {
    return ScaleTransition(
      scale: Tween(begin: 1.0, end: 1.03).animate(animation),
      child: Material(
        color: Colors.transparent,
        elevation: 6,
        borderRadius: BorderRadius.circular(14),
        child: child,
      ),
    );
  }

  // 排序落库（onReorderItem 的 newIndex 已自动调整，无需修正）
  Future<void> _reorder(
    WidgetRef ref,
    List<Envelope> envelopes,
    int oldIndex,
    int newIndex,
  ) async {
    final list = [...envelopes];
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    final repo = ref.read(repoProvider);
    for (var i = 0; i < list.length; i++) {
      await repo.updateEnvelope(list[i].id, sortOrder: i);
    }
  }

  // 进入编辑弹层
  Future<void> _openEdit(
    BuildContext context,
    WidgetRef ref,
    Envelope envelope,
  ) async {
    await showEditEnvelopeSheet(context, ref, envelope);
  }
}

// ── 管理行（高 60）──────────────────────────────

/// 32dp 图标块 + 名 + 结转标记 + 16dp 拖拽把手
class _ManageRow extends ConsumerWidget {
  const _ManageRow({
    super.key,
    required this.envelope,
    required this.index,
    required this.onTap,
  });

  final Envelope envelope;

  // 列表中的位置（拖拽把手需要）
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = envelope;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.of(context).pop(); // 退出管理页
        Navigator.of(context).push(
          AppPageRoute<void>(
            builder: (_) => EnvelopeDetailPage(envelopeId: e.id),
          ),
        );
      },
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            // 32dp 圆角图标块（信封色实底 + 白图标）
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: envelopeColorById(e.color).main,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                envelopeIconById(e.icon),
                size: 16,
                color: Colors.white,
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
            // 结转标记：开 = 浅底胶囊「结转」；关 = 无底灰字「不结转」
            Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: e.carryover ? T.surfaceSubtle : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                e.carryover ? '结转' : '不结转',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: e.carryover ? const Color(0xFF6E675C) : T.textTertiary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // 拖拽把手
            ReorderableDragStartListener(
              index: index,
              child: const SizedBox(
                width: 32,
                height: 32,
                child: Icon(Icons.drag_handle, size: 16, color: T.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
