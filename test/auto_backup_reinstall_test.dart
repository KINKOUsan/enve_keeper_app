// 重装找回自动备份（v1.2.x 票 03 · DESIGN.md §19）：
// 检测条件（首启 + 初始空账未引导）、确认后整体恢复直进主界面、
// 拒绝/无文件/内容损坏都静默走引导、恢复失败保护当前数据、非首启不重复弹。
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:enve_keeper_app/app.dart';
import 'package:enve_keeper_app/data/app_repository.dart';
import 'package:enve_keeper_app/data/auto_backup_store.dart';
import 'package:enve_keeper_app/data/db/database.dart' as db;
import 'package:enve_keeper_app/domain/models.dart';
import 'package:enve_keeper_app/state/auto_backup.dart';
import 'package:enve_keeper_app/state/providers.dart';
import 'package:enve_keeper_app/ui/copy.dart';

// 假存储：read 直接吐预置内容（null = 找不到/读不了），write 只记录
class _FakeStore extends AutoBackupStore {
  _FakeStore([this.readResult]);

  final String? readResult;

  @override
  Future<String?> read() async => readResult;

  @override
  Future<AutoBackupWriteResult> write(String json) async =>
      const AutoBackupWriteResult(publicTarget: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 造一份「上一个安装」的全量备份：已完成引导 + 一个信封
  Future<String> seedJson() async {
    final seedDb = db.EnvelopeDatabase(NativeDatabase.memory());
    addTearDown(seedDb.close);
    final seedRepo = AppRepository(seedDb);
    final ledger = await seedRepo.ensureBootstrap();
    await seedRepo.markOnboarded(ledger.id);
    await seedRepo.createOrRestoreEnvelope(
      ledgerId: ledger.id,
      name: '餐饮',
      icon: 'food',
      color: 'clay',
    );
    final json = await seedRepo.exportBackupJson();
    return json;
  }

  // 泵起完整 App：内存库 + mock prefs + 假存储（预置备份内容）
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    String? backupJson,
    Map<String, Object> prefsInit = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefsInit);
    final prefs = await SharedPreferences.getInstance();
    final database = db.EnvelopeDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final container = ProviderContainer(
      overrides: [
        dbProvider.overrideWithValue(database),
        prefsProvider.overrideWithValue(prefs),
        autoBackupStoreProvider.overrideWithValue(_FakeStore(backupJson)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const JinDaXiSuanApp(),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('有自动备份：弹摘要确认框，确认后整体恢复直进主界面', (tester) async {
    // 预置「已看过手势引导」：恢复后主界面的引导遮罩带循环动画，
    // 会让 pumpAndSettle 永不收敛（与被测流程无关）
    final container = await pumpApp(
      tester,
      backupJson: await seedJson(),
      prefsInit: {'gestureCoachShown': true},
    );

    expect(find.text(autoBackupFoundTitle), findsOneWidget);
    // 摘要：时间 · 账本数 · 信封数 · 流水数
    expect(find.textContaining('个账本'), findsOneWidget);
    expect(find.textContaining('个信封'), findsOneWidget);
    expect(find.textContaining('笔流水'), findsOneWidget);

    await tester.tap(find.text('恢复备份'));
    await tester.pumpAndSettle();

    // 直进主界面：恢复出的信封在首页，不再进引导
    expect(find.text('先点清手头有多少钱'), findsNothing);
    expect(find.text('餐饮'), findsOneWidget);
    // 数据真的回来了：账本带着备份里的已完成引导标记
    //（widget 测试里裸订阅 drift watch 流不吐首帧，从 provider 读）
    final ledgers = container.read(ledgersProvider).value!;
    expect(ledgers.single.onboarded, isTrue);

    await tester.pump(const Duration(seconds: 4)); // 冲掉恢复触发的备份防抖计时
  });

  testWidgets('拒绝恢复：正常走三屏引导，数据保持空白', (tester) async {
    final container = await pumpApp(tester, backupJson: await seedJson());

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('先点清手头有多少钱'), findsOneWidget);
    final repo = container.read(repoProvider);
    final ledgers = container.read(ledgersProvider).value!;
    expect(await repo.isLedgerEmpty(ledgers.first.id), isTrue);
    await tester.pump(const Duration(seconds: 4)); // 冲掉防抖计时，避免测试收尾时 Timer 未决
  });

  testWidgets('无备份文件：直接正常引导，无弹窗打扰', (tester) async {
    await pumpApp(tester);

    expect(find.text(autoBackupFoundTitle), findsNothing);
    expect(find.text('先点清手头有多少钱'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4)); // 冲掉防抖计时，避免测试收尾时 Timer 未决
  });

  testWidgets('备份内容损坏（读得出文件读不出摘要）：与无文件同路径静默走引导', (tester) async {
    await pumpApp(tester, backupJson: '这不是 JSON');

    expect(find.text(autoBackupFoundTitle), findsNothing);
    expect(find.text('先点清手头有多少钱'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4)); // 冲掉防抖计时，避免测试收尾时 Timer 未决
  });

  testWidgets('恢复失败（版本超前拒收）：弹失败框，当前数据未动，继续走引导', (tester) async {
    final future = jsonEncode({
      'app': '金打细算',
      'schemaVersion': 999,
      'exportedAt': DateTime.now().toIso8601String(),
      'counts': {'ledgers': 1, 'envelopes': 2, 'transactions': 3},
    });
    final container = await pumpApp(tester, backupJson: future);

    await tester.tap(find.text('恢复备份'));
    await tester.pumpAndSettle();
    expect(find.text('恢复失败'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('先点清手头有多少钱'), findsOneWidget);
    final repo = container.read(repoProvider);
    final ledgers = container.read(ledgersProvider).value!;
    expect(await repo.isLedgerEmpty(ledgers.first.id), isTrue);
    await tester.pump(const Duration(seconds: 4)); // 冲掉防抖计时，避免测试收尾时 Timer 未决
  });

  testWidgets('非首次启动（偏好里已有激活账本）：不弹找回，正常引导', (tester) async {
    await pumpApp(
      tester,
      backupJson: await seedJson(),
      prefsInit: {'activeLedgerId': '上一次安装留下的 id'},
    );

    expect(find.text(autoBackupFoundTitle), findsNothing);
    expect(find.text('先点清手头有多少钱'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4)); // 冲掉防抖计时，避免测试收尾时 Timer 未决
  });

  test('isLedgerEmpty：新账本为空；记流水或建信封后不为空，账本之间互不干扰', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final database = db.EnvelopeDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final container = ProviderContainer(
      overrides: [
        dbProvider.overrideWithValue(database),
        prefsProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    final repo = container.read(repoProvider);

    final ledger = await repo.ensureBootstrap();
    expect(await repo.isLedgerEmpty(ledger.id), isTrue);

    // 另一个账本只记一笔收入（不建信封）：不算空
    final other = await repo.createLedger();
    await repo.addTransaction(
      ledgerId: other.id,
      txn: Txn(
        id: repo.newTxnId(),
        type: TxType.income,
        amount: 100,
        description: '手头的钱',
        at: DateTime.now(),
        toId: kToBudget,
      ),
      fallback: '记一笔收入',
    );
    expect(await repo.isLedgerEmpty(other.id), isFalse);
    expect(await repo.isLedgerEmpty(ledger.id), isTrue);

    // 建信封后原账本也不算空
    await repo.createOrRestoreEnvelope(
      ledgerId: ledger.id,
      name: '餐饮',
      icon: 'food',
      color: 'clay',
    );
    expect(await repo.isLedgerEmpty(ledger.id), isFalse);
  });

  test('AutoBackupStore.read：沙盒降级档写入后能读出原内容；无文件返回 null', () async {
    final docs = await Directory.systemTemp.createTemp('auto_backup_test');
    addTearDown(() => docs.delete(recursive: true));
    // 注入临时文档目录（测试宿主上 path_provider 走平台 FFI，不可 mock）
    final store = AutoBackupStore(docsDirectory: () async => docs);

    expect(await store.read(), isNull);

    await store.write('一份自动备份');
    expect(await store.read(), '一份自动备份');
  });
}
