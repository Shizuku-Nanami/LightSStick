/**
 * @file battery_manager.h
 * @brief 电池管理模块
 * 
 * 使用 ADC 检测电池电压，计算电量百分比
 */

#ifndef BATTERY_MANAGER_H
#define BATTERY_MANAGER_H

#include <stdint.h>
#include <stdbool.h>

// 电池电量变化回调函数类型
typedef void (*battery_level_callback_t)(uint8_t level);

/**
 * @brief 初始化电池管理器
 */
void battery_manager_init(void);

/**
 * @brief 电池管理器处理函数（在主循环中调用）
 */
void battery_manager_process(void);

/**
 * @brief 获取电池电压 (mV)
 * 
 * @return 电池电压 (单位: mV)
 */
uint16_t battery_manager_get_voltage(void);

/**
 * @brief 获取电池电量百分比
 * 
 * @return 电量百分比 (0-100%)
 */
uint8_t battery_manager_get_level(void);

/**
 * @brief 检查是否处于低电状态
 * 
 * @return true 低电, false 正常
 */
bool battery_manager_is_low(void);

/**
 * @brief 强制更新电池状态
 */
void battery_manager_update(void);

/**
 * @brief 注册电池电量变化回调
 * 
 * @param callback 回调函数
 */
void battery_manager_register_callback(battery_level_callback_t callback);

#endif // BATTERY_MANAGER_H
