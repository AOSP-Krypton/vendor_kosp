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

# Wrapper script for extracting images from payload

if [ -z $ANDROID_BUILD_TOP ] ; then
  echo "Error: ANDROID_BUILD_TOP is null,please source build/envsetup.sh"
  exit 1
fi

__help() {
  cat <<EOF
    Usage:  -h  Print this help.
            -z  Zip file to extract payload from.
            -e  Directory to extract zip to,default is /tmp
            -p  payload.bin to extract.If neither zip location nor payload is provided then the script expects a payload.bin in the current directory.
                Provide either zip or payload,don't be dumb.
            -o  Directory where the images should be extracted to,default is output in the current folder.
                Any .img files in this directory will get wiped,proceed with caution.
            -d  directory containing old payload for extracting from differential ota,default is old.
            -v  Verbose, useful for debugging errors.
                FYI,if run in verbose mode ext2rd will throw errors like chown or lchown failed,no need to panic it's not an issue.
EOF
exit 0
}

# Default values
OUT=output
OLD=out
DIFF=false
DIR=/tmp
PAYLOAD=payload.bin
VERBOSE=false

# ext2fstools to unpack .img
EXT2RD=$ANDROID_BUILD_TOP/prebuilts/krypton-tools/linux-x86/bin/ext2rd

while getopts 'hz:e:p:o:d:v' arg; do
  case $arg in
    h) __help;;
    z) ZIP=$OPTARG;;
    e) DIR=$OPTARG;;
    p) PAYLOAD=$OPTARG;;
    o) OUT=$OPTARG;;
    d) OLD=$OPTARG
       DIFF=true;;
    v) VERBOSE=true;;
  esac
done

__unzip() {
  if [ ! -z $ZIP ] ; then
    echo "Unzipping....."
    PAYLOAD=$DIR/payload.bin
    rm -rf $PAYLOAD
    if $VERBOSE ; then
      unzip -o $ZIP payload.bin -d $DIR
    else
      unzip -o -q $ZIP payload.bin -d $DIR
    fi
  fi
}

__payload() {
  # Clean out
  rm -rf $OUT/*.img $OUT/system $OUT/vendor
  if ! $DIFF ; then
    python3 payload_dumper.py --out $OUT $PAYLOAD
  else
    python3 payload_dumper.py --diff --old $OLD --out $OUT $PAYLOAD
  fi
}

__unpack() {
  mkdir -p $OUT/system $OUT/vendor
  if $VERBOSE ; then
    if [ -f $OUT/system.img ] ; then
      $EXT2RD $OUT/system.img ./:$OUT/system
    fi
    if [ -f $OUT/vendor.img ] ; then
      $EXT2RD $OUT/vendor.img ./:$OUT/vendor
    fi
  else
    if [ -f $OUT/system.img ] ; then
      echo "Unpacking system.img...."
      $EXT2RD $OUT/system.img ./:$OUT/system &>/dev/null
      if [ $? -eq 0 ] ; then
        echo "Done"
      else
        echo "System unpack failed"
      fi
    fi
    if [ -f $OUT/vendor.img ] ; then
      echo "Unpacking vendor.img...."
      $EXT2RD $OUT/vendor.img ./:$OUT/vendor &>/dev/null
      if [ $? -eq 0 ] ; then
        echo "Done"
      else
        echo "Vendor unpack failed"
      fi
    fi
  fi
}

__unzip
__payload
__unpack
