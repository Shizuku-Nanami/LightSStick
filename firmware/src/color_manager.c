/**
 * @file color_manager.c
 * @brief 颜色管理模块实现
 */

#include "color_manager.h"
#include "led_driver.h"
#include "nrf_log.h"
#include <string.h>

// 当前颜色索引
static uint8_t m_color_index = 0;

// 颜色变化回调函数
static color_change_callback_t m_color_change_callback = NULL;

// 默认预设颜色表（50 种颜色，用于恢复出厂）
static const led_color_t m_default_color_table[COLOR_COUNT] = {
    // 纯色系列 (R, G, B, W)
    {255, 0, 0, 0},      // 0: 红色
    {0, 255, 0, 0},      // 1: 绿色
    {0, 0, 255, 0},      // 2: 蓝色
    {255, 255, 0, 0},    // 3: 黄色
    {255, 0, 255, 0},    // 4: 品红
    {0, 255, 255, 0},    // 5: 青色
    {0, 0, 0, 255},      // 6: 纯白

    // 粉色系列
    {255, 192, 203, 0},  // 7: 粉色
    {255, 182, 193, 0},  // 8: 浅粉色
    {255, 105, 180, 0},  // 9: 热粉色
    {255, 20, 147, 0},   // 10: 深粉色

    // 橙色系列
    {255, 165, 0, 0},    // 11: 橙色
    {255, 140, 0, 0},    // 12: 深橙色
    {255, 69, 0, 0},     // 13: 橙红色
    {255, 127, 80, 0},   // 14: 珊瑚色

    // 紫色系列
    {128, 0, 128, 0},    // 15: 紫色
    {138, 43, 226, 0},   // 16: 蓝紫色
    {148, 0, 211, 0},    // 17: 深紫色
    {186, 85, 211, 0},   // 18: 中紫色
    {221, 160, 221, 0},  // 19: 梅红色

    // 蓝色系列
    {0, 0, 139, 0},      // 20: 深蓝色
    {0, 0, 205, 0},      // 21: 中蓝色
    {30, 144, 255, 0},   // 22: 道奇蓝
    {135, 206, 250, 0},  // 23: 天蓝色
    {0, 191, 255, 0},    // 24: 深天蓝

    // 绿色系列
    {0, 128, 0, 0},      // 25: 深绿色
    {34, 139, 34, 0},    // 26: 森林绿
    {0, 255, 127, 0},    // 27: 春绿色
    {50, 205, 50, 0},    // 28: 酸橙绿
    {144, 238, 144, 0},  // 29: 浅绿色

    // 黄色系列
    {255, 215, 0, 0},    // 30: 金色
    {255, 250, 205, 0},  // 31: 柠檬绸色
    {255, 255, 224, 0},  // 32: 浅黄色

    // 棕色系列
    {165, 42, 42, 0},    // 33: 棕色
    {139, 69, 19, 0},    // 34: 马鞍棕色
    {210, 105, 30, 0},   // 35: 巧克力色
    {244, 164, 96, 0},   // 36: 沙褐色

    // 灰色系列
    {128, 128, 128, 0},  // 37: 灰色
    {192, 192, 192, 0},  // 38: 银色
    {169, 169, 169, 0},  // 39: 深灰色
    {211, 211, 211, 0},  // 40: 浅灰色

    // 特殊颜色
    {255, 0, 0, 50},     // 41: 红色+白光
    {0, 255, 0, 50},     // 42: 绿色+白光
    {0, 0, 255, 50},     // 43: 蓝色+白光
    {128, 128, 0, 100},  // 44: 橄榄色+白光
    {0, 128, 128, 100},  // 45: 水鸭色+白光
    {128, 0, 128, 100},  // 46: 紫色+白光
    {100, 100, 100, 200},// 47: 暖白光
    {150, 150, 150, 255},// 48: 冷白光
    {0, 0, 0, 0}         // 49: 关闭
};

// 可写颜色表（运行时从默认表初始化，可被 APP 覆盖）
static led_color_t m_color_table[COLOR_COUNT];

/**
 * @brief 检查颜色是否为关闭状态（RGBW 全为 0）
 */
