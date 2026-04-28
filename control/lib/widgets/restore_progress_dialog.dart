import 'package:flutter/material.dart';

/// DFU 颜色恢复进度弹窗
class RestoreProgressDialog extends StatefulWidget {
  final ValueNotifier<String> statusNotifier;
  final ValueNotifier<RestoreState> stateNotifier;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  const RestoreProgressDialog({
    super.key,
    required this.statusNotifier,
    required this.stateNotifier,
    this.onRetry,
    this.onCancel,
  });

  @override
  State<RestoreProgressDialog> createState() => _RestoreProgressDialogState();
}

class _RestoreProgressDialogState extends State<RestoreProgressDialog> {
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // 禁止返回键关闭
      child: AlertDialog(
        title: const Text('正在初始化设备'),
        content: ValueListenableBuilder<String>(
          valueListenable: widget.statusNotifier,
          builder: (context, status, _) {
            return ValueListenableBuilder<RestoreState>(
              valueListenable: widget.stateNotifier,
              builder: (context, state, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 进度步骤
                    _buildStep('等待设备重启', _getStepState(state, 0)),
                    _buildStep('连接设备', _getStepState(state, 1)),
                    _buildStep('同步颜色数据', _getStepState(state, 2)),
                    _buildStep('验证数据完整性', _getStepState(state, 3)),

                    const SizedBox(height: 16),

                    // 状态文字
                    Text(
                      status,
                      style: TextStyle(
                        color: state == RestoreState.failed
                            ? Colors.red
                            : Colors.grey.shade600,
                      ),
                    ),

                    // 加载指示器或结果图标
                    const SizedBox(height: 16),
                    Center(child: _buildStatusIndicator(state)),
                  ],
                );
              },
            );
          },
        ),
        actions: [
          // 根据状态显示不同的按钮
          ValueListenableBuilder<RestoreState>(
            valueListenable: widget.stateNotifier,
            builder: (context, state, _) {
              if (state == RestoreState.failed) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: widget.onCancel,
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: widget.onRetry,
                      child: const Text('重试'),
                    ),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStep(String title, StepState state) {
    IconData icon;
    Color color;

    switch (state) {
      case StepState.waiting:
        icon = Icons.radio_button_unchecked;
        color = Colors.grey;
      case StepState.active:
        icon = Icons.hourglass_empty;
        color = Colors.blue;
      case StepState.completed:
        icon = Icons.check_circle;
        color = Colors.green;
      case StepState.failed:
        icon = Icons.cancel;
        color = Colors.red;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: state == StepState.active ? Colors.blue : Colors.grey,
              fontWeight: state == StepState.active
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  StepState _getStepState(RestoreState restoreState, int step) {
    if (restoreState == RestoreState.failed) {
      // 失败时，当前步骤显示失败，后续步骤显示等待
      final currentStep = _getCurrentStep(restoreState);
      if (step < currentStep) return StepState.completed;
      if (step == currentStep) return StepState.failed;
      return StepState.waiting;
    }

    final currentStep = _getCurrentStep(restoreState);
    if (step < currentStep) return StepState.completed;
    if (step == currentStep) {
      return restoreState == RestoreState.completed
          ? StepState.completed
          : StepState.active;
    }
    return StepState.waiting;
  }

  int _getCurrentStep(RestoreState state) {
    switch (state) {
      case RestoreState.waitingRestart:
        return 0;
      case RestoreState.connecting:
        return 1;
      case RestoreState.syncingColors:
        return 2;
      case RestoreState.verifying:
        return 3;
      case RestoreState.completed:
        return 4;
      case RestoreState.failed:
        return 2; // 默认在同步步骤失败
    }
  }

  Widget _buildStatusIndicator(RestoreState state) {
    switch (state) {
      case RestoreState.completed:
        return const Icon(Icons.check_circle, size: 48, color: Colors.green);
      case RestoreState.failed:
        return const Icon(Icons.error, size: 48, color: Colors.red);
      default:
        return const CircularProgressIndicator();
    }
  }
}

/// 恢复状态枚举
enum RestoreState {
  waitingRestart, // 等待设备重启
  connecting, // 连接设备
  syncingColors, // 同步颜色数据
  verifying, // 验证数据完整性
  completed, // 完成
  failed, // 失败
}

/// 步骤状态枚举
enum StepState {
  waiting, // 等待中
  active, // 进行中
  completed, // 已完成
  failed, // 失败
}
