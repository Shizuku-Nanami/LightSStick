import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ensemble_icons/remixicon.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/dfu_service.dart';
import '../services/ble_service.dart';
import '../models/led_color.dart';
import '../widgets/restore_progress_dialog.dart';

/// DFU 固件更新界面
class DfuScreen extends StatefulWidget {
  final String currentVersionStr;

  const DfuScreen({super.key, this.currentVersionStr = '2.0.0'});

  @override
  State<DfuScreen> createState() => _DfuScreenState();
}

class _DfuScreenState extends State<DfuScreen> {
  @override
  void initState() {
    super.initState();
    // 进入页面后自动检查更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });
  }

  Future<void> _checkForUpdate() async {
    final dfuService = context.read<DfuService>();
    // 将版本字符串转换为整数
    final versionInt = _versionStringToInt(widget.currentVersionStr);
    await dfuService.checkForUpdate(versionInt);
  }

  int _versionStringToInt(String version) {
    final parts = version.split('.');
    final major = int.tryParse(parts[0]) ?? 2;
    final minor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final patch = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
    return major * 10000 + minor * 100 + patch;
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();
    final dfu = context.watch<DfuService>();

    return Scaffold(
      appBar: AppBar(title: const Text('固件更新')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 设备信息卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Remix.bluetooth_fill,
                          color: ble.isConnected ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          ble.isConnected ? ble.displayDeviceName : '未连接设备',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '当前固件版本: ${ble.firmwareVersion}',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    if (dfu.latestFirmware != null)
                      Text(
                        '最新版本: v${dfu.latestFirmware!.version}',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 更新日志
            if (dfu.latestFirmware != null &&
                dfu.latestFirmware!.changelog.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '更新日志',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(dfu.latestFirmware!.changelog),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 24),

            // 进度指示器
            if (dfu.isUpdating || dfu.state == DfuState.complete)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // 状态图标
                      Icon(
                        _getStateIcon(dfu.state),
                        size: 64,
                        color: _getStateColor(dfu.state),
                      ),
                      const SizedBox(height: 16),

                      // 状态文字
                      Text(
                        dfu.statusMessage,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),

                      // 进度条
                      if (dfu.state != DfuState.complete &&
                          dfu.state != DfuState.error)
                        LinearProgressIndicator(
                          value: dfu.progress > 0 ? dfu.progress : null,
                          backgroundColor: Colors.grey.shade200,
                        ),
                      const SizedBox(height: 8),

                      // 百分比
                      if (dfu.state != DfuState.complete &&
                          dfu.state != DfuState.error)
                        Text(
                          '${(dfu.progress * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            // 错误信息
            if (dfu.state == DfuState.error)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Remix.error_warning_line, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dfu.errorMessage ?? '未知错误',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const Spacer(),

            // 操作按钮
            if (!dfu.isUpdating)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _checkForUpdate(),
                      icon: const Icon(Remix.refresh_line),
                      label: const Text('检查更新'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          ble.isConnected &&
                              dfu.latestFirmware != null &&
                              dfu.state != DfuState.error &&
                              _canUpdate()
                          ? () => _startDfu(ble)
                          : null,
                      icon: const Icon(Remix.upload_2_line),
                      label: Text(_canUpdate() ? '开始更新' : '已是最新'),
                    ),
                  ),
                ],
              ),

            // 取消按钮
            if (dfu.isUpdating)
              OutlinedButton.icon(
                onPressed: () {
                  // TODO: 取消 DFU
                },
                icon: const Icon(Remix.close_fill),
                label: const Text('取消更新'),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getStateIcon(DfuState state) {
    switch (state) {
      case DfuState.idle:
        return Remix.information_line;
      case DfuState.checking:
        return Remix.search_line;
      case DfuState.downloading:
        return Remix.download_2_line;
      case DfuState.enteringDfu:
        return Remix.settings_3_line;
      case DfuState.scanning:
        return Remix.search_line;
      case DfuState.updating:
        return Remix.upload_2_line;
      case DfuState.complete:
        return Remix.checkbox_circle_line;
      case DfuState.error:
        return Remix.error_warning_line;
    }
  }

  Color _getStateColor(DfuState state) {
    switch (state) {
      case DfuState.idle:
        return Colors.grey;
      case DfuState.checking:
      case DfuState.downloading:
      case DfuState.enteringDfu:
      case DfuState.scanning:
      case DfuState.updating:
        return Colors.blue;
      case DfuState.complete:
        return Colors.green;
      case DfuState.error:
        return Colors.red;
    }
  }

  Future<void> _startDfu(BleService ble) async {
    final dfuService = context.read<DfuService>();
    if (ble.device == null) return;

    // 1. 保存当前所有颜色和设备 ID
    try {
      final savedPresets = await ble.readAllPresets();
      debugPrint('Saved ${savedPresets.length} presets before DFU');

      // 保存到 SharedPreferences（DFU 后设备会重连）
      final prefs = await SharedPreferences.getInstance();
      final jsonList = savedPresets.map((c) => c.toJson()).toList();
      await prefs.setString('dfu_saved_presets', jsonEncode(jsonList));
      // 保存设备 ID 用于验证
      await prefs.setString('dfu_saved_device_id', ble.deviceId ?? '');
    } catch (e) {
      debugPrint('Failed to save presets: $e');
    }

    // 2. 执行 DFU
    final versionInt = _versionStringToInt(ble.firmwareVersion);
    await dfuService.startDfu(ble.device!, versionInt);

    // 3. DFU 完成后，等待设备重连并恢复颜色
    if (dfuService.state == DfuState.complete) {
      await _restoreColorsAfterDfu(ble);
    }
  }

  // DFU 完成后恢复颜色（带弹窗和验证）
  Future<void> _restoreColorsAfterDfu(BleService ble) async {
    final statusNotifier = ValueNotifier<String>('正在初始化...');
    final stateNotifier = ValueNotifier<RestoreState>(
      RestoreState.waitingRestart,
    );
    List<LedColor>? savedPresets;
    String savedDeviceId = '';

    // 读取保存的数据
    final prefs = await SharedPreferences.getInstance();
    final savedJson = prefs.getString('dfu_saved_presets');
    savedDeviceId = prefs.getString('dfu_saved_device_id') ?? '';

    if (savedJson != null && savedJson.isNotEmpty) {
      try {
        final jsonList = jsonDecode(savedJson) as List;
        savedPresets = jsonList.map((j) => LedColor.fromJson(j)).toList();
      } catch (e) {
        debugPrint('Failed to parse saved presets: $e');
      }
    }

    if (savedPresets == null || savedPresets.isEmpty) {
      debugPrint('No saved presets to restore');
      return;
    }

    // 显示进度弹窗
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => RestoreProgressDialog(
        statusNotifier: statusNotifier,
        stateNotifier: stateNotifier,
        onRetry: () {
          Navigator.pop(ctx);
          _restoreColorsAfterDfu(ble);
        },
        onCancel: () {
          Navigator.pop(ctx);
          prefs.remove('dfu_saved_presets');
          prefs.remove('dfu_saved_device_id');
        },
      ),
    );

    // 步骤 1：等待设备重启
    stateNotifier.value = RestoreState.waitingRestart;
    statusNotifier.value = '等待设备重启...';
    await Future.delayed(const Duration(seconds: 5));

    // 步骤 2：连接设备
    stateNotifier.value = RestoreState.connecting;
    statusNotifier.value = '正在连接设备...';

    bool connected = false;
    if (ble.isBound) {
      debugPrint('Connecting to bound device: ${ble.boundDeviceId}');
      await ble.connectToBoundDevice();
      connected = ble.isConnected;
    } else {
      // 等待被动重连（最多 30 秒）
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (ble.isConnected) {
          connected = true;
          break;
        }
        statusNotifier.value = '正在连接设备... (${i + 1}/30)';
      }
    }

    if (!connected) {
      stateNotifier.value = RestoreState.failed;
      statusNotifier.value = '连接设备超时，请检查设备是否正常工作';
      return;
    }

    // 验证设备 ID
    if (ble.deviceId != savedDeviceId) {
      stateNotifier.value = RestoreState.failed;
      statusNotifier.value = '连接的设备与保存的设备不匹配';
      return;
    }

    statusNotifier.value = '设备已连接，等待服务发现...';
    await Future.delayed(const Duration(seconds: 2));

    // 步骤 3：同步颜色数据
    stateNotifier.value = RestoreState.syncingColors;
    statusNotifier.value = '正在同步颜色数据...';

    try {
      final batch = <int, LedColor>{};
      for (int i = 0; i < savedPresets.length; i++) {
        batch[i] = savedPresets[i];
      }
      await ble.writePresetsBatch(batch);
      debugPrint('Colors written to device');
    } catch (e) {
      stateNotifier.value = RestoreState.failed;
      statusNotifier.value = '写入颜色失败: $e';
      return;
    }

    // 步骤 4：验证数据完整性
    stateNotifier.value = RestoreState.verifying;
    statusNotifier.value = '正在验证数据完整性...';

    await Future.delayed(const Duration(milliseconds: 500));

    try {
      final readBackPresets = await ble.readAllPresets();
      bool isMatch = true;
      int mismatchIndex = -1;

      for (int i = 0; i < savedPresets.length; i++) {
        if (savedPresets[i] != readBackPresets[i]) {
          isMatch = false;
          mismatchIndex = i;
          break;
        }
      }

      if (isMatch) {
        // 验证成功
        stateNotifier.value = RestoreState.completed;
        statusNotifier.value = '颜色恢复成功！';

        // 清除保存的数据
        await prefs.remove('dfu_saved_presets');
        await prefs.remove('dfu_saved_device_id');

        // 延迟关闭弹窗并显示成功提示
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.pop(context); // 关闭弹窗
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('颜色恢复成功'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // 验证失败
        stateNotifier.value = RestoreState.failed;
        statusNotifier.value = '颜色恢复失败（位置 $mismatchIndex 不匹配），请重试或手动设置';
      }
    } catch (e) {
      stateNotifier.value = RestoreState.failed;
      statusNotifier.value = '验证失败: $e';
    }
  }

  bool _canUpdate() {
    final dfu = context.read<DfuService>();
    if (dfu.latestFirmware == null) return false;
    final currentVersionInt = _versionStringToInt(widget.currentVersionStr);
    return dfu.latestFirmware!.versionInt > currentVersionInt;
  }
}
