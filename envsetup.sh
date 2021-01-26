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

# Common tags
ERROR="\033[1;31mError"
INFO="\033[1;32mInfo"
WARN="\033[1;35mWarning"
NC="\033[0m"

# Default to unofficial status
official=false

function krypton_help() {
cat <<EOF
Krypton specific functions:
- cleanup:    Clean \$OUT directory, logs, as well as intermediate zips if any.
- launch:     Build a full ota.
              Usage: launch <device> <variant> [-q] [-s] [-g] [-n]
              -q to run silently.
              -s to generate signed ota.
              -g to build gapps variant.
              -n to not wipe out directory.
- dirty:      Run a dirty build.Mandatory to run lunch prior to it's execution.
              Usage: dirty [-q]
              -q to run silently.
- sign:       Sign and build ota.Execute only after a successfull make.
              Usage: sign [-q]
              -q to run silently.
- zipup:      Rename the signed ota with build info.
              Usage: zipup <variant>
- search:     Search in every file in the current directory for a string.Uses xargs for parallel search.
              Usage: search <string>
- reposync:   Sync repo with the following default params: -j\$(nproc --all) --no-clone-bundle --no-tags --current-branch.
              Pass in additional options alongside if any.
- fetchrepos: Set up local_manifest for device and fetch the repos set in vendor/krypton/products/device.deps
              Usage: fetchrepos <device>

If run quietly, full logs will be available in ${ANDROID_BUILD_TOP}/buildlog.
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
  echo -e "${INFO}: cleaning build directory....${NC}"
  make clean &> /dev/null
  rm -rf *.zip buildlog
  echo -e "${INFO}: done cleaning${NC}"
  return $?
}

function fetchrepos() {
  local deps="${ANDROID_BUILD_TOP}/vendor/krypton/products/${1}.deps"
  local list=() # Array for holding the projects
  local repos=() # Array for storing the values for the <project> tag
  local dir="${ANDROID_BUILD_TOP}/.repo/local_manifests" # Local manifest directory
  local manifest="${dir}/${1}.xml" # Local manifest
  [ -z $1 ] && echo -e "${ERROR}: device name cannot be empty.Usage: fetchrepos <device>${NC}" && return 1
  echo "${INFO}: Setting up ${1}.xml${NC}"

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
  reposync # Sync the repos
}

function launch() {
  OPTIND=1
  local device=""
  local variant=""
  local quiet=false
  local sign=false
  local wipe=true
  local GAPPS_BUILD=false

  # Add all officialy supported devices to an array
  local LIST="${ANDROID_BUILD_TOP}/vendor/krypton/products/products.list"
  while read -r product; do
    krypton_products+=("$product")
  done < $LIST

  # Check for official devices
  for product in ${krypton_products[@]}; do
    if [ $1 == $product ] ; then
      device="$1"
      official=true
      break
    fi
  done
  shift # Remove device name from options

  # Check for build variant
  check_variant $1
  [ $? -ne 0 ] && echo -e "${ERROR}: invalid build variant${NC}" && return 1
  variant=$1
  shift # Remove build variant from options

  while getopts ":qsgn" option; do
    case $option in
      q) quiet=true;;
      s) sign=true;;
      g) GAPPS_BUILD=true;;
      n) wipe=false;;
     \?) echo -e "${ERROR}: invalid option, run hmm and learn the proper syntax${NC}"; return 1
    esac
  done
  export GAPPS_BUILD # Set whether to include gapps in the rom

  # Execute rest of the commands now as all vars are set.
  if $quiet ; then
    # Show official or unofficial status
    if $official ; then
      echo -e "${INFO}: device $device is officially supported by KOSP${NC}"
    else
      echo -e "${WARN}: device $device is not officially supported,you might not be able to complete the build successfully${NC}"
    fi
    $wipe && cleanup
    echo -e "${INFO}: Starting build for $device ${NC}"
    lunch krypton_$device-$variant &>> buildlog
    [ $? -eq 0 ] && dirty -q
    [ $? -eq 0 ] && $sign && sign -q && zipup $variant && return 0
  else
    $wipe && rm -rf *.zip buildlog && make clean
    lunch krypton_$device-$variant
    [ $? -eq 0 ] && dirty
    [ $? -eq 0 ] && $sign && sign && zipup $variant && return 0
  fi
  return 1
}

