/**
 * @file ble_service.h
 * @brief BLE 服务模块
 *
 * 实现 BLE 广播和自定义 GATT 服务
 * Service UUID: 0xFFF0
 * Characteristics:
 *   - FFF1: Write (设置颜色)
 *   - FFF2: Read + Notify (当前颜色，按钮切换时通知 APP)
 *   - FFF3: Read (电池电量)
 *   - FFF4: Write (设置预设颜色，单条/批量)
 *   - FFF5: Read (读取全部50个预设颜色)
 *   - FFF6: Read (固件版本)
 *   - FFF7: Write (DFU 控制 - 写入 "DFU" 进入升级模式)
 */

#ifndef BLE_SERVICE_H
#define BLE_SERVICE_H

#include <stdint.h>
#include <stdbool.h>
#include "ble.h"
#include "ble_srv_common.h"

// 自定义服务 UUID
#define CUSTOM_SERVICE_UUID             0xFFF0

// Characteristic UUIDs
#define CHAR_COLOR_WRITE_UUID           0xFFF1
#define CHAR_COLOR_READ_UUID            0xFFF2
#define CHAR_BATTERY_READ_UUID          0xFFF3
#define CHAR_PRESET_WRITE_UUID          0xFFF4
#define CHAR_PRESET_READ_UUID           0xFFF5
#define CHAR_VERSION_READ_UUID          0xFFF6
#define CHAR_DFU_CONTROL_UUID           0xFFF7
#define CHAR_BRIGHTNESS_UUID            0xFFF8
#define CHAR_STROBE_UUID                0xFFF9

// 软件版本号（自动迭代）
#define SOFTWARE_VERSION                "3.1.2"

// BLE 服务结构体
typedef struct {
    uint16_t                    service_handle;
    uint16_t                    conn_handle;
    ble_gatts_char_handles_t    color_write_handles;
    ble_gatts_char_handles_t    color_read_handles;
    ble_gatts_char_handles_t    battery_handles;
    ble_gatts_char_handles_t    preset_write_handles;
    ble_gatts_char_handles_t    preset_read_handles;
    ble_gatts_char_handles_t    version_handles;
    ble_gatts_char_handles_t    dfu_control_handles;
    ble_gatts_char_handles_t    brightness_handles;
    ble_gatts_char_handles_t    strobe_handles;
    uint8_t                     uuid_type;
} ble_lightstick_service_t;

/**
 * @brief 初始化 BLE 服务
 */
void ble_service_init(void);

/**
 * @brief BLE 服务处理函数（在主循环中调用）
 */
void ble_service_process(void);

/**
 * @brief 更新当前颜色特征值
 *
 * @param r 红色分量
 * @param g 绿色分量
 * @param b 蓝色分量
 * @param w 白色分量
 */
void ble_service_update_color(uint8_t r, uint8_t g, uint8_t b, uint8_t w);

/**
 * @brief 更新电池电量特征值
 *
 * @param battery_level 电池电量 (0-100%)
 */
void ble_service_update_battery(uint8_t battery_level);

/**
 * @brief 获取 BLE 连接状态
 *
 * @return true 已连接, false 未连接
 */
bool ble_service_is_connected(void);

/**
 * @brief 开始 BLE 广播
 */
void ble_service_advertising_start(void);

/**
 * @brief 停止 BLE 广播
 */
void ble_service_advertising_stop(void);

/**
 * @brief 设置是否允许自动重启广播
 *
 * @param enable true 允许自动重启, false 禁止自动重启
 */
void ble_service_set_auto_adv(bool enable);

/**
 * @brief 处理待保存的数据（在主循环中调用）
 */
void ble_service_process_pending_save(void);

/**
 * @brief 更新设备名称
 * 
 * @param name 新的设备名称
 */
void ble_service_update_device_name(const char *name);

#endif // BLE_SERVICE_H
