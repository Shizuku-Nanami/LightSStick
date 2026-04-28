/**
 * @file storage_manager.h
 * @brief Flash 存储管理模块
 * 
 * 使用 FDS (Flash Data Storage) 保存设备配置
 */

#ifndef STORAGE_MANAGER_H
#define STORAGE_MANAGER_H

#include <stdint.h>
#include <stdbool.h>
#include "led_driver.h"
#include "color_manager.h"

// 设备名称最大长度
#define DEVICE_NAME_MAX_LENGTH          20

// 设备配置结构
typedef struct {
    uint8_t color_index;                        // 当前颜色索引
    uint8_t brightness;                         // 亮度 (预留)
    char device_name[DEVICE_NAME_MAX_LENGTH];   // 设备名称（用户可编辑）
    led_color_t color_table[COLOR_COUNT];       // 全部 50 个预设颜色
} device_config_t;

/**
 * @brief 初始化存储管理器
 */
void storage_manager_init(void);

/**
 * @brief 保存配置到 Flash
 * 
 * @return true 成功, false 失败
 */
bool storage_manager_save_config(void);

/**
 * @brief 从 Flash 加载配置
 * 
 * @return true 成功, false 失败
 */
bool storage_manager_load_config(void);

/**
 * @brief 获取当前配置
 * 
 * @param p_config 输出配置结构体指针
 */
void storage_manager_get_config(device_config_t *p_config);

/**
 * @brief 设置配置
 * 
 * @param p_config 输入配置结构体指针
 */
void storage_manager_set_config(const device_config_t *p_config);

/**
 * @brief 清除所有存储的配置
 */
void storage_manager_clear(void);

/**
 * @brief 获取设备名称
 * 
 * @return 设备名称字符串指针
 */
const char *storage_manager_get_device_name(void);

/**
 * @brief 设置设备名称
 * 
 * @param name 新的设备名称
 */
void storage_manager_set_device_name(const char *name);

#endif // STORAGE_MANAGER_H
