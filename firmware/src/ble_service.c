/**
 * @file ble_service.c
 * @brief BLE 服务模块实现
 */

#include "ble_service.h"
#include "nrf_log.h"
#include "app_error.h"
#include "app_timer.h"
#include "ble_advertising.h"
#include "ble_conn_params.h"
#include "nrf_sdh_ble.h"
#include "nrf_ble_gatt.h"
#include "nrf_ficr.h"
#include "nrf_power.h"
#include "led_driver.h"
#include "color_manager.h"
#include "storage_manager.h"
#include "battery_manager.h"
#include <string.h>
#include <stdio.h>

/**
 * @brief 进入 DFU 模式
 * 
 * 使用 GPREGRET 寄存器方法进入 DFU 模式
 * Bootloader 需要启用 NRF_BL_DFU_ENTER_METHOD_GPREGRET
 */
static void enter_dfu_mode(void)
{
    NRF_LOG_INFO("=== Entering DFU mode ===");
    
    // 使用 SoftDevice API 设置 GPREGRET（0xB1 是 Nordic Bootloader 的 DFU 标志）
    sd_power_gpregret_clr(0, 0xFF);
    sd_power_gpregret_set(0, 0xB1);
    
    // 触发系统复位
    NVIC_SystemReset();
}

// BLE 配置参数
#define DEVICE_NAME_PREFIX              "HikariStick-"
#define DEVICE_NAME_MAX_LEN             20          // "HikariStick-XXXX" = 15 字符
#define APP_BLE_CONN_CFG_TAG            1
#define APP_BLE_OBSERVER_PRIO           3

#define APP_ADV_INTERVAL                160         // 100ms (单位: 0.625ms)
#define APP_ADV_DURATION                0           // 0 = 无限广播

// 连接参数 - 优化为保守值确保连接稳定（从 nrf52832-new 移植）
#define MIN_CONN_INTERVAL               MSEC_TO_UNITS(50, UNIT_1_25_MS)    // 50ms
#define MAX_CONN_INTERVAL               MSEC_TO_UNITS(100, UNIT_1_25_MS)   // 100ms
#define SLAVE_LATENCY                   4                                   // 允许4次跳过
#define CONN_SUP_TIMEOUT                MSEC_TO_UNITS(4000, UNIT_10_MS)    // 4秒

// 连接参数更新设置（从 nrf52832-new 移植 - 稳定连接逻辑）
#define FIRST_CONN_PARAMS_UPDATE_DELAY  APP_TIMER_TICKS(10000)  // 10秒后首次更新
#define NEXT_CONN_PARAMS_UPDATE_DELAY   APP_TIMER_TICKS(30000)  // 每30秒尝试更新
#define MAX_CONN_PARAMS_UPDATE_COUNT    3

// 心跳定时器 - 定期发送数据保持连接活跃（从 nrf52832-new 移植）
#define HEARTBEAT_INTERVAL              APP_TIMER_TICKS(2000)   // 2秒

// 延迟保存配置（避免频繁写入 Flash）
#define SAVE_DELAY_MS                   2000    // 2秒后保存
APP_TIMER_DEF(m_save_timer);
static volatile bool m_save_pending = false;

// 心跳定时器（从 nrf52832-new 移植 - 保持连接活跃）
APP_TIMER_DEF(m_heartbeat_timer_id);

// 连接统计（从 nrf52832-new 移植）
static uint32_t m_conn_count = 0;
static uint32_t m_disconn_count = 0;
static uint32_t m_heartbeat_count = 0;
static uint32_t m_last_conn_interval = 0;
static uint32_t m_last_slave_latency = 0;
static uint32_t m_last_sup_timeout = 0;

// 全局变量
static ble_lightstick_service_t m_lightstick_service;
static uint16_t m_conn_handle = BLE_CONN_HANDLE_INVALID;
static bool m_auto_adv_enabled = true;  // 是否允许自动重启广播
static uint8_t m_brightness_init = 255; // 亮度初始值

NRF_BLE_GATT_DEF(m_gatt);
BLE_ADVERTISING_DEF(m_advertising);

// BLE 事件处理函数（前向声明，用于 Observer）
static void ble_evt_handler(ble_evt_t const *p_ble_evt, void *p_context);
static void ble_service_update_presets(void);

// 延迟保存定时器回调
static void save_timer_handler(void *p_context)
{
    UNUSED_PARAMETER(p_context);
    // 不在定时器回调中执行保存，只设置标志
    // 保存操作将在主循环中执行
}

// 心跳定时器处理函数（从 nrf52832-new 移植 - 定期发送数据保持连接）
static void heartbeat_timer_handler(void *p_context)
{
    UNUSED_PARAMETER(p_context);

    if (m_conn_handle != BLE_CONN_HANDLE_INVALID)
    {
        m_heartbeat_count++;

        // 每 10 次心跳（20 秒）记录连接状态
        if (m_heartbeat_count % 10 == 0)
        {
            NRF_LOG_INFO("Heartbeat #%u, Conn interval: %u ms, Latency: %u, Timeout: %u ms",
                         m_heartbeat_count,
                         m_last_conn_interval * 125 / 100,
                         m_last_slave_latency,
                         m_last_sup_timeout * 10);
        }
    }
}

