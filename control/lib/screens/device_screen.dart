import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ensemble_icons/remixicon.dart';
import 'package:provider/provider.dart';

import '../models/led_color.dart';
import '../services/ble_service.dart';
import '../widgets/battery_indicator.dart';
import '../widgets/color_picker_dialog.dart';
import '../widgets/color_preview.dart';
import '../widgets/glass_card.dart';

/// Tab1: 设备控制页
class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  Timer? _batteryTimer;
  bool _autoConnectAttempted = false;

  @override
  void initState() {
    super.initState();
    // 延迟执行自动连接，等待 BleService 初始化完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutoConnect();
    });
  }

  Future<void> _tryAutoConnect() async {
    if (_autoConnectAttempted) return;
    _autoConnectAttempted = true;

    final ble = context.read<BleService>();

    // 等待绑定设备加载完成
    await ble.waitForBoundDeviceLoaded();

    if (!ble.isConnected && ble.isBound) {
      debugPrint('Auto-connecting to bound device: ${ble.boundDeviceId}');
      await ble.connectToBoundDevice();
    }
  }

  @override
  void dispose() {
    _batteryTimer?.cancel();
    super.dispose();
  }

  void _startBatteryPolling(BleService ble) {
    _batteryTimer?.cancel();
    _batteryTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (ble.isConnected) ble.readBatteryLevel();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BleService>(
      builder: (context, ble, _) {
        if (ble.isConnected) _startBatteryPolling(ble);

        return Scaffold(
          appBar: AppBar(
            title: Text(
              ble.displayDeviceName.isNotEmpty ? ble.displayDeviceName : '设备控制',
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  ble.isConnected
                      ? Remix.bluetooth_connect_fill
                      : Remix.bluetooth_fill,
                  color: ble.isConnected ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
          body: ble.isConnected
              ? _buildConnectedView(context, ble)
              : _buildDisconnectedView(context, ble),
        );
      },
    );
  }

  Widget _buildDisconnectedView(BuildContext context, BleService ble) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Remix.bluetooth_fill, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 24),
          Text('未连接设备', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            '点击下方按钮扫描附近的 HikariStick 设备',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 32),
          (ble.isScanning || ble.isLoading)
              ? const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('正在扫描并连接...'),
                  ],
                )
              : FilledButton.icon(
                  onPressed: () => ble.scanAndConnect(),
                  icon: const Icon(Remix.search_line),
                  label: const Text('扫描设备'),
                ),
        ],
      ),
    );
  }

  Widget _buildConnectedView(BuildContext context, BleService ble) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 电池信息 — 液态玻璃卡片
          GlassCard(
            padding: const EdgeInsets.all(16),
            height: 72,
            child: Row(
              children: [
                BatteryIndicator(level: ble.batteryLevel),
                const Spacer(),
                Text(
                  ble.displayDeviceName,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 当前颜色预览
          ColorPreview(
            color: ble.currentColor.toDisplayColor(),
            size: 150,
            label: '当前颜色',
            onTap: () async {
              final color = await ColorPickerDialog.show(
                context,
                initialColor: ble.currentColor,
                title: '设置颜色',
              );
              if (color != null) await ble.writeColor(color);
            },
          ),

          const SizedBox(height: 8),
          Text(
            'R:${ble.currentColor.r} G:${ble.currentColor.g} '
            'B:${ble.currentColor.b} W:${ble.currentColor.w}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            '点击预览圆可自定义颜色',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),

          const SizedBox(height: 24),

          // 快速调色板
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('快速调色板', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: _quickColors.map((qc) {
                      return GestureDetector(
                        onTap: () {
                          debugPrint('Quick color tapped: ${qc.label}');
                          ble.writeColor(qc.color);
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: qc.displayColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              qc.label,
                              style: TextStyle(
                                fontSize: 10,
                                color: qc.displayColor.computeLuminance() > 0.5
                                    ? Colors.black
                                    : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // RGBW 滑块 - 使用独立组件避免页面重建
          _RgbwSliderCard(
            currentColor: ble.currentColor,
            onColorChanged: (color) => ble.writeColor(color),
          ),

          const SizedBox(height: 16),

          // 亮度和爆闪控制卡片
          _BrightnessStrobeCard(ble: ble),

          const SizedBox(height: 16),

          // 断开连接 + 绑定/解绑按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: () => ble.disconnect(),
                icon: const Icon(Remix.link_unlink),
                label: const Text('断开连接'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () {
                  if (ble.isCurrentDeviceBound) {
                    ble.unbindDevice();
                  } else if (ble.deviceId != null) {
                    ble.bindDevice(ble.deviceId!, ble.displayDeviceName);
                  }
                },
                icon: Icon(
                  ble.isCurrentDeviceBound ? Remix.link_unlink : Remix.link,
                ),
                label: Text(ble.isCurrentDeviceBound ? '解绑' : '绑定'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ble.isCurrentDeviceBound
                      ? Colors.orange
                      : Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSlider(
    BuildContext context,
    String label,
    double value,
    Color activeColor,
    ValueChanged<double> onChanged, {
    ValueChanged<double>? onEnd,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: activeColor == Colors.amber ? null : activeColor,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            divisions: 255,
            activeColor: activeColor,
            onChanged: onChanged,
            onChangeEnd: onEnd,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text('${value.toInt()}', textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

class _QuickColor {
  final LedColor color;
  final String label;
  final Color displayColor;
  const _QuickColor(this.color, this.label, this.displayColor);
}

const _quickColors = [
  _QuickColor(LedColor(255, 0, 0, 0), '红', Colors.red),
  _QuickColor(LedColor(0, 255, 0, 0), '绿', Colors.green),
  _QuickColor(LedColor(0, 0, 255, 0), '蓝', Colors.blue),
  _QuickColor(LedColor(255, 255, 0, 0), '黄', Colors.yellow),
  _QuickColor(LedColor(255, 0, 255, 0), '紫', Colors.purple),
  _QuickColor(LedColor(0, 255, 255, 0), '青', Colors.cyan),
  _QuickColor(LedColor(255, 165, 0, 0), '橙', Colors.orange),
  _QuickColor(LedColor(255, 192, 203, 0), '粉', Colors.pink),
  _QuickColor(LedColor(0, 0, 0, 255), '白', Colors.white),
  _QuickColor(LedColor(0, 0, 0, 0), '关', Colors.black),
];

// RGBW 滑动条独立组件 - 避免页面重建导致卡顿
class _RgbwSliderCard extends StatefulWidget {
  final LedColor currentColor;
  final ValueChanged<LedColor> onColorChanged;

  const _RgbwSliderCard({
    required this.currentColor,
    required this.onColorChanged,
  });

  @override
  State<_RgbwSliderCard> createState() => _RgbwSliderCardState();
}

class _RgbwSliderCardState extends State<_RgbwSliderCard> {
  late int _r, _g, _b, _w;

  @override
  void initState() {
    super.initState();
    _r = widget.currentColor.r;
    _g = widget.currentColor.g;
    _b = widget.currentColor.b;
    _w = widget.currentColor.w;
  }

  @override
  void didUpdateWidget(_RgbwSliderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只在外部颜色变化且本地没有拖动时同步
    if (widget.currentColor != oldWidget.currentColor) {
      _r = widget.currentColor.r;
      _g = widget.currentColor.g;
      _b = widget.currentColor.b;
      _w = widget.currentColor.w;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('RGBW 控制', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _buildSlider(
              'R',
              _r.toDouble(),
              Colors.red,
              (v) => setState(() => _r = v.toInt()),
              onEnd: (_) => widget.onColorChanged(LedColor(_r, _g, _b, _w)),
            ),
            _buildSlider(
              'G',
              _g.toDouble(),
              Colors.green,
              (v) => setState(() => _g = v.toInt()),
              onEnd: (_) => widget.onColorChanged(LedColor(_r, _g, _b, _w)),
            ),
            _buildSlider(
              'B',
              _b.toDouble(),
              Colors.blue,
              (v) => setState(() => _b = v.toInt()),
              onEnd: (_) => widget.onColorChanged(LedColor(_r, _g, _b, _w)),
            ),
            _buildSlider(
              'W',
              _w.toDouble(),
              Colors.amber,
              (v) => setState(() => _w = v.toInt()),
              onEnd: (_) => widget.onColorChanged(LedColor(_r, _g, _b, _w)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    Color color,
    ValueChanged<double> onChanged, {
    ValueChanged<double>? onEnd,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color == Colors.amber ? null : color,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: 0,
            max: 255,
            divisions: 255,
            activeColor: color,
            onChanged: onChanged,
            onChangeEnd: onEnd,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            value.toInt().toString(),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// 亮度和爆闪控制卡片
class _BrightnessStrobeCard extends StatefulWidget {
  final BleService ble;

  const _BrightnessStrobeCard({required this.ble});

  @override
  State<_BrightnessStrobeCard> createState() => _BrightnessStrobeCardState();
}

class _BrightnessStrobeCardState extends State<_BrightnessStrobeCard> {
  double _brightness = 255;
  bool _strobeEnabled = false;
  double _strobeFreq = 5;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 亮度
            Text(
              '亮度',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.lightbulb_outline, size: 20),
                Expanded(
                  child: Slider(
                    value: _brightness,
                    min: 0,
                    max: 255,
                    divisions: 255,
                    activeColor: Colors.amber,
                    onChanged: (v) => setState(() => _brightness = v),
                    onChangeEnd: (v) {
                      widget.ble.writeBrightness(v.toInt());
                    },
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${(_brightness / 255 * 100).toInt()}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 爆闪
            Row(
              children: [
                Expanded(
                  child: Text(
                    '爆闪',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Switch(
                  value: _strobeEnabled,
                  onChanged: (v) {
                    setState(() => _strobeEnabled = v);
                    widget.ble.writeStrobe(v, _strobeFreq.toInt());
                  },
                ),
              ],
            ),

            // 爆闪频率（仅在开启时显示）
            if (_strobeEnabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.speed, size: 20),
                  Expanded(
                    child: Slider(
                      value: _strobeFreq,
                      min: 1,
                      max: 20,
                      divisions: 19,
                      label: '${_strobeFreq.toInt()} Hz',
                      activeColor: Colors.orange,
                      onChanged: (v) => setState(() => _strobeFreq = v),
                      onChangeEnd: (v) {
                        widget.ble.writeStrobe(_strobeEnabled, v.toInt());
                      },
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '${_strobeFreq.toInt()} Hz',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
