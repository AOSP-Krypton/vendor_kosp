include vendor/krypton/config/BoardConfigKernel.mk

ifeq ($(BOARD_USES_QCOM_HARDWARE),true)
include vendor/krypton/config/BoardConfigQcom.mk
endif

include vendor/krypton/config/BoardConfigSoong.mk