// 启动延迟保存
static void schedule_save(void)
{
    m_save_pending = true;
    app_timer_start(m_save_timer, APP_TIMER_TICKS(SAVE_DELAY_MS), NULL);
}

// 处理待保存的数据（在主循环中调用）
void ble_service_process_pending_save(void)
{
    if (m_save_pending && m_conn_handle == BLE_CONN_HANDLE_INVALID)
    {
        m_save_pending = false;
        storage_manager_save_config();
        NRF_LOG_INFO("Config saved in main loop");
    }
}

// 在全局作用域注册 BLE 事件观察者（必须在全局，不能在函数内）
NRF_SDH_BLE_OBSERVER(m_ble_observer, APP_BLE_OBSERVER_PRIO, ble_evt_handler, NULL);

/**
 * @brief GAP 参数初始化
 */
static void gap_params_init(void)
{
    ret_code_t err_code;
    ble_gap_conn_params_t gap_conn_params;
    ble_gap_conn_sec_mode_t sec_mode;

    BLE_GAP_CONN_SEC_MODE_SET_OPEN(&sec_mode);

    // 从 FICR 读取设备地址，生成 "HikariStick-XXXX" 名称
    // MAC 地址格式: XX:XX:XX:XX:XX:XX
    // DEVICEADDR[1] 存储高位字节, DEVICEADDR[0] 存储低位字节
    // 取 DEVICEADDR[0] 的低 16 位 = MAC 地址最后 2 字节 (XX:XX 的部分)
    char device_name[DEVICE_NAME_MAX_LEN];
    uint16_t mac_suffix = (uint16_t)(NRF_FICR->DEVICEADDR[0] & 0xFFFFu);
    snprintf(device_name, sizeof(device_name), "%s%04X", DEVICE_NAME_PREFIX, mac_suffix);

    err_code = sd_ble_gap_device_name_set(&sec_mode,
                                          (const uint8_t *)device_name,
                                          strlen(device_name));
    APP_ERROR_CHECK(err_code);

    // 设置 PPCP 参数（从 nrf52832-new 移植 - 保守参数确保连接稳定）
    memset(&gap_conn_params, 0, sizeof(gap_conn_params));
    gap_conn_params.min_conn_interval = MIN_CONN_INTERVAL;
    gap_conn_params.max_conn_interval = MAX_CONN_INTERVAL;
    gap_conn_params.slave_latency     = SLAVE_LATENCY;
    gap_conn_params.conn_sup_timeout  = CONN_SUP_TIMEOUT;

    err_code = sd_ble_gap_ppcp_set(&gap_conn_params);
    APP_ERROR_CHECK(err_code);

    NRF_LOG_INFO("GAP params initialized (name: %s)", (uint32_t)device_name);
    NRF_LOG_INFO("GAP PPCP: interval=%u-%u ms, latency=%u, timeout=%u ms",
                 MIN_CONN_INTERVAL * 125 / 100,
                 MAX_CONN_INTERVAL * 125 / 100,
                 SLAVE_LATENCY,
                 CONN_SUP_TIMEOUT * 10);
}

/**
 * @brief GATT 初始化
 */
static void gatt_init(void)
{
    ret_code_t err_code = nrf_ble_gatt_init(&m_gatt, NULL);
    APP_ERROR_CHECK(err_code);

    NRF_LOG_INFO("GATT initialized");
}

/**
 * @brief 自定义服务初始化
 */
