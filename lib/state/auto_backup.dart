// 自动备份控制器（v1.2.x 票 02 · ADR-0018 · DESIGN.md §19）：
// 开关默认开（shared_preferences 持久化；不进 .jx——恢复旧备份不翻转开关）。
// 数据变动（drift 按事务提交通知，见 repo.watchDataChanges）后静默 3 秒写
// 固定文件单文件覆盖；静默期内退到后台（onHide）立即落盘，最后一次变动不丢；
// 失败静默（无 toast），只更新状态行。手动备份（BackupStore/SAF）不受影响。
import 'dart:async';

import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auto_backup_store.dart';
import 'providers.dart';

// 开关的持久化键（.jx 只含 drift 表，此键天然不进备份内容）
const kAutoBackupEnabledKey = 'backup.autoEnabled';

/// 自动备份状态（备份页状态行显示用）：开关 + 最近一次结果 + 位置类别
class AutoBackupState {
  const AutoBackupState({
    this.enabled = true,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.publicTarget = false,
  });

  // 开关（默认开）
  final bool enabled;

  // 最近一次成功写入的时刻
  final DateTime? lastSuccessAt;

  // 最近一次失败的时刻（失败静默，只反映在状态行）
  final DateTime? lastFailureAt;

  // 最近一次成功写入是否落在公共目录（false = 沙盒，文案不承诺卸载可恢复）
  final bool publicTarget;

  // 最近一次结果是失败（失败晚于上次成功，或从未成功）
  bool get lastAttemptFailed =>
      lastFailureAt != null &&
      (lastSuccessAt == null || lastFailureAt!.isAfter(lastSuccessAt!));

  AutoBackupState copyWith({
    bool? enabled,
    DateTime? lastSuccessAt,
    DateTime? lastFailureAt,
    bool? publicTarget,
  }) {
    return AutoBackupState(
      enabled: enabled ?? this.enabled,
      lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      lastFailureAt: lastFailureAt ?? this.lastFailureAt,
      publicTarget: publicTarget ?? this.publicTarget,
    );
  }
}

/// 自动备份控制器：订阅数据变动信号 + 生命周期，驱动防抖落盘。
/// 生命周期归属：由 app.dart 的 _Boot watch 保持全应用存活。
class AutoBackupController extends Notifier<AutoBackupState> {
  // 防抖静默期（票 02：约 3 秒）
  static const debounce = Duration(seconds: 3);

  Timer? _timer;
  StreamSubscription<Set<TableUpdate>>? _sub;
  AppLifecycleListener? _lifecycle;
  bool _dirty = false;
  bool _writing = false;

  // 是否处于退到后台（hidden）状态：后台写入期间再有变动时不防抖、立即补写
  //（后台进程随时可能被冻结，等下一个 3 秒 = 丢最后一次变动）
  bool _backgrounded = false;

  bool _active = true;

  @override
  AutoBackupState build() {
    _active = true;
    _sub = ref
        .watch(repoProvider)
        .watchDataChanges()
        .listen((_) => _onDataChanged());
    _lifecycle = AppLifecycleListener(
      onHide: () {
        _backgrounded = true;
        flushNow();
      },
      onShow: () => _backgrounded = false,
    );
    ref.onDispose(() {
      _active = false;
      _timer?.cancel();
      _sub?.cancel();
      _lifecycle?.dispose();
    });
    return AutoBackupState(
      enabled: ref.watch(prefsProvider).getBool(kAutoBackupEnabledKey) ?? true,
    );
  }

  /// 开关（备份页调用）：关闭即取消排程、丢弃未落盘的脏标记
  Future<void> setEnabled(bool v) async {
    await ref.read(prefsProvider).setBool(kAutoBackupEnabledKey, v);
    if (v) {
      state = state.copyWith(enabled: true);
      return;
    }
    _timer?.cancel();
    _timer = null;
    _dirty = false;
    state = state.copyWith(enabled: false);
  }

  // 数据变动：开启状态记脏 + 重排 3 秒静默计时（连续变动合并成一次落盘）
  void _onDataChanged() {
    if (!state.enabled) return;
    _dirty = true;
    if (_writing) return; // 写入中：完成后按 _dirty 再排程
    _timer?.cancel();
    _timer = Timer(debounce, _writeNow);
  }

  /// 退到后台（onHide）立即落盘：静默期内的最后一次变动不能等
  void flushNow() {
    if (!state.enabled || !_dirty || _writing) return;
    _writeNow();
  }

  Future<void> _writeNow() async {
    _timer?.cancel();
    _timer = null;
    if (!_dirty || _writing || !_active) return;
    _dirty = false;
    _writing = true;
    final prev = state;
    try {
      final repo = ref.read(repoProvider);
      final json = await repo.exportBackupJson();
      final result = await ref.read(autoBackupStoreProvider).write(json);
      if (!_active) return;
      state = AutoBackupState(
        enabled: prev.enabled,
        lastSuccessAt: DateTime.now(),
        publicTarget: result.publicTarget,
      );
    } on Exception {
      if (!_active) return;
      // 失败静默（只捕 Exception：Error 是编程缺陷，不该被静默吞掉）：
      // 保留上次成功时间与位置类别，状态行反映最近一次失败
      state = prev.copyWith(lastFailureAt: DateTime.now());
    } finally {
      _writing = false;
      // 写入期间又有变动：前台再排一轮静默；后台不防抖，立即补写
      if (_active && _dirty && state.enabled) {
        if (_backgrounded) {
          _writeNow();
        } else {
          _timer = Timer(debounce, _writeNow);
        }
      }
    }
  }
}

// 自动备份写入器（测试可覆写）
final autoBackupStoreProvider = Provider<AutoBackupStore>(
  (ref) => AutoBackupStore(),
);

// 自动备份状态（_Boot watch 常驻；备份页状态行与开关读这里）
final autoBackupProvider =
    NotifierProvider<AutoBackupController, AutoBackupState>(
      AutoBackupController.new,
    );
