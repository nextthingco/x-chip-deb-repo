# TIC-80 packaging (overlay)

Builds TIC-80 from source as the `tic80` armhf .deb, linked against the **system
SDL2 + mesa GLES2/EGL** (SDLGPU) so it runs on the CHIP's Mali400/lima GPU.
Upstream's prebuilt `rpi.deb` links the **Broadcom** GLES blobs (`/opt/vc`,
`libbrcmEGL`/`libbrcmGLESv2`) and does NOT run on the CHIP -- verified.

## How this is wired (overlay, no fork)

`packages/tic80` is a **pristine** `nesbox/TIC-80` submodule. This `debian/` lives
here in x-chip-deb-repo, NOT in the submodule. At build time `build.sh` copies it
into the submodule root before `dpkg-buildpackage`, then `git clean`s it back out.
So we bump TIC-80 by moving the submodule pointer to a new tag, and bump the
packaging by editing this dir -- the two are independent. (The dcache key folds in
a hash of this `debian/`, so editing it rebuilds even if the submodule sha is
unchanged.)

Generic mechanism: any `packaging/<pkg>/debian/` overlays onto a pristine
`packages/<pkg>` submodule the same way.

## One-time setup

```sh
cd x-chip-deb-repo
git submodule add https://github.com/nesbox/TIC-80 packages/tic80
git -C packages/tic80 checkout v1.1.2837      # the tag this debian/ targets
git -C packages/tic80 submodule update --init --recursive
git add .gitmodules packages/tic80
```

`build.sh` USERSPACE already lists `tic80`. Push -> CI builds it -> reprepro ->
apt. THEN add `tic80` to x-chip-os/pocketchip/config/package-lists/
pocketchip.list.chroot (adding it before the deb is published would fail the
rootfs build on a missing package).

## Bumping TIC-80 later

```sh
git -C packages/tic80 fetch --tags
git -C packages/tic80 checkout <newtag>
git -C packages/tic80 submodule update --init --recursive
git add packages/tic80
# bump debian/changelog here to <newtag>-1, commit, push
```

## Notes / likely first-build iteration

* `debian/control` Build-Depends is a best guess for the SDL+GLES2 path plus
  `BUILD_WITH_ALL` (ruby+rake for mruby). New-upstream debianization usually
  needs a tweak or two -- watch the first CI log and add whatever `apt-get
  build-dep` / cmake reports missing.
* `-Ofast` enables `-ffast-math`; if TIC-80 audio/timing misbehaves, drop
  `debian/rules` to `-O3`.
* pocket-home's launcher already points "Play" at `tic80` (with a tic80 icon).
