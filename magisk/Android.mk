LOCAL_PATH := $(call my-dir)

ifeq ($(BOARD_MAGISK_INIT),true)
$(shell cp $(LOCAL_PATH)/magiskinit $(PRODUCT_OUT)/magiskinit)
endif
