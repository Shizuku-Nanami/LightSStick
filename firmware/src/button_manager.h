/**
 * @file button_manager.h
 * @brief 按键管理模块
 * 
 * 使用 GPIOTE 中断检测按键，20ms 去抖
 * BTN_PREV 长按 5 秒实现假关机/假开机
 */

#ifndef BUTTON_MANAGER_H
#define BUTTON_MANAGER_H

#include <stdint.h>
#include <stdbool.h>

// 按键事件类型
typedef enum {
    BUTTON_EVENT_NEXT,      // 下一颜色按键
    BUTTON_EVENT_PREV       // 上一颜色按键
} button_event_t;

// 按键事件回调函数类型
typedef void (*button_event_handler_t)(button_event_t event);

/**
 * @brief 初始化按键管理器
 */
void button_manager_init(void);

/**
 * @brief 按键管理器处理函数（在主循环中调用）
 */
void button_manager_process(void);

/**
 * @brief 注册按键事件处理函数
 * 
 * @param handler 事件处理函数指针
 */
void button_manager_register_handler(button_event_handler_t handler);

/**
 * @brief 启用按键检测
 */
void button_manager_enable(void);

/**
 * @brief 禁用按键检测
 */
void button_manager_disable(void);

/**
 * @brief 查询是否处于假关机状态
 * 
 * @return true 假关机中, false 正常工作
 */
bool button_manager_is_fake_off(void);

#endif // BUTTON_MANAGER_H
