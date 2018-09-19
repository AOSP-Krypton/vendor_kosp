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
ifeq ($(TARGET_KERNEL_VERSION),)
TARGET_KERNEL_VERSION := $(shell echo $(TARGET_KERNEL_SOURCE) | sed 's_kernel/msm-__')
endif
TARGET_KERNEL_CROSS_COMPILE_PREFIX := $(PREBUILTS_COMMON)/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin/aarch64-linux-android-
TARGET_KERNEL_CROSS_COMPILE_ARM32_PREFIX := $(PREBUILTS_COMMON)/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-
TARGET_KERNEL_DISABLE_DEBUGFS := true

# Build tools
KERNEL_LLVM_SUPPORT := true
KRYPTON_TOOLS := $(PREBUILTS_COMMON)/krypton-tools
CLANG_TOOLCHAIN := $(PREBUILTS_COMMON)/clang/host/linux-x86/clang-r383902b/bin
HOST_GCC_TOOLCHAIN := $(PREBUILTS_COMMON)/gcc/linux-x86/host/x86_64-linux-glibc2.17-4.8/bin
PATH_OVERRIDE := PATH=$(KRYPTON_TOOLS)/linux-x86/bin:$$PATH
MAKE := $(PREBUILTS_COMMON)/build-tools/linux-x86/bin/make -j$(shell $(KRYPTON_TOOLS)/linux-x86/bin/nproc --all)

DTC := $(HOST_OUT_EXECUTABLES)/dtc$(HOST_EXECUTABLE_SUFFIX)
UFDT_APPLY_OVERLAY := $(HOST_OUT_EXECUTABLES)/ufdt_apply_overlay$(HOST_EXECUTABLE_SUFFIX)

TARGET_KERNEL_MAKE_ENV := DTC_EXT=$(TEMP_TOP)/$(DTC)
TARGET_KERNEL_MAKE_ENV += DTC_OVERLAY_TEST_EXT=$(TEMP_TOP)/$(UFDT_APPLY_OVERLAY)
TARGET_KERNEL_MAKE_ENV += CONFIG_BUILD_ARM64_DT_OVERLAY=y
TARGET_KERNEL_MAKE_ENV += HOSTCC=$(CLANG_TOOLCHAIN)/clang
TARGET_KERNEL_MAKE_ENV += HOSTAR=$(HOST_GCC_TOOLCHAIN)/x86_64-linux-ar
TARGET_KERNEL_MAKE_ENV += HOSTLD=$(HOST_GCC_TOOLCHAIN)/x86_64-linux-ld
TARGET_KERNEL_MAKE_ENV += HOSTCFLAGS="-I/usr/include -I/usr/include/x86_64-linux-gnu -L/usr/lib -L/usr/lib/x86_64-linux-gnu -fuse-ld=lld"
TARGET_KERNEL_MAKE_ENV += HOSTLDFLAGS="-L/usr/lib -L/usr/lib/x86_64-linux-gnu -fuse-ld=lld"
KERNEL_MAKE_ENV_SOONG := $(TARGET_KERNEL_MAKE_ENV)
TARGET_KERNEL_MAKE_ENV += $(PATH_OVERRIDE)
TARGET_KERNEL_DISABLE_DEBUGFS := true

# Build dtbo
ifeq ($(strip $(BOARD_KERNEL_SEPARATED_DTBO)),true)
BOARD_PREBUILT_DTBOIMAGE := $(PRODUCT_OUT)/prebuilt_dtbo.img
endif

# Include kernel build makefile from kernel source
include $(TARGET_KERNEL_SOURCE)/AndroidKernel.mk
$(TARGET_PREBUILT_KERNEL): $(DTC) $(UFDT_APPLY_OVERLAY)

$(INSTALLED_KERNEL_TARGET): $(TARGET_PREBUILT_KERNEL) | $(ACP)
	$(transform-prebuilt-to-target)

endif
