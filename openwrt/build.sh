#!/bin/bash -e
RED_COLOR='\033[1;31m'
GREEN_COLOR='\033[1;32m'
YELLOW_COLOR='\033[1;33m'
BLUE_COLOR='\033[1;34m'
PINK_COLOR='\033[1;35m'
SHAN='\033[1;33;5m'
RES='\033[0m'

GROUP=
group() {
    endgroup
    echo "::group::  $1"
    GROUP=1
}
endgroup() {
    if [ -n "$GROUP" ]; then
        echo "::endgroup::"
    fi
    GROUP=
}

# 自定义链接地址
export github="github.com"

REPO_URL="https://github.com/${GITHUB_REPOSITORY}"
if [ "$REPO_URL" = "https://github.com/grandway2025/OpenWrt-24.10-Action" ]; then
    export mirror="http://127.0.0.1:8080"
else
    export mirror="https://raw.githubusercontent.com/grandway2025/OpenWrt-24.10-Action/main"
fi

# 检测 Root
if [ "$(id -u)" = "0" ]; then
    export FORCE_UNSAFE_CONFIGURE=1 FORCE=1
fi

# 开始时间
starttime=`date +'%Y-%m-%d %H:%M:%S'`
CURRENT_DATE=$(date +%s)

# 处理器核心数设置
cores=`expr $(nproc --all) + 1`

# 进度条设置
if curl --help | grep progress-bar >/dev/null 2>&1; then
    CURL_BAR="--progress-bar";
fi

SUPPORTED_BOARDS="rockchip x86_64"
if [ -z "$1" ] || ! echo "$SUPPORTED_BOARDS" | grep -qw "$2"; then
    echo -e "\n${RED_COLOR}Building type not specified or unsupported board: '$2'.${RES}\n"
    echo -e "Usage:\n"

    for board in $SUPPORTED_BOARDS; do
        echo -e "$board releases: ${GREEN_COLOR}bash build.sh v24 $board${RES}"
    done
    echo
    exit 1
fi

# 源分支
latest_release="v$(curl -s $mirror/tags/v24)"
export branch=openwrt-24.10
export version=v24

# LAN
[ -n "$LAN" ] && export LAN=$LAN || export LAN=10.0.0.1

# 设备类型
case "$2" in
    rockchip)
        platform="rockchip"
        toolchain_arch="aarch64_generic"
        ;;
    x86_64)
        platform="x86_64"
        toolchain_arch="x86_64"
        ;;
esac
export platform toolchain_arch

# GCC 版本设置
case "$GCC_VERSION" in
  GCC13)
    export gcc_version=13
    ;;
  GCC14)
    export gcc_version=14
    ;;
  GCC15)
    export gcc_version=15
    ;;
esac

echo "👉 已选择 GCC 版本: $gcc_version"


# 脚本定义
export \
    ENABLE_BPF=$ENABLE_BPF \
    ROOT_PASSWORD=$ROOT_PASSWORD

# 打印设备信息
echo -e "\r\n${GREEN_COLOR}Building $branch${RES}\r\n"
case "$platform" in
    x86_64)
        echo -e "${GREEN_COLOR}Model: x86_64${RES}"
        ;;
    rockchip)
        echo -e "${GREEN_COLOR}Model: rockchip${RES}"
        ;;
esac

# 打印构建选项
get_kernel_version=$(curl -s $mirror/tags/kernel-6.6)
kmod_hash=$(echo -e "$get_kernel_version" | awk -F'HASH-' '{print $2}' | awk '{print $1}' | tail -1 | md5sum | awk '{print $1}')
kmodpkg_name=$(echo $(echo -e "$get_kernel_version" | awk -F'HASH-' '{print $2}' | awk '{print $1}')~$(echo $kmod_hash)-r1)
echo -e "${GREEN_COLOR}Kernel: $kmodpkg_name ${RES}"
echo -e "${GREEN_COLOR}Date: $CURRENT_DATE${RES}\r\n"
echo -e "${GREEN_COLOR}SCRIPT_URL:${RES} ${BLUE_COLOR}$mirror${RES}\r\n"
echo -e "${GREEN_COLOR}GCC VERSION: $gcc_version${RES}"
print_status() {
    local name="$1"
    local value="$2"
    local true_color="${3:-$GREEN_COLOR}"
    local false_color="${4:-$YELLOW_COLOR}"
    local newline="${5:-}"
    if [ "$value" = "y" ]; then
        echo -e "${GREEN_COLOR}${name}:${RES} ${true_color}true${RES}${newline}"
    else
        echo -e "${GREEN_COLOR}${name}:${RES} ${false_color}false${RES}${newline}"
    fi
}
[ -n "$LAN" ] && echo -e "${GREEN_COLOR}LAN:${RES} $LAN" || echo -e "${GREEN_COLOR}LAN:${RES} 10.0.0.1"
[ -n "$ROOT_PASSWORD" ] \
    && echo -e "${GREEN_COLOR}Default Password:${RES} ${BLUE_COLOR}$ROOT_PASSWORD${RES}" \
    || echo -e "${GREEN_COLOR}Default Password:${RES} (${YELLOW_COLOR}No password${RES})"
