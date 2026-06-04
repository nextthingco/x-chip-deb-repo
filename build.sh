#!/bin/bash -ex

# Build every package from the submodules under packages/ and collect their
# .debs into ./debs (for reprepro). Run on a host with docker -- the CI runner
# or locally. Needs the submodules checked out (git submodule update --init).
#
# Caching: each package's built .debs are cached under dcache/<pkg>/<submodule-sha>/.
# A package is only rebuilt when its submodule pointer (HEAD sha) changes;
# otherwise the cached .debs are reused. dcache/ is what CI persists via
# actions/cache, so an unchanged package -- i.e. a version already built and
# uploaded on a prior run -- is never rebuilt. Each rebuild prunes the package's
# older sha slots, so the cache only holds the current debs.
#
# Build split: the kernel uses its OWN amd64 cross-compile image+Makefile (fast);
# the simple userspace packages share one native-armhf image
# (Dockerfile.userspace), pulling Build-Depends from their debian/control.

HERE=$(cd "$(dirname "$0")" && pwd); cd "$HERE"

DEBS="$HERE/debs";     rm -rf "$DEBS"; mkdir -p "$DEBS"
DCACHE="$HERE/dcache"; mkdir -p "$DCACHE"

# Userspace submodules (kebab-case dirs). Missing ones are skipped, so this can
# name repos that aren't wired up yet.
USERSPACE="chip-power chip-hwtest chip-dt-overlays"

USERSPACE_IMAGE_BUILT=

# $1 = package dir name under packages/ ; $2 = "kernel" | "userspace"
build_pkg() {
    local pkg="$1" kind="$2" sha slot
    [ -d "packages/$pkg" ] || { echo ">> skip $pkg (submodule not present)"; return; }

    sha=$(git -C "packages/$pkg" rev-parse HEAD)
    slot="$DCACHE/$pkg/$sha"

    if ls "$slot"/*.deb >/dev/null 2>&1; then
        echo ">> $pkg @ ${sha:0:12}: cache hit -- not rebuilding"
    else
        echo ">> $pkg @ ${sha:0:12}: building"
        rm -rf "$DCACHE/$pkg"            # drop this package's stale sha slot(s)
        mkdir -p "$slot"
        if [ "$kind" = kernel ]; then
            make -C "packages/$pkg"
            # publish everything except the heavy debug-symbol packages
            for f in "packages/$pkg"/build/*.deb; do
                case "$f" in *dbg*) continue ;; esac
                cp "$f" "$slot/"
            done
        else
            # Locate the Debian source within the submodule -- some repos nest it
            # below the root (e.g. chip-power/chip-power/debian/). src = the dir
            # containing debian/; out = its parent, where dpkg-buildpackage drops
            # the .debs.
            local control src out
            control=$(find "packages/$pkg" -path '*/debian/control' -not -path '*/.git/*' | head -1)
            [ -n "$control" ] || { echo "ERROR: no debian/control under packages/$pkg" >&2; exit 1; }
            src=$(dirname "$(dirname "$control")")
            out=$(dirname "$src")

            if [ -z "$USERSPACE_IMAGE_BUILT" ]; then
                docker build --platform linux/arm/v7 -t chip-userspace-armhf -f Dockerfile.userspace .
                USERSPACE_IMAGE_BUILT=1
            fi
            docker run --rm --platform linux/arm/v7 \
                -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
                -v "$PWD:/work" -w "/work/$src" \
                chip-userspace-armhf bash -euxc '
                    apt-get update
                    apt-get build-dep -y ./
                    # -b: build all binaries (arch-dep AND arch:all) -- userspace
                    # packages may be Architecture: all (e.g. chip-power), which
                    # -B would skip.
                    dpkg-buildpackage -b -uc -us
                    # hand back just the source dir + the artifacts in its parent
                    # (avoid recursively chowning all of packages/).
                    chown -R "$HOST_UID:$HOST_GID" .
                    chown "$HOST_UID:$HOST_GID" ../*.deb ../*.buildinfo ../*.changes 2>/dev/null || true
                '
            for f in "$out"/*.deb; do cp "$f" "$slot/"; done
            rm -f "$out"/*.deb "$out"/*.buildinfo "$out"/*.changes "$out"/*.dsc "$out"/*.tar.* 2>/dev/null || true
        fi
    fi

    cp "$slot"/*.deb "$DEBS/"
}

build_pkg x-chip-linux-deb kernel
for pkg in $USERSPACE; do
    build_pkg "$pkg" userspace
done

echo ">> collected debs:"; ls -l "$DEBS"
