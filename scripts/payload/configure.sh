#!/bin/bash

# Check for python and required dependencies
if [ -z $(which python3) ] ; then
  echo "Error: please install python3"
  exit 1
elif [ -z $(which pip3) ] ; then
  echo "Error: please install pip3"
  exit 1
elif [ -z $ANDROID_BUILD_TOP ] ; then
  echo "Error: please source envsetup,ANDROID_BUILD_TOP is null"
  exit 1
fi

# Additional modules needed for script
deps=("protobuf==3.6.0" "six==1.11.0" "bsdiff4>=1.1.5")
for dep in ${deps[@]} ; do
  echo "Installing $dep"
  pip3 install $dep
done