static void services_init(void)
{
    ret_code_t err_code;
    ble_uuid_t ble_uuid;
    // 标准 Bluetooth SIG 128-bit Base UUID: 00000000-0000-1000-8000-00805F9B34FB
    ble_uuid128_t base_uuid = {{0xFB, 0x34, 0x9B, 0x5F, 0x80, 0x00, 0x00, 0x80,
                               0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}};

    m_lightstick_service.conn_handle = BLE_CONN_HANDLE_INVALID;

    // 添加自定义 UUID base
    err_code = sd_ble_uuid_vs_add(&base_uuid, &m_lightstick_service.uuid_type);
    APP_ERROR_CHECK(err_code);

    // 添加服务
    ble_uuid.type = m_lightstick_service.uuid_type;
    ble_uuid.uuid = CUSTOM_SERVICE_UUID;

    err_code = sd_ble_gatts_service_add(BLE_GATTS_SRVC_TYPE_PRIMARY,
                                        &ble_uuid,
                                        &m_lightstick_service.service_handle);
    APP_ERROR_CHECK(err_code);

    // 添加 FFF1 特征（Write - 设置颜色）
    ble_gatts_char_md_t char_md;
    ble_gatts_attr_t attr_char_value;
    ble_gatts_attr_md_t attr_md;

    memset(&char_md, 0, sizeof(char_md));
    char_md.char_props.write = 1;
    char_md.char_props.write_wo_resp = 1;

    memset(&attr_md, 0, sizeof(attr_md));
    BLE_GAP_CONN_SEC_MODE_SET_OPEN(&attr_md.read_perm);
    BLE_GAP_CONN_SEC_MODE_SET_OPEN(&attr_md.write_perm);
    attr_md.vloc = BLE_GATTS_VLOC_STACK;

    memset(&attr_char_value, 0, sizeof(attr_char_value));
    ble_uuid.type = m_lightstick_service.uuid_type;
    ble_uuid.uuid = CHAR_COLOR_WRITE_UUID;
    attr_char_value.p_uuid = &ble_uuid;
    attr_char_value.p_attr_md = &attr_md;
    attr_char_value.init_len = 4;
    attr_char_value.max_len = 4;

    err_code = sd_ble_gatts_characteristic_add(m_lightstick_service.service_handle,
                                               &char_md,
                                               &attr_char_value,
                                               &m_lightstick_service.color_write_handles);
    APP_ERROR_CHECK(err_code);

    // 添加 FFF2 特征（Read + Notify - 当前颜色）
    // Notify 允许固件在按钮切换颜色时主动通知 APP
    memset(&char_md, 0, sizeof(char_md));
    char_md.char_props.read = 1;
    char_md.char_props.notify = 1;
    char_md.p_cccd_md = &attr_md;  // CCCD 用于订阅通知

    // 重新初始化 attr_md 为读/写权限（CCCD 需要写权限）
    memset(&attr_md, 0, sizeof(attr_md));
    BLE_GAP_CONN_SEC_MODE_SET_OPEN(&attr_md.read_perm);
    BLE_GAP_CONN_SEC_MODE_SET_OPEN(&attr_md.write_perm);
    attr_md.vloc = BLE_GATTS_VLOC_STACK;

    ble_uuid.uuid = CHAR_COLOR_READ_UUID;
    attr_char_value.p_uuid = &ble_uuid;

    err_code = sd_ble_gatts_characteristic_add(m_lightstick_service.service_handle,
                                               &char_md,
                                               &attr_char_value,
                                               &m_lightstick_service.color_read_handles);
    APP_ERROR_CHECK(err_code);

    // 添加 FFF3 特征（Read - 电池电量）
    ble_uuid.uuid = CHAR_BATTERY_READ_UUID;
    attr_char_value.init_len = 1;
    attr_char_value.max_len = 1;
    attr_char_value.p_uuid = &ble_uuid;

    err_code = sd_ble_gatts_characteristic_add(m_lightstick_service.service_handle,
                                               &char_md,
                                               &attr_char_value,
                                               &m_lightstick_service.battery_handles);
    APP_ERROR_CHECK(err_code);

    // 添加 FFF4 特征（Write - 设置预设颜色，单条/批量）
    memset(&char_md, 0, sizeof(char_md));
    char_md.char_props.write = 1;
    char_md.char_props.write_wo_resp = 1;

    memset(&attr_md, 0, sizeof(attr_md));
    BLE_GAP_CONN_SEC_MODE_SET_OPEN(&attr_md.read_perm);
    BLE_GAP_CONN_SEC_MODE_SET_OPEN(&attr_md.write_perm);
    attr_md.vloc = BLE_GATTS_VLOC_STACK;

    memset(&attr_char_value, 0, sizeof(attr_char_value));
    ble_uuid.uuid = CHAR_PRESET_WRITE_UUID;
    attr_char_value.p_uuid = &ble_uuid;
    attr_char_value.p_attr_md = &attr_md;
    attr_char_value.init_len = 0;
    attr_char_value.max_len = 255;  // 最大可批量写入 51 个预设 (51*5=255)

    err_code = sd_ble_gatts_characteristic_add(m_lightstick_service.service_handle,
                                               &char_md,
                                               &attr_char_value,
                                               &m_lightstick_service.preset_write_handles);
    APP_ERROR_CHECK(err_code);

    // 添加 FFF5 特征（Read - 读取全部50个预设颜色）
    memset(&char_md, 0, sizeof(char_md));
    char_md.char_props.read = 1;

    memset(&attr_md, 0, sizeof(attr_md));
    BLE_GAP_CONN_SEC_MODE_SET_OPEN(&attr_md.read_perm);
    BLE_GAP_CONN_SEC_MODE_SET_OPEN(&attr_md.write_perm);
    attr_md.vloc = BLE_GATTS_VLOC_STACK;

    memset(&attr_char_value, 0, sizeof(attr_char_value));
    ble_uuid.uuid = CHAR_PRESET_READ_UUID;
    attr_char_value.p_uuid = &ble_uuid;
    attr_char_value.p_attr_md = &attr_md;
    attr_char_value.init_len = 0;
    attr_char_value.max_len = 200;  // 50 * 4 bytes

    err_code = sd_ble_gatts_characteristic_add(m_lightstick_service.service_handle,
                                               &char_md,
                                               &attr_char_value,
                                               &m_lightstick_service.preset_read_handles);
    APP_ERROR_CHECK(err_code);

    // 添加 FFF6 特征（Read - 软件版本号）
    memset(&char_md, 0, sizeof(char_md));
    char_md.char_props.read = 1;

    memset(&attr_md, 0, sizeof(attr_md));
    BLE_GAP_CONN_SEC_MODE_SET_OPEN(&attr_md.read_perm);
    attr_md.vloc = BLE_GATTS_VLOC_STACK;

    memset(&attr_char_value, 0, sizeof(attr_char_value));
    ble_uuid.uuid = CHAR_VERSION_READ_UUID;
    attr_char_value.p_uuid = &ble_uuid;
    attr_char_value.p_attr_md = &attr_md;
    attr_char_value.init_len = strlen(SOFTWARE_VERSION);
    attr_char_value.max_len = 20;  // 版本号最大长度
    attr_char_value.p_value = (uint8_t *)SOFTWARE_VERSION;

    err_code = sd_ble_gatts_characteristic_add(m_lightstick_service.service_handle,
                                               &char_md,
                                               &attr_char_value,
                                               &m_lightstick_service.version_handles);
    APP_ERROR_CHECK(err_code);

    // 添加 FFF7 特征（Write + Write Without Response - DFU 控制，写入 "DFU" 进入升级模式）
    memset(&char_md, 0, sizeof(char_md));
    char_md.char_props.write = 1;
    char_md.char_props.write_wo_resp = 1;

    memset(&attr_md, 0, sizeof(attr_md));
    BLE_GAP_CONN_SEC_MODE_SET_OPEN(&attr_md.read_perm);
    BLE_GAP_CONN_SEC_MODE_SET_OPEN(&attr_md.write_perm);
    attr_md.vloc = BLE_GATTS_VLOC_STACK;

    memset(&attr_char_value, 0, sizeof(attr_char_value));
    ble_uuid.uuid = CHAR_DFU_CONTROL_UUID;
    attr_char_value.p_uuid = &ble_uuid;
    attr_char_value.p_attr_md = &attr_md;
    attr_char_value.init_len = 0;
    attr_char_value.max_len = 3;  // "DFU" = 3 bytes

    err_code = sd_ble_gatts_characteristic_add(m_lightstick_service.service_handle,
                                               &char_md,
                                               &attr_char_value,
                                               &m_lightstick_service.dfu_control_handles);
    APP_ERROR_CHECK(err_code);

    // 添加 FFF8 特征（Write - 亮度控制）
    memset(&char_md, 0, sizeof(char_md));
    char_md.char_props.write = 1;
    char_md.char_props.write_wo_resp = 1;

    memset(&attr_md, 0, sizeof(attr_md));
    BLE_GAP_CONN_SEC_MODE_SET_OPEN(&attr_md.read_perm);
    BLE_GAP_CONN_SEC_MODE_SET_OPEN(&attr_md.write_perm);
    attr_md.vloc = BLE_GATTS_VLOC_STACK;

    memset(&attr_char_value, 0, sizeof(attr_char_value));
    ble_uuid.uuid = CHAR_BRIGHTNESS_UUID;
    attr_char_value.p_uuid = &ble_uuid;
    attr_char_value.p_attr_md = &attr_md;
    attr_char_value.init_len = 1;
    attr_char_value.max_len = 1;
    attr_char_value.p_value = &m_brightness_init;

    err_code = sd_ble_gatts_characteristic_add(m_lightstick_service.service_handle,
                                               &char_md,
                                               &attr_char_value,
                                               &m_lightstick_service.brightness_handles);
    APP_ERROR_CHECK(err_code);

    // 添加 FFF9 特征（Write - 爆闪控制）
    memset(&char_md, 0, sizeof(char_md));
    char_md.char_props.write = 1;
    char_md.char_props.write_wo_resp = 1;

    memset(&attr_md, 0, sizeof(attr_md));
    BLE_GAP_CONN_SEC_MODE_SET_OPEN(&attr_md.read_perm);
    BLE_GAP_CONN_SEC_MODE_SET_OPEN(&attr_md.write_perm);
    attr_md.vloc = BLE_GATTS_VLOC_STACK;

    memset(&attr_char_value, 0, sizeof(attr_char_value));
    ble_uuid.uuid = CHAR_STROBE_UUID;
    attr_char_value.p_uuid = &ble_uuid;
    attr_char_value.p_attr_md = &attr_md;
    attr_char_value.init_len = 0;
    attr_char_value.max_len = 2;  // [mode, freq]

    err_code = sd_ble_gatts_characteristic_add(m_lightstick_service.service_handle,
                                               &char_md,
                                               &attr_char_value,
                                               &m_lightstick_service.strobe_handles);
    APP_ERROR_CHECK(err_code);

    NRF_LOG_INFO("Custom service initialized (UUID: 0x%04X, 9 chars, version: %s)", 
                 CUSTOM_SERVICE_UUID, (uint32_t)SOFTWARE_VERSION);
}

