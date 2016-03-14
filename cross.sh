#!/bin/bash
set -e
set -o pipefail

DIR=`pwd`

test -d src/gcc || git submodule add git://github.com/gcc-mirror/gcc src/gcc
test -d src/binutils || git submodule add git://sourceware.org/git/binutils-gdb.git src/binutils
test -d src/cygwin || git submodule add git://sourceware.org/git/newlib-cygwin.git src/cygwin
test -d src/mingw || git submodule add https://github.com/mirror/mingw-w64 src/mingw
mkdir -p logs

test -n "$TARGET" || TARGET=x86_64-pc-cygwin
test -n "$PARALLEL" || PARALLEL=$((`nproc`+1))
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
    make --no-print-directory -j${PARALLEL} -C $DIR/work/$work $@ |& tee $DIR/logs/`echo $work|sed 's#/#_#g'`-build.log
}

install()
{
    work=$1
    shift
    make -j${PARALLEL} -C $DIR/work/$work $@ |& tee $DIR/logs/`echo $work|sed 's#/#_#g'`-install.log
}

# no deps
conf mingw/mingw-w64-headers mingw-headers --target=${TARGET} --prefix=${DIR}/install/${TARGET} --enable-w32api
build mingw-headers all
test -e $DIR/install/${TARGET}/include/w32api/windows.h || install mingw-headers install

# no deps
conf binutils binutils --target=${TARGET} --prefix=${DIR}/install
build binutils all-{binutils,ld,gas}
test -e $DIR/install/bin/${TARGET}-ld || install binutils install-{binutils,ld,gas}

# no deps
conf gcc mingw-gcc --target=x86_64-w64-mingw32 --prefix=${DIR}/install --enable-languages=c++
build mingw-gcc all-gcc
test -e $DIR/install/bin/x86_64-w64-mingw32-gcc || install mingw-gcc install-gcc

# needs binutils for target libs
conf gcc gcc1 --target=${TARGET} --prefix=${DIR}/install --enable-languages=c++ --disable-shared
build gcc1 all-gcc
test -e $DIR/install/bin/${TARGET}-gcc || install gcc1 install-gcc

# needs gcc
conf cygwin cygwin1 --target=${TARGET} --prefix=${DIR}/install --with-build-time-tools=${DIR}/install/${TARGET}/bin \
    CC_FOR_TARGET=${TARGET_PREFIX}-gcc CXX_FOR_TARGET=${TARGET_PREFIX}-g++ WINDRES_FOR_TARGET=${TARGET_PREFIX}-windres
build cygwin1 all-target-newlib
test -e $DIR/install/${TARGET}/lib/libc.a || install cygwin1 install-target-newlib

# FIXME: shouldn't need this.
mkdir -p ${DIR}/install/${TARGET}/lib/w32api
test -e ${DIR}/install/${TARGET}/lib/w32api/libntdll.a || ar r ${DIR}/install/${TARGET}/lib/w32api/libntdll.a

# needs libntdll.a
conf cygwin/winsup/cygwin cygwin-headers --target=${TARGET} --prefix=${DIR}/install CC=${TARGET_PREFIX}-gcc
test -e $DIR/install/${TARGET}/include/cygwin/config.h || install cygwin-headers install-headers

# needs cygwin-headers
# FIXME: --with-build-time-tools
conf mingw/mingw-w64-crt mingw-crt --target=${TARGET} --prefix=${DIR}/install/${TARGET} --enable-w32api --disable-lib32 \
    CC=${TARGET_PREFIX}-gcc DLLTOOL=${TARGET_PREFIX}-dlltool AS=${TARGET_PREFIX}-as AR=${TARGET_PREFIX}-ar RANLIB=${TARGET_PREFIX}-ranlib
test -e $DIR/install/${TARGET}/lib/w32api/libkernel32.a || build mingw-crt all
test -e $DIR/install/${TARGET}/lib/w32api/libkernel32.a || install mingw-crt install

# FIXME: shouldn't need this.
test -e ${DIR}/install/${TARGET}/lib/libcygwin.a || ar r ${DIR}/install/${TARGET}/lib/libcygwin.a
test -e ${DIR}/install/${TARGET}/lib/crt0.o || ${TARGET_PREFIX}-gcc -c $DIR/crt.c -o ${DIR}/install/${TARGET}/lib/crt0.o

# needs mingw-crt
build gcc1 all-target-libstdc++-v3
test -e $DIR/install/${TARGET}/lib/libstdc++.a || install gcc1 install-target-libstdc++-v3

# needs libstdc++-v3
# FIXME: objcopy for target
# FIXME: bootstrap just cygwin
build cygwin1 configure-target-winsup MINGW64_CC=${DIR}/install/${TARGET}/bin/x86_64-w64-mingw32-gcc \
    MINGW_CXX=${DIR}/install/${TARGET}/bin/x86_64-w64-mingw32-g++ OBJCOPY=${TARGET_PREFIX}-objcopy
build cygwin1/${TARGET}/winsup cygwin
test -e $DIR/install/${TARGET}/lib/cygwin1.dll || install cygwin1/${TARGET}/winsup/cygwin install-libs

# needs cygwin
conf gcc gcc2 --target=${TARGET} --prefix=${DIR}/install --enable-languages=c++
build gcc2 all
test -e $DIR/install/${TARGET}/lib/cyggcc_s-seh-1.dll || install gcc2 install

# needs shared libgcc
# FIXME: windres for target
conf cygwin cygwin2 --target=${TARGET} --prefix=${DIR}/install --with-build-time-tools=${DIR}/install/${TARGET}/bin \
    CC_FOR_TARGET=${TARGET_PREFIX}-gcc CXX_FOR_TARGET=${TARGET_PREFIX}-g++ WINDRES_FOR_TARGET=${TARGET_PREFIX}-windres
build cygwin2 all
install cygwin2 install
