# FriendlyELEC Ubuntu Server 24.04 编译系统

支持多个FriendlyELEC设备的Ubuntu Server 24.04编译系统。

## 支持设备

| 设备 | SoC | 内核 | 状态 |
|------|------|------|------|
| NanoPC-T4 | RK3399 | 6.6.y | ✅ 支持 |
| NanoPi R6C | RK3588S | 6.1.y | ✅ 支持 |

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

### 本地编译

```bash
git clone https://github.com/linyueweia/friendlyelec-ubuntu-server.git
cd friendlyelec-ubuntu-server
sudo -S -p '' ./build.sh nanopc-t4  # 或 nanopi-r6c
```

## 刷机方法

直接将固件用写盘工具写入NVMe硬盘，插上就能启动。不需要SD卡，前提是需要动eMMC（清空eMMC后才能从NVMe启动）。

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
