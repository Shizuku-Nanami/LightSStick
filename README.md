# HikariStick 应援棒控制器固件

## 项目概述

| 项目 | 说明 |
|------|------|
| 产品名称 | HikariStick（应援棒控制器） |
| 软件版本 | 3.0.2 |
| 硬件平台 | nRF52832 |
| SDK | nRF5 SDK 17.1.0 |
| SoftDevice | S132 v7.x |
| LED 类型 | SK6812 RGBW（单灯珠，800kHz GRBW 协议） |

## 功能特性

### LED 驱动
- **SK6812 RGBW**：PWM + EasyDMA 驱动，P0.24 引脚，800kHz
- **颜色校正流水线**：Gamma Decode → 3×3 矩阵校正 → RGB→RGBW 分离 → 亮度限制 → Gamma Encode
- **全局亮度控制**：0-255 级，实时生效
- **爆闪模式**：1-20 Hz 频率可调，使用 App Timer 实现

### BLE 服务
- **自定义 GATT 服务**：UUID 0xFFF0，9 个特征值
- **稳定长连接**：连接间隔 50-100ms，从设备延迟 4，监督超时 4s
- **心跳机制**：2 秒间隔，保持连接活跃
- **自动广播**：断连后自动重启广播，10 分钟超时停止
- **设备绑定**：APP 可绑定设备，重启后自动连接

### 颜色管理
- **50 个预设颜色**：包含主色、粉色、橙色、紫色、蓝色、绿色、黄色、棕色、灰色、混合色、白色变体
- **智能跳过**：按键切换时自动跳过关闭状态的颜色
- **APP 可编辑**：通过 BLE 写入新的颜色预设

### 按键控制
- **2 个物理按键**：P0.09（上一个）、P0.10（下一个）
- **GPIOTE 中断 + 20ms 去抖**
- **双键同时按下**：重新启动广播
- **任意按键唤醒**：休眠状态下按键唤醒

### 电池监测
- **ADC 采样**：AIN0（P0.02），分压电路 R1=100kΩ，R2=200kΩ
- **10 秒采样间隔**
- **低电保护**：连续 3 次低电压确认后自动关机休眠

### Flash 存储
- **Nordic FDS**：持久化存储颜色索引、50 个预设颜色、设备名称
- **延迟保存**：减少 Flash 写入次数，延长寿命
- **自动垃圾回收**：Flash 满时自动回收

### 电源管理
- **30 分钟自动休眠**：无操作 30 分钟后自动休眠
- **广播超时**：10 分钟无连接自动停止广播
- **休眠恢复**：唤醒后恢复休眠前的 LED 颜色

### DFU 支持
- **OTA 升级**：通过 BLE 写入 "DFU" 命令进入 Bootloader
- **签名验证**：ECDSA-P256 签名，安全固件更新

## BLE 特征值

| UUID | 名称 | 属性 | 说明 |
|------|------|------|------|
| 0xFFF1 | 颜色写入 | Write | 写入 RGBW 颜色（4 字节） |
| 0xFFF2 | 颜色读取 | Read + Notify | 当前颜色，按键切换时通知 APP |
| 0xFFF3 | 电池读取 | Read | 电池电量百分比 |
| 0xFFF4 | 预设写入 | Write | 写入预设颜色（单条/批量） |
| 0xFFF5 | 预设读取 | Read | 读取全部 50 个预设颜色 |
| 0xFFF6 | 版本读取 | Read | 固件版本号 |
| 0xFFF7 | DFU 控制 | Write | 写入 "DFU" 进入升级模式 |
| 0xFFF8 | 亮度控制 | Write | 全局亮度（0-255） |
| 0xFFF9 | 爆闪控制 | Write | [模式, 频率]，模式=1 开启 |

## 编译

```bash
# 编译固件
mingw32-make

# 清理
mingw32-make clean
```

## 烧录

### 首次烧录（完整）
```bash
# 烧录 SoftDevice + Bootloader + Application + Settings
flash_all.cmd
```

### 后续更新（仅应用）
```bash
# 生成 DFU 包
dfu_package.cmd 3.0.2

# 或单独生成 settings
generate_settings.cmd 3.0.2
```

### 使用第三方烧录工具
```
1. SoftDevice (0x00000) - s132_nrf52_7.2.0_softdevice.hex
2. Bootloader (0x78000) - secure_bootloader.hex
3. Application (0x26000) - _build/nrf52832_xxaa.hex
4. Settings (0x7F000) - settings.hex
```

## 固件目录结构

```
firmware/
├── _build/                     # 编译输出目录
├── config/
│   ├── sdk_config.h            # SDK 配置文件
│   └── nrf52832_xxaa.ld        # 链接脚本
├── src/
│   ├── main.c                  # 主程序入口
│   ├── led_driver.c/h          # SK6812 LED 驱动
│   ├── ble_service.c/h         # BLE 服务和 GATT 特征值
│   ├── color_manager.c/h       # 颜色预设管理
│   ├── button_manager.c/h      # 按键检测
│   ├── battery_manager.c/h     # 电池监测
│   ├── storage_manager.c/h     # Flash 存储
│   └── power_manager.c/h       # 电源管理
├── Makefile                    # 编译脚本
├── dfu_package.cmd             # DFU 包生成（CMD）
├── dfu_package.ps1             # DFU 包生成（PowerShell）
├── dfu_package.sh              # DFU 包生成（Bash）
├── generate_settings.cmd       # Settings 生成
├── flash_all.cmd               # 完整烧录脚本
├── secure_bootloader.hex       # DFU Bootloader
├── private.pem                 # DFU 签名私钥
├── dfu_public_key.c            # DFU 签名公钥
└── README.md                   # 本文件
```

## 故障排除

### 编译错误
- 确保 ARM GCC 工具链已安装
- 确保路径中没有中文或特殊字符
- 检查 SDK 路径是否正确

### DFU 升级失败
- 检查 settings.hex 是否正确烧录
- 检查签名密钥是否匹配
- 确认固件版本号递增

### 连接不稳定
- 检查 RTT 日志中的断开原因
- 确保 SoftDevice 版本正确（S132 v7.2.0）

### LED 无显示
- 检查 PWM 引脚配置（P0.24）
- 确认 SK6812 灯珠焊接正常
- 查看崩溃日志（红色闪烁）


## 更新日志
- *(2026/03/30)* 固件第一版,实现初始灯光颜色修改、切换、APP控制  
- *(2026/03/31)* 固件修正,完善APP基础逻辑修正与交互优化  
- *(2026/04/01)* APP/固件修正,添加APP更新与固件DFU更新  
- *(2026/04/21)* 固件修正,完善休眠逻辑与BLE广播逻辑  
- *(2026/04/28)* 固件/APP功能新增,添加亮度调节与灯光爆闪  



### 鸣谢
> Xiaomi大模型
  - MiMo V2.0-Pro   
  - Mimo V2.5-Pro  

### 固件维护
HikariSame Technology Studio
