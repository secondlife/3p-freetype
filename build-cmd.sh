#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

FREETYPELIB_SOURCE_DIR="freetype"

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [[ "$OSTYPE" == "cygwin" || "$OSTYPE" == "msys" ]] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

top="$(pwd)"
stage="$(pwd)/stage"

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# remove_cxxstd
source "$(dirname "$AUTOBUILD_VARIABLES_FILE")/functions"

[ -f "$stage"/packages/include/zlib-ng/zlib.h ] || fail "You haven't installed packages yet."

pushd "$FREETYPELIB_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in

        windows*)
            load_vsvars

            opts="$(replace_switch /Zi /Z7 $LL_BUILD_RELEASE)"
            plainopts="$(remove_switch /GR $(remove_cxxstd $opts))"

            mkdir -p "build"
            pushd "build"
                cmake -G Ninja .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS:BOOL=OFF \
                    -DCMAKE_C_FLAGS:STRING="$plainopts" \
                    -DCMAKE_CXX_FLAGS:STRING="$opts" \
                    -DCMAKE_INSTALL_PREFIX="$(cygpath -m $stage)" \
                    -DCMAKE_INSTALL_LIBDIR="$(cygpath -m "$stage/lib/release")" \
                    -DFT_REQUIRE_ZLIB=ON \
                    -DFT_REQUIRE_PNG=ON \
                    -DFT_DISABLE_HARFBUZZ=ON \
                    -DFT_DISABLE_BZIP2=ON \
                    -DFT_DISABLE_BROTLI=ON \
                    -DZLIB_INCLUDE_DIR="$(cygpath -m "$stage/packages/include/zlib-ng/")" \
                    -DZLIB_LIBRARY="$(cygpath -m "$stage/packages/lib/release/zlib.lib")" \
                    -DPNG_PNG_INCLUDE_DIR="$(cygpath -m "${stage}/packages/include/libpng16/")" \
                    -DPNG_LIBRARY="$(cygpath -m "${stage}/packages/lib/release/libpng16.lib")"

                cmake --build . --config Release
                cmake --install . --config Release
            popd
        ;;

        darwin*)
            export MACOSX_DEPLOYMENT_TARGET="$LL_BUILD_DARWIN_DEPLOY_TARGET"

            for arch in x86_64 arm64 ; do
                ARCH_ARGS="-arch $arch"
                opts="${TARGET_OPTS:-$ARCH_ARGS $LL_BUILD_RELEASE}"
                cc_opts="$(remove_cxxstd $opts)"
                ld_opts="$ARCH_ARGS"

                mkdir -p "build_$arch"
                pushd "build_$arch"
                    CFLAGS="$cc_opts" \
                    CXXFLAGS="$opts" \
                    LDFLAGS="$ld_opts" \
                    cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS:BOOL=OFF \
                        -DCMAKE_C_FLAGS="$cc_opts" \
                        -DCMAKE_CXX_FLAGS="$opts" \
                        -DCMAKE_OSX_ARCHITECTURES:STRING="$arch" \
                        -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                        -DCMAKE_MACOSX_RPATH=YES \
                        -DCMAKE_INSTALL_PREFIX="$stage" \
                        -DCMAKE_INSTALL_LIBDIR="$stage/lib/release/$arch" \
                        -DFT_REQUIRE_ZLIB=ON \
                        -DFT_REQUIRE_PNG=ON \
                        -DFT_DISABLE_HARFBUZZ=ON \
                        -DFT_DISABLE_BZIP2=ON \
                        -DFT_DISABLE_BROTLI=ON \
                        -DPNG_PNG_INCLUDE_DIR="${stage}/packages/include/libpng16/" \
                        -DPNG_LIBRARY="${stage}/packages/lib/release/libpng16.a" \
                        -DZLIB_INCLUDE_DIR="${stage}/packages/include/zlib-ng/" \
                        -DZLIB_LIBRARY="${stage}/packages/lib/release/libz.a"

                    cmake --build . --config Release
                    cmake --install . --config Release

                    # conditionally run unit tests
                    if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                        ctest -C Release
                    fi
                popd
            done

            # Create universal library
            lipo -create -output "$stage/lib/release/libfreetype.a" "$stage/lib/release/x86_64/libfreetype.a" "$stage/lib/release/arm64/libfreetype.a"
        ;;

        linux*)
            # Default target per AUTOBUILD_ADDRSIZE
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE}"
            plainopts="$(remove_cxxstd $opts)"

            mkdir -p "build"
            pushd "build"
                cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS:BOOL=OFF \
                    -DCMAKE_C_FLAGS="$plainopts" \
                    -DCMAKE_CXX_FLAGS="$opts" \
                    -DCMAKE_INSTALL_PREFIX="$stage" \
                    -DCMAKE_INSTALL_LIBDIR="$stage/lib/release" \
                    -DFT_REQUIRE_ZLIB=ON \
                    -DFT_REQUIRE_PNG=ON \
                    -DFT_DISABLE_HARFBUZZ=ON \
                    -DFT_DISABLE_BZIP2=ON \
                    -DFT_DISABLE_BROTLI=ON \
                    -DPNG_PNG_INCLUDE_DIR="${stage}/packages/include/libpng16/" \
                    -DPNG_LIBRARY="${stage}/packages/lib/release/libpng16.a" \
                    -DZLIB_INCLUDE_DIR="${stage}/packages/include/zlib-ng/" \
                    -DZLIB_LIBRARY="${stage}/packages/lib/release/libz.a"

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp LICENSE.TXT "$stage/LICENSES/freetype.txt"
popd

mkdir -p "$stage"/docs/freetype/
cp -a README.Linden "$stage"/docs/freetype/
