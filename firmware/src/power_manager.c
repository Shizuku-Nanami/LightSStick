/**
 * @file power_manager.c
 * @brief 功耗管理模块实现
 */

#include "power_manager.h"
#include "nrf_pwr_mgmt.h"
#include "app_timer.h"
#include "nrf_log.h"
#include "nrf_log_ctrl.h"
#include "app_error.h"
#include "led_driver.h"
#include "ble_service.h"
#include "color_manager.h"

// 系统状态
static bool m_is_sleeping = false;
static uint32_t m_idle_count = 0;  // 以 60 秒为单位计数，30 次 = 30 分钟

// 广播超时状态
static bool m_advertising_active = false;
static uint32_t m_adv_timeout_count = 0;  // 广播超时计数，5 次 = 5 分钟

// 休眠前保存的颜色
static led_color_t m_saved_color = {255, 0, 0, 0};

// 睡眠定时器 (每分钟检查)
APP_TIMER_DEF(m_sleep_timer);

/**
 * @brief 睡眠定时器超时处理
 */
static void sleep_timer_handler(void *p_context)
{
    UNUSED_PARAMETER(p_context);

    m_idle_count++;

    // 检查广播超时
    if (m_advertising_active && !ble_service_is_connected())
    {
        m_adv_timeout_count++;
        if (m_adv_timeout_count >= 5)  // 5 分钟
        {
            NRF_LOG_INFO("Advertising timeout, stopping...");
            ble_service_advertising_stop();
            ble_service_set_auto_adv(false);  // 禁止自动重启广播
            m_advertising_active = false;
            m_adv_timeout_count = 0;
        }
    }

    // 30 次 × 60 秒 = 30 分钟无操作
    if (m_idle_count >= 30 && !ble_service_is_connected())
    {
        NRF_LOG_INFO("Auto sleep triggered (idle: %d min)", m_idle_count);
        power_manager_enter_sleep();
    }
}

void power_manager_init(void)
{
    ret_code_t err_code;
    
    // 创建睡眠定时器 (每分钟检查一次)
    err_code = app_timer_create(&m_sleep_timer,
                               APP_TIMER_MODE_REPEATED,
                               sleep_timer_handler);
    APP_ERROR_CHECK(err_code);
    
    // 启动定时器
    err_code = app_timer_start(m_sleep_timer, APP_TIMER_TICKS(60000), NULL);
    APP_ERROR_CHECK(err_code);
    
    // 初始化时设置广播状态为活跃
    m_advertising_active = true;
    m_adv_timeout_count = 0;
    
    NRF_LOG_INFO("Power manager initialized, advertising timeout enabled (5min)");
}

void power_manager_process(void)
{
    // 功耗管理在定时器中处理
}

void power_manager_enter_sleep(void)
{
    if (m_is_sleeping)
    {
        return;
    }
    
    NRF_LOG_INFO("Entering sleep mode...");
    
    // 保存当前颜色
    color_manager_get_current_color(&m_saved_color);
    
    // 关闭 LED
    led_off();
    
    // 停止 BLE 广播（如果未连接）
    if (!ble_service_is_connected())
    {
        ble_service_advertising_stop();
        ble_service_set_auto_adv(false);  // 禁止自动重启广播
        m_advertising_active = false;
    }
    
    m_is_sleeping = true;
    
    NRF_LOG_INFO("System entered sleep mode");
}

void power_manager_wakeup(void)
{
    if (!m_is_sleeping)
    {
        return;
    }
    
    NRF_LOG_INFO("Waking up from sleep...");
    
    // 恢复休眠前的颜色
    led_set_color(m_saved_color.r, m_saved_color.g, m_saved_color.b, m_saved_color.w);
    
    // 重置空闲计数
    m_idle_count = 0;
    
    m_is_sleeping = false;
    
    NRF_LOG_INFO("System woken up, LED restored");
}

void power_manager_reset_activity_timer(void)
{
    // 重置空闲计数
    m_idle_count = 0;
    
    // 如果正在休眠，唤醒系统
    if (m_is_sleeping)
    {
        power_manager_wakeup();
    }
}

void power_manager_restart_advertising(void)
{
    NRF_LOG_INFO("Restarting advertising by button press...");
    
    // 如果正在休眠，先唤醒
    if (m_is_sleeping)
    {
        power_manager_wakeup();
        return;
    }
    
    // 启动广播
    if (!ble_service_is_connected())
    {
        ble_service_set_auto_adv(true);  // 允许自动重启广播
        ble_service_advertising_start();
        m_advertising_active = true;
        m_adv_timeout_count = 0;
        m_idle_count = 0;
        NRF_LOG_INFO("Advertising restarted with 5min timeout");
    }
}

bool power_manager_is_sleeping(void)
{
    return m_is_sleeping;
}

bool power_manager_is_advertising(void)
{
    return m_advertising_active;
}
