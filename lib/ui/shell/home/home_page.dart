// 首页（信封）— 弧形待规划头部 + 日期行 + 固定网格分页 + 拖拽覆盖层
// （DESIGN.md §3/§4 v1.1.0 · ADR-0014 固定网格分页）。
// 手势（复刻原型 §拖拽）：
//   待规划拖到信封 = 分配 · 信封拖回待规划 = 撤销 · 信封拖到信封 = 转移
//   信封拖到底部边缘 / 双击信封卡 = 记支出 · 长按信封 = 操作面板 · 点待规划 = 记收入
// 分页（ADR-0014）：2 列 × 5 行 = 每页 10 个、绝不滚动；>10 个出圆点分页器；
// 硬币不跨页——命中注册表只含当前页的卡，跨页分配走长按面板的选择器。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models.dart';
import '../../../domain/period_logic.dart';
import '../../../state/providers.dart';
import '../../../theme/tokens.dart';
import '../../copy.dart';
import '../../keypad/keypad_flow.dart';
import '../../keypad/keypad_models.dart';
import '../../envelope/create_envelope_sheet.dart';
import '../../envelope/envelope_detail_page.dart';
import '../../ledger/period_settings_page.dart';
import 'budget_arc_header.dart';
import 'envelope_action_panel.dart';
import 'envelope_card.dart';
import 'home_controller.dart';
import 'home_skeleton.dart';

