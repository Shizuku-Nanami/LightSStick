/**
 * @file color_manager.h
 * @brief 颜色管理模块
 * 
 * 管理预设颜色表和颜色切换
 */

#ifndef COLOR_MANAGER_H
#define COLOR_MANAGER_H

#include <stdint.h>
#include "led_driver.h"

// 最大预设颜色数量
#define COLOR_COUNT 50

// 颜色变化回调函数类型
typedef void (*color_change_callback_t)(uint8_t r, uint8_t g, uint8_t b, uint8_t w);

/**
 * @brief 初始化颜色管理器
 */
void color_manager_init(void);

/**
 * @brief 注册颜色变化回调函数
 * 
 * @param callback 回调函数指针
 */
void color_manager_register_callback(color_change_callback_t callback);

/**
 * @brief 切换到下一个颜色
 */
void color_manager_next(void);

/**
 * @brief 切换到上一个颜色
 */
void color_manager_prev(void);

/**
 * @brief 获取当前颜色索引
 * 
 * @return 当前颜色索引 (0 ~ COLOR_COUNT-1)
 */
uint8_t color_manager_get_index(void);

/**
 * @brief 设置当前颜色索引
 * 
 * @param index 颜色索引
 */
void color_manager_set_index(uint8_t index);

/**
 * @brief 获取当前颜色
 * 
 * @param p_color 输出颜色结构体指针
 */
void color_manager_get_current_color(led_color_t *p_color);

/**
 * @brief 获取指定索引的颜色
 * 
 * @param index 颜色索引
 * @param p_color 输出颜色结构体指针
 */
void color_manager_get_color_by_index(uint8_t index, led_color_t *p_color);

/**
 * @brief 应用当前颜色到 LED
 */
void color_manager_apply_current(void);

/**
 * @brief 覆盖指定索引的预设颜色
 *
 * @param index 颜色索引 (0 ~ COLOR_COUNT-1)
 * @param r 红色分量
 * @param g 绿色分量
 * @param b 蓝色分量
 * @param w 白色分量
 */
void color_manager_set_color(uint8_t index, uint8_t r, uint8_t g, uint8_t b, uint8_t w);

/**
 * @brief 获取全部 50 个预设颜色
 *
 * @param p_buffer 输出缓冲区，需 >= COLOR_COUNT * sizeof(led_color_t) 字节
 */
void color_manager_get_all_colors(led_color_t *p_buffer);

/**
 * @brief 获取颜色表指针（供存储管理器直接读写）
 *
 * @return 颜色表首地址
 */
led_color_t *color_manager_get_table(void);

/**
 * @brief 恢复出厂默认颜色表
 */
void color_manager_reset_to_defaults(void);

#endif // COLOR_MANAGER_H
