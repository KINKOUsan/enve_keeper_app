// 用户资料状态 — 装饰性数据（昵称/签名/头像路径），纯本地 shared_preferences 存储。
// 定位（profile-polish 票）：不进 .jx 备份（换机重设）、不进领域层、与账本无关。
// 头像文件拷贝在应用私有目录（避开相册 content:// 临时 URI 失效），替换时清理旧文件。
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'providers.dart';

// 用户资料快照（各字段空串 = 未设置，展示层负责回退默认文案）
class UserProfile {
  const UserProfile({
    this.nickname = '',
    this.signature = '',
    this.avatarPath = '',
  });

  // 昵称（≤12 字，UI 层限长）
  final String nickname;

  // 签名（≤30 字，UI 层限长）
  final String signature;

  // 头像文件的应用私有目录路径
  final String avatarPath;

  // 是否设置了自定义头像
  bool get hasAvatar => avatarPath.isNotEmpty;
}

// ── 资料控制器 ──────────────────────────────────

/// 资料读写：shared_preferences 三键（profile.nickname / signature / avatarPath）。
/// 装饰性数据不走 AppRepository，不参与余额与备份。
class ProfileController extends Notifier<UserProfile> {
  // 存储键
  static const _kNickname = 'profile.nickname';
  static const _kSignature = 'profile.signature';
  static const _kAvatarPath = 'profile.avatarPath';

  // 头像文件序号：同一毫秒内连续换头像也保证新路径不重复（260922 修复）
  static int _avatarSeq = 0;

  // 应用支持目录解析器（测试注入临时目录用，生产 = path_provider）
  ProfileController({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectory;

  @override
  UserProfile build() {
    final prefs = ref.watch(prefsProvider);
    return UserProfile(
      nickname: prefs.getString(_kNickname) ?? '',
      signature: prefs.getString(_kSignature) ?? '',
      avatarPath: prefs.getString(_kAvatarPath) ?? '',
    );
  }

  // 保存昵称与签名（传 null 的字段保持原值）
  Future<void> save({String? nickname, String? signature}) async {
    final prefs = ref.watch(prefsProvider);
    final next = UserProfile(
      nickname: nickname ?? state.nickname,
      signature: signature ?? state.signature,
      avatarPath: state.avatarPath,
    );
    state = next;
    await prefs.setString(_kNickname, next.nickname);
    await prefs.setString(_kSignature, next.signature);
  }

  // 从相册选取的源文件拷贝进应用私有目录并记录路径；替换成功后清理旧文件
  Future<void> setAvatarFrom(String sourcePath) async {
    await _commitAvatar((target) => File(sourcePath).copy(target));
  }

  // 裁剪结果字节直接写入私有目录（v1.3.0 票 04：换头像先裁剪）
  Future<void> setAvatarBytes(List<int> bytes) async {
    await _commitAvatar((target) => File(target).writeAsBytes(bytes));
  }

  // 头像落库共用段：唯一文件名 + 写入 + 更新状态与偏好 + 清理旧文件
  Future<void> _commitAvatar(
    Future<void> Function(String target) write,
  ) async {
    final docs = await _supportDirectory();
    final dir = Directory('${docs.path}/avatar');
    await dir.create(recursive: true);
    // 每次选取用新文件名（时间戳 + 序号），不复用固定 avatar.png：
    // 同名覆盖后路径不变，Flutter 图片缓存按路径命中旧图，
    // 表现为「选了图却不替换」「恢复默认后再选还是旧图」（260922 修复）
    final target =
        '${dir.path}/avatar-${DateTime.now().millisecondsSinceEpoch}'
        '-${_avatarSeq++}.png';
    await write(target);

    final old = state.avatarPath;
    state = UserProfile(
      nickname: state.nickname,
      signature: state.signature,
      avatarPath: target,
    );
    await ref.watch(prefsProvider).setString(_kAvatarPath, target);

    // 旧头像清理失败不影响新头像生效（best effort）
    if (old.isNotEmpty && old != target) {
      try {
        await File(old).delete();
      } on FileSystemException {
        // 文件不存在或被占用都无所谓
      }
    }
  }

  // 恢复默认头像：清路径并删除私有目录里的文件
  Future<void> clearAvatar() async {
    final old = state.avatarPath;
    state = UserProfile(nickname: state.nickname, signature: state.signature);
    await ref.watch(prefsProvider).setString(_kAvatarPath, '');
    if (old.isNotEmpty) {
      try {
        await File(old).delete();
      } on FileSystemException {
        // 文件不存在就算了
      }
    }
  }
}

// 用户资料 provider（全局，非账本级）
final profileProvider = NotifierProvider<ProfileController, UserProfile>(
  ProfileController.new,
);
