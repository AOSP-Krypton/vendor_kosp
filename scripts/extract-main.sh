#!/bin/bash

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

# Option to choose whether to use adb or copy from unpacked images
method="$1"
[ -z $1 ] && echo -e "Info: using adb as no method for extraction is specified" && method="adb"

if [ $method == "adb" ] ; then
  # Check if adb exists
  if ! which adb > /dev/null ; then
    echo "adb not found,please install adb and try again"
    exit 1
  fi

  # Start adb
  offline=true
  echo "Waiting for device to come online"
  while $offline ; do
    out=$(adb devices)
    device=$(echo $out | sed 's/List of devices attached//')
    temp=$(echo $device | grep 'recovery\|device')
    [ ! -z "$temp" ] && offline=false
  done
  echo "Device online!"

  # Check if adb is running as root
  if adb root | grep -q "running as root" ; then
    echo "adb is running as root,proceeding with extraction"
  else
    echo "adb is not running as root,aborting!"
    exit 1
  fi
else
  [ -d $2 ] || echo "Error: path '$2' does not exist" && return 1
  blobroot="$2"
fi

# Wipe existing blobs directory and create necessary files
# First check if the directory is already a git repo, if so then do not wipe git metadata
git -C $BLOBS_PATH rev-parse 2>/dev/null
if [ $? -eq 0 ] ; then
  rm -rf $BLOBS_PATH/*.* $BLOBS_PATH/system $BLOBS_PATH/vendor
else
  rm -rf $BLOBS_PATH && mkdir -p ${BLOBS_PATH}
fi
echo -ne "PRODUCT_SOONG_NAMESPACES += vendor/${VENDOR}/${DEVICE}\n\nPRODUCT_COPY_FILES += " > $MKFILE
echo -e "soong_namespace {\n}" > ${BLOBS_PATH}/Android.bp

# arrays to hold list of certain blobs for import
appArray=()
dexArray=()
libArray=()
xmlArray=()
packageArray=()

# Var to store failed pull count
countFailed=0
# Main function to extract
function start_extraction() {
  # Read blobs list line by line
  while read line; do
    diffSource=false
    import=false
    # Null check
    if [ ! -z "$line" ] ; then
      # Comments
      if [[ $line == *"#"* ]] ; then
        echo $line
      else
        if [[ $line == -* ]] ; then
          line=$(echo $line | sed 's/-//')
          import=true
        fi
        if [[ $line == *:* ]] ; then
          diffSource=true
          origFile=${line%:*}
          line=${line#*:}
        else
          origFile=$line
        fi
        destFile=$line

        # Blobs to import
        if $import ; then
          # Apks, jars, libs
          if [[ $line == *".apk"* ]] ; then
            appArray+=($line)
          elif [[ $line == *".jar"* ]] ; then
            dexArray+=($line)
          elif [[ $line == *".xml"* ]] ; then
            xmlArray+=($line)
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
        extract_blob $origFile $destFile
        [ $? -ne 0 ] && echo -e "\033[1;31mFailed\033[0m" && countFailed=$(expr $countFailed + 1)
      fi
    fi
  done < $BLOBS_LIST
}

# Extract everything
function extract_blob() {
  local blobPath=${2%/*}
  mkdir -p ${BLOBS_PATH}/${blobPath}
  STATUS=0
  if [ $method == "adb" ] ; then
    adb pull $1 ${BLOBS_PATH}/${blobPath}
    [ $? -ne 0 ] && $diffSource && adb pull $2 ${BLOBS_PATH}/${blobPath}
    STATUS=$?
  else
    if [[ $1 == *"system/"* ]] ; then
      path=${blobroot}/system/$1
    else
      path=${blobroot}/$1
    fi
    cp $path ${BLOBS_PATH}/${blobPath}
    STATUS=$?
  fi
  return $STATUS
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

# Import xml to Android.bp
function import_xml() {
  for xml in ${xmlArray[@]}; do
    write_xml_bp $xml
    packageArray+=($xml)
  done
}

function write_lib_bp() {
  local moduleName=${1##*/}
  moduleName=${moduleName%.*}
  echo -ne "\ncc_prebuilt_library_shared {
    name: \"$moduleName\",
    owner: \"$VENDOR\",
    strip: {
        none: true,
    },
    target: {
        android_arm: {
            srcs: [\"${1}\"],
        },
        android_arm64: {
            srcs: [\"${1}\"],
        },
    },
    compile_multilib: \"both\",
    check_elf_files: false,
    prefer: true," >> ${BLOBS_PATH}/Android.bp

  which_partition $1
}

function write_app_bp() {
  local moduleName=${1##*/}
  moduleName=${moduleName%.*}
  echo -ne "\nandroid_app_import {
    name: \"$moduleName\",
    owner: \"$VENDOR\",
    apk: \"$1\",
    certificate: \"platform\",
    dex_preopt: {
        enabled: false,
    }," >> ${BLOBS_PATH}/Android.bp

  if [[ $1 == *"priv-app"* ]] ; then
    echo -ne "
    privileged: true," >> ${BLOBS_PATH}/Android.bp
  fi
  which_partition $1
}

function write_dex_bp() {
  local moduleName=${1##*/}
  moduleName=${moduleName%.*}
  echo -ne "\ndex_import {
    name: \"$moduleName\",
    owner: \"$VENDOR\",
    jars: [\"$1\"]," >> ${BLOBS_PATH}/Android.bp

  which_partition $1
}

function write_xml_bp() {
  local moduleName=${1##*/}
  moduleName=${moduleName%.*}
  echo -ne "\nprebuilt_etc_xml {
    name: \"$moduleName\",
    owner: \"$VENDOR\",
    src: \"$1\",
    filename_from_src: true,
    sub_dir: \"vintf/manifest\"," >> ${BLOBS_PATH}/Android.bp

  which_partition $1
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

function which_partition() {
  if [[ $1 == *"system/product/"* ]] ; then
    echo -e "
    product_specific: true,
}" >> ${BLOBS_PATH}/Android.bp
  elif [[ $1 == *"system/system_ext/"* ]] ; then
    echo -e "
    system_ext_specific: true,
}" >> ${BLOBS_PATH}/Android.bp
  elif [[ $1 == *"system/"* ]] ; then
    echo -e "
}" >> ${BLOBS_PATH}/Android.bp
  else
    echo -e "
    soc_specific: true,
}" >> ${BLOBS_PATH}/Android.bp
  fi
}

# Everything starts here
start_extraction
import_lib
import_app
import_dex
import_xml
write_packages
[ $countFailed -ne 0 ] && echo -e "\033[1;31mFailed pulls: $countFailed\033[0m"
