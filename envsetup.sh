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
LY="\033[1;33m"
NC="\033[0m"

# Common tags
ERROR="${LR}Error"
INFO="${LG}Info"
WARN="${LY}Warning"

# Set to non gapps build by default
export GAPPS_BUILD=false

function krypton_help() {
    cat <<EOF
Krypton specific functions:
- launch:     Build a full ota package.
              Usage: launch <device> <variant> [-g] [-w] [-c] [-f] [-o] [-i]
                      -g to build gapps variant.
                      -w to wipe out directory.
                      -c to do an install-clean. Also deletes contents of target files dir before copying new target
                         files if specified with -i option
                      -j to generate ota json for the device.
                      -f to generate fastboot zip
                      -b to generate boot.img
                      -s to sideload built zip file
                      -o to set the destination dir (relative) of generated ota zip file, boot.img and such
                      -i to specify directory containing incremental update zip to generate an incremental update.
                         If the directory does not contain target files then default target is built, otherwise
                         incremental target is built. New target files will be copied and replaced in this dir
                         for each build.
- gen_info:   Print ota info like md5, size, etc.
              Usage: gen_info [-j]
                      -j to generate json
- search:     Search in every file in the current directory for a string. Uses xargs for parallel search.
              Usage: search <string>
- reposync:   Sync repo with with some additional flags
- fetchrepos: Set up local_manifest for device and fetch the repos set in device/<vendor>/<codename>/krypton.dependencies
              Usage: fetchrepos <device>
- keygen:     Generate keys for signing builds.
              Usage: keygen <dir>
              Default output dir is ${ANDROID_BUILD_TOP}/certs
- sideload:   Sideload a zip while device is booted. It will boot to recovery, sideload the file and boot you back to system
              Usage: sideload filename
EOF
    "$ANDROID_BUILD_TOP"/vendor/krypton/scripts/merge_aosp.main.kts -h
}

function __timer() {
    local time=$(($2 - $1))
    local sec=$((time % 60))
    local min=$((time / 60))
    local hr=$((min / 60))
    local min=$((min % 60))
    echo "$hr:$min:$sec"
}

function fetchrepos() {
    if [ -z "$1" ]; then
        __print_error "Device name must not be empty"
        return 1
    fi
    if ! command -v python3 &>/dev/null; then
        __print_error "Python3 is not installed"
        return 1
    fi
    $(which python3) vendor/krypton/build/tools/roomservice.py "$1"
}

