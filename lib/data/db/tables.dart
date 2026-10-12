// drift 表定义 — 对应 IMPLEMENTATION.md §1 数据模型，外加以 ledgerId 为维度的账本（ADR-0011）。
import 'package:drift/drift.dart';

import '../../domain/models.dart' show kDefaultCurrency;

/// 账本 — 互相隔离的数据空间（不是账户层，见 ADR-0011）。
/// 预算周期每账本独立（ADR-0013）。
class Ledgers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// 该账本是否已完成三屏引导（新账本从零开始，重走引导）
  BoolColumn get onboarded => boolean().withDefault(const Constant(false))();

  /// 当前周期起点（ISO 日期 'yyyy-MM-dd'），打开/切换时用于结转检测（ADR-0013）
  TextColumn get lastPeriodStart => text().nullable()();

  /// 预算周期类型：naturalMonth | weekly | customStartDay | free（ADR-0013）
  TextColumn get periodType =>
      text().withDefault(const Constant('naturalMonth'))();

  /// 自定义起始日（1–28），仅 periodType = customStartDay 时有值
  IntColumn get periodStartDay => integer().nullable()();

  /// 排序：创建顺序
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 信封
class Envelopes extends Table {
  TextColumn get id => text()();
  TextColumn get ledgerId => text()();
  TextColumn get name => text()();
  TextColumn get icon => text()();
  TextColumn get color => text()();

  /// 本期被分配到的金额
  RealColumn get planned => real()();

  /// 本期已发生的支出
  RealColumn get used => real()();

  /// 可选目标额，只用于进度条
  RealColumn get target => real().nullable()();

  /// 本期结余是否带入下一期
  BoolColumn get carryover => boolean()();

  /// 首页网格排序
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// 停用时间（ADR-0012）：非空 = 已停用；信封没有删除，只有停用与恢复
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 交易：expense | income | transfer | refund（ADR-0016）。
/// 分配 = transfer(fromId='toBudget')；撤销 = transfer(toId='toBudget')；
/// 结转退回 = refund(fromId=信封, toId='toBudget')，系统行为、不可撤销。
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get ledgerId => text()();
  TextColumn get type => text()();

  /// 恒为正数，方向由 type/fromId/toId 决定
  RealColumn get amount => real()();

  /// 写入时定型（不变量⑤），不随信封改名而变
  TextColumn get description => text()();
  DateTimeColumn get at => dateTime()();

  /// expense 必填
  TextColumn get envelopeId => text().nullable()();

  /// transfer 必填，可为 'toBudget'
  TextColumn get fromId => text().nullable()();

  /// 同上
  TextColumn get toId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 描述历史（v1.3.0 票 02 / ADR-0020）：每个信封（含待规划 'toBudget'）记住的、
/// 用户在数字键盘**手动输入过**的描述。只有手输文字入史，兜底描述不入；
/// 同信封重复输入上浮不重复；每信封保留最近 N 条（kDescriptionHistoryLimit）。
/// 独立于交易存在——撤销/删除交易不触碰本表。
class DescriptionHistory extends Table {
  TextColumn get ledgerId => text()();

  /// 信封 id，或 'toBudget'（待规划是独立的历史域）
  TextColumn get envelopeId => text()();

  TextColumn get description => text()();

  /// 最近一次输入时刻（排序与 LRU 淘汰依据）
  DateTimeColumn get lastUsedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {ledgerId, envelopeId, description};
}

/// 每账本一份的设置
class AppSettings extends Table {
  TextColumn get ledgerId => text()();

  /// 尚未分配到任何信封的钱（不变量②：不允许为负）
  RealColumn get toBudget => real()();

  /// 新建信封时的默认结转值
  BoolColumn get carryoverDefault =>
      boolean().withDefault(const Constant(true))();

  /// 货币符号（v1.2.0 票 02 / ADR-0017）：按账本独立的显示偏好，默认 ¥。
  /// 影响数据可读性、属账本语义，故进 schema（与「装饰性数据不进 schema」的边界见 ADR-0017）。
  TextColumn get currency =>
      text().withDefault(const Constant(kDefaultCurrency))();

  @override
  Set<Column> get primaryKey => {ledgerId};
}
