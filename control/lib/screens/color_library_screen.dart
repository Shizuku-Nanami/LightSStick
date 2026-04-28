import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ensemble_icons/remixicon.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/led_color.dart';
import '../services/ble_service.dart';
import '../services/color_api_service.dart';
import '../widgets/api_import_sheet.dart';
import '../widgets/color_picker_dialog.dart';
import '../widgets/glass_card.dart';
import '../widgets/preset_grid.dart';

typedef MultiSelectCallback = void Function(bool active, {Widget? bottomBar});

/// 全局 key，供 MainNavigation 在系统返回时退出多选
final colorLibraryKey = GlobalKey<_ColorLibraryScreenState>();

/// Tab2: 颜色库页 — 50 个预设管理
class ColorLibraryScreen extends StatefulWidget {
  final MultiSelectCallback? onMultiSelectChanged;

  const ColorLibraryScreen({super.key, this.onMultiSelectChanged});

  @override
  State<ColorLibraryScreen> createState() => _ColorLibraryScreenState();
}

class _ColorLibraryScreenState extends State<ColorLibraryScreen> {
  static const String _presetsKey = 'local_presets';
  static const String _gridColsKey = 'grid_cross_axis_count';
  static const int _presetCount = 50;

  List<LedColor> _presets = [];
  final Set<int> _selectedIndices = {};
  final Map<int, int> _selectionOrder = {};
  int _selectionCounter = 0;
  bool _isMultiSelectMode = false;

  int _crossAxisCount = 5;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _crossAxisCount = prefs.getInt(_gridColsKey) ?? 5;