/**
 * @brief 广播初始化
 */
static void advertising_init(void)
{
    ret_code_t err_code;
    ble_advertising_init_t init;

    memset(&init, 0, sizeof(init));

    init.advdata.name_type = BLE_ADVDATA_FULL_NAME;
    init.advdata.include_appearance = false;
    init.advdata.flags = BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE;

    // 在广播数据中包含服务 UUID
    static ble_uuid_t adv_uuids[1];
    adv_uuids[0].type = m_lightstick_service.uuid_type;
    adv_uuids[0].uuid = CUSTOM_SERVICE_UUID;
    init.advdata.uuids_complete.uuid_cnt = 1;
    init.advdata.uuids_complete.p_uuids = adv_uuids;

    init.config.ble_adv_fast_enabled = true;
    init.config.ble_adv_fast_interval = APP_ADV_INTERVAL;
    init.config.ble_adv_fast_timeout = APP_ADV_DURATION;

    err_code = ble_advertising_init(&m_advertising, &init);
    APP_ERROR_CHECK(err_code);

    ble_advertising_conn_cfg_tag_set(&m_advertising, APP_BLE_CONN_CFG_TAG);
    
    NRF_LOG_INFO("Advertising initialized (interval: %d ms)", 
                 APP_ADV_INTERVAL * 625 / 1000);
}

