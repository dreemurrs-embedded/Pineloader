## Copyright 2020 - Dreemurrs Embedded Labs / DanctNIX
## Copyright 2020 - Martijn Braam

## SPDX-License-Identifier: GPL-2.0-only

CROSS_FLAGS = ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
CROSS_FLAGS_BOOT = CROSS_COMPILE=aarch64-linux-gnu-

all: pine64-pinephone.img.xz pine64-pinetab.img.xz


pine64-pinephone.img: fat-pine64-pinephone.img u-boot-sunxi-with-spl.bin
	rm -f $@
	truncate --size 50M $@
	parted -s $@ mktable msdos
	parted -s $@ mkpart primary fat32 2048s 100%
	parted -s $@ set 1 boot on
	dd if=u-boot-sunxi-with-spl.bin of=$@ bs=8k seek=1
	dd if=fat-$@ of=$@ seek=1024 bs=1k

fat-pine64-pinephone.img: initramfs-pine64-pinephone.gz kernel-sunxi.gz pine64-pinephone.scr dtbs/sunxi/sun50i-a64-pinephone-1.0.dtb
	@echo "MKFS  $@"
	@rm -f $@
	@truncate --size 40M $@
	@mkfs.fat -F32 $@
	
	@mcopy -i $@ kernel-sunxi.gz ::Image.gz
	@mcopy -i $@ dtbs/sunxi/sun50i-a64-pinephone-1.0.dtb ::sun50i-a64-pinephone-1.0.dtb
	@mcopy -i $@ initramfs-pine64-pinephone.gz ::initramfs.gz
	@mcopy -i $@ pine64-pinephone.scr ::boot.scr

pine64-pinetab.img: fat-pine64-pinetab.img u-boot-sunxi-with-spl.bin
	rm -f $@
	truncate --size 50M $@
	parted -s $@ mktable msdos
	parted -s $@ mkpart primary fat32 2048s 100%
	parted -s $@ set 1 boot on
	dd if=u-boot-sunxi-with-spl.bin of=$@ bs=8k seek=1
	dd if=fat-$@ of=$@ seek=1024 bs=1k

fat-pine64-pinetab.img: initramfs-pine64-pinetab.gz kernel-sunxi.gz pine64-pinetab.scr dtbs/sunxi/sun50i-a64-pinetab.dtb
	@echo "MKFS  $@"
	@rm -f $@
	@truncate --size 40M $@
	@mkfs.fat -F32 $@
	
	@mcopy -i $@ kernel-sunxi.gz ::Image.gz
	@mcopy -i $@ dtbs/sunxi/sun50i-a64-pinetab.dtb ::sun50i-a64-pinetab.dtb
	@mcopy -i $@ initramfs-pine64-pinetab.gz ::initramfs.gz
	@mcopy -i $@ pine64-pinetab.scr ::boot.scr

%.img.xz: %.img
	@echo "XZ    $@"
	@xz -c $< > $@

initramfs/bin/busybox: src/busybox src/busybox_config
	@echo "MAKE  $@"
	@mkdir -p build/busybox
	@cp src/busybox_config build/busybox/.config
	@$(MAKE) -C src/busybox O=../../build/busybox $(CROSS_FLAGS)
	@cp build/busybox/busybox initramfs/bin/busybox

initramfs/bin/bash: src/bash
	@echo "MAKE  $@"
	@mkdir -p build/bash
	@cd build/bash;\
	../../src/bash/configure --host=aarch64-linux-gnu --enable-static-link --without-bash-malloc
	@$(MAKE) -C build/bash
	@aarch64-linux-gnu-strip build/bash/bash
	@upx --best build/bash/bash
	@cp build/bash/bash initramfs/bin/bash

initramfs/bin/kexec: src/kexec-tools
	@echo "MAKE  $@"
	@mkdir -p build/kexec-tools
	@cd src/kexec-tools;./bootstrap
	@cd build/kexec-tools;\
	LDFLAGS=-static ../../src/kexec-tools/configure --host=aarch64-linux-gnu
	@$(MAKE) -C build/kexec-tools
	@aarch64-linux-gnu-strip build/kexec-tools/build/sbin/kexec
	@cp build/kexec-tools/build/sbin/kexec initramfs/bin/kexec

initramfs-%.cpio: initramfs/bin/busybox initramfs/bin/bash initramfs/bin/kexec initramfs/init initramfs/init_functions.sh initramfs/pineloader
	@echo "CPIO  $@"
	@rm -rf initramfs-$*
	@cp -r initramfs initramfs-$*
	@cp src/info-$*.sh initramfs-$*/info.sh
	@cp src/info-$*.sh initramfs-$*/info.sh
	@cd initramfs-$*; find . | cpio -H newc -o > ../$@
	
