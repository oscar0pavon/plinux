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

  target=$(uname -m)-plinux-gnu

  pushd ${src_directory}

  echo "############# Building Binutils"
  pushd ${src_directory}/binutils
  mkdir obj
  pushd ${src_directory}/binutils/obj
  ../configure --prefix=${build_directory}/tools \
             --with-sysroot=${build_directory} \
             --target=${target}       \
             --disable-nls       \
             --enable-gprofng=no \
             --disable-werror    \
             --enable-new-dtags  \
             --enable-default-hash-style=gnu
  make -j32
  make -j32 install

  popd #src


  pushd ${src_directory}/gcc

  mkdir obj
  pushd ${src_directory}/gcc/obj

  ../configure                              \
    --target=${target}                      \
    --prefix=${build_directory}/tools       \
    --with-glibc-version=2.41               \
    --with-sysroot=${build_directory}       \
    --with-newlib             \
    --without-headers         \
    --enable-default-pie      \
    --enable-default-ssp      \
    --disable-nls             \
    --disable-shared          \
    --disable-multilib        \
    --disable-threads         \
    --disable-libatomic       \
    --disable-libgomp         \
    --disable-libquadmath     \
    --disable-libssp          \
    --disable-libvtv          \
    --disable-libstdcxx       \
    --enable-languages=c,c++

  make -j32
  make install


  popd #src

else
  mkdir -p obj/tools
fi