function launch() {
    OPTIND=1
    local variant=""
    local wipe=false
    local installclean=false
    local json=false
    local fastbootZip=false
    local bootImage=false
    local sideloadZip=false
    local outputDir
    local incremental=false
    local targetFilesDir

    local device=$1
    shift # Remove device name from options

    # Check for build variant
    if ! check_variant "$1"; then
        __print_error "Invalid build variant" && return 1
    fi
    variant=$1
    shift             # Remove build variant from options
    GAPPS_BUILD=false # Reset it here everytime
    while getopts ":gwcjfbso:i:" option; do
        case $option in
        g) GAPPS_BUILD=true ;;
        w) wipe=true ;;
        c) installclean=true ;;
        j) json=true ;;
        f) fastbootZip=true ;;
        b) bootImage=true ;;
        s) sideloadZip=true ;;
        o) outputDir="$OPTARG" ;;
        i) targetFilesDir="$OPTARG" ;;
        \?)
            __print_error "Invalid option, run hmm and learn the proper syntax"
            return 1
            ;;
        esac
    done
    export GAPPS_BUILD # Set whether to include gapps in the rom

    # Execute rest of the commands now as all vars are set.
    startTime=$(date "+%s")

    if ! lunch "krypton_$device-$variant"; then
        return 1
    fi

    if $wipe; then
        make clean
        [ -d "$outputDir" ] && rm -rf "${outputDir:?}/*"
    elif $installclean; then
        make install-clean
        [ -d "$outputDir" ] && rm -rf "${outputDir:?}/*"
    fi

    if [ -z "$outputDir" ]; then
        outputDir="$OUT"
    else
        outputDir="$ANDROID_BUILD_TOP/$outputDir"
        [ -d "$outputDir" ] || mkdir -p "$outputDir"
    fi

    if [ -n "$targetFilesDir" ]; then
        incremental=true
        if $installclean; then
            __print_warn "All files in $targetFilesDir will be deleted before copying new target files"
        fi
        if [ ! -d "$targetFilesDir" ]; then
            mkdir -p "$targetFilesDir"
        fi
    else
        incremental=false
    fi

    local target="kosp"
    local previousTargetFile
    if $incremental; then
        previousTargetFile=$(ls -A "$targetFilesDir" | sort -n | tail -n 1)
        if [ -n "$previousTargetFile" ]; then
            target="kosp-incremental"
            export PREVIOUS_TARGET_FILES_PACKAGE="$targetFilesDir/$previousTargetFile"
        else
            __print_info "Previous target files package not present, using default target"
            export PREVIOUS_TARGET_FILES_PACKAGE=
        fi
    fi
    if ! $incremental && [ -n "$PREVIOUS_TARGET_FILES_PACKAGE" ]; then
        export PREVIOUS_TARGET_FILES_PACKAGE=
    fi

    make "-j$(nproc --all)" "$target" &&
        __rename_zip "$outputDir" &&
        if [ -d "$targetFilesDir" ]; then
            if $installclean; then
                __print_info "Deleting old target files"
                rm -rf ${targetFilesDir:?}/*
            fi
            __copy_new_target_files
        fi &&
        if $json; then
            gen_info "-j" -o "$outputDir"
        else
            gen_info -o "$outputDir"
        fi &&
        if $fastbootZip; then
            gen_fastboot_zip "$outputDir"
        fi &&
        if $bootImage; then
            gen_boot_image "$outputDir"
        fi
    local STATUS=$?

    endTime=$(date "+%s")
    __print_info "Build finished in $(__timer "$startTime" "$endTime")"

    if [ $STATUS -ne 0 ]; then
        return $STATUS
    fi

    if $sideloadZip; then
        sideload "$FILE"
    fi
}

function __rename_zip() {
    croot
    local FULL_PATH
    FULL_PATH=$(find "$OUT" -type f -name "KOSP*.zip" -printf "%T@ %p\n" | sort -n | tail -n 1 | awk '{print $2}')
    local FILE
    FILE=$(basename "$FULL_PATH")
    FILE=$(__zip_append_timestamp "$FILE")
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
    fi
    local DST_FILE="$1/$FILE"
    if ! [[ "$DST_FILE" == "$FILE" ]]; then
        mv "$FULL_PATH" "$DST_FILE"
    fi
    __print_info "Build file $(realpath --relative-to="$PWD" "$DST_FILE")"
}

function __zip_append_timestamp() {
    local TIME
    TIME=$(date "+%Y%m%d-%H%M")
    local APPENDED_ZIP
    APPENDED_ZIP=$(sed -r "s/-*[0-9]*-*[0-9]*.zip//" <<<"$1")-"$TIME.zip"
    echo "$APPENDED_ZIP"
}

function __copy_new_target_files() {
    local newTargetFile
    newTargetFile=$(find "$OUT" -type f -name "*target_files*.zip" -print -quit)
    if [ -z "$newTargetFile" ]; then
        return 1
    fi
    local destTargetFile
    destTargetFile=$(basename "$newTargetFile")
    destTargetFile=$(__zip_append_timestamp "$destTargetFile")
    __print_info "Copying new target files package"
    cp "$newTargetFile" "$targetFilesDir/$destTargetFile"
}

function gen_info() {
    croot
    local GIT_BRANCH="A12"
    local json=false
    local outDir="$OUT"

    OPTIND=1
    while getopts ":jo:" option; do
        case $option in
        j) json=true ;;
        o) outDir="$OPTARG" ;;
        \?)
            __print_error "Invalid option passed to gen_info, run hmm and learn the proper syntax"
            return 1
            ;;
        esac
    done

    if [ ! -d "$outDir" ] ; then
        __print_error "Output dir $outDir doesn't exist"
        return 1
    fi

    # Check if ota is present
    [ -z "$KRYPTON_BUILD" ] && __print_error "Have you run lunch?" && return 1

    FILE=$(find "$outDir" -type f -name "KOSP*.zip" -printf "%p\n" | sort -n | tail -n 1)
    if [ -z "$FILE" ] ; then
        __print_error "OTA file not found!"
        return 1
    fi
    NAME=$(basename "$FILE")

    SIZE=$(du -b "$FILE" | awk '{print $1}')
    local SIZE_IN_GB
    SIZE_IN_GB=$(du -h "$FILE" | awk '{print $1}')
    MD5=$(md5sum "$FILE" | awk '{print $1}')
    SHA512=$(sha512sum "$FILE" | awk '{print $1}')

    DATE=$(get_prop_value ro.build.date.utc)
    DATE=$((DATE * 1000))

    __print_info "Name    : $NAME"
    __print_info "Size    : $SIZE_IN_GB ($SIZE bytes)"
    __print_info "Date    : $DATE"
    __print_info "MD5     : $MD5"
    __print_info "SHA-512 : $SHA512"

    local JSON_DEVICE_DIR=ota/$KRYPTON_BUILD
    JSON=$JSON_DEVICE_DIR/ota.json

    if $json; then
        if [ ! -d "$JSON_DEVICE_DIR" ]; then
            mkdir -p "$JSON_DEVICE_DIR"
        fi

        local VERSION
        VERSION=$(get_prop_value ro.krypton.build.version)

        # Generate ota json
        cat <<EOF >"$JSON"
{
    "version"    : "$VERSION",
    "date"       : "$DATE",
    "url"        : "https://downloads.kosp.workers.dev/0:/$GIT_BRANCH/$KRYPTON_BUILD/$NAME",
    "filename"   : "$NAME",
    "file_name"  : "$NAME",
    "filesize"   : "$SIZE",
    "file_size"  : "$SIZE",
    "md5"        : "$MD5",
    "sha_512"    : "$SHA512"
}
EOF
        __print_info "JSON  : $JSON"
    fi
}

function get_prop_value() {
    grep "$1" "$OUT/system/build.prop" | sed "s/$1=//"
}

function gen_fastboot_zip() {
    croot
    if [ ! -f "out/host/linux-x86/bin/img_from_target_files" ]; then
        make -j8 img_from_target_files
    fi
    local tool="out/host/linux-x86/bin/img_from_target_files"
    local in_file
    in_file=$(find "$OUT"/obj/PACKAGING/target_files_intermediates -type f -name "krypton_$KRYPTON_BUILD-target_files-*.zip")
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
    fi
    local tmp_dir="$OUT/fastboot-tmp"
    if [ ! -d "$tmp_dir" ] ; then
        mkdir -p "$tmp_dir"
    else
        rm -rf "${tmp_dir:?}"/*
    fi
    local out_file="$OUT/fastboot-img-uncompressed.zip"
    [ -f "$out_file" ] && rm -rf "$out_file"
    $tool "$in_file" "$out_file" || return 1
    unzip -q "$out_file" -d "$tmp_dir" || return 1
    local compressed_out_file="$1/${NAME%.*}-img.zip"
    cd "$tmp_dir" || return 1
    zip -r -j -6 "$compressed_out_file" ./* || return 1
    croot
    rm -rf "$tmp_dir"
    __print_info "Fastboot zip  : $(realpath --relative-to="$PWD" "$compressed_out_file")"
    return 0
}

function gen_boot_image() {
    croot
    local intermediates_dir
    intermediates_dir=$(find "$OUT/obj/PACKAGING/target_files_intermediates" -type d -name "krypton_*")
    local boot_img="$intermediates_dir/IMAGES/boot.img"
    local timestamp
    timestamp=$(date +%Y_%d_%m)
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
    fi
    local dest_boot_img="$1/boot_$timestamp.img"
    if cp "$boot_img" "$dest_boot_img"; then
        __print_info "Boot image  : $(realpath --relative-to="$PWD" "$dest_boot_img")"
    else
        __print_error "Source boot image not found!"
    fi
}

function search() {
    [ -z "$1" ] && echo -e "${ERROR}: provide a string to search${NC}" && return 1
    find . -type f -print0 | xargs -0 -P "$(nproc --all)" grep "$*" && return 0
}

function reposync() {
    local SYNC_ARGS="--optimized-fetch --no-clone-bundle --no-tags --current-branch"
    repo sync -j"$(nproc --all)" $SYNC_ARGS "$@"
    return $?
}

function keygen() {
    local certs_dir=${ANDROID_BUILD_TOP}/certs
    [ -z "$1" ] || certs_dir=$1
    rm -rf "$certs_dir"
    mkdir -p "$certs_dir"
    local subject
    echo "Sample subject: '/C=US/ST=California/L=Mountain View/O=Android/OU=Android/CN=Android/emailAddress=android@android.com'"
    echo "Now enter subject details for your keys:"
    for entry in C ST L O OU CN emailAddress; do
        echo -n "$entry:"
        read -r val
        subject+="/$entry=$val"
    done
    for key in releasekey platform shared media networkstack testkey; do
        ./development/tools/make_key "$certs_dir"/$key "$subject"
    done
}

function sideload() {
    adb wait-for-device reboot sideload-auto-reboot && adb wait-for-device-sideload && adb sideload "$1"
}

function merge_aosp() {
    "$ANDROID_BUILD_TOP"/vendor/krypton/scripts/merge_aosp.main.kts "$@"
}

function __print_info() {
    echo -e "${INFO}: $*${NC}"
}

function __print_warn() {
    echo -e "${WARN}: $*${NC}"
}

function __print_error() {
    echo -e "${ERROR}: $*${NC}"
}
