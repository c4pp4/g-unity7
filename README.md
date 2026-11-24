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

An Ubuntu security update of a package that G Unity⁷ changes arrives with its
rebuild in the PPA. unattended-upgrades installs the updates of the PPA
automatically, like the Ubuntu security updates.

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
installed, so `apt autoremove` never removes them. It also removes
packages of the Ubuntu Unity image that G Unity⁷ does not use: Fcitx 4, which
the installer leaves from the live system, with the KDE Frameworks it pulls in
(G Unity⁷ uses IBus), Kvantum, the Qt style of the installer, GParted (GNOME
Disks does the basic tasks) and the libraries of the installer. It removes the
mount units of snap revisions that are not installed, which fail at every
boot, and the configuration files of PulseAudio, which PipeWire replaces
and whose autostart file remains. Other desktops, such as GNOME, are not
removed. `g-unity7-cleanup` shows all changes and asks
before making them. `g-unity7-cleanup --dry-run` only shows them. To keep a
package that it would remove, run `sudo g-unity7-cleanup --keep <package>`.

Ubuntu installs Firefox and Thunderbird as snaps. `g-unity7-cleanup` offers the
PPA packages with Unity's global menu instead, built from the Debian sources. It
copies the snap profiles without replacing existing ones, installs the
language packages of the system's languages and removes the snaps. It does not
offer a package older than the snap, because Firefox and Thunderbird do not
open a profile that a newer version used. If you keep the snaps,
`g-unity7-apt-pin` keeps them too. If the snap is not installed,
`g-unity7-cleanup` offers the PPA package as well. A Firefox or Thunderbird
package from another source, such as Mozilla's APT repository, stays.

Finally, restart the computer:

```
sudo reboot
```

The running session still uses the old versions of Unity, Compiz and GTK 3.
The login screen and services such as PipeWire, which replaces PulseAudio on
Ubuntu Unity, start with the new packages only after a restart.

### Going back to Ubuntu

`ppa-purge` reinstalls the Ubuntu versions of the packages from the PPA and
removes the packages that only the PPA has, such as `g-unity7-desktop`:

```
sudo apt install ppa-purge
sudo ppa-purge ppa:c4pp4/g-unity7
```

Firefox and Thunderbird go back to the Ubuntu packages, which install the
snaps. The files that only the G Unity⁷ packages have in `/etc`, such as their
X session scripts, go with them. The configuration files of `g-unity7-apt-pin`
stay until `sudo apt purge g-unity7-apt-pin`; without the PPA, they change
nothing.

`ppa-purge` does not reinstall the packages that `g-unity7-cleanup` removed. On
Ubuntu Unity, reinstall them with its task, then restart:

```
sudo apt install ubuntu-unity-desktop
sudo reboot
```

Before upgrading to the next Ubuntu release, go back to Ubuntu with `ppa-purge`
until the PPA has packages for that release. The upgrade disables the PPA but
keeps its packages, and many of them have the same or a higher version than the
packages of the new release.

## Layout

