#!/bin/bash
# FriendlyELEC设备编译脚本
# 支持: nanopc-t4, nanopi-r6c

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

BUILD_DIR="$(pwd)"
WORK_DIR="${BUILD_DIR}/work"

# 设备配置
declare -A DEVICE_CONFIG=(
    ["nanopc-t4"]="rk3399|sd-fuse_rk3399|kernel-6.6.y|ubuntu-noble-minimal-arm64|https://downloads.friendlyelec.com/os-images/rk3399/images"
    ["nanopi-r6c"]="rk3588|sd-fuse_rk3588|kernel-6.1.y|ubuntu-noble-minimal-arm64|https://downloads.friendlyelec.com/os-images/rk3588/images"
)

usage() {
    echo "用法: $0 <设备名>"
    echo ""
    echo "支持的设备:"
    echo "  nanopc-t4   - NanoPC-T4 (RK3399)"
    echo "  nanopi-r6c  - NanoPi R6C (RK3588S)"
    echo ""
    echo "示例:"
    echo "  sudo ./build.sh nanopc-t4"
    echo "  sudo ./build.sh nanopi-r6c"
    exit 1
}

if [ $# -eq 0 ] || [ -z "${DEVICE_CONFIG[$1]}" ]; then
    usage
fi

DEVICE="$1"
IFS='|' read -r SOC SDK_REPO KERNEL_BRANCH TARGET_OS IMAGE_URL <<< "${DEVICE_CONFIG[$DEVICE]}"

info "目标设备: $DEVICE"
info "SoC: $SOC"
info "SDK: $SDK_REPO"
info "内核: $KERNEL_BRANCH"
info "系统: $TARGET_OS"

# 清理
clean() {
    info "清理..."
    rm -rf ${WORK_DIR}
    info "清理完成"
}

# 克隆源码
clone() {
    info "克隆FriendlyELEC源码..."
    mkdir -p ${WORK_DIR}
    cd ${WORK_DIR}
    
    [ ! -d "${SDK_REPO}" ] && git clone --depth 1 -b ${KERNEL_BRANCH} https://github.com/friendlyarm/${SDK_REPO}.git
    
    cd ${SDK_REPO}
    if [ ! -d "${TARGET_OS}" ]; then
        info "下载预编译镜像..."
        wget -q ${IMAGE_URL}/${TARGET_OS}-images-*.tgz
        tar xvzf ${TARGET_OS}-images-*.tgz
    fi
    
    cd ${BUILD_DIR}
    info "源码准备完成"
}

# 构建镜像
build() {
    info "构建SD卡镜像..."
    cd ${WORK_DIR}/${SDK_REPO}
    ./mk-sd-image.sh ${TARGET_OS}
    cd ${BUILD_DIR}
    info "镜像构建完成"
}

# 重命名固件
rename() {
    info "重命名固件..."
    cd ${WORK_DIR}/${SDK_REPO}/out
    VERSION="24.04.4"
    NEW_NAME="${DEVICE}-ubuntu-server-${VERSION}.img"
    mv ${SOC}-sd-*.img ${NEW_NAME}
    ls -lh *.img
    cd ${BUILD_DIR}
}

case "$1" in
    clean)
        clean
        ;;
    *)
        clone
        build
        rename
        info "完成！镜像: ${WORK_DIR}/${SDK_REPO}/out/*.img"
        ;;
esac
