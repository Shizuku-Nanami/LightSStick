import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/led_color.dart';

/// 自定义设备发现结果
class DiscoveredBleDevice {
  final String id;
  final String name;
  final int rssi;
  final BluetoothDevice? device;

  const DiscoveredBleDevice({
    required this.id,
    required this.name,
    this.rssi = -100,
    this.device,
  });

  String displayName(Map<String, String> customNames) {
    if (customNames.containsKey(id)) return customNames[id]!;
    return name;
  }
}

/// BLE 服务（基于 flutter_blue_plus）
class BleService extends ChangeNotifier {
  // ── UUID 常量（与固件一致）───────────────────────────────
  static final Guid _serviceUuid = Guid("0000fff0-0000-1000-8000-00805f9b34fb");
  static final Guid _colorWriteUuid = Guid(
    "0000fff1-0000-1000-8000-00805f9b34fb",
  );
  static final Guid _colorReadUuid = Guid(
    "0000fff2-0000-1000-8000-00805f9b34fb",
  );
  static final Guid _batteryReadUuid = Guid(
    "0000fff3-0000-1000-8000-00805f9b34fb",
  );
  static final Guid _presetWriteUuid = Guid(
    "0000fff4-0000-1000-8000-00805f9b34fb",
  );
  static final Guid _presetReadUuid = Guid(
    "0000fff5-0000-1000-8000-00805f9b34fb",
  );
  static final Guid _versionReadUuid = Guid(
    "0000fff6-0000-1000-8000-00805f9b34fb",
  );
  static final Guid _brightnessUuid = Guid(
    "0000fff8-0000-1000-8000-00805f9b34fb",
  );
  static final Guid _strobeUuid = Guid(
    "0000fff9-0000-1000-8000-00805f9b34fb",
  );

  static const String _customNamesKey = 'ble_custom_names';
  static const String _boundDeviceKey = 'bound_device';

  // ── 状态 ─────────────────────────────────────────────
  BluetoothDevice? _device;
  BluetoothCharacteristic? _colorWriteChar;
  BluetoothCharacteristic? _colorReadChar;
  BluetoothCharacteristic? _batteryReadChar;
  BluetoothCharacteristic? _presetWriteChar;
  BluetoothCharacteristic? _presetReadChar;
  BluetoothCharacteristic? _versionReadChar;

  bool _isConnected = false;
  bool _isScanning = false;
  bool _isLoading = false; // 扫描并连接的加载状态
  String? _deviceId;
  String _deviceName = '';
  String _firmwareVersion = '未知';
  LedColor _currentColor = const LedColor.off();
  int _batteryLevel = -1;
  final List<DiscoveredBleDevice> _discoveredDevices = [];
  final Map<String, String> _customNames = {};
  String? _boundDeviceId; // 绑定设备 ID
  String _boundDeviceName = ''; // 绑定设备名称
  BluetoothCharacteristic? _brightnessChar;
  BluetoothCharacteristic? _strobeChar;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _colorNotifySub;

