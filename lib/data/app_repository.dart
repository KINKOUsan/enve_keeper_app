// 应用仓库层 — 所有落库操作收口在这里。
// 引擎（applyTx）在这里被调用：读当前状态 → 引擎算新状态 → 事务写回。
// UI 不直接碰 drift，也不直接碰引擎。
import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/models.dart';
import '../domain/tx_engine.dart';
import '../domain/period_logic.dart';
import 'db/database.dart' as db;

/// 恢复失败（版本不兼容 / 内容损坏），message 为 UI 提示文案
class BackupRestoreException implements Exception {
  BackupRestoreException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 备份摘要（列表行显示用）：来源时间 + 笔数统计
class BackupSummary {
  const BackupSummary({
    required this.exportedAt,
    required this.ledgerCount,
    required this.envelopeCount,
    required this.txnCount,
  });

  final DateTime exportedAt;
  final int ledgerCount;
  final int envelopeCount;
  final int txnCount;
}

/// 领域模型 ↔ drift 行的映射与全部业务写操作。
/// drift 行类与本文件顶部的领域模型同名冲突，因此 drift 统一加 `db.` 前缀引用。
class AppRepository {
  AppRepository(this._db);
  final db.EnvelopeDatabase _db;

  // ── 账本 ───────────────────────────────────

  /// 监听全部账本（创建顺序）
  Stream<List<db.Ledger>> watchLedgers() {
    return (_db.select(
      _db.ledgers,
    )..orderBy([(l) => OrderingTerm.asc(l.sortOrder)])).watch();
  }

  /// 首次启动兜底：没有任何账本时建一个默认账本（未完成引导）
  Future<db.Ledger> ensureBootstrap() async {
    final existing = await _db.select(_db.ledgers).get();
    if (existing.isNotEmpty) return existing.first;
    final id = _newId('lg');
    await _db
        .into(_db.ledgers)
        .insert(
          db.LedgersCompanion.insert(
            id: id,
            name: '账本 1',
            createdAt: DateTime.now(),
            sortOrder: const Value(0),
            // 周期起点初始化为本自然月 1 号（默认周期类型 = 自然月，ADR-0013）
            lastPeriodStart: Value(isoDateOf(monthStart(DateTime.now()))),
          ),
        );
    await _db
        .into(_db.appSettings)
        .insert(db.AppSettingsCompanion.insert(ledgerId: id, toBudget: 0));
    return (await getLedger(id))!;
  }

  /// 新建账本：从一切为 0 元开始（ADR-0011），名字默认「账本 N」
  Future<db.Ledger> createLedger({String? name}) async {
    final all = await _db.select(_db.ledgers).get();
    final id = _newId('lg');
    final finalName = name ?? '账本 ${all.length + 1}';
    await _db.transaction(() async {
      await _db
          .into(_db.ledgers)
          .insert(
            db.LedgersCompanion.insert(
              id: id,
              name: finalName,
              createdAt: DateTime.now(),
              sortOrder: Value(all.length),
              // 周期起点初始化为本自然月 1 号（默认周期类型 = 自然月，ADR-0013）
              lastPeriodStart: Value(isoDateOf(monthStart(DateTime.now()))),
            ),
          );
      await _db
          .into(_db.appSettings)
          .insert(db.AppSettingsCompanion.insert(ledgerId: id, toBudget: 0));
    });
    return (await getLedger(id))!;
  }

  /// 重命名账本
  Future<void> renameLedger(String id, String name) async {
    await (_db.update(_db.ledgers)..where((l) => l.id.equals(id))).write(
      db.LedgersCompanion(name: Value(name)),
    );
  }