static bool is_color_off(uint8_t index)
{
    if (index >= COLOR_COUNT) return true;
    return (m_color_table[index].r == 0 &&
            m_color_table[index].g == 0 &&
            m_color_table[index].b == 0 &&
            m_color_table[index].w == 0);
}

void color_manager_init(void)
{
    memcpy(m_color_table, m_default_color_table, sizeof(m_color_table));
    m_color_index = 0;
    m_color_change_callback = NULL;
    NRF_LOG_INFO("Color manager initialized, total colors: %d", COLOR_COUNT);
}

void color_manager_register_callback(color_change_callback_t callback)
{
    m_color_change_callback = callback;
    NRF_LOG_INFO("Color change callback registered");
}

void color_manager_next(void)
{
    // 智能跳过：找到下一个非关闭的颜色
    uint8_t start_index = m_color_index;
    do {
        m_color_index++;
        if (m_color_index >= COLOR_COUNT)
        {
            m_color_index = 0;
        }
        // 防止无限循环（所有颜色都是关闭状态）
        if (m_color_index == start_index)
        {
            break;
        }
    } while (is_color_off(m_color_index));

    NRF_LOG_INFO("Color switched to next: index=%d", m_color_index);
    color_manager_apply_current();
}

void color_manager_prev(void)
{
    // 智能跳过：找到上一个非关闭的颜色
    uint8_t start_index = m_color_index;
    do {
        if (m_color_index == 0)
        {
            m_color_index = COLOR_COUNT - 1;
        }
        else
        {
            m_color_index--;
        }
        // 防止无限循环（所有颜色都是关闭状态）
        if (m_color_index == start_index)
        {
            break;
        }
    } while (is_color_off(m_color_index));

    NRF_LOG_INFO("Color switched to prev: index=%d", m_color_index);
    color_manager_apply_current();
}

uint8_t color_manager_get_index(void)
{
    return m_color_index;
}

void color_manager_set_index(uint8_t index)
{
    if (index < COLOR_COUNT)
    {
        m_color_index = index;
        NRF_LOG_INFO("Color index set to: %d", index);
    }
}

void color_manager_get_current_color(led_color_t *p_color)
{
    if (p_color != NULL && m_color_index < COLOR_COUNT)
    {
        memcpy(p_color, &m_color_table[m_color_index], sizeof(led_color_t));
    }
}

void color_manager_get_color_by_index(uint8_t index, led_color_t *p_color)
{
    if (p_color != NULL && index < COLOR_COUNT)
    {
        memcpy(p_color, &m_color_table[index], sizeof(led_color_t));
    }
}

void color_manager_apply_current(void)
{
    led_color_t color;
    color_manager_get_current_color(&color);
    
    // 应用颜色校正流水线
    uint8_t r_corr, g_corr, b_corr, w_corr;
    led_color_correct(color.r, color.g, color.b, color.w,
                      &r_corr, &g_corr, &b_corr, &w_corr);
    led_set_color(r_corr, g_corr, b_corr, w_corr);
    
    // 通知 BLE 服务更新颜色特征值（使用原始颜色，便于 APP 显示）
    if (m_color_change_callback != NULL)
    {
        m_color_change_callback(color.r, color.g, color.b, color.w);
    }
}

void color_manager_set_color(uint8_t index, uint8_t r, uint8_t g, uint8_t b, uint8_t w)
{
    if (index < COLOR_COUNT)
    {
        m_color_table[index].r = r;
        m_color_table[index].g = g;
        m_color_table[index].b = b;
        m_color_table[index].w = w;
        NRF_LOG_INFO("Preset %d overwritten: R=%d G=%d B=%d W=%d", index, r, g, b, w);
    }
}

void color_manager_get_all_colors(led_color_t *p_buffer)
{
    if (p_buffer != NULL)
    {
        memcpy(p_buffer, m_color_table, sizeof(m_color_table));
    }
}

led_color_t *color_manager_get_table(void)
{
    return m_color_table;
}

void color_manager_reset_to_defaults(void)
{
    memcpy(m_color_table, m_default_color_table, sizeof(m_color_table));
    m_color_index = 0;
    color_manager_apply_current();
    NRF_LOG_INFO("Color table reset to defaults");
}
