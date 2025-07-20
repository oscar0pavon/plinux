#!/bin/sh

export MAKEFLAGS=-j32

working_directory=$(pwd)
src_directory=${working_directory}/src
build_directory=${working_directory}/obj

pushd(){
  command pushd "$@" > /dev/null
}

popd(){
  command popd "$@" > /dev/null
}

if [ -d obj ];then

  musl_directory=${build_directory}

  target=$(uname -m)-plinux-gnu
fi

if [ "$1" == "virt" ]; then
  echo "Virtual Machine"
  pushd virtual_machine

  losetup -P /dev/loop0 disk.raw
  
  mount /dev/loop0p1 disk/boot
  mount /dev/loop0p2 disk/root
  

  umount /dev/loop0p1
  umount /dev/loop0p2

  losetup -d /dev/loop0

  popd

  exit
fi

if [ "$1" == "tools" ]; then
  echo "building tools"
else
  echo "Building standard"
fi

if [ "$1" == "clean" ]; then
  pushd ${src_directory}/linux
  make clean
  popd
  pushd ${src_directory}/pboot
  make clean
  popd
  pushd ${src_directory}/pinit
  make clean
  popd
  exit

fi

################## Build ###################

pushd ${src_directory}/pboot
echo "Building bootloader"
make &> /dev/null

popd

pushd ${src_directory}/linux

echo "Building kernel"

make pavon_defconfig &> /dev/null

make &> /dev/null

popd


echo "Building init PID 1"

pushd ${src_directory}/pinit

make &> /dev/null

popd


echo "Building getty"

pushd ${src_directory}/pgetty

make &> /dev/null

popd



echo "Building login"

pushd ${src_directory}/shadow

./configure --sysconfdir=/etc   \
						--disable-static \
						--disable-shadowgrp \
						--disable-silent-rules \
						--disable-subordinate-ids \
						--disable-man \
						--disable-logind \
            --with-{b,yes}crypt \
            --without-libbsd    \
            --with-group-name-max-length=32 \
						--without-libpam \
						--without-bcrypt \
						--without-yescrypt \
						--without-nscd \
						--without-sssd \
						--without-sha-crypt \
						--without-acl \
						--without-attr \
						--without-btrfs \
						--without-audit &> /dev/null

make &> /dev/null

popd



echo "Building bash"

pushd ${src_directory}/bash

./configure --without-bash-malloc &> /dev/null

make &> /dev/null

popd

echo "SUCCESS you have plinux"
exit


################## Toolchain ###################

build_directory=""
src_directory=""
musl_directory=""

if [ -d obj ];then

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
