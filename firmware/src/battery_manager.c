/**
 * @file battery_manager.c
 * @brief 电池管理模块实现
 */

#include "battery_manager.h"
#include "nrf_drv_saadc.h"
#include "nrf_log.h"
#include "app_error.h"
#include "app_timer.h"
#include "led_driver.h"
#include "power_manager.h"

// GPIO 配置
#define BATTERY_ADC_PIN         NRF_SAADC_INPUT_AIN0    // P0.02

// 分压电路参数: R1=100kΩ, R2=200kΩ
// V_adc = V_battery × R2 / (R1 + R2) = V_battery × 2/3
// V_battery = V_adc × (R1 + R2) / R2 = V_adc × 1.5
#define VOLTAGE_DIVIDER_RATIO   (3.0f / 2.0f)  // 1.5

// 电压阈值 (mV) - 4.2V 锂电池
#define BATTERY_VOLTAGE_FULL    4200    // 100%
#define BATTERY_VOLTAGE_75      3950    // 75%
#define BATTERY_VOLTAGE_50      3850    // 50%
#define BATTERY_VOLTAGE_25      3800    // 25%
#define BATTERY_VOLTAGE_10      3750    // 10%
#define BATTERY_VOLTAGE_LOW     3700    // 低电保护阈值

// 采样周期 (10秒)
#define BATTERY_SAMPLE_INTERVAL APP_TIMER_TICKS(10000)

// ADC 配置
#define ADC_REF_VOLTAGE_MV      600     // 内部参考电压: 0.6V
#define ADC_RESOLUTION          1024    // 10位分辨率
#define ADC_PRESCALER           4       // 预分频器
#define ADC_GAIN                (1.0f/6.0f)  // 增益: 1/6

// 电池状态
static uint16_t m_battery_voltage_mv = 3700;   // 默认安全值，等 ADC 首次采样后更新
static uint8_t m_battery_level_percent = 50;
static bool m_battery_low = false;
static uint8_t m_low_count = 0;                // 连续低电计数，防止单次误读

// ADC 采样缓冲区
static nrf_saadc_value_t m_adc_buffer;

// 电池电量变化回调函数
static battery_level_callback_t m_battery_level_callback = NULL;

// 定时器
APP_TIMER_DEF(m_battery_timer);

/**
 * @brief 将 ADC 值转换为电池电压 (mV)
 */
static uint16_t adc_to_voltage(nrf_saadc_value_t adc_value)
{
    // ADC 引脚电压 = ADC_value * (REF_voltage / ADC_resolution) / GAIN
    float adc_voltage = (float)adc_value * ADC_REF_VOLTAGE_MV / ADC_RESOLUTION / ADC_GAIN;
    
    // 电池电压 = ADC 引脚电压 × 分压比
    float battery_voltage = adc_voltage * VOLTAGE_DIVIDER_RATIO;
    
    return (uint16_t)battery_voltage;
}

/**
 * @brief 根据电压计算电量百分比
 */
static uint8_t voltage_to_level(uint16_t voltage_mv)
{
    if (voltage_mv >= BATTERY_VOLTAGE_FULL)
    {
        return 100;
    }
    else if (voltage_mv >= BATTERY_VOLTAGE_75)
    {
        // 线性插值: 75% ~ 100%
        return 75 + (voltage_mv - BATTERY_VOLTAGE_75) * 25 / 
               (BATTERY_VOLTAGE_FULL - BATTERY_VOLTAGE_75);
    }
    else if (voltage_mv >= BATTERY_VOLTAGE_50)
    {
        // 线性插值: 50% ~ 75%
        return 50 + (voltage_mv - BATTERY_VOLTAGE_50) * 25 / 
               (BATTERY_VOLTAGE_75 - BATTERY_VOLTAGE_50);
    }
    else if (voltage_mv >= BATTERY_VOLTAGE_25)
    {
        // 线性插值: 25% ~ 50%
        return 25 + (voltage_mv - BATTERY_VOLTAGE_25) * 25 / 
               (BATTERY_VOLTAGE_50 - BATTERY_VOLTAGE_25);
    }
    else if (voltage_mv >= BATTERY_VOLTAGE_10)
    {
        // 线性插值: 10% ~ 25%
        return 10 + (voltage_mv - BATTERY_VOLTAGE_10) * 15 / 
               (BATTERY_VOLTAGE_25 - BATTERY_VOLTAGE_10);
    }
    else if (voltage_mv >= BATTERY_VOLTAGE_LOW)
    {
        // 线性插值: 0% ~ 10%
        return (voltage_mv - BATTERY_VOLTAGE_LOW) * 10 / 
               (BATTERY_VOLTAGE_10 - BATTERY_VOLTAGE_LOW);
    }
    else
    {
        return 0;
    }
}

