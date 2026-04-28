import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

/// 液态玻璃效果卡片 — 用于设备页信息卡片
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double? height;
  final double borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.height,
    this.borderRadius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final r = borderRadius;
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: IntrinsicHeight(
        child: SizedBox(
          height: height,
          child: LiquidGlassView(
            pixelRatio: 0.5,
            realTimeCapture: false,
            backgroundWidget: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(r),
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
              ),
              child: padding != null
                  ? Padding(padding: padding!, child: child)
                  : child,
            ),
            children: [
              LiquidGlass(
                width: double.infinity,
                height: height ?? 100,
                distortion: 0.06,
                distortionWidth: 25,
                magnification: 1.0,
                color: Colors.white.withValues(alpha: 0.08),
                shape: RoundedRectangleShape(cornerRadius: r),
                position: LiquidGlassAlignPosition(alignment: Alignment.center),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 液态玻璃效果的下拉操作栏
class GlassBar extends StatelessWidget {
  final Widget child;

  const GlassBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LiquidGlassView(
        pixelRatio: 0.4,
        realTimeCapture: false,
        backgroundWidget: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerLow.withValues(alpha: 0.75),
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
              ),
            ),
          ),
          child: child,
        ),
        children: [
          LiquidGlass(
            width: double.infinity,
            height: 46,
            distortion: 0.04,
            distortionWidth: 15,
            color: Colors.white.withValues(alpha: 0.06),
            shape: const RoundedRectangleShape(cornerRadius: 0),
            position: LiquidGlassAlignPosition(alignment: Alignment.center),
          ),
        ],
      ),
    );
  }
}
