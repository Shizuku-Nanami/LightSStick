/**
 * @file storage_manager.c
 * @brief Flash 存储管理模块实现
 */

#include "storage_manager.h"
#include "fds.h"
#include "nrf_sdh.h"
#include "nrf_log.h"
#include "app_error.h"
#include "color_manager.h"
#include <string.h>

// FDS 配置
#define CONFIG_FILE_ID      0x1111
#define CONFIG_RECORD_KEY   0x2222

// 当前配置（color_table 由 color_manager_init 填充默认值后同步）
static device_config_t m_config;

// FDS 初始化标志
static volatile bool m_fds_initialized = false;

/**
 * @brief FDS 事件处理函数
 */
static void fds_evt_handler(fds_evt_t const *p_evt)
{
    switch (p_evt->id)
    {
        case FDS_EVT_INIT:
            if (p_evt->result == NRF_SUCCESS)
            {
                m_fds_initialized = true;
                NRF_LOG_INFO("FDS initialized successfully");
            }
            break;

        case FDS_EVT_WRITE:
            if (p_evt->result == NRF_SUCCESS)
            {
                NRF_LOG_DEBUG("FDS write successful");
            }
            else
            {
                NRF_LOG_ERROR("FDS write failed: %d", p_evt->result);
            }
            break;

        case FDS_EVT_UPDATE:
            if (p_evt->result == NRF_SUCCESS)
            {
                NRF_LOG_DEBUG("FDS update successful");
            }
            break;

        case FDS_EVT_DEL_RECORD:
            if (p_evt->result == NRF_SUCCESS)
            {
                NRF_LOG_DEBUG("FDS delete successful");
            }
            break;

        case FDS_EVT_GC:
            if (p_evt->result == NRF_SUCCESS)
            {
                NRF_LOG_DEBUG("FDS garbage collection successful");
            }
            break;

        default:
            break;
    }
}

void storage_manager_init(void)
{
    ret_code_t err_code;

    err_code = fds_register(fds_evt_handler);
    APP_ERROR_CHECK(err_code);

    err_code = fds_init();
    APP_ERROR_CHECK(err_code);

    // 等待 FDS 初始化完成
    // FDS 初始化结果通过 SoftDevice SOC 事件链派发，必须主动轮询事件
    while (!m_fds_initialized)
    {
        nrf_sdh_evts_poll();
    }

    NRF_LOG_INFO("Storage manager initialized");
}

bool storage_manager_save_config(void)
{
    ret_code_t err_code;
    fds_record_desc_t desc = {0};
    fds_find_token_t tok = {0};
    
    // 更新配置（从颜色管理器获取当前索引和颜色表）
    m_config.color_index = color_manager_get_index();
    color_manager_get_all_colors(m_config.color_table);

    // 查找现有记录
    err_code = fds_record_find(CONFIG_FILE_ID, CONFIG_RECORD_KEY, &desc, &tok);

    fds_record_t record;
    record.file_id = CONFIG_FILE_ID;
    record.key = CONFIG_RECORD_KEY;
    record.data.p_data = &m_config;
    record.data.length_words = (sizeof(device_config_t) + 3) / sizeof(uint32_t);

    if (err_code == NRF_SUCCESS)
    {
        // 记录存在，更新
        err_code = fds_record_update(&desc, &record);
        if (err_code == NRF_SUCCESS)
        {
            NRF_LOG_INFO("Config updated in Flash (index=%d)", m_config.color_index);
            return true;
        }
    }
    else
    {
        // 记录不存在，写入新记录
        err_code = fds_record_write(&desc, &record);
        if (err_code == NRF_SUCCESS)
        {
            NRF_LOG_INFO("Config written to Flash (index=%d)", m_config.color_index);
            return true;
        }
    }

    // 保存失败，尝试垃圾回收后重试
    if (err_code == FDS_ERR_NO_SPACE_IN_FLASH || err_code == FDS_ERR_NO_SPACE_IN_QUEUES)
    {
        NRF_LOG_WARNING("Flash full, running GC...");
        fds_gc();
        
        // 重试一次
        err_code = fds_record_find(CONFIG_FILE_ID, CONFIG_RECORD_KEY, &desc, &tok);
        if (err_code == NRF_SUCCESS)
        {
            err_code = fds_record_update(&desc, &record);
        }
        else
        {
            err_code = fds_record_write(&desc, &record);
        }
        
        if (err_code == NRF_SUCCESS)
        {
            NRF_LOG_INFO("Config saved after GC (index=%d)", m_config.color_index);
            return true;
        }
    }

    NRF_LOG_ERROR("Failed to save config: 0x%X", err_code);
    return false;
}

bool storage_manager_load_config(void)
{
    ret_code_t err_code;
    fds_record_desc_t desc = {0};
    fds_find_token_t tok = {0};

    err_code = fds_record_find(CONFIG_FILE_ID, CONFIG_RECORD_KEY, &desc, &tok);
    
    if (err_code == NRF_SUCCESS)
    {
        fds_flash_record_t flash_record = {0};
        
        err_code = fds_record_open(&desc, &flash_record);
        if (err_code == NRF_SUCCESS)
        {
            // 拷贝数据
            memcpy(&m_config, flash_record.p_data, sizeof(device_config_t));
            
            err_code = fds_record_close(&desc);
            APP_ERROR_CHECK(err_code);
            
            // 恢复颜色表和索引
            led_color_t *table = color_manager_get_table();
            memcpy(table, m_config.color_table, sizeof(m_config.color_table));
            color_manager_set_index(m_config.color_index);
            color_manager_apply_current();

            NRF_LOG_INFO("Config loaded from Flash (index=%d, table restored)", m_config.color_index);
            return true;
        }
    }
    else
    {
        NRF_LOG_WARNING("No saved config found, using defaults");
    }

    return false;
}

void storage_manager_get_config(device_config_t *p_config)
{
    if (p_config != NULL)
    {
        memcpy(p_config, &m_config, sizeof(device_config_t));
    }
}

void storage_manager_set_config(const device_config_t *p_config)
{
    if (p_config != NULL)
    {
        memcpy(&m_config, p_config, sizeof(device_config_t));
    }
}

void storage_manager_clear(void)
{
    ret_code_t err_code;
    fds_record_desc_t desc = {0};
    fds_find_token_t tok = {0};

    err_code = fds_record_find(CONFIG_FILE_ID, CONFIG_RECORD_KEY, &desc, &tok);
    
    if (err_code == NRF_SUCCESS)
    {
        err_code = fds_record_delete(&desc);
        if (err_code == NRF_SUCCESS)
        {
            NRF_LOG_INFO("Config cleared from Flash");
            
            // 触发垃圾回收
            fds_gc();
        }
    }
}

const char *storage_manager_get_device_name(void)
{
    return m_config.device_name;
}

void storage_manager_set_device_name(const char *name)
{
    if (name != NULL)
    {
        strncpy(m_config.device_name, name, DEVICE_NAME_MAX_LENGTH - 1);
        m_config.device_name[DEVICE_NAME_MAX_LENGTH - 1] = '\0';
        NRF_LOG_INFO("Device name set to: %s", (uint32_t)m_config.device_name);
    }
}
