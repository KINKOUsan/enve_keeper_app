// period_logic / tx_engine 结转与删除安全单测 — 只测纯函数输入输出（spec Testing Decisions）。
// 覆盖：周期起点/下期边界推算（四类型）、结转触发判定（自由类型永不自动）、
// carryEnvelope 结转三铁律矩阵（四类型下语义一致）、跨月周周期与统计日历解耦、
// deleteKeepsToBudgetNonNegative（各类型矩阵，不变量⑦：撤销后 toBudget 不许为负）、
// 结转退回 refund（v1.2.0 票 01 / ADR-0016）：引擎转移语义、零和守恒、流水组合。
import 'package:flutter_test/flutter_test.dart';
import 'package:enve_keeper_app/domain/models.dart';
import 'package:enve_keeper_app/domain/period_logic.dart';
import 'package:enve_keeper_app/domain/tx_engine.dart';

// 造一个信封的快捷方法（只关心金额字段，其余给固定值）
Envelope _env({
  String id = 'e1',
  double planned = 0,
  double used = 0,
  bool carryover = true,
}) {
  return Envelope(
    id: id,
    name: '信封$id',
    icon: 'food',
    color: 'clay',
    planned: planned,
    used: used,
    carryover: carryover,
  );
}

// 造一笔交易的快捷方法
Txn _txn(TxType type, double amount, {String? from, String? to, String? env}) {
  return Txn(
    id: 't',
    type: type,
    amount: amount,
    description: '',
    at: DateTime(2026, 9, 15),
    envelopeId: env,
    fromId: from,
    toId: to,
  );
}

// 生产结转组合（与仓库层 _rollEnvelopeRows 同序，v1.2.0 票 01 / ADR-0016）：
// 先逐信封施加结转退回流水（引擎转移语义：信封扣减、待规划增加），
// 再做信封面三铁律。顺序不可换，否则正结余会被退两次。
LedgerState _rollWithRefunds(LedgerState s) {
  var state = s;
  for (final (e, amount) in carryRefundsOf(s)) {
    state = applyTx(
      state,
      Txn(
        id: 'refund-${e.id}',
        type: TxType.refund,
        amount: amount,
        description: '结转退回 · ${e.name}',
        at: DateTime(2026, 9, 30, 23, 59, 59),
        fromId: e.id,
        toId: kToBudget,
      ),
      kApply,
    );
  }
  return carryOverEnvelopes(state);
}

