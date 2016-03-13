#!/bin/bash
set -e
DIR=`pwd`
test -d src/gcc || git submodule add git://github.com/gcc-mirror/gcc src/gcc
test -d src/binutils || git submodule add git://sourceware.org/git/binutils-gdb.git src/binutils
test -d src/cygwin || git submodule add git://sourceware.org/git/newlib-cygwin.git src/cygwin
test -z $TARGET || TARGET=x86_64-pc-cygwin
test -z $PARALLEL || PARALLEL=$((`nproc`+1))
mkdir -p logs work/gcc1
#mkdir -p work/{mingw-{headers,w64},gcc_bootstrap}

#cd work/mingw-headers
#test -f Makefile || ($DIR/src/mingw-w64/mingw-w64-headers/configure --host=${TARGET} --prefix=${DIR}/install/${TARGET} || rm Makefile)
#test -f $DIR/install/$TARGET/include/_mingw_mac.h || make install

cd work/gcc1
test -f Makefile || $DIR/src/gcc/configure --target=${TARGET} --prefix=${DIR}/install --enable-languages=c |& tee $DIR/logs/gcc1.log
make -j5
exit
make all-host all-target-{libgcc,newlib} -j5
test -f $DIR/install/bin/$TARGET-gcc || make install-host install-target-{libgcc,newlib} -j5

#cd ../mingw-w64
#test -f Makefile || (PATH=$DIR/install/bin:${PATH} $DIR/src/mingw-w64/configure --host=${TARGET} --prefix=${DIR}/install/${TARGET} || rm Makefile)
#PATH=$DIR/install/bin:$PATH make