  /// 删除账本及其全部数据。调用方必须先保证「至少保留一个账本」（ADR-0011）。
  Future<void> deleteLedger(String id) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.transactions,
      )..where((t) => t.ledgerId.equals(id))).go();
      await (_db.delete(
        _db.envelopes,
      )..where((e) => e.ledgerId.equals(id))).go();
      await (_db.delete(
        _db.appSettings,
      )..where((s) => s.ledgerId.equals(id))).go();
      await (_db.delete(_db.ledgers)..where((l) => l.id.equals(id))).go();
    });
  }

  /// 标记账本完成引导
  Future<void> markOnboarded(String id) async {
    await (_db.update(_db.ledgers)..where((l) => l.id.equals(id))).write(
      db.LedgersCompanion(onboarded: const Value(true)),
    );
  }

  Future<db.Ledger?> getLedger(String id) async {
    return (_db.select(
      _db.ledgers,
    )..where((l) => l.id.equals(id))).getSingleOrNull();
  }

  /// 账本是否还是初始空账（无信封且无流水）——重装找回自动备份的检测条件
  /// （v1.2.x 票 03）。引导第 1 屏录了收入但没走完的账本不算空，不弹找回框。
  Future<bool> isLedgerEmpty(String ledgerId) async {
    final envelopes = _db.envelopes.id.count();
    final envRow = await (_db.selectOnly(
      _db.envelopes,
    )..addColumns([envelopes])
          ..where(_db.envelopes.ledgerId.equals(ledgerId)))
        .getSingle();
    if ((envRow.read(envelopes) ?? 0) > 0) return false;
    final txns = _db.transactions.id.count();
    final txnRow = await (_db.selectOnly(
      _db.transactions,
    )..addColumns([txns])
          ..where(_db.transactions.ledgerId.equals(ledgerId)))
        .getSingle();
    return (txnRow.read(txns) ?? 0) == 0;
  }

  // ── 信封 ───────────────────────────────────

  /// 监听某账本**在用**的信封（按 sortOrder 稳定排序；停用的不出现，ADR-0012）
  Stream<List<Envelope>> watchEnvelopes(String ledgerId) {
    final q = _db.select(_db.envelopes)
      ..where((e) => e.ledgerId.equals(ledgerId) & e.archivedAt.isNull())
      ..orderBy([(e) => OrderingTerm.asc(e.sortOrder)]);
    return q.watch().map((rows) => rows.map(_envFromRow).toList());
  }

  /// 监听某账本**全部**信封（含停用）——流水/详情解析信封名用
  Stream<List<Envelope>> watchAllEnvelopes(String ledgerId) {
    final q = _db.select(_db.envelopes)
      ..where((e) => e.ledgerId.equals(ledgerId))
      ..orderBy([(e) => OrderingTerm.asc(e.sortOrder)]);
    return q.watch().map((rows) => rows.map(_envFromRow).toList());
  }

  // 新建信封的结果：普通创建 / 同名恢复 / 在用同名冲突
  ({bool conflict, bool restored, Envelope envelope}) _createResult(
    bool conflict,
    bool restored,
    Envelope envelope,
  ) => (conflict: conflict, restored: restored, envelope: envelope);

  /// 新建信封（ADR-0012：名字即身份）：
  /// - 已有**在用**同名 → 不创建，返回 conflict = true（UI 提示阻止）
  /// - 有**停用**同名 → 恢复最近停用的一行，其他同名停用行的流水迁移过来后删除（合并旧档）
  /// - 否则正常创建（结转开关从账本全局默认值初始化）
  Future<({bool conflict, bool restored, Envelope envelope})>
  createOrRestoreEnvelope({
    required String ledgerId,
    required String name,
    required String icon,
    required String color,
    bool? carryover,
  }) async {
    // 在用同名：名字唯一性阻止
    final activeDup =
        await (_db.select(_db.envelopes)..where(
              (e) =>
                  e.ledgerId.equals(ledgerId) &
                  e.archivedAt.isNull() &
                  e.name.equals(name),
            ))
            .get();
    if (activeDup.isNotEmpty) {
      return _createResult(true, false, _envFromRow(activeDup.first));
    }

    // 停用同名：恢复 + 合并
    final archived =
        await (_db.select(_db.envelopes)..where(
              (e) =>
                  e.ledgerId.equals(ledgerId) &
                  e.archivedAt.isNotNull() &
                  e.name.equals(name),
            ))
            .get();
    if (archived.isNotEmpty) {
      // 关键步骤：按停用时间取最近一行作为恢复载体
      final sorted = [...archived]
        ..sort((a, b) => b.archivedAt!.compareTo(a.archivedAt!));
      final target = sorted.first;
      final others = sorted.skip(1).toList();

      await _db.transaction(() async {
        // 复活：清停用标记 + 沿用用户新选的图标/颜色；planned/used 已在停用时清零
        await (_db.update(
          _db.envelopes,
        )..where((e) => e.id.equals(target.id))).write(
          db.EnvelopesCompanion(
            archivedAt: const Value(null),
            icon: Value(icon),
            color: Value(color),
            carryover: Value(carryover ?? target.carryover),
          ),
        );
        // 关键步骤：把其他同名停用行的流水全部迁移到恢复行，然后删除这些行
        for (final other in others) {
          await _migrateEnvelopeRefs(other.id, target.id);
          await (_db.delete(
            _db.envelopes,
          )..where((e) => e.id.equals(other.id))).go();
        }
      });
      return _createResult(
        false,
        true,
        _envFromRow(await getEnvelopeRow(target.id)),
      );
    }

    // 正常创建
    final settings = await _settingsRow(ledgerId);
    final count = await _countActiveEnvelopes(ledgerId);
    final id = _newId('env');
    await _db
        .into(_db.envelopes)
        .insert(
          db.EnvelopesCompanion.insert(
            id: id,
            ledgerId: ledgerId,
            name: name,
            icon: icon,
            color: color,
            planned: 0,
            used: 0,
            carryover: carryover ?? settings.carryoverDefault,
            sortOrder: Value(count),
          ),
        );
    return _createResult(false, false, _envFromRow(await getEnvelopeRow(id)));
  }

  /// 停用信封（ADR-0012）：未花完部分退回待规划，planned/used 清零，打停用标记。
  /// 流水保留不动（停用≠撤销）。
  Future<void> archiveEnvelope(String id, {required String ledgerId}) async {
    await _db.transaction(() async {
      final row = await (_db.select(
        _db.envelopes,
      )..where((e) => e.id.equals(id))).getSingleOrNull();
      if (row == null) return;
      // 关键步骤：未花完的分配退回待规划
      final avail = round2(row.planned - row.used);
      if (avail > 0) {
        final state = await _loadState(ledgerId);
        await _writeBack(
          ledgerId,
          LedgerState(
            toBudget: round2(state.toBudget + avail),
            envelopes: state.envelopes,
          ),
        );
      }
      // 账面清零 + 打停用标记
      await (_db.update(_db.envelopes)..where((e) => e.id.equals(id))).write(
        db.EnvelopesCompanion(
          planned: Value(0),
          used: Value(0),
          archivedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  /// 按 id 读单行（内部用）
  Future<db.Envelope> getEnvelopeRow(String id) =>
      (_db.select(_db.envelopes)..where((e) => e.id.equals(id))).getSingle();

  Future<int> _countActiveEnvelopes(String ledgerId) async {
    final c = _db.envelopes.id.count();
    final q = _db.selectOnly(_db.envelopes)
      ..addColumns([c])
      ..where(
        _db.envelopes.archivedAt.isNull() &
            _db.envelopes.ledgerId.equals(ledgerId),
      );
    final row = await q.getSingle();
    return row.read(c) ?? 0;
  }

  /// 更新信封的可编辑字段（名称/图标/颜色/结转/排序/目标额）
  Future<void> updateEnvelope(
    String id, {
    String? name,
    String? icon,
    String? color,
    bool? carryover,
    int? sortOrder,
  }) async {
    await (_db.update(_db.envelopes)..where((e) => e.id.equals(id))).write(
      db.EnvelopesCompanion(
        name: name == null ? const Value.absent() : Value(name),
        icon: icon == null ? const Value.absent() : Value(icon),
        color: color == null ? const Value.absent() : Value(color),
        carryover: carryover == null ? const Value.absent() : Value(carryover),
        sortOrder: sortOrder == null ? const Value.absent() : Value(sortOrder),
      ),
    );
  }

  /// 恢复同名停用信封时合并旧档用：迁移某行的全部流水引用到另一行（ADR-0012）。
  /// 仅供 createOrRestoreEnvelope 内部在事务中调用。
  Future<void> _migrateEnvelopeRefs(String fromId, String toId) async {
    await (_db.update(_db.transactions)
          ..where((t) => t.envelopeId.equals(fromId)))
        .write(db.TransactionsCompanion(envelopeId: Value(toId)));
    await (_db.update(_db.transactions)..where((t) => t.fromId.equals(fromId)))
        .write(db.TransactionsCompanion(fromId: Value(toId)));
    await (_db.update(_db.transactions)..where((t) => t.toId.equals(fromId)))
        .write(db.TransactionsCompanion(toId: Value(toId)));
  }

  // ── 交易 ───────────────────────────────────

  /// 监听某账本的全部交易（新→旧）
  Stream<List<Txn>> watchTransactions(String ledgerId) {
    final q = _db.select(_db.transactions)
      ..where((t) => t.ledgerId.equals(ledgerId))
      ..orderBy([(t) => OrderingTerm.desc(t.at)]);
    return q.watch().map((rows) => rows.map(_txnFromRow).toList());
  }

  /// 新增一笔交易：写交易行 + 施加引擎影响（同一事务）。
  /// [fallback] 是调用方按不变量⑤生成的兜底描述（写入时定型）。
  Future<void> addTransaction({
    required String ledgerId,
    required Txn txn,
    required String fallback,
  }) async {
    final finalTxn = txn.description.isEmpty
        ? txn.copyWith(description: fallback)
        : txn;
    await _db.transaction(() async {
      final state = await _loadState(ledgerId);
      final after = applyTx(state, finalTxn, kApply);
      await _db
          .into(_db.transactions)
          .insert(
            db.TransactionsCompanion.insert(
              id: finalTxn.id,
              ledgerId: ledgerId,
              type: txTypeToDb(finalTxn.type),
              amount: finalTxn.amount,
              description: finalTxn.description.isEmpty
                  ? fallback
                  : finalTxn.description,
              at: finalTxn.at,
              envelopeId: Value(finalTxn.envelopeId),
              fromId: Value(finalTxn.fromId),
              toId: Value(finalTxn.toId),
            ),
          );
      await _writeBack(ledgerId, after);
    });
  }

  /// 编辑金额（不变量⑥：撤销旧的 + 施加新的，同一事务）。
  /// 描述不随金额编辑而改；类型 / 信封 / 时间不变。
  Future<void> editTransactionAmount({
    required String ledgerId,
    required Txn oldTxn,
    required double newAmount,
  }) async {
    await _db.transaction(() async {
      final state = await _loadState(ledgerId);
      final mid = applyTx(state, oldTxn, kRevert);
      final after = applyTx(mid, oldTxn.copyWith(amount: newAmount), kApply);
      await (_db.update(_db.transactions)..where((t) => t.id.equals(oldTxn.id)))
          .write(db.TransactionsCompanion(amount: Value(round2(newAmount))));
      await _writeBack(ledgerId, after);
    });
  }

  /// 编辑描述（不影响任何余额）
  Future<void> editTransactionDescription(String id, String description) async {
    await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
      db.TransactionsCompanion(description: Value(description)),
    );
  }

  /// 编辑时间（只允许改「日」，跨月由 UI 层挡住，见不变量⑧）
  Future<void> editTransactionAt(String id, DateTime at) async {
    await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
      db.TransactionsCompanion(at: Value(at)),
    );
  }

  /// 撤销一笔流水（ADR-0012：原「删除」，术语即语义）。
  /// 分流：涉及**停用信封**的笔只删行不动余额（停用时账面已清零、钱已结算，
  /// 引擎 revert 会造成重复入账/凭空消失）；其余正常走引擎。
  /// 结转退回（refund，ADR-0016）是系统行为、不可撤销：请求直接抛错，
  /// 删掉它只会抹掉账目痕迹、破坏钱守恒。
  Future<void> revertTransaction({
    required String ledgerId,
    required Txn txn,
  }) async {
    if (txn.type == TxType.refund) {
      throw ArgumentError('结转退回是系统行为，不可撤销（ADR-0016）');
    }
    final archivedIds = await _archivedEnvelopeIds(ledgerId);
    final touchesArchive = _touchesArchived(txn, archivedIds);
    await _db.transaction(() async {
      var state = await _loadState(ledgerId);
      if (!touchesArchive) {
        state = applyTx(state, txn, kRevert);
      }
      await (_db.delete(
        _db.transactions,
      )..where((t) => t.id.equals(txn.id))).go();
      await _writeBack(ledgerId, state);
    });
  }

  /// 批量撤销（整批原子，ADR-0012）：先整批预检待规划非负，任一笔不通过则整批不动。
  /// 涉及停用信封的笔只删行（不参与预检与余额计算）。
  /// 结转退回（refund，ADR-0016）不可撤销：出现在请求里即整批阻断（返回该笔）。
  /// 返回 null 表示全部成功；否则返回第一笔阻断的交易（UI 提示用）。
  Future<Txn?> revertTransactions({
    required String ledgerId,
    required List<Txn> txns,
  }) async {
    // 关键步骤：refund 是系统行为不可撤销——整批拦下，一笔都不动
    final refund = txns.where((t) => t.type == TxType.refund).firstOrNull;
    if (refund != null) return refund;
    final archivedIds = await _archivedEnvelopeIds(ledgerId);
    // 分流：引擎笔 vs 停用档案笔
    final engineTxns = txns
        .where((t) => !_touchesArchived(t, archivedIds))
        .toList();
    final archiveOnly = txns
        .where((t) => _touchesArchived(t, archivedIds))
        .toList();

    // 关键步骤：整批预检引擎笔——按顺序模拟 revert，任何一步 toBudget 为负即阻断
    var state = await _loadState(ledgerId);
    for (final t in engineTxns) {
      if (!deleteKeepsToBudgetNonNegative(state, t)) return t;
      state = applyTx(state, t, kRevert);
    }
    // 预检通过：同一事务内全部删行，引擎笔先 revert
    await _db.transaction(() async {
      var s = await _loadState(ledgerId);
      for (final t in engineTxns) {
        s = applyTx(s, t, kRevert);
        await (_db.delete(
          _db.transactions,
        )..where((x) => x.id.equals(t.id))).go();
      }
      for (final t in archiveOnly) {
        await (_db.delete(
          _db.transactions,
        )..where((x) => x.id.equals(t.id))).go();
      }
      await _writeBack(ledgerId, s);
    });
    return null;
  }

  /// 某账本全部**停用**信封的 id 集合
  Future<Set<String>> _archivedEnvelopeIds(String ledgerId) async {
    final rows =
        await (_db.select(_db.envelopes)..where(
              (e) => e.ledgerId.equals(ledgerId) & e.archivedAt.isNotNull(),
            ))
            .get();
    return rows.map((r) => r.id).toSet();
  }

  /// 一笔流水是否涉及停用信封（envelopeId / fromId / toId 任一命中）
  bool _touchesArchived(Txn t, Set<String> archivedIds) {
    if (archivedIds.isEmpty) return false;
    final ids = <String?>[t.envelopeId, t.fromId, t.toId];
    return ids.any(
      (id) => id != null && id != kToBudget && archivedIds.contains(id),
    );
  }

  // ── 设置 ───────────────────────────────────

  Stream<db.AppSetting> watchSettings(String ledgerId) {
    return (_db.select(
      _db.appSettings,
    )..where((s) => s.ledgerId.equals(ledgerId))).watchSingle();
  }

  Future<db.AppSetting> _settingsRow(String ledgerId) async {
    return (_db.select(
      _db.appSettings,
    )..where((s) => s.ledgerId.equals(ledgerId))).getSingle();
  }

  /// 更新结转全局默认
  Future<void> updateCarryoverDefault(String ledgerId, bool v) async {
    await (_db.update(_db.appSettings)
          ..where((s) => s.ledgerId.equals(ledgerId)))
        .write(db.AppSettingsCompanion(carryoverDefault: Value(v)));
  }

  /// 更新货币符号（v1.2.0 票 02 / ADR-0017）：按账本独立的显示偏好，
  /// 只改设置行，不影响任何金额数值、不产生流水。
  Future<void> updateCurrency(String ledgerId, String symbol) async {
    await (_db.update(_db.appSettings)
          ..where((s) => s.ledgerId.equals(ledgerId)))
        .write(db.AppSettingsCompanion(currency: Value(symbol)));
  }

  // ── 结转（ADR-0011：只对激活账本触发；ADR-0013：按周期边界触发）──────

  /// 打开 / 切换到某账本时调用：按账本自己的周期类型检测边界并静默结转。
  /// - 自动类型（自然月/每周/自定义起始日）：今天越过下期边界即结转，
  ///   新周期起点 = 今天所在周期起点（隔多期没打开也一次结到位）；
  /// - 自由周期：**永不**自动结转（唯一入口是设置页「结束本期」，后续票）；
  /// - 起点未初始化（迁移兜底）时只写入起点，不做结转；
  /// - 遗留 toBudget 原样带入；旧周期交易原样保留在流水里。
  Future<void> touchLedgerPeriod(String ledgerId, DateTime now) async {
    final ledger = await getLedger(ledgerId);
    if (ledger == null) return;
    final type = periodTypeFromDb(ledger.periodType);
    if (type == BudgetPeriodType.free) return; // 自由类型：永不自动结转

    final startDay = ledger.periodStartDay;
    // 今天所在周期起点（未初始化补写与结转后的新起点是同一个值，只算一次）
    final newStart = Value(
      isoDateOf(periodStartOf(type: type, startDay: startDay, now: now)),
    );
    final storedStart = tryParseIsoDate(ledger.lastPeriodStart);
    if (storedStart == null) {
      // 关键步骤：起点未初始化 → 只补写今天所在周期起点，无跨周期事实不结转
      await (_db.update(_db.ledgers)..where((l) => l.id.equals(ledgerId)))
          .write(db.LedgersCompanion(lastPeriodStart: newStart));
      return;
    }
    if (!hasCrossedPeriodBoundary(
      type: type,
      startDay: startDay,
      storedStart: storedStart,
      now: now,
    )) {
      return; // 仍在同一周期内
    }

    await _db.transaction(() async {
      // 关键步骤：越界 → 按三铁律结转全部信封；refund 流水回填旧周期结束时刻
      // （旧周期末 = 被越过的下期边界的前一毫秒，跨多期未打开也只结一次）
      final boundary = nextPeriodBoundary(
        type: type,
        startDay: startDay,
        periodStart: storedStart,
      );
      await _rollEnvelopeRows(
        ledgerId,
        periodEnd: boundary!.subtract(const Duration(milliseconds: 1)),
      );
      await (_db.update(_db.ledgers)..where((l) => l.id.equals(ledgerId)))
          .write(db.LedgersCompanion(lastPeriodStart: newStart));
    });
  }

  /// 结转某账本全部信封（铁律见 period_logic：正结余看开关——关开关退回待规划
  /// （ADR-0015）、负缺口必带、used 归零）。只动信封行与待规划，不写账本起点
  /// ——由调用方在同一事务内负责写。
  /// [periodEnd] 是旧周期结束时刻：关开关信封的正结余按 ADR-0016 每信封一笔
  /// 写入 refund 流水（at 回填 [periodEnd]、描述写入时定型「结转退回 · 信封名」），
  /// 金额流动经 applyTx 引擎施加——本通道自此不再是不写流水的余额变更点。
  Future<void> _rollEnvelopeRows(
    String ledgerId, {
    required DateTime periodEnd,
  }) async {
    final pre = await _loadState(ledgerId);
    // 关键步骤：先逐信封施加结转退回流水（引擎转移语义：信封扣减、待规划增加），
    // 再做信封面三铁律结转——顺序不可换，否则正结余会被退两次
    var state = pre;
    final refundRows = <db.TransactionsCompanion>[];
    for (final (env, amount) in carryRefundsOf(pre)) {
      final txn = Txn(
        id: _newId('tx'),
        type: TxType.refund,
        amount: amount,
        // 不变量⑤：描述写入时定型，之后不随信封改名而变
        description: fallbackDescription(
          type: TxType.refund,
          envelopeName: env.name,
        ),
        at: periodEnd,
        fromId: env.id,
        toId: kToBudget,
      );
      state = applyTx(state, txn, kApply);
      refundRows.add(
        db.TransactionsCompanion.insert(
          id: txn.id,
          ledgerId: ledgerId,
          type: txTypeToDb(txn.type),
          amount: txn.amount,
          description: txn.description,
          at: txn.at,
          fromId: Value(txn.fromId),
          toId: Value(txn.toId),
        ),
      );
    }
    // 信封面三铁律结转（正结余已随 refund 流水退出，这里不再二次退款）
    await _writeBack(ledgerId, carryOverEnvelopes(state));
    for (final row in refundRows) {
      await _db.into(_db.transactions).insert(row);
    }
  }

  // ── 周期设置（ADR-0013 §4/§5）──────────────

  /// 更新预算周期设置：切换类型或修改起始日时立即按新规则重算当前周期起点；
  /// 若与已存起点不同，**当场静默结转一次**（与打开账本同一套语义）。
  /// 自由类型只换标记不结转（§5：自由只手动）；自定义起始日必须 1–28。
  /// [now] 仅供测试注入。返回是否执行了结转（UI 提示用）。
  Future<bool> updateBudgetPeriod(
    String ledgerId, {
    required BudgetPeriodType type,
    int? startDay,
    DateTime? now,
  }) async {
    if (type == BudgetPeriodType.customStartDay &&
        !isValidCustomStartDay(startDay ?? 0)) {
      throw ArgumentError.value(startDay, 'startDay', '自定义起始日必须在 1–28');
    }
    final ledger = await getLedger(ledgerId);
    if (ledger == null) return false;
    final at = now ?? DateTime.now();
    final storedStart = tryParseIsoDate(ledger.lastPeriodStart);
    // 结转判定与 UI 预告共用同一纯函数（预告什么就发生什么）
    final roll = switchRequiresCarryover(
      newType: type,
      newStartDay: startDay,
      storedStart: storedStart,
      now: at,
    );
    final newStart = periodStartOf(
      type: type,
      startDay: startDay,
      now: at,
      storedStart: storedStart,
    );
    await _db.transaction(() async {
      if (roll) {
        // 关键步骤：起点变化 → 按三铁律当场结转一次
        // （旧周期在设置变更那一刻被截断，refund 流水回填该时刻）
        await _rollEnvelopeRows(ledgerId, periodEnd: at);
      }
      await (_db.update(
        _db.ledgers,
      )..where((l) => l.id.equals(ledgerId))).write(
        db.LedgersCompanion(
          periodType: Value(periodTypeToDb(type)),
          // 起始日只在自定义类型下有值
          periodStartDay: Value(
            type == BudgetPeriodType.customStartDay ? startDay : null,
          ),
          lastPeriodStart: Value(isoDateOf(newStart)),
        ),
      );
    });
    return roll;
  }

  /// 自由周期「结束本期」（ADR-0013 §5）：结转一次，新周期起点 = 点击当日。
  /// 仅对自由类型生效（唯一手动结转入口）；本期已从今天开始时不重复结转。
  /// [now] 仅供测试注入。返回是否执行了结转。
  Future<bool> closeFreePeriod(String ledgerId, DateTime now) async {
    final ledger = await getLedger(ledgerId);
    if (ledger == null) return false;
    if (periodTypeFromDb(ledger.periodType) != BudgetPeriodType.free) {
      return false; // 只有自由周期有手动结束
    }
    final today = dateOnly(now);
    final storedStart = tryParseIsoDate(ledger.lastPeriodStart);
    if (storedStart != null && storedStart == today) {
      return false; // 本期已从今天开始：重复点击不重复结转
    }
    await _db.transaction(() async {
      // 关键步骤：手动结束本期 → 结转一次，refund 流水回填点击时刻
      // （自由周期的旧周期结束时刻就是用户点击的那一刻）
      await _rollEnvelopeRows(ledgerId, periodEnd: now);
      await (_db.update(_db.ledgers)..where((l) => l.id.equals(ledgerId)))
          .write(db.LedgersCompanion(lastPeriodStart: Value(isoDateOf(today))));
    });
    return true;
  }

  // ── 数据变动信号（自动备份的触发源，v1.2.x 票 02 · ADR-0018）──────

  /// 监听全库数据变动（账本/信封/流水/设置四表）。drift 按事务提交原子通知：
  /// 一次编辑交易（撤旧 + 记新）只产生一次事件——自动备份防抖以此为「一次变动」。
  Stream<Set<TableUpdate>> watchDataChanges() {
    return _db.tableUpdates(
      TableUpdateQuery.onAllTables([
        _db.ledgers,
        _db.envelopes,
        _db.transactions,
        _db.appSettings,
      ]),
    );
  }

  // ── 备份与恢复（.jx = JSON 全量导出，ADR-0011：覆盖全部账本）───────

  /// 导出全部账本数据为 .jx 内容（JSON 字符串，含 schemaVersion 供恢复时校验）
  Future<String> exportBackupJson() async {
    final ledgers = await (_db.select(
      _db.ledgers,
    )..orderBy([(l) => OrderingTerm.asc(l.sortOrder)])).get();
    final envelopes = await (_db.select(_db.envelopes)).get();
    final txns = await (_db.select(_db.transactions)).get();
    final settings = await (_db.select(_db.appSettings)).get();
    final map = <String, dynamic>{
      'app': '金打细算',
      'schemaVersion': _db.schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'counts': {
        'ledgers': ledgers.length,
        'envelopes': envelopes.length,
        'transactions': txns.length,
      },
      'ledgers': ledgers.map((r) => r.toJson()).toList(),
      'envelopes': envelopes.map((r) => r.toJson()).toList(),
      'transactions': txns.map((r) => r.toJson()).toList(),
      'appSettings': settings.map((r) => r.toJson()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// 读取一份备份的摘要（列表行用）：解析 JSON 取导出时间与笔数。
  /// 内容损坏会抛 FormatException，由调用方处理。
  Future<BackupSummary> readBackupSummary(String raw) async {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final counts = (map['counts'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BackupSummary(
      exportedAt:
          DateTime.tryParse(map['exportedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      ledgerCount: (counts['ledgers'] as num?)?.toInt() ?? 0,
      envelopeCount: (counts['envelopes'] as num?)?.toInt() ?? 0,
      txnCount: (counts['transactions'] as num?)?.toInt() ?? 0,
    );
  }

  /// 从 .jx 内容恢复：清空全部表后整体写回（单事务）。
  /// 版本策略（票 01）：旧版本（≤ 当前 schema）先归一化到当前结构再写回；
  /// 比当前更新或无法识别的版本拒收。内容损坏抛 BackupRestoreException；
  /// 失败时库未被改动。
  Future<void> restoreFromJson(String raw) async {
    final Map<String, dynamic> map;
    try {
      map = jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      throw BackupRestoreException('这份备份没能读出来，可能已损坏。');
    }
    final version = (map['schemaVersion'] as num?)?.toInt();
    if (version == null || version > _db.schemaVersion) {
      throw BackupRestoreException(
        version == null
            ? '这份备份没能读出来，可能已损坏。'
            : '这份备份来自更新的版本（$version），'
                  '当前版本（${_db.schemaVersion}）暂不支持恢复。',
      );
    }
    try {
      final ledgers = (map['ledgers'] as List? ?? const [])
          .map(
            (m) => db.Ledger.fromJson(
              _normalizeLedgerJson(m as Map<String, dynamic>),
            ),
          )
          .toList();
      final envelopes = (map['envelopes'] as List? ?? const [])
          .map((m) => db.Envelope.fromJson(m as Map<String, dynamic>))
          .toList();
      final txns = (map['transactions'] as List? ?? const [])
          .map((m) => db.Transaction.fromJson(m as Map<String, dynamic>))
          .toList();
      final settings = (map['appSettings'] as List? ?? const [])
          .map(
            (m) => db.AppSetting.fromJson(
              _normalizeSettingJson(m as Map<String, dynamic>),
            ),
          )
          .toList();

      await _db.transaction(() async {
        // 关键步骤：先清空再整体写回（外键顺序：流水 → 信封 → 设置 → 账本）
        await _db.delete(_db.transactions).go();
        await _db.delete(_db.envelopes).go();
        await _db.delete(_db.appSettings).go();
        await _db.delete(_db.ledgers).go();
        await _db.batch((b) {
          b.insertAll(_db.ledgers, ledgers);
          b.insertAll(_db.envelopes, envelopes);
          b.insertAll(_db.transactions, txns);
          b.insertAll(_db.appSettings, settings);
        });
      });
    } on BackupRestoreException {
      rethrow;
    } on Exception {
      // fromJson/insert 失败：事务已回滚，当前数据未动
      throw BackupRestoreException('这份备份没能读出来，可能已损坏。');
    }
  }

  /// 旧版备份（schema v1/v2）的账本 JSON 归一化到当前结构（ADR-0013）：
  /// - lastActiveMonth（月 key '2026-09'）→ lastPeriodStart（'2026-09-01' 当月 1 号）
  /// - 缺失 periodType → 默认自然月；缺失 periodStartDay → null（仅自定义类型用）
  /// - 缺失 onboarded → false（最旧备份兜底）
  Map<String, dynamic> _normalizeLedgerJson(Map<String, dynamic> m) {
    final out = Map<String, dynamic>.of(m);
    final legacyMonth = out.remove('lastActiveMonth') as String?;
    out['lastPeriodStart'] ??= legacyMonth == null ? null : '$legacyMonth-01';
    out['periodType'] ??= periodTypeToDb(BudgetPeriodType.naturalMonth);
    if (!out.containsKey('periodStartDay')) out['periodStartDay'] = null;
    out['onboarded'] ??= false;
    return out;
  }

  /// 旧版备份（schema ≤ v3）的设置 JSON 归一化到当前结构（v1.2.0 票 02 / ADR-0017）：
  /// 缺失 currency → 默认符号 ¥（drift 的 fromJson 对缺失的非空列会直接抛错，
  /// 必须在此补默认值；v4 起导出的备份自带该键）
  Map<String, dynamic> _normalizeSettingJson(Map<String, dynamic> m) {
    final out = Map<String, dynamic>.of(m);
    out['currency'] ??= kDefaultCurrency;
    return out;
  }

  /// 某个自然日内新增的流水数（恢复确认文案用：会丢什么要算清楚，§19）
  Future<int> countTxnsOnDay(DateTime day) async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final c = _db.transactions.id.count();
    final q = _db.selectOnly(_db.transactions)
      ..addColumns([c])
      ..where(
        _db.transactions.at.isBiggerOrEqualValue(start) &
            _db.transactions.at.isSmallerThanValue(end),
      );
    final row = await q.getSingle();
    return row.read(c) ?? 0;
  }

  // ── 内部工具 ───────────────────────────────

  /// 读一份当前账本的引擎输入状态
  Future<LedgerState> _loadState(String ledgerId) async {
    final settings = await _settingsRow(ledgerId);
    final rows = await (_db.select(
      _db.envelopes,
    )..where((e) => e.ledgerId.equals(ledgerId))).get();
    final envs = {for (final r in rows) r.id: _envFromRow(r)};
    return LedgerState(toBudget: settings.toBudget, envelopes: envs);
  }

  /// 把引擎输出的状态写回各表（只写被引用的字段）
  Future<void> _writeBack(String ledgerId, LedgerState after) async {
    await (_db.update(_db.appSettings)
          ..where((s) => s.ledgerId.equals(ledgerId)))
        .write(db.AppSettingsCompanion(toBudget: Value(after.toBudget)));
    for (final e in after.envelopes.values) {
      await (_db.update(_db.envelopes)..where((x) => x.id.equals(e.id))).write(
        db.EnvelopesCompanion(planned: Value(e.planned), used: Value(e.used)),
      );
    }
  }

  Envelope _envFromRow(db.Envelope r) => Envelope(
    id: r.id,
    name: r.name,
    icon: r.icon,
    color: r.color,
    planned: r.planned,
    used: r.used,
    target: r.target,
    carryover: r.carryover,
    archivedAt: r.archivedAt,
  );

  Txn _txnFromRow(db.Transaction r) => Txn(
    id: r.id,
    type: txTypeFromDb(r.type),
    amount: r.amount,
    description: r.description,
    at: r.at,
    envelopeId: r.envelopeId,
    fromId: r.fromId,
    toId: r.toId,
  );

  // 自增序号：同一微秒内多次生成的 id 也不会冲突（如结转一次写多笔退款流水）
  int _idSeq = 0;

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${_idSeq++}';

  /// 生成新的交易 id（流程编排层构建 Txn 时用）
  String newTxnId() => _newId('tx');
}
