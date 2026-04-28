import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ensemble_icons/remixicon.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../models/led_color.dart';
import '../services/ble_service.dart';
import '../services/color_api_service.dart';
import '../services/dfu_service.dart';
import 'dfu_screen.dart';

/// Tab3: 软件设置页
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = HikariStickApp.of(context);
    final ble = context.watch<BleService>();
    final apiService = context.watch<ColorApiService>();

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          // ── 外观 ──────────────────────────────────────
          _sectionHeader('外观'),
          ListTile(
            leading: const Icon(Remix.contrast_line),
            title: const Text('主题模式'),
            trailing: DropdownButton<ThemeMode>(
              value: appState?.themeMode ?? ThemeMode.system,
              underline: const SizedBox(),
              isDense: true,
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('浅色')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('深色')),
              ],
              onChanged: (v) {
                if (v != null) appState?.setThemeMode(v);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Remix.palette_line),
            title: const Text('主题色'),
            trailing: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: appState?.seedColor ?? const Color(0xFF6C63FF),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).dividerColor,
                  width: 2,
                ),
              ),
            ),
            onTap: () => _showThemeColorPicker(appState),
          ),

          const Divider(),

          // ── ColorAPI ──────────────────────────────────
          _sectionHeader('ColorAPI'),
          ListTile(
            leading: const Icon(Remix.link),
            title: const Text('当前 API 地址'),
            subtitle: Text(
              apiService.currentUrl.isNotEmpty ? apiService.currentUrl : '未设置',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ListTile(
            leading: const Icon(Remix.list_check),
            title: const Text('选择 / 管理 API 地址'),
            onTap: () => _showUrlManager(apiService),
          ),
          ListTile(
            leading: apiService.isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Remix.refresh_line),
            title: const Text('刷新缓存'),
            subtitle: apiService.error != null
                ? Text(
                    apiService.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                : Text('已缓存 ${apiService.teams.length} 个团队'),
            onTap: apiService.isLoading ? null : () => apiService.refresh(),
          ),
          ListTile(
            leading: const Icon(Remix.delete_bin_line),
            title: const Text('清除缓存'),
            onTap: () async {
              await apiService.clearCache();
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('缓存已清除')));
              }
            },
          ),

          const Divider(),

          // ── 设备信息 ──────────────────────────────────
          _sectionHeader('设备信息'),
          ListTile(
            leading: const Icon(Remix.bluetooth_fill),
            title: const Text('设备名称'),
            subtitle: Text(ble.deviceName.isNotEmpty ? ble.deviceName : '未连接'),
          ),
          if (ble.isConnected)
            ListTile(
              leading: const Icon(Remix.edit_line),
              title: const Text('自定义显示名称'),
              subtitle: Text(
                ble.customNames.containsKey(ble.deviceId)
                    ? ble.customNames[ble.deviceId]!
                    : '点击设置自定义名称',
              ),
              onTap: () => _showRenameDialog(ble),
            ),
          ListTile(
            leading: const Icon(Remix.cpu_line),
            title: const Text('固件版本'),
            subtitle: Text(ble.isConnected ? ble.firmwareVersion : '未连接'),
            onTap: ble.isConnected ? () => _openDfuScreen(context, ble) : null,
          ),
          ListTile(
            leading: const Icon(Remix.restart_line),
            title: const Text('恢复出厂颜色'),
            subtitle: const Text('将设备内50个预设恢复为默认值'),
            onTap: () => _restoreDeviceDefaults(ble),
          ),

          const Divider(),

          // ── 关于 ──────────────────────────────────────
          _sectionHeader('关于'),
          ListTile(
            leading: const Icon(Remix.information_line),
            title: const Text('版本'),
            subtitle: FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Text(
                    '${snapshot.data!.version}+${snapshot.data!.buildNumber}',
                  );
                }
                return const Text('加载中...');
              },
            ),
            onTap: () => _checkAppUpdate(context),
          ),
          ListTile(
            leading: const Icon(Remix.file_text_line),
            title: const Text('开源协议'),
            subtitle: const Text('MIT License'),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  // ── 自定义设备名称 ────────────────────────────────────

  void _showRenameDialog(BleService ble) {
    if (!ble.isConnected || ble.deviceId == null) return;
    final controller = TextEditingController(
      text: ble.customNames[ble.deviceId] ?? '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义显示名称'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '设备: ${ble.deviceName}\nMAC: ${ble.deviceId}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '输入自定义名称（留空使用设备原名）',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              ble.setCustomName(ble.deviceId!, controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // ── 获取设备 CPU 架构 ──────────────────────────────────
  Future<String> _getCpuArchitecture() async {
    if (Platform.isAndroid) {
      // Android: 通过 platform channel 获取 ABI
      try {
        const platform = MethodChannel('hks.hikari.control/system');
        final abi = await platform.invokeMethod<String>('getCpuAbi');
        if (abi != null) return abi;
      } catch (_) {}
      // 默认返回 arm64-v8a
      return 'arm64-v8a';
    }
    return 'universal';
  }

  // ── APP 更新检查 ──────────────────────────────────────
  Future<void> _checkAppUpdate(BuildContext context) async {
    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 获取当前版本和 CPU 架构
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuildNumber = packageInfo.buildNumber;
      final cpuAbi = await _getCpuArchitecture();

      // 从服务器获取最新版本（单个 JSON）
      final response = await http
          .get(
            Uri.parse(
              'https://control.hksstudio.work/hikari-control/app/version',
            ),
          )
          .timeout(const Duration(seconds: 10));

      // 关闭加载对话框
      if (mounted) Navigator.pop(context);

      if (response.statusCode == 200) {
        // 使用 UTF-8 解码以正确处理中文
        final responseBody = utf8.decode(response.bodyBytes);
        final data = jsonDecode(responseBody);
        final latestVersion = data['version'] as String? ?? '';
        final latestBuildNumber = data['build_number'] as String? ?? '0';
        final changelog = data['changelog'] as String? ?? '';

        // 获取对应架构的下载链接
        String downloadUrl = '';
        final downloadUrls = data['download_urls'];
        if (downloadUrls is Map<String, dynamic>) {
          downloadUrl = downloadUrls[cpuAbi] as String? ?? '';
          // 如果没有对应架构，尝试使用 universal
          if (downloadUrl.isEmpty) {
            downloadUrl = downloadUrls['universal'] as String? ?? '';
          }
        } else if (data['download_url'] is String) {
          // 兼容旧格式
          downloadUrl = data['download_url'] as String;
        }

        // 比较版本
        final currentVersionInt = _versionStringToInt(currentVersion);
        final latestVersionInt = _versionStringToInt(latestVersion);

        if (latestVersionInt > currentVersionInt ||
            (latestVersionInt == currentVersionInt &&
                int.parse(latestBuildNumber) > int.parse(currentBuildNumber))) {
          // 有新版本，显示更新对话框
          if (mounted) {
            _showAppUpdateDialog(
              context,
              currentVersion: currentVersion,
              latestVersion: latestVersion,
              changelog: changelog,
              downloadUrl: downloadUrl,
            );
          }
        } else {
          // 已是最新版本
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('已是最新版本')));
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('检查更新失败，请稍后再试')));
        }
      }
    } catch (e) {
      // 关闭加载对话框
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('检查更新失败: $e')));
      }
    }
  }

  int _versionStringToInt(String version) {
    final parts = version.split('.');
    final major = int.tryParse(parts[0]) ?? 0;
    final minor = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final patch = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
    return major * 10000 + minor * 100 + patch;
  }

  void _showAppUpdateDialog(
    BuildContext context, {
    required String currentVersion,
    required String latestVersion,
    required String changelog,
    required String downloadUrl,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现新版本'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本: v$currentVersion'),
            Text(
              '最新版本: v$latestVersion',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            if (changelog.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                '更新内容:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(changelog),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后再说'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadAppUpdate(downloadUrl, latestVersion);
            },
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAppUpdate(String downloadUrl, String version) async {
    // 请求安装未知来源应用的权限（Android）
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        final result = await Permission.requestInstallPackages.request();
        if (!result.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('需要安装应用权限才能更新')));
          }
          return;
        }
      }
    }

    // 显示下载进度对话框
    double downloadProgress = 0;
    ValueNotifier<double> progressNotifier = ValueNotifier(0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('正在下载'),
        content: ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value > 0 ? value : null),
              const SizedBox(height: 8),
              Text('${(value * 100).toInt()}%'),
            ],
          ),
        ),
      ),
    );

    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/app_update_v$version.apk';

      final dio = Dio();
      await dio.download(
        downloadUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            downloadProgress = received / total;
            progressNotifier.value = downloadProgress;
          }
        },
      );

      // 关闭下载对话框
      if (mounted) Navigator.pop(context);

      // 打开 APK 文件进行安装
      final result = await OpenFile.open(filePath);
      if (result.type != ResultType.done) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('打开文件失败: ${result.message}')));
        }
      }
    } catch (e) {
      // 关闭下载对话框
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('下载失败: $e')));
      }
    }
  }

  // ── 固件更新页面 ──────────────────────────────────────
  void _openDfuScreen(BuildContext context, BleService ble) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => DfuService(),
          child: DfuScreen(currentVersionStr: ble.firmwareVersion),
        ),
      ),
    );
  }

  // ── 主题色选择 ──────────────────────────────────────

  void _showThemeColorPicker(HikariStickAppState? appState) {
    if (appState == null) return;
    final colors = <Color>[
      const Color(0xFF6C63FF),
      const Color(0xFF2196F3),
      const Color(0xFF00BCD4),
      const Color(0xFF4CAF50),
      const Color(0xFFFF9800),
      const Color(0xFFFF5722),
      const Color(0xFFE91E63),
      const Color(0xFF9C27B0),
      const Color(0xFF607D8B),
      const Color(0xFF795548),
      const Color(0xFF3F51B5),
      const Color(0xFF009688),
    ];

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选择主题色',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: colors.map((c) {
                  final isSelected = appState.seedColor == c;
                  return GestureDetector(
                    onTap: () {
                      appState.setSeedColor(c);
                      Navigator.pop(ctx);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: c.withValues(alpha: 0.5),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── API 地址管理 ─────────────────────────────────────

  void _showUrlManager(ColorApiService apiService) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        expand: false,
        builder: (ctx, scrollController) => SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    const Text(
                      '管理 API 地址',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Remix.add_circle_line),
                      tooltip: '添加自定义地址',
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showAddUrlDialog(apiService);
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: apiService.allUrls.length,
                  itemBuilder: (context, i) {
                    final url = apiService.allUrls[i];
                    final isCustom = i >= 2; // 前两个是内置的
                    final isActive = apiService.currentUrl == url;
                    return ListTile(
                      leading: Icon(
                        isActive
                            ? Remix.checkbox_circle_fill
                            : Remix.checkbox_blank_circle_line,
                        color: isActive
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      title: Text(url, style: const TextStyle(fontSize: 13)),
                      subtitle: isCustom
                          ? const Text('自定义', style: TextStyle(fontSize: 11))
                          : null,
                      trailing: isCustom
                          ? IconButton(
                              icon: const Icon(Remix.close_fill, size: 18),
                              onPressed: () {
                                apiService.removeCustomUrl(url);
                              },
                            )
                          : null,
                      onTap: () {
                        apiService.setUrl(url);
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddUrlDialog(ColorApiService apiService) {
    _urlController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加自定义 API 地址'),
        content: TextField(
          controller: _urlController,
          decoration: const InputDecoration(
            hintText: 'https://example.com/api/colors.json',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final url = _urlController.text.trim();
              if (url.isNotEmpty) {
                apiService.addCustomUrl(url);
                apiService.setUrl(url);
              }
              Navigator.pop(ctx);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  // ── 恢复出厂 ────────────────────────────────────────

  void _restoreDeviceDefaults(BleService ble) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复出厂颜色'),
        content: const Text('此操作将设备内 50 个预设颜色恢复为出厂默认值，确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (ble.isConnected) {
                ble.writePresetsBatch(_getDefaultColors());
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已发送恢复命令')));
              } else {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('请先连接设备')));
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Map<int, LedColor> _getDefaultColors() {
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
    final map = <int, LedColor>{};
    for (int i = 0; i < defaults.length; i++) {
      map[i] = LedColor(
        defaults[i][0],
        defaults[i][1],
        defaults[i][2],
        defaults[i][3],
      );
    }
    return map;
  }
}
