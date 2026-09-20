// tx_math 单测 — 求值（含括号/乘除优先/除零/残缺表达式）与键盘输入规则。
import 'package:flutter_test/flutter_test.dart';
import 'package:enve_keeper_app/domain/tx_math.dart';

void main() {
  group('evaluateExpression 求值', () {
    test('纯数字', () {
      expect(evaluateExpression('128'), 128);
      expect(evaluateExpression('12.5'), 12.5);
    });

    test('加减从左到右', () {
      expect(evaluateExpression('10+5'), 15);
      expect(evaluateExpression('10−5'), 5); // 全角减号
      expect(evaluateExpression('10-5+3'), 8);
    });

    test('乘除优先', () {
      expect(evaluateExpression('2+3×4'), 14);
      expect(evaluateExpression('10÷2−3'), 2);
      expect(evaluateExpression('2×3×4'), 24);
    });

    test('括号最优先', () {
      expect(evaluateExpression('(2+3)×4'), 20);
      expect(evaluateExpression('2×(3+4)'), 14);
      expect(evaluateExpression('((2+3))'), 5);
    });

    test('结果保留 2 位小数', () {
      expect(evaluateExpression('10÷4'), 2.5);
      expect(evaluateExpression('1÷3'), 0.33);
    });

    test('非法输入返回 null', () {
      expect(evaluateExpression(''), isNull);
      expect(evaluateExpression('2+'), isNull); // 残缺：由 = 键修复后求值
      expect(evaluateExpression('8÷0'), isNull); // 除零
      expect(evaluateExpression('(2+3'), isNull); // 括号未闭合
      expect(evaluateExpression('×3'), isNull); // 运算符开头
    });
  });

  group('normalizeForEval 修复', () {
    test('用户场景：6+ → 6', () {
      expect(evaluateExpression(normalizeForEval('6+')), 6);
    });

    test('用户场景：10+5- → 15', () {
      expect(evaluateExpression(normalizeForEval('10+5-')), 15);
    });

    test('补齐未闭合括号：(6+ → (6) → 6', () {
      expect(evaluateExpression(normalizeForEval('(6+')), 6);
    });

    test('混合残缺：((10÷2)- → 5', () {
      expect(evaluateExpression(normalizeForEval('((10÷2)-')), 5);
    });
  });

  group('appendKeyToExpr 输入规则', () {
    test('连续运算符 → 替换', () {
      expect(appendKeyToExpr('6+', '−'), '6−');
      expect(appendKeyToExpr('6×', '÷'), '6÷');
    });

    test('式首运算符被拒', () {
      expect(appendKeyToExpr('', '+'), isNull);
      expect(appendKeyToExpr('(', '×'), isNull);
    });

    test('段内小数点防重', () {
      expect(appendKeyToExpr('1.5', '.'), isNull);
      expect(appendKeyToExpr('', '.'), '0.');
      expect(appendKeyToExpr('6+', '.'), '6+0.');
    });

    test('段首零替换', () {
      expect(appendKeyToExpr('0', '5'), '5');
      expect(appendKeyToExpr('1+0', '3'), '1+3');
      expect(appendKeyToExpr('10', '0'), '100'); // 非「段首零」正常追加
    });

    test('智能左括号：数字后自动补 ×', () {
      expect(appendKeyToExpr('6', '('), '6×(');
      expect(appendKeyToExpr('6×', '('), '6×(');
    });

    test('右括号必须有未闭合的左括号', () {
      expect(appendKeyToExpr('6', ')'), isNull);
      expect(appendKeyToExpr('(6', ')'), '(6)');
      expect(appendKeyToExpr('(6+', ')'), isNull); // 运算符后不能闭合
    });
  });
}
