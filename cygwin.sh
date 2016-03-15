#!/bin/bash
set -e
set -o pipefail

DIR=`pwd`

test -d src/gcc       || git submodule add git://github.com/gcc-mirror/gcc src/gcc
test -d src/binutils  || git submodule add git://sourceware.org/git/binutils-gdb.git src/binutils
test -d src/cygwin    || git submodule add git://sourceware.org/git/newlib-cygwin.git src/cygwin
test -d src/mingw     || git submodule add https://github.com/mirror/mingw-w64 src/mingw
mkdir -p logs

test -n "$PARALLEL" || PARALLEL=$((`nproc`+1))

TARGET=x86_64-pc-cygwin
TARGET_PREFIX=${DIR}/install/bin/${TARGET}

conf()
{
    src=$1
    shift
    work=$1
    shift
    mkdir -p $DIR/work/$work
    cd $DIR/work/$work
    test -e Makefile || $DIR/src/$src/configure $@ |& tee $DIR/logs/$work-config.log
}

build()
{
    work=$1
    shift
    make --no-print-directory -j${PARALLEL} -C $DIR/work/$work $@ |& tee $DIR/logs/$work-build.log
}

install()
{
    work=$1
    shift
    make -j${PARALLEL} -C $DIR/work/$work $@ |& tee $DIR/logs/$work-install.log
}

# no deps
conf mingw/mingw-w64-headers mingw-headers --target=${TARGET} --prefix=${DIR}/install/${TARGET} --enable-w32api
build mingw-headers all
test -e $DIR/install/${TARGET}/include/w32api/windows.h || install mingw-headers install

# no deps
conf binutils binutils --target=${TARGET} --prefix=${DIR}/install
build binutils all-{binutils,ld,gas}
test -e ${TARGET_PREFIX}-ld || install binutils install-{binutils,ld,gas}

# need binutils
conf gcc gcc1 --target=${TARGET} --prefix=${DIR}/install --enable-languages=c++ --disable-shared --with-newlib
build gcc1 all-gcc
test -e $DIR/install/bin/${TARGET}-gcc || install gcc1 install-gcc

# need gcc1
# FIXME: CC/CXX_FOR_TARGET
conf cygwin cygwin1 --target=${TARGET} --prefix=${DIR}/install --with-build-time-tools=${DIR}/install/${TARGET}/bin \
    CC_FOR_TARGET=${TARGET_PREFIX}-gcc CXX_FOR_TARGET=${TARGET_PREFIX}-g++ --with-only-headers
build cygwin1 all-target-newlib
test -e $DIR/install/${TARGET}/lib/libc.a || install cygwin1 install-target-newlib

# need gcc1
build cygwin1 configure-target-winsup
test -e $DIR/install/${TARGET}/include/cygwin/config.h || install cygwin1 install-target-winsup

# needs cygwin-headers
# FIXME: --with-build-time-tools
conf mingw/mingw-w64-crt mingw-crt --host=${TARGET} --prefix=${DIR}/install/${TARGET} --enable-w32api --disable-lib32 \
    CC=${TARGET_PREFIX}-gcc DLLTOOL=${TARGET_PREFIX}-dlltool AS=${TARGET_PREFIX}-as AR=${TARGET_PREFIX}-ar RANLIB=${TARGET_PREFIX}-ranlib
build mingw-crt all
test -e $DIR/install/${TARGET}/lib/w32api/libkernel32.a || install mingw-crt install

# need mingw-crt
build gcc1 all-target-libstdc++-v3
test -e $DIR/install/${TARGET}/lib/libstdc++.a || install gcc1 install-target-libstdc++-v3

# need libstdc++-v3
conf cygwin cygwin2 --target=${TARGET} --prefix=${DIR}/install --with-build-time-tools=${DIR}/install/${TARGET}/bin \
    CC_FOR_TARGET=${TARGET_PREFIX}-gcc CXX_FOR_TARGET=${TARGET_PREFIX}-g++
# FIXME: objcopy for target
#OBJCOPY=${TARGET_PREFIX}-objcopy
build cygwin2 all
test -e $DIR/install/bin/cyglsa64.dll || install cygwin2 install

# need cygwin2
conf gcc gcc2 --target=${TARGET} --prefix=${DIR}/install
build gcc2 all
test -e $DIR/install/${TARGET}/lib/cyggcc_s-seh-1.dll || install gcc2 install
