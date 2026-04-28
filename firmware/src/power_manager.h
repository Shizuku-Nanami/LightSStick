/**
 * @file power_manager.h
 * @brief 功耗管理模块
 * 
 * 管理系统休眠和唤醒
 */

#ifndef POWER_MANAGER_H
#define POWER_MANAGER_H

#include <stdint.h>
#include <stdbool.h>

// 自动休眠超时时间 (30分钟)
#define AUTO_SLEEP_TIMEOUT_MS   (30 * 60 * 1000)

/**
 * @brief 初始化功耗管理器
 */
void power_manager_init(void);

/**
 * @brief 功耗管理器处理函数（在主循环中调用）
 */
void power_manager_process(void);

/**
 * @brief 进入休眠模式
 */
void power_manager_enter_sleep(void);

/**
 * @brief 唤醒系统
 */
void power_manager_wakeup(void);

/**
 * @brief 重置活动计时器（有操作时调用）
 */
void power_manager_reset_activity_timer(void);

/**
 * @brief 两键同时按下重启广播
 * 
 * 当广播超时停止后，同时按下两个按钮可重新启动广播
 */
void power_manager_restart_advertising(void);

/**
 * @brief 检查是否处于休眠状态
 * 
 * @return true 休眠中, false 活动中
 */
bool power_manager_is_sleeping(void);

/**
 * @brief 检查是否正在广播
 * 
 * @return true 正在广播, false 未广播
 */
bool power_manager_is_advertising(void);

#endif // POWER_MANAGER_H
