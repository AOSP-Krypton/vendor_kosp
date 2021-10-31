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

# Clear the screen
clear

# Colors
LR="\033[1;31m"
LG="\033[1;32m"
LP="\033[1;35m"
NC="\033[0m"

# Common tags
ERROR="${LR}Error"
INFO="${LG}Info"
WARN="${LP}Warning"

# Add all officialy supported devices to an array
krypton_products=()
device=

buildDate=

# Set to non gapps build by default
GAPPS_BUILD=false
export GAPPS_BUILD

function devices() {
  local tmp="0"
  local LIST="${ANDROID_BUILD_TOP}/vendor/krypton/products/products.list"
  local print=false
  krypton_products=()
  # Check whether to print list of devices
  [ ! -z $1 ] && [ $1 == "-p" ] && print=true && echo -e "${LG}List of officially supported devices and corresponding codes:${NC}"

  while read -r product; do
    if [ ! -z $product ] ; then
      tmp=$(expr $tmp + 1)
      krypton_products+=("$product:$tmp")
      if $print ; then
        echo -ne "${LP}$tmp:${NC} ${LG}$product${NC}\t"
        local pos=$(expr $tmp % 3)
        [ $pos -eq 0 ] && echo -ne "\n"
      fi
    fi
  done < $LIST
  $print && echo ""
}
devices
official=false # Default to unofficial status

function krypton_help() {
cat <<EOF
Krypton specific functions:
- cleanup:    Clean \$OUT directory, as well as intermediate zips if any.
- launch:     Build a full ota.
              Usage: launch <device | codenum> <variant> [-g] [-w] [-c] [-f]
              codenum for your device can be obtained by running: devices -p
              -g to build gapps variant.
              -w to wipe out directory.
              -c to do an install-clean.
              -j to generate ota json for the device.
              -f to generate fastboot zip
              Example: 'launch 1 user -wg' , or 'launch guacamole user -wg'
                    Both will do a clean user build with gapps for device guacamole (codenum 1)
- devices:    Usage: devices -p
              Prints all officially supported devices with their code numbers.
- chk_device: Usage: chk_device <device>
              Prints whether or not device is officially supported by KOSP
- gen_info:   Print ota info like md5, size.
              Usage: gen_info [-j]
              -j to generate json
- search:     Search in every file in the current directory for a string.Uses xargs for parallel search.
              Usage: search <string>
- reposync:   Sync repo with the following default params: -j\$(nproc --all) --no-clone-bundle --no-tags --current-branch.
              Pass in additional options alongside if any.
- fetchrepos: Set up local_manifest for device and fetch the repos set in vendor/krypton/products/device.deps
              Usage: fetchrepos <device>
- keygen:     Generate keys for signing builds.
              Usage: keygen <dir>
              Default dir is ${ANDROID_BUILD_TOP}/certs
- merge_aosp: Fetch and merge the given tag from aosp source for the repos forked from aosp in krypton.xml
              Usage: merge_aosp -t <tag> [-p]
              -t for aosp tag to merge
              -p to push to github for all repos
              Example: merge_aosp -t android-12.0.0_r2 -p
EOF
}

function timer() {
  local time=$(expr $2 - $1)
  local sec=$(expr $time % 60)
  local min=$(expr $time / 60)
  local hr=$(expr $min / 60)
  local min=$(expr $min % 60)
  echo "$hr:$min:$sec"
}

function cleanup() {
  croot
  make clean
  rm -rf K*.zip s*.zip
  return $?
}

