/**
 * @file main.c
 * @brief 应援棒控制器固件主程序（稳定长连接版本）
 *
 * 硬件平台: nRF52832
 * SDK: nRF5 SDK 17.1.0
 * SoftDevice: S132 v7.x
 * 
 * 特性:
 * - 稳定的 BLE 长连接（保守连接参数 + 心跳机制）
 * - SK6812 RGBW LED 驱动
 * - 按键颜色切换
 * - 50 个预设颜色
 * - 电池电量监测
 * - Flash 持久化存储
 * - 30 分钟自动休眠
 */

#include <stdint.h>
#include <string.h>
#include "nordic_common.h"
#include "nrf.h"
#include "nrf_sdh.h"
#include "nrf_sdh_ble.h"
#include "nrf_sdh_soc.h"
#include "nrf_sdm.h"
#include "nrf_pwr_mgmt.h"
#include "app_timer.h"
#include "app_error.h"
#include "nrf_log.h"
#include "nrf_log_ctrl.h"
#include "nrf_log_default_backends.h"

#include "led_driver.h"
#include "button_manager.h"
#include "ble_service.h"
#include "battery_manager.h"
#include "storage_manager.h"
#include "power_manager.h"
#include "color_manager.h"

#define APP_BLE_CONN_CFG_TAG    1

static void log_init(void)
{
    ret_code_t err_code = NRF_LOG_INIT(NULL);
    APP_ERROR_CHECK(err_code);
    NRF_LOG_DEFAULT_BACKENDS_INIT();

    // 读取 SoftDevice FWID
    uint16_t sd_fwid = SD_FWID_GET(MBR_SIZE);

    NRF_LOG_INFO("=================================");
    NRF_LOG_INFO("  HikariStick Firmware: %s", SOFTWARE_VERSION);
    NRF_LOG_INFO("  Platform: nRF52832");
    NRF_LOG_INFO("  BLE: Stable Long Connection");
    NRF_LOG_INFO("  SoftDevice FWID: 0x%04X", sd_fwid);
    NRF_LOG_INFO("=================================");
}

static void timers_init(void)
{
    ret_code_t err_code = app_timer_init();
    APP_ERROR_CHECK(err_code);
}

static void power_management_init(void)
{
    ret_code_t err_code = nrf_pwr_mgmt_init();
    APP_ERROR_CHECK(err_code);
}

static void ble_stack_init(void)
{
    ret_code_t err_code;

    err_code = nrf_sdh_enable_request();
    APP_ERROR_CHECK(err_code);

    uint32_t ram_start = 0;
    err_code = nrf_sdh_ble_default_cfg_set(APP_BLE_CONN_CFG_TAG, &ram_start);
    APP_ERROR_CHECK(err_code);

    err_code = nrf_sdh_ble_enable(&ram_start);
    APP_ERROR_CHECK(err_code);

    NRF_LOG_INFO("BLE stack initialized, RAM start: 0x%08X", ram_start);
}

static void idle_state_handle(void)
{
    if (NRF_LOG_PROCESS() == false)
    {
        nrf_pwr_mgmt_run();
    }
}

void app_error_fault_handler(uint32_t id, uint32_t pc, uint32_t info)
{
    static uint32_t        s_err_code = 0;
    static uint32_t        s_line     = 0;
    static const uint8_t * s_file     = NULL;
    (void)s_file;

    if (id == NRF_FAULT_ID_SDK_ERROR && info >= 0x20000000u)
    {
        error_info_t const * p_err = (error_info_t const *)info;
        s_err_code = p_err->err_code;
        s_line     = p_err->line_num;
        s_file     = p_err->p_file_name;
    }
    else
    {
        s_err_code = info;
    }

    __disable_irq();
    led_driver_abort();

    NRF_LOG_ERROR("!!! CRASH id=0x%X info_raw=0x%X err=0x%X line=%d",
                  id, info, s_err_code, s_line);
    NRF_LOG_FINAL_FLUSH();

    uint32_t blink_count = 0;
    while (true)
    {
        if (blink_count % 5 == 0)
        {
            NRF_LOG_ERROR("CRASH err=0x%X line=%d (blink#%d)",
                          s_err_code, s_line, blink_count);
            NRF_LOG_FINAL_FLUSH();
        }
        blink_count++;

        led_set_color(0, 0, 255, 0);
        volatile uint32_t d = 800000; while(d--) {}
        led_set_color(0, 0, 0, 0);
        volatile uint32_t d2 = 800000; while(d2--) {}
    }
}

void assert_nrf_callback(uint16_t line_num, const uint8_t *p_file_name)
{
    app_error_handler(0xDEADBEEF, line_num, p_file_name);
}

int main(void)
{
    log_init();
    timers_init();
    power_management_init();

    // LED 和颜色管理器提前初始化，不依赖 BLE
    led_init();
    color_manager_init();
    NRF_LOG_INFO("[STEP 1] led+color init OK, BLE stack starting...");

    ble_stack_init();
    NRF_LOG_INFO("[STEP 2] ble_stack_init OK");

    NRF_LOG_INFO("[STEP 3] button_manager_init...");
    button_manager_init();

    NRF_LOG_INFO("[STEP 4] storage_manager_init...");
    storage_manager_init();

    NRF_LOG_INFO("[STEP 5] battery_manager_init...");
    battery_manager_init();

    NRF_LOG_INFO("[STEP 6] ble_service_init...");
    ble_service_init();

    NRF_LOG_INFO("[STEP 7] power_manager_init...");
    power_manager_init();

    NRF_LOG_INFO("[STEP 8] all modules OK, loading config...");

    // 恢复上次颜色（Flash 有记录）或使用默认（索引 0 = 红色）
    if (!storage_manager_load_config())
    {
        // 没有保存记录：显示默认颜色（索引 0）
        color_manager_apply_current();
    }

    NRF_LOG_INFO("[STEP 9] Application ready. Entering main loop...");

    while (1)
    {
        ble_service_process();
        ble_service_process_pending_save();
        button_manager_process();
        led_driver_process();
        battery_manager_process();
        power_manager_process();
        idle_state_handle();
    }
}
