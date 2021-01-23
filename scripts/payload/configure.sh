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