/**
 * @brief ADC 事件处理函数
 */
static void saadc_callback(nrf_drv_saadc_evt_t const *p_event)
{
    if (p_event->type == NRF_DRV_SAADC_EVT_DONE)
    {
        nrf_saadc_value_t adc_value = p_event->data.done.p_buffer[0];
        
        // 转换为电压
        m_battery_voltage_mv = adc_to_voltage(adc_value);
        
        // 计算电量百分比
        m_battery_level_percent = voltage_to_level(m_battery_voltage_mv);
        
        // 确保电量百分比在有效范围内
        if (m_battery_level_percent > 100)
        {
            m_battery_level_percent = 100;
        }
        
        // 检查低电状态（连续 3 次采样都低于阈值才触发，防止悬空/噪声误触发）
        if (m_battery_voltage_mv < BATTERY_VOLTAGE_LOW)
        {
            m_low_count++;
            if (m_low_count >= 3 && !m_battery_low)
            {
                m_battery_low = true;
                NRF_LOG_WARNING("Battery low! Voltage: %d mV", m_battery_voltage_mv);
                led_off();
                power_manager_enter_sleep();
            }
        }
        else
        {
            m_low_count = 0;
            m_battery_low = false;
        }
        
        NRF_LOG_DEBUG("Battery: %d mV, %d%%", m_battery_voltage_mv, m_battery_level_percent);
        
        // 通知电池电量变化
        if (m_battery_level_callback != NULL)
        {
            m_battery_level_callback(m_battery_level_percent);
        }
    }
}

/**
 * @brief 定时器超时处理
 */
static void battery_timer_handler(void *p_context)
{
    UNUSED_PARAMETER(p_context);
    battery_manager_update();
}

void battery_manager_init(void)
{
    ret_code_t err_code;

    // 配置 ADC
    nrf_drv_saadc_config_t saadc_config = NRF_DRV_SAADC_DEFAULT_CONFIG;
    err_code = nrf_drv_saadc_init(&saadc_config, saadc_callback);
    APP_ERROR_CHECK(err_code);

    // 配置 ADC 通道
    nrf_saadc_channel_config_t channel_config =
        NRF_DRV_SAADC_DEFAULT_CHANNEL_CONFIG_SE(BATTERY_ADC_PIN);
    
    err_code = nrf_drv_saadc_channel_init(0, &channel_config);
    APP_ERROR_CHECK(err_code);

    // 创建定时器
    err_code = app_timer_create(&m_battery_timer,
                               APP_TIMER_MODE_REPEATED,
                               battery_timer_handler);
    APP_ERROR_CHECK(err_code);

    // 启动定时器
    err_code = app_timer_start(m_battery_timer, BATTERY_SAMPLE_INTERVAL, NULL);
    APP_ERROR_CHECK(err_code);

    // 立即进行第一次采样
    err_code = nrf_drv_saadc_buffer_convert(&m_adc_buffer, 1);
    APP_ERROR_CHECK(err_code);
    
    err_code = nrf_drv_saadc_sample();
    APP_ERROR_CHECK(err_code);

    NRF_LOG_INFO("Battery manager initialized");
}

void battery_manager_process(void)
{
    // 电池管理在定时器中处理
}

void battery_manager_update(void)
{
    ret_code_t err_code;
    
    err_code = nrf_drv_saadc_buffer_convert(&m_adc_buffer, 1);
    APP_ERROR_CHECK(err_code);
    
    err_code = nrf_drv_saadc_sample();
    APP_ERROR_CHECK(err_code);
}

uint16_t battery_manager_get_voltage(void)
{
    return m_battery_voltage_mv;
}

uint8_t battery_manager_get_level(void)
{
    return m_battery_level_percent;
}

bool battery_manager_is_low(void)
{
    return m_battery_low;
}

void battery_manager_register_callback(battery_level_callback_t callback)
{
    m_battery_level_callback = callback;
}