// 每页容量：2 列 × 5 行（ADR-0014）
const int kEnvelopesPerPage = 10;

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key, required this.gesture});

  // 手势状态机：由 AppShell 拥有并与引导遮罩共享（构造注入，避免在
  // initState/dispose 里改 provider——Riverpod 3 会抛 tree-building 异常）
  final HomeController gesture;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  // 页面坐标系（手势状态机经 [HomePage.gesture] 注入）
  final _bodyKey = GlobalKey();

  // 统一入口：页面内沿用 _controller 引用
  HomeController get _controller => widget.gesture;

  // 当前分页（内存态，不入库——ADR-0014）；0 起
  int _page = 0;
  final _pageController = PageController();

  // 落点带几何常量（与原型一致）：判定线 = 内容区底 −(56 导航条 + 12 外扩) = −68
  static const double _dropInset = 68;
  // 渐变从判定线上方 132 处开始显现
  static const double _glowAboveDrop = 132;

  @override
  void initState() {
    super.initState();
    // 拖拽状态一变就整页重绘（覆盖层要跟手，频率可接受）
    widget.gesture.addListener(_onGestureChanged);
  }

  @override
  void dispose() {
    // 控制器归 AppShell 所有，这里只摘掉监听、不销毁
    widget.gesture.removeListener(_onGestureChanged);
    _pageController.dispose();
    super.dispose();
  }

  // 拖拽状态变化 → 整页重绘
  void _onGestureChanged() => setState(() {});

  // ── 落点几何 ──

  // 落点判定线的全局 Y（end() 里与全局手指坐标比较）
  double _dropYGlobal() {
    final bodyBox = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    if (bodyBox == null || !bodyBox.attached) return double.infinity;
    final h = bodyBox.size.height;
    return bodyBox.localToGlobal(Offset(0, h - _dropInset)).dy;
  }

  // ── 手势入口 ──

  // 拖拽结束：按判定结果打开对应语境的键盘
  Future<void> _handleDrop(DropResult? res) async {
    if (res == null) return;
    switch (res.action) {
      case DropAction.assign:
        await _openKeypad(
          KeypadRequest(action: KeypadAction.assign, envelopeId: res.toId),
        );
      case DropAction.unassign:
        await _openKeypad(
          KeypadRequest(action: KeypadAction.unassign, envelopeId: res.envId),
        );
      case DropAction.transfer:
        await _openKeypad(
          KeypadRequest(
            action: KeypadAction.transfer,
            fromId: res.envId,
            envelopeId: res.toId,
          ),
        );
      case DropAction.expense:
        await _openKeypad(
          KeypadRequest(action: KeypadAction.expense, envelopeId: res.envId),
        );
    }
  }

  // 点待规划卡 = 记一笔收入
  Future<void> _onBudgetTap() async {
    await _openKeypad(const KeypadRequest(action: KeypadAction.income));
  }

  // 点信封卡 = 进详情
  Future<void> _onEnvTap(String envId) async {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EnvelopeDetailPage(envelopeId: envId),
      ),
    );
  }

  // 双击信封卡 = 记一笔支出（与拖到底部边缘落点带同一效果）
  Future<void> _onEnvDoubleTap(String envId) async {
    await _openKeypad(
      KeypadRequest(action: KeypadAction.expense, envelopeId: envId),
    );
  }

  // 长按信封 = 操作面板（ADR-0014 §4：快捷分配主动作 + 记支出 / 跨页转移）
  Future<void> _openActionPanel(String envId) async {
    if (!mounted) return;
    await showEnvelopeActionPanel(context, ref, envId);
  }

  Future<void> _openKeypad(KeypadRequest request) =>
      runKeypadFlow(context, ref, request);

  // 进入预算周期设置页（日期行整行可点，DESIGN.md §3 v1.1.0）
  void _openPeriodSettings(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const PeriodSettingsPage()));
  }

  // ── 构建 ──

  @override
  Widget build(BuildContext context) {
    // 异步 watches：loading 状态供骨架门使用（§18：>200ms 才显示骨架）
    final envelopesAsync = ref.watch(envelopesProvider);
    final settingsAsync = ref.watch(settingsProvider);
    final envelopes = envelopesAsync.value ?? const [];
    final toBudget = settingsAsync.value?.toBudget ?? 0;
    // 当前账本货币符号（ADR-0017）：头部金额与信封卡共用
    final symbol = ref.watch(currencySymbolProvider);
    // 金额隐私偏好（v1.2.0 票 03）：仅首页生效，进度条不藏。
    // watch 在 build：开关翻转即整页重建（卡片在 build 外读快照即可）
    ref.watch(hideToBudgetProvider);
    ref.watch(hiddenEnvelopeIdsProvider);
    final now = DateTime.now();
    // 日期行随周期类型（DESIGN.md §3 v1.1.0）：大字 = 本期起始月，小字 = 本期区间
    final ledger = ref.watch(activeLedgerProvider);
    final periodType = ledger == null
        ? BudgetPeriodType.naturalMonth
        : periodTypeFromDb(ledger.periodType);
    final startDay = ledger?.periodStartDay;
    final storedStart = tryParseIsoDate(ledger?.lastPeriodStart);
    final periodStart =
        storedStart ??
        periodStartOf(type: periodType, startDay: startDay, now: now);
    final rangeLabel = periodRangeLabel(
      type: periodType,
      startDay: startDay,
      storedStart: storedStart,
      now: now,
    );

    // 分页：当前页的信封切片；信封变少时收拢页码
    final pageCount = (envelopes.length / kEnvelopesPerPage).ceil();
    final safePage = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
    if (safePage != _page) {
      _page = safePage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(_page);
        }
      });
    }
    final pageStart = safePage * kEnvelopesPerPage;
    final pageEnvelopes = envelopes
        .skip(pageStart)
        .take(kEnvelopesPerPage)
        .toList();

    // 同步命中注册表：全部在用信封都注册 key（防翻页时空断言崩溃），
    // 当前页 id 集交给控制器做「硬币不跨页」过滤（ADR-0014 §3）
    final ids = envelopes.map((e) => e.id).toSet();
    _controller.envKeys.removeWhere((id, _) => !ids.contains(id));
    for (final e in envelopes) {
      _controller.envKeys.putIfAbsent(e.id, GlobalKey.new);
    }
    _controller.pageEnvIds = pageEnvelopes.map((e) => e.id).toSet();

    // 拖拽覆盖层的位置（全局 → 页面局部）
    final drag = _controller.drag;
    final bodyBox = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    final dragLocal = (drag != null && bodyBox != null && bodyBox.attached)
        ? bodyBox.globalToLocal(drag.position)
        : null;

    // 边缘带渐显进度（原型公式：pr = (y − GLOW_Y0) / (DROP_Y − GLOW_Y0 + 40)）；
    // 会话本身只在真正拖动后存在（票 05），无需再判 moved
    var edgePr = 0.0;
    if (drag != null &&
        drag.kind == DragKind.env &&
        bodyBox != null &&
        bodyBox.attached) {
      final dropY = bodyBox.size.height - _dropInset;
      final glowY0 = dropY - _glowAboveDrop;
      edgePr = ((dragLocal!.dy - glowY0) / (dropY - glowY0 + 40)).clamp(
        0.0,
        1.0,
      );
    }

    // 骨架门：数据 >200ms 未就绪时显示灰块骨架，就绪后无缝切回真实内容
    return HomeSkeletonGate(
      loading: envelopesAsync.isLoading || settingsAsync.isLoading,
      child: Stack(
        key: _bodyKey,
        children: [
          // ── 内容层 ──
          // 顶部不套安全区：弧形头部直接顶到状态栏背后（黄色即状态栏背景），
          // 头部内部自读 MediaQuery 顶部 inset 做内容下移
          SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 弧形待规划头部区（点击=记收入、拖出=分配，手势在外层包装）
                _wrapBudget(
                  BudgetArcHeader(
                    toBudget: toBudget,
                    symbol: symbol,
                    hideAmount: ref.read(hideToBudgetProvider),
                  ),
                ),
                // 日期行：大字 + 周期区间 + 新增按钮
                _Header(
                  onNewEnvelope: () => _showWip(context),
                  onOpenPeriod: () => _openPeriodSettings(context),
                  monthLabel: '${periodStart.month}月',
                  rangeLabel: rangeLabel,
                ),
                // 信封区：固定网格分页（绝不滚动）
                Expanded(
                  child: envelopes.isEmpty
                      ? _EmptyState(onCreate: () => _showWip(context))
                      : Column(
                          children: [
                            Expanded(
                              child: PageView.builder(
                                controller: _pageController,
                                itemCount: pageCount,
                                // 拖拽进行中锁掉横滑（另一处手指扫到间隙也不会翻页）
                                physics: drag != null
                                    ? const NeverScrollableScrollPhysics()
                                    : const PageScrollPhysics(),
                                // 翻页回调 → 重绘 + 同步命中注册表
                                onPageChanged: (p) => setState(() => _page = p),
                                itemBuilder: (context, p) => _GridPage(
                                  envelopes: envelopes
                                      .skip(p * kEnvelopesPerPage)
                                      .take(kEnvelopesPerPage)
                                      .toList(),
                                  drag: drag,
                                  wrapEnvelope: _wrapEnvelope,
                                ),
                              ),
                            ),
                            // 分页器：仅 >10 个时出现（ADR-0014）；拖拽中不误触
                            if (pageCount > 1)
                              _PageDots(
                                count: pageCount,
                                current: safePage,
                                locked: drag != null,
                                onTap: (p) => _pageController.animateToPage(
                                  p,
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOut,
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),

          // ── 覆盖层：底部落点带（仅信封拖拽时渐显）──
          if (drag != null && drag.kind == DragKind.env && edgePr > 0)
            _EdgeBand(opacity: edgePr),

          // ── 覆盖层：硬币（拖拽跟手；铺满整层避免裁剪）──
          if (drag != null && dragLocal != null)
            Positioned.fill(
              child: _DragFollow(local: dragLocal),
            ),
        ],
      ),
    );
  }

  // 弧形头部：拖 = 分配，点 = 记收入（原型 §bindBudget；budgetKey 供引导遮罩定位）
  Widget _wrapBudget(Widget header) {
    return KeyedSubtree(
      key: _controller.budgetKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onBudgetTap,
        // 会话在拖动被识别（onPanStart）才开始：按下不动无任何拖拽视觉（票 05）
        onPanStart: (d) =>
            _controller.begin(DragKind.budget, null, d.globalPosition),
        onPanUpdate: (d) => _controller.update(d.globalPosition),
        onPanCancel: _controller.cancel,
        onPanEnd: (_) => _handleDrop(_controller.end(dropY: _dropYGlobal())),
        child: header,
      ),
    );
  }

  // 信封卡：点=详情 · 双击=记支出 · 长按=面板 · 拖=四向 + 手势状态透传 + 金额隐私（票 03）
  // （onDoubleTap 与 onTap 共存时单击判定延迟约 300ms——双击判别的固有代价）
  Widget _wrapEnvelope(Envelope e, DragSession? drag) {
    return KeyedSubtree(
      key: _controller.envKeys[e.id]!,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onEnvTap(e.id),
        onDoubleTap: () => _onEnvDoubleTap(e.id),
        onLongPressStart: (_) => _openActionPanel(e.id),
        // 会话在拖动被识别（onPanStart）才开始：按下不动无任何拖拽视觉（票 05）
        onPanStart: (d) =>
            _controller.begin(DragKind.env, e.id, d.globalPosition),
        onPanUpdate: (d) => _controller.update(d.globalPosition),
        onPanCancel: _controller.cancel,
        onPanEnd: (_) => _handleDrop(_controller.end(dropY: _dropYGlobal())),
        child: EnvelopeCard(
          envelope: e,
          // 方法在 build 之外：读快照即可——build 已 watch 这两个 provider，
          // 符号变化/隐私开关翻转都会触发整页重建（票 03）
          symbol: ref.read(currencySymbolProvider),
          hideAmount: ref.read(hiddenEnvelopeIdsProvider).contains(e.id),
          dimmed: drag?.kind == DragKind.env && drag?.envId == e.id,
          hovered: drag?.hoverEnvId == e.id,
        ),
      ),
    );
  }

  void _showWip(BuildContext context) {
    showCreateEnvelopeSheet(context, ref);
  }
}

