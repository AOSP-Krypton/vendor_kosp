#!/bin/bash

function krypton_help() {
cat <<EOF
Krypton specific functions:
- cleanup:    Clean \$OUT directory, logs, as well as intermediate zips if any.
- launch:     Usage: launch <target> <variant> <q> <sign>
              Clean and then build a full ota.
              Pass target name and build variant as space separated arguments (mandatory).
              Optionally pass "q" to run silently.
              Optionally pass "sing" to generate signed ota.
- dirty:      Run a dirty build.Mandatory to run lunch prior to it's execution.
              Optionally pass "q" to run silently.
- sign:       Sign apps and generate signed ota.Execute only after lunch.
              Optionally pass "q" to run silently.
- search:     Search in every file in the build directory for a string given as an argument.Uses xargs for parallel search.
- reposync:   Sync repo with the following params: -j\$(nproc --all) --no-clone-bundle --no-tags --current-branch.Pass f to force-sync

If run quietly, logs will be available in ${ANDROID_BUILD_TOP}/buildlog.
EOF
}

function cleanup() {
  echo "Info: cleaning build directory...."
  make clean &> /dev/null
  rm -rf *.zip
  rm -rf buildlog
  echo "Info: done cleaning"
}

function launch() {
  if [ $# -lt 2 ] ; then
    echo "Error: please provide target name and build variant"
    return
  elif [ $# -gt 4 ] ; then
    echo "Error: maximum expected arguments 4, provided $#"
    return
  fi

  if [ -z $3 ] ; then
    cleanup
    lunch krypton_$1-$2
    dirty
  elif [ $3 == "q" ] ; then
    cleanup q
    lunch krypton_$1-$2 &>> buildlog
    dirty q
    if [ ! -z $4 ] ; then
      if [ $4 == "sign" ] ; then
        sign q
      else
        echo "Error: expected argument \"sign\", provided \"$3\""
      fi
    fi
  elif [ $3 == "sign" ] ; then
    sign
  else
    echo "Error: expected argument \"q\" or \"sign\", provided \"$3\""
    return
  fi
}

function dirty() {
  if [ -z $KRYPTON_BUILD ] ; then
    echo "Error: Target device not found ,have you run lunch?"
    return
  fi
  local start_time=$(date "+%s")
  if [ -z $1 ] ; then
    make -j$(nproc --all) target-files-package otatools
  elif [ $1 == "q" ] ; then
    echo "Info: running full build......"
    make -j$(nproc --all) target-files-package otatools &>> buildlog
  else
    echo "Error: expected argument \"q\", provided \"$1\""
    return
  fi
  echo -e "\nInfo: make finished in $(timer $start_time $(date "+%s"))"
}

function sign() {
  if [ -z $KRYPTON_BUILD ] ; then
    echo "Error: target device not found,have you run lunch?"
    return
  fi
  local TFI=out/target/product/${KRYPTON_BUILD}/obj/PACKAGING/target_files_intermediates
  local HOSTTOOLS=out/host/linux-x86
  local OTATOOLS=build/tools/releasetools
  local CERTS=$ANDROID_BUILD_TOP/certs
  local start_time=$(date "+%s")
  if [ -z $1 ] ; then
    $OTATOOLS/sign_target_files_apks -o -d $CERTS -p $COMMONTOOLS -v $TFI/*target_files*.zip signed-target_files.zip
    if [ $? -eq 0 ] ; then
      $OTATOOLS/ota_from_target_files -k $CERTS/releasekey -p $COMMONTOOLS -v --block signed-target_files.zip signed-ota.zip
    fi
  elif [ $1 == "q" ] ; then
    echo "Info: signing build......"
    $OTATOOLS/sign_target_files_apks -o -d $CERTS -p $COMMONTOOLS -v $TFI/*target_files*.zip signed-target_files.zip &>> buildlog
    if [ $? -eq 0 ] ; then
      echo "Info: done signing build"
    else
      echo "Error: failed to sign build!"
      return
    fi
    echo "Info: generating ota package....."
    $OTATOOLS/ota_from_target_files -k $CERTS/releasekey -p $COMMONTOOLS -v --block signed-target_files.zip signed-ota.zip &>> buildlog
    if [ $? -eq 0 ] ; then
      echo "Info: signed ota built from target files package"
    else
      echo "Error: failed to build ota!"
      return
    fi
  else
    echo "Error: expected argument \"q\", provided \"$1\""
    return
  fi
  echo -e "\nInfo: ota generated in $(timer $start_time $(date "+%s"))"
}

function timer() {
  local time=$(expr $2 - $1)
  local sec=$(expr $time % 60)
  local min=$(expr $time / 60)
  local hr=$(expr $min / 60)
  local min=$(expr $min % 60)
  echo "$hr:$min:$sec"
}

function search() {
  if [ ! -z $1 ] ; then
    find . -type f -print0 | xargs -0 -P $(nproc --all) grep $1
  else
    echo "Error: please provide a string to search"
  fi
}

function reposync() {
  if [ -z $1 ] ; then
    repo sync -j$(nproc --all) --no-clone-bundle --no-tags --current-branch
  elif [ $1 == "f" ] ; then
    repo sync -j$(nproc --all) --no-clone-bundle --no-tags --current-branch --force-sync
  else
    echo "Error: expected argument \"f\", provided \"$1\""
  fi
}
