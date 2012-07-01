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

TARGET_ZIP=stock+_$(date +%Y-%m-%d).zip

make clean
make cyanogenmod_vibrantmtd_defconfig
make -j4

if [[ $? != 0 ]]; then
    echo "${RED}Build failed! Please see the errors above and correct them.${RESET}"
    exit 1
fi

echo "${GREEN}Build succeeded!${RESET}"
echo "${GREEN}Packing up...${RESET}"

ZIMAGE=`readlink -f arch/arm/boot/zImage`
if [ ! -e $ZIMAGE ]; then
    echo "${RED}Failed to find zImage{$RESET}"
    exit 1
fi

if [ -e staging/tmp ]; then
    rm -rf staging/tmp
fi

mkdir staging/tmp

# Create boot.img
./staging/mkshbootimg.py staging/tmp/boot.img $ZIMAGE staging/ramdisk.img staging/ramdisk-recovery.img

# Copy over package files
cp -R staging/package/* staging/tmp

# Find modules
MODULES=$(find -name *.ko)
for MODULE in $MODULES; do
    cp $MODULE staging/tmp/system/lib/modules/
done

if [ ! -e out ]; then
    mkdir out
fi

# Zip it up!
cd staging/tmp
zip -r ../../out/$TARGET_ZIP .
cd ../..

echo "${GREEN}Done! Package: out/${TARGET_ZIP}${RESET}"
