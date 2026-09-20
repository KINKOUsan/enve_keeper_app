// 首页拖拽控制器 — 复刻原型 §拖拽 的状态机：跟随硬币、悬停高亮、落点判定。
// 只管状态与命中判定，不建 Widget；视觉渲染在 home_page 的 Stack 覆盖层。
import 'package:flutter/material.dart';

import '../../../domain/models.dart';

// 拖拽的来源：待规划卡 / 信封卡
enum DragKind { budget, env }

// 拖拽结束后的判定结果 → 决定打开哪种键盘语境
enum DropAction { assign, unassign, transfer, expense }

// 一次落点判定的完整信息
class DropResult {
  const DropResult({required this.action, this.envId, this.toId});

  final DropAction action;

  /// unassign / expense 的来源信封；transfer 时是来源信封
  final String? envId;

  /// assign / transfer 的接收信封
  final String? toId;
}

// 一次拖拽会话（从拖动被识别到手指抬起）
class DragSession {
  DragSession({
    required this.kind,
    required this.envId,
    required this.position,
  });

  final DragKind kind;

  /// kind == env 时的信封 id
  final String? envId;

  /// 手指当前位置（全局坐标；渲染时换算成页面局部）
  Offset position;

  /// 悬停命中的信封 id（高亮显示；与源卡相同则不算）
  String? hoverEnvId;
}

// 首页手势状态机 — 拖拽命中判定。
// （原「点选目标模式」随长按菜单一起被操作面板取代——ADR-0014 §4，
// 跨页转移改走面板里的目标选择器。）
class HomeController extends ChangeNotifier {
  // ── 状态 ──

  // 进行中的拖拽；null = 没在拖
  DragSession? _drag;

  DragSession? get drag => _drag;

  // ── 命中注册表（home_page 同步注册，命中测试按 RenderBox 判定）──

  // 每个信封卡一个 GlobalKey（全部在用信封都注册，命中时再按当前页过滤）
  final Map<String, GlobalKey> envKeys = {};

  // 当前分页可见的信封 id 集（ADR-0014：硬币不跨页——命中只认这些 id）。
  // 由 home_page 每次 build 同步。
  Set<String> pageEnvIds = {};

  // 待规划卡
  final GlobalKey budgetKey = GlobalKey();

  // ── 拖拽生命周期 ──

  /// 拖动被识别（onPanStart，已越过框架滑动阈值）：会话开始，硬币出现。
  /// 按下不动不会走到这里——按下阶段无任何拖拽视觉（v1.2.0 票 05）。
  void begin(DragKind kind, String? envId, Offset globalPos) {
    _drag = DragSession(kind: kind, envId: envId, position: globalPos);
    notifyListeners();
  }

  /// 拖拽中（onPanUpdate）：更新位置、悬停命中
  void update(Offset globalPos) {
    final d = _drag;
    if (d == null) return;
    d.position = globalPos;
    final hit = hitTest(globalPos);
    d.hoverEnvId = (hit != null && hit != kToBudget && hit != d.envId)
        ? hit
        : null;
    notifyListeners();
  }

  /// 取消视觉（长按接管手势 / 点按结束时 pan 被拒绝）
  void cancel() {
    if (_drag == null) return;
    _drag = null;
    notifyListeners();
  }

  /// 手指抬起（onPanEnd）：按原型 onUp 判定落点。
  /// [dropY] 是落点判定线的**全局** Y（内容区底 −(56 导航条 + 12 外扩)）。
  /// 会话只在拖动被识别后存在——点按（未越过阈值）到这里自然是 null。
  DropResult? end({required double dropY}) {
    final d = _drag;
    cancel();
    if (d == null) return null;
    final p = d.position;

    // 支出：信封拖到屏幕底部边缘之外（照记不拦截，键盘里有软警告）
    if (d.kind == DragKind.env && p.dy > dropY) {
      return DropResult(action: DropAction.expense, envId: d.envId);
    }

    final hit = hitTest(p);
    if (hit == null) return null;
    // 待规划 → 信封：分配
    if (d.kind == DragKind.budget && hit != kToBudget) {
      return DropResult(action: DropAction.assign, toId: hit);
    }
    // 信封 → 待规划：撤销分配
    if (d.kind == DragKind.env && hit == kToBudget) {
      return DropResult(action: DropAction.unassign, envId: d.envId);
    }
    // 信封 → 信封：转移
    if (d.kind == DragKind.env && hit != kToBudget && hit != d.envId) {
      return DropResult(action: DropAction.transfer, envId: d.envId, toId: hit);
    }
    return null;
  }

  // ── 命中测试 ──

  /// 返回命中的信封 id / kToBudget（待规划卡）/ null（什么都没命中）。全局坐标。
  /// 信封只认当前分页（pageEnvIds）——硬币不跨页（ADR-0014 §3）。
  String? hitTest(Offset globalPos) {
    final budgetBox = _box(budgetKey);
    if (budgetBox != null && _hit(budgetBox, globalPos)) return kToBudget;
    for (final entry in envKeys.entries) {
      if (!pageEnvIds.contains(entry.key)) continue; // 邻页卡不参与命中
      final box = _box(entry.value);
      if (box != null && _hit(box, globalPos)) return entry.key;
    }
    return null;
  }

  // RenderBox 便利方法与命中判断
  RenderBox? _box(GlobalKey key) =>
      key.currentContext?.findRenderObject() as RenderBox?;

  bool _hit(RenderBox box, Offset globalPos) =>
      box.size.contains(box.globalToLocal(globalPos));
}