#if NRF_BLE_CONN_PARAMS_ENABLED
/**
 * @brief 连接参数事件处理（从 nrf52832-new 移植）
 */
static void on_conn_params_evt(ble_conn_params_evt_t *p_evt)
{
    if (p_evt->evt_type == BLE_CONN_PARAMS_EVT_FAILED)
    {
        NRF_LOG_WARNING("Connection parameters negotiation failed!");
        // 不要因为参数协商失败就断开连接（从 nrf52832-new 移植）
    }
    else if (p_evt->evt_type == BLE_CONN_PARAMS_EVT_SUCCEEDED)
    {
        NRF_LOG_INFO("Connection parameters negotiation succeeded!");
    }
}

/**
 * @brief 连接参数错误处理（从 nrf52832-new 移植）
 */
static void conn_params_error_handler(uint32_t nrf_error)
{
    APP_ERROR_HANDLER(nrf_error);
}

/**
 * @brief 连接参数初始化
 */
static void conn_params_init(void)
{
    ret_code_t err_code;
    ble_conn_params_init_t cp_init;

    memset(&cp_init, 0, sizeof(cp_init));

    cp_init.p_conn_params = NULL;
    cp_init.first_conn_params_update_delay = FIRST_CONN_PARAMS_UPDATE_DELAY;  // 10秒后首次更新
    cp_init.next_conn_params_update_delay  = NEXT_CONN_PARAMS_UPDATE_DELAY;   // 每30秒尝试更新
    cp_init.max_conn_params_update_count   = MAX_CONN_PARAMS_UPDATE_COUNT;
    cp_init.start_on_notify_cccd_handle    = BLE_GATT_HANDLE_INVALID;
    cp_init.disconnect_on_fail             = false;  // 不因参数失败断开（从 nrf52832-new 移植）
    cp_init.evt_handler                    = on_conn_params_evt;
    cp_init.error_handler                  = conn_params_error_handler;

    err_code = ble_conn_params_init(&cp_init);
    // 忽略错误，因为连接参数更新是可选的
    if (err_code != NRF_SUCCESS)
    {
        NRF_LOG_WARNING("Connection params init warning: 0x%X", err_code);
    }

    NRF_LOG_INFO("Connection parameters initialized");
}
#endif

/**
 * @brief BLE 事件处理函数
 */
