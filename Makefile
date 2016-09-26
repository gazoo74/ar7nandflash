#!/usr/bin/make -f
#
# Copyright 2016 Gaël PORTAY <gael.portay@gmail.com>
#
# Licensed under the MIT license.
#

PREFIX ?= /usr/local

ARCH := mips
CROSS_COMPILE ?= mipsel-unknown-linux-gnu-

export ARCH CROSS_COMPILE

ifeq (,$(shell which srec2bin))
.PHONY: prerequisites
prerequisites: srec2bin all

.PHONY: install
install:
	install -d $(PREFIX)/bin/
	install -m 755 srec2bin $(DESTDIR)$(PREFIX)/bin/

PATH := $(PATH):.
endif

.PHONY: all
all: vmlinuz.bin

$(CROSS_COMPILE)busybox $(CROSS_COMPILE)linux $(CROSS_COMPILE)rootfs $(CROSS_COMPILE)rootfs/dev $(CROSS_COMPILE)rootfs/tmp:
	mkdir -p $@/

initramfs.cpio.gz:

initramfs.cpio: $(CROSS_COMPILE)rootfs/init $(CROSS_COMPILE)rootfs/bin/busybox | $(CROSS_COMPILE)rootfs/dev $(CROSS_COMPILE)rootfs/tmp

$(CROSS_COMPILE)rootfs/init: | $(CROSS_COMPILE)rootfs
	ln -sf bin/sh $@

busybox/Makefile:
	wget -qO- https://busybox.net/index.html | \
	sed -n -e '/<li><b>.* -- BusyBox .* (stable)<\/b>/,/<\/li>/{/<p><a href=".*">BusyBox .*<\/a>/p}' | \
	sed    -e 's,.*href="\([a-z0-9;/-].*\)">BusyBox \([0-9.]*\).*,wget -qO- \1 | tar xvj \&\& ln -sf busybox-\2 busybox \&\& exit 0,' | \
	sh

$(CROSS_COMPILE)rootfs/bin/busybox: $(CROSS_COMPILE)busybox/busybox
	make -C busybox O=$(CURDIR)/$(CROSS_COMPILE)busybox CONFIG_STATIC=y CONFIG_PREFIX=$(CURDIR)/$(CROSS_COMPILE)rootfs install

$(CROSS_COMPILE)busybox/.config: | $(CROSS_COMPILE)busybox busybox/Makefile
	yes "" | make -C busybox O=$(CURDIR)/$(CROSS_COMPILE)busybox oldconfig

$(CROSS_COMPILE)busybox/busybox: $(CROSS_COMPILE)busybox/.config
	make -C busybox O=$(CURDIR)/$(CROSS_COMPILE)busybox CONFIG_STATIC=y

linux/Makefile:
	wget -qO- https://www.kernel.org/index.html | \
	sed -n '/<td id="latest_link"/,/<\/td>/s,.*<a.*href="\(.*\)">\(.*\)</a>.*,wget -qO- \1 | tar xvJ \&\& ln -sf linux-\2 linux,p'  | \
	sh

$(CROSS_COMPILE)linux/.config: linux/Makefile | $(CROSS_COMPILE)linux
	make -C linux O=$(CURDIR)/$(CROSS_COMPILE)linux ar7_defconfig

$(CROSS_COMPILE)linux/vmlinuz: initramfs.cpio $(CROSS_COMPILE)linux/.config
	make -C linux O=$(CURDIR)/$(CROSS_COMPILE)linux CONFIG_INITRAMFS_SOURCE=$(CURDIR)/$< $(@F)

vmlinuz.elf: $(CROSS_COMPILE)linux/vmlinuz
	cp $< $@

.PHONY: flash
flash: vmlinuz.bin
	openocd -f interface/ftdi/tumpa.cfg \
	        -f tools/firmware-recovery.tcl \
	        -c "board netgear-dg834v3; reset_config srst_only; flash_part firmware $<; shutdown"

busybox_menuconfig:
busybox_%:
	make -C busybox O=$(CURDIR)/$(CROSS_COMPILE)busybox $*

linux_menuconfig:
linux_%:
	make -C linux O=$(CURDIR)/$(CROSS_COMPILE)linux $*

%.srec: %.elf
	$(CROSS_COMPILE)objcopy -S -O srec $(addprefix --remove-section=,reginfo .mdebug .comment .note .pdr .options .MIPS.options) $< $@

%.bin: %.srec
	srec2bin $< $@

%.cpio:
	cd $(<D) && find . | cpio -H newc -o -R root:root >$(CURDIR)/$@

%.gz: %
	gzip -9 $*

.PHONY: clean
clean:
	rm -f vmlinuz.* initramfs.cpio*

.PHONY: mrproper
mrproper: clean
	rm -Rf $(CROSS_COMPILE)*

