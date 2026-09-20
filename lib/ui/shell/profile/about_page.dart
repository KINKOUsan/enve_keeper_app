// 关于页（DESIGN.md §9 v1.1.0 · 票 07）。
// App 图标 + 名称「金打细算」+ 版本号（packageInfoProvider 动态读取）；
// 作者卡片 = GitHub 头像（本地资产 assets/avatar.jpg，票 10——GitHub CDN 国内
// 不可达，头像更换后手动重新下载覆盖资产文件）+ @KINKOUsan，点按卡片与
// 「意见反馈」均跳 GitHub 主页（url_launcher 外部浏览器）；「开源许可」= LicensePage。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../state/providers.dart';
import '../../../theme/tokens.dart';
import '../../keypad/keypad_flow.dart';

// 作者 GitHub 主页：「意见反馈」跳同一地址
const kGitHubHome = 'https://github.com/KINKOUsan';

// 作者头像资产（关于页作者卡，票 10 本地化）
const kAvatarAsset = 'assets/avatar.jpg';

/// 关于页：App 信息卡 + 作者卡 + 反馈/许可行
class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 版本号：与「我的」页同源的包信息
    final version = ref.watch(packageInfoProvider).value?.version;
    return Scaffold(
      backgroundColor: T.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // ── 页头：返回 + 标题 ──
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  _CircleButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    '关于',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // ── App 信息卡 ──
            _AppCard(version: version),
            const SizedBox(height: 14),
            // ── 作者卡片：整卡可点，跳 GitHub 主页 ──
            _AuthorCard(onTap: () => _openGitHubHome(context)),
            const SizedBox(height: 14),
            // ── 反馈 / 许可 ──
            _ActionsCard(
              onFeedback: () => _openGitHubHome(context),
              onLicenses: () => _showLicenses(context, version),
            ),
          ],
        ),
      ),
    );
  }

  // 打开 GitHub 主页（外部浏览器）；失败时 toast 提示手动访问
  Future<void> _openGitHubHome(BuildContext context) async {
    try {
      final ok = await launchUrl(
        Uri.parse(kGitHubHome),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        appToast(context, '没能打开浏览器，请手动访问 $kGitHubHome');
      }
    } catch (_) {
      // 设备无浏览器等平台异常：同样给出手动访问提示
      if (context.mounted) {
        appToast(context, '没能打开浏览器，请手动访问 $kGitHubHome');
      }
    }
  }

  // 打开 Flutter 开源许可页
  void _showLicenses(BuildContext context, String? version) {
    showLicensePage(
      context: context,
      applicationName: '金打细算',
      applicationVersion: version == null || version.isEmpty
          ? null
          : 'v$version',
      applicationIcon: _appIcon(size: 56, radius: 12),
    );
  }
}

// ── App 信息卡 ─────────────────────────────────

/// 白卡圆角 20：图标 72dp + 名称 17 SemiBold + 版本号 12 tertiary
class _AppCard extends StatelessWidget {
  const _AppCard({required this.version});

  // 包版本号（package_info_plus；读取中/失败时显示占位空串）
  final String? version;

  @override
  Widget build(BuildContext context) {
    // 局部拷贝以启用空值提升（公共字段不提升）
    final v = version;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F6B5738),
            offset: Offset(0, 3),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          _appIcon(size: 72, radius: 16),
          const SizedBox(height: 12),
          const Text(
            '金打细算',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            v == null || v.isEmpty ? '' : 'v$v',
            style: const TextStyle(fontSize: 12, color: T.textTertiary),
          ),
        ],
      ),
    );
  }
}

// App 图标：assets 里由 gen_icons.dart 产出的不透明方格，裁圆角显示
Widget _appIcon({required double size, required double radius}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: Image.asset(
      'assets/logo_icon.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
    ),
  );
}

// ── 作者卡片 ───────────────────────────────────

/// 白卡圆角 18：44dp 圆头像（本地资产，票 10）+ @KINKOUsan + 主页提示 + 右箭头
class _AuthorCard extends StatelessWidget {
  const _AuthorCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F6B5738),
            offset: Offset(0, 3),
            blurRadius: 10,
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _avatar(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      '@KINKOUsan',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'GitHub 主页',
                      style: TextStyle(fontSize: 12, color: T.textTertiary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.open_in_new, size: 16, color: T.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  // GitHub 头像：本地资产（v1.2.0 票 10——GitHub CDN 国内不可达，在线加载恒失败；
  // 头像更换后需手动重新下载覆盖资产文件）
  Widget _avatar() {
    return ClipOval(
      child: SizedBox(
        width: 44,
        height: 44,
        child: Image.asset(
          kAvatarAsset,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}

// ── 反馈 / 许可行卡 ─────────────────────────────

/// 白卡圆角 18、内边距 8；行高 48，样式对齐「我的」页分组卡
class _ActionsCard extends StatelessWidget {
  const _ActionsCard({required this.onFeedback, required this.onLicenses});

  // 「意见反馈」回调（跳作者主页）
  final VoidCallback onFeedback;

  // 「开源许可」回调（LicensePage）
  final VoidCallback onLicenses;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: T.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F6B5738),
            offset: Offset(0, 3),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          _ActionRow(
            icon: Icons.chat_bubble_outline,
            label: '意见反馈',
            onTap: onFeedback,
          ),
          _ActionRow(
            icon: Icons.menu_book_outlined,
            label: '开源许可',
            onTap: onLicenses,
          ),
        ],
      ),
    );
  }
}

// 一行：32dp 圆角图标块 + 名称 + 右箭头（样式对齐「我的」页分组卡）
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: T.surfaceSubtle,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: const Color(0xFF6E675C)),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: T.typeBase,
                fontWeight: FontWeight.w500,
                color: T.textPrimary,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, size: 16, color: T.textTertiary),
          ],
        ),
      ),
    );
  }
}

// ── 圆形返回按钮（对齐 period_settings_page 同款） ──

/// 36dp 圆形图标按钮
class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Material(
        color: T.surfaceSubtle,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Icon(icon, size: 16, color: T.textPrimary),
        ),
      ),
    );
  }
}
