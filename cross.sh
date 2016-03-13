#!/bin/bash
set -e
set -o pipefail
DIR=`pwd`
test -d src/gcc || git submodule add git://github.com/gcc-mirror/gcc src/gcc
test -d src/binutils || git submodule add git://sourceware.org/git/binutils-gdb.git src/binutils
test -d src/cygwin || git submodule add git://sourceware.org/git/newlib-cygwin.git src/cygwin
test -n "$TARGET" || TARGET=x86_64-pc-cygwin
test -n "$PARALLEL" || PARALLEL=$((`nproc`+1))
mkdir -p logs

#cd work/mingw-headers
#test -f Makefile || ($DIR/src/mingw-w64/mingw-w64-headers/configure --host=${TARGET} --prefix=${DIR}/install/${TARGET} || rm Makefile)
#test -f $DIR/install/$TARGET/include/_mingw_mac.h || make install

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
    make -j${PARALLEL} -C $DIR/work/$work $@ |& tee $DIR/logs/$work-build.log
}

install()
{
    work=$1
    shift
    make -j${PARALLEL} -C $DIR/work/$work $@ |& tee $DIR/logs/$work-install.log
}

conf binutils binutils --target=${TARGET} --prefix=${DIR}/install
build binutils all-{binutils,ld,gas}
install binutils install-{binutils,ld,gas}

conf gcc gcc1 --target=${TARGET} --prefix=${DIR}/install --enable-languages=c
build gcc1 all-gcc
exit
install gcc1 install-gcc

conf gcc gcc2 --target=${TARGET} --prefix=${DIR}/install --enable-languages=c++
build gcc2 all
install gcc2 install
