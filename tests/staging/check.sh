#!/bin/bash
## Check that g-unity7-desktop installs from the staging PPA as intended, with
##  the apt simulation in an Ubuntu container of the series (as root): apt can
##  install it with the pins of g-unity7-apt-pin, it does not pull in
##  PulseAudio or build tools, and the packages that staging has come in their
##  G Unity⁷ version. Firefox and Thunderbird stay the Ubuntu packages until
##  g-unity7-cleanup installs the G Unity⁷ ones.
##
##    podman run --rm -v "$PWD":/work:ro,Z docker.io/library/ubuntu:26.10 \
##      /work/tests/staging/check.sh

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
work=$(cd "$(dirname "$0")"/../.. && pwd)
# shellcheck source=../../config.sh
source "${work}"/config.sh
series=${SERIES[0]}
owner=${PPA_STAGING%/*} name=${PPA_STAGING#*/}
## Packages that g-unity7-desktop must not install
forbidden=( pulseaudio lintian build-essential gdebi )

## Only a simulation, so the PPA is not checked against its key
echo "deb [trusted=yes] https://ppa.launchpadcontent.net/${owner}/${name}/ubuntu ${series} main" \
	> /etc/apt/sources.list.d/g-unity7-staging.list
## The pins of g-unity7-apt-pin for the staging PPA
sed "s/o=LP-PPA-c4pp4-g-unity7\$/o=LP-PPA-${owner}-${name}/" "${work}"/local/g-unity7-apt-pin/g-unity7.pref \
	> /etc/apt/preferences.d/g-unity7-staging.pref
grep -q "o=LP-PPA-${owner}-${name}\$" /etc/apt/preferences.d/g-unity7-staging.pref \
	|| { echo "check.sh: the pin for the staging PPA is missing" >&2; exit 1; }
for i in 1 2 3; do
	apt-get update -qq && break
	[[ ${i} -lt 3 ]] || exit 1
	sleep 60
done

if ! simulation=$(apt-get -s install g-unity7-desktop 2>&1); then
	echo "${simulation}"
	echo "check.sh: apt cannot install g-unity7-desktop from ppa:${PPA_STAGING}" >&2
	exit 1
fi

problems=()
for package in "${forbidden[@]}"; do
	grep -q "^Inst ${package} " <<< "${simulation}" && problems+=( "it installs ${package}" )
done
## The binary packages that staging has, except Firefox and Thunderbird. apt
##  keeps the package lists compressed.
declare -A staging=()
while read -r package; do
	staging[${package}]=1
done < <(for list in /var/lib/apt/lists/*"${owner}_${name}"*_Packages*; do
		[[ -f ${list} ]] && /usr/lib/apt/apt-helper cat-file "${list}"
	done | sed -n 's/^Package: //p' | grep -v -E '^(firefox|thunderbird)(-l10n-.*)?$' | sort -u)
[[ ${#staging[@]} -gt 0 ]] || problems+=( "the package list of ppa:${PPA_STAGING} is empty" )
## "Inst <package> (<version> <release> [<arch>])"
count=0
while read -r package version; do
	[[ -n ${staging[${package}]:-} ]] || continue
	count=$(( count + 1 ))
	[[ ${version} == *"+${VERSION_TAG}."* ]] || problems+=( "it installs ${package} ${version} instead of the G Unity⁷ version" )
done < <(awk '/^Inst / { v = ($3 ~ /^\[/) ? $4 : $3; gsub(/[()]/, "", v); print $2, v }' <<< "${simulation}")

if [[ ${#problems[@]} -gt 0 ]]; then
	printf 'check.sh: %s\n' "${problems[@]}" >&2
	exit 1
fi
echo "g-unity7-desktop installs from ppa:${PPA_STAGING}: $(grep -c '^Inst ' <<< "${simulation}") packages, ${count} of them from staging in their G Unity⁷ version."
