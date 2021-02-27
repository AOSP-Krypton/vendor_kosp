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
            -o  Directory where the images should be extracted to,default is output in the current folder.
                Any files in this directory will get wiped,proceed with caution.
EOF
exit 0
}

# Default values
OUT=output

# ext2fstools to unpack .img
EXT2RD=$ANDROID_BUILD_TOP/prebuilts/krypton-tools/linux-x86/bin/ext2rd

while getopts 'hz:o:' arg; do
  case $arg in
    h) __help;;
    z) ZIP=$OPTARG;;
    o) OUT=$OPTARG;;
  esac
done

# Abort if zipfile is not provided
[ -z $ZIP ] && echo "Error: zip file not provided, use -h for help"
# Check for required directories and make them if not present, exit if unable to make them
[ -d $OUT ] || mkdir -p $OUT
[ $? -ne 0 ] && echo "Error: unable to create dir $OUT" && exit 1
$DIFF && [ ! -d $OLD ] && echo "Error: directory $OLD does not exist!" && exit 1

__unzip() {
  if [ ! -z $ZIP ] ; then
    rm -rf $OUT/*
    unzip -o $ZIP -d $OUT
    [ $? -ne 0 ] && exit 1
  fi
}

__extract() {
  brotli_files=$(find $OUT -type f -name *.br)
  [ ! -z "$brotli_files" ] && __brotli "$brotli_files" && return $?
  payload=$(find $OUT -type f -name *.bin)
  [ ! -z "$payload" ] && __payload $payload && return $?
}

__brotli() {
  for file in $1 ; do
    of=$(echo $file | sed 's|.br||')
    brotli --decompress $file -o $of
    [ $? -ne 0 ] && exit 1
    __sdat2img $of
  done
}

__sdat2img() {
  partName=$(echo $1 | sed 's|.new.dat||')
  trlist="$partName.transfer.list"
  partName=${partName##*/}
  echo $partName $trlist
  ./sdat2img.py $trlist $1 $OUT/"$partName.img"
  [ $? -ne 0 ] && exit 1
}

__payload() {
  python3 payload_dumper.py --out $OUT $1
  [ $? -ne 0 ] && exit 1
}

__unpack() {
  mkdir -p $OUT/system $OUT/vendor
  if [ -f $OUT/system.img ] ; then
    $EXT2RD $OUT/system.img ./:$OUT/system
  fi
    if [ -f $OUT/vendor.img ] ; then
      $EXT2RD $OUT/vendor.img ./:$OUT/vendor
  fi
}

echo "Starting extraction......"
__unzip
__extract
__unpack
echo "Extraction finished successfully!"
