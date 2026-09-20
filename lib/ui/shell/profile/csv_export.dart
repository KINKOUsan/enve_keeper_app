// CSV 导出 — 当前激活账本的全部流水（ADR-0011：CSV 只含当前账本，与备份区分）。
// UTF-8 带 BOM（Excel 直接打开不乱码）；列：日期 / 信封 / 类型 / 金额 / 描述。
// 通过系统保存框（SAF）让用户选位置，无需存储权限。
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../domain/models.dart';
import '../../../state/providers.dart';
import '../../copy.dart';

// 统一提示（跨 async 前取好 messenger 由调用方保证）
void _toast(ScaffoldMessengerState messenger, String text) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(milliseconds: 2200),
      ),
    );
}

/// 导出当前账本流水为 CSV。供「我的 · 导出 CSV」调用。
Future<void> exportCsv(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final txns = ref.read(txnsProvider).value ?? const <Txn>[];
  final envelopes = ref.read(allEnvelopesProvider).value ?? const <Envelope>[];
  if (txns.isEmpty) {
    _toast(messenger, toastCsvEmpty);
    return;
  }
  _toast(messenger, toastExporting);

  // 信封名解析用全量集（含停用——停用信封的历史流水也要能对上名字）
  final names = {for (final e in envelopes) e.id: e.name};
  String nameOf(String? id) {
    if (id == null) return '外界';
    if (id == kToBudget) return '待规划';
    return names[id] ?? '已停用的信封';
  }

  String typeLabel(TxType t) => switch (t) {
    TxType.expense => '支出',
    TxType.income => '收入',
    TxType.transfer => '转移',
    TxType.refund => '结转退回',
  };

  // 金额裸数字（不带千分位/符号），方便表格软件做统计
  String amount(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  final lines = <String>['日期,信封,类型,金额,描述'];
  for (final t in txns.reversed) {
    // 旧→新，便于直接看时间线
    final when = DateFormat('yyyy-MM-dd HH:mm').format(t.at);
    final env = switch (t.type) {
      TxType.expense => nameOf(t.envelopeId),
      TxType.income => '待规划',
      TxType.transfer => '${nameOf(t.fromId)} → ${nameOf(t.toId)}',
      // 工单规格：结转退回渲染为「信封 → 待规划（结转退回）」
      TxType.refund =>
        '${nameOf(t.fromId)} → ${nameOf(t.toId)}（结转退回）',
    };
    lines.add(
      [
        when,
        env,
        typeLabel(t.type),
        amount(t.amount),
        t.description,
      ].map(_escape).join(','),
    );
  }

  // 关键步骤：UTF-8 BOM 前缀——Excel（尤其中文区）识别编码靠它
  final bytes = utf8.encode('\uFEFF${lines.join('\r\n')}');
  final stamp = DateFormat('yyyyMMdd').format(DateTime.now());
  final path = await FilePicker.platform.saveFile(
    fileName: '金打细算-流水-$stamp.csv',
    bytes: bytes,
  );
  if (path == null) {
    _toast(messenger, toastExportCancelled);
    return;
  }
  // 关键步骤：移动端 saveFile(bytes:) 已由插件经 SAF 写完文件，返回的是文档
  // URI（content:// 或 /document/raw:… 形式），不能再用 dart:io 打开写；
  // 桌面端只返回目标路径，需要我们自己写。
  if (Platform.isAndroid || Platform.isIOS) {
    _toast(messenger, toastExportedToPicker);
  } else {
    await File(path).writeAsBytes(bytes, flush: true);
    _toast(messenger, toastExportedToPath(path));
  }
}

// CSV 字段转义：含逗号/引号/换行的字段加引号，内部引号翻倍
String _escape(String s) =>
    (s.contains(',') || s.contains('"') || s.contains('\n'))
    ? '"${s.replaceAll('"', '""')}"'
    : s;
