# HikariStick DFU 使用指南

## 当前状态
- ✅ Bootloader 已刷入 (secure_bootloader.hex)
- ✅ 应用固件已编译
- ✅ DFU 签名密钥已生成

## 重要说明

### 关于 UICR
**不要手动烧录 UICR！** Bootloader 会在首次启动时自动写入 UICR。
如果手动烧录 UICR 会导致启动问题。

### 正确的烧录方式

使用第三方工具烧录时，只需要烧录：

1. **SoftDevice** (如果尚未烧录)
   - 地址: 0x00000
   - 文件: s132_nrf52_7.3.0_softdevice.hex

2. **Application**
   - 地址: 0x26000
   - 文件: _build/nrf52832_xxaa.hex

3. **Bootloader** (如果尚未烧录)
   - 地址: 0x78000
   - 文件: secure_bootloader.hex
   - 注意：不要烧录 UICR 区域

## 烧录步骤

### 方案 A：使用第三方工具

```
1. 擦除芯片
2. 烧录 SoftDevice (0x00000)
3. 烧录 Application (0x26000)
4. 烧录 Bootloader (0x78000)，不要烧录 UICR
5. 复位设备
```

### 方案 B：只更新应用固件

如果 Bootloader 和 SoftDevice 已存在：

```
1. 擦除 Application 区域 (0x26000 - 0x77FFF)
2. 烧录 _build/nrf52832_xxaa.hex
3. 复位设备
```

## DFU 工作流程

### 首次使用
1. 烧录固件（按上述步骤）
2. 设备启动，显示设备名 HikariStick-XXXX
3. 连接 APP

### 后续更新（OTA）
1. APP 检查更新
2. 下载固件包
3. 点击"开始更新"
4. 设备自动进入 DFU 模式
5. 更新完成，设备自动重启

## 文件说明

| 文件 | 用途 |
|------|------|
| _build/nrf52832_xxaa.hex | 应用固件 |
| secure_bootloader.hex | DFU Bootloader |
| private.pem | DFU 签名私钥 |
| dfu_package.cmd | 生成 DFU 包 |
| flash_app.cmd | 烧录应用固件说明 |

## 故障排除

### Q: 设备无法启动
A: 检查是否烧录了 UICR。如果烧录了，需要擦除芯片重新烧录（不要烧录 UICR）

### Q: DFU 更新失败
A: 检查：
1. Bootloader 是否正确烧录
2. 私钥是否匹配
3. 固件包是否使用正确的私钥签名

### Q: 如何生成 DFU 包
A: 运行: `dfu_package.cmd 2.2.0`
   生成: firmware_v2.2.0.zip

## 内存布局

```
0x00000 ┐ MBR
0x01000 ├ SoftDevice S132 v7.3.0 (~152KB)
0x26000 ├ Application (~328KB)
0x78000 ├ Secure DFU Bootloader (~24KB)
0x7E000 ├ MBR Parameters (自动管理)
0x7F000 ┘ Bootloader Settings (自动管理)
```
