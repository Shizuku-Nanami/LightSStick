import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/led_color.dart';

/// RGBW 四通道颜色选择器 — 滑块 + 手动输入
class ColorPickerDialog extends StatefulWidget {
  final LedColor initialColor;
  final String title;

  const ColorPickerDialog({
    super.key,
    required this.initialColor,
    this.title = '选择颜色',
  });

  static Future<LedColor?> show(
    BuildContext context, {
    LedColor initialColor = const LedColor.off(),
    String title = '选择颜色',
  }) {
    return showDialog<LedColor>(
      context: context,
      builder: (_) =>
          ColorPickerDialog(initialColor: initialColor, title: title),
    );
  }

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog> {
  late int _r, _g, _b, _w;
  late final TextEditingController _rCtrl;
  late final TextEditingController _gCtrl;
  late final TextEditingController _bCtrl;
  late final TextEditingController _wCtrl;
  late final TextEditingController _hexCtrl;

  @override
  void initState() {
    super.initState();
    _r = widget.initialColor.r;
    _g = widget.initialColor.g;
    _b = widget.initialColor.b;
    _w = widget.initialColor.w;
    _rCtrl = TextEditingController(text: '$_r');
    _gCtrl = TextEditingController(text: '$_g');
    _bCtrl = TextEditingController(text: '$_b');
    _wCtrl = TextEditingController(text: '$_w');
    _hexCtrl = TextEditingController(text: _toHex());
  }

  @override
  void dispose() {
    _rCtrl.dispose();
    _gCtrl.dispose();
    _bCtrl.dispose();
    _wCtrl.dispose();
    _hexCtrl.dispose();
    super.dispose();
  }

  Color get _previewColor => Color.fromARGB(
    255,
    (_r + _w).clamp(0, 255),
    (_g + _w).clamp(0, 255),
    (_b + _w).clamp(0, 255),
  );

  String _toHex() =>
      '#${_r.toRadixString(16).padLeft(2, '0')}'
      '${_g.toRadixString(16).padLeft(2, '0')}'
      '${_b.toRadixString(16).padLeft(2, '0')}';

  void _syncTextControllers() {
    _rCtrl.text = '$_r';
    _gCtrl.text = '$_g';
    _bCtrl.text = '$_b';
    _wCtrl.text = '$_w';
    _hexCtrl.text = _toHex();
  }

  void _onHexChanged(String hex) {
    var clean = hex.replaceAll('#', '').replaceAll(' ', '');
    if (clean.length == 6) {
      final val = int.tryParse(clean, radix: 16);
      if (val != null) {
        setState(() {
          _r = (val >> 16) & 0xFF;
          _g = (val >> 8) & 0xFF;
          _b = val & 0xFF;
          // W 不变
          _rCtrl.text = '$_r';
          _gCtrl.text = '$_g';
          _bCtrl.text = '$_b';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 颜色预览
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: _previewColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _previewColor.withValues(alpha: 0.5),
                    blurRadius: 15,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // R
            _buildSliderRow(
              'R',
              _r,
              Colors.red,
              (v) {
                setState(() {
                  _r = v.toInt().clamp(0, 255);
                  _syncTextControllers();
                });
              },
              _rCtrl,
              (v) {
                final val = int.tryParse(v);
                if (val != null) {
                  setState(() {
                    _r = val.clamp(0, 255);
                    _syncTextControllers();
                  });
                }
              },
            ),
            // G
            _buildSliderRow(
              'G',
              _g,
              Colors.green,
              (v) {
                setState(() {
                  _g = v.toInt().clamp(0, 255);
                  _syncTextControllers();
                });
              },
              _gCtrl,
              (v) {
                final val = int.tryParse(v);
                if (val != null) {
                  setState(() {
                    _g = val.clamp(0, 255);
                    _syncTextControllers();
                  });
                }
              },
            ),
            // B
            _buildSliderRow(
              'B',
              _b,
              Colors.blue,
              (v) {
                setState(() {
                  _b = v.toInt().clamp(0, 255);
                  _syncTextControllers();
                });
              },
              _bCtrl,
              (v) {
                final val = int.tryParse(v);
                if (val != null) {
                  setState(() {
                    _b = val.clamp(0, 255);
                    _syncTextControllers();
                  });
                }
              },
            ),
            // W
            _buildSliderRow(
              'W',
              _w,
              Colors.amber,
              (v) {
                setState(() {
                  _w = v.toInt().clamp(0, 255);
                  _syncTextControllers();
                });
              },
              _wCtrl,
              (v) {
                final val = int.tryParse(v);
                if (val != null) {
                  setState(() {
                    _w = val.clamp(0, 255);
                    _syncTextControllers();
                  });
                }
              },
            ),

            const SizedBox(height: 12),

            // HEX 输入
            Row(
              children: [
                const SizedBox(
                  width: 32,
                  child: Text(
                    'HEX',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _hexCtrl,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      border: const OutlineInputBorder(),
                      hintText: 'RRGGBB',
                      suffixIcon: Container(
                        width: 20,
                        height: 20,
                        margin: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _previewColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9a-fA-F#]'),
                      ),
                      LengthLimitingTextInputFormatter(7),
                    ],
                    onChanged: _onHexChanged,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, LedColor(_r, _g, _b, _w)),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildSliderRow(
    String label,
    int value,
    Color activeColor,
    ValueChanged<double> onSliderChanged,
    TextEditingController ctrl,
    ValueChanged<String> onTextSubmitted,
  ) {
    final effectiveColor = activeColor == Colors.amber
        ? Theme.of(context).colorScheme.primary
        : activeColor;

    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: effectiveColor,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 255,
              activeColor: effectiveColor,
              onChanged: onSliderChanged,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: TextField(
            controller: ctrl,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            onSubmitted: onTextSubmitted,
          ),
        ),
      ],
    );
  }
}
