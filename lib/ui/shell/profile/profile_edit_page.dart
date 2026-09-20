// 编辑资料页 — 头像（相册选图→拷贝私有目录）+ 昵称 + 签名（profile-polish 票）。
// 装饰性数据：shared_preferences 存储，不进备份、不做云同步；长度限 12/30。
// 从「我的」页用户卡进入；保存后数据流自动刷新用户卡。
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/profile.dart';
import '../../../theme/tokens.dart';
import '../../copy.dart';
import '../../keypad/keypad_flow.dart';

/// 编辑资料页 — 头像、昵称、签名三段式表单；保存即落 shared_preferences。
class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  // 表单控制器：初值取当前资料（只在进入时读一次）
  late final TextEditingController _nicknameCtrl;
  late final TextEditingController _signatureCtrl;

  // 提交中标志：防重复保存
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider);
    _nicknameCtrl = TextEditingController(text: profile.nickname);
    _signatureCtrl = TextEditingController(text: profile.signature);
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _signatureCtrl.dispose();
    super.dispose();
  }

  // ── 动作 ──

  // 相册选图 → 拷贝进应用私有目录 → 更新资料
  Future<void> _pickAvatar() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = picked?.files.single.path;
    if (path == null || !mounted) return; // 用户取消
    try {
      await ref.read(profileProvider.notifier).setAvatarFrom(path);
      if (mounted) setState(() {}); // 刷新头像区
    } on FileSystemException {
      if (mounted) appToast(context, avatarPickFailedToast);
    }
  }

  // 恢复默认头像：清路径并删私有目录文件
  Future<void> _resetAvatar() async {
    await ref.read(profileProvider.notifier).clearAvatar();
    if (mounted) setState(() {});
  }

  // 保存昵称与签名，成功后提示并返回
  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    await ref
        .read(profileProvider.notifier)
        .save(
          nickname: _nicknameCtrl.text.trim(),
          signature: _signatureCtrl.text.trim(),
        );
    if (!mounted) return;
    appToast(context, profileSavedToast);
    Navigator.of(context).pop();
  }

  // ── 界面 ──

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(editProfileTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            // ── 头像区 ──
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickAvatar,
                    child: _Avatar(path: profile.avatarPath, size: 88),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    avatarChangeHint,
                    style: const TextStyle(
                      fontSize: T.typeXs,
                      color: T.textTertiary,
                    ),
                  ),
                  if (profile.hasAvatar)
                    TextButton(
                      onPressed: _resetAvatar,
                      child: const Text(resetAvatarLabel),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // ── 昵称 ──
            _LabeledField(
              label: nicknameLabel,
              hint: nicknameHint,
              controller: _nicknameCtrl,
              maxLength: 12,
            ),
            const SizedBox(height: 16),
            // ── 签名 ──
            _LabeledField(
              label: signatureLabel,
              hint: signatureHint,
              controller: _signatureCtrl,
              maxLength: 30,
            ),
            const SizedBox(height: 28),
            // ── 保存 ──
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: T.primary,
                  foregroundColor: T.textPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(T.radiusKey),
                  ),
                ),
                onPressed: _save,
                child: const Text(
                  '保存',
                  style: TextStyle(
                    fontSize: T.typeMd,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 小组件 ──────────────────────────────────

// 圆头像：有自定义图用 Image.file（读取失败回退默认），否则默认暖黄人像
class _Avatar extends StatelessWidget {
  const _Avatar({required this.path, required this.size});

  final String path;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: T.primarySoft,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: path.isEmpty
            ? const Icon(
                Icons.person_outline,
                size: 44,
                color: Color(0xFFB08A00),
              )
            : Image.file(
                File(path),
                width: size,
                height: size,
                fit: BoxFit.cover,
                // 头像文件被清理或损坏时回退默认人像，不崩页面
                errorBuilder: (_, _, _) => const Icon(
                  Icons.person_outline,
                  size: 44,
                  color: Color(0xFFB08A00),
                ),
              ),
      ),
    );
  }
}

// 带标签的输入框：13 标签 + 浅底圆角 12 输入区（与键盘描述栏同视觉）
class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.maxLength,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: T.typeSm,
            fontWeight: FontWeight.w600,
            color: T.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLength: maxLength,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: T.surfaceSubtle,
            counterStyle: const TextStyle(
              fontSize: T.typeXs,
              color: T.textTertiary,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}