initramfs-%.gz: initramfs-%.cpio
	@echo "GZ    $@"
	@gzip < $< > $@
	
kernel-sunxi.gz dtbs/sunxi/sun50i-a64-pinephone-1.0.dtb dtbs/sunxi/sun50i-a64-pinetab.dtb &: src/linux_config_sunxi
	@echo "MAKE  kernel-sunxi.gz"
	@mkdir -p build/linux-sunxi
	@mkdir -p dtbs/sunxi
	@cp src/linux_config_sunxi build/linux-sunxi/.config
	@$(MAKE) -C src/linux O=../../build/linux-sunxi $(CROSS_FLAGS) olddefconfig
	@$(MAKE) -C src/linux O=../../build/linux-sunxi $(CROSS_FLAGS)
	@cp build/linux-sunxi/arch/arm64/boot/Image.gz kernel-sunxi.gz
	@cp build/linux-sunxi/arch/arm64/boot/dts/allwinner/*.dtb dtbs/sunxi/

%.scr: src/%.txt
	@echo "MKIMG $@"
	@mkimage -A arm -O linux -T script -C none -n "U-Boot boot script" -d $< $@
	
build/atf/sun50i_a64/bl31.bin: src/arm-trusted-firmware
	@echo "MAKE  $@"
	@mkdir -p build/atf/sun50i_a64
	@cd src/arm-trusted-firmware; make $(CROSS_FLAGS_BOOT) PLAT=sun50i_a64 bl31
	@cp src/arm-trusted-firmware/build/sun50i_a64/release/bl31.bin "$@"

u-boot-sunxi-with-spl.bin: build/atf/sun50i_a64/bl31.bin src/u-boot
	@echo "MAKE  $@"
	@mkdir -p build/u-boot/sun50i_a64
	@BL31=../../../build/atf/sun50i_a64/bl31.bin $(MAKE) -C src/u-boot O=../../build/u-boot/sun50i_a64 $(CROSS_FLAGS_BOOT) pinephone_defconfig
	@BL31=../../../build/atf/sun50i_a64/bl31.bin $(MAKE) -C src/u-boot O=../../build/u-boot/sun50i_a64 $(CROSS_FLAGS_BOOT) ARCH=arm all
	@cp build/u-boot/sun50i_a64/u-boot-sunxi-with-spl.bin "$@"

src/bash:
	@echo "WGET  bash"
	@mkdir src/bash
	@wget http://git.savannah.gnu.org/cgit/bash.git/snapshot/bash-5.0.tar.gz
	@tar -xvf bash-5.0.tar.gz --strip-components 1 -C src/bash

src/kexec-tools:
	@echo "WGET  kexec-tools"
	@mkdir src/kexec-tools
	@wget https://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git/snapshot/kexec-tools-2.0.20.tar.gz
	@tar -xvf kexec-tools-2.0.20.tar.gz --strip-components 1 -C src/kexec-tools

src/arm-trusted-firmware:
	@echo "WGET  arm-trusted-firmware"
	@mkdir src/arm-trusted-firmware
	@wget https://github.com/ARM-software/arm-trusted-firmware/archive/50d8cf26dc57bb453b1a52be646140bfea4aa591.tar.gz
	@tar -xvf 50d8cf26dc57bb453b1a52be646140bfea4aa591.tar.gz --strip-components 1 -C src/arm-trusted-firmware

src/u-boot:
	@echo "WGET  u-boot"
	@mkdir src/u-boot
	@wget ftp://ftp.denx.de/pub/u-boot/u-boot-2020.04.tar.bz2
	@tar -xvf u-boot-2020.04.tar.bz2 --strip-components 1 -C src/u-boot
	@cd src/u-boot && patch -p1 < ../u-boot-pinephone.patch


.PHONY: clean cleanfast

cleanfast:
	@rm -rvf build
	@rm -rvf initramfs-*/
	@rm -vf *.img
	@rm -vf *.img.xz
	@rm -vf *.apk
	@rm -vf *.bin
	@rm -vf *.cpio
	@rm -vf *.gz
	@rm -vf *.scr

clean: cleanfast
	@rm -vf kernel*.gz
	@rm -vf initramfs/bin/busybox
	@rm -vf initramfs/bin/bash
	@rm -vf initramfs/bin/kexec
	@rm -vrf dtbs
