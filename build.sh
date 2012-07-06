#!/bin/bash

# Colors
RESET=$(tput sgr0)
BLUE=$(tput setaf 4)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)

# Variables
IS_JELLYBEAN=false

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
    if $IS_JELLYBEAN ; then
        touch staging/ramdisk-is-jellybean
        cd staging/jellybean_ramdisk
    else
        rm -f staging/ramdisk-is-jellybean
        cd staging/ramdisk
    fi
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

function set_jb
{
    IS_JELLYBEAN=true
}

for CMD in $(echo "$*" | tr "+" "\n"); do
    if [ "$CMD" = "root" ]; then
        build_root_ramdisk
    elif [ "$CMD" = "recovery" ]; then
        build_recovery_ramdisk
    elif [ "$CMD" = "kernel" ]; then
        build_kernel
    elif [ "$CMD" = "jb" ]; then
        set_jb
    fi
done

VERSION=$(cat Makefile | grep '_Arbiter_' | cut -d "_" -f 3)
EXTRA="_CM9"
if [[ $IS_JELLYBEAN == true ]]; then
    EXTRA="_JB"
fi
TARGET_ZIP=Arbiter_${VERSION}${EXTRA}.zip

ZIMAGE=`readlink -f arch/arm/boot/zImage`
test -e $ZIMAGE || error "zImage not found at ${ZIMAGE}"

if [ ! -e staging/tmp ]; then
    mkdir staging/tmp
fi

if [[ -e staging/ramdisk-is-jellybean && $IS_JELLYBEAN == false ]]; then
    error "Ramdisk is made for Jelly Bean, please rebuild."
fi

if [[ ! -e staging/ramdisk-is-jellybean && $IS_JELLYBEAN == true ]]; then
    error "Ramdisk is made for CM9, please rebuild."
fi

test -e staging/ramdisk.img || error "Root ramdisk not found!"
test -e staging/ramdisk-recovery.img || error "Recovery ramdisk not found!"

echo "${GREEN}Packing up...${RESET}"

# Create boot.img
./staging/mkshbootimg.py staging/tmp/boot.img $ZIMAGE staging/ramdisk.img staging/ramdisk-recovery.img

# Copy over package files
cp -R staging/package/* staging/tmp

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
