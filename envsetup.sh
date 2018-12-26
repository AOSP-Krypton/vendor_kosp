#!/bin/bash

# List of officially supported products
krypton_products=("guacamole")

function krypton_help() {
cat <<EOF
Krypton specific functions:
- cleanup:    Clean \$OUT directory, logs, as well as intermediate zips if any.
- launch:     Usage: launch <target> <variant> -q -s -g
              Clean and then build a full ota.
              Pass target name and build variant as space separated arguments (mandatory).
              Optionally pass -q to run silently.
              Optionally pass -s to generate signed ota.
              Optionallt pass -g to build gapps variant.
- dirty:      Run a dirty build.Mandatory to run lunch prior to it's execution.
              Optionally pass -q to run silently.
- sign:       Sign and build ota.Execute only after a build.
              Optionally pass -q to run silently.
- codex:      Rename the signed ota with proper info.Pass the build variant as an argument.
- search:     Search in every file in the current directory for a string given as an argument.Uses xargs for parallel search.
- reposync:   Sync repo with the following params: -j\$(nproc --all) --no-clone-bundle --no-tags --current-branch.
              Optionally pass -f for --force-sync

If run quietly, logs will be available in ${ANDROID_BUILD_TOP}/buildlog.
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
  echo "Info: cleaning build directory...."
  make clean &> /dev/null
  rm -rf *.zip buildlog
  echo "Info: done cleaning"
  return $?
}