static void ble_evt_handler(ble_evt_t const *p_ble_evt, void *p_context)
{
    UNUSED_PARAMETER(p_context);

    switch (p_ble_evt->header.evt_id)
    {
        case BLE_GAP_EVT_CONNECTED:
            m_conn_count++;
            NRF_LOG_INFO("BLE Connected! Connection #%u", m_conn_count);
            m_conn_handle = p_ble_evt->evt.gap_evt.conn_handle;
            m_lightstick_service.conn_handle = m_conn_handle;

            // 记录连接参数（从 nrf52832-new 移植）
            {
                ble_gap_conn_params_t const *p_conn_params =
                    &p_ble_evt->evt.gap_evt.params.connected.conn_params;
                m_last_conn_interval = p_conn_params->max_conn_interval;
                m_last_slave_latency = p_conn_params->slave_latency;
                m_last_sup_timeout = p_conn_params->conn_sup_timeout;

                NRF_LOG_INFO("Initial params: interval=%u ms, latency=%u, timeout=%u ms",
                             m_last_conn_interval * 125 / 100,
                             m_last_slave_latency,
                             m_last_sup_timeout * 10);
            }

            // 启动心跳定时器（从 nrf52832-new 移植 - 保持连接活跃）
            app_timer_start(m_heartbeat_timer_id, HEARTBEAT_INTERVAL, NULL);
            m_heartbeat_count = 0;

            // 连接后立即更新当前颜色特征值（修复 APP 无法读取当前颜色的问题）
            {
                led_color_t current_color;
                color_manager_get_current_color(&current_color);
                ble_service_update_color(current_color.r, current_color.g, current_color.b, current_color.w);
                NRF_LOG_INFO("Initial color synced: R=%d G=%d B=%d W=%d",
                             current_color.r, current_color.g, current_color.b, current_color.w);
            }

            // 连接后立即准备 FFF5 预设数据
            ble_service_update_presets();
            break;

        case BLE_GAP_EVT_DISCONNECTED:
        {
            m_disconn_count++;
            uint8_t reason = p_ble_evt->evt.gap_evt.params.disconnected.reason;
            NRF_LOG_INFO("BLE Disconnected (reason=0x%02X), Total disconnects: %u",
                         reason, m_disconn_count);

            // 停止心跳定时器（从 nrf52832-new 移植）
            app_timer_stop(m_heartbeat_timer_id);

            // 停止延迟保存定时器
            app_timer_stop(m_save_timer);

            // 如果有待保存的数据，现在保存
            if (m_save_pending)
            {
                m_save_pending = false;
                storage_manager_save_config();
                NRF_LOG_INFO("Config saved on disconnect");
            }

            m_conn_handle = BLE_CONN_HANDLE_INVALID;
            m_lightstick_service.conn_handle = BLE_CONN_HANDLE_INVALID;

            // 断连时停止爆闪
            led_strobe_stop();

            // 重新开始广播（仅在允许时）
            if (m_auto_adv_enabled)
            {
                ble_service_advertising_start();
            }
            break;
        }

        case BLE_GAP_EVT_CONN_PARAM_UPDATE:
        {
            // 连接参数更新事件（从 nrf52832-new 移植）
            ble_gap_conn_params_t const *p_conn_params =
                &p_ble_evt->evt.gap_evt.params.conn_param_update.conn_params;
            m_last_conn_interval = p_conn_params->max_conn_interval;
            m_last_slave_latency = p_conn_params->slave_latency;
            m_last_sup_timeout = p_conn_params->conn_sup_timeout;

            NRF_LOG_INFO("Params updated: interval=%u ms, latency=%u, timeout=%u ms",
                         m_last_conn_interval * 125 / 100,
                         m_last_slave_latency,
                         m_last_sup_timeout * 10);
            break;
        }

        case BLE_GAP_EVT_PHY_UPDATE_REQUEST:
        {
            // PHY 更新请求（从 nrf52832-new 移植）
            NRF_LOG_DEBUG("PHY update request.");
            ble_gap_phys_t const phys =
            {
                .rx_phys = BLE_GAP_PHY_AUTO,
                .tx_phys = BLE_GAP_PHY_AUTO,
            };
            sd_ble_gap_phy_update(p_ble_evt->evt.gap_evt.conn_handle, &phys);
            break;
        }

        case BLE_GAP_EVT_TIMEOUT:
            // 广播超时，重新广播（仅在允许时）
            NRF_LOG_INFO("GAP timeout, src: %d", p_ble_evt->evt.gap_evt.params.timeout.src);
            if (m_auto_adv_enabled)
            {
                ble_service_advertising_start();
            }
            break;

        case BLE_GATTC_EVT_TIMEOUT:
            NRF_LOG_DEBUG("GATT Client Timeout.");
            break;

        case BLE_GATTS_EVT_TIMEOUT:
            NRF_LOG_DEBUG("GATT Server Timeout.");
            break;

        case BLE_GATTS_EVT_WRITE:
        {
            ble_gatts_evt_write_t const *p_evt_write = &p_ble_evt->evt.gatts_evt.params.write;

            // 处理颜色写入 (FFF1)
            if (p_evt_write->handle == m_lightstick_service.color_write_handles.value_handle)
            {
                if (p_evt_write->len == 4)
                {
                    uint8_t r = p_evt_write->data[0];
                    uint8_t g = p_evt_write->data[1];
                    uint8_t b = p_evt_write->data[2];
                    uint8_t w = p_evt_write->data[3];

                    NRF_LOG_INFO("BLE received color: R=%d, G=%d, B=%d, W=%d", r, g, b, w);

                    // 应用颜色校正流水线
                    uint8_t r_corr, g_corr, b_corr, w_corr;
                    led_color_correct(r, g, b, w, &r_corr, &g_corr, &b_corr, &w_corr);
                    NRF_LOG_INFO("Color corrected: R=%d, G=%d, B=%d, W=%d", r_corr, g_corr, b_corr, w_corr);

                    // 更新 LED 颜色（使用校正后的颜色）
                    led_set_color(r_corr, g_corr, b_corr, w_corr);

                    // 更新颜色管理器中的当前颜色（使用原始颜色，便于 APP 显示）
                    // 将自定义颜色写入索引 0 位置
                    color_manager_set_color(0, r, g, b, w);
                    color_manager_set_index(0);

                    // 更新当前颜色特征值 (FFF2) - 使用原始颜色，确保 APP 能读取到正确颜色
                    ble_service_update_color(r, g, b, w);

                    // 延迟保存到 Flash（避免频繁写入）
                    schedule_save();
                }
            }
            // 处理预设写入 (FFF4): 格式 [index, R, G, B, W] x N
            else if (p_evt_write->handle == m_lightstick_service.preset_write_handles.value_handle)
            {
                if (p_evt_write->len >= 5 && (p_evt_write->len % 5) == 0)
                {
                    uint8_t count = p_evt_write->len / 5;
                    NRF_LOG_INFO("BLE preset write: %d preset(s)", count);

                    for (uint8_t i = 0; i < count; i++)
                    {
                        uint8_t offset = i * 5;
                        uint8_t idx = p_evt_write->data[offset];
                        uint8_t r  = p_evt_write->data[offset + 1];
                        uint8_t g  = p_evt_write->data[offset + 2];
                        uint8_t b  = p_evt_write->data[offset + 3];
                        uint8_t w  = p_evt_write->data[offset + 4];

                        color_manager_set_color(idx, r, g, b, w);
                        NRF_LOG_INFO("  Preset[%d] = R=%d G=%d B=%d W=%d", idx, r, g, b, w);
                    }

                    // 延迟保存到 Flash（避免频繁写入）
                    schedule_save();

                    // 更新 FFF5 读取数据
                    ble_service_update_presets();
                }
            }
            // 处理 DFU 控制写入 (FFF7): 写入 "DFU" 进入升级模式
            else if (p_evt_write->handle == m_lightstick_service.dfu_control_handles.value_handle)
            {
                if (p_evt_write->len == 3 && 
                    p_evt_write->data[0] == 'D' && 
                    p_evt_write->data[1] == 'F' && 
                    p_evt_write->data[2] == 'U')
                {
                    NRF_LOG_INFO("DFU command received, entering DFU mode...");
                    enter_dfu_mode();
                }
            }
            // 处理亮度写入 (FFF8): 1 字节 0-255
            else if (p_evt_write->handle == m_lightstick_service.brightness_handles.value_handle)
            {
                if (p_evt_write->len >= 1)
                {
                    uint8_t brightness = p_evt_write->data[0];
                    NRF_LOG_INFO("Brightness set: %d", brightness);
                    led_set_brightness(brightness);
                }
            }
            // 处理爆闪控制写入 (FFF9): [mode, freq]
            else if (p_evt_write->handle == m_lightstick_service.strobe_handles.value_handle)
            {
                if (p_evt_write->len >= 1)
                {
                    uint8_t mode = p_evt_write->data[0];
                    uint8_t freq = (p_evt_write->len >= 2) ? p_evt_write->data[1] : 5;
                    NRF_LOG_INFO("Strobe: mode=%d, freq=%d Hz", mode, freq);
                    led_set_strobe(mode == 1, freq);
                }
            }
            break;
        }

        default:
            break;
    }
}

