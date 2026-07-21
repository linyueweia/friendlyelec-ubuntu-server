#!/bin/bash
# Ubuntu Server NVMe迁移脚本
# 将系统从eMMC迁移到NVMe盘，Boot保留在eMMC
# 用法: sudo bash migrate-to-nvme.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
    error "请使用 root 权限运行: sudo bash $0"
fi

detect_device() {
    if [ -e /dev/mmcblk2 ]; then
        BOOT_DEV="mmcblk2"
        BOOT_PART="mmcblk2p2"
        info "检测到eMMC: /dev/$BOOT_DEV"
    elif [ -e /dev/mmcblk1 ]; then
        BOOT_DEV="mmcblk1"
        BOOT_PART="mmcblk1p2"
        info "检测到SD卡: /dev/$BOOT_DEV"
    else
        error "未检测到eMMC或SD卡"
    fi
}

detect_nvme() {
    if [ ! -e /dev/nvme0n1 ]; then
        error "未检测到NVMe硬盘"
    fi
    NVME_SIZE=$(lsblk -b /dev/nvme0n1 -o SIZE -n 2>/dev/null)
    NVME_SIZE_GB=$((${NVME_SIZE} / 1024 / 1024 / 1024))
    info "检测到NVMe: /dev/nvme0n1 (${NVME_SIZE_GB}GB)"
}

confirm() {
    echo ""
    warn "警告: 此操作将格式化NVMe硬盘并复制系统!"
    warn "NVMe将使用整个硬盘空间"
    echo "源: /dev/$BOOT_PART (eMMC/SD卡)"
    echo "目标: /dev/nvme0n1 (NVMe整个硬盘)"
    echo ""
    read -p "确认继续? (y/N): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "已取消"
        exit 0
    fi
}

partition_nvme() {
    info "分区NVMe硬盘（使用整个硬盘）..."
    wipefs -a /dev/nvme0n1 2>/dev/null || true
    parted /dev/nvme0n1 --script mklabel gpt
    parted /dev/nvme0n1 --script mkpart primary ext4 1MiB 100%
    sleep 2
    info "分区完成 - 整个NVMe硬盘用作rootfs"
}

copy_system() {
    info "复制系统文件..."
    mkdir -p /tmp/nvme_root /tmp/emmc_root
    
    mount /dev/$BOOT_PART /tmp/emmc_root 2>/dev/null || mount /dev/${BOOT_PART}p2 /tmp/emmc_root
    mount /dev/nvme0n1p1 /tmp/nvme_root
    
    info "复制rootfs (可能需要几分钟)..."
    rsync -aAXv --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} /tmp/emmc_root/ /tmp/nvme_root/
    
    info "文件复制完成"
}

update_fstab() {
    info "更新 fstab..."
    NVME_UUID=$(blkid -s UUID -o value /dev/nvme0n1p1)
    info "NVMe UUID: $NVME_UUID"
    
    cat > /tmp/nvme_root/etc/fstab << FSTABEOF
# <file system> <mount point> <type> <options> <dump> <pass>
UUID=$NVME_UUID / ext4 errors=remount-ro 0 1
FSTABEOF
    
    info "fstab 更新完成"
    cat /tmp/nvme_root/etc/fstab
}

update_boot_config() {
    info "更新启动配置..."
    
    NVME_PARTUUID=$(blkid -s PARTUUID -o value /dev/nvme0n1p1)
    info "NVMe PARTUUID: $NVME_PARTUUID"
    
    # 更新extlinux.conf
    if [ -f /tmp/nvme_root/boot/extlinux/extlinux.conf ]; then
        info "更新 extlinux.conf..."
        sed -i "s|root=PARTUUID=[^ ]*|root=PARTUUID=$NVME_PARTUUID|g" /tmp/nvme_root/boot/extlinux/extlinux.conf
    fi
    
    # 更新boot.txt
    if [ -f /tmp/nvme_root/boot/boot.txt ]; then
        info "更新 boot.txt..."
        sed -i "s|root=PARTUUID=[^ ]*|root=PARTUUID=$NVME_PARTUUID|g" /tmp/nvme_root/boot/boot.txt
    fi
    
    info "启动配置更新完成"
}

clean_emmc() {
    echo ""
    read -p "是否清理eMMC上的旧系统? (y/N): " CLEAN_CONFIRM
    if [ "$CLEAN_CONFIRM" = "y" ] || [ "$CLEAN_CONFIRM" = "Y" ]; then
        info "清理eMMC旧系统（保留boot分区）..."
        
        mkdir -p /tmp/emmc_clean
        mount /dev/$BOOT_PART /tmp/emmc_clean 2>/dev/null || mount /dev/${BOOT_PART}p2 /tmp/emmc_clean
        
        info "删除旧系统文件..."
        cd /tmp/emmc_clean
        rm -rf bin boot dev etc home lib lib64 lost+found media mnt opt proc root run sbin srv sys tmp usr var
        
        mkdir -p boot dev proc sys tmp
        
        cd /
        umount /tmp/emmc_clean 2>/dev/null || true
        rmdir /tmp/emmc_clean 2>/dev/null || true
        
        info "eMMC清理完成 - 只保留boot分区"
    else
        info "跳过eMMC清理"
    fi
}

cleanup() {
    umount /tmp/nvme_root 2>/dev/null || true
    umount /tmp/emmc_root 2>/dev/null || true
    rm -rf /tmp/nvme_root /tmp/emmc_root
}

main() {
    echo "============================================"
    echo "  Ubuntu Server NVMe 迁移工具"
    echo "  Boot在eMMC，系统迁移到NVMe整个硬盘"
    echo "============================================"
    echo ""
    
    detect_device
    detect_nvme
    confirm
    partition_nvme
    copy_system
    update_fstab
    update_boot_config
    clean_emmc
    cleanup
    
    echo ""
    echo "============================================"
    echo "  迁移完成!"
    echo "============================================"
    echo ""
    echo "下一步:"
    echo "1. 重启设备"
    echo "2. 系统将从NVMe启动（Boot仍在eMMC）"
    echo ""
}

main "$@"