echo -e "${GREEN_COLOR}Standard C Library:${RES} ${BLUE_COLOR}musl${RES}"
echo -e "${GREEN_COLOR}Web Server:${RES} ${BLUE_COLOR}$web_server${RES}"
print_status "ENABLE_OTA"        "$ENABLE_OTA"
print_status "ENABLE_BPF"        "$ENABLE_BPF" "$GREEN_COLOR" "$RED_COLOR"
print_status "ENABLE_LTO"        "$ENABLE_LTO" "$GREEN_COLOR" "$RED_COLOR"
print_status "ENABLE_LOCAL_KMOD" "$ENABLE_LOCAL_KMOD"
print_status "BUILD_FAST"        "$BUILD_FAST" "$GREEN_COLOR" "$YELLOW_COLOR" "\n"

# 清理旧的文件
rm -rf openwrt immortalwrt

# openwrt - 克隆
[ "$(whoami)" = "runner" ] && group "source code"
git clone https://$github/openwrt/openwrt -b $branch
git clone https://$github/immortalwrt/immortalwrt -b $branch

if [ -d openwrt ]; then
    cd openwrt
    curl -Os $mirror/openwrt/patch/key.tar.gz && tar zxf key.tar.gz && rm -f key.tar.gz
    curl -Os $mirror/info.md
else
    echo -e "${RED_COLOR}Failed to download source code${RES}"
    exit 1
fi

# 版本设置
git describe --abbrev=0 --tags > version.txt

# 替换更新源
curl -s $mirror/openwrt/doc/feeds/feeds.conf.default > feeds.conf.default

# 更新并安装源
[ "$(whoami)" = "runner" ] && group "feeds update -a"
./scripts/feeds update -a
[ "$(whoami)" = "runner" ] && endgroup

[ "$(whoami)" = "runner" ] && group "feeds install -a"
./scripts/feeds install -a
[ "$(whoami)" = "runner" ] && endgroup

# 加载程序
if [ -f ../dl.gz ]; then
    tar xf ../dl.gz -C .
fi

###############################################
echo -e "\n${GREEN_COLOR}Patching ...${RES}\n"

# scripts
scripts=(
  00-prepare_base.sh
  01-prepare_package.sh
  02-prepare_adguard_core.sh
# 03-preset_mihimo_core.sh
  04-preset_homeproxy.sh
  06-fix-source.sh
  10-custom.sh
  99_clean_build_cache.sh
)
for script in "${scripts[@]}"; do
  curl -sO "$mirror/openwrt/scripts/$script"
done
if [ "$platform" = "rockchip" ]; then
    curl -sO "$mirror/openwrt/scripts/05-rockchip_target_only.sh"
elif [ "$platform" = "x86_64" ]; then
    curl -sO "$mirror/openwrt/scripts/05-x86_64_target_only.sh"
fi
chmod 0755 *sh
[ "$(whoami)" = "runner" ] && group "patching openwrt"
bash 00-prepare_base.sh
bash 01-prepare_package.sh
bash 02-prepare_adguard_core.sh
# bash 03-preset_mihimo_core.sh
bash 04-preset_homeproxy.sh
bash 06-fix-source.sh
if [ "$platform" = "rockchip" ]; then
    bash 05-rockchip_target_only.sh
    export core=arm64
elif [ "$platform" = "x86_64" ]; then
    bash 05-x86_64_target_only.sh
    export core=amd64
fi
[ -f "10-custom.sh" ] && bash 10-custom.sh
find feeds -type f -name "*.orig" -exec rm -f {} \;
[ "$(whoami)" = "runner" ] && endgroup

rm -f 0*-*.sh 10-custom.sh
rm -rf ../master

# Load devices Config
if [ "$platform" = "x86_64" ]; then
    curl -s $mirror/openwrt/24-config-musl-x86 > .config
elif [ "$platform" = "rockchip" ]; then
    curl -s $mirror/openwrt/24-config-musl-rockchip > .config
fi

# config-common
curl -s $mirror/openwrt/24-config-common >> .config

# ota
[ "$ENABLE_OTA" = "y" ] && [ "$version" = "v24" ] && echo 'CONFIG_PACKAGE_luci-app-ota=y' >> .config

# docker
[ "$ENABLE_DOCKER" = "y" ] && curl -s $mirror/openwrt/generic/config-docker >> .config

# bpf
[ "$ENABLE_BPF" = "y" ] && curl -s $mirror/openwrt/generic/config-bpf >> .config

# LTO
export ENABLE_LTO=$ENABLE_LTO
[ "$ENABLE_LTO" = "y" ] && curl -s $mirror/openwrt/generic/config-lto >> .config

