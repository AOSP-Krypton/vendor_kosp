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
BPFILE=${BLOBS_PATH}/Android.bp

# Whether to pin the first found blob by default, be careful with this option
pinFirst=false

# Whether to consider successfully pulled blobs for pinning
includePulls=false

# Parse options
while getopts "acup:d:fi" option; do
  case $option in
    a) method="adb";;
    c) method="copy";;
    u) updateHash=true;;
    p) blobroot=$OPTARG;;
    d) dirs+="$OPTARG ";;
    f) pinFirst=true;;
    i) includePulls=true;;
  esac
done

# Option to choose whether to use adb or copy from unpacked images
[ -z $method ] && echo -e "Info: using adb as no method for extraction is specified" && method="adb"

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
  if [ -z $blobroot ] ; then
    echo "Error: path to extracted firmware must be specified" && exit 1
  elif [ ! -d $blobroot ]; then
    echo "Error: path $blobroot does not exist" && exit 1
  fi
fi

for dir in $dirs ; do
  [ ! -z $dir ] && [ ! -d $dir ] && echo "Error: path $dir does not exist" && exit 1
done

# Wipe existing blobs directory and create necessary files
# First check if the directory is already a git repo, if so then do not wipe git metadata
git -C $BLOBS_PATH rev-parse 2>/dev/null
if [ $? -eq 0 ] ; then
  rm -rf $BLOBS_PATH/*.* $BLOBS_PATH/system $BLOBS_PATH/vendor
else
  rm -rf $BLOBS_PATH && mkdir -p ${BLOBS_PATH}
fi
echo -ne "PRODUCT_SOONG_NAMESPACES += vendor/${VENDOR}/${DEVICE}\n\nPRODUCT_COPY_FILES += " > $MKFILE
echo -e "soong_namespace {\n}" > $BPFILE

# arrays to hold list of certain blobs for import
appArray=()
dexArray=()
libArray=()
xmlArray=()
packageArray=()

# Var to store failed pull count
countFailed=0

# App signature type
cert=

# Main function to extract
function start_extraction() {
  # Read blobs list line by line
  while read line; do
    hash=
    pinned=false
    diffSource=false
    import=false
    cert="platform"
    origFile=
    destFile=
    # Null check
    if [ ! -z "$line" ] ; then
      # Comments
      if [[ $line == *"#"* ]] ; then
        echo $line
      else
        if [[ $line == -* ]] ; then
          line=$(echo $line | sed 's,-,,')
          import=true
        fi
        if [[ $line == *:* ]] ; then
          diffSource=true
          origFile=${line%:*}
          line=${line#*:}
          destFile=$line
        fi
        if [[ $line == *"|"* ]] ; then
          hash=${line#*|}
          line=${line%|*}
          if $diffSource ; then
            destFile=$line
          else
            origFile=$line
          fi
          if [[ $hash == *";"* ]] ; then
            local temp=$hash
            hash=${temp%;*}
            cert=${temp#*;}
          fi
          pinned=true
        fi
        [ -z $origFile ] && origFile=$line
        [ -z $destFile ] && destFile=$line

        # Blobs to import
        if $import ; then
          # Apks, jars, libs
          if [[ $line == *".apk"* ]] ; then
            appArray+=("$line.$cert")
          elif [[ $line == *".jar"* ]] ; then
            dexArray+=($line)
          elif [[ $line == *".xml"* ]] ; then
            xmlArray+=($line)
          elif [[ $line == *"/lib64/"* ]] || [[ $line == *"/lib/"* ]]; then
            libArray+=($line)
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
  local fileName=${2##*/}
  local destPath=${BLOBS_PATH}/${2%/*}
  local filePath=$1
  mkdir -p $destPath

  if [ $method == "adb" ] ; then
    adb pull $filePath $destPath 2>/dev/null
    STATUS=$?
    if [ $STATUS -ne 0 ] && $diffSource ; then
      filePath=$2
      adb pull $filePath $destPath 2>/dev/null
      STATUS=$?
    fi
  else
    filePath=${blobroot}/$1
    [ ! -f $filePath ] && filePath=${blobroot}/system/$1
    if $diffSource ; then
      [ ! -f $filePath ] && filePath=${blobroot}/$2
      [ ! -f $filePath ] && filePath=${blobroot}/system/$2
    fi
    cp $filePath $destPath 2>/dev/null
    STATUS=$?
    ! $pinned && [[ $STATUS -ne 0 ]] && echo "cp failed for $filePath"
  fi

  if $pinned ; then
    [ -z $hash ] && create_hash $2 $destPath $filePath && return $?
    blobHash=$(md5sum $filePath 2>/dev/null | awk '{print $1}')
    if [ -z $blobHash ] || [ ! "$blobHash" = "$hash" ] ; then
      rm -rf $destPath/$fileName
      for dir in $dirs ; do
        string=$1
        list=$(find $dir -type f -name $fileName | grep "$string")
        if [ -z $list ] ; then
          string=$2
          list=$(find $dir -type f -name $fileName | grep "$string")
        fi
        [ -z $list ] && continue
        for line in $list ; do
          blob=$(echo $list | grep "$string")
          [ ! -z $blob ] && break
        done
        [ -z $blob ] && return 1
        blobHash=$(md5sum $blob | awk '{print $1}')
        if [ "$blobHash" = "$hash" ] ; then
          cp $blob $destPath
          return $?
        fi
      done
    fi
  fi
  return $STATUS
}

# Import libs to Android.bp
function import_lib() {
  local multiLibArray=()
  for lib in ${libArray[@]}; do
    local parsed=false
    isLib=$(echo $lib | grep "/lib/")
    if [ -z $isLib ] ; then
      isLib64=$(echo $lib | grep "/lib64/")
      if [ ! -z $isLib64 ] ; then
        variant32=$(echo $lib | sed 's|/lib64/|/lib/|')
        for tmp in ${libArray[@]}; do
          if [ "$variant32" = "$tmp" ] ; then
            included=false
            for multiLib in ${multiLibArray[@]}; do
              if [ "$tmp|$lib" = "$multiLib" ] ; then
                included=true && break
              fi
            done
            ! $included && multiLibArray+=("$tmp|$lib")
            parsed=true
            break
          fi
        done
        if ! $parsed ; then
          write_lib_bp "lib64" $lib
          packageArray+=($lib)
        fi
      else
        echo "Error: unknown lib variant"
        return 1
      fi
    else
      variant64=$(echo $lib | sed 's|/lib/|/lib64/|')
      for tmp in ${libArray[@]}; do
        if [ "$variant64" = "$tmp" ] ; then
          included=false
          for multiLib in ${multiLibArray[@]}; do
            if [ "$lib|$tmp" = "$multiLib" ] ; then
              included=true && break
            fi
          done
          ! $included && multiLibArray+=("$lib|$tmp")
          parsed=true
          break
        fi
      done
      if ! $parsed ; then
        write_lib_bp "lib32" $lib
        packageArray+=($lib)
      fi
    fi
  done

  for multiLib in ${multiLibArray[@]}; do
    write_lib_bp "multilib" ${multiLib%|*} ${multiLib#*|}
    packageArray+=(${multiLib#*|})
  done
}

# Import apps to Android.bp
function import_app() {
  for app in ${appArray[@]}; do
    cert=${app##*.}
    app=$(echo $app | sed "s/.$cert//")
    write_app_bp $app $cert
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
  local moduleName=
  local lib32=
  local lib64=
  local multiMode=false
  case $1 in
    "lib32") lib32=$2;;
    "lib64") lib64=$2;;
    "multilib") multiMode=true ; lib32=$2 ; lib64=$3;;
  esac
  moduleName=${2##*/}
  moduleName=${moduleName%.*}
  echo -ne "\ncc_prebuilt_library_shared {
    name: \"$moduleName\",
    owner: \"$VENDOR\",
    strip: {
        none: true,
    },
    target: {" >> $BPFILE
  if [ ! -z $lib32 ] ; then
    echo -ne "
        android_arm: {
            srcs: [\"${lib32}\"],
        }," >> $BPFILE
  fi
  if [ ! -z $lib64 ] ; then
    echo -ne "
        android_arm64: {
            srcs: [\"${lib64}\"],
        }," >> $BPFILE
  fi
  echo -ne "
    }," >> $BPFILE
  if $multiMode ; then
    echo -ne "
    compile_multilib: \"both\"," >> $BPFILE
  else
    echo -ne "
    compile_multilib: \"first\"," >> $BPFILE
  fi
  echo -ne "
    check_elf_files: false,
    prefer: true," >> $BPFILE

  which_partition $2
}

function write_app_bp() {
  local moduleName=${1##*/}
  moduleName=${moduleName%.*}
  echo -ne "\nandroid_app_import {
    name: \"$moduleName\",
    owner: \"$VENDOR\",
    apk: \"$1\"," >> $BPFILE
    if [ "$2" = "presigned" ] ; then
      echo -ne "
    presigned: true," >> $BPFILE
    else
      echo -ne "
    certificate: \"$2\"," >> $BPFILE
    fi
    echo -ne "
    dex_preopt: {
        enabled: false,
    }," >> $BPFILE

  if [[ $1 == *"priv-app"* ]] ; then
    echo -ne "
    privileged: true," >> $BPFILE
  fi
  which_partition $1
}

function write_dex_bp() {
  local moduleName=${1##*/}
  moduleName=${moduleName%.*}
  echo -ne "\ndex_import {
    name: \"$moduleName\",
    owner: \"$VENDOR\",
    jars: [\"$1\"]," >> $BPFILE

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
    sub_dir: \"vintf/manifest\"," >> $BPFILE

  which_partition $1
}

# Write rules to copy out blobs
function write_to_makefiles() {
  local path=${1#*/}
  if [[ $1 == *"system/product/"* ]] ; then
    path=${path#*/}
    echo -ne "\\" >> $MKFILE
    echo -ne "\n\tvendor/${VENDOR}/${DEVICE}/${1}:\$(TARGET_COPY_OUT_PRODUCT)/${path} " >> $MKFILE
  elif [[ $1 == *"system/system_ext/"* ]] ; then
    path=${path#*/}
    echo -ne "\\" >> $MKFILE
    echo -ne "\n\tvendor/${VENDOR}/${DEVICE}/${1}:\$(TARGET_COPY_OUT_SYSTEM_EXT)/${path} " >> $MKFILE
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
}" >> $BPFILE
  elif [[ $1 == *"system/system_ext/"* ]] ; then
    echo -e "
    system_ext_specific: true,
}" >> $BPFILE
  elif [[ $1 == *"system/"* ]] ; then
    echo -e "
}" >> $BPFILE
  elif [[ $1 == *"vendor/"* ]] ; then
    echo -e "
    soc_specific: true,
}" >> $BPFILE
  fi
}

function create_hash() {
  hashGen=false
  local name=${1##*/}
  local file=$2/$name
  ! $pinFirst && read -p "Create hash for this file: $1 [Y/n]?" prompt </dev/tty
  if $pinFirst || [ "$prompt" = "Y" ] || [ -z $prompt ] ; then
    if $includePulls && [ -f $file ] ; then
      print_message $file $3
      ! $pinFirst && read -p "Pin this blob [Y/n]?" pin </dev/tty
      if ! $pinFirst && [ "$pin" = "Y" ] || [ -z $pin ] ; then
        hashGen=true
        replace_line $file $1
        return $?
      fi
    fi
    if ! $hashGen ; then
      for dir in $dirs ; do
        list=$(find $dir -type f -name $name | grep "$1")
        [ -z $list ] && continue
        for line in $list ; do
          blob=$(echo $list | grep "$1")
          [ ! -z $blob ] && break
        done
        ! $pinFirst && read -p "Pin this blob: $blob [Y/n]?" pin </dev/tty
        if $pinFirst || [ "$pin" = "Y" ] || [ -z $pin ] ; then
          replace_line $blob $1
          print_message $1 $blob
          cp $blob $2
          return $?
        fi
      done
    fi
  else
    return $?
  fi
}

function replace_line() {
  blobHash=$(md5sum $1 | awk '{print $1}')
  line=$(cat $BLOBS_LIST | grep $2)
  newLine="$line$blobHash"
  sed -i "s,$line,$newLine," $BLOBS_LIST
}

function print_message() {
  echo -n "Blob $1 "
  [ "$method" = "adb" ] && echo -n "pulled via adb"
  [ "$method" = "copy" ] && echo -n "copied "
  echo "from $2"
}

# Everything starts here
start_extraction
import_lib
import_app
import_dex
import_xml
write_packages
[ $countFailed -ne 0 ] && echo -e "\033[1;31mFailed pulls: $countFailed\033[0m"
