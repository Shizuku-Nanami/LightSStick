/**
 * @file led_driver.h
 * @brief SK6812 RGBW LED 驱动接口
 * 
 * 使用 PWM + EasyDMA 驱动 SK6812
 * 数据顺序: GRBW
 */

#ifndef LED_DRIVER_H
#define LED_DRIVER_H

#include <stdint.h>
#include <stdbool.h>

// LED 颜色结构（按 RGBW 顺序定义，便于颜色表初始化）
// send_color() 在发送时仍按 SK6812 的 GRBW 协议顺序输出
typedef struct {
    uint8_t r;  // Red
    uint8_t g;  // Green
    uint8_t b;  // Blue
    uint8_t w;  // White
} led_color_t;

/**
 * @brief 初始化 LED 驱动
 */
void led_init(void);

/**
 * @brief 设置 LED 颜色
 * 
 * @param r 红色分量 (0-255)
 * @param g 绿色分量 (0-255)
 * @param b 蓝色分量 (0-255)
 * @param w 白色分量 (0-255)
 */
void led_set_color(uint8_t r, uint8_t g, uint8_t b, uint8_t w);

/**
 * @brief 设置 LED 颜色（使用结构体）
 * 
 * @param p_color 颜色结构体指针
 */
void led_set_color_struct(const led_color_t *p_color);

/**
 * @brief 关闭 LED
 */
void led_off(void);

/**
 * @brief 更新 LED 显示（刷新输出）
 */
void led_update(void);

/**
 * @brief LED 驱动处理函数（在主循环中调用）
 */
void led_driver_process(void);

/**
 * @brief 获取当前 LED 状态
 * 
 * @return true LED 已开启, false LED 已关闭
 */
bool led_is_on(void);

/**
 * @brief 强制中止 PWM 并重置忙标志（仅在错误处理中使用）
 *
 * 在 app_error_fault_handler 等中断嵌套场景调用，
 * 防止 m_pwm_busy 因 PWM 回调无法触发而死锁。
 */
void led_driver_abort(void);

/**
 * @brief 颜色校正流水线
 *
 * 完整流程:
 *   1. Gamma Decode: sRGB → Linear
 *   2. 3×3 颜色校正矩阵（线性空间）
 *   3. RGB → RGBW 分离（线性空间）
 *   4. 亮度限制（Clamp 0-255）
 *   5. Gamma Encode: Linear → sRGB
 *
 * @param r_in  输入红色分量 (0-255, sRGB)
 * @param g_in  输入绿色分量 (0-255, sRGB)
 * @param b_in  输入蓝色分量 (0-255, sRGB)
 * @param w_in  输入白色分量 (0-255)
 * @param r_out 输出红色分量 (0-255, sRGB)
 * @param g_out 输出绿色分量 (0-255, sRGB)
 * @param b_out 输出蓝色分量 (0-255, sRGB)
 * @param w_out 输出白色分量 (0-255)
 */
void led_color_correct(uint8_t r_in, uint8_t g_in, uint8_t b_in, uint8_t w_in,
                       uint8_t *r_out, uint8_t *g_out, uint8_t *b_out, uint8_t *w_out);

/**
 * @brief 设置全局亮度
 *
 * @param brightness 亮度级别 (0-255, 255=满亮度)
 */
void led_set_brightness(uint8_t brightness);

/**
 * @brief 获取当前亮度
 */
uint8_t led_get_brightness(void);

/**
 * @brief 设置爆闪模式
 *
 * @param enable true 开启爆闪, false 关闭
 * @param freq_hz 闪烁频率 (1-20 Hz)
 */
void led_set_strobe(bool enable, uint8_t freq_hz);

/**
 * @brief 获取爆闪状态
 */
bool led_is_strobe(void);

/**
 * @brief 获取爆闪频率
 */
uint8_t led_get_strobe_freq(void);

/**
 * @brief 停止爆闪（断连时调用）
 */
void led_strobe_stop(void);

#endif // LED_DRIVER_H
