import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/team_color.dart';

/// ColorAPI 网络服务 — 获取团队颜色 + 本地缓存
class ColorApiService extends ChangeNotifier {
  static const String _urlKey = 'color_api_url';
  static const String _cacheKey = 'color_api_cache';
  static const String _customUrlsKey = 'color_api_custom_urls';

  // 内置预设 API 地址
  static const List<String> _builtinUrls = [
    'https://control.hksstudio.work/hikari-stick/color_json/BanGDream.json',
  ];

  String _currentUrl = '';
  List<TeamColor> _teams = [];
  bool _isLoading = false;
  String? _error;
  List<String> _customUrls = [];

  String get currentUrl => _currentUrl;
  List<TeamColor> get teams => _teams;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// 全部 URL = 内置 + 用户自定义
  List<String> get allUrls => [..._builtinUrls, ..._customUrls];

  ColorApiService() {
    _loadAll();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUrl = prefs.getString(_urlKey) ?? '';

    // 加载自定义 URL
    final customJson = prefs.getString(_customUrlsKey);
    if (customJson != null) {
      try {
        _customUrls = (jsonDecode(customJson) as List).cast<String>();
      } catch (_) {}
    }

    // 加载缓存
    final cacheJson = prefs.getString(_cacheKey);
    if (cacheJson != null && cacheJson.isNotEmpty) {
      try {
        final data = jsonDecode(cacheJson);
        final response = ColorApiResponse.fromJson(data);
        _teams = response.teams;
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> setUrl(String url) async {
    _currentUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, url);
    notifyListeners();
  }

  /// 添加自定义 URL
  Future<void> addCustomUrl(String url) async {
    if (url.isEmpty || _customUrls.contains(url)) return;
    _customUrls.add(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customUrlsKey, jsonEncode(_customUrls));
    notifyListeners();
  }

  /// 删除自定义 URL
  Future<void> removeCustomUrl(String url) async {
    _customUrls.remove(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customUrlsKey, jsonEncode(_customUrls));
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_currentUrl.isEmpty) {
      _error = '请先设置 ColorAPI URL';
      notifyListeners();
      return;
    }
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http
          .get(Uri.parse(_currentUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final apiResponse = ColorApiResponse.fromJson(data);
        _teams = apiResponse.teams;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, response.body);
        _error = null;
      } else {
        _error = '请求失败: HTTP ${response.statusCode}';
      }
    } catch (e) {
      _error = '请求异常: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    _teams = [];
    notifyListeners();
  }
}
