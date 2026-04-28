import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:nordic_dfu/nordic_dfu.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// DFU 状态枚举
enum DfuState {
  idle,
  checking,
  downloading,
  enteringDfu,
  scanning,
  updating,
  complete,
  error,
}

/// DFU 固件信息
class FirmwareInfo {
  final String version;
  final int versionInt;
  final String downloadUrl;
  final String changelog;

  const FirmwareInfo({
    required this.version,
    required this.versionInt,
    required this.downloadUrl,
    required this.changelog,
  });

  factory FirmwareInfo.fromJson(Map<String, dynamic> json) {
    final versionStr = json['version']?.toString() ?? '1.0.0';
    final parts = versionStr.split('.');
    final major = int.tryParse(parts[0]) ?? 1;
    final minor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final patch = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
    final versionInt = major * 10000 + minor * 100 + patch;

    return FirmwareInfo(
      version: versionStr,
      versionInt: versionInt,
      downloadUrl: json['download_url'] ?? '',
      changelog: json['changelog'] ?? '',
    );
  }

  bool isNewerThan(int currentVersionInt) {
    return versionInt > currentVersionInt;
  }
}

/// DFU 服务
class DfuService extends ChangeNotifier {
  static final Guid _dfuControlUuid = Guid(
    "0000fff7-0000-1000-8000-00805f9b34fb",
  );
  static final Guid _dfuServiceUuid = Guid(
    "0000fe59-0000-1000-8000-00805f9b34fb",
  );

  static const String _apiBaseUrl = 'https://control.hksstudio.work';
  static const String _versionEndpoint = '/hikari-stick/firmware/version';

  final Dio _dio = Dio();

  DfuState _state = DfuState.idle;
  double _progress = 0;
  String _statusMessage = '';
  FirmwareInfo? _latestFirmware;
  String? _errorMessage;

  DfuState get state => _state;
  double get progress => _progress;
  String get statusMessage => _statusMessage;
  FirmwareInfo? get latestFirmware => _latestFirmware;
  String? get errorMessage => _errorMessage;
  bool get isUpdating =>
      _state != DfuState.idle &&
      _state != DfuState.complete &&
      _state != DfuState.error;