void main() {
  group('isoDateOf / tryParseIsoDate 日期序列化', () {
    test('DateTime → ISO 日期，补零定宽', () {
      expect(isoDateOf(DateTime(2026, 9, 1)), '2026-09-01');
      expect(isoDateOf(DateTime(2026, 12, 28)), '2026-12-28');
    });

    test('ISO 日期 → 本地 0 点；坏串返回 null', () {
      expect(tryParseIsoDate('2026-09-01'), DateTime(2026, 9, 1));
      expect(tryParseIsoDate('垃圾'), isNull);
      expect(tryParseIsoDate(null), isNull);
    });

    test('dateOnly 去掉时分秒', () {
      final d = dateOnly(DateTime(2026, 9, 17, 15, 30, 45));
      expect(d, DateTime(2026, 9, 17));
    });
  });

  group('isValidCustomStartDay 起始日范围', () {
    test('1–28 合法（每月都存在，避开 2 月与小月歧义）', () {
      expect(isValidCustomStartDay(1), isTrue);
      expect(isValidCustomStartDay(15), isTrue);
      expect(isValidCustomStartDay(28), isTrue);
    });

    test('0 / 29 / 31 / 负数不合法', () {
      expect(isValidCustomStartDay(0), isFalse);
      expect(isValidCustomStartDay(29), isFalse);
      expect(isValidCustomStartDay(31), isFalse);
      expect(isValidCustomStartDay(-3), isFalse);
    });
  });

  group('periodStartOf 周期起点推算', () {
    test('自然月：本月 1 号 0 点（月中任意时刻同一起点）', () {
      expect(
        periodStartOf(
          type: BudgetPeriodType.naturalMonth,
          now: DateTime(2026, 9, 17, 15, 30),
        ),
        DateTime(2026, 9, 1),
      );
      expect(
        periodStartOf(
          type: BudgetPeriodType.naturalMonth,
          now: DateTime(2026, 9, 1),
        ),
        DateTime(2026, 9, 1),
      );
    });

    test('每周：本周一 0 点（周中/周日都归到同一周一）', () {
      // 2026-09-17 是周四，所在周的周一是 9月14日
      expect(
        periodStartOf(
          type: BudgetPeriodType.weekly,
          now: DateTime(2026, 9, 17, 22),
        ),
        DateTime(2026, 9, 14),
      );
      // 2026-09-20 是周日，仍归到 9月14日那一周
      expect(
        periodStartOf(
          type: BudgetPeriodType.weekly,
          now: DateTime(2026, 9, 20),
        ),
        DateTime(2026, 9, 14),
      );
    });

    test('自定义起始日：本月 X 号起；本月还没到则回退上月 X 号', () {
      // 9月17日，起始日 15 → 本月 15 号
      expect(
        periodStartOf(
          type: BudgetPeriodType.customStartDay,
          startDay: 15,
          now: DateTime(2026, 9, 17),
        ),
        DateTime(2026, 9, 15),
      );
      // 9月1日，起始日 15 → 上月 15 号
      expect(
        periodStartOf(
          type: BudgetPeriodType.customStartDay,
          startDay: 15,
          now: DateTime(2026, 9, 1),
        ),
        DateTime(2026, 8, 15),
      );
      // 起始日 1：行为与自然月一致
      expect(
        periodStartOf(
          type: BudgetPeriodType.customStartDay,
          startDay: 1,
          now: DateTime(2026, 9, 30),
        ),
        DateTime(2026, 9, 1),
      );
    });

    test('自定义起始日跨年回退：1 月初回退到上一年 12 月', () {
      expect(
        periodStartOf(
          type: BudgetPeriodType.customStartDay,
          startDay: 20,
          now: DateTime(2027, 1, 5),
        ),
        DateTime(2026, 12, 20),
      );
    });

    test('自由周期：起点就是已存的那一天；无已存则用今天', () {
      expect(
        periodStartOf(
          type: BudgetPeriodType.free,
          now: DateTime(2026, 9, 17),
          storedStart: DateTime(2026, 9, 10),
        ),
        DateTime(2026, 9, 10),
      );
      expect(
        periodStartOf(
          type: BudgetPeriodType.free,
          now: DateTime(2026, 9, 17, 8),
        ),
        DateTime(2026, 9, 17),
      );
    });
  });

  group('nextPeriodBoundary 下期边界推算', () {
    test('自然月：下月 1 号（跨年 12 月 → 1 月）', () {
      expect(
        nextPeriodBoundary(
          type: BudgetPeriodType.naturalMonth,
          periodStart: DateTime(2026, 9, 1),
        ),
        DateTime(2026, 10, 1),
      );
      expect(
        nextPeriodBoundary(
          type: BudgetPeriodType.naturalMonth,
          periodStart: DateTime(2026, 12, 1),
        ),
        DateTime(2027, 1, 1),
      );
    });

    test('每周：起点 + 7 天（永远是周一）', () {
      final next = nextPeriodBoundary(
        type: BudgetPeriodType.weekly,
        periodStart: DateTime(2026, 9, 21),
      )!;
      expect(next, DateTime(2026, 9, 28));
      expect(next.weekday, DateTime.monday);
    });

    test('自定义起始日：下月同号（28 号对 2 月无需特判）', () {
      // 1月28日 → 2月28日（2027 非闰年，28 号存在）
      expect(
        nextPeriodBoundary(
          type: BudgetPeriodType.customStartDay,
          startDay: 28,
          periodStart: DateTime(2027, 1, 28),
        ),
        DateTime(2027, 2, 28),
      );
      // 2月28日 → 3月28日，永不出「2月30日」
      expect(
        nextPeriodBoundary(
          type: BudgetPeriodType.customStartDay,
          startDay: 28,
          periodStart: DateTime(2027, 2, 28),
        ),
        DateTime(2027, 3, 28),
      );
    });

    test('自由周期：没有自动边界（null）', () {
      expect(
        nextPeriodBoundary(
          type: BudgetPeriodType.free,
          periodStart: DateTime(2026, 9, 10),
        ),
        isNull,
      );
    });
  });

  group('hasCrossedPeriodBoundary 结转触发判定', () {
    test('自由周期永不自动触发（哪怕已存起点很古老）', () {
      expect(
        hasCrossedPeriodBoundary(
          type: BudgetPeriodType.free,
          storedStart: DateTime(2025, 1, 1),
          now: DateTime(2026, 9, 17),
        ),
        isFalse,
      );
    });

    test('未初始化（storedStart = null）不触发，由调用方写入起点', () {
      expect(
        hasCrossedPeriodBoundary(
          type: BudgetPeriodType.naturalMonth,
          storedStart: null,
          now: DateTime(2026, 9, 17),
        ),
        isFalse,
      );
    });

    test('自然月：期内不触发；边界日当天触发；隔多月一次结到位', () {
      const type = BudgetPeriodType.naturalMonth;
      final stored = DateTime(2026, 9, 1);
      expect(
        hasCrossedPeriodBoundary(
          type: type,
          storedStart: stored,
          now: DateTime(2026, 9, 30, 23, 59),
        ),
        isFalse,
      );
      expect(
        hasCrossedPeriodBoundary(
          type: type,
          storedStart: stored,
          now: DateTime(2026, 10, 1),
        ),
        isTrue,
      );
      // 两个月没打开 App：也只判「已越过」，新起点由 periodStartOf(今天) 给出
      expect(
        hasCrossedPeriodBoundary(
          type: type,
          storedStart: stored,
          now: DateTime(2026, 12, 15),
        ),
        isTrue,
      );
    });

    test('每周：周日深夜不触发，周一凌晨触发', () {
      const type = BudgetPeriodType.weekly;
      final stored = DateTime(2026, 9, 21); // 周一
      expect(
        hasCrossedPeriodBoundary(
          type: type,
          storedStart: stored,
          now: DateTime(2026, 9, 27, 23, 0), // 周日
        ),
        isFalse,
      );
      expect(
        hasCrossedPeriodBoundary(
          type: type,
          storedStart: stored,
          now: DateTime(2026, 9, 28, 0, 1), // 周一
        ),
        isTrue,
      );
    });

    test('自定义起始日：起始日前不触发（9月期跨到 10 月初仍在期内）', () {
      const type = BudgetPeriodType.customStartDay;
      expect(
        hasCrossedPeriodBoundary(
          type: type,
          startDay: 15,
          storedStart: DateTime(2026, 9, 15),
          now: DateTime(2026, 10, 1),
        ),
        isFalse,
      );
      expect(
        hasCrossedPeriodBoundary(
          type: type,
          startDay: 15,
          storedStart: DateTime(2026, 9, 15),
          now: DateTime(2026, 10, 15),
        ),
        isTrue,
      );
    });
  });

  group('跨月周周期与统计日历解耦（ADR-0013 §7）', () {
    test('周期跨月合法：9月28日（周一）开始的周期包含 10月1日–4日', () {
      final stored = DateTime(2026, 9, 28); // 周一
      // 10 月 1 日（周四）仍在同一周期：不触发结转
      expect(
        hasCrossedPeriodBoundary(
          type: BudgetPeriodType.weekly,
          storedStart: stored,
          now: DateTime(2026, 10, 1, 12),
        ),
        isFalse,
      );
      // 今天所在周期起点仍是 9月28日，与已存起点一致
      expect(
        periodStartOf(
          type: BudgetPeriodType.weekly,
          now: DateTime(2026, 10, 2),
        ),
        stored,
      );
      // 10月5日（周一）越界 → 新起点 10月5日
      expect(
        hasCrossedPeriodBoundary(
          type: BudgetPeriodType.weekly,
          storedStart: stored,
          now: DateTime(2026, 10, 5),
        ),
        isTrue,
      );
      expect(
        periodStartOf(
          type: BudgetPeriodType.weekly,
          now: DateTime(2026, 10, 5),
        ),
        DateTime(2026, 10, 5),
      );
    });

    test('统计仍按日历月聚合，不受预算周期影响', () {
      // 同一天 10月2日：预算周期起点是 9月28日（周周期），统计口径仍是 10 月
      final day = DateTime(2026, 10, 2);
      expect(
        periodStartOf(type: BudgetPeriodType.weekly, now: day),
        DateTime(2026, 9, 28),
      );
      expect(monthStart(day), DateTime(2026, 10, 1));
      expect(rangeOf(day).key, '2026-10');
      // 周期起点 9月28日所在的自然月仍是 9 月（日历函数不感知周期）
      expect(monthStart(DateTime(2026, 9, 28)), DateTime(2026, 9, 1));
    });
  });

  group('结转铁律矩阵 — 四种周期类型下语义一致（ADR-0013 §6 + ADR-0015/0016）', () {
    // 结转语义与周期类型无关（carryOverEnvelopes 不感知类型）：
    // 正结余看信封开关（关 = 账面清零并经 refund 流水退回待规划）、
    // 负缺口无论开关都带入、used 归零。矩阵遍历四类型钉住「换周期类型不换结转结果」
    // 的契约；组合方式 = 生产路径（引擎施加 refund 流水 → 信封面结转）。
    for (final type in BudgetPeriodType.values) {
      test('$type：混合状态结转（正结余/关结转/透支/待规划）', () {
        final s = LedgerState(
          toBudget: 500.25,
          envelopes: {
            'a': _env(id: 'a', planned: 100, used: 40, carryover: true),
            'b': _env(id: 'b', planned: 200, used: 150, carryover: false),
            'c': _env(id: 'c', planned: 80, used: 120, carryover: false),
          },
        );
        final r = _rollWithRefunds(s);
        // 铁律一：正结余看开关（a 开 → 带入 60；b 关 → 账面清零并退回待规划）
        expect(r.envelopes['a']!.planned, 60);
        expect(r.envelopes['b']!.planned, 0);
        // 铁律二：负缺口无论开关都带入（c 透支 40，c 是关结转也照带）
        expect(r.envelopes['c']!.planned, -40);
        // 铁律三：used 一律归零；关开关的正结余 50 退回待规划（500.25 + 50）
        expect(r.envelopes.values.every((e) => e.used == 0), isTrue);
        expect(r.toBudget, 550.25);
      });

      test('$type：钱守恒 — 结转前后总金额不变（ADR-0015 单入口单出口）', () {
        final s = LedgerState(
          toBudget: 300,
          envelopes: {
            'a': _env(id: 'a', planned: 100, used: 40, carryover: true),
            'b': _env(id: 'b', planned: 200, used: 150, carryover: false),
            'c': _env(id: 'c', planned: 80, used: 120, carryover: false),
          },
        );
        final r = _rollWithRefunds(s);
        // 总额 = 待规划 + 各信封 available（used 已花掉，不在守恒范围；
        // 结转后 planned 即剩余），结转前后必须相等
        final before =
            s.toBudget +
            s.envelopes.values.fold(0.0, (t, e) => t + e.available);
        final after =
            r.toBudget + r.envelopes.values.fold(0.0, (t, e) => t + e.planned);
        expect(after, before);
      });
    }

    test('carryOverEnvelopes 纯函数性：不修改入参状态、不动待规划', () {
      final s = LedgerState(
        toBudget: 100,
        envelopes: {'a': _env(id: 'a', planned: 100, used: 40)},
      );
      carryOverEnvelopes(s);
      expect(s.envelopes['a']!.planned, 100);
      expect(s.envelopes['a']!.used, 40);
      final r = carryOverEnvelopes(s);
      expect(r.toBudget, 100); // 退款不在本函数内直接加 toBudget（ADR-0016）
    });
  });

  group('carryRefundsOf 结转退款清单（v1.2.0 票 01 / ADR-0016 流水数据源）', () {
    test('只含关开关且正结余的信封，金额 = available（round2）', () {
      final s = LedgerState(
        toBudget: 0,
        envelopes: {
          'a': _env(id: 'a', planned: 100, used: 40, carryover: true),
          'b': _env(id: 'b', planned: 200, used: 150, carryover: false),
          'c': _env(id: 'c', planned: 80, used: 120, carryover: false),
          'd': _env(id: 'd', planned: 50, used: 50, carryover: false),
        },
      );
      final refunds = carryRefundsOf(s);
      expect(refunds.length, 1);
      expect(refunds.single.$1.id, 'b');
      expect(refunds.single.$2, 50);
    });

    test('全开结转/全透支 → 空清单（无退款即无 refund 流水）', () {
      final s = LedgerState(
        toBudget: 0,
        envelopes: {
          'a': _env(id: 'a', planned: 100, used: 40, carryover: true),
          'b': _env(id: 'b', planned: 50, used: 80, carryover: false),
        },
      );
      expect(carryRefundsOf(s), isEmpty);
    });

    test('多信封退款逐项列出（每信封一笔流水的前提）', () {
      final s = LedgerState(
        toBudget: 0,
        envelopes: {
          'a': _env(id: 'a', planned: 30, used: 10, carryover: false),
          'b': _env(id: 'b', planned: 12.5, used: 0, carryover: false),
        },
      );
      final refunds = carryRefundsOf(s);
      expect(refunds.map((r) => r.$1.id), ['a', 'b']);
      expect(refunds.fold(0.0, (t, r) => t + r.$2), 32.5);
    });
  });

  group('引擎 refund 分支 — 结转退回的转移语义（v1.2.0 票 01 / ADR-0016）', () {
    test('施加：信封 planned 扣减、待规划增加，零和', () {
      final s = LedgerState(
        toBudget: 100,
        envelopes: {'a': _env(id: 'a', planned: 60, used: 20)},
      );
      final r = applyTx(
        s,
        _txn(TxType.refund, 40, from: 'a', to: kToBudget),
        kApply,
      );
      expect(r.envelopes['a']!.planned, 20); // 信封扣减
      expect(r.envelopes['a']!.used, 20); // used 不动
      expect(r.toBudget, 140); // 待规划增加
      // 零和：总额（toBudget + Σavailable）不变
      final totalBefore = s.toBudget + s.envelopes['a']!.available;
      final totalAfter = r.toBudget + r.envelopes['a']!.available;
      expect(totalAfter, totalBefore);
    });

    test('撤销（引擎层面）：方向相反，待规划扣回前不得为负（不变量⑦守卫一致）', () {
      final s = LedgerState(
        toBudget: 100,
        envelopes: {'a': _env(id: 'a', planned: 60, used: 20)},
      );
      final txn = _txn(TxType.refund, 40, from: 'a', to: kToBudget);
      final applied = applyTx(s, txn, kApply);
      final reverted = applyTx(applied, txn, kRevert);
      expect(reverted.toBudget, 100); // 施加/撤销往返后原样
      expect(reverted.envelopes['a']!.planned, 60);
      // 守卫：toBudget 不足以扣回时挡住（与撤销分配同口径）
      expect(deleteKeepsToBudgetNonNegative(applied, txn), isTrue);
      expect(
        deleteKeepsToBudgetNonNegative(
          LedgerState(toBudget: 39.99, envelopes: applied.envelopes),
          txn,
        ),
        isFalse,
      );
    });

    test('金额精度：planned/toBudget 都过 round2，无浮点漂移', () {
      final s = LedgerState(
        toBudget: 0.1 + 0.2,
        envelopes: {'a': _env(id: 'a', planned: 33.33, used: 0.01)},
      );
      final r = applyTx(
        s,
        _txn(TxType.refund, 33.32, from: 'a', to: kToBudget),
        kApply,
      );
      expect(r.envelopes['a']!.planned, 0.01);
      expect(r.toBudget, 33.62);
    });
  });

  group('carryRefund 结转退款（ADR-0015：关开关的正结余退回待规划）', () {
    test('正结余 + 结转关 → 退款 = 剩余金额', () {
      expect(carryRefund(_env(planned: 100, used: 30, carryover: false)), 70);
    });

    test('正结余 + 结转开 → 不退款（结余带入下期）', () {
      expect(carryRefund(_env(planned: 100, used: 30, carryover: true)), 0);
    });

    test('透支 + 结转关 → 不退款（缺口带入下期，不变量①）', () {
      expect(carryRefund(_env(planned: 50, used: 80, carryover: false)), 0);
    });

    test('零结余 → 不退款', () {
      expect(carryRefund(_env(planned: 50, used: 50, carryover: false)), 0);
    });

    test('金额精度：退款经 round2，不带浮点漂移', () {
      expect(
        carryRefund(_env(planned: 33.33, used: 0.01, carryover: false)),
        33.32,
      );
    });
  });

  group('carryEnvelope 结转决定（单信封语义回归）', () {
    test('正结余 + 结转开 → 结余带入 planned', () {
      final r = carryEnvelope(_env(planned: 100, used: 30, carryover: true));
      expect(r.planned, 70);
      expect(r.used, 0);
    });

    test('正结余 + 结转关 → 账面清零（退款由 carryRefund 计入待规划）', () {
      final r = carryEnvelope(_env(planned: 100, used: 30, carryover: false));
      expect(r.planned, 0);
      expect(r.used, 0);
    });

    test('负缺口 + 结转开 → 缺口照带（透支欠账不能凭空消失）', () {
      final r = carryEnvelope(_env(planned: 50, used: 80, carryover: true));
      expect(r.planned, -30);
      expect(r.used, 0);
    });

    test('负缺口 + 结转关 → 缺口仍然带入（无论开关，不变量①透支必须看得见）', () {
      final r = carryEnvelope(_env(planned: 50, used: 80, carryover: false));
      expect(r.planned, -30);
      expect(r.used, 0);
    });

    test('零结余 → planned 归 0（开/关结果一致）', () {
      expect(carryEnvelope(_env(planned: 50, used: 50)).planned, 0);
      expect(
        carryEnvelope(_env(planned: 50, used: 50, carryover: false)).planned,
        0,
      );
    });

    test('金额精度：available 经 round2，带入值不带浮点漂移', () {
      final r = carryEnvelope(_env(planned: 33.33, used: 0.01));
      expect(r.planned, 33.32);
    });

    test('其余字段原样保留（身份/图标/颜色/结转开关不受结转影响）', () {
      final e = _env(id: 'e9', planned: 10, carryover: true);
      final r = carryEnvelope(e);
      expect(r.id, 'e9');
      expect(r.name, '信封e9');
      expect(r.carryover, true);
      expect(r.isArchived, false);
    });
  });

  group('periodType 存库字符串互转', () {
    test('四类型 name 往返一致', () {
      for (final t in BudgetPeriodType.values) {
        expect(periodTypeFromDb(periodTypeToDb(t)), t);
      }
    });

    test('未知/空值容错回退自然月（坏备份不崩）', () {
      expect(periodTypeFromDb('垃圾'), BudgetPeriodType.naturalMonth);
      expect(periodTypeFromDb(''), BudgetPeriodType.naturalMonth);
      expect(periodTypeFromDb(null), BudgetPeriodType.naturalMonth);
    });
  });

  group('switchRequiresCarryover 切换设置是否需结转（ADR-0013 §4）', () {
    test('自由类型切换永不结转（§5：自由只手动）', () {
      expect(
        switchRequiresCarryover(
          newType: BudgetPeriodType.free,
          storedStart: DateTime(2025, 1, 1),
          now: DateTime(2026, 9, 17),
        ),
        isFalse,
      );
    });

    test('起点未初始化只写不结转', () {
      expect(
        switchRequiresCarryover(
          newType: BudgetPeriodType.weekly,
          storedStart: null,
          now: DateTime(2026, 9, 17),
        ),
        isFalse,
      );
    });

    test('自然月 → 每周：起点从 9月1日 变 9月14日 → 需要结转', () {
      expect(
        switchRequiresCarryover(
          newType: BudgetPeriodType.weekly,
          storedStart: DateTime(2026, 9, 1),
          now: DateTime(2026, 9, 17),
        ),
        isTrue,
      );
    });

    test('自然月 → 自定义 1 号：起点同为 9月1日 → 不结转（无确认框）', () {
      expect(
        switchRequiresCarryover(
          newType: BudgetPeriodType.customStartDay,
          newStartDay: 1,
          storedStart: DateTime(2026, 9, 1),
          now: DateTime(2026, 9, 17),
        ),
        isFalse,
      );
    });

    test('修改起始日 15 → 20（9月17日当天）：起点回退到 8月20日 → 需要结转', () {
      expect(
        switchRequiresCarryover(
          newType: BudgetPeriodType.customStartDay,
          newStartDay: 20,
          storedStart: DateTime(2026, 9, 15),
          now: DateTime(2026, 9, 17),
        ),
        isTrue,
      );
    });
  });

  group('periodTypeShortLabel 我的页右侧值', () {
    test('四类型文案', () {
      expect(periodTypeShortLabel(BudgetPeriodType.naturalMonth, null), '自然月');
      expect(periodTypeShortLabel(BudgetPeriodType.weekly, null), '每周');
      expect(
        periodTypeShortLabel(BudgetPeriodType.customStartDay, 15),
        '每月 15 号',
      );
      expect(
        periodTypeShortLabel(BudgetPeriodType.customStartDay, null),
        '每月 1 号',
      );
      expect(periodTypeShortLabel(BudgetPeriodType.free, null), '自由周期');
    });
  });

  group('periodRangeLabel 首页日期行区间（DESIGN.md §3 v1.1.0）', () {
    test('自然月：9月1日 – 9月30日', () {
      expect(
        periodRangeLabel(
          type: BudgetPeriodType.naturalMonth,
          storedStart: DateTime(2026, 9, 1),
          now: DateTime(2026, 9, 17),
        ),
        '9月1日 – 9月30日',
      );
    });

    test('每周：9月14日 – 9月20日', () {
      expect(
        periodRangeLabel(
          type: BudgetPeriodType.weekly,
          storedStart: DateTime(2026, 9, 14),
          now: DateTime(2026, 9, 17),
        ),
        '9月14日 – 9月20日',
      );
    });

    test('自定义起始日：跨月区间 9月15日 – 10月14日', () {
      expect(
        periodRangeLabel(
          type: BudgetPeriodType.customStartDay,
          startDay: 15,
          storedStart: DateTime(2026, 9, 15),
          now: DateTime(2026, 9, 17),
        ),
        '9月15日 – 10月14日',
      );
    });

    test('自由周期：起点 – 至今', () {
      expect(
        periodRangeLabel(
          type: BudgetPeriodType.free,
          storedStart: DateTime(2026, 9, 10),
          now: DateTime(2026, 9, 17),
        ),
        '9月10日 – 至今',
      );
    });

    test('起点未存：按今天推算兜底（自然月 → 本月 1 日 – 月末）', () {
      expect(
        periodRangeLabel(
          type: BudgetPeriodType.naturalMonth,
          storedStart: null,
          now: DateTime(2026, 9, 17),
        ),
        '9月1日 – 9月30日',
      );
    });
  });

  group('periodOverviewLabel 我的页概览条前缀（DESIGN.md §9 v1.1.0）', () {
    test('自然月也用「本期还剩 N 天」（9月17日 → 13 天，按周期边界）', () {
      expect(
        periodOverviewLabel(
          type: BudgetPeriodType.naturalMonth,
          storedStart: DateTime(2026, 9, 1),
          now: DateTime(2026, 9, 17),
        ),
        '本期还剩 13 天',
      );
    });

    test('每周：本期还剩 N 天（周四距边界下周一 4 天，再减边界日 → 3 天）', () {
      expect(
        periodOverviewLabel(
          type: BudgetPeriodType.weekly,
          storedStart: DateTime(2026, 9, 14),
          now: DateTime(2026, 9, 17),
        ),
        '本期还剩 3 天',
      );
    });

    test('自定义起始日：本期还剩 N 天（9月17日距 10月15日 27 天）', () {
      expect(
        periodOverviewLabel(
          type: BudgetPeriodType.customStartDay,
          startDay: 15,
          storedStart: DateTime(2026, 9, 15),
          now: DateTime(2026, 9, 17),
        ),
        '本期还剩 27 天',
      );
    });

    test('本期最后一天 → 还剩 0 天（边界口径与 v1 一致）', () {
      expect(
        periodOverviewLabel(
          type: BudgetPeriodType.weekly,
          storedStart: DateTime(2026, 9, 14),
          now: DateTime(2026, 9, 20),
        ),
        '本期还剩 0 天',
      );
    });

    test('自由周期：本期已进行 N 天（9月10日起，9月17日 → 8 天，含今天）', () {
      expect(
        periodOverviewLabel(
          type: BudgetPeriodType.free,
          storedStart: DateTime(2026, 9, 10),
          now: DateTime(2026, 9, 17),
        ),
        '本期已进行 8 天',
      );
    });
  });

  group('deleteKeepsToBudgetNonNegative 类型矩阵（不变量⑦）', () {
    final state = LedgerState(
      toBudget: 100,
      envelopes: {
        'a': _env(id: 'a', planned: 200, used: 50),
        'b': _env(id: 'b', planned: 50, used: 10),
      },
    );

    test('支出 → 恒安全（不碰 toBudget）', () {
      expect(
        deleteKeepsToBudgetNonNegative(
          state,
          _txn(TxType.expense, 999, env: 'a'),
        ),
        isTrue,
      );
    });

    test('分配（待规划→信封）→ 恒安全（撤销它只会让 toBudget 变多）', () {
      expect(
        deleteKeepsToBudgetNonNegative(
          state,
          _txn(TxType.transfer, 80, from: kToBudget, to: 'a'),
        ),
        isTrue,
      );
    });

    test('信封 → 信封转移 → 恒安全（零和，不变量③）', () {
      expect(
        deleteKeepsToBudgetNonNegative(
          state,
          _txn(TxType.transfer, 30, from: 'a', to: 'b'),
        ),
        isTrue,
      );
    });

    test('收入：toBudget 够 → 安全；恰好清零 → 安全（边界 0）', () {
      expect(
        deleteKeepsToBudgetNonNegative(state, _txn(TxType.income, 100)),
        isTrue,
      );
      expect(
        deleteKeepsToBudgetNonNegative(state, _txn(TxType.income, 100.01)),
        isFalse,
      );
    });

    test('撤销分配（信封→待规划）：toBudget 不足 → 挡住', () {
      expect(
        deleteKeepsToBudgetNonNegative(
          state,
          _txn(TxType.transfer, 100.5, from: 'a', to: kToBudget),
        ),
        isFalse,
      );
      expect(
        deleteKeepsToBudgetNonNegative(
          state,
          _txn(TxType.transfer, 100, from: 'a', to: kToBudget),
        ),
        isTrue,
      );
    });

    test('toBudget = 0 的边界：撤销 0 元安全，撤销任何正数都挡住', () {
      final zero = LedgerState(toBudget: 0, envelopes: {});
      expect(
        deleteKeepsToBudgetNonNegative(zero, _txn(TxType.income, 0)),
        isTrue,
      );
      expect(
        deleteKeepsToBudgetNonNegative(zero, _txn(TxType.income, 0.01)),
        isFalse,
      );
    });

    test('金额精度：0.1 + 0.2 类浮点漂移不能误挡（round2 兜底）', () {
      // toBudget 由 0.1+0.2 累出来会是 0.30000000000000004，
      // 撤销 0.3 时若不 round2 会得到 1e-17 而被误判为负
      final drifted = LedgerState(toBudget: 0.1 + 0.2, envelopes: {});
      expect(
        deleteKeepsToBudgetNonNegative(drifted, _txn(TxType.income, 0.3)),
        isTrue,
      );
    });
  });
}
