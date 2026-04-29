/**
 * @file button_manager.c
 * @brief 按键管理模块实现
 *
 * BTN_PREV 长按 5 秒实现假关机/假开机
 * 假关机状态下所有按键操作被屏蔽，LED 关闭
 * 状态不持久化，断电后自动恢复正常
 */

#include "button_manager.h"
#include "nrf_drv_gpiote.h"
#include "app_timer.h"
#include "nrf_log.h"
#include "app_error.h"
#include "color_manager.h"
#include "storage_manager.h"
#include "power_manager.h"
#include "led_driver.h"

// GPIO 配置
#define BTN_PREV_PIN            9      // P0.09
#define BTN_NEXT_PIN            10      // P0.10

// 去抖延迟时间 (20ms)
#define DEBOUNCE_DELAY_MS       20

// 长按检测时间 (5秒)
#define LONG_PRESS_MS           5000

// 两键同时按下检测窗口 (100ms)
#define BOTH_BUTTONS_WINDOW_MS  100

// 按键去抖定时器
APP_TIMER_DEF(m_debounce_timer_next);
APP_TIMER_DEF(m_debounce_timer_prev);

// 长按检测定时器（仅 BTN_PREV）
APP_TIMER_DEF(m_long_press_timer);

// 按键事件处理函数
static button_event_handler_t m_event_handler = NULL;

// 按键使能标志
static bool m_buttons_enabled = true;

// 假关机状态（不持久化，断电自动恢复）
static bool m_fake_power_off = false;

// 长按检测状态
static volatile bool m_prev_held = false;  // BTN_PREV 是否正在被按住

// 两键同时按下检测
static volatile bool m_next_pressed = false;
static volatile bool m_prev_pressed = false;
static volatile uint32_t m_last_button_time = 0;

/**
 * @brief 检查两键是否同时按下
 */
static void check_both_buttons_pressed(void)
{
    if (m_next_pressed && m_prev_pressed)
    {
        NRF_LOG_INFO("Both buttons pressed simultaneously!");
        
        // 重置按键状态
        m_next_pressed = false;
        m_prev_pressed = false;
        
        // 重启广播
        power_manager_restart_advertising();
    }
}

/**
 * @brief 长按定时器回调（BTN_PREV 按住 5 秒触发）
 */
static void long_press_timer_handler(void *p_context)
{
    UNUSED_PARAMETER(p_context);

    // 确认 BTN_PREV 仍然被按住
    if (nrf_drv_gpiote_in_is_set(BTN_PREV_PIN) == false)
    {
        m_fake_power_off = !m_fake_power_off;

        if (m_fake_power_off)
        {
            NRF_LOG_INFO("=== FAKE POWER OFF (long press) ===");
            led_off();
        }
        else
        {
            NRF_LOG_INFO("=== FAKE POWER ON (long press) ===");
            // 恢复当前颜色
            color_manager_apply_current();
        }
    }

    m_prev_held = false;
}

/**
 * @brief 去抖定时器超时处理（下一颜色）
 */
static void debounce_timeout_handler_next(void *p_context)
{
    UNUSED_PARAMETER(p_context);
    
    // 假关机状态下屏蔽所有按键
    if (!m_buttons_enabled || m_fake_power_off)
    {
        return;
    }
    
    // 重置活动计时器（唤醒休眠）
    power_manager_reset_activity_timer();
    
    // 确认按键状态
    if (nrf_drv_gpiote_in_is_set(BTN_NEXT_PIN) == false)
    {
        // 标记按键按下
        m_next_pressed = true;
        m_last_button_time = app_timer_cnt_get();
        
        // 检查两键同时按下
        check_both_buttons_pressed();
        
        // 如果不是两键同时按下，执行正常颜色切换
        if (!m_prev_pressed)
        {
            NRF_LOG_INFO("Button NEXT pressed");
            
            // 切换到下一颜色
            color_manager_next();
            
            // 保存配置到 Flash
            storage_manager_save_config();
            
            // 触发事件回调
            if (m_event_handler != NULL)
            {
                m_event_handler(BUTTON_EVENT_NEXT);
            }
        }
    }
    else
    {
        // 按键释放
        m_next_pressed = false;
    }
}

/**
 * @brief 去抖定时器超时处理（上一颜色）
 */
static void debounce_timeout_handler_prev(void *p_context)
{
    UNUSED_PARAMETER(p_context);
    
    // 假关机状态下，只检测长按，不执行颜色切换
    if (m_fake_power_off)
    {
        return;
    }
    
    if (!m_buttons_enabled)
    {
        return;
    }
    
    // 重置活动计时器（唤醒休眠）
    power_manager_reset_activity_timer();
    
    // 确认按键状态
    if (nrf_drv_gpiote_in_is_set(BTN_PREV_PIN) == false)
    {
        // 标记按键按下
        m_prev_pressed = true;
        m_last_button_time = app_timer_cnt_get();
        
        // 检查两键同时按下
        check_both_buttons_pressed();
        
        // 如果不是两键同时按下，执行正常颜色切换
        if (!m_next_pressed)
        {
            NRF_LOG_INFO("Button PREV pressed");
            
            // 切换到上一颜色
            color_manager_prev();
            
            // 保存配置到 Flash
            storage_manager_save_config();
            
            // 触发事件回调
            if (m_event_handler != NULL)
            {
                m_event_handler(BUTTON_EVENT_PREV);
            }
        }
    }
    else
    {
        // 按键释放
        m_prev_pressed = false;
    }
}

