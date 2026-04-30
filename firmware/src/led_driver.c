/**
 * @file led_driver.c
 * @brief SK6812 RGBW LED 驱动实现
 *
 * 使用 PWM + EasyDMA 方式驱动（NRF_PWM_LOAD_COMMON 单通道模式）
 * 通信协议: 800kHz 单线通信，数据格式: GRBW
 *
 * 硬件说明：数据链路上存在反相级（三极管/驱动器），因此 PWM 采样值
 * 需设置 bit15（nRF52 PWM 内部反相标志），使最终到达 SK6812 的时序正确。
 */

#include "led_driver.h"
#include "nrf_drv_pwm.h"
#include "nrf_log.h"
#include "app_error.h"
#include "app_timer.h"

// 爆闪定时器
APP_TIMER_DEF(m_strobe_timer);

// ============================================================
// 颜色校正流水线配置（当前被禁用 — 使用最大亮度直通模式）
// 如需重新启用颜色校正，删除下方 #if 0 和 #endif 即可
// ============================================================
#if 0

// [D] Gamma Decode: sRGB → Linear（256 字节查找表）
// 使用 sRGB 标准 gamma 曲线（gamma ≈ 2.2）
static const uint8_t srgb_to_linear[256] = {
    0,   0,   0,   0,   0,   0,   0,   1,   1,   1,   1,   1,   1,   1,   1,   1,
    1,   1,   1,   1,   1,   2,   2,   2,   2,   2,   2,   2,   2,   2,   3,   3,
    3,   3,   3,   3,   3,   3,   4,   4,   4,   4,   4,   4,   5,   5,   5,   5,
    5,   6,   6,   6,   6,   6,   7,   7,   7,   7,   8,   8,   8,   8,   9,   9,
    9,   10,  10,  10,  10,  11,  11,  11,  12,  12,  12,  13,  13,  13,  14,  14,
    14,  15,  15,  16,  16,  16,  17,  17,  18,  18,  18,  19,  19,  20,  20,  21,
    21,  22,  22,  23,  23,  24,  24,  25,  25,  26,  26,  27,  28,  28,  29,  29,
    30,  31,  31,  32,  33,  33,  34,  35,  35,  36,  37,  38,  38,  39,  40,  41,
    42,  42,  43,  44,  45,  46,  47,  48,  48,  49,  50,  51,  52,  53,  54,  55,
    56,  57,  58,  59,  60,  61,  62,  63,  64,  66,  67,  68,  69,  70,  71,  73,
    74,  75,  76,  78,  79,  80,  82,  83,  84,  86,  87,  88,  90,  91,  93,  94,
    96,  97,  99,  100, 102, 103, 105, 106, 108, 110, 111, 113, 115, 116, 118, 120,
    122, 123, 125, 127, 129, 131, 133, 134, 136, 138, 140, 142, 144, 146, 148, 150,
    152, 154, 156, 158, 161, 163, 165, 167, 169, 172, 174, 176, 179, 181, 183, 186,
    188, 190, 193, 195, 198, 200, 203, 205, 208, 210, 213, 216, 218, 221, 224, 226,
    229, 232, 235, 237, 240, 243, 246, 249, 252, 255, 255, 255, 255, 255, 255, 255,
};

// [Gamma Encode] Linear → sRGB（256 字节查找表）
static const uint8_t linear_to_srgb[256] = {
    0,  13,  22,  28,  33,  38,  42,  46,  49,  52,  55,  58,  61,  64,  66,  69,
   71,  73,  76,  78,  80,  82,  84,  86,  88,  90,  92,  93,  95,  97,  99, 100,
  102, 104, 105, 107, 108, 110, 112, 113, 115, 116, 118, 119, 120, 122, 123, 125,
  126, 127, 129, 130, 131, 133, 134, 135, 137, 138, 139, 141, 142, 143, 144, 146,
  147, 148, 149, 151, 152, 153, 154, 155, 157, 158, 159, 160, 161, 163, 164, 165,
  166, 167, 168, 170, 171, 172, 173, 174, 175, 176, 177, 179, 180, 181, 182, 183,
  184, 185, 186, 187, 188, 189, 190, 191, 193, 194, 195, 196, 197, 198, 199, 200,
  201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216,
  217, 218, 219, 220, 221, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231,
  232, 233, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 242, 243, 244, 245,
  246, 247, 248, 249, 250, 250, 251, 252, 253, 254, 255, 255, 255, 255, 255, 255,
  255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
  255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
  255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
  255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
  255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
};