function fetchrepos() {
  local deps="${ANDROID_BUILD_TOP}/vendor/krypton/products/${1}.deps"
  local list=() # Array for holding the projects
  local repos=() # Array for storing the values for the <project> tag
  local dir="${ANDROID_BUILD_TOP}/.repo/local_manifests" # Local manifest directory
  local manifest="${dir}/${1}.xml" # Local manifest
  [ -z $1 ] && echo -e "${ERROR}: device name cannot be empty.Usage: fetchrepos <device>${NC}" && return 1
  [ ! -f $deps ] && echo -e "${ERROR}: deps file $deps not found" && return 1 # Return if deps file is not found
  echo -e "${INFO}: Setting up manifest for ${1}${NC}"

  [ ! -d $dir ] && mkdir -p $dir
  echo -e "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<manifest>" > $manifest

  # Grab all the projects
  while read -r project; do
    [[ ! $project =~ ^#.* ]] && list+=("$project")
  done < $deps

  for ((i=0; i<${#list[@]}; i++)); do
    local project=()
    for val in ${list[i]}; do
      project+=($val)
    done
    echo -e "\t<project ${project[@]} />" >> $manifest
  done
  echo "</manifest>" >> $manifest # Manifest has been written
  echo -e "${INFO}: Fetching repos....${NC}"
  reposync # Sync the repos
}

function chk_device() {
  device=""
  official=false
  for entry in ${krypton_products[@]}; do
    local product=${entry%:*}
    local product_num=${entry#*:}
    if [ "$1" == "$product_num" ] || [ "$1" == "$product" ] ; then
      device="$product"
      official=true
      break
    fi
  done
  [ -z "$device" ] && device="$1"
  # Show official or unofficial status
  if $official ; then
    echo -e "${INFO}: device $device is officially supported by KOSP${NC}"
  else
    echo -e "${WARN}: device $device is not officially supported by KOSP${NC}"
  fi
}

function launch() {
  buildDate=$(date "+%Y%m%d")
  OPTIND=1
  local variant=""
  local wipe=false
  local installclean=false
  local json=false
  local fastbootZip=false

  # Check for official devices
  chk_device $1; shift # Remove device name from options

  # Check for build variant
  check_variant $1
  [ $? -ne 0 ] && echo -e "${ERROR}: invalid build variant${NC}" && return 1
  variant=$1; shift # Remove build variant from options
  GAPPS_BUILD=false # Reset it here everytime
  while getopts ":gwcjf" option; do
    case $option in
      g) GAPPS_BUILD=true;;
      w) wipe=true;;
      c) installclean=true;;
      j) json=true;;
      f) fastbootZip=true;;
     \?) echo -e "${ERROR}: invalid option, run hmm and learn the proper syntax${NC}"; return 1
    esac
  done
  export GAPPS_BUILD # Set whether to include gapps in the rom

  # Execute rest of the commands now as all vars are set.
  timeStart=$(date "+%s")

  if $wipe ; then
    cleanup
  elif $installclean ; then
    make install-clean
  fi

  lunch krypton_$device-$variant
  STATUS=$?

  if [ $STATUS -eq 0 ] ; then
    make -j$(nproc --all) kosp
    STATUS=$?
  else
    return $STATUS
  fi

  if [ $STATUS -eq 0 ] ; then
    rename_zip
    STATUS=$?
  else
    return $STATUS
  fi

  if [ $STATUS -eq 0 ] ; then
    if $json ; then
      gen_info "-j"
      STATUS=$?
    else
      gen_info
      STATUS=$?
    fi
  else
    return $STATUS
  fi

  if [ $STATUS -eq 0 ] ; then
    if $fastbootZip ; then
      gen_fastboot_zip
      STATUS=$?
    fi
  fi

  endTime=$(date "+%s")
  echo -e "${INFO}: build finished in $(timer $timeStart $endTime)${NC}"

  return $STATUS
}

function rename_zip() {
  croot
  FULL_PATH=$(find $OUT -type f -name "KOSP*.zip" -printf "%T@ %p\n" | sort -n | tail -n 1 | awk '{print $2}')
  FILE=$(basename $FULL_PATH)
  FILENAME=${FILE%.*}
  TIME=$(date "+%Y%m%d-%H%M")
  FILE="$FILENAME-$TIME.zip"
  DST_FILE=$OUT/$FILE
  mv $FULL_PATH $DST_FILE
  REL_PATH=$(realpath --relative-to="$PWD" $DST_FILE)
  echo -e "${INFO}: Build file $REL_PATH"
}

function gen_info() {
  croot

  # Check if ota is present
  [ $? -ne 0 ] && echo -e "${ERROR}: must provide a valid build variant${NC}" && return 1
  [ -z $KRYPTON_BUILD ] && echo -e "${ERROR}: have you run lunch?${NC}" && return 1

  FILE=$(find $OUT -type f -name "KOSP*.zip" -printf "%p\n" | sort -n | tail -n 1)
  NAME=$(basename $FILE)

  SIZE=$(du -b $FILE | awk '{print $1}')
  local SIZEH=$(du -h $FILE | awk '{print $1}')
  MD5=$(md5sum $FILE | awk '{print $1}')

  DATE=$(get_prop_value ro.build.date.utc)

  echo -e "${INFO}: name  : ${NAME}"
  echo -e "${INFO}: size  : ${SIZEH} (${SIZE})"
  echo -e "${INFO}: date  : ${DATE}"
  echo -e "${INFO}: md5   : ${MD5}"

  local JSON_DEVICE_DIR=ota/$KRYPTON_BUILD
  JSON=$JSON_DEVICE_DIR/ota.json

  if [ ! -z $1 ] && [ $1 == "-j" ] ; then
    if [ ! -d $JSON_DEVICE_DIR ] ; then
      mkdir -p $JSON_DEVICE_DIR
    fi

    local VERSION=$(get_prop_value ro.krypton.build.version)

    # Generate ota json
    echo -ne "{
      \"version\"    : \"$VERSION\",
      \"date\"       : \"$DATE\",
      \"url\"        : \"https://downloads.kosp.workers.dev/0:/$KRYPTON_BUILD/$NAME\",
      \"filename\"   : \"$NAME\",
      \"filesize\"   : \"$SIZE\",
      \"md5\"        : \"$MD5\"
}" > $JSON
  echo -e "${INFO}: json  : $JSON${NC}"
  fi
}

