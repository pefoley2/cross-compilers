#!/bin/bash
set -e
set -o pipefail

DIR=`pwd`

test -d src/gcc       || git submodule add git://github.com/gcc-mirror/gcc src/gcc
test -d src/binutils  || git submodule add git://sourceware.org/git/binutils-gdb.git src/binutils
test -d src/cygwin    || git submodule add git://sourceware.org/git/newlib-cygwin.git src/cygwin
test -d src/mingw     || git submodule add https://github.com/mirror/mingw-w64 src/mingw
#test -d src/zlib      || (wget -q http://zlib.net/zlib-1.2.8.tar.gz -O - | tar xz -C src; mv src/zlib-1.2.8 src/zlib)
mkdir -p logs

test -n "$PARALLEL" || PARALLEL=$((`nproc`+1))

TARGET=x86_64-pc-cygwin
MINGW=x86_64-w64-mingw32
TARGET_PREFIX=${DIR}/install/bin/${TARGET}
MINGW_PREFIX=${DIR}/install/bin/${MINGW}

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
#conf mingw/mingw-w64-headers mingw-headers-native --target=${MINGW} --prefix=${DIR}/install/${MINGW}
#build mingw-headers-native all
#test -e $DIR/install/${MINGW}/include/windows.h || install mingw-headers-native install

# no deps
conf binutils binutils --target=${TARGET} --prefix=${DIR}/install
build binutils all-{binutils,ld,gas}
test -e ${TARGET_PREFIX}-ld || install binutils install-{binutils,ld,gas}

# no deps
#conf binutils mingw-binutils --target=${MINGW} --prefix=${DIR}/install
#build mingw-binutils all-{binutils,ld,gas}
#test -e ${MINGW_PREFIX}-ld || install mingw-binutils install-{binutils,ld,gas}

# need mingw-binutils
#conf gcc mingw-gcc --target=${MINGW} --prefix=${DIR}/install --enable-languages=c++ --disable-multilib
#build mingw-gcc all-gcc
#test -e ${MINGW_PREFIX}-gcc || install mingw-gcc install-gcc

# need mingw-gcc
#cd $DIR/src/zlib
#test -e libz.a || CROSS_PREFIX=$DIR/install/bin/${MINGW}- ./configure --prefix=$DIR/install/${MINGW}
#test -e $DIR/install/${MINGW}/lib/libz.a || make -j${PARALLEL} -C $DIR/src/zlib install

# need mingw-gcc
#conf mingw/mingw-w64-crt mingw-crt-native --host=${MINGW} --prefix=${DIR}/install/${MINGW} --disable-lib32 \
#    CC=${MINGW_PREFIX}-gcc DLLTOOL=${MINGW_PREFIX}-dlltool AS=${MINGW_PREFIX}-as AR=${MINGW_PREFIX}-ar RANLIB=${MINGW_PREFIX}-ranlib
#build mingw-crt-native all
#test -e $DIR/install/${MINGW}/lib/libkernel32.a || install mingw-crt-native install

# need mingw-crt-native
#build mingw-gcc all-target-libstdc++-v3
#test -e ${DIR}/install/${MINGW}/lib/libstdc++-6.dll || install mingw-gcc install-target-libstdc++-v3

# need binutils
conf gcc gcc1 --target=${TARGET} --prefix=${DIR}/install --enable-languages=c++ --disable-shared
build gcc1 all-gcc
test -e $DIR/install/bin/${TARGET}-gcc || install gcc1 install-gcc

# need gcc1
# FIXME: target tools
conf cygwin cygwin1 --target=${TARGET} --prefix=${DIR}/install --with-build-time-tools=${DIR}/install/${TARGET}/bin \
    CC_FOR_TARGET=${TARGET_PREFIX}-gcc CXX_FOR_TARGET=${TARGET_PREFIX}-g++ WINDRES_FOR_TARGET=${TARGET_PREFIX}-windres
build cygwin1 all-target-newlib
test -e $DIR/install/${TARGET}/lib/libc.a || install cygwin1 install-target-newlib

# FIXME: shouldn't need this.
#mkdir -p ${DIR}/install/${TARGET}/lib/w32api
#test -e ${DIR}/install/${TARGET}/lib/w32api/libntdll.a || ar r ${DIR}/install/${TARGET}/lib/w32api/libntdll.a

# need gcc1
#conf cygwin/winsup/cygwin cygwin-headers --host=${TARGET} --prefix=${DIR}/install/${TARGET} CC=${TARGET_PREFIX}-gcc
build cygwin1 configure-target-cygwin
# FIXME: winsup-level target
test -e $DIR/install/${TARGET}/include/cygwin/config.h || install cygwin1/${TARGET}/winsup/cygwin install-headers

# needs cygwin-headers
# FIXME: --with-build-time-tools
conf mingw/mingw-w64-crt mingw-crt --host=${TARGET} --prefix=${DIR}/install/${TARGET} --enable-w32api --disable-lib32 \
    CC=${TARGET_PREFIX}-gcc DLLTOOL=${TARGET_PREFIX}-dlltool AS=${TARGET_PREFIX}-as AR=${TARGET_PREFIX}-ar RANLIB=${TARGET_PREFIX}-ranlib
build mingw-crt all
test -e $DIR/install/${TARGET}/lib/w32api/libkernel32.a || install mingw-crt install

# FIXME: shouldn't need this.
#test -e ${DIR}/install/${TARGET}/lib/libcygwin.a || ar r ${DIR}/install/${TARGET}/lib/libcygwin.a
#test -e ${DIR}/install/${TARGET}/lib/crt0.o || ${TARGET_PREFIX}-gcc -xc -c - -o ${DIR}/install/${TARGET}/lib/crt0.o << EOF
#  void __main(void) {}
#  int atexit(void (*function)(void)) {}
#EOF

# need mingw-crt
build gcc1 all-target-libstdc++-v3
test -e $DIR/install/${TARGET}/lib/libstdc++.a || install gcc1 install-target-libstdc++-v3

# need libstdc++-v3
# FIXME: objcopy for target
# FIXME: bootstrap just cygwin
build cygwin1 configure-target-winsup OBJCOPY=${TARGET_PREFIX}-objcopy
#MINGW64_CC=${DIR}/install/${TARGET}/bin/${MINGW}-gcc MINGW_CXX=${DIR}/install/${TARGET}/bin/${MINGW}-g++
build cygwin1/${TARGET}/winsup cygwin
test -e $DIR/install/${TARGET}/lib/cygwin1.dll || install cygwin1/${TARGET}/winsup/cygwin install-libs

# need cygwin1
conf gcc gcc2 --target=${TARGET} --prefix=${DIR}/install --enable-languages=c++
build gcc2 all
test -e $DIR/install/${TARGET}/lib/cyggcc_s-seh-1.dll || install gcc2 install

# needs gcc2
# FIXME: windres for target
conf cygwin cygwin2 --target=${TARGET} --prefix=${DIR}/install --with-build-time-tools=${DIR}/install/${TARGET}/bin \
    CC_FOR_TARGET=${TARGET_PREFIX}-gcc CXX_FOR_TARGET=${TARGET_PREFIX}-g++ WINDRES_FOR_TARGET=${TARGET_PREFIX}-windres
build cygwin2 all OBJCOPY=${TARGET_PREFIX}-objcopy
#MINGW64_CC=${DIR}/install/bin/${MINGW}-gcc MINGW_CXX=${DIR}/install/bin/${MINGW}-g++
test -e $DIR/install/bin/cyglsa64.dll || install cygwin2 install