function dirty() {
  croot
  if [ -z $1 ] ; then
    make -j$(nproc --all) target-files-package otatools && return 0
  elif [ $1 == "-q" ] ; then
    [ -z $KRYPTON_BUILD ] && echo -e "${ERROR}: Target device not found ,have you run lunch?${NC}" && return 1
    echo -e "${INFO}: running make....${NC}"
    local start=$(date "+%s")
    make -j$(nproc --all) target-files-package otatools  &>> buildlog
    [ $? -eq 0 ] && echo -e "\n${INFO}: make finished in $(timer $start $(date "+%s"))${NC}" && return 0
  else
    echo -e "${ERROR}: expected argument \"-q\", provided \"$1\"${NC}" && return 1
  fi
}

function sign() {
  local tfi="$OUT/obj/PACKAGING/target_files_intermediates/*target_files*.zip"
  local apksign="./build/tools/releasetools/sign_target_files_apks -o -d $ANDROID_BUILD_TOP/certs \
                -p out/host/linux-x86 -v $tfi signed-target_files.zip"

  local buildota="./build/tools/releasetools/ota_from_target_files -k $ANDROID_BUILD_TOP/certs/releasekey \
                  -p out/host/linux-x86 -v --block \
                  signed-target_files.zip signed-ota.zip"

  croot
  if [ -z $1 ] ; then
    $apksign && $buildota
  elif [ $1 == "-q" ] ; then
    local start=$(date "+%s")
    if [ -z $KRYPTON_BUILD ] ; then
      echo -e "${ERROR}: target device not found,have you run lunch?${NC}" && return 1
    elif [ ! -f $tfi ] ; then
      echo -e "${ERROR}: target files zip not found,was make successfull?${NC}" && return 1
    fi
    echo -e "${INFO}: signing build......${NC}"
    $apksign &>> buildlog
    [ $? -ne 0 ] && echo -e "${ERROR}: failed to sign build!${NC}" && return 1
    echo -e "${INFO}: done signing build${NC}"
    echo -e "${INFO}: generating ota package.....${NC}"
    $buildota &>> buildlog
    [ $? -ne 0 ] && echo -e "${ERROR}: failed to build ota!${NC}" && return 1
    echo -e "${INFO}: signed ota built from target files package${NC}"
    echo -e "${INFO}: ota generated in $(timer $start $(date "+%s"))${NC}"
    return 0
  else
    echo -e "${ERROR}: expected argument \"-q\", provided \"$1\"${NC}" && return 1
  fi
}

function zipup() {
  croot
  # Version info
  versionMajor=1
  versionMinor=0
  version="v$versionMajor.$versionMinor"

  # Check build variant and check if ota is present
  check_variant $1
  [ $? -ne 0 ] && echo -e "${ERROR}: must provide a valid build variant${NC}" && return 1
  [ ! -f signed-ota.zip ] && echo -e "${ERROR}: ota not found${NC}" && return 1

  # Rename the ota with proper version info and timestamp
  if $official ; then
    mv signed-ota.zip KOSP-${version}-${KRYPTON_BUILD}-OFFICIAL-$(date "+%Y%d%m")-${1}.zip
  else
    mv signed-ota.zip KOSP-${version}-${KRYPTON_BUILD}-UNOFFICIAL-$(date "+%Y%d%m")-${1}.zip
  fi
  echo -e "${LTGREEN}Now flash that shit and feel the kryptonian power${NC}"
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
