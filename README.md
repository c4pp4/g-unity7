# G Unity⁷ Desktop

Ubuntu packages of the Unity7 desktop with the patches from the
[gentoo-unity7](https://github.com/c4pp4/gentoo-unity7) overlay, built for the
`ppa:c4pp4/g-unity7` PPA.

Each package is the latest Ubuntu source with:

- the patches that the overlay ebuild applies (from the overlay's `files/`
  directory),
- the edits that the ebuild makes with `sed` and other commands, as one more
  patch,
- the `debian/` changes that the port needs.

Changes that only matter on Gentoo (libdir, OpenRC, the Portage sandbox, …) are
left out. The patches are taken from the overlay at build time, so a patch
changed in the overlay is included in the next package version automatically.

## Installing

On Ubuntu 26.10 (Ubuntu Unity or any other flavor):

```
sudo add-apt-repository ppa:c4pp4/g-unity7
sudo apt install g-unity7-desktop
sudo apt full-upgrade
```

`g-unity7-desktop` installs `g-unity7-apt-pin`, which makes apt prefer the PPA
packages to the Ubuntu ones. `apt install` only upgrades the packages that
`g-unity7-desktop` needs. `apt full-upgrade` upgrades the other installed
packages that G Unity⁷ changes, such as Compiz and GTK 3.

Then run:

```
sudo g-unity7-cleanup
```

It works like Gentoo's `emerge --depclean`. apt keeps the applications that are
already installed and every installed alternative of a relation such as
`vlc | showtime`. It also does not install the first alternative when another
one is installed, for example Atril from `atril | papers | evince` when Papers
is installed. For each `g-unity7-desktop` application with several installed
alternatives, `g-unity7-cleanup` asks which one to keep. The first alternative
is recommended and offered for installation, and you can also install another
one.

If you are coming from Ubuntu Unity, it also removes the packages that G Unity⁷
replaces. The Ubuntu Unity installer marks its applications as manually
installed, so `apt autoremove` never removes them. Other desktops, such as
GNOME, are not removed. `g-unity7-cleanup` shows all changes and asks before
making them. `g-unity7-cleanup --dry-run` only shows them.

Ubuntu installs Firefox and Thunderbird as snaps. `g-unity7-cleanup` offers the
PPA packages with Unity's global menu instead, built from the Debian sources. It
copies the snap profiles for users who have no profile yet, installs the
language packages of the system's languages and removes the snaps. It does not
offer a package older than the snap, because Firefox and Thunderbird do not
open a profile that a newer version used. If you keep the snaps,
`g-unity7-apt-pin` keeps them too.

## Layout

```
config.sh                 series, PPAs, version tag
packages/<package>/
  package.sh              the port (see below)
  patches/                Ubuntu variants of overlay patches (a file with the same name wins)
  debian/                 files copied over debian/
scripts/
  build-source.sh         build the source package of one package
  make-review.sh          create debdiff.diff, code.diff and summary.md for a build
  test-build.sh           build binary packages locally from a source package
  run-local.sh            run a script in the Ubuntu build container
  plan.sh                 list packages whose Ubuntu version or input changed
  upload.sh               sign a source package and upload it to staging
  approve.py              manage the approval issue and its commands
  lp.py                   query Launchpad (versions, build states)
  lp_write.py             change Launchpad (copy to the main PPA, retry builds)
  lp_login.py             create Launchpad credentials for lp_write.py (public write access only)
  dep3.py                 convert an overlay patch header to a DEP-3 header
local/<package>/          own packages (package.sh and the whole source)
Containerfile             the build container (Ubuntu of the series)
```

## Ports: `packages/<package>/package.sh`

```bash
OVERLAY_PKG="unity-base/unity"     # ebuild directory in the overlay (or ehooks/<cat>/<pkg>)
UBUNTU_SRC="unity"                 # Ubuntu source package

# Patches from ${OVERLAY_PKG}/files, applied in this order #
PATCHES=(
	fix-dash-preview-thumbnails.patch
)

# debian/ changes, made before the Ubuntu patches are applied #
debian_edit() {
	sed -i -e "s/unity-gtk-module/appmenu-gtk-module/" debian/control || return 1
	grep -Fq "appmenu-gtk-module" debian/control || return 1
}

# Source edits from the ebuild, saved as debian/patches/g-unity7/ebuild-edits.patch #
src_edit() {
	sed -i -e "/preview_width =/{s/770/700/}" unity-shared/PreviewStyle.cpp || return 1
	grep -Fq "const RawPixel preview_width = 700_em;" unity-shared/PreviewStyle.cpp || return 1
}
```

The functions can use `FILESDIR` (the overlay's `files/` directory) and
`BRANDING_DIR`.

For `ehooks/<cat>/<pkg>[:<slot>]`, the build picks the ehooks directory for the
base version the way the overlay does: `firefox-160:rapid` or `firefox-160`
for Firefox 160 if it exists, `firefox:rapid` otherwise. The versioned
directories are part of the input hash.

Optional settings:

- `PATCH_MODE=quilt|direct` overrides the mode chosen from
  `debian/source/format`.
- `GROUP` names packages that are promoted together.
- `OVERLAY_FILES` lists other overlay files the package is made from. They are
  part of its input hash.
- `SOURCE_NAME` builds a source package derived from `UBUNTU_SRC` under another
  name, such as nemo-engrampa from nemo-fileroller.
- `HOLD` stops building the package and keeps its latest version in the
  staging PPA. Its value says why, such as an overlay patch that does not
  apply to a new version yet.
- `UBUNTU_SERIES` takes the source from an older Ubuntu release when Ubuntu
  has removed it.
- `DEBIAN_SUITE` takes the source from Debian (`sid`, `experimental`, or both
  separated by a space) instead of the Ubuntu archive, such as Firefox from sid
  and Thunderbird from experimental. The `.dsc` must also have a valid
  signature of a Debian developer.

apt downloads the sources from the Ubuntu or Debian archive with its archive
key, which signs the checksums of every file. The older series of
`UBUNTU_SERIES` are signed only with keys that apt no longer accepts, so their
sources come from Launchpad over HTTPS. The changelog records where the source
comes from, the SHA256 of its `.dsc` and, for Debian, the signer.

Own packages can set `local_prepare()` to create their source from overlay
files.

## Building locally

Rootless podman is enough. The container image is built on the first run.

```sh
scripts/run-local.sh scripts/build-source.sh libunity
scripts/run-local.sh --root scripts/test-build.sh libunity
```

`OVERLAY_DIR` points to the overlay checkout (default: `../gentoo-unity7`).
The result is in `build/<series>/<package>/`: `out/` holds the source package,
`review/` the review, and `result.env` the version and fingerprint. The
unpacked source trees are removed when the build succeeds and kept when it
fails. While they exist, Firefox and Thunderbird need about 17 GB.

To build on another disk, set `BUILD_DIR` or make `build` a symlink;
`run-local.sh` mounts either one in the container.

## Versions

`<Ubuntu version>+gu7.<N>~<series version>`, for example
`7.1.4+19.04.20190319-8+gu7.1~26.10`. `N` increases when the patches change
for the same Ubuntu version. The changelog entry lists the patches with their
hashes and the fingerprint of the whole change, which decides whether a new
version is needed.

## Uploading and promoting

Nothing reaches users without the owner's approval:

1. `ppa.yml` (daily) builds the changed packages. A version with the same
   fingerprint as in the staging PPA (a new Ubuntu revision) is uploaded to
   `ppa:c4pp4/g-unity7-staging` right away. Any other version waits for review
   in the approval issue: `/upload` or `/reject`.
2. `review.yml` (hourly) lists the staging versions that are newer than in
   `ppa:c4pp4/g-unity7`, with their build state. `/promote` copies them with
   their binaries. Packages of the same `GROUP` are promoted only together.
   `/retry` retries failed builds.
3. `g-unity7-apt-pin` keeps the PPA versions on users' systems until a newer
   version is promoted.

`pr.yml` checks on every push that all patches still apply.

A local upload signs with the gpg-agent outside the container:

```sh
scripts/run-local.sh --gpg scripts/upload.sh libunity
```

## GitHub setup

- The `approve` label. The approval issue is found by this label.
- The `launchpad` environment, with deployment branches limited to `master`:
  - secrets `GPG_PRIVATE_KEY` (only the signing subkey:
    `gpg --armor --export-secret-subkeys <subkey>!`), `GPG_PASSPHRASE` and
    `LP_CREDENTIALS` (a launchpadlib credentials file created by
    `scripts/lp_login.py`)
  - variables `DEBEMAIL`, `DEBFULLNAME` and `GPG_KEY_ID`
- Repository variables `DEBEMAIL` and `DEBFULLNAME` for the build jobs.