function get_prop_value() {
  cat $OUT/system/build.prop | grep $1 | sed "s/$1=//"
}

function gen_fastboot_zip() {
  if [ ! -f "out/host/linux-x86/bin/img_from_target_files" ]; then
    make -j8 img_from_target_files
  fi
  local tool="out/host/linux-x86/bin/img_from_target_files"
  local in_file=$(find $OUT/obj/PACKAGING/target_files_intermediates -type f -name "krypton_$KRYPTON_BUILD-target_files-*.zip")
  local out_file="$OUT/fastboot-img.zip"
  local rel_path=$(realpath --relative-to="$PWD" $out_file)
  $tool $in_file $out_file
  mkdir -p $OUT/fboot-tmp
  unzip -q $out_file -d $OUT/fboot-tmp
  cd $OUT/fboot-tmp
  zip -r -6 $OUT/${NAME%.*}-img.zip *
  croot
  rm -rf $OUT/fboot-tmp
  local ret=$?
  echo -e "${INFO}: fastboot-zip  : $rel_path${NC}"
  return $ret
}

function search() {
  [ -z $1 ] && echo -e "${ERROR}: provide a string to search${NC}" && return 1
  find . -type f -print0 | xargs -0 -P $(nproc --all) grep "$*" && return 0
}

function reposync() {
  local SYNC_ARGS="--no-clone-bundle --no-tags --current-branch"
  repo sync -j$(nproc --all) $SYNC_ARGS $*
  return $?
}

function keygen() {
  local certsdir=${ANDROID_BUILD_TOP}/certs
  [ -z $1 ] || certsdir=$1
  rm -rf $certsdir
  mkdir -p $certsdir
  subject=""
  echo "Sample subject: '/C=US/ST=California/L=Mountain View/O=Android/OU=Android/CN=Android/emailAddress=android@android.com'"
  echo "Now enter subject details for your keys:"
  for entry in C ST L O OU CN emailAddress ; do
    echo -n "$entry:"
    read val
    subject+="/$entry=$val"
  done
  for key in releasekey platform shared media networkstack testkey; do
    ./development/tools/make_key $certsdir/$key $subject
  done
}

function merge_aosp() {
  OPTIND=1
  local tag=
  local push=false

  while getopts ":t:p" option; do
    case $option in
      t) tag=$OPTARG;;
      p) push=true;;
     \?) echo -e "${ERROR}: invalid option, run hmm and learn the proper syntax${NC}"; return 1
    esac
  done

  local platformUrl="https://android.googlesource.com/platform/"
  local url=
  local excludeList="krypton|kosp|lineage|vendor|clang"

  croot
  [ -z $tag ] && echo -e "${ERROR}: aosp tag cannot be empty${NC}" && return 1
  local manifest="${ANDROID_BUILD_TOP}/.repo/manifests/snippets/krypton.xml"
  if [ -f $manifest ] ; then
    while read line; do
      if [[ $line == *"<project"* ]] ; then
        tmp=$(echo $line | awk '{print $2}' | sed 's|path="||; s|"||')
        isExcluded=$(echo $tmp | grep -iE $excludeList)
        if [[ ! -z $isExcluded ]] ; then
          continue
        fi
        git -C $tmp rev-parse 2>/dev/null
        if [ $? -eq 0 ] ; then
          cd $tmp
          if [ $tmp == "build/make" ] ; then
            url="${platformUrl}build"
          else
            url="$platformUrl$tmp"
          fi
          remoteName=$(git remote -v | grep -m 1 "$url" | awk '{print $1}')
          if [ -z $remoteName ] ; then
            echo "adding remote for $tmp"
            remoteName="aosp"
            git remote add $remoteName $url
          fi
          echo -e "${INFO}: merging tag $tag in $tmp${NC}"
          git fetch $remoteName $tag && git merge FETCH_HEAD
          if [ $? -eq 0 ] ; then
            echo -e "${INFO}: merged tag $tag${NC}"
            if $push ; then
              git push krypton-ssh HEAD:A12
              if [ $? -ne 0 ] ; then
                echo -e "${ERROR}: pushing changes failed, please do a manual push${NC}"
                return 1
              fi
            fi
          else
            echo -e "${ERROR}: merging tag $tag failed, please do a manual merge${NC}"
            croot
            return 1
          fi
          croot
        else
          echo -e "${ERROR}: $tmp is not a git repo${NC}"
          croot
          return 1
        fi
      fi
    done < $manifest
  else
    echo -e "${ERROR}: unable to find $manifest file${NC}" && return 1
  fi
}