# not all kmod
[ "$NO_KMOD" = "y" ] && sed -i '/CONFIG_ALL_KMODS=y/d' .config

# uhttpd
[ "$web_server" = "uhttpd" ] && sed -i '/nginx/d' .config && echo 'CONFIG_PACKAGE_ariang=y' >> .config

# version
curl -s $mirror/openwrt/generic/config-version >> .config

# local kmod
if [ "$ENABLE_LOCAL_KMOD" = "y" ]; then
    echo -e "\n# local kmod" >> .config
    echo "CONFIG_VERSION_NUMBER="24.10.2" " >> .config
fi

# gcc15 patches
[ "$(whoami)" = "runner" ] && group "patching toolchain"
curl -s $mirror/openwrt/patch/gcc/200-toolchain-gcc-add-support-for-GCC-15.patch | patch -p1

# gcc config
echo -e "\n# gcc ${gcc_version}" >> .config
echo -e "CONFIG_DEVEL=y" >> .config
echo -e "CONFIG_TOOLCHAINOPTS=y" >> .config
echo -e "CONFIG_GCC_USE_VERSION_${gcc_version}=y\n" >> .config
[ "$(whoami)" = "runner" ] && endgroup

# Toolchain Cache
if [ "$BUILD_FAST" = "y" ]; then
    echo -e "\n${GREEN_COLOR}Download Toolchain ...${RES}"
    [ -f /etc/os-release ] && source /etc/os-release
    TOOLCHAIN_URL=https://"$github_proxy"github.com/xianren78/openwrt_caches/releases/download/openwrt-24.10
    curl -L ${TOOLCHAIN_URL}/toolchain_musl_${toolchain_arch}_gcc-${gcc_version}.tar.zst -o toolchain.tar.zst $CURL_BAR
    echo -e "\n${GREEN_COLOR}Process Toolchain ...${RES}"
    tar -I "zstd" -xf toolchain.tar.zst
    rm -f toolchain.tar.zst
    mkdir bin
    find ./staging_dir/ -name '*' -exec touch {} \; >/dev/null 2>&1
    find ./tmp/ -name '*' -exec touch {} \; >/dev/null 2>&1
fi

# init openwrt config
rm -rf tmp/*
if [ "$BUILD" = "n" ]; then
    exit 0
else
    make defconfig
fi

# Compile
if [ "$BUILD_TOOLCHAIN" = "y" ]; then
    echo -e "\r\n${GREEN_COLOR}Building Toolchain ...${RES}\r\n"
    make -j$cores toolchain/compile || make -j$cores toolchain/compile V=s || exit 1
    mkdir -p toolchain-cache
    tar -I "zstd -19 -T$(nproc --all)" -cf toolchain-cache/toolchain_musl_${toolchain_arch}_gcc-${gcc_version}.tar.zst ./{build_dir,dl,staging_dir,tmp}
    echo -e "\n${GREEN_COLOR} Build success! ${RES}"
    exit 0
else
    echo -e "\r\n${GREEN_COLOR}Building OpenWrt ...${RES}\r\n"
    sed -i "/BUILD_DATE/d" package/base-files/files/usr/lib/os-release
    sed -i "/BUILD_ID/aBUILD_DATE=\"$CURRENT_DATE\"" package/base-files/files/usr/lib/os-release
    make -j$cores IGNORE_ERRORS="n m"
fi

# Compile time
endtime=`date +'%Y-%m-%d %H:%M:%S'`
start_seconds=$(date --date="$starttime" +%s);
end_seconds=$(date --date="$endtime" +%s);
SEC=$((end_seconds-start_seconds));

if [ -f bin/targets/*/*/sha256sums ]; then
    echo -e "${GREEN_COLOR} Build success! ${RES}"
    echo -e " Build time: $(( SEC / 3600 ))h,$(( (SEC % 3600) / 60 ))m,$(( (SEC % 3600) % 60 ))s"
else
    echo -e "\n${RED_COLOR} Build error... ${RES}"
    echo -e " Build time: $(( SEC / 3600 ))h,$(( (SEC % 3600) / 60 ))m,$(( (SEC % 3600) % 60 ))s"
    echo
    exit 1
fi

if [ "$platform" = "x86_64" ]; then
    if [ "$NO_KMOD" != "y" ]; then
        cp -a bin/targets/x86/*/packages $kmodpkg_name/
        rm -f $kmodpkg_name/Packages*
        cp -a bin/packages/x86_64/base/rtl88*a-firmware*.ipk $kmodpkg_name/
        cp -a bin/packages/x86_64/base/natflow*.ipk $kmodpkg_name/
        bash kmod-sign $kmodpkg_name
        tar zcf x86_64-$kmodpkg_name.tar.gz $kmodpkg_name
        rm -rf $kmodpkg_name
    fi      
### People come and go, we struggled with laughter and tears,and all the years have gone by,still Ihave you by my side. 你陪了我多少年，花开花落。一路上起起跌跌 ###
