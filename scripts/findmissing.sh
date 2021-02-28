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

[ -z $1 ] && echo "Error: provide path to the directory where rom is dumped" && exit 1
if ! which readelf > /dev/null ; then
    echo "Error: readelf program not found, install it"
fi

dirs=$(find $1 -type d -name "bin" 2>/dev/null)
list=$(find $1 -type f -name *.so 2>/dev/null)
missing=
for dir in $dirs ; do
    path=${dir%/*}
    for libPath in lib lib64 ; do
        currentDir="$path/$libPath"
        echo "Searching in path $currentDir"
        libs=$(find $currentDir -type f -name *.so)
        for lib in $libs ; do
            deps=$(readelf --dynamic $lib | grep "Shared library")
            [ $? -ne 0 ] && echo "$lib"
            for tmp in $deps ; do
                temp=$(echo $tmp | grep "\[")
                if [ ! -z $temp ] ; then
                    blob=$(echo ${temp#*[} | sed 's/]//')
                    isPresent=$(echo $list | grep $blob)
                    [ ! -z "$isPresent" ] && continue
                    found=$(find $currentDir -type f -name $blob)
                    if [ -z "$found" ] ; then
                        if [ -z "$(echo $missing | grep $blob)" ] ; then
                            echo "$blob not found" && missing+="$blob "
                        fi
                    fi
                fi
            done
        done
    done
done