```
config.sh                 series, PPAs, version tag
packages/<package>/
  package.sh              the port (see below)
  patches/                Ubuntu variants of overlay patches (a file with the same name wins;
                          the approval issue reports changes of the overlay patch)
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
- `OVERLAY_FOLLOW` lists other overlay packages whose ebuild changes the
  approval issue reports for the package, such as the indicator and lens
  metapackages for `g-unity7-meta`.
- `SOURCE_NAME` builds a source package derived from `UBUNTU_SRC` under another
  name, such as nemo-engrampa from nemo-fileroller.
- `HOLD` stops building the package and keeps its latest version in the
  staging PPA. Its value says why, such as an overlay patch that does not
  apply to a new version yet.
- `UBUNTU_SERIES` takes the source from an older Ubuntu release when Ubuntu
  has removed it. `DSC_SHA256` is then the SHA256 of its `.dsc`.
- `DEBIAN_REPLACES` lists the files of `packages/<package>/debian/` that
  replace a file of the Ubuntu source, such as the Qt 6 `debian/control` of
  dee-qt6. Another file of the port that would replace one of the source stops
  the build, so that a file that Ubuntu adds later is not lost unnoticed.
- `DEBIAN_SUITE` takes the source from Debian (`sid`, `experimental`, or both
  separated by a space) instead of the Ubuntu archive, such as Firefox from sid
  and Thunderbird from experimental. The `.dsc` must also have a valid
  signature of a Debian developer.

apt downloads the sources from the Ubuntu or Debian archive with its archive
key, which signs the checksums of every file. The older series of
`UBUNTU_SERIES` are signed only with keys that apt no longer accepts, so their
sources come from Launchpad over HTTPS. The build checks their `.dsc` against
`DSC_SHA256` and the files against the `.dsc`. The changelog records where the
source comes from, the SHA256 of its `.dsc` and, for Debian, the signer. A
build from uncommitted changes says `-dirty` after the commit, and
`upload.sh` refuses it.

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

`<Ubuntu version><mark>+gu7.<N>~<series version>`, for example
`6.6.4-1a+gu7.1~26.10` and `7.7.1+26.04.20260306-0ubuntu3+gu7.7~26.10`. `N`
increases when the patches change for the same Ubuntu version. It counts across
the series, so that the version for a newer series with the same Ubuntu version
is higher.

dpkg sorts letters before `+`. Without the mark, a version built on an Ubuntu
update such as `6.6.4-1ubuntu0.1` would be lower than the one built on
`6.6.4-1`, and Launchpad would refuse it. The mark is `a` after a digit, `0`
after a letter (`26.10.2ubuntu0+gu7.1`), and nothing after an ubuntu or build
revision (`0ubuntu3`), whose updates add `.1`. Own packages, Firefox and
Thunderbird (built from Debian) and the sources of an older series have no
mark.

The changelog entry lists the patches with their hashes, the fingerprint of the
whole change, which decides whether a new version is needed, and the Ubuntu or
Debian version (`G-Unity7-Base`).

## Uploading and promoting

Nothing reaches users without the owner's approval:

1. `ppa.yml` (twice a day) builds the changed packages. A version with the
   same fingerprint as in the staging PPA (a new Ubuntu revision) is uploaded to
   `ppa:c4pp4/g-unity7-staging` right away. Any other version waits for review
   in the approval issue: `/upload` or `/reject`. With the repository variable
   `STAGING_FROZEN` (any value, such as the reason), every version waits for
   review, for example while staging is tested before a promotion. Then
   `ppa.yml` checks that `g-unity7-desktop` installs from staging as intended.
2. `review.yml` (a few times a day) lists the staging versions that are newer
   than in `ppa:c4pp4/g-unity7`, with their build state. `/promote` copies them
   with their binaries, and `/promote --dry-run` only shows what it would copy.
   Packages of the same `GROUP` are promoted only together, the `desktop` group
   before the `mozilla` group, whose packages need it. A group is incomplete
   while a member waits for review, failed its last build, or is in neither
   PPA; `--force` promotes it anyway. `/retry` retries failed builds.
   `/upload` and `/promote` take only the versions that the issue showed before
   the command.
3. `g-unity7-apt-pin` keeps the PPA versions on users' systems until a newer
   version is promoted.

The approval issue also lists the packages whose build failed, those that
`ppa.yml` could not check (a Launchpad error stops only that package), those
that are behind Ubuntu or Debian for more than a day, the Mozilla releases that
Debian has not packaged after three days, and the overlay changes that the
ports may need, which `/ported` records as checked. A comment announces each
new item.

If a broken version reaches the main PPA, fix it forward: Launchpad cannot
bring back an older version. Revert the change in the port or the overlay, let
`ppa.yml` build the next version, upload it with `/upload`, test it and promote
it. To stop the broken version from reaching more users meanwhile, delete it
from the main PPA on Launchpad; the systems that have it keep it until the
fixed version arrives.

`pr.yml` checks on every push that the patches of the changed packages still
apply, those of all packages when the scripts change, and every week.

A local upload signs with the gpg-agent outside the container:

```sh
scripts/run-local.sh --gpg scripts/upload.sh libunity
```

## GitHub setup

- The `approve` label. The approval issue is found by this label.
- The `launchpad` environment for the uploads (`ppa.yml` and `/upload`), with
  deployment branches limited to `master`:
  - secrets `GPG_PRIVATE_KEY` (only the signing subkey:
    `gpg --armor --export-secret-subkeys <subkey>!`) and `GPG_PASSPHRASE`
  - variables `DEBEMAIL`, `DEBFULLNAME` and `GPG_KEY_ID`
- The `launchpad-api` environment for `/promote` and `/retry`, with deployment
  branches limited to `master`: secret `LP_CREDENTIALS` (a launchpadlib
  credentials file created by `scripts/lp_login.py`). With required reviewers,
  these commands also wait for a confirmation on GitHub.
- Repository variables `DEBEMAIL` and `DEBFULLNAME` for the build jobs, and
  `STAGING_FROZEN` while staging is frozen.
- Actions limited to those of GitHub, with SHA pinning required, and a ruleset
  for `master` that blocks force pushes and deletion.
