import 'package:flutter/material.dart';

/// 圆形颜色预览组件
class ColorPreview extends StatelessWidget {
  final Color color;
  final double size;
  final String? label;
  final VoidCallback? onTap;

  const ColorPreview({
    super.key,
    required this.color,
    this.size = 120,
    this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 8),
            Text(label!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// 带序号的颜色小方块（用于网格预设）
class ColorTile extends StatelessWidget {
  final Color color;
  final int index;
  final bool isSelected;
  final int? selectionOrder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ColorTile({
    super.key,
    required this.color,
    required this.index,
    this.isSelected = false,
    this.selectionOrder,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 3 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.4),
                    blurRadius: 8,
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            // 序号
            Positioned(
              bottom: 2,
              right: 4,
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 10,
                  color: _textColor(color),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // 选中标记
            if (isSelected && selectionOrder != null)
              Positioned(
                top: 2,
                left: 4,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$selectionOrder',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 根据背景色计算对比文字色
  static Color _textColor(Color bg) {
    final luminance = bg.computeLuminance();
    return luminance > 0.5 ? Colors.black : Colors.white;
  }
}