  Future<bool> checkForUpdate(int currentVersionInt) async {
    _state = DfuState.checking;
    _statusMessage = '正在检查更新...';
    notifyListeners();

    try {
      final response = await _dio.get('$_apiBaseUrl$_versionEndpoint');

      Map<String, dynamic> data;
      if (response.data is String) {
        data = jsonDecode(response.data);
      } else {
        data = response.data;
      }

      _latestFirmware = FirmwareInfo.fromJson(data);

      if (_latestFirmware!.isNewerThan(currentVersionInt)) {
        _statusMessage = '发现新版本 v${_latestFirmware!.version}';
        _state = DfuState.idle;
        notifyListeners();
        return true;
      } else {
        _statusMessage = '已是最新版本';
        _state = DfuState.idle;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = '检查更新失败: $e';
      _statusMessage = _errorMessage!;
      _state = DfuState.error;
      notifyListeners();
      return false;
    }
  }

  Future<String?> _downloadFirmware(String url) async {
    _state = DfuState.downloading;
    _statusMessage = '正在下载固件...';
    _progress = 0;
    notifyListeners();

    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/firmware_dfu.zip';

      await _dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            _progress = received / total;
            _statusMessage = '下载中... ${(_progress * 100).toInt()}%';
            notifyListeners();
          }
        },
      );

      _statusMessage = '下载完成';
      _state = DfuState.idle;
      notifyListeners();
      return filePath;
    } catch (e) {
      _errorMessage = '下载失败: $e';
      _statusMessage = _errorMessage!;
      _state = DfuState.error;
      notifyListeners();
      return null;
    }
  }

  /// 发送 DFU 命令到设备
  Future<void> _sendDfuCommand(BluetoothDevice device) async {
    _state = DfuState.enteringDfu;
    _statusMessage = '正在进入 DFU 模式...';
    notifyListeners();

    try {
      final services = await device.discoverServices();

      for (final service in services) {
        for (final char in service.characteristics) {
          if (char.uuid == _dfuControlUuid) {
            await char.write([0x44, 0x46, 0x55], withoutResponse: true);

            _statusMessage = 'DFU 命令已发送，等待设备重启...';
            notifyListeners();

            // 等待设备进入 DFU 模式
            await Future.delayed(const Duration(seconds: 2));

            // 断开连接
            try {
              await device.disconnect();
            } catch (_) {}

            return;
          }
        }
      }

      _errorMessage = '未找到 DFU 特征值';
      _state = DfuState.error;
      notifyListeners();
    } catch (e) {
      _errorMessage = '发送 DFU 命令失败: $e';
      _state = DfuState.error;
      notifyListeners();
    }
  }

  /// 执行 DFU 更新
  Future<void> startDfu(BluetoothDevice device, int currentVersion) async {
    if (_latestFirmware == null) {
      final hasUpdate = await checkForUpdate(currentVersion);
      if (!hasUpdate) return;
    }

    final filePath = await _downloadFirmware(_latestFirmware!.downloadUrl);
    if (filePath == null) return;

    // 发送 DFU 命令
    await _sendDfuCommand(device);
    if (_state == DfuState.error) return;

    // 等待设备进入 DFU 模式
    _state = DfuState.scanning;
    _statusMessage = '正在等待 DfuTarg 设备...';
    notifyListeners();

    // 等待更长时间让 DfuTarg 广播（DfuTarg 需要时间启动）
    await Future.delayed(const Duration(seconds: 5));

    // 扫描 DfuTarg 设备获取实际地址
    String? dfuDeviceId;
    String? dfuDeviceName;

    try {
      _statusMessage = '正在扫描 DfuTarg...';
      notifyListeners();

      // 停止之前的扫描
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}

      // 开始新的扫描
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      // 等待扫描结果
      await Future.delayed(const Duration(seconds: 5));

      // 获取扫描结果
      final results = await FlutterBluePlus.scanResults.first;
      debugPrint('扫描到 ${results.length} 个设备:');

      for (final result in results) {
        final name = result.device.platformName;
        final address = result.device.remoteId.str;
        debugPrint('  设备: $address ($name)');

        if (name.contains('DfuTarg') ||
            name.contains('DFU') ||
            name.contains('Nordic')) {
          dfuDeviceId = address;
          dfuDeviceName = name;
          debugPrint('找到 DfuTarg: $dfuDeviceId ($name)');
          break;
        }
      }

      await FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('扫描失败: $e');
    }

    if (dfuDeviceId == null) {
      _errorMessage = '未找到 DfuTarg 设备，请手动使用 nRF Connect 进行 DFU';
      _state = DfuState.error;
      notifyListeners();
      return;
    }

    _statusMessage = '找到 DfuTarg: $dfuDeviceName，正在更新...';
    _state = DfuState.updating;
    _progress = 0;
    notifyListeners();

    try {
      debugPrint('开始 DFU，目标设备: $dfuDeviceId ($dfuDeviceName)');
      debugPrint('固件文件: $filePath');

      await NordicDfu().startDfu(
        dfuDeviceId,
        filePath,
        numberOfPackets: 10,
        enableUnsafeExperimentalButtonlessServiceInSecureDfu: true,
      );

      _state = DfuState.complete;
      _statusMessage = '固件更新完成！';
      notifyListeners();
    } catch (e) {
      _errorMessage = 'DFU 执行失败: $e';
      _state = DfuState.error;
      notifyListeners();
    }
  }

  void reset() {
    _state = DfuState.idle;
    _progress = 0;
    _statusMessage = '';
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _dio.close();
    super.dispose();
  }
}
