// Riverpod 状态层 — 单一事实源是 drift 数据库；
// provider 只做「查询流 + 激活账本」这两件事，写操作走 AppRepository。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/app_repository.dart';
import '../data/db/database.dart' as db;
import '../domain/models.dart';
import '../domain/stats_range.dart';

// 全局数据库实例
final dbProvider = Provider<db.EnvelopeDatabase>((ref) {
  final database = db.EnvelopeDatabase();
  ref.onDispose(database.close);
  return database;
});

// SharedPreferences（main 里覆写注入）
final prefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('main 中覆写'),
);

// 应用仓库
final repoProvider = Provider<AppRepository>(
  (ref) => AppRepository(ref.watch(dbProvider)),
);

// 激活账本 id（SharedPreferences 持久化）
class ActiveLedgerId extends Notifier<String?> {
  @override
  String? build() => ref.watch(prefsProvider).getString('activeLedgerId');

  // 切换账本
  Future<void> set(String id) async {
    state = id;
    await ref.watch(prefsProvider).setString('activeLedgerId', id);
  }
}

final activeLedgerIdProvider = NotifierProvider<ActiveLedgerId, String?>(
  ActiveLedgerId.new,
);

// 全部账本流
final ledgersProvider = StreamProvider<List<db.Ledger>>(
  (ref) => ref.watch(repoProvider).watchLedgers(),
);

// 激活账本（id 无效或为空时回落到第一个账本）
final activeLedgerProvider = Provider<db.Ledger?>((ref) {
  final ledgers = ref.watch(ledgersProvider).value;
  if (ledgers == null || ledgers.isEmpty) return null;
  final id = ref.watch(activeLedgerIdProvider);
  return ledgers.where((l) => l.id == id).firstOrNull ?? ledgers.first;
});

// 激活账本**在用**的信封流（停用不出现；首页/键盘/管理页用）
final envelopesProvider = StreamProvider<List<Envelope>>((ref) {
  final ledger = ref.watch(activeLedgerProvider);
  if (ledger == null) return Stream.value(const []);
  return ref.watch(repoProvider).watchEnvelopes(ledger.id);
});

// 激活账本**全部**信封流（含停用；流水/详情解析信封名用，ADR-0012）
final allEnvelopesProvider = StreamProvider<List<Envelope>>((ref) {
  final ledger = ref.watch(activeLedgerProvider);
  if (ledger == null) return Stream.value(const []);
  return ref.watch(repoProvider).watchAllEnvelopes(ledger.id);
});

// 激活账本的交易流（新→旧）
final txnsProvider = StreamProvider<List<Txn>>((ref) {
  final ledger = ref.watch(activeLedgerProvider);
  if (ledger == null) return Stream.value(const <Txn>[]);
  return ref.watch(repoProvider).watchTransactions(ledger.id);
});

// 激活账本的设置流
final settingsProvider = StreamProvider<db.AppSetting>((ref) {
  final ledger = ref.watch(activeLedgerProvider);
  if (ledger == null) {
    return Stream.value(
      db.AppSetting(
        ledgerId: '-',
        toBudget: 0,
        carryoverDefault: true,
        currency: kDefaultCurrency,
      ),
    );
  }
  return ref.watch(repoProvider).watchSettings(ledger.id);
});

// 当前账本的货币符号（v1.2.0 票 02 / ADR-0017）：设置流的派生值，
// 全 app 金额显示统一从这里取符号；读取中/无账本回落默认 ¥
final currencySymbolProvider = Provider<String>((ref) {
  return ref.watch(settingsProvider).value?.currency ?? kDefaultCurrency;
});

// 引擎输入：当前账本状态快照（信封 + 待规划）
final ledgerStateProvider = Provider<LedgerState>((ref) {
  final envelopes = ref.watch(envelopesProvider).value ?? const <Envelope>[];
  final toBudget = ref.watch(settingsProvider).value?.toBudget ?? 0;
  return LedgerState(
    toBudget: toBudget,
    envelopes: {for (final e in envelopes) e.id: e},
  );
});

// ── 手势引导（DESIGN.md §17）──────────────────────

// 「已看过手势引导」标记：shared_preferences 持久化（key: gestureCoachShown）
class GestureCoachSeen extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(prefsProvider).getBool('gestureCoachShown') ?? false;

  // 标记已看过（引导走完或跳过时调用）
  Future<void> markSeen() async {
    state = true;
    await ref.watch(prefsProvider).setBool('gestureCoachShown', true);
  }
}

final gestureCoachSeenProvider = NotifierProvider<GestureCoachSeen, bool>(
  GestureCoachSeen.new,
);

// ── 流水页显示偏好（v1.2.0 票 04）─────────────────

