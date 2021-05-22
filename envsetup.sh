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
device=""

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
              Usage: launch <device | codenum> <variant> [-s] [-g] [-n] [-c]
              codenum for your device can be obtained by running: devices -p
              -s to generate signed ota.
              -g to build gapps variant.
              -n to not wipe out directory.
              -c to do an install-clean.
              Example: 'launch 1 user -sg' , or 'launch guacamole user -sg'
                    Both will do a clean user build with gapps for device guacamole (codenum 1)
- devices:    Usage: devices -p
              Prints all officially supported devices with their code numbers.
- chk_device: Usage: chk_device <device>
              Prints whether or not device is officially supported by KOSP
- sign:       Sign and build ota.Execute only after a successfull make.
- zipup:      Rename the signed ota with build info.
              Usage: zipup <variant>
- search:     Search in every file in the current directory for a string.Uses xargs for parallel search.
              Usage: search <string>
- reposync:   Sync repo with the following default params: -j\$(nproc --all) --no-clone-bundle --no-tags --current-branch.
              Pass in additional options alongside if any.
- fetchrepos: Set up local_manifest for device and fetch the repos set in vendor/krypton/products/device.deps
              Usage: fetchrepos <device>
- keygen:     Generate keys for signing builds.
              Usage: keygen <dir>
              Default dir is ${ANDROID_BUILD_TOP}/certs
- syncopengapps:  Sync OpenGapps repos.
                  Usage: syncgapps [-i]
                  -i to initialize git lfs in all the source repos
- syncpixelgapps:  Sync our Gapps repo.
                  Usage: syncpixelgapps [-i]
                  -i to initialize git lfs in all the source repos
- merge_aosp: Fetch and merge the given tag from aosp source for the repos forked from aosp in krypton.xml
              Usage: merge_aosp <tag>
              Example: merge_aosp android-11.0.0_r37
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
    if [ $1 == $product_num ] || [ $1 == $product ] ; then
      device="$product"
      official=true
      break
    fi
  done
  [ -z $device ] && device="$1"
  # Show official or unofficial status
  if $official ; then
    echo -e "${INFO}: device $device is officially supported by KOSP${NC}"
  else
    echo -e "${WARN}: device $device is not officially supported by KOSP${NC}"
  fi
}

function launch() {
  OPTIND=1
  local variant=""
  local sign=false
  local wipe=true
  local installclean=false

  # Check for official devices
  chk_device $1; shift # Remove device name from options

  # Check for build variant
  check_variant $1
  [ $? -ne 0 ] && echo -e "${ERROR}: invalid build variant${NC}" && return 1
  variant=$1; shift # Remove build variant from options

  while getopts ":sgnc" option; do
    case $option in
      s) sign=true;;
      g) GAPPS_BUILD=true;;
      n) wipe=false;;
      c) installclean=true;;
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
    make -j$(nproc --all) target-files-package otatools
    STATUS=$?
  else
    return $STATUS
  fi

  if [ $STATUS -eq 0 ] ; then
    if $sign ; then
      sign
      STATUS=$?
    fi
  else
    return $STATUS
  fi

  if [ $STATUS -eq 0 ] ; then
    zipup $variant
    STATUS=$?
  else
    return $STATUS
  fi

  endTime=$(date "+%s")
  echo -e "${INFO}: build finished in $(timer $timeStart $endTime)${NC}"

  return $STATUS
}

