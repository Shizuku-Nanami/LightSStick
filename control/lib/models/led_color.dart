import 'dart:ui';

/// LED 颜色模型 (RGBW)
class LedColor {
  final int r;
  final int g;
  final int b;
  final int w;

  const LedColor(this.r, this.g, this.b, this.w);

  const LedColor.off() : r = 0, g = 0, b = 0, w = 0;

  factory LedColor.fromBytes(List<int> bytes) {
    if (bytes.length < 4) return const LedColor.off();
    return LedColor(bytes[0], bytes[1], bytes[2], bytes[3]);
  }

  /// 从 JSON 对象创建 {r, g, b, w?}
  factory LedColor.fromJson(Map<String, dynamic> json) {
    return LedColor(
      (json['r'] as num).toInt(),
      (json['g'] as num).toInt(),
      (json['b'] as num).toInt(),
      json.containsKey('w') ? (json['w'] as num).toInt() : 0,
    );
  }

  /// 转为 4 字节 BLE 写入格式
  List<int> toBytes() => [r, g, b, w];

  Map<String, dynamic> toJson() => {'r': r, 'g': g, 'b': b, 'w': w};

  /// 转为 Flutter Color（忽略 W 通道用于 UI 显示）
  Color toColor() => Color.fromARGB(255, r, g, b);

  /// 带白光混合的预览色（近似 SK6812 效果）
  Color toDisplayColor() {
    if (w == 0) return Color.fromARGB(255, r, g, b);
    final mr = ((r + w).clamp(0, 255)).toInt();
    final mg = ((g + w).clamp(0, 255)).toInt();
    final mb = ((b + w).clamp(0, 255)).toInt();
    return Color.fromARGB(255, mr, mg, mb);
  }

  /// 亮度 0-255
  int get brightness => [r, g, b, w].reduce((a, b) => a > b ? a : b);

  /// 是否为全黑
  bool get isOff => r == 0 && g == 0 && b == 0 && w == 0;

  LedColor copyWith({int? r, int? g, int? b, int? w}) {
    return LedColor(r ?? this.r, g ?? this.g, b ?? this.b, w ?? this.w);
  }

  @override
  bool operator ==(Object other) =>
      other is LedColor &&
      r == other.r &&
      g == other.g &&
      b == other.b &&
      w == other.w;

  @override
  int get hashCode => Object.hash(r, g, b, w);

  @override
  String toString() => 'LedColor(r=$r, g=$g, b=$b, w=$w)';
}
