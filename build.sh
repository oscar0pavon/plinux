#!/bin/sh

if [ "$1" == "tools" ]; then
  echo "building tools"
else
  echo "none arguments"
fi


build_directory=""
src_directory=""
musl_directory=""

if [ -d obj ];then
  echo "building"
  working_directory=$(pwd)
  build_directory=${working_directory}/obj
  src_directory=${working_directory}/src

  musl_directory=${build_directory}/musl

  pushd ${src_directory}/musl
  env CFLAGS="$CFLAGS -Os -ffunction-sections -fdata-sections" 
  env LDFLAGS='-Wl,--gc-sections' ./configure --prefix=${musl_directory}
  make -j32 install

  popd
  echo "############# Setting CC to musl-gcc"

  export CC="${musl_directory}/musl/bin/musl-gcc"
  

  echo ${build_directory}

else
  mkdir obj
fi
