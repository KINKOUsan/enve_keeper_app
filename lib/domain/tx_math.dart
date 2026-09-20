// 数字键盘的表达式求值 — 支持 + − × ÷ 与括号。
// 优先级：括号 > 乘除 > 加减，同级从左到右；结果保留 2 位小数。
import 'models.dart';

/// 对输入串求值。空串 / 无法解析 / 除零返回 null。
/// [raw] 中的全角减号 '−' 统一归一化为 '-'。
/// 注意：残缺表达式（如「2+」）返回 null——由 UI 层的「=」键负责
/// 去掉尾部无效符号后再求值（见 keypad_sheet 的 _normalize）。
double? evaluateExpression(String raw) {
  // 归一化：全角减号与乘除符号 → 解析器内部符号
  final s = raw.replaceAll('−', '-').replaceAll('×', '*').replaceAll('÷', '/');
  if (s.trim().isEmpty) return null;
  final parser = _ExprParser(s);
  final v = parser.parseExpression();
  if (v == null || !parser.atEnd) return null; // 有未消费的字符 = 语法错误
  if (v.isNaN || v.isInfinite) return null;
  return round2(v);
}

/// 递归下降解析器：
///   expression := term (('+' | '-') term)*
///   term       := factor (('*' | '/') factor)*
///   factor     := number | '(' expression ')'
class _ExprParser {
  _ExprParser(this.s);

  final String s;

  // 解析游标
  int pos = 0;

  bool get atEnd => pos >= s.length;

  // 跳过空白（容错）
  void _skipSpaces() {
    while (pos < s.length && s[pos] == ' ') {
      pos++;
    }
  }

  // 加减层：同级左结合
  double? parseExpression() {
    final first = _parseTerm();
    if (first == null) return null;
    var acc = first;
    while (true) {
      _skipSpaces();
      if (atEnd) return acc;
      final op = s[pos];
      if (op != '+' && op != '-') return acc;
      pos++;
      final right = _parseTerm();
      if (right == null) return null; // 「2+」这类残缺 → 失败
      acc = op == '+' ? acc + right : acc - right;
    }
  }

  // 乘除层：同级左结合；除零视为不可解析
  double? _parseTerm() {
    final first = _parseFactor();
    if (first == null) return null;
    var acc = first;
    while (true) {
      _skipSpaces();
      if (atEnd) return acc;
      final op = s[pos];
      if (op != '*' && op != '/') return acc;
      pos++;
      final right = _parseFactor();
      if (right == null) return null;
      if (op == '/' && right == 0) return null; // 除零不解析
      acc = op == '*' ? acc * right : acc / right;
    }
  }

  // 最内层：数字或括号子表达式
  double? _parseFactor() {
    _skipSpaces();
    if (atEnd) return null;
    final c = s[pos];
    // 括号子表达式
    if (c == '(') {
      pos++;
      final v = parseExpression();
      if (v == null) return null;
      _skipSpaces();
      if (atEnd || s[pos] != ')') return null; // 括号未闭合
      pos++;
      return v;
    }
    // 数字（含小数）
    final m = RegExp(r'\d+\.?\d*').matchAsPrefix(s, pos);
    if (m == null) return null;
    pos = m.end;
    return double.tryParse(m.group(0)!) ?? 0;
  }
}

/// 「=」按下前对表达式做修复：去掉尾部无效运算符、补齐未闭合的左括号。
/// 例：6+ → 6；10+5- → 10+5；(6+ → (6)。
String normalizeForEval(String expr) {
  var s = expr;
  // 关键步骤：循环去掉尾部的 + − × ÷
  while (s.isNotEmpty && '+-−×÷'.contains(s[s.length - 1])) {
    s = s.substring(0, s.length - 1);
  }
  // 关键步骤：补齐未闭合的左括号
  final open = '('.allMatches(s).length - ')'.allMatches(s).length;
  for (var i = 0; i < open; i++) {
    s += ')';
  }
  return s;
}

/// 键盘输入的追加规则：防止「1++」「1.2.3」「())」这类坏表达式。
/// 追加成功返回新串；不合法返回 null（调用方忽略本次按键）。
/// [key] ∈ 0-9 / . / + − × ÷ / ( )
String? appendKeyToExpr(String expr, String key) {
  final isEmpty = expr.isEmpty;
  final last = isEmpty ? '' : expr.substring(expr.length - 1);
  final lastIsOp = !isEmpty && '+-−×÷'.contains(last);
  final lastIsDigit = '0123456789'.contains(last);
  final lastIsOpen = last == '(';
  final lastIsClose = last == ')';
  final lastIsDot = last == '.';

  // 当前数字段（最近一个运算符/括号之后的部分），用于小数点与段首零判断
  final seg = expr.split(RegExp(r'[+\-−×÷()]')).last;

  // ── 数字 ──
  if (RegExp(r'^\d$').hasMatch(key)) {
    if (lastIsClose) return null; // ) 后接数字需显式 ×，忽略
    // 段是纯 0：用新数字替换这个 0（避免「05」）
    if (seg == '0') {
      return '${expr.substring(0, expr.length - 1)}$key';
    }
    return '$expr$key';
  }

  switch (key) {
    // ── 小数点 ──
    case '.':
      if (lastIsClose || lastIsDot) return null;
      if (seg.contains('.')) return null; // 一段只允许一个小数点
      if (isEmpty || lastIsOp || lastIsOpen) return '${expr}0.'; // 段首补 0
      return '$expr.';

    // ── 四则运算符 ──
    case '+':
    case '−':
    case '×':
    case '÷':
      if (lastIsOp) {
        // 关键步骤：连续运算符 → 替换最后一个
        return '${expr.substring(0, expr.length - 1)}$key';
      }
      if (isEmpty || lastIsOpen) return null; // 式首 / 左括号后不能跟运算符
      return '$expr$key';

    // ── 左括号：数字/右括号后自动补乘号（6(3+2) → 6×(3+2)）──
    case '(':
      if (lastIsDot) return null;
      if (lastIsDigit || lastIsClose) return '$expr×(';
      return '$expr(';

    // ── 右括号：必须有未闭合的左括号，且前面不能是运算符/左括号 ──
    case ')':
      final open = '('.allMatches(expr).length - ')'.allMatches(expr).length;
      if (open <= 0) return null;
      if (isEmpty || lastIsOp || lastIsOpen) return null;
      return '$expr$key';
  }
  return null;
}