    final jsonStr = prefs.getString(_presetsKey);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final list = jsonDecode(jsonStr) as List;
        if (list.length >= _presetCount) {
          _presets = list
              .take(_presetCount)
              .map((j) => LedColor.fromJson(j as Map<String, dynamic>))
              .toList();
        }
      } catch (e) {
        // 解析失败，将使用默认值
        debugPrint('Failed to load presets: $e');
      }
    }
    if (_presets.length < _presetCount) {
      _presets = List.generate(_presetCount, (i) => _defaultColor(i));
      await _savePresets();
    }
    setState(() {});
  }

  Future<void> _savePresets() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_presets.map((c) => c.toJson()).toList());
    await prefs.setString(_presetsKey, jsonStr);
  }

  Future<void> _saveGridCols(int cols) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_gridColsKey, cols);
  }

  // ── 选择逻辑 ──────────────────────────────────────────

  void _toggleSelect(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
        _selectionOrder.remove(index);
        _rebuildOrder();
      } else {
        _selectedIndices.add(index);
        _selectionOrder[index] = _selectionCounter++;
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIndices.clear();
      _selectionOrder.clear();
      _selectionCounter = 1;
      for (int i = 0; i < _presetCount; i++) {
        _selectedIndices.add(i);
        _selectionOrder[i] = _selectionCounter++;
      }
    });
  }

  void _invertSelection() {
    setState(() {
      final allIndices = List.generate(_presetCount, (i) => i);
      for (final i in allIndices) {
        if (_selectedIndices.contains(i)) {
          _selectedIndices.remove(i);
          _selectionOrder.remove(i);
        } else {
          _selectedIndices.add(i);
        }
      }
      _rebuildOrder();
    });
  }

  void _enterMultiSelect(int initialIndex) {
    setState(() {
      _isMultiSelectMode = true;
      _selectedIndices.add(initialIndex);
      _selectionOrder[initialIndex] = _selectionCounter++;
    });
    _notifyParent();
  }

  void exitMultiSelect() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedIndices.clear();
      _selectionOrder.clear();
      _selectionCounter = 0;
    });
    _notifyParent();
  }

  void _rebuildOrder() {
    _selectionOrder.clear();
    _selectionCounter = 1;
    final sorted = _selectedIndices.toList()..sort();
    for (final idx in sorted) {
      _selectionOrder[idx] = _selectionCounter++;
    }
  }

  void _notifyParent() {
    widget.onMultiSelectChanged?.call(
      _isMultiSelectMode,
      bottomBar: _isMultiSelectMode ? _buildBottomBar() : null,
    );
  }

  // ── 操作 ──────────────────────────────────────────────

  void _onTap(int index) {
    if (_isMultiSelectMode) {
      _toggleSelect(index);
      return;
    }
    _showSingleTileDialog(index);
  }

  void _onLongPress(int index) {
    if (_isMultiSelectMode) {
      _toggleSelect(index);
      return;
    }
    _enterMultiSelect(index);
  }

  void _showSingleTileDialog(int index) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _presets[index].toDisplayColor(),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
              ),
              title: Text('格子 #${index + 1}'),
              subtitle: Text(
                'R:${_presets[index].r} G:${_presets[index].g} '
                'B:${_presets[index].b} W:${_presets[index].w}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Remix.contrast_2_line),
              title: const Text('颜色选择'),
              onTap: () {
                Navigator.pop(ctx);
                _editSingleColor(index);
              },
            ),
            ListTile(
              leading: const Icon(Remix.exchange_line),
              title: const Text('API导入'),
              onTap: () {
                Navigator.pop(ctx);
                _selectedIndices.add(index);
                _selectionOrder[index] = 1;
                _selectionCounter = 2;
                _onApiImport();
              },
            ),
            ListTile(
              leading: const Icon(Remix.restart_line),
              title: const Text('恢复默认'),
              onTap: () {
                Navigator.pop(ctx);
                _resetSingle(index);
              },
            ),
            ListTile(
              leading: const Icon(Remix.send_plane_line),
              title: const Text('发送到设备'),
              onTap: () {
                Navigator.pop(ctx);
                final ble = context.read<BleService>();
                if (ble.isConnected) {
                  ble.writeColor(_presets[index]);
                } else {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('请先连接设备')));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editSingleColor(int index) async {
    final color = await ColorPickerDialog.show(
      context,
      initialColor: _presets[index],
      title: '修改格子 #${index + 1}',
    );
    if (color != null) {
      setState(() => _presets[index] = color);
      await _savePresets();
      final ble = context.read<BleService>();
      if (ble.isConnected) await ble.writePreset(index, color);
    }
  }

  void _resetSingle(int index) {
    setState(() => _presets[index] = _defaultColor(index));
    _savePresets();
    final ble = context.read<BleService>();
    if (ble.isConnected) ble.writePreset(index, _presets[index]);
  }

  Future<void> _syncFromDevice() async {
    final ble = context.read<BleService>();
    if (!ble.isConnected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先连接设备')));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('正在从设备读取预设...')));
    try {
      final presets = await ble.readAllPresets();
      setState(() => _presets = presets);
      await _savePresets();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('同步完成')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('同步失败: $e')));
    }
  }

  Future<void> _onApiImport() async {
    final apiService = context.read<ColorApiService>();
    if (apiService.teams.isEmpty) await apiService.refresh();
    if (apiService.teams.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无可用团队数据: ${apiService.error ?? "请设置API URL"}')),
      );
      return;
    }
    final result = await ApiImportSheet.show(
      context,
      teams: apiService.teams,
      selectedCount: _selectedIndices.length,
    );
    if (result != null && result.length == _selectedIndices.length) {
      final sortedIndices = _selectedIndices.toList()..sort();
      for (int i = 0; i < sortedIndices.length; i++) {
        _presets[sortedIndices[i]] = result[i];
      }
      setState(() {});
      await _savePresets();
      final ble = context.read<BleService>();
      if (ble.isConnected) {
        final batch = <int, LedColor>{};
        for (int i = 0; i < sortedIndices.length; i++) {
          batch[sortedIndices[i]] = result[i];
        }
        await ble.writePresetsBatch(batch);
      }
      exitMultiSelect();
    } else {
      exitMultiSelect();
    }
  }

  Future<void> _onCustomColor() async {
    final sortedIndices = _selectedIndices.toList()..sort();
    for (final idx in sortedIndices) {
      final color = await ColorPickerDialog.show(
        context,
        initialColor: _presets[idx],
        title: '格子 #${idx + 1}',
      );
      if (color != null) _presets[idx] = color;
    }
    setState(() {});
    await _savePresets();
    final ble = context.read<BleService>();
    if (ble.isConnected) {
      final batch = <int, LedColor>{};
      for (final idx in sortedIndices) batch[idx] = _presets[idx];
      await ble.writePresetsBatch(batch);
    }
    exitMultiSelect();
  }

  Future<void> _onDelete() async {
    final sortedIndices = _selectedIndices.toList()..sort();
    for (final idx in sortedIndices) _presets[idx] = _defaultColor(idx);
    setState(() {});
    await _savePresets();
    final ble = context.read<BleService>();
    if (ble.isConnected) {
      final batch = <int, LedColor>{};
      for (final idx in sortedIndices) batch[idx] = _presets[idx];
      await ble.writePresetsBatch(batch);
    }
    exitMultiSelect();
  }

  // 批量清除颜色（设置为关闭状态 RGBW=0,0,0,0）
  Future<void> _onClearColors() async {
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清除'),
        content: Text('确定要将选中的 ${_selectedIndices.length} 个格子清除为关闭状态吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final sortedIndices = _selectedIndices.toList()..sort();
    for (final idx in sortedIndices) {
      _presets[idx] = const LedColor(0, 0, 0, 0); // 清除为关闭状态
    }
    setState(() {});
    await _savePresets();
    final ble = context.read<BleService>();
    if (ble.isConnected) {
      final batch = <int, LedColor>{};
      for (final idx in sortedIndices) batch[idx] = _presets[idx];
      await ble.writePresetsBatch(batch);
    }
    exitMultiSelect();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已清除 ${sortedIndices.length} 个格子')));
  }

  // ── UI ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleService>();

    return Scaffold(
      appBar: _isMultiSelectMode
          ? _buildMultiSelectAppBar()
          : _buildNormalAppBar(),
      body: _presets.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildDropdownBar(ble),
                Expanded(
                  child: PresetGrid(
                    presets: _presets,
                    selectedIndices: _selectedIndices,
                    selectionOrder: _selectionOrder,
                    isMultiSelectMode: _isMultiSelectMode,
                    crossAxisCount: _crossAxisCount,
                    onTap: _onTap,
                    onLongPress: _onLongPress,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDropdownBar(BleService ble) {
    return GlassBar(
      child: Row(
        children: [
          Icon(
            Remix.grid_line,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          DropdownButton<int>(
            value: _crossAxisCount,
            underline: const SizedBox(),
            isDense: true,
            items: const [
              DropdownMenuItem(value: 3, child: Text('3列')),
              DropdownMenuItem(value: 4, child: Text('4列')),
              DropdownMenuItem(value: 5, child: Text('5列')),
              DropdownMenuItem(value: 6, child: Text('6列')),
              DropdownMenuItem(value: 8, child: Text('8列')),
              DropdownMenuItem(value: 10, child: Text('10列')),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() => _crossAxisCount = v);
                _saveGridCols(v);
              }
            },
          ),
          const Spacer(),
          Icon(
            Remix.bluetooth_fill,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 6),
          if (ble.isScanning)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            _buildDeviceDropdown(ble),
        ],
      ),
    );
  }

  Widget _buildDeviceDropdown(BleService ble) {
    if (ble.isConnected) {
      return Text(
        ble.displayDeviceName,
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }
    if (ble.discoveredDevices.isEmpty) {
      return TextButton.icon(
        onPressed: () => ble.startScan(),
        icon: const Icon(Remix.search_line, size: 16),
        label: const Text('扫描', style: TextStyle(fontSize: 13)),
      );
    }
    return DropdownButton<String>(
      value: null,
      hint: Text(
        '选择设备 (${ble.discoveredDevices.length})',
        style: const TextStyle(fontSize: 13),
      ),
      underline: const SizedBox(),
      isDense: true,
      items: ble.discoveredDevices.map((d) {
        return DropdownMenuItem(
          value: d.id,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                d.displayName(ble.customNames),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(width: 6),
              Text(
                d.id.length > 8 ? d.id.substring(d.id.length - 8) : d.id,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (deviceId) {
        if (deviceId != null) ble.connectToDevice(deviceId);
      },
    );
  }

  AppBar _buildNormalAppBar() {
    return AppBar(
      title: const Text('颜色库'),
      actions: [
        IconButton(
          icon: const Icon(Remix.refresh_line),
          tooltip: '从设备同步',
          onPressed: _syncFromDevice,
        ),
      ],
    );
  }

  AppBar _buildMultiSelectAppBar() {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Remix.close_fill),
        onPressed: exitMultiSelect,
      ),
      title: Text('已选 ${_selectedIndices.length} 个'),
      actions: [
        IconButton(
          icon: const Icon(Remix.checkbox_multiple_blank_line),
          tooltip: '全选',
          onPressed: _selectAll,
        ),
        IconButton(
          icon: const Icon(Remix.arrow_left_right_line),
          tooltip: '反选',
          onPressed: _invertSelection,
        ),
        IconButton(
          icon: const Icon(Remix.restart_line),
          tooltip: '恢复全部默认',
          onPressed: () {
            setState(() {
              for (int i = 0; i < _presetCount; i++) {
                _presets[i] = _defaultColor(i);
              }
            });
            _savePresets();
            exitMultiSelect();
          },
        ),
      ],
    );
  }

  /// 多选模式底部操作栏（替换 NavigationBar）
  Widget _buildBottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _selectedIndices.isNotEmpty ? _onApiImport : null,
                icon: const Icon(Remix.exchange_line, size: 18),
                label: const Text('API导入'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onLongPress: _selectedIndices.isNotEmpty
                    ? _onClearColors
                    : null,
                child: FilledButton.icon(
                  onPressed: _selectedIndices.isNotEmpty
                      ? _onCustomColor
                      : null,
                  icon: const Icon(Remix.brush_line, size: 18),
                  label: const Text('自定义'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _selectedIndices.isNotEmpty ? _onDelete : null,
                icon: const Icon(Remix.delete_bin_line, size: 18),
                label: const Text('恢复默认'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  foregroundColor: Theme.of(
                    context,
                  ).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static LedColor _defaultColor(int index) {
    const defaults = [
      [255, 0, 0, 0],
      [0, 255, 0, 0],
      [0, 0, 255, 0],
      [255, 255, 0, 0],
      [255, 0, 255, 0],
      [0, 255, 255, 0],
      [0, 0, 0, 255],
      [255, 192, 203, 0],
      [255, 182, 193, 0],
      [255, 105, 180, 0],
      [255, 20, 147, 0],
      [255, 165, 0, 0],
      [255, 140, 0, 0],
      [255, 69, 0, 0],
      [255, 127, 80, 0],
      [128, 0, 128, 0],
      [138, 43, 226, 0],
      [148, 0, 211, 0],
      [186, 85, 211, 0],
      [221, 160, 221, 0],
      [0, 0, 139, 0],
      [0, 0, 205, 0],
      [30, 144, 255, 0],
      [135, 206, 250, 0],
      [0, 191, 255, 0],
      [0, 128, 0, 0],
      [34, 139, 34, 0],
      [0, 255, 127, 0],
      [50, 205, 50, 0],
      [144, 238, 144, 0],
      [255, 215, 0, 0],
      [255, 250, 205, 0],
      [255, 255, 224, 0],
      [165, 42, 42, 0],
      [139, 69, 19, 0],
      [210, 105, 30, 0],
      [244, 164, 96, 0],
      [128, 128, 128, 0],
      [192, 192, 192, 0],
      [169, 169, 169, 0],
      [211, 211, 211, 0],
      [255, 0, 0, 50],
      [0, 255, 0, 50],
      [0, 0, 255, 50],
      [128, 128, 0, 100],
      [0, 128, 128, 100],
      [128, 0, 128, 100],
      [100, 100, 100, 200],
      [150, 150, 150, 255],
      [0, 0, 0, 0],
    ];
    if (index < defaults.length) {
      final d = defaults[index];
      return LedColor(d[0], d[1], d[2], d[3]);
    }
    return const LedColor.off();
  }
}
