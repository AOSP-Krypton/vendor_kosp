# Copyright 2021 AOSP-Krypton Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Kernel make environment flags are set here
# Bail out if either kernel source or defconfig is not defined for building kernel
TEMP_TOP := $(shell pwd)
ifeq ($(TARGET_PREBUILT_KERNEL),)
ifeq ($(TARGET_KERNEL_SOURCE),)
$(error "Kernel source is not defined")
else ifeq ($(TARGET_KERNEL_DEFCONFIG),)
$(error "Kernel defconfig is not defined")
endif

# Common path for prebuilts
PREBUILTS_COMMON := $(TEMP_TOP)/prebuilts

# AndroidKernel.mk needs KERNEL_DEFCONFIG
KERNEL_DEFCONFIG := $(strip $(TARGET_KERNEL_DEFCONFIG))

# Set this for caf hals
TARGET_COMPILE_WITH_MSM_KERNEL := true

ifeq ($(TARGET_KERNEL_ARCH),)
TARGET_KERNEL_ARCH := arm64
endif
ifeq ($(TARGET_KERNEL_HEADER_ARCH),)
TARGET_KERNEL_HEADER_ARCH := $(TARGET_KERNEL_ARCH)
endif

TARGET_KERNEL_CROSS_COMPILE_PREFIX := $(strip $(TARGET_KERNEL_CROSS_COMPILE_PREFIX))
TARGET_KERNEL_CROSS_COMPILE_ARM32_PREFIX := $(strip $(TARGET_KERNEL_CROSS_COMPILE_ARM32_PREFIX))

# Build tools
KERNEL_LLVM_SUPPORT := true
KRYPTON_TOOLS := $(PREBUILTS_COMMON)/krypton-tools

ifneq ($(strip $(CLANG_CUSTOM_TOOLCHAIN)),)
CLANG_TOOLCHAIN := $(PREBUILTS_COMMON)/clang/host/$(HOST_PREBUILT_TAG)/$(strip $(CLANG_CUSTOM_TOOLCHAIN))/bin
ifeq (,$(wildcard $(CLANG_TOOLCHAIN)/clang))
$(error "Unable to find clang binary in $(CLANG_TOOLCHAIN)")
endif
else
CLANG_TOOLCHAIN := $(PREBUILTS_COMMON)/clang/host/$(HOST_PREBUILT_TAG)/clang-r416183b/bin
endif

HOST_GCC_TOOLCHAIN := $(PREBUILTS_COMMON)/gcc/$(HOST_PREBUILT_TAG)/host/x86_64-linux-glibc2.17-4.8/bin
PATH_OVERRIDE := \
    PATH=$(KRYPTON_TOOLS)/$(HOST_PREBUILT_TAG)/bin:$(CLANG_TOOLCHAIN):$$PATH \
    PERL5LIB=$(KRYPTON_TOOLS)/common/perl-base
CPIO := $(KRYPTON_TOOLS)/$(HOST_PREBUILT_TAG)/bin/cpio
MAKE := $(PREBUILTS_COMMON)/build-tools/$(HOST_PREBUILT_TAG)/bin/make -j$(shell $(KRYPTON_TOOLS)/$(HOST_PREBUILT_TAG)/bin/nproc --all)

DTC := $(HOST_OUT_EXECUTABLES)/dtc$(HOST_EXECUTABLE_SUFFIX)

TARGET_KERNEL_MAKE_ENV += $(PATH_OVERRIDE)
TARGET_KERNEL_MAKE_ENV := DTC_EXT=$(TEMP_TOP)/$(DTC)
TARGET_KERNEL_MAKE_ENV += HOSTCC=$(CLANG_TOOLCHAIN)/clang
TARGET_KERNEL_MAKE_ENV += HOSTAR=$(HOST_GCC_TOOLCHAIN)/x86_64-linux-ar
TARGET_KERNEL_MAKE_ENV += HOSTLD=$(HOST_GCC_TOOLCHAIN)/x86_64-linux-ld
TARGET_KERNEL_MAKE_ENV += HOSTCFLAGS="-I/usr/include -I/usr/include/x86_64-linux-gnu -L/usr/lib -L/usr/lib/x86_64-linux-gnu -fuse-ld=lld"
TARGET_KERNEL_MAKE_ENV += HOSTLDFLAGS="-L/usr/lib -L/usr/lib/x86_64-linux-gnu -fuse-ld=lld"
TARGET_KERNEL_MAKE_ENV += $(TARGET_KERNEL_ADDITIONAL_FLAGS)
TARGET_KERNEL_DISABLE_DEBUGFS := true

# Build dtbo
ifeq ($(strip $(BOARD_KERNEL_SEPARATED_DTBO)),true)
BOARD_PREBUILT_DTBOIMAGE := $(PRODUCT_OUT)/prebuilt_dtbo.img
endif

#Android makefile to build kernel as a part of Android Build
PERL = perl

KERNEL_TARGET := $(strip $(INSTALLED_KERNEL_TARGET))
ifeq ($(KERNEL_TARGET),)
INSTALLED_KERNEL_TARGET := $(PRODUCT_OUT)/kernel
endif

ifneq ($(TARGET_KERNEL_APPEND_DTB), true)
INSTALLED_DTBIMAGE_TARGET := $(PRODUCT_OUT)/dtb.img
endif

ifeq ($(strip $(BOARD_KERNEL_SEPARATED_DTBO)),true)
DTBTOOL := $(HOST_OUT_EXECUTABLES)/mkdtimg$(HOST_EXECUTABLE_SUFFIX)
endif

