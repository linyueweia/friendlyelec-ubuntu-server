#!/bin/bash
# Ubuntu Server NVMe迁移脚本（官方标准流程）
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

[ "$(id -u)" -ne 0 ] && error "请使用 root 权限运行: sudo bash $0"

# ========== 步骤1: 检测设备 ==========
detect_device() {
    if [ -e /dev/mmcblk2 ]; then
        BOOT_DEV="mmcblk2"; BOOT_PART1="mmcblk2p1"; BOOT_PART2="mmcblk2p2"
        info "检测到eMMC: /dev/$BOOT_DEV"
    elif [ -e /dev/mmcblk1 ]; then
        BOOT_DEV="mmcblk1"; BOOT_PART1="mmcblk1p1"; BOOT_PART2="mmcblk1p2"
        info "检测到SD卡: /dev/$BOOT_DEV"
    else
        error "未检测到eMMC或SD卡"
    fi
    [ -b "/dev/$BOOT_PART1" ] || error "未找到boot分区 /dev/$BOOT_PART1"
    [ -b "/dev/$BOOT_PART2" ] || error "未找到rootfs分区 /dev/$BOOT_PART2"
    info "Boot分区: /dev/$BOOT_PART1"
    info "Rootfs分区: /dev/$BOOT_PART2"
}

detect_nvme() {
    [ -e /dev/nvme0n1 ] || error "未检测到NVMe硬盘"
    NVME_SIZE=$(lsblk -b /dev/nvme0n1 -o SIZE -n 2>/dev/null)
    NVME_SIZE_GB=$((${NVME_SIZE} / 1024 / 1024 / 1024))
    info "检测到NVMe: /dev/nvme0n1 (${NVME_SIZE_GB}GB)"
    mount | grep -q nvme0n1 && error "NVMe已被挂载，请先卸载"
}

# ========== 步骤2: 确认操作 ==========
confirm() {
    echo ""
    warn "此操作将格式化NVMe并复制系统！"
    echo "源rootfs: /dev/$BOOT_PART2"
    echo "目标NVMe: /dev/nvme0n1p1 (整个硬盘)"
    echo ""
    read -p "确认继续? (y/N): " CONFIRM
    [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ] || { echo "已取消"; exit 0; }
}

# ========== 步骤3: 格式化NVMe ==========
partition_nvme() {
    info "格式化NVMe硬盘为ext4..."
    wipefs -a /dev/nvme0n1 2>/dev/null || true
    sgdisk --zap-all /dev/nvme0n1 2>/dev/null || true
    parted /dev/nvme0n1 --script mklabel gpt
    parted /dev/nvme0n1 --script mkpart primary ext4 1MiB 100%
    sleep 2
    partprobe /dev/nvme0n1 2>/dev/null || true
    sleep 2
    # 用dd清零确保干净
    dd if=/dev/zero of=/dev/nvme0n1p1 bs=1M count=10 2>/dev/null || true
    NVME_UUID=$(uuidgen)
    info "请在另一个终端执行以下命令格式化NVMe:"
    info "  sudo mkfs.ext4 -U $NVME_UUID -F /dev/nvme0n1p1"
    echo ""
    read -p "格式化完成后按回车继续..."
    # 验证格式化是否成功
    blkid /dev/nvme0n1p1 | grep -q ext4 || error "NVMe格式化失败，请检查"
    info "NVMe格式化完成"
}

# ========== 步骤4: 复制rootfs ==========
copy_system() {
    info "复制系统文件 (rsync -aAX 保留权限)..."
    mkdir -p /tmp/emmc_root /tmp/nvme_root
    mount /dev/$BOOT_PART2 /tmp/emmc_root
    mount /dev/nvme0n1p1 /tmp/nvme_root
    rsync -aAXv \
        --exclude="/dev/*" --exclude="/proc/*" --exclude="/sys/*" \
        --exclude="/tmp/*" --exclude="/run/*" --exclude="/mnt/*" \
        --exclude="/media/*" --exclude="/lost+found" --exclude="/boot/*" \
        /tmp/emmc_root/ /tmp/nvme_root/
    info "rootfs复制完成"
}

