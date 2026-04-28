import 'package:flutter/material.dart';

import '../models/led_color.dart';
import 'color_preview.dart';

/// 50 格颜色预设网格 — 点击 / 长按
class PresetGrid extends StatelessWidget {
  final List<LedColor> presets;
  final Set<int> selectedIndices;
  final Map<int, int> selectionOrder;
  final bool isMultiSelectMode;
  final int crossAxisCount;
  final ValueChanged<int>? onTap;
  final ValueChanged<int>? onLongPress;

  const PresetGrid({
    super.key,
    required this.presets,
    this.selectedIndices = const {},
    this.selectionOrder = const {},
    this.isMultiSelectMode = false,
    this.crossAxisCount = 5,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: presets.length,
      itemBuilder: (context, index) {
        final color = presets[index];
        final isSelected = selectedIndices.contains(index);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap?.call(index),
          onLongPress: () => onLongPress?.call(index),
          child: ColorTile(
            color: color.toDisplayColor(),
            index: index,
            isSelected: isSelected,
            selectionOrder: isSelected ? selectionOrder[index] : null,
          ),
        );
      },
    );
  }
}
