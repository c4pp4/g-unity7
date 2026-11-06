# G Unity⁷ build configuration, sourced by the scripts.

## Ubuntu series to build for (Launchpad series names).
SERIES=( stonking )

## Ubuntu version numbers of the series, appended to package versions (~26.10).
declare -A SERIES_VERSION=(
	[stonking]=26.10
)

## The gentoo-unity7 commit (or tag) that each series is built from. Empty
##  means master. Set it when the overlay moves its stable release to the next
##  series.
declare -A OVERLAY_REF=(
	[stonking]=
)

## Launchpad PPAs (owner/name).
PPA_STAGING="c4pp4/g-unity7-staging"
PPA_MAIN="c4pp4/g-unity7"

## Version tag: <ubuntu version>+gu7.<N>~<series version>.
VERSION_TAG="gu7"

## Bump it when a script change alters the generated source packages. It is
##  part of the fingerprint, so all packages are rebuilt.
FORMAT_VERSION=1

## Repositories for the Origin links in patch headers.
OVERLAY_URL="https://github.com/c4pp4/gentoo-unity7"
G_UNITY7_URL="https://github.com/c4pp4/g-unity7"

## Changelog and patch author. The email address must belong to the Launchpad account.
DEBFULLNAME="${DEBFULLNAME:-c4pp4}"
DEBEMAIL="${DEBEMAIL:-$(git config user.email 2>/dev/null || true)}"

## Fingerprint of the OpenPGP key that signs the uploads, registered on Launchpad.
GPG_KEY_ID="${GPG_KEY_ID:-6D44971D1E0C2A5CEB43FF9FFDB90412F9ABE974}"