function launch() {
  local args=($*)
  local opt_args=("-q" "-s" "-g")
  local variant=("user" "userdebug" "eng")
  local flag=false
  local hit=0
  local quiet=false
  local sign=false
  local gapps=false

  # Check if enough arguments are passed to run launch
  if [ $# -lt 2 ] ; then
    echo "Error: please provide atleast target name and build variant"
    return
  elif [ $# -gt 5 ] ; then
    echo "Error: maximum expected arguments 5, provided $#"
    return
  fi

  # Check if product is officially supported
  for product in ${krypton_products[@]} ; do
    if [ $1 == $product ] ; then
      echo "Info: $1 is officially supported"
      args=()
      local temp=($*)
      for tmp in ${temp[@]} ; do
        if [ ! $tmp == $1 ] ; then
          args+=($tmp)
        fi
      done
      break
    else
      echo "Error: $1 is not officially supported"
      return 1
    fi
  done

  # Check if passed build variant is valid
  for varnt in ${variant[@]} ; do
    if [ $2 == $varnt ] ; then
      flag=true
      local temp=("${args[@]}")
      args=()
      for tmp in ${temp[@]} ; do
        if [ ! $tmp == $2 ] ; then
          args+=($tmp)
        fi
      done
      break
    fi
  done
  if ! $flag ; then
    echo "Error: valid build variants are 'user' 'userdebug' 'eng', provided '$2'"
    return 1
  fi

  # Basic check passed, hence proceeding to cleaning.
  cleanup

  # Evaluating rest of the arguments:
  for optarg in ${opt_args[@]} ; do
    for arg in ${args[@]} ; do
      if [ $arg == $optarg ] ; then
        hit=$(expr $hit + 1)
        case $arg in
          "-q")
            quiet=true
            ;;

          "-s")
            sign=true
            ;;

          "-g")
            gapps=true
            ;;
        esac
      fi
    done
  done
  if [ $hit -ne ${#args[@]} ] ; then
    echo "Error: invalid argument in '${args[@]}', please run hmm and learn how to use this function"
    return 1
  fi

  # Export variable to choose build type
  if $gapps ; then
    GAPPS_BUILD=true
  else
    GAPPS_BUILD=false
  fi
  export GAPPS_BUILD

  # Execute rest of the commands now as all vars are set.
  if $quiet ; then
    echo "Info: Starting build for $1"
    lunch krypton_$1-$2 &>> buildlog
    dirty -q
  else
    lunch krypton_$1-$2
    dirty
  fi
  if [ $? -eq 0 ] ; then
    if $sign ; then
      sign
    fi
  fi
  if [ $? -eq 0 ] ; then
    codex $2
  fi
  return $?
}

function dirty() {
  if [ -z $KRYPTON_BUILD ] ; then
    echo "Error: Target device not found ,have you run lunch?"
    return 1
  fi
  local start_time=$(date "+%s")
  if [ -z $1 ] ; then
    make -j$(nproc --all) target-files-package otatools
  elif [ $1 == "-q" ] ; then
    echo "Info: running make......"
    make -j$(nproc --all) target-files-package otatools  &>> buildlog
  else
    echo "Error: expected argument \"-q\", provided \"$1\""
    return 1
  fi
  if [ $? -eq 0 ] ; then
    echo -e "\nInfo: make finished in $(timer $start_time $(date "+%s"))"
  fi
  return $?
}

function sign() {
  if [ -z $KRYPTON_BUILD ] ; then
    echo "Error: target device not found,have you run lunch?"
    return 1
  fi
  tfi="$OUT/obj/PACKAGING/target_files_intermediates/*target_files*.zip"
  if [ ! -f $tfi ] ; then
    echo "Error: target files zip not found,was make successfull?"
    return 1
  fi
  local apksign="./build/tools/releasetools/sign_target_files_apks -o -d $ANDROID_BUILD_TOP/certs \
                -p out/host/linux-x86 -v $tfi signed-target_files.zip"

  local buildota="./build/tools/releasetools/ota_from_target_files -k $ANDROID_BUILD_TOP/certs/releasekey \
                  -p out/host/linux-x86 -v --block \
                  signed-target_files.zip signed-ota.zip"

  local start_time=$(date "+%s")
  if [ -z $1 ] ; then
    $apksign
    if [ $? -eq 0 ] ; then
      $buildota
    fi
  elif [ $1 == "-q" ] ; then
    echo "Info: signing build......"
    $apksign &>> buildlog
    if [ $? -eq 0 ] ; then
      echo "Info: done signing build"
    else
      echo "Error: failed to sign build!"
      return $?
    fi
    echo "Info: generating ota package....."
    $buildota &>> buildlog
    if [ $? -eq 0 ] ; then
      echo "Info: signed ota built from target files package"
    else
      echo "Error: failed to build ota!"
      return $?
    fi
  else
    echo "Error: expected argument \"-q\", provided \"$1\""
    return 1
  fi
  if [ $? -eq 0 ] ; then
    echo -e "\nInfo: ota generated in $(timer $start_time $(date "+%s"))"
  fi
  return $?
}

function codex() {
  if [ -z $1 ] ; then
    echo "Error: must provide a build variant"
    return 1
  elif [ $1 != "eng" ] && [ $1 != "userdebug" ] && [ "$1" != "user" ] ; then
    echo "Error: expected argument 'eng' 'userdebug' 'user', provided '$1'"
    return 1
  fi

  if [ -f signed-ota.zip ] ; then
    mv signed-ota.zip KryptoN-OFFICIAL-A11-$KRYPTON_BUILD-$(date "+%Y%d%m")-${1}.zip
    echo "Now flash that shit and feel the kryptonian power"
  else
    echo "Error: ota not found"
    return 1
  fi
}

function search() {
  if [ ! -z $1 ] ; then
    find . -type f -print0 | xargs -0 -P $(nproc --all) grep $1
  else
    echo "Error: please provide a string to search"
    return 1
  fi
  return $?
}

function reposync() {
  local SYNC_ARGS="--no-clone-bundle --no-tags --current-branch"
  if [ -z $1 ] ; then
    repo sync -j$(nproc --all) $SYNC_ARGS
  elif [ $1 == "-f" ] ; then
    repo sync -j$(nproc --all) $SYNC_ARGS --force-sync
  else
    echo "Error: expected argument \"-f\", provided \"$1\""
    return 1
  fi
  return $?
}