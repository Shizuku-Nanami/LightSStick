import 'package:flutter/material.dart';

import '../models/led_color.dart';
import '../models/team_color.dart';

/// API 导入底部弹窗（单步选择模式）
/// 用户直接点击颜色选择，选够数量后确认导入
class ApiImportSheet extends StatefulWidget {
  final List<TeamColor> teams;
  final int selectedCount; // 需要选择的颜色数量

  const ApiImportSheet({
    super.key,
    required this.teams,
    required this.selectedCount,
  });

  /// 显示底部弹窗，返回颜色列表（长度 == selectedCount），或 null 取消
  static Future<List<LedColor>?> show(
    BuildContext context, {
    required List<TeamColor> teams,
    required int selectedCount,
  }) {
    return showModalBottomSheet<List<LedColor>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ApiImportSheet(teams: teams, selectedCount: selectedCount),
    );
  }

  @override
  State<ApiImportSheet> createState() => _ApiImportSheetState();
}

class _ApiImportSheetState extends State<ApiImportSheet> {
  // 已选择的颜色（按选择顺序）
  final List<LedColor> _selectedColors = [];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = widget.selectedCount - _selectedColors.length;
    final canConfirm = _selectedColors.length == widget.selectedCount;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动条
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.4,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text('选择颜色', style: theme.textTheme.titleLarge),
                const Spacer(),
                Text(
                  '已选 ${_selectedColors.length} / ${widget.selectedCount}',
                  style: TextStyle(
                    color: remaining > 0 ? Colors.orange : Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // 已选颜色预览条
          if (_selectedColors.isNotEmpty)
            Container(
              height: 48,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedColors.length,
                itemBuilder: (context, i) {
                  final color = _selectedColors[i];
                  return GestureDetector(
                    onTap: () => _removeColor(i),
                    child: Container(
                      width: 48,
                      height: 48,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: color.toDisplayColor(),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color:
                                color.toDisplayColor().computeLuminance() > 0.5
                                ? Colors.black
                                : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          const Divider(height: 16),

          // 团队颜色列表
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.teams.length,
              itemBuilder: (context, teamIdx) {
                final team = widget.teams[teamIdx];
                final remaining = widget.selectedCount - _selectedColors.length;
                return _TeamColorGrid(
                  team: team,
                  selectedColors: _selectedColors,
                  remainingSlots: remaining,
                  onColorTap: (color) => _toggleColor(color),
                  onSelectAll: () => _toggleTeam(team),
                );
              },
            ),
          ),

          // 底部按钮
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _dismiss(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: canConfirm
                        ? () => _dismiss(
                            context,
                            result: List<LedColor>.from(_selectedColors),
                          )
                        : null,
                    child: const Text('确认导入'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 安全关闭弹窗
  void _dismiss(BuildContext context, {List<LedColor>? result}) {
    if (!context.mounted) return;

    // 使用 addPostFrameCallback 延迟到下一帧
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted && Navigator.canPop(context)) {
        Navigator.pop(context, result);
      }
    });
  }

  void _toggleColor(LedColor color) {
    setState(() {
      final idx = _selectedColors.indexOf(color);
      if (idx >= 0) {
        // 已选中，取消选择
        _selectedColors.removeAt(idx);
      } else if (_selectedColors.length < widget.selectedCount) {
        // 未选中，添加选择
        _selectedColors.add(color);
      }
    });
  }

  void _removeColor(int index) {
    setState(() {
      _selectedColors.removeAt(index);
    });
  }

  // 切换整个团队的选择状态
  void _toggleTeam(TeamColor team) {
    setState(() {
      final allSelected = team.colors.every((c) => _selectedColors.contains(c));

      if (allSelected) {
        // 取消选择该团队的所有颜色
        for (final color in team.colors) {
          _selectedColors.remove(color);
        }
      } else {
        // 选择该团队的所有颜色（如果还有空间）
        final remaining = widget.selectedCount - _selectedColors.length;
        for (final color in team.colors) {
          if (!_selectedColors.contains(color) &&
              _selectedColors.length < widget.selectedCount) {
            _selectedColors.add(color);
          }
        }
      }
    });
  }
}

/// 团队颜色网格组件
class _TeamColorGrid extends StatelessWidget {
  final TeamColor team;
  final List<LedColor> selectedColors;
  final int remainingSlots;
  final ValueChanged<LedColor> onColorTap;
  final VoidCallback onSelectAll;

  const _TeamColorGrid({
    required this.team,
    required this.selectedColors,
    required this.remainingSlots,
    required this.onColorTap,
    required this.onSelectAll,
  });

  bool get _isTeamFullySelected {
    return team.colors.every((c) => selectedColors.contains(c));
  }

  bool get _canSelectAll {
    return team.colors.length <= remainingSlots;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 团队名称 + 全选勾
            Row(
              children: [
                Expanded(
                  child: Text(
                    team.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  '${team.colors.length}色',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 4),
                // 全选勾
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Checkbox(
                    value: _isTeamFullySelected,
                    onChanged: (_canSelectAll || _isTeamFullySelected)
                        ? (_) => onSelectAll()
                        : null,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 颜色网格
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: team.colors.map((color) {
                final selectedIdx = selectedColors.indexOf(color);
                final isSelected = selectedIdx >= 0;

                return GestureDetector(
                  onTap: () => onColorTap(color),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color.toDisplayColor(),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? Colors.blue : Colors.grey,
                        width: isSelected ? 3 : 1,
                      ),
                    ),
                    child: isSelected
                        ? Center(
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.blue,
                              child: Text(
                                '${selectedIdx + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
