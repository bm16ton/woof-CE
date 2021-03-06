if [ -z "$WOOF_CFLAGS"]; then
    case "$DISTRO_TARGETARCH" in
    arm) WOOF_CFLAGS="-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard" ;;
    x86) WOOF_CFLAGS="-march=i486 -mtune=i686" ;;
    x86_64) WOOF_CFLAGS="-march=x86-64 -mtune=generic" ;;
    esac
fi

[ -z "$WOOF_CXXFLAGS"] && WOOF_CXXFLAGS="$WOOF_CFLAGS"

WOOF_CC="/ccache gcc"
WOOF_CXX="/ccache g++"

WOOF_CFLAGS="$WOOF_CFLAGS -Os -fomit-frame-pointer -ffunction-sections -fdata-sections -fmerge-all-constants"
WOOF_CXXCFLAGS="$WOOF_CXXCFLAGS -Os -fomit-frame-pointer -ffunction-sections -fdata-sections -fmerge-all-constants"
WOOF_LDFLAGS="$WOOF_LDFLAGS -Wl,--gc-sections -Wl,--sort-common -Wl,-s"

MAKEFLAGS=-j`nproc`

HAVE_ROOTFS=0
HAVE_BUSYBOX=0
HERE=`pwd`
PKGS=

# busybox must be first, so other petbuilds can use coreutils commands
for i in ../rootfs-petbuilds/busybox ../rootfs-petbuilds/*; do
    NAME=${i#../rootfs-petbuilds/}

    if grep -iq "^yes|${NAME}|" ../DISTRO_PKGS_SPECS-${DISTRO_BINARY_COMPAT}-${DISTRO_COMPAT_VERSION}; then
        echo "Skipping ${NAME}, using a package"
        continue
    fi

    ALTNAME=`echo ${NAME} | tr - _`
    if grep -iq "^yes|${ALTNAME}|" ../DISTRO_PKGS_SPECS-${DISTRO_BINARY_COMPAT}-${DISTRO_COMPAT_VERSION}; then
        echo "Skipping ${NAME}, using alternate package ${ALTNAME}"
        continue
    fi

    if [ "$NAME" = "pa-applet" ] && [ -z "`grep '^yes|pulseaudio|' ../DISTRO_PKGS_SPECS-${DISTRO_BINARY_COMPAT}-${DISTRO_COMPAT_VERSION}`" ]; then
        echo "Skipping pa-applet, pulseaudio is not installed"
        continue
    fi

    if [ "$NAME" = "xarchiver" ] && [ -n "`grep '^yes|xarchive|' ../DISTRO_PKGS_SPECS-${DISTRO_BINARY_COMPAT}-${DISTRO_COMPAT_VERSION}`" ]; then
        echo "Skipping xarchiver, using xarchive"
        continue
    fi

    if [ "$NAME" = "l3afpad" ] && [ -n "`grep '^yes|leafpad|' ../DISTRO_PKGS_SPECS-${DISTRO_BINARY_COMPAT}-${DISTRO_COMPAT_VERSION}`" ]; then
        echo "Skipping l3afpad, using leafpad"
        continue
    fi

    HASH=`cat ../DISTRO_PKGS_SPECS-${DISTRO_BINARY_COMPAT}-${DISTRO_COMPAT_VERSION} ../DISTRO_COMPAT_REPOS ../DISTRO_COMPAT_REPOS-${DISTRO_BINARY_COMPAT}-${DISTRO_COMPAT_VERSION} ../DISTRO_PET_REPOS $i/petbuild 2>/dev/null | md5sum | awk '{print $1}'`
    if [ ! -d "../petbuild-output/${NAME}-${HASH}" ]; then
        if [ $HAVE_ROOTFS -eq 0 ]; then
            echo "Preparing build environment"
            rm -rf petbuild-rootfs-complete
            cp -a rootfs-complete petbuild-rootfs-complete

            rm -f sh petbuild-rootfs-complete/bin/sh
            ln -s bash petbuild-rootfs-complete/bin/sh

            # to speed up compilation, we build a static, native ccache executable
            if [ ! -f ../petbuild-cache/ccache ]; then
                wget -t 1 -T 15 https://github.com/ccache/ccache/releases/download/v3.7.12/ccache-3.7.12.tar.xz
                tar -xJf ccache-3.7.12.tar.xz
                cd ccache-3.7.12
                CFLAGS=-O3 LDFLAGS="-static -Wl,-s" ./configure
                MAKEFLAGS="$MAKEFLAGS" make
                install -D -m 755 ccache ../../petbuild-cache/ccache
                cd ..
            fi
            install -m 755 ../petbuild-cache/ccache petbuild-rootfs-complete/ccache

            # speed configure scripts by using a native shell executable and a native busybox
            if [ "$WOOF_HOSTARCH" != "$WOOF_TARGETARCH" ]; then
                if [ ! -f ../petbuild-cache/bash ]; then
                    wget -t 1 -T 15 https://ftp.gnu.org/gnu/bash/bash-5.1.tar.gz
                    tar -xzf bash-5.1.tar.gz
                    cd bash-5.1
                    CFLAGS=-O3 LDFLAGS="-static -Wl,-s" ./configure --enable-minimal-config
                    MAKEFLAGS="$MAKEFLAGS" make bash
                    install -D -m 755 bash ../../petbuild-cache/bash
                    cd ..
                fi

                rm -f petbuild-rootfs-complete/bin/sh petbuild-rootfs-complete/bin/bash
                install -m 755 ../petbuild-cache/bash petbuild-rootfs-complete/bin/bash
                ln -s bash petbuild-rootfs-complete/bin/sh

                if [ ! -f ../petbuild-cache/busybox ]; then
                    mkdir -p ../petbuild-cache/busybox
                    wget -t 1 -T 15 https://busybox.net/downloads/busybox-1.32.1.tar.bz2
                    tar -xjf busybox-1.32.1.tar.bz2
                    cp -f ../rootfs-petbuilds/busybox/DOTconfig busybox-1.32.1/.config
                    cd busybox-1.32.1
                    make CONFIG_STATIC=y
                    install -D -m 755 busybox ../../petbuild-cache/busybox
                    cd ..
                fi

                rm -f petbuild-rootfs-complete/bin/busybox
                install -m 755 ../petbuild-cache/busybox petbuild-rootfs-complete/bin/busybox
            fi

            # required for slacko
            chroot petbuild-rootfs-complete ldconfig

            HAVE_ROOTFS=1
        fi

        if [ $HAVE_BUSYBOX -eq 0 -a "$NAME" != "busybox" ]; then
            if [ ! -f petbuild-rootfs-complete/bin/busybox ]; then
                if [ -f ../petbuild-output/busybox-latest/bin/busybox ]; then # busybox petbuild
                    install -D -m 755 ../petbuild-output/busybox-latest/bin/busybox petbuild-rootfs-complete/bin/busybox
                elif [ -f ../packages-${DISTRO_FILE_PREFIX}/busybox/bin/busybox ]; then # prebuilt busybox
                    install -D -m 755 ../packages-${DISTRO_FILE_PREFIX}/busybox/bin/busybox petbuild-rootfs-complete/bin/busybox
                elif [ "$NAME" != "busybox" ]; then
                    echo "No busybox in the build environment!"
                    exit 1
                fi
            fi
            ../support/busybox_symlinks.sh petbuild-rootfs-complete
            HAVE_BUSYBOX=1
        fi

        echo "Downloading ${NAME}"

        if [ -d ../petbuild-sources/${NAME} ]; then
            rm -rf ../petbuild-sources/${NAME}/* 2>/dev/null
        else
            mkdir -p ../petbuild-sources/${NAME}
        fi
        cd ../petbuild-sources/${NAME}
        . ${HERE}/../rootfs-petbuilds/${NAME}/petbuild
        download
        if [ -f ${HERE}/../rootfs-petbuilds/${NAME}/sha256.sum ]; then
            sha256sum -c ${HERE}/../rootfs-petbuilds/${NAME}/sha256.sum || exit 1
        fi

        echo "Building ${NAME}"

        cd $HERE

        mkdir -p ../petbuild-output/${NAME}-${HASH} petbuild-rootfs-complete-${NAME}
        mount -t aufs -o br=../petbuild-output/${NAME}-${HASH}:devx:petbuild-rootfs-complete petbuild petbuild-rootfs-complete-${NAME}

        mkdir -p petbuild-rootfs-complete-${NAME}/proc petbuild-rootfs-complete-${NAME}/sys petbuild-rootfs-complete-${NAME}/dev petbuild-rootfs-complete-${NAME}/tmp
        mkdir -p petbuild-rootfs-complete-${NAME}/root/.ccache
        mount --bind /proc petbuild-rootfs-complete-${NAME}/proc
        mount --bind /sys petbuild-rootfs-complete-${NAME}/sys
        mount --bind /dev petbuild-rootfs-complete-${NAME}/dev
        mount -t tmpfs -o size=1G petbuild-tmp-${NAME} petbuild-rootfs-complete-${NAME}/tmp
        mkdir -p ../petbuild-cache/.ccache
        mount --bind ../petbuild-cache/.ccache petbuild-rootfs-complete-${NAME}/root/.ccache

        cp -a ../petbuild-sources/${NAME}/* petbuild-rootfs-complete-${NAME}/tmp/
        cp -a ../rootfs-petbuilds/${NAME}/* petbuild-rootfs-complete-${NAME}/tmp/
        CC="$WOOF_CC" CXX="$WOOF_CXX" CFLAGS="$WOOF_CFLAGS" CXXFLAGS="$WOOF_CXXFLAGS" LDFLAGS="$WOOF_LDFLAGS" MAKEFLAGS="$MAKEFLAGS" CCACHE_DIR=/root/.ccache CCACHE_NOHASHDIR=1 chroot petbuild-rootfs-complete-${NAME} sh -ec "cd /tmp && . ./petbuild && build"
        ret=$?
        umount -l petbuild-rootfs-complete-${NAME}/root/.ccache
        umount -l petbuild-rootfs-complete-${NAME}/tmp
        umount -l petbuild-rootfs-complete-${NAME}/dev
        umount -l petbuild-rootfs-complete-${NAME}/sys
        umount -l petbuild-rootfs-complete-${NAME}/proc
        umount -l petbuild-rootfs-complete-${NAME}
        rmdir petbuild-rootfs-complete-${NAME}

        if [ $ret -ne 0 ]; then
            echo "ERROR: failed to build ${NAME}"
            rm -rf ../petbuild-output/${NAME}-${HASH}
            rm -rf petbuild-rootfs-complete
            exit 1
        fi

        rm -rf ../petbuild-output/${NAME}-${HASH}/root/.ccache
        rm -rf ../petbuild-output/${NAME}-${HASH}/tmp
        rm -rf ../petbuild-output/${NAME}-${HASH}/etc/ssl
        rm -f ../petbuild-output/${NAME}-${HASH}/etc/resolv.conf
        rm -f ../petbuild-output/${NAME}-${HASH}/root/.wget-hsts

        rm -rf ../petbuild-output/${NAME}-${HASH}/usr/share/man
        rm -rf ../petbuild-output/${NAME}-${HASH}/usr/share/info
        rm -f ../petbuild-output/${NAME}-${HASH}/usr/share/icons/hicolor/icon-theme.cache
        rm -rf ../petbuild-output/${NAME}-${HASH}/lib/pkgconfig
        rm -rf ../petbuild-output/${NAME}-${HASH}/usr/lib/pkgconfig
        rm -rf ../petbuild-output/${NAME}-${HASH}/usr/share/pkgconfig
        rm -rf ../petbuild-output/${NAME}-${HASH}/usr/include

        find ../petbuild-output/${NAME}-${HASH} -name '.wh*' -delete
        find ../petbuild-output/${NAME}-${HASH} -name '.git*' -delete
        find ../petbuild-output/${NAME}-${HASH} -name '*.a' -delete
        find ../petbuild-output/${NAME}-${HASH} -name '*.la' -delete

        LIBDIRS="lib usr/lib"
        case $DISTRO_BINARY_COMPAT in
        slackware64) # in slacko64, we move all shared libraries to lib64
            for LIBDIR in $LIBDIRS; do
                mkdir -p ../petbuild-output/${NAME}-${HASH}/${LIBDIR}64
                for SO in `ls ../petbuild-output/${NAME}-${HASH}/${LIBDIR}/*.so* 2>/dev/null`; do
                    mv -f $SO ../petbuild-output/${NAME}-${HASH}/${LIBDIR}64/
                done
            done
            ;;

        raspbian|debian|devuan|ubuntu|trisquel) # in debian, we move all shared libraries to ARCHDIR, e.g. lib/arm-linux-gnueabihf
            for LIBDIR in $LIBDIRS; do
                mkdir -p ../petbuild-output/${NAME}-${HASH}/${LIBDIR}/${ARCHDIR}
                for SO in `ls ../petbuild-output/${NAME}-${HASH}/${LIBDIR}/*.so* 2>/dev/null`; do
                    mv -f $SO /../petbuild-output/${NAME}-${HASH}/${LIBDIR}/${ARCHDIR}/
                done
            done
            ;;
        esac

        rmdir ../petbuild-output/${NAME}-${HASH}/usr/share/* 2>/dev/null
        rmdir ../petbuild-output/${NAME}-${HASH}/usr/* 2>/dev/null
        rmdir ../petbuild-output/${NAME}-${HASH}/* 2>/dev/null

        find ../petbuild-output/${NAME}-${HASH} -type l | while read LINK; do
            [ "`readlink $LINK`" = "/bin/busybox" ] && rm -f $LINK
        done

        find ../petbuild-output/${NAME}-${HASH} -type f | while read ELF; do
            strip --strip-all -R .note -R .comment ${ELF} 2>/dev/null
        done

        for EXTRAFILE in ../rootfs-petbuilds/${NAME}/*; do
            case "${EXTRAFILE##*/}" in
            petbuild|pinstall.sh|pet.specs|*.patch|sha256.sum|*-*|DOTconfig|*.c) ;;
            *) cp -a $EXTRAFILE ../petbuild-output/${NAME}-${HASH}/
            esac
        done
    fi

    rm -f ../petbuild-output/${NAME}-latest
    ln -s ${NAME}-${HASH} ../petbuild-output/${NAME}-latest

    PKGS="$PKGS $NAME"
done

[ $HAVE_ROOTFS -eq 1 ] && rm -rf petbuild-rootfs-complete

for NAME in $PKGS; do
    echo "Copying ${NAME}"

    cp -a ../petbuild-output/${NAME}-latest/* rootfs-complete/

    if [ -f ../rootfs-petbuilds/${NAME}/pinstall.sh ]; then
        echo >> /tmp/rootfs_pkgs_pinstall.sh
        cat ../rootfs-petbuilds/${NAME}/pinstall.sh >> /tmp/rootfs_pkgs_pinstall.sh
        echo >> /tmp/rootfs_pkgs_pinstall.sh
    fi

    cat ../rootfs-petbuilds/${NAME}/pet.specs >> /tmp/rootfs-petbuilds.specs
done