import 'led_color.dart';

/// 团队颜色模型（ColorAPI 返回数据）
class TeamColor {
  final String name;
  final List<LedColor> colors;

  const TeamColor({required this.name, required this.colors});

  factory TeamColor.fromJson(Map<String, dynamic> json) {
    final colorsList = json['colors'] as List<dynamic>? ?? [];
    return TeamColor(
      name: json['name'] as String? ?? 'Unknown',
      colors: colorsList
          .map((c) => LedColor.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'colors': colors.map((c) => c.toJson()).toList(),
  };

  @override
  String toString() => 'TeamColor($name, ${colors.length} colors)';
}

/// ColorAPI 响应模型
class ColorApiResponse {
  final List<TeamColor> teams;

  const ColorApiResponse({required this.teams});

  factory ColorApiResponse.fromJson(dynamic json) {
    if (json is List) {
      return ColorApiResponse(
        teams: json
            .map((t) => TeamColor.fromJson(t as Map<String, dynamic>))
            .toList(),
      );
    }
    // 兼容 { "teams": [...] } 格式
    if (json is Map<String, dynamic>) {
      final teamsList = json['teams'] as List<dynamic>? ?? [];
      return ColorApiResponse(
        teams: teamsList
            .map((t) => TeamColor.fromJson(t as Map<String, dynamic>))
            .toList(),
      );
    }
    return const ColorApiResponse(teams: []);
  }
}
