#!/bin/bash
##### https://github.com/itiligent/Resize-SquashFS
#######################################################################################################################
# Enlarge default SquashFS partitions for OpenWRT x86 builds and convert new raw images to vmdk
# FOR x86 BUILDS TO HDD/VM/MMC ONLY! (Not for use with router flash memory - you've been warned!!)
# David Harrop
# April 2023
#######################################################################################################################

clear

# Select the OWRT version to build
#BUILDER="https://downloads.openwrt.org/releases/22.03.5/targets/x86/64/openwrt-imagebuilder-22.03.5-x86-64.Linux-x86_64.tar.xz"
#BUILDER="https://downloads.openwrt.org/snapshots/targets/x86/64/openwrt-imagebuilder-x86-64.Linux-x86_64.tar.xz" # Current snapshot
BUILDER="https://chinanet.mirrors.ustc.edu.cn/openwrt/releases/22.03.5/targets/x86/64/openwrt-imagebuilder-22.03.5-x86-64.Linux-x86_64.tar.xz"

# Select the desired SquashFS partition sizes in MB
KERNEL_PARTSIZE=64 # in MB
ROOTFS_PARTSIZE=4096 # in MB (values over 8192 may give memory exhaustion errors)

# Add your choice of custom packages here
CUSTOM_PACKAGES="blockd block-mount curl dnsmasq -dnsmasq-full kmod-fs-ext4 kmod-usb2 kmod-usb3 kmod-usb-storage kmod-usb-core \
    usbutils nano socat tcpdump luci -luci-app-ddns luci-app-mwan3 mwan3 luci-app-openvpn openvpn-openssl \
    wsdd2 luci-app-sqm sqm-scripts sqm-scripts-extra kmod-usb-net wpad-basic-wolfssl \
	kmod-nvme \
    kmod-usb-net-asix-ax88179 kmod-mt7921u kmod-usb-net-rndis kmod-usb-net-ipheth usbmuxd libimobiledevice \
    iptables-mod-ipopt auc luci-app-attendedsysupgrade smcroute mcproxy python3-light python3-netifaces open-vm-tools" 
    # luci-app-samba4

# This ID tag will be added to the completed image filename
IMAGE_TAG="BigSquash"

# Setup the image builder working environment 
SOURCE_FILE="${BUILDER##*/}" # Separate the tar.xz file name from the link
SOURCE_DIR="${SOURCE_FILE%%.tar.xz}" # Get the uncompressed tar.xz directory name
BUILD_ROOT="$(pwd)/owrt_builds"
OUTPUT="${BUILD_ROOT}/images"
VMDK="${BUILD_ROOT}/vmdk"
INJECT_FILES="$(pwd)/owrt_inject_files"
BUILD_LOG="${BUILD_ROOT}/build.log"

# Clear out any previous builds
rm -rf "${BUILD_ROOT}"
rm -rf "${SOURCE_DIR}"

# Create the destination directories
mkdir -pv "${BUILD_ROOT}"
mkdir -pv "${OUTPUT}"
mkdir -pv "${VMDK}"
mkdir -pv "${INJECT_FILES}"

# Prepare text output colours
LYELLOW='\033[0;93m'
NC='\033[0m' #No Colou

# Option to preconfigure images with injected config files
echo
echo -e "${LYELLOW}Image Builder activity will be logged to ${BUILD_LOG}"
echo
read -p $"Copy image config files to ${INJECT_FILES} now. Enter to continue..."
echo -e ${NC}

# Install OWRT build system dependencies for recent Ubuntu/Debian.
# See here for other distro dependencies: https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem
# sudo apt-get update  2>&1 | tee -a ${BUILD_LOG}
# sudo apt-get install -y build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
# gettext git libncurses-dev libssl-dev python3-distutils rsync unzip zlib1g-dev file wget qemu-utils 2>&1 | tee -a ${BUILD_LOG}

# Download the image builder source if we haven't already
if [ ! -f "${BUILDER##*/}" ]; then
    wget -q --show-progress "$BUILDER"
    tar xJvf "${BUILDER##*/}" --checkpoint=.100 2>&1 | tee -a ${BUILD_LOG}
fi

# Uncompress if the source tar.xz exists but the uncompressed source directory is not present.
if [ -n "${SOURCE_DIR}" ]; then
    tar xJvf "${BUILDER##*/}" --checkpoint=.100 2>&1 | tee -a ${BUILD_LOG}
fi

# Patch the source partition size config settings
sed -i "s/CONFIG_TARGET_KERNEL_PARTSIZE=.*/CONFIG_TARGET_KERNEL_PARTSIZE=$KERNEL_PARTSIZE/g" "$PWD/$SOURCE_DIR/.config"
sed -i "s/CONFIG_TARGET_ROOTFS_PARTSIZE=.*/CONFIG_TARGET_ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE/g" "$PWD/$SOURCE_DIR/.config"

# Patch for source partition size config settings giving errors https://forum.openwrt.org/t/22-03-3-image-builder-issues/154168
sed -i '/\$(CONFIG_TARGET_ROOTFS_PARTSIZE) \$(IMAGE_ROOTFS)/,/256/ s/256/'"$ROOTFS_PARTSIZE"'/' "$PWD/$SOURCE_DIR/target/linux/x86/image/Makefile"

# Patch repositories.conf

sed -e 's,https://downloads.openwrt.org,https://chinanet.mirrors.ustc.edu.cn/openwrt,g' -i.bak "$PWD/$SOURCE_DIR/repositories.conf"

# Start a clean image build with the selected packages
cd $(pwd)/"${SOURCE_DIR}"/
make clean 2>&1 | tee -a ${BUILD_LOG}
make image PROFILE="generic" PACKAGES="${CUSTOM_PACKAGES}" EXTRA_IMAGE_NAME="${IMAGE_TAG}" FILES="${INJECT_FILES}" BIN_DIR="${OUTPUT}" 2>&1 | tee -a ${BUILD_LOG}

# Copy the new images to a separate directory for conversion to vmdk
cp -v $OUTPUT/*.gz $VMDK

# Create a list of new images to unzip
for LIST in $VMDK/*img.gz
do
    echo $LIST
    gunzip $LIST
done

# Convert the unzipped images to vmdk
for LIST in $VMDK/*.img
do
    echo $LIST
    qemu-img convert -f raw -O vmdk $LIST $LIST.vmdk 2>&1 | tee -a ${BUILD_LOG}
done

# Clean up
rm -v $VMDK/*.img