void ble_service_init(void)
{
    // 初始化延迟保存定时器
    ret_code_t err_code = app_timer_create(&m_save_timer, APP_TIMER_MODE_SINGLE_SHOT, save_timer_handler);
    APP_ERROR_CHECK(err_code);

    // 初始化心跳定时器（从 nrf52832-new 移植 - 保持连接活跃）
    err_code = app_timer_create(&m_heartbeat_timer_id,
                                APP_TIMER_MODE_REPEATED,
                                heartbeat_timer_handler);
    APP_ERROR_CHECK(err_code);

    gap_params_init();
    gatt_init();
    services_init();
    advertising_init();
#if NRF_BLE_CONN_PARAMS_ENABLED
    conn_params_init();
#endif

    // 注册颜色变化回调（修复按键切换颜色后 APP 无法获取当前颜色的问题）
    color_manager_register_callback(ble_service_update_color);

    // 注册电池电量变化回调
    battery_manager_register_callback(ble_service_update_battery);

    // 启动广播
    ble_service_advertising_start();

    NRF_LOG_INFO("BLE service initialized");
}

void ble_service_process(void)
{
    // BLE 事件在 SoftDevice 中处理，这里只处理广播重启
    // 如果未连接且广播未运行且允许自动重启，尝试重启广播
    static uint32_t last_adv_check = 0;
    uint32_t now = app_timer_cnt_get();
    
    if (m_auto_adv_enabled &&
        m_conn_handle == BLE_CONN_HANDLE_INVALID &&
        app_timer_cnt_diff_compute(now, last_adv_check) > APP_TIMER_TICKS(1000))
    {
        last_adv_check = now;
        ble_service_advertising_start();
    }
}