TARGET_KERNEL_MAKE_ENV := $(strip $(TARGET_KERNEL_MAKE_ENV))
ifeq ($(TARGET_KERNEL_MAKE_ENV),)
KERNEL_MAKE_ENV :=
else
KERNEL_MAKE_ENV := $(TARGET_KERNEL_MAKE_ENV)
endif

TARGET_KERNEL_ARCH := $(strip $(TARGET_KERNEL_ARCH))
ifeq ($(TARGET_KERNEL_ARCH),)
KERNEL_ARCH := arm
else
KERNEL_ARCH := $(TARGET_KERNEL_ARCH)
endif

TARGET_KERNEL_HEADER_ARCH := $(strip $(TARGET_KERNEL_HEADER_ARCH))
ifeq ($(TARGET_KERNEL_HEADER_ARCH),)
KERNEL_HEADER_ARCH := $(KERNEL_ARCH)
else
KERNEL_HEADER_ARCH := $(TARGET_KERNEL_HEADER_ARCH)
endif

KERNEL_HEADER_DEFCONFIG := $(strip $(KERNEL_HEADER_DEFCONFIG))
ifeq ($(KERNEL_HEADER_DEFCONFIG),)
KERNEL_HEADER_DEFCONFIG := $(KERNEL_DEFCONFIG)
endif

# Force 32-bit binder IPC for 64bit kernel with 32bit userspace
ifeq ($(KERNEL_ARCH),arm64)
ifeq ($(TARGET_ARCH),arm)
KERNEL_CONFIG_OVERRIDE := CONFIG_ANDROID_BINDER_IPC_32BIT=y
endif
endif

ifeq ($(TARGET_KERNEL_CROSS_COMPILE_PREFIX),)
KERNEL_CROSS_COMPILE := aarch64-linux-android-
else
KERNEL_CROSS_COMPILE := $(TARGET_KERNEL_CROSS_COMPILE_PREFIX)
endif

ifeq ($(TARGET_KERNEL_CROSS_COMPILE_ARM32_PREFIX),)
KERNEL_CROSS_COMPILE_ARM32 := arm-linux-androideabi-
else
KERNEL_CROSS_COMPILE_ARM32 := $(TARGET_KERNEL_CROSS_COMPILE_ARM32_PREFIX)
endif

ifeq ($(KERNEL_LLVM_SUPPORT), true)
  ifeq ($(KERNEL_SD_LLVM_SUPPORT), true)  #Using sd-llvm compiler
    ifeq ($(shell echo $(SDCLANG_PATH) | head -c 1),/)
       KERNEL_LLVM_BIN := $(SDCLANG_PATH)/clang
    else
       KERNEL_LLVM_BIN := $(TEMP_TOP)/$(SDCLANG_PATH)/clang
    endif
  else
     KERNEL_LLVM_BIN := $(CLANG_TOOLCHAIN)/clang #Using aosp-llvm compiler
  endif
endif

cc :=
ifeq ($(KERNEL_LLVM_SUPPORT),true)
  ifeq ($(KERNEL_ARCH), arm64)
	cc := CC=$(KERNEL_LLVM_BIN) CLANG_TRIPLE=aarch64-linux-gnu-
  else
	cc := CC=$(KERNEL_LLVM_BIN) CLANG_TRIPLE=arm-linux-gnueabihf
  endif
endif

BUILD_ROOT_LOC := $(TEMP_TOP)/
KERNEL_OUT := $(TARGET_OUT_INTERMEDIATES)/$(TARGET_KERNEL_SOURCE)
KERNEL_SYMLINK := $(TARGET_OUT_INTERMEDIATES)/KERNEL_OBJ
KERNEL_USR := $(KERNEL_SYMLINK)/usr

# Add RTIC DTB to dtb.img if RTIC MPGen is enabled.
# Note: unfortunately we can't define RTIC DTS + DTB rule here as the
# following variable/ tools (needed for DTS generation)
# are missing - DTB_OBJS, OBJDUMP, KCONFIG_CONFIG, CC, DTC_FLAGS (the only available is DTC).
# The existing RTIC kernel integration in scripts/link-vmlinux.sh generates RTIC MP DTS
# that will be compiled with optional rule below.
# To be safe, we check for MPGen enable.
ifdef RTIC_MPGEN
RTIC_DTB := $(KERNEL_SYMLINK)/rtic_mp.dtb
endif

KERNEL_CONFIG := $(KERNEL_OUT)/.config

ifeq ($(KERNEL_DEFCONFIG)$(wildcard $(KERNEL_CONFIG)),)
$(error Kernel configuration not defined, cannot build kernel)
endif

ifeq ($(BOARD_KERNEL_IMAGE_NAME),)
ifeq ($(TARGET_USES_UNCOMPRESSED_KERNEL),true)
TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/Image
else
ifeq ($(KERNEL_ARCH),arm64)
TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/Image.gz
else
TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/zImage
endif
endif
ifeq ($(TARGET_KERNEL_APPEND_DTB), true)
TARGET_PREBUILT_INT_KERNEL := $(TARGET_PREBUILT_INT_KERNEL)-dtb
endif
else
TARGET_PREBUILT_INT_KERNEL := $(KERNEL_OUT)/arch/$(KERNEL_ARCH)/boot/$(BOARD_KERNEL_IMAGE_NAME)
endif

KERNEL_HEADERS_INSTALL := $(KERNEL_OUT)/usr
TARGET_PREBUILT_KERNEL := $(TARGET_PREBUILT_INT_KERNEL)

# Include kernel build makefile
#include vendor/krypton/build/tasks/kernel.mk
$(TARGET_PREBUILT_KERNEL): $(DTC)

$(INSTALLED_KERNEL_TARGET): $(TARGET_PREBUILT_KERNEL) | $(ACP)
	$(transform-prebuilt-to-target)

endif
