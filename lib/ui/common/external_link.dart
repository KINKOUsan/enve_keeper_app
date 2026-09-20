// 外链打开 — 统一走外部浏览器，打不开时 toast 提示手动访问。
// 关于页（GitHub 主页）与使用说明页（sspai 文章）共用（DESIGN.md §9）。
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../copy.dart';
import '../keypad/keypad_flow.dart' show appToast;

/// 用外部浏览器打开 [url]；平台异常（无浏览器等）或被拒绝时，
/// toast 给出可手动访问的兜底文案（陷阱清单：跨 async 后先查 mounted）
Future<void> openExternalLink(BuildContext context, String url) async {
  try {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      appToast(context, linkOpenFailedToast(url));
    }
  } catch (_) {
    if (context.mounted) {
      appToast(context, linkOpenFailedToast(url));
    }
  }
}