// [C] 3×3 颜色校正矩阵（线性空间，可调参数）
// SK6812 典型参数：绿色过亮，需要降低
#define M_RR  1.00f    // R → R
#define M_RG -0.12f    // G → R（绿色对红色的干扰补偿）
#define M_RB  0.00f    // B → R
#define M_GR  0.00f    // R → G
#define M_GG  0.80f    // G → G（降低绿色亮度 20%）
#define M_GB  0.00f    // B → G
#define M_BR  0.00f    // R → B
#define M_BG -0.08f    // G → B（绿色对蓝色的干扰补偿）
#define M_BB  1.00f    // B → B

// [B] RGBW 分离配置
#define W_MAX_LIMIT    255.0f   // 白色分量上限（允许满亮度）

// ── Gamma Decode：sRGB → Linear（查表法） ──
static inline float gamma_decode(uint8_t val)
{
    return (float)srgb_to_linear[val];
}

// ── Gamma Encode：Linear → sRGB（查表法） ──
static inline uint8_t gamma_encode(float val)
{
    if (val <= 0.0f) return 0;
    if (val >= 255.0f) return 255;
    return linear_to_srgb[(uint8_t)(val + 0.5f)];
}

// ── 3×3 颜色校正矩阵（线性空间） ──
static inline void apply_matrix(float r, float g, float b,
                                float *r_out, float *g_out, float *b_out)
{
    *r_out = M_RR * r + M_RG * g + M_RB * b;
    *g_out = M_GR * r + M_GG * g + M_GB * b;
    *b_out = M_BR * r + M_BG * g + M_BB * b;
}

// ── RGB → RGBW 分离（线性空间） ──
static inline void rgb_to_rgbw(float r, float g, float b,
                                float *r_out, float *g_out, float *b_out, float *w_out)
{
    float w = r;
    if (g < w) w = g;
    if (b < w) w = b;
    if (w > W_MAX_LIMIT) w = W_MAX_LIMIT;
    *r_out = r - w;
    *g_out = g - w;
    *b_out = b - w;
    *w_out = w;
}

// ── 亮度限制（Clamp 0-255） ──
static inline uint8_t clamp_to_uint8(float val)
{
    if (val < 0.0f) return 0;
    if (val > 255.0f) return 255;
    return (uint8_t)(val + 0.5f);
}

#endif // 0 — 最大亮度模式已禁用颜色校正管线

// 亮度增益（2.5x = Boost 150%）
#define BRIGHTNESS_BOOST  2.50f

// ============================================================
// 颜色校正流水线（公开接口）
// ============================================================

void led_color_correct(uint8_t r_in, uint8_t g_in, uint8_t b_in, uint8_t w_in,
                       uint8_t *r_out, uint8_t *g_out, uint8_t *b_out, uint8_t *w_out)
{
    // 最大亮度模式：跳过颜色校正矩阵和 RGB→RGBW 分离，
    // 仅保留 Boost + Clamp，白色通道独立透传。
    float r_f = (float)r_in * BRIGHTNESS_BOOST;
    float g_f = (float)g_in * BRIGHTNESS_BOOST;
    float b_f = (float)b_in * BRIGHTNESS_BOOST;

    if (r_f > 255.0f) r_f = 255.0f;
    if (g_f > 255.0f) g_f = 255.0f;
    if (b_f > 255.0f) b_f = 255.0f;

    *r_out = (uint8_t)(r_f + 0.5f);
    *g_out = (uint8_t)(g_f + 0.5f);
    *b_out = (uint8_t)(b_f + 0.5f);
    *w_out = w_in;
}

// ============================================================
// GPIO 配置
// ============================================================
#define LED_DATA_PIN    24   // P0.24

// SK6812 时序参数（硬件链路存在反相，故 duty 值配合 bit15 使用）
// 16MHz 时钟，COUNTERTOP=19，实际周期 = 20×62.5ns = 1250ns（800kHz）
// T0H 规格: 300ns ±150ns → PWM_DUTY_0=6 → 6×62.5ns = 375ns  ✓
// T1H 规格: 600ns ±150ns → PWM_DUTY_1=10 → 10×62.5ns = 625ns ✓
// bit15=1 时 nRF52 PWM 内部对该通道做极性翻转，与链路反相互补
#define PWM_PERIOD      19
#define PWM_DUTY_0      (6  | 0x8000u)   // 0 码（含 PWM 内部反相标志）
#define PWM_DUTY_1      (10 | 0x8000u)   // 1 码（含 PWM 内部反相标志）

#define LED_COUNT       1
#define BYTES_PER_LED   4               // GRBW
#define TOTAL_BITS      (LED_COUNT * BYTES_PER_LED * 8)
// SK6812 复位低电平 >= 80us，留 100us 裕量（80 slots × 1.25us = 100us）
#define RESET_SLOTS     80

