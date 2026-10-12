// drift 数据库 — 单文件 SQLite，全部表挂 ledgerId 维度（ADR-0011）。
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../domain/models.dart' show kDefaultCurrency;
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [Ledgers, Envelopes, Transactions, AppSettings, DescriptionHistory],
)
class EnvelopeDatabase extends _$EnvelopeDatabase {
  EnvelopeDatabase([QueryExecutor? executor])
    : super(executor ?? openConnection());

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      // v2：信封停用标记（ADR-0012）
      if (from < 2) {
        await m.addColumn(envelopes, envelopes.archivedAt);
      }
      // v3：预算周期泛化（ADR-0013）——月 key（last_active_month，'2026-09'）
      // 泛化为周期起点（last_period_start，ISO 日期 '2026-09-01' = 当月 1 号），
      // 默认自然月；新增周期类型与自定义起始日字段。
      // 做法：加三列 + 一条 UPDATE 回填（不重建表）；旧列留在 SQLite 中不再读写，
      // 新装用户按新 schema 建表天然没有旧列。
      if (from < 3) {
        await m.addColumn(ledgers, ledgers.lastPeriodStart);
        await m.addColumn(ledgers, ledgers.periodType);
        await m.addColumn(ledgers, ledgers.periodStartDay);
        // 关键步骤：旧月 key 拼 '-01' 得到自然月起点；NULL 保持 NULL
        // （起点未初始化，首次打开由 touchLedgerPeriod 补写）
        await customStatement(
          "UPDATE ledgers SET last_period_start = last_active_month || '-01' "
          'WHERE last_active_month IS NOT NULL',
        );
      }
      // v4：货币符号按账本设置（v1.2.0 票 02 / ADR-0017）——
      // 账本设置表加 currency 列，存量行由列默认值（¥）回填，无需数据改写。
      if (from < 4) {
        await m.addColumn(appSettings, appSettings.currency);
      }
      // v5：描述历史（v1.3.0 票 02 / ADR-0020）——新增表，
      // 无存量数据可回填（历史只记手输描述，从零开始积累）。
      if (from < 5) {
        await m.createTable(descriptionHistory);
      }
    },
  );

  /// 平台默认的数据库文件路径（安卓优先，iOS 同理）
  static QueryExecutor openConnection() {
    return driftDatabase(name: 'enve_keeper');
  }
}
