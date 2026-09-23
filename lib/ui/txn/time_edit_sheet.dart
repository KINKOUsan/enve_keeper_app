// 交易时间编辑弹层（txn-time-edit 票 01 / ADR-0019）。
// 底部弹层 + 「日期 + 时分」滚轮：可补记到任意过去时刻（含跨月跨年），上限今天。
// 时间是档案标签：确定才交回，由调用方写库；不重算任何账，无确认框（与改描述同档）。
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// 打开改时间弹层。返回选定时刻（取消 / 下拉关闭 → null）。
/// [initial] 传入当前交易时间；上限固定为今天 23:59:59。
Future<DateTime?> showTimeEditSheet(
  BuildContext context, {
  required DateTime initial,
}) {
  final now = DateTime.now();
  // 上限今天：今天内任意时分可选，明天起不可选（ADR-0019）
  final max = DateTime(now.year, now.month, now.day, 23, 59, 59);
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: T.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(T.radiusSheet)),
    ),
    isScrollControlled: true,
    builder: (_) => _TimeEditSheet(initial: initial, max: max),
  );
}

class _TimeEditSheet extends StatefulWidget {
  const _TimeEditSheet({required this.initial, required this.max});

  final DateTime initial;
  final DateTime max;

  @override
  State<_TimeEditSheet> createState() => _TimeEditSheetState();
}

class _TimeEditSheetState extends State<_TimeEditSheet> {
  // 弹层内的草稿时刻：滚轮只改草稿，点「确定」才交回（与筛选面板同一交互语言）
  late DateTime _draft;

  @override
  void initState() {
    super.initState();
    // 设备时钟被改过等极端情况下，初始值也不能越过上限
    _draft = widget.initial.isAfter(widget.max) ? widget.max : widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题行（与筛选面板同款）
            Row(
              children: [
                const Text(
                  '改时间',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.pop(context),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 20, color: T.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 日期 + 时分滚轮：包在暖浅底圆角容器里，字色走 App 主题
            Container(
              decoration: BoxDecoration(
                color: T.surfaceSubtle,
                borderRadius: BorderRadius.circular(T.radiusKey),
              ),
              height: 216,
              child: CupertinoTheme(
                data: const CupertinoThemeData(
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: T.textPrimary,
                    ),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.dateAndTime,
                  use24hFormat: true,
                  initialDateTime: _draft,
                  // 不设下限：任意过去时刻都可补记（ADR-0019），上限由 maximumDate 把守
                  maximumDate: widget.max,
                  onDateTimeChanged: (v) => _draft = v,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // 底部操作：取消 + 确定（与筛选面板底部同款）
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      backgroundColor: T.surfaceSubtle,
                      foregroundColor: T.textSecondary,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(T.radiusKey),
                      ),
                    ),
                    child: const Text(
                      '取消',
                      style: TextStyle(
                        fontSize: T.typeBase,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, _draft),
                    style: TextButton.styleFrom(
                      backgroundColor: T.primary,
                      foregroundColor: T.textPrimary,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(T.radiusKey),
                      ),
                    ),
                    child: const Text(
                      '确定',
                      style: TextStyle(
                        fontSize: T.typeBase,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
