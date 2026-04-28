import 'package:flutter/material.dart';

/// 电池指示器组件
class BatteryIndicator extends StatelessWidget {
  final int level; // 0-100, -1 表示未知
  final double size;

  const BatteryIndicator({super.key, required this.level, this.size = 32});

  @override
  Widget build(BuildContext context) {
    if (level < 0) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.battery_unknown, size: size, color: Colors.grey),
          const SizedBox(width: 4),
          Text('--', style: Theme.of(context).textTheme.bodyMedium),
        ],
      );
    }

    final icon = _batteryIcon(level);
    final color = _batteryColor(level);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: size, color: color),
        const SizedBox(width: 4),
        Text(
          '$level%',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static IconData _batteryIcon(int level) {
    if (level <= 10) return Icons.battery_0_bar;
    if (level <= 25) return Icons.battery_1_bar;
    if (level <= 50) return Icons.battery_3_bar;
    if (level <= 75) return Icons.battery_5_bar;
    return Icons.battery_full;
  }

  static Color _batteryColor(int level) {
    if (level <= 10) return Colors.red;
    if (level <= 25) return Colors.orange;
    return Colors.green;
  }
}
