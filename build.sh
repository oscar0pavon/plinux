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

  musl_directory=${build_directory}

  pushd ${src_directory}/musl
  env CFLAGS="$CFLAGS -Os -ffunction-sections -fdata-sections" 
  env LDFLAGS='-Wl,--gc-sections' ./configure --prefix=${musl_directory}
  make -j32 install

  popd

  echo "############# Setting CC to musl-gcc"

  export CC="${musl_directory}/bin/musl-gcc"
  
  echo "############# Building Binutils"
  pushd ${src_directory}/binutils
  mkdir obj
  pushd ${src_directory}/binutils/obj
  ../configure --prefix=${build_directory}/tools \
             --with-sysroot=${build_directory} \
             --disable-nls       \
             --enable-gprofng=no \
             --disable-werror    \
             --enable-new-dtags  \
             --enable-default-hash-style=gnu
  make -j32
  make -j32 install

else
  mkdir -p obj/tools
fi
