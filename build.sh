#!/bin/bash

# Colors
RESET=$(tput sgr0)
BLUE=$(tput setaf 4)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)

# Setup environment
export ARCH=arm
export CROSS_COMPILE=staging/toolchain/bin/arm-eabi-

# Setup source symlink
if [ ! -L source ]; then
    ln -s . source
fi

function build_root_ramdisk
{
    echo "${GREEN}Building root ramdisk...${RESET}"
    rm -f staging/ramdisk.img
    cd staging/ramdisk
    find . | cpio -o -H newc | gzip > ../ramdisk.img
    cd ../..
}

function build_recovery_ramdisk
{
    echo "${GREEN}Building recovery ramdisk...${RESET}"
    rm -f staging/ramdisk-recovery.img
    cd staging/ramdisk-recovery
    find . | cpio -o -H newc | gzip > ../ramdisk-recovery.img
    cd ../..
}

function build_kernel
{
    echo "${GREEN}Building kernel...${RESET}"
    make clean
    make cyanogenmod_vibrantmtd_defconfig
    make -j4

    if [[ $? != 0 ]]; then
        error "Build failed! Please see the errors above and correct them."
    fi

    echo "${GREEN}Build succeeded!${RESET}"
}

function error
{
    MSG=$1
    echo "${RED}ERROR:${RESET} ${MSG}"
    exit 1
}

for OPT in $(echo "$*" | tr "+" "\n"); do
    if [ "$OPT" = "clean" ]; then
        echo "${GREEN}Cleaning...${RESET}"
        rm -rf \
            staging/tmp
        make clean
    fi
done

for CMD in $(echo "$*" | tr "+" "\n"); do
    if [ "$CMD" = "root" ]; then
        build_root_ramdisk
    elif [ "$CMD" = "recovery" ]; then
        build_recovery_ramdisk
    elif [ "$CMD" = "kernel" ]; then
        build_kernel
    fi
done

VERSION=$(cat Makefile | grep '_Arbiter_' | cut -d "_" -f 3)
TARGET="CM9"
TARGET_ZIP=Arbiter_${VERSION}_${TARGET}.zip

ZIMAGE=`readlink -f arch/arm/boot/zImage`
test -e $ZIMAGE || error "zImage not found at ${ZIMAGE}"

if [ ! -e staging/tmp ]; then
    mkdir staging/tmp
fi

test -e staging/ramdisk.img || error "Root ramdisk not found!"
test -e staging/ramdisk-recovery.img || error "Recovery ramdisk not found!"
gzip -t staging/ramdisk.img &> /dev/null || error "Root ramdisk is not a valid gzip archive!"
gzip -t staging/ramdisk-recovery.img &> /dev/null || error "Recovery ramdisk not a valid gzip archive!"

echo "${GREEN}Packing up...${RESET}"

# Create boot.img
./staging/mkshbootimg.py staging/tmp/boot.img $ZIMAGE staging/ramdisk.img staging/ramdisk-recovery.img

# Copy over package files
cp -R staging/package/* staging/tmp

SEDS="s/\${VERSION}/${VERSION}/"
SEDS="s/\${TARGET}/${TARGET}/;$SEDS"

sed -i ${SEDS} \
    staging/tmp/META-INF/com/google/android/updater-script

# Find modules
MODULES=$(find -name *.ko)
for MODULE in $MODULES; do
    MODULE_NAME=$(basename $MODULE)
    TARGET_MODULE=staging/tmp/system/lib/modules/$MODULE_NAME
    # Update modules (if they differ)
    if [[ ! -e $TARGET_MODULE || $(md5sum $MODULE | cut -d " " -f 1) != \
          $(md5sum $TARGET_MODULE | cut -d " " -f 1) ]]; then
        echo "${GREEN}Target module:${RESET} ${MODULE_NAME}"
        cp $MODULE staging/tmp/system/lib/modules/
    fi
done

if [ ! -e out ]; then
    mkdir out
fi

# Zip it up!
cd staging/tmp
zip -r ../../out/$TARGET_ZIP .
cd ../..

# Clean
find -name *.o -exec rm -f {} \;

echo "${GREEN}Done! Package: out/${TARGET_ZIP}${RESET}"