function sign() {
  croot
  ./build/tools/releasetools/sign_target_files_apks \
         -o -d $ANDROID_BUILD_TOP/certs \
         -p out/host/linux-x86 -v \
         $OUT/obj/PACKAGING/target_files_intermediates/*target_files*.zip signed-target_files.zip
  ./build/tools/releasetools/ota_from_target_files -k $ANDROID_BUILD_TOP/certs/releasekey \
         -p out/host/linux-x86 -v --block \
         signed-target_files.zip signed-ota.zip
}

function zipup() {
  croot
  # Version info
  versionMajor=1
  versionMinor=0
  version="v$versionMajor.$versionMinor"
  TAGS=

  # Check build variant and check if ota is present
  check_variant $1
  [ $? -ne 0 ] && echo -e "${ERROR}: must provide a valid build variant${NC}" && return 1
  [ ! -f signed-ota.zip ] && echo -e "${ERROR}: ota not found${NC}" && return 1

  if $official ; then
    TAGS+="-OFFICIAL"
  fi
  if $GAPPS_BUILD; then
    TAGS+="-GAPPS"
  else
    TAGS+="-VANILLA"
  fi

  SIZE=$(du -b signed-ota.zip | awk '{print $1}')

  # Rename the ota with proper build info and timestamp
  NAME="KOSP-${version}-${KRYPTON_BUILD}${TAGS}-$(date "+%Y%m%d")-${1}.zip"
  mv signed-ota.zip $NAME
  MD5=$(md5sum $NAME | awk '{print $1}')

  DATE=$(cat $OUT/system/build.prop | grep "ro.build.date.utc" | sed 's|ro.build.date.utc=||')

  echo -e "${INFO}: filename: ${NAME}"
  echo -e "${INFO}: filesize: ${SIZE}"
  echo -e "${INFO}: date: ${DATE}"
  echo -e "${INFO}: md5sum: ${MD5}"
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

function syncopengapps() {
  local sourceroot="${ANDROID_BUILD_TOP}/vendor/opengapps/sources"
  [ ! -d $sourceroot ] && echo "${ERROR}: OpenGapps repo has not been synced!${NC}" && return 1
  local all="${sourceroot}/all"
  local arm="${sourceroot}/arm"
  local arm64="${sourceroot}/arm64"

  # Initialize git lfs in the repo
  if [ ! -z $1 ] ; then
    if [ $1 == "-i" ] ; then
      for dir in $all $arm $arm64; do
        cd $dir && git lfs install
      done
    fi
  fi

  # Fetch files
  for dir in $all $arm $arm64; do
    cd $dir && git lfs fetch && git lfs checkout
  done
  croot
}

function syncpixelgapps() {
  local sourceroot="${ANDROID_BUILD_TOP}/vendor/google"
  [ ! -d $sourceroot ] && echo "${ERROR}: Gapps repo has not been synced!${NC}" && return 1
  local gms="${sourceroot}/gms"
  local pixel="${sourceroot}/pixel"

  # Initialize git lfs in the repo
  if [ ! -z $1 ] ; then
    if [ $1 == "-i" ] ; then
      for dir in $gms $pixel; do
        cd $dir && git lfs install
      done
    fi
  fi

  # Fetch files
  for dir in $gms $pixel; do
    cd $dir && git lfs fetch && git lfs checkout
  done
  croot
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
  local tag="$1"
  local platformUrl="https://android.googlesource.com/platform/"
  local url=
  croot
  [ -z $tag ] && echo -e "${ERROR}: aosp tag cannot be empty${NC}" && return 1
  local manifest="${ANDROID_BUILD_TOP}/.repo/manifests/krypton.xml"
  if [ -f $manifest ] ; then
    while read line; do
      if [[ $line == *"<project"* ]] ; then
        tmp=$(echo $line | awk '{print $2}' | sed 's|path="||; s|"||')
        if [[ -z $(echo $tmp | grep -iE "krypton|kosp|devicesettings") ]] ; then
          cd $tmp
          git -C . rev-parse 2>/dev/null
          if [ $? -eq 0 ] ; then
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
            # skip system/core as we have rebased this repo, manually cherry-pick the patches
            if [[ $tmp == "system/core" ]] ; then
              echo -e "${INFO}: skipping $tmp, please do a manual merge${NC}"
              croot
              continue
            fi
            echo -e "${INFO}: merging tag $tag in $tmp${NC}"
            git fetch $remoteName $tag && git merge FETCH_HEAD
            if [ $? -eq 0 ] ; then
              echo -e "${INFO}: merged tag $tag${NC}"
              git push krypton HEAD:A11
              if [ $? -ne 0 ] ; then
                echo -e "${ERROR}: pushing changes failed, please do a manual push${NC}"
              fi
            else
              echo -e "${ERROR}: merging tag $tag failed, please do a manual merge${NC}"
              croot
              return 1
            fi
          else
            echo -e "${ERROR}: $tmp is not a git repo${NC}"
            croot
            return 1
          fi
          croot
        fi
      fi
    done < $manifest
  else
    echo -e "${ERROR}: unable to find $manifest file${NC}" && return 1
  fi
}
