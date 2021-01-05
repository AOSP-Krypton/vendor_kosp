#!/bin/bash

# Check if required variables are set
if [ -z $ANDROID_BUILD_TOP ] ; then
  echo "ANDROID_BUILD_TOP not found,source build/envsetup.sh"
  exit 1
fi
if [[ -z $VENDOR || -z $DEVICE ]] ; then
  echo "DEVICE and VENDOR not be found, have you run the script in device tree?"
  exit 1
fi

# Path to extract blobs to and makefile for copying blobs and building modules
BLOBS_LIST=${ANDROID_BUILD_TOP}/device/${VENDOR}/${DEVICE}/blobs.txt
BLOBS_PATH=${ANDROID_BUILD_TOP}/vendor/${VENDOR}/${DEVICE}
MKFILE=${BLOBS_PATH}/${DEVICE}-proprietary.mk

# Check if adb exists
if ! which adb > /dev/null ; then
  echo "adb not found,please install adb and try again"
  exit 1
fi

# Start adb
echo "Waiting for device to come online"
adb wait-for-device
echo "Device online!"

# Check if adb is running as root
if adb root | grep -q "running as root" ; then
  echo "adb is running as root,proceeding with extraction"
else
  echo "adb is not running as root,aborting!"
  exit 1
fi

# Wipe existing blobs directory and create necessary files
rm -rf $BLOBS_PATH && mkdir -p ${BLOBS_PATH}
echo -ne "PRODUCT_SOONG_NAMESPACES += vendor/${VENDOR}/${DEVICE}\n\nPRODUCT_COPY_FILES += " > $MKFILE
echo -e "soong_namespace {\n}" > ${BLOBS_PATH}/Android.bp

# arrays to hold list of certain blobs for import
appArray=()
dexArray=()
libArray=()
packageArray=()

# Main function to extract
function start_extraction() {
  # Read blobs list line by line
  while read line; do
    # Null check
    if [ ! -z "$line" ] ; then
      # Comments
      if [[ $line == *"#"* ]] ; then
        echo $line
      else
        # Blobs to import
        if [[ $line == -* ]] ; then
          line=$(echo $line | sed 's/-//')
          # Apks, jars, libs
          if [[ $line == *"apk"* ]] ; then
            appArray+=($line)
          elif [[ $line == *"jar"* ]] ; then
            dexArray+=($line)
          else
            if [[ $line == *"lib64"* ]] ; then
                libArray+=($line)
            fi
          fi
        else
          # Just copy blobs
          write_to_makefiles $line
        fi
      # Extract the blob from device
      extract_blob $line
      fi
    fi
  done < $BLOBS_LIST
}

# Extract everything
function extract_blob() {
  local blobPath=${1%/*}
  mkdir -p ${BLOBS_PATH}/${blobPath}
  adb pull $1 ${BLOBS_PATH}/${blobPath}
}

# Import libs to Android.bp
function import_lib() {
  for lib in ${libArray[@]}; do
    write_lib_bp $lib
    packageArray+=($lib)
  done
}

# Import apps to Android.bp
function import_app() {
  for app in ${appArray[@]}; do
    write_app_bp $app
    packageArray+=($app)
  done
}

# Import jars to Android.bp
function import_dex() {
  for dex in ${dexArray[@]}; do
    write_dex_bp $dex
    packageArray+=($dex)
  done
}

function write_lib_bp() {
  local moduleName=${1##*/}
  moduleName=${moduleName%.*}
  echo -e "\ncc_prebuilt_library_shared {
  name: \"$moduleName\",
  owner: \"$VENDOR\",
  strip: {\n\t\tnone: true,\n\t},
  target: {\n\t\tandroid_arm: {\n\t\t\tsrcs: [\"${1}\"],\n\t\t},\n\t\tandroid_arm64: {\n\t\t\tsrcs: [\"${1}\"],\n\t\t},\n\t},
  compile_multilib: \"both\",
  check_elf_files: false,
  prefer: true," >> ${BLOBS_PATH}/Android.bp

  if [[ $1 == *"system/product/"* ]] ; then
    echo -e "\tproduct_specific: true,\n}" >> ${BLOBS_PATH}/Android.bp
  elif [[ $1 == *"system/"* ]] ; then
    echo -e "}" >> ${BLOBS_PATH}/Android.bp
  else
    echo -e "\tsoc_specific: true,\n}" >> ${BLOBS_PATH}/Android.bp
  fi
}

function write_app_bp() {
  local moduleName=${1##*/}
  moduleName=${moduleName%.*}
  echo -e "\nandroid_app_import {
  name: \"$moduleName\",
  owner: \"$VENDOR\",
  apk: \"$1\",
  certificate: \"platform\",
  dex_preopt: {\n\t\tenabled: false,\n\t}," >> ${BLOBS_PATH}/Android.bp

  if [[ $1 == *"priv-app"* ]] ; then
    echo -e "\tprivileged: true," >> ${BLOBS_PATH}/Android.bp
  fi

  if [[ $1 == *"system/product/"* ]] ; then
    echo -e "\tproduct_specific: true,\n}" >> ${BLOBS_PATH}/Android.bp
  elif [[ $1 == *"system/"* ]] ; then
    echo -e "}" >> ${BLOBS_PATH}/Android.bp
  else
    echo -e "\tsoc_specific: true,\n}" >> ${BLOBS_PATH}/Android.bp
  fi
}

function write_dex_bp() {
  local moduleName=${1##*/}
  moduleName=${moduleName%.*}
  echo -e "\ndex_import {
  name: \"$moduleName\",
  owner: \"$VENDOR\",
  jars: [\"$1\"]," >> ${BLOBS_PATH}/Android.bp

  if [[ $1 == *"system/product/"* ]] ; then
    echo -e "\tproduct_specific: true,\n}" >> ${BLOBS_PATH}/Android.bp
  elif [[ $1 == *"system/"* ]] ; then
    echo -e "}" >> ${BLOBS_PATH}/Android.bp
  else
    echo -e "\tsoc_specific: true,\n}" >> ${BLOBS_PATH}/Android.bp
  fi
}

# Write rules to copy out blobs
function write_to_makefiles() {
  local path=${1#*/}
  if [[ $1 == *"system/product/"* ]] ; then
    path=${path#*/}
    echo -ne "\\" >> $MKFILE
    echo -ne "\n\tvendor/${VENDOR}/${DEVICE}/${1}:\$(TARGET_COPY_OUT_PRODUCT)/${path} " >> $MKFILE
  elif [[ $1 == *"system/"* ]] ; then
    echo -ne "\\" >> $MKFILE
    echo -ne "\n\tvendor/${VENDOR}/${DEVICE}/${1}:\$(TARGET_COPY_OUT_SYSTEM)/${path} " >> $MKFILE
  else
    echo -ne "\\" >> $MKFILE
    echo -ne "\n\tvendor/${VENDOR}/${DEVICE}/${1}:\$(TARGET_COPY_OUT_VENDOR)/${path} " >> $MKFILE
  fi
}

# Include packages to build
function write_packages() {
  echo -ne "\n\nPRODUCT_PACKAGES += " >> $MKFILE
  for package in ${packageArray[@]}; do
    packageName=${package##*/}
    packageName=${packageName%.*}
    echo -ne "\\" >> $MKFILE
    echo -ne "\n\t$packageName " >> $MKFILE
  done
}

# Everything starts here
start_extraction
import_lib
import_app
import_dex
write_packages