  // ── Getters ──────────────────────────────────────────
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  bool get isLoading => _isLoading;
  String? get deviceId => _deviceId;
  String get deviceName => _deviceName;
  String get displayDeviceName => _customNames[_deviceId] ?? _deviceName;
  String get firmwareVersion => _firmwareVersion;
  LedColor get currentColor => _currentColor;
  int get batteryLevel => _batteryLevel;
  BluetoothDevice? get device => _device;
  List<DiscoveredBleDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);
  Map<String, String> get customNames => Map.unmodifiable(_customNames);
  String? get boundDeviceId => _boundDeviceId;
  String get boundDeviceName => _boundDeviceName;
  bool get isBound => _boundDeviceId != null;
  bool get isCurrentDeviceBound => _deviceId == _boundDeviceId;

  BleService() {
    _loadCustomNames();
    _loadBoundDevice();
  }

  // ── 持久化自定义名称 ─────────────────────────────────
  Future<void> _loadCustomNames() async {
    final prefs = await SharedPreferences.getInstance();
    final namesJson = prefs.getStringList(_customNamesKey) ?? [];
    for (final entry in namesJson) {
      final parts = entry.split('|');
      if (parts.length == 2) {
        _customNames[parts[0]] = parts[1];
      }
    }
    notifyListeners();
  }

  Future<void> _saveCustomNames() async {
    final prefs = await SharedPreferences.getInstance();
    final namesJson = _customNames.entries
        .map((e) => '${e.key}|${e.value}')
        .toList();
    await prefs.setStringList(_customNamesKey, namesJson);
  }

  void setCustomName(String deviceId, String name) {
    if (name.isEmpty) {
      _customNames.remove(deviceId);
    } else {
      _customNames[deviceId] = name;
    }
    _saveCustomNames();
    notifyListeners();
  }

  // ── 设备绑定 ──────────────────────────────────────────
  final Completer<void> _boundDeviceLoaded = Completer<void>();
  bool get isBoundDeviceLoaded => _boundDeviceLoaded.isCompleted;

  Future<void> _loadBoundDevice() async {
    final prefs = await SharedPreferences.getInstance();
    final boundJson = prefs.getString(_boundDeviceKey);
    if (boundJson != null && boundJson.isNotEmpty) {
      try {
        final data = jsonDecode(boundJson);
        _boundDeviceId = data['id'];
        _boundDeviceName = data['name'] ?? '';
        debugPrint('Loaded bound device: $_boundDeviceId ($_boundDeviceName)');
      } catch (e) {
        debugPrint('Failed to load bound device: $e');
      }
    }
    if (!_boundDeviceLoaded.isCompleted) {
      _boundDeviceLoaded.complete();
    }
  }

  /// 等待绑定设备加载完成
  Future<void> waitForBoundDeviceLoaded() async {
    await _boundDeviceLoaded.future;
  }

  Future<void> _saveBoundDevice() async {
    final prefs = await SharedPreferences.getInstance();
    if (_boundDeviceId != null) {
      await prefs.setString(
        _boundDeviceKey,
        jsonEncode({'id': _boundDeviceId, 'name': _boundDeviceName}),
      );
    } else {
      await prefs.remove(_boundDeviceKey);
    }
  }

  void bindDevice(String deviceId, String deviceName) {
    _boundDeviceId = deviceId;
    _boundDeviceName = deviceName;
    _saveBoundDevice();
    notifyListeners();
    debugPrint('Device bound: $deviceId ($deviceName)');
  }

  void unbindDevice() {
    _boundDeviceId = null;
    _boundDeviceName = '';
    _saveBoundDevice();
    notifyListeners();
    debugPrint('Device unbound');
  }

  // ── 权限 ─────────────────────────────────────────────
  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      return statuses.values.every((s) => s.isGranted);
    }
    if (Platform.isIOS) {
      final status = await Permission.bluetooth.request();
      return status.isGranted;
    }
    return true;
  }

  // ── 扫描 ─────────────────────────────────────────────
  Future<void> startScan() async {
    if (_isConnected || _isScanning) return;

    final hasPermission = await _requestPermissions();
    if (!hasPermission) return;

    _isScanning = true;
    _discoveredDevices.clear();
    notifyListeners();

    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      withServices: [_serviceUuid],
    );

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        if (result.device.platformName.startsWith('HikariStick')) {
          final existing = _discoveredDevices.indexWhere(
            (d) => d.id == result.device.remoteId.str,
          );
          final device = DiscoveredBleDevice(
            id: result.device.remoteId.str,
            name: result.device.platformName,
            rssi: result.rssi,
            device: result.device,
          );
          if (existing >= 0) {
            _discoveredDevices[existing] = device;
          } else {
            _discoveredDevices.add(device);
          }
          notifyListeners();
        }
      }
    });

    // 扫描结束 - 只更新扫描状态，不重置加载状态
    FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning && _isScanning) {
        _isScanning = false;
        notifyListeners();
      }
    });
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanSub?.cancel();
    _isScanning = false;
    _isLoading = false;
    notifyListeners();
  }

  // ── 连接 ─────────────────────────────────────────────
  Future<void> connectToDevice(String deviceId) async {
    if (_isConnected) await disconnect();

    final deviceInfo = _discoveredDevices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => DiscoveredBleDevice(id: deviceId, name: 'HikariStick'),
    );

    _deviceName = deviceInfo.name;
    _deviceId = deviceId;
    _device = deviceInfo.device;
    _isScanning = false;
    _isLoading = false;
    _scanSub?.cancel();
    notifyListeners();

    if (_device == null) return;

    try {
      await FlutterBluePlus.stopScan();
      await _device!.connect(timeout: const Duration(seconds: 15));

      // 监听连接状态
      _connSub = _device!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.connected) {
          _isConnected = true;
          notifyListeners();
          _discoverServices();
        } else if (state == BluetoothConnectionState.disconnected) {
          _isConnected = false;
          _deviceId = null;
          _deviceName = '';
          _clearCharacteristics();
          notifyListeners();
        }
      });
    } catch (e) {
      _isConnected = false;
      _deviceId = null;
      _deviceName = '';
      _clearCharacteristics();
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _connSub?.cancel();
    _connSub = null;
    _colorNotifySub?.cancel();
    _colorNotifySub = null;
    if (_device != null) {
      try {
        await _device!.disconnect();
      } catch (_) {}
    }
    _isConnected = false;
    _deviceId = null;
    _deviceName = '';
    _clearCharacteristics();
    notifyListeners();
  }

  void _clearCharacteristics() {
    _colorWriteChar = null;
    _colorReadChar = null;
    _batteryReadChar = null;
    _presetWriteChar = null;
    _presetReadChar = null;
    _versionReadChar = null;
    _brightnessChar = null;
    _strobeChar = null;
    _colorNotifySub?.cancel();
    _colorNotifySub = null;
    _batteryLevel = -1;
    _firmwareVersion = '未知';
    _currentColor = const LedColor.off();
  }

  // ── 发现服务和特征值 ─────────────────────────────────
  Future<void> _discoverServices() async {
    if (_device == null) return;

    try {
      final services = await _device!.discoverServices();

      for (final service in services) {
        if (service.uuid == _serviceUuid) {
          for (final char in service.characteristics) {
            if (char.uuid == _colorWriteUuid) {
              _colorWriteChar = char;
            } else if (char.uuid == _colorReadUuid) {
              _colorReadChar = char;
            } else if (char.uuid == _batteryReadUuid) {
              _batteryReadChar = char;
            } else if (char.uuid == _presetWriteUuid) {
              _presetWriteChar = char;
            } else if (char.uuid == _presetReadUuid) {
              _presetReadChar = char;
            } else if (char.uuid == _versionReadUuid) {
              _versionReadChar = char;
            } else if (char.uuid == _brightnessUuid) {
              _brightnessChar = char;
            } else if (char.uuid == _strobeUuid) {
              _strobeChar = char;
            }
          }
          break;
        }
      }

      // 订阅 FFF2 通知（固件按钮切换颜色时自动通知 APP）
      await _subscribeToColorNotifications();

      // 读取初始状态
      await _readInitialState();
    } catch (e) {
      debugPrint('Service discovery failed: $e');
    }
  }

  // ── 订阅 FFF2 颜色通知 ──────────────────────────────
  Future<void> _subscribeToColorNotifications() async {
    if (_colorReadChar == null) return;

    try {
      // 检查是否支持通知
      if (_colorReadChar!.properties.notify) {
        await _colorReadChar!.setNotifyValue(true);
        _colorNotifySub = _colorReadChar!.onValueReceived.listen((value) {
          if (value.length >= 4) {
            _currentColor = LedColor.fromBytes(value);
            debugPrint(
              'Color notification received: R=${value[0]} G=${value[1]} B=${value[2]} W=${value[3]}',
            );
            notifyListeners();
          }
        });
        debugPrint('Subscribed to color notifications');
      }
    } catch (e) {
      debugPrint('Failed to subscribe to color notifications: $e');
    }
  }

  Future<void> _readInitialState() async {
    for (int i = 0; i < 3; i++) {
      if (!_isConnected) return;

      try {
        await readCurrentColor();
        await readBatteryLevel();
        await readFirmwareVersion();

        // 自动同步所有预设颜色
        await _syncPresetsFromDevice();
        return;
      } catch (e) {
        if (i < 2) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
  }

  // ── 从设备同步所有预设颜色 ──────────────────────────────
  Future<void> _syncPresetsFromDevice() async {
    try {
      final presets = await readAllPresets();
      // 保存到 SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final jsonList = presets.map((c) => c.toJson()).toList();
      await prefs.setString('local_presets', jsonEncode(jsonList));
      debugPrint('Presets synced from device: ${presets.length} colors');
    } catch (e) {
      debugPrint('Failed to sync presets: $e');
    }
  }

  // ── FFF6: 读取固件版本 ─────────────────────────────────
  Future<String> readFirmwareVersion() async {
    if (_versionReadChar == null) return '未知';
    try {
      final bytes = await _versionReadChar!.read();
      // 只保留数字和小数点，过滤掉所有其他字符
      final version = String.fromCharCodes(
        bytes,
      ).replaceAll(RegExp(r'[^0-9.]'), '').trim();
      _firmwareVersion = version.isNotEmpty ? 'v$version' : '未知';
      notifyListeners();
      return _firmwareVersion;
    } catch (e) {
      return '未知';
    }
  }

  // ── FFF1: 写入颜色到设备 ────────────────────────────────
  Future<void> writeColor(LedColor color) async {
    if (_colorWriteChar == null) return;
    try {
      // 使用 Write Without Response 提升快速调色响应速度
      if (_colorWriteChar!.properties.writeWithoutResponse) {
        await _colorWriteChar!.write(color.toBytes(), withoutResponse: true);
      } else {
        await _colorWriteChar!.write(color.toBytes(), withoutResponse: false);
      }
      _currentColor = color;
      notifyListeners();
    } catch (e) {
      debugPrint('Write color failed: $e');
    }
  }

  // ── FFF2: 读取当前颜色 ─────────────────────────────────
  Future<LedColor> readCurrentColor() async {
    if (_colorReadChar == null) return const LedColor.off();
    try {
      final bytes = await _colorReadChar!.read();
      _currentColor = LedColor.fromBytes(bytes);
      notifyListeners();
      return _currentColor;
    } catch (e) {
      return const LedColor.off();
    }
  }

  // ── FFF3: 读取电池电量 ─────────────────────────────────
  Future<int> readBatteryLevel() async {
    if (_batteryReadChar == null) return -1;
    try {
      final bytes = await _batteryReadChar!.read();
      _batteryLevel = bytes.isNotEmpty ? bytes[0] : -1;
      notifyListeners();
      return _batteryLevel;
    } catch (e) {
      return -1;
    }
  }

  // ── FFF4: 写入预设（单条） ──────────────────────────────
  Future<void> writePreset(int index, LedColor color) async {
    if (_presetWriteChar == null) return;
    try {
      final data = [index, ...color.toBytes()];
      await _presetWriteChar!.write(data, withoutResponse: false);
    } catch (e) {
      debugPrint('Write preset failed: $e');
    }
  }

  // ── FFF4: 批量写入预设（分块处理）──────────────────────────
  Future<void> writePresetsBatch(Map<int, LedColor> presets) async {
    if (_presetWriteChar == null || presets.isEmpty) return;

    final entries = presets.entries.toList();
    const chunkSize = 3; // 每块最多 3 个预设（15 字节）

    for (int i = 0; i < entries.length; i += chunkSize) {
      final chunk = entries.skip(i).take(chunkSize);
      final data = <int>[];
      for (final entry in chunk) {
        data.add(entry.key);
        data.addAll(entry.value.toBytes());
      }
      try {
        await _presetWriteChar!.write(data, withoutResponse: false);
        if (i + chunkSize < entries.length) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      } catch (e) {
        debugPrint('Write preset batch failed: $e');
      }
    }
  }

  // ── FFF5: 读取全部 50 个预设 ────────────────────────────
  Future<List<LedColor>> readAllPresets() async {
    if (_presetReadChar == null) return List.filled(50, const LedColor.off());
    try {
      final bytes = await _presetReadChar!.read();
      if (bytes.length < 200) {
        return List.filled(50, const LedColor.off());
      }
      final presets = <LedColor>[];
      for (int i = 0; i < 50; i++) {
        final offset = i * 4;
        presets.add(
          LedColor(
            bytes[offset],
            bytes[offset + 1],
            bytes[offset + 2],
            bytes[offset + 3],
          ),
        );
      }
      return presets;
    } catch (e) {
      return List.filled(50, const LedColor.off());
    }
  }

  // ── 扫描并自动连接（设备页用）───────────────────────────
  Future<void> scanAndConnect() async {
    if (_isConnected || _isLoading) return;

    _isLoading = true;
    notifyListeners();

    await startScan();

    // 等待扫描完成（最多15秒）
    for (int i = 0; i < 15; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (_discoveredDevices.isNotEmpty) {
        await connectToDevice(_discoveredDevices.first.id);
        // 等待连接建立（最多5秒）
        for (int j = 0; j < 5; j++) {
          await Future.delayed(const Duration(seconds: 1));
          if (_isConnected) break;
        }
        break;
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  // ── 连接到绑定设备 ────────────────────────────────────
  Future<void> connectToBoundDevice() async {
    if (_isConnected || _isLoading || _boundDeviceId == null) return;

    _isLoading = true;
    notifyListeners();

    await startScan();

    // 等待扫描完成（最多10秒），查找绑定设备
    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(seconds: 1));

      // 查找绑定设备
      final boundDevice = _discoveredDevices.firstWhere(
        (d) => d.id == _boundDeviceId,
        orElse: () => DiscoveredBleDevice(id: '', name: ''),
      );

      if (boundDevice.id.isNotEmpty) {
        debugPrint('Found bound device: ${boundDevice.name}');
        await connectToDevice(boundDevice.id);
        // 等待连接建立（最多5秒）
        for (int j = 0; j < 5; j++) {
          await Future.delayed(const Duration(seconds: 1));
          if (_isConnected) break;
        }
        break;
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  // ── FFF8: 写入亮度 (0-255) ───────────────────────────
  Future<void> writeBrightness(int brightness) async {
    if (_brightnessChar == null) return;
    try {
      final value = brightness.clamp(0, 255);
      if (_brightnessChar!.properties.writeWithoutResponse) {
        await _brightnessChar!.write([value], withoutResponse: true);
      } else {
        await _brightnessChar!.write([value], withoutResponse: false);
      }
      debugPrint('Brightness written: $value');
    } catch (e) {
      debugPrint('Write brightness failed: $e');
    }
  }

  // ── FFF9: 写入爆闪控制 [mode, freq] ──────────────────
  Future<void> writeStrobe(bool enable, int freqHz) async {
    if (_strobeChar == null) return;
    try {
      final data = [enable ? 1 : 0, freqHz.clamp(1, 20)];
      if (_strobeChar!.properties.writeWithoutResponse) {
        await _strobeChar!.write(data, withoutResponse: true);
      } else {
        await _strobeChar!.write(data, withoutResponse: false);
      }
      debugPrint('Strobe written: enable=$enable, freq=$freqHz Hz');
    } catch (e) {
      debugPrint('Write strobe failed: $e');
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connSub?.cancel();
    _colorNotifySub?.cancel();
    _device?.disconnect();
    super.dispose();
  }
}