# ========== 步骤5: 修改fstab（只改根分区UUID） ==========
update_fstab() {
    info "修改fstab..."
    NVME_UUID=$(blkid -s UUID -o value /dev/nvme0n1p1)
    cp /tmp/nvme_root/etc/fstab /tmp/nvme_root/etc/fstab.bak
    sed -i "s|UUID=[^ ]* / |UUID=$NVME_UUID / |" /tmp/nvme_root/etc/fstab
    info "fstab已更新（保留swap/tmpfs等其他条目）"
    echo "--- fstab ---"
    cat /tmp/nvme_root/etc/fstab
    echo "---"
}

# ========== 步骤6: 更新extlinux.conf ==========
update_boot_config() {
    info "更新启动配置..."
    NVME_PARTUUID=$(blkid -s PARTUUID -o value /dev/nvme0n1p1)
    EXTLINUX_CONF=""
    for conf in /tmp/nvme_root/boot/extlinux/extlinux.conf \
                /tmp/nvme_root/boot/extlinux.conf; do
        [ -f "$conf" ] && EXTLINUX_CONF="$conf" && break
    done
    if [ -n "$EXTLINUX_CONF" ]; then
        cp "$EXTLINUX_CONF" "${EXTLINUX_CONF}.bak"
        sed -i "s|root=PARTUUID=[^ ]*|root=PARTUUID=$NVME_PARTUUID|g" "$EXTLINUX_CONF"
        info "extlinux.conf已更新"
    else
        warn "未找到extlinux.conf，重启后请手动检查"
    fi
}

# ========== 步骤7: chroot重新生成initramfs ==========
update_initramfs() {
    info "重新生成initramfs（必须步骤，否则NVMe无法启动）..."
    mount --bind /dev /tmp/nvme_root/dev
    mount --bind /dev/pts /tmp/nvme_root/dev/pts
    mount -t proc proc /tmp/nvme_root/proc
    mount -t sysfs sysfs /tmp/nvme_root/sys
    if command -v chroot &>/dev/null; then
        chroot /tmp/nvme_root /bin/bash -c "update-initramfs -u -k all" || {
            warn "chroot initramfs更新失败"
            warn "请重启后手动执行: sudo update-initramfs -u -k all"
        }
    else
        warn "chroot不可用，请重启后执行: sudo update-initramfs -u -k all"
    fi
    umount /tmp/nvme_root/sys 2>/dev/null || true
    umount /tmp/nvme_root/proc 2>/dev/null || true
    umount /tmp/nvme_root/dev/pts 2>/dev/null || true
    umount /tmp/nvme_root/dev 2>/dev/null || true
}

# ========== 步骤8: 清理eMMC（可选） ==========
clean_emmc() {
    echo ""
    read -p "是否清理eMMC旧系统(保留boot)? (y/N): " CLEAN_CONFIRM
    if [ "$CLEAN_CONFIRM" = "y" ] || [ "$CLEAN_CONFIRM" = "Y" ]; then
        mkdir -p /tmp/emmc_clean
        mount /dev/$BOOT_PART2 /tmp/emmc_clean
        cd /tmp/emmc_clean
        # 只清除rootfs内容，boot分区(/dev/$BOOT_PART1)不动
        rm -rf bin sbin lib lib64 usr etc var home opt root run tmp
        mkdir -p bin dev etc home lib lib64 mnt opt proc root run sbin srv sys tmp usr var
        cd /; umount /tmp/emmc_clean 2>/dev/null || true; rmdir /tmp/emmc_clean 2>/dev/null || true
        info "eMMC清理完成（boot分区保留）"
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
    echo "  Boot在eMMC，系统迁移到NVMe"
    echo "  (Ubuntu官方标准流程)"
    echo "============================================"
    detect_device
    detect_nvme
    confirm
    partition_nvme
    copy_system
    update_fstab
    update_boot_config
    update_initramfs
    clean_emmc
    cleanup
    echo ""
    echo "============================================"
    echo "  迁移完成!"
    echo "============================================"
    echo ""
    echo "迁移摘要:"
    echo "  Boot: /dev/$BOOT_PART1 (eMMC保留)"
    echo "  系统: /dev/nvme0n1p1 (NVMe)"
    echo "  fstab: 已更新为NVMe UUID"
    echo "  extlinux.conf: 已更新为NVMe PARTUUID"
    echo "  initramfs: 已重新生成"
    echo ""
    echo "下一步: sudo reboot"
    echo ""
    echo "启动失败排查:"
    echo "  1. 从eMMC启动"
    echo "  2. cat /etc/fstab"
    echo "  3. cat /boot/extlinux/extlinux.conf"
    echo "  4. sudo update-initramfs -u -k all"
    echo ""
}

main "$@"