// ── 网格页 ──────────────────────────────────────

/// 一页固定网格：2 列 × 5 行，行高按剩余空间均分（弹性压缩），不足 10 个顶部对齐
class _GridPage extends StatelessWidget {
  const _GridPage({
    required this.envelopes,
    required this.drag,
    required this.wrapEnvelope,
  });

  // 本页 ≤10 个信封（切片由调用方给好）
  final List<Envelope> envelopes;

  // 进行中的拖拽会话（透传给卡片做变暗/悬停视觉）
  final DragSession? drag;

  // 卡片手势包装（home_page 注入，保持手势状态机单点）
  final Widget Function(Envelope e, DragSession? drag) wrapEnvelope;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.spaceLg, 4, T.spaceLg, 4),
      child: Column(
        children: [
          for (var r = 0; r < 5; r++) ...[
            if (r > 0) const SizedBox(height: T.spaceMd),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _cell(r * 2)),
                  const SizedBox(width: T.spaceMd),
                  Expanded(child: _cell(r * 2 + 1)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 第 i 槽：有信封则带手势包装，空槽留白（顶部对齐靠空槽在尾部）
  Widget _cell(int i) {
    if (i >= envelopes.length) return const SizedBox();
    return wrapEnvelope(envelopes[i], drag);
  }
}

// 圆点分页器：居中一排，当前页拉长成胶囊；点击翻页
class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.current,
    required this.locked,
    required this.onTap,
  });

  final int count;
  final int current;

  // 拖拽进行中锁定点击（硬币拖拽时手可能扫过分页器）
  final bool locked;
  final void Function(int page) onTap;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: locked,
      child: SizedBox(
        height: 22,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < count; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: i == current ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == current ? T.primary : const Color(0xFFE3DCD0),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── 覆盖层组件 ──────────────────────────────

// 底部落点带：104 渐变 + 56 实心条，随拖拽渐显（原型 .edge）
class _EdgeBand extends StatelessWidget {
  const _EdgeBand({required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: SizedBox(
            height: 160,
            child: Stack(
              children: [
                // 渐变区
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 56,
                  height: 104,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, 0.5, 1],
                        colors: [
                          Color(0x00FFC72B),
                          Color(0x29FFC72B),
                          Color(0x73FFC72B),
                        ],
                      ),
                    ),
                  ),
                ),
                // 实心落点条
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 56,
                  child: Container(
                    color: const Color(0xEBFFC72B),
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: T.textPrimary,
                        ),
                        SizedBox(width: 6),
                        Text(
                          dragEdgeBandLabel,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: T.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 拖拽跟手层：40dp 硬币贴图（恒在触点上方 14dp，原型 setCoin）。
// 光斑已按 v1.2.0 票 05 移除；票 06 起硬币改为用户自备贴图渲染
// （assets/coin.png，512×512 透明底，40dp 盒内等比缩放），
// 不再代码绘制黄圆与符号，贴图自带剪影故无投影。
// 会话只在真正拖动后存在，本层只在拖拽中出现。
class _DragFollow extends StatelessWidget {
  const _DragFollow({required this.local});

  // 手指的页面局部坐标
  final Offset local;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          // 硬币贴图
          Positioned(
            left: local.dx - 20,
            top: local.dy - 54,
            child: Image.asset(
              'assets/coin.png',
              width: 40,
              height: 40,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 内容组件 ──────────────────────────────────

/// 日期行（DESIGN.md §3 v1.1.0）：左「本期起始月」大字 + 本期区间小字
/// （随周期类型），整行可点进「预算周期与结转」设置页；右 36dp 新增按钮
class _Header extends StatelessWidget {
  const _Header({
    required this.onNewEnvelope,
    required this.onOpenPeriod,
    required this.monthLabel,
    required this.rangeLabel,
  });

  final VoidCallback onNewEnvelope;

  // 日期行整行点击 → 进周期设置页
  final VoidCallback onOpenPeriod;

  // 本期起始月，如「9月」
  final String monthLabel;

  // 本期区间小字，随周期类型（自由 = 「起点 – 至今」）
  final String rangeLabel;

  @override
  Widget build(BuildContext context) {
    // 不锁固定高度：行高随文字自适应（系统字体缩放调大时不会溢出，
    // 模拟器 fontScale≠1 的场景此前在此处溢出 2px）
    return Padding(
      padding: const EdgeInsets.fromLTRB(T.spaceLg, 10, T.spaceLg, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 整行可点：日期区包 InkWell（含上下 3dp 热区扩展）
          Expanded(
            child: InkWell(
              onTap: onOpenPeriod,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      monthLabel,
                      style: const TextStyle(
                        fontSize: T.typeXl,
                        height: 26 / 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      rangeLabel,
                      style: const TextStyle(
                        fontSize: T.typeXs,
                        height: 15 / 11,
                        color: T.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            height: 36,
            child: Material(
              color: T.primarySoft,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: onNewEnvelope,
                child: const Icon(Icons.add, size: 16, color: T.primaryDeep),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 空状态（DESIGN.md §14）：不隐藏待规划头部，把下一步动作勾出来
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: const BoxDecoration(
              color: T.primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mail_outline_rounded,
              size: 32,
              color: Color(0xFFC9A63C),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            emptyHomeTitle,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            emptyHomeBody,
            style: TextStyle(fontSize: T.typeXs, color: T.textTertiary),
          ),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: T.primary,
              foregroundColor: T.textPrimary,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(T.radiusKey),
              ),
            ),
            onPressed: onCreate,
            child: const Text(
              emptyHomeCta,
              style: TextStyle(
                fontSize: T.typeBase,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