void ble_service_update_color(uint8_t r, uint8_t g, uint8_t b, uint8_t w)
{
    if (m_conn_handle != BLE_CONN_HANDLE_INVALID)
    {
        uint8_t color_data[4] = {r, g, b, w};
        ble_gatts_value_t gatts_value;
        uint16_t len = 4;
        
        memset(&gatts_value, 0, sizeof(gatts_value));
        gatts_value.len = 4;
        gatts_value.offset = 0;
        gatts_value.p_value = color_data;
        
        // 先更新本地特征值
        sd_ble_gatts_value_set(m_conn_handle,
                               m_lightstick_service.color_read_handles.value_handle,
                               &gatts_value);

        // 发送通知给已订阅的 APP
        ble_gatts_hvx_params_t hvx_params;
        memset(&hvx_params, 0, sizeof(hvx_params));
        hvx_params.handle = m_lightstick_service.color_read_handles.value_handle;
        hvx_params.type = BLE_GATT_HVX_NOTIFICATION;
        hvx_params.offset = 0;
        hvx_params.p_len = &len;
        hvx_params.p_data = color_data;

        ret_code_t err_code = sd_ble_gatts_hvx(m_conn_handle, &hvx_params);
        if (err_code == NRF_SUCCESS)
        {
            NRF_LOG_DEBUG("Color notification sent: R=%d G=%d B=%d W=%d", r, g, b, w);
        }
        else if (err_code != BLE_ERROR_GATTS_SYS_ATTR_MISSING)
        {
            NRF_LOG_DEBUG("Color notification failed: 0x%X", err_code);
        }
    }
}

void ble_service_update_battery(uint8_t battery_level)
{
    if (m_conn_handle != BLE_CONN_HANDLE_INVALID)
    {
        ble_gatts_value_t gatts_value;
        
        memset(&gatts_value, 0, sizeof(gatts_value));
        gatts_value.len = 1;
        gatts_value.offset = 0;
        gatts_value.p_value = &battery_level;
        
        sd_ble_gatts_value_set(m_conn_handle,
                               m_lightstick_service.battery_handles.value_handle,
                               &gatts_value);
    }
}

/**
 * @brief 更新 FFF5 预设读取特征值（准备全部 200 字节）
 */
static void ble_service_update_presets(void)
{
    if (m_conn_handle != BLE_CONN_HANDLE_INVALID)
    {
        uint8_t preset_data[200];  // 50 * 4 bytes
        led_color_t colors[50];

        color_manager_get_all_colors(colors);

        for (uint8_t i = 0; i < 50; i++)
        {
            preset_data[i * 4 + 0] = colors[i].r;
            preset_data[i * 4 + 1] = colors[i].g;
            preset_data[i * 4 + 2] = colors[i].b;
            preset_data[i * 4 + 3] = colors[i].w;
        }

        ble_gatts_value_t gatts_value;
        memset(&gatts_value, 0, sizeof(gatts_value));
        gatts_value.len = 200;
        gatts_value.offset = 0;
        gatts_value.p_value = preset_data;

        sd_ble_gatts_value_set(m_conn_handle,
                               m_lightstick_service.preset_read_handles.value_handle,
                               &gatts_value);
    }
}

bool ble_service_is_connected(void)
{
    return (m_conn_handle != BLE_CONN_HANDLE_INVALID);
}

void ble_service_advertising_start(void)
{
    // 如果正在连接中，不启动广播
    if (m_conn_handle != BLE_CONN_HANDLE_INVALID)
    {
        NRF_LOG_WARNING("Advertising skipped: already connected (handle=0x%04X)", m_conn_handle);
        return;
    }
    
    ret_code_t err_code = ble_advertising_start(&m_advertising, BLE_ADV_MODE_FAST);
    // NRF_ERROR_INVALID_STATE 表示广播已经在运行，不是真正的错误
    if (err_code == NRF_SUCCESS || err_code == NRF_ERROR_INVALID_STATE)
    {
        NRF_LOG_INFO("Advertising start OK (err=0x%X)", err_code);
    }
    else
    {
        NRF_LOG_ERROR("Advertising start failed: 0x%X", err_code);
    }
}

void ble_service_advertising_stop(void)
{
    sd_ble_gap_adv_stop(m_advertising.adv_handle);
    NRF_LOG_INFO("Advertising stopped");
}

void ble_service_set_auto_adv(bool enable)
{
    m_auto_adv_enabled = enable;
    NRF_LOG_INFO("Auto advertising: %s", enable ? "enabled" : "disabled");
}

void ble_service_update_device_name(const char *name)
{
    if (name != NULL && strlen(name) > 0)
    {
        // 保存到存储管理器
        storage_manager_set_device_name(name);
        
        // 更新 GAP 设备名称
        ble_gap_conn_sec_mode_t sec_mode;
        BLE_GAP_CONN_SEC_MODE_SET_OPEN(&sec_mode);
        
        ret_code_t err_code = sd_ble_gap_device_name_set(&sec_mode,
                                                          (const uint8_t *)name,
                                                          strlen(name));
        if (err_code == NRF_SUCCESS)
        {
            NRF_LOG_INFO("Device name updated to: %s", (uint32_t)name);
        }
        else
        {
            NRF_LOG_ERROR("Failed to update device name: 0x%X", err_code);
        }
    }
}
