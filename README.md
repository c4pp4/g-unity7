# G Unity⁷ Desktop

Ubuntu packages of the Unity7 desktop with the patches of the
[gentoo-unity7](https://github.com/c4pp4/gentoo-unity7) overlay, built for the
`ppa:c4pp4/g-unity7` PPA.

Each package is the newest Ubuntu source with:

- the patches the overlay ebuild applies (from the overlay `files/` directory),
- the edits the ebuild makes with `sed` and other commands, as one more patch,
- the `debian/` changes the port needs,

leaving out what only concerns Gentoo (libdir, OpenRC, the portage sandbox, …).
The patches are taken from the overlay at build time, so a patch changed in the
overlay gets into the next package version by itself.

## Installing

On Ubuntu 26.10 (Ubuntu Unity or any other flavour):

```
sudo add-apt-repository ppa:c4pp4/g-unity7
sudo apt install g-unity7-desktop
```

`g-unity7-desktop` installs `g-unity7-apt-pin`, which prefers the packages of
the PPA to those of Ubuntu.

Then run:

```
sudo g-unity7-cleanup
```

It works as `emerge --depclean` of Gentoo. apt keeps the applications already
installed and every installed alternative of a relation such as
`vlc | showtime`, and it does not install the first alternative if another one
is installed (Atril of `atril | papers | evince` with Papers). Of the installed
alternatives of an application of `g-unity7-desktop` `g-unity7-cleanup` asks
which one to keep, the first one is recommended and offered for installation,
an alternative that is not installed can be installed too.

Coming from Ubuntu Unity, it also removes the packages G Unity⁷ replaces: the
installer of Ubuntu Unity marks its applications as manually installed, so
`apt autoremove` never removes them. Other desktops, such as GNOME, are not
removed. It shows all packages and asks first, `g-unity7-cleanup --dry-run`
changes nothing.

## Layout

```
config.sh                 series, PPAs, version tag
packages/<package>/
  package.sh              the port (see below)
  patches/                Ubuntu variants of overlay patches (same name wins)
  debian/                 files copied over debian/
scripts/
  build-source.sh         build the source package of one package
  make-review.sh          debdiff.diff, code.diff and summary.md of a build
  test-build.sh           local binary build of a built source package
  run-local.sh            run a script in the Ubuntu build container
  plan.sh                 packages whose Ubuntu version or input changed
  upload.sh               sign a source package and upload it to staging
  approve.py              the approval issue and its commands
  lp.py                   Launchpad queries (versions, build states)
  lp_write.py             Launchpad changes (copy to the main PPA, retry)
  lp_login.py             Launchpad credentials of lp_write.py (public write only)
  dep3.py                 overlay patch header → DEP-3 header
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

# debian/ changes, run before the Ubuntu patchset is applied #
debian_edit() {
	sed -i -e "s/unity-gtk-module/appmenu-gtk-module/" debian/control || return 1
	grep -Fq "appmenu-gtk-module" debian/control || return 1
}

# Source edits of the ebuild, saved as debian/patches/g-unity7/ebuild-edits.patch #
src_edit() {
	sed -i -e "/preview_width =/{s/770/700/}" unity-shared/PreviewStyle.cpp || return 1
	grep -Fq "const RawPixel preview_width = 700_em;" unity-shared/PreviewStyle.cpp || return 1
}
```

`FILESDIR` (the overlay `files/` directory) and `BRANDING_DIR` can be used in
the functions. Optional: `PATCH_MODE=quilt|direct` overrides the mode chosen from
`debian/source/format`, `GROUP` names packages promoted together,
`OVERLAY_FILES` lists further overlay files the package is made from (they are
part of its input hash), `SOURCE_NAME` makes a derived source package of
`UBUNTU_SRC` under another name (e.g. nemo-engrampa from nemo-fileroller). Own packages may set `local_prepare()` to make their
source from overlay files.

## Building locally

Rootless podman is enough, the container image is built on the first run.

```sh
scripts/run-local.sh scripts/build-source.sh libunity
scripts/run-local.sh --root scripts/test-build.sh libunity
```

`OVERLAY_DIR` points to the overlay checkout (default `../gentoo-unity7`). The
result is in `build/<series>/<package>/`: `out/` holds the source package,
`review/` the review and `result.env` the version and fingerprint.

## Versions

`<Ubuntu version>+gu7.<N>~<series version>`, e.g.
`7.1.4+19.04.20190319-8+gu7.1~26.10`. `N` grows when the patches change on the
same Ubuntu version. The changelog entry lists the patches with their hashes
and the fingerprint of the whole change, which decides whether a new version
is needed.

## Uploading and promoting

Nothing gets to the users without the owner's approval:

1. `ppa.yml` (daily) builds the changed packages. A version with the same
   fingerprint as the staging PPA (a new Ubuntu revision) is uploaded to
   `ppa:c4pp4/g-unity7-staging` right away, any other version waits in the
   approval issue for review: `/upload` or `/reject`.
2. `review.yml` (hourly) lists the versions of staging newer than in
   `ppa:c4pp4/g-unity7` with their build state. `/promote` copies them with
   their binaries, packages of one `GROUP` only together; `/retry` retries
   failed builds.
3. The users' apt keeps the PPA versions (`g-unity7-apt-pin`) until a newer
   version is promoted.

`pr.yml` checks on every push that all patches still apply.

A local upload signs with the gpg-agent outside the container:

```sh
scripts/run-local.sh --gpg scripts/upload.sh libunity
```

## GitHub setup

- Label `approve` (the approval issue is found by it).
- Environment `launchpad`, deployment branches limited to `master`:
  - secrets `GPG_PRIVATE_KEY` (only the signing subkey:
    `gpg --armor --export-secret-subkeys <subkey>!`), `GPG_PASSPHRASE`,
    `LP_CREDENTIALS` (launchpadlib credentials file made by `scripts/lp_login.py`)
  - variables `DEBEMAIL`, `DEBFULLNAME`, `GPG_KEY_ID`
- Repository variables `DEBEMAIL` and `DEBFULLNAME` for the build jobs.
