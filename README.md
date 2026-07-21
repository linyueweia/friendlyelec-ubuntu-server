# FriendlyELEC Ubuntu Server 24.04 编译系统

支持多个FriendlyELEC设备的Ubuntu Server 24.04编译系统。

## 支持设备

| 设备 | SoC | 内核 | 状态 |
|------|------|------|------|
| NanoPC-T4 | RK3399 | 6.6.y | ✅ 支持 |
| NanoPi R6C | RK3588S | 6.1.y | ✅ 支持 |

> RK3399/RK3588S 的 Boot ROM 不支持直接从 NVMe 启动（硬件限制），Boot 必须留在 eMMC 或 SD 卡。

## 下载

在 [Actions](https://github.com/linyueweia/friendlyelec-ubuntu-server/actions) 页面，点击最近的成功构建，下载对应设备的固件。

## 使用方法

### 编译指定设备

```bash
# 编译NanoPC-T4固件
sudo -S -p '' ./build.sh nanopc-t4

# 编译NanoPi R6C固件
sudo -S -p '' ./build.sh nanopi-r6c
```

## 刷机方法

### 方案1: USB 线刷到 eMMC（推荐）
1. 设备按住 Recovery 按钮，用 Type-C USB 线连接电脑
2. 打开 RKDevTool → Upgrade Firmware → 选择固件
3. 点击 Upgrade 等待刷入完成

### 方案2: SD 卡启动
使用写盘工具将固件写入SD卡，然后插入设备启动。

### 方案3: eMMC + NVMe 组合（推荐，系统在NVMe）
1. 先将Ubuntu刷入eMMC（方案1或方案2）
2. 从eMMC启动后，运行NVMe迁移脚本：
```bash
sudo -S -p '' bash scripts/migrate-to-nvme.sh
```
3. 重启设备，Boot在eMMC，系统在NVMe整个硬盘

## NVMe迁移脚本

将系统从eMMC迁移到NVMe盘，Boot保留在eMMC。

| 步骤 | 说明 |
|------|------|
| 1. 检测设备 | 自动检测eMMC/SD卡和NVMe |
| 2. 确认操作 | 提示用户确认（防止误操作） |
| 3. 分区NVMe | 整个NVMe硬盘用作rootfs |
| 4. 复制系统 | 使用rsync复制rootfs |
| 5. 更新fstab | 自动更新UUID指向NVMe |
| 6. 更新启动配置 | 更新extlinux.conf/boot.txt中的PARTUUID |
| 7. 清理eMMC | 询问是否清理，保留boot分区，清除旧系统 |

### 注意事项
- 迁移前确保eMMC已有系统
- 迁移会格式化NVMe硬盘
- 迁移完成后需要重启设备

## 设备规格

### NanoPC-T4 (RK3399)

| 项目 | 规格 |
|------|------|
| SoC | Rockchip RK3399 |
| CPU | 双核Cortex-A72 + 四核Cortex-A53 |
| 内存 | 最高4GB DDR3 |
| 存储 | eMMC + SD卡 + NVMe |

### NanoPi R6C (RK3588S)

| 项目 | 规格 |
|------|------|
| SoC | Rockchip RK3588S |
| CPU | 四核Cortex-A76 + 四核Cortex-A55 |
| 内存 | 4GB/8GB LPDDR4X |
| 存储 | eMMC + SD卡 + NVMe |
| 网络 | 2.5G以太网 |

## 致谢

- [FriendlyELEC](https://www.friendlyelec.com/) - 硬件支持
- [Rockchip](https://www.rock-chips.com/) - RK3399/RK3588S SDK