// PWM 实例
static nrf_drv_pwm_t m_pwm = NRF_DRV_PWM_INSTANCE(0);

// COMMON 模式缓冲区
static uint16_t m_pwm_buffer[TOTAL_BITS + RESET_SLOTS];

// PWM 忙标志，防止并发调用
static volatile bool m_pwm_busy = false;

// 当前 LED 颜色
static led_color_t m_current_color = {0, 0, 0, 0};
static bool m_led_on = false;

// 亮度和爆闪状态
static uint8_t m_brightness = 255;   // 全局亮度 (0-255)
static bool m_strobe_enabled = false; // 爆闪开关
static uint8_t m_strobe_freq_hz = 5;  // 爆闪频率 (Hz)
static volatile bool m_strobe_on = false;   // 爆闪当前状态 (亮/灭)

// 前向声明
static void send_color(const led_color_t *p_color);

/**
 * @brief 应用亮度到当前颜色并发送
 */
static void apply_brightness_and_send(void)
{
    uint8_t r = (uint8_t)((uint16_t)m_current_color.r * m_brightness / 255);
    uint8_t g = (uint8_t)((uint16_t)m_current_color.g * m_brightness / 255);
    uint8_t b = (uint8_t)((uint16_t)m_current_color.b * m_brightness / 255);
    uint8_t w = (uint8_t)((uint16_t)m_current_color.w * m_brightness / 255);
    led_color_t scaled = {r, g, b, w};
    send_color(&scaled);
}

/**
 * @brief 爆闪定时器回调
 */
static void strobe_timer_handler(void *p_context)
{
    UNUSED_PARAMETER(p_context);

    if (!m_strobe_enabled || !m_led_on) return;

    m_strobe_on = !m_strobe_on;

    if (m_strobe_on)
    {
        apply_brightness_and_send();
    }
    else
    {
        led_color_t off_color = {0, 0, 0, 0};
        send_color(&off_color);
    }
}

/**
 * @brief 启动爆闪定时器
 */
static void strobe_timer_start(void)
{
    uint32_t ticks = APP_TIMER_TICKS(500 / m_strobe_freq_hz); // 半周期
    if (ticks < APP_TIMER_TICKS(10)) ticks = APP_TIMER_TICKS(10); // 最小 10ms
    app_timer_start(m_strobe_timer, ticks, NULL);
}

/**
 * @brief 停止爆闪定时器
 */
static void strobe_timer_stop(void)
{
    app_timer_stop(m_strobe_timer);
}

/**
 * @brief PWM 事件处理函数
 */
static void pwm_handler(nrf_drv_pwm_evt_type_t event_type)
{
    if (event_type == NRF_DRV_PWM_EVT_STOPPED)
    {
        m_pwm_busy = false;
    }
}

/**
 * @brief 将字节转换为 PWM 缓冲区中的脉冲序列（MSB 优先）
 */
static void byte_to_pwm(uint8_t byte, uint16_t offset)
{
    for (int i = 7; i >= 0; i--)
    {
        m_pwm_buffer[offset++] = (byte & (1 << i)) ? PWM_DUTY_1 : PWM_DUTY_0;
    }
}

/**
 * @brief 发送颜色数据到 LED（SK6812 GRBW 协议）
 */
static void send_color(const led_color_t *p_color)
{
    uint16_t bit_idx = 0;

    // SK6812 协议: G → R → B → W 顺序发送（MSB 优先）
    byte_to_pwm(p_color->g, bit_idx);  bit_idx += 8;
    byte_to_pwm(p_color->r, bit_idx);  bit_idx += 8;
    byte_to_pwm(p_color->b, bit_idx);  bit_idx += 8;
    byte_to_pwm(p_color->w, bit_idx);  bit_idx += 8;

    // 追加复位低电平窗口（>= 80us）
    for (uint16_t i = 0; i < RESET_SLOTS; i++)
    {
        m_pwm_buffer[bit_idx + i] = 0;
    }

    // 等待上一次序列完成（超时保护：约 5ms，远大于单帧传输时间 ~150us）
    uint32_t timeout = 80000;
    while (m_pwm_busy && timeout--) { }
    if (m_pwm_busy)
    {
        // 超时：强制中止上一次 DMA 并重置标志
        nrf_drv_pwm_stop(&m_pwm, false);
        m_pwm_busy = false;
    }
    m_pwm_busy = true;

    nrf_pwm_sequence_t const seq =
    {
        .values.p_common = m_pwm_buffer,
        .length          = TOTAL_BITS + RESET_SLOTS,
        .repeats         = 0,
        .end_delay       = 0
    };

    ret_code_t err_code = nrf_drv_pwm_simple_playback(&m_pwm, &seq, 1, NRF_DRV_PWM_FLAG_STOP);
    APP_ERROR_CHECK(err_code);
}

void led_init(void)
{
    nrf_drv_pwm_config_t const config =
    {
        .output_pins =
        {
            LED_DATA_PIN,               // channel 0，正常引脚极性
            NRF_DRV_PWM_PIN_NOT_USED,
            NRF_DRV_PWM_PIN_NOT_USED,
            NRF_DRV_PWM_PIN_NOT_USED,
        },
        .irq_priority = APP_IRQ_PRIORITY_LOWEST,
        .base_clock   = NRF_PWM_CLK_16MHz,
        .count_mode   = NRF_PWM_MODE_UP,
        .top_value    = PWM_PERIOD,
        .load_mode    = NRF_PWM_LOAD_COMMON,
        .step_mode    = NRF_PWM_STEP_AUTO
    };

    ret_code_t err_code = nrf_drv_pwm_init(&m_pwm, &config, pwm_handler);
    APP_ERROR_CHECK(err_code);

    // 创建爆闪定时器
    err_code = app_timer_create(&m_strobe_timer,
                               APP_TIMER_MODE_REPEATED,
                               strobe_timer_handler);
    APP_ERROR_CHECK(err_code);

    NRF_LOG_INFO("LED driver init: P0.%02d, 800kHz, inv-phase mode", LED_DATA_PIN);
}

void led_set_color(uint8_t r, uint8_t g, uint8_t b, uint8_t w)
{
    m_current_color.r = r;
    m_current_color.g = g;
    m_current_color.b = b;
    m_current_color.w = w;
    m_led_on = (r != 0 || g != 0 || b != 0 || w != 0);

    if (m_strobe_enabled)
    {
        // 爆闪开启时，重置状态让新颜色立即显示
        m_strobe_on = true;
        strobe_timer_stop();
        apply_brightness_and_send();
        strobe_timer_start();
    }
    else
    {
        apply_brightness_and_send();
    }

    NRF_LOG_INFO("LED color set: R=%d G=%d B=%d W=%d (brightness=%d, strobe=%d)",
                 r, g, b, w, m_brightness, m_strobe_enabled);
}

void led_set_color_struct(const led_color_t *p_color)
{
    if (p_color != NULL)
    {
        led_set_color(p_color->r, p_color->g, p_color->b, p_color->w);
    }
}

void led_off(void)
{
    led_color_t off_color = {0, 0, 0, 0};
    send_color(&off_color);
    m_led_on = false;
    NRF_LOG_DEBUG("LED off");
}

void led_update(void)
{
    send_color(&m_current_color);
}

void led_driver_process(void)
{
    // 爆闪现在使用定时器处理，主循环中无需处理
}

bool led_is_on(void)
{
    return m_led_on;
}

void led_driver_abort(void)
{
    // 立即停止 PWM 输出（不等待序列自然结束）
    nrf_drv_pwm_stop(&m_pwm, false);
    m_pwm_busy = false;
}

void led_set_brightness(uint8_t brightness)
{
    m_brightness = brightness;
    // 立即应用到当前颜色
    if (m_led_on)
    {
        apply_brightness_and_send();
    }
    NRF_LOG_INFO("Brightness set: %d", m_brightness);
}

uint8_t led_get_brightness(void)
{
    return m_brightness;
}

void led_set_strobe(bool enable, uint8_t freq_hz)
{
    m_strobe_enabled = enable;
    if (enable)
    {
        m_strobe_freq_hz = (freq_hz < 1) ? 1 : (freq_hz > 20) ? 20 : freq_hz;
        m_strobe_on = true; // 先亮一次显示当前颜色
        apply_brightness_and_send();
        strobe_timer_start();
        NRF_LOG_INFO("Strobe ON, freq=%d Hz", m_strobe_freq_hz);
    }
    else
    {
        strobe_timer_stop();
        NRF_LOG_INFO("Strobe OFF");
        // 恢复当前颜色（应用亮度）
        if (m_led_on)
        {
            apply_brightness_and_send();
        }
    }
}

bool led_is_strobe(void)
{
    return m_strobe_enabled;
}

uint8_t led_get_strobe_freq(void)
{
    return m_strobe_freq_hz;
}

void led_strobe_stop(void)
{
    if (m_strobe_enabled)
    {
        m_strobe_enabled = false;
        strobe_timer_stop();
        // 恢复当前颜色（应用亮度）
        if (m_led_on)
        {
            apply_brightness_and_send();
        }
        NRF_LOG_INFO("Strobe stopped (disconnect)");
    }
}