/**
 * @brief GPIOTE 事件处理函数（双沿检测：按下和释放）
 */
static void gpiote_event_handler(nrf_drv_gpiote_pin_t pin, nrf_gpiote_polarity_t action)
{
    ret_code_t err_code;
    bool pin_is_low;

    switch (pin)
    {
        case BTN_NEXT_PIN:
            pin_is_low = (nrf_drv_gpiote_in_is_set(BTN_NEXT_PIN) == false);

            if (pin_is_low)
            {
                // 按下：启动去抖定时器
                if (m_buttons_enabled && !m_fake_power_off)
                {
                    err_code = app_timer_start(m_debounce_timer_next,
                                              APP_TIMER_TICKS(DEBOUNCE_DELAY_MS),
                                              NULL);
                    APP_ERROR_CHECK(err_code);
                }
            }
            else
            {
                // 释放：标记释放
                m_next_pressed = false;
            }
            break;

        case BTN_PREV_PIN:
            pin_is_low = (nrf_drv_gpiote_in_is_set(BTN_PREV_PIN) == false);

            if (pin_is_low)
            {
                // 按下：启动去抖定时器 + 长按检测定时器
                m_prev_held = true;

                // 长按定时器（假关机状态下也需要启动，用于长按唤醒）
                err_code = app_timer_start(m_long_press_timer,
                                          APP_TIMER_TICKS(LONG_PRESS_MS),
                                          NULL);
                APP_ERROR_CHECK(err_code);

                // 去抖定时器（正常按键处理）
                if (m_buttons_enabled)
                {
                    err_code = app_timer_start(m_debounce_timer_prev,
                                              APP_TIMER_TICKS(DEBOUNCE_DELAY_MS),
                                              NULL);
                    APP_ERROR_CHECK(err_code);
                }
            }
            else
            {
                // 释放：停止长按定时器，标记释放
                m_prev_held = false;
                m_prev_pressed = false;
                app_timer_stop(m_long_press_timer);
            }
            break;

        default:
            break;
    }
}

void button_manager_init(void)
{
    ret_code_t err_code;
    
    // 初始化 GPIOTE
    if (!nrf_drv_gpiote_is_init())
    {
        err_code = nrf_drv_gpiote_init();
        APP_ERROR_CHECK(err_code);
    }
    
    // 配置按键输入引脚（双沿检测：按下和释放都能触发中断）
    nrf_drv_gpiote_in_config_t in_config = GPIOTE_CONFIG_IN_SENSE_TOGGLE(false);
    in_config.pull = NRF_GPIO_PIN_PULLUP;
    
    err_code = nrf_drv_gpiote_in_init(BTN_NEXT_PIN, &in_config, gpiote_event_handler);
    APP_ERROR_CHECK(err_code);
    
    err_code = nrf_drv_gpiote_in_init(BTN_PREV_PIN, &in_config, gpiote_event_handler);
    APP_ERROR_CHECK(err_code);
    
    // 使能按键检测
    nrf_drv_gpiote_in_event_enable(BTN_NEXT_PIN, true);
    nrf_drv_gpiote_in_event_enable(BTN_PREV_PIN, true);
    
    // 创建去抖定时器
    err_code = app_timer_create(&m_debounce_timer_next,
                               APP_TIMER_MODE_SINGLE_SHOT,
                               debounce_timeout_handler_next);
    APP_ERROR_CHECK(err_code);
    
    err_code = app_timer_create(&m_debounce_timer_prev,
                               APP_TIMER_MODE_SINGLE_SHOT,
                               debounce_timeout_handler_prev);
    APP_ERROR_CHECK(err_code);

    // 创建长按检测定时器
    err_code = app_timer_create(&m_long_press_timer,
                               APP_TIMER_MODE_SINGLE_SHOT,
                               long_press_timer_handler);
    APP_ERROR_CHECK(err_code);
    
    NRF_LOG_INFO("Button manager initialized (NEXT: P0.%d, PREV: P0.%d, long press: %d ms)",
                 BTN_NEXT_PIN, BTN_NEXT_PIN, LONG_PRESS_MS);
}

void button_manager_process(void)
{
    // 按键管理在定时器中处理
}

void button_manager_register_handler(button_event_handler_t handler)
{
    m_event_handler = handler;
}

void button_manager_enable(void)
{
    m_buttons_enabled = true;
    
    // 重新使能按键检测
    nrf_drv_gpiote_in_event_enable(BTN_NEXT_PIN, true);
    nrf_drv_gpiote_in_event_enable(BTN_PREV_PIN, true);
    
    NRF_LOG_INFO("Buttons enabled");
}

void button_manager_disable(void)
{
    m_buttons_enabled = false;
    
    // 禁用按键检测
    nrf_drv_gpiote_in_event_disable(BTN_NEXT_PIN);
    nrf_drv_gpiote_in_event_disable(BTN_PREV_PIN);
    
    NRF_LOG_INFO("Buttons disabled");
}

bool button_manager_is_fake_off(void)
{
    return m_fake_power_off;
}