// 「显示转移项」开关：shared_preferences 持久化（key: records.showTransfers）。
// 默认关闭——流水页聚焦收入与支出，转移（含结转退回）按需显示；
// 只影响流水页列表，信封详情页的流水不受影响。
class ShowTransfers extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(prefsProvider).getBool('records.showTransfers') ?? false;

  // 切换显隐并持久化
  Future<void> set(bool show) async {
    state = show;
    await ref.watch(prefsProvider).setBool('records.showTransfers', show);
  }
}

final showTransfersProvider = NotifierProvider<ShowTransfers, bool>(
  ShowTransfers.new,
);

// ── 首页金额隐私（v1.2.0 票 03）─────────────────
// 纯展示偏好边界：只藏首页的数字、不藏进度，不触碰数据层——不进 drift schema、
// 不进 .jx 备份（换设备/重装即重置为显示），与账本数据完全解耦。
// 生效范围仅首页：分配页/流水页/详情页/统计页一律不藏。

// 「隐藏待规划金额」开关（shared_preferences 持久化，key: home.hideToBudget）
class HideToBudget extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(prefsProvider).getBool('home.hideToBudget') ?? false;

  // 切换隐藏并持久化
  Future<void> set(bool hide) async {
    state = hide;
    await ref.watch(prefsProvider).setBool('home.hideToBudget', hide);
  }
}

final hideToBudgetProvider = NotifierProvider<HideToBudget, bool>(
  HideToBudget.new,
);

// 隐藏金额的信封 id 集（shared_preferences 持久化，key: home.hiddenEnvelopeIds）
class HiddenEnvelopeIds extends Notifier<Set<String>> {
  @override
  Set<String> build() =>
      (ref.watch(prefsProvider).getStringList('home.hiddenEnvelopeIds') ??
              const <String>[])
          .toSet();

  // 设置单个信封的隐藏状态并持久化
  Future<void> setHidden(String id, bool hide) async {
    final next = {...state};
    if (hide) {
      next.add(id);
    } else {
      next.remove(id);
    }
    state = next;
    await ref
        .watch(prefsProvider)
        .setStringList('home.hiddenEnvelopeIds', next.toList());
  }
}

final hiddenEnvelopeIdsProvider =
    NotifierProvider<HiddenEnvelopeIds, Set<String>>(HiddenEnvelopeIds.new);

// ── 统计页区间胶囊偏好（v1.2.0 票 07）───────────────
// 纯展示偏好：勾选哪些区间段进胶囊（周/月恒显不可勾掉），shared_preferences
// 持久化（key: stats.segments），不进 drift schema、不进 .jx 备份。

// 「统计胶囊段」勾选集：读出后按固定顺序收敛（票 07：段顺序固定不支持排序）
class StatsSegments extends Notifier<List<StatsRange>> {
  static const _key = 'stats.segments';

  @override
  List<StatsRange> build() {
    final stored =
        ref.watch(prefsProvider).getStringList(_key) ?? const <String>[];
    // 容错解析：未知名字忽略；周/月恒显兜底（旧数据/手改数据都安全）
    final checked = stored.map(_parse).whereType<StatsRange>().toSet();
    return kStatsSegmentOrder
        .where(
          (r) => !kStatsOptionalSegments.contains(r) || checked.contains(r),
        )
        .toList();
  }

  // 切换一个可选段的勾选状态并持久化（只存可选段的选中项）
  Future<void> toggle(StatsRange r) async {
    if (!kStatsOptionalSegments.contains(r)) return;
    final next = [...state];
    if (next.contains(r)) {
      next.remove(r);
    } else {
      next.add(r);
    }
    state = next;
    await ref
        .watch(prefsProvider)
        .setStringList(
          _key,
          next.where(kStatsOptionalSegments.contains).map(_name).toList(),
        );
  }

  // 枚举名 ↔ 字符串（存储用，避免 dart:mirrors）
  static String _name(StatsRange r) => r.name;
  static StatsRange? _parse(String s) {
    for (final r in kStatsOptionalSegments) {
      if (r.name == s) return r;
    }
    return null;
  }
}

final statsSegmentsProvider = NotifierProvider<StatsSegments, List<StatsRange>>(
  StatsSegments.new,
);

// 「重看手势引导」请求计数：我的页自增一次，AppShell 监听后切回首页并重放遮罩
class CoachReplayRequest extends Notifier<int> {
  @override
  int build() => 0;

  // 请求重放一次引导
  void request() => state++;
}

final coachReplayRequestProvider = NotifierProvider<CoachReplayRequest, int>(
  CoachReplayRequest.new,
);

// ── 应用包信息（票 07）──────────────────────────────

// 包版本信息：关于页与「我的」页版本行共用同一来源，避免双处硬编码
final packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);
