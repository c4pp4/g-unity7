#!/bin/bash
## Check that g-unity7-desktop installs from the staging PPA (or the main PPA)
##  as intended, with the apt simulation in an Ubuntu container of the series
##  (as root): apt can install it with the pins of g-unity7-apt-pin, it does not
##  pull in PulseAudio or build tools, and the packages that the PPA has come in
##  their G Unity⁷ version. Firefox and Thunderbird stay the Ubuntu packages
##  until g-unity7-cleanup installs the G Unity⁷ ones. The main PPA is checked
##  once it has g-unity7-desktop.
##
##    podman run --rm -v "$PWD":/work:ro,Z docker.io/library/ubuntu:26.10 \
##      /work/tests/staging/check.sh [staging|main]

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
work=$(cd "$(dirname "$0")"/../.. && pwd)
# shellcheck source=../../config.sh
source "${work}"/config.sh
series=${SERIES[0]}
which=${1:-staging}
case ${which} in
	staging) ppa=${PPA_STAGING} ;;
	main) ppa=${PPA_MAIN} ;;
	*) echo "usage: check.sh [staging|main]" >&2; exit 2 ;;
esac
owner=${ppa%/*} name=${ppa#*/}
## Packages that g-unity7-desktop must not install
forbidden=( pulseaudio lintian build-essential gdebi )

## Only a simulation, so the PPA is not checked against its key
echo "deb [trusted=yes] https://ppa.launchpadcontent.net/${owner}/${name}/ubuntu ${series} main" \
	> /etc/apt/sources.list.d/g-unity7-check.list
## The pins of g-unity7-apt-pin for the PPA
sed "s/o=LP-PPA-c4pp4-g-unity7\$/o=LP-PPA-${owner}-${name}/" "${work}"/local/g-unity7-apt-pin/g-unity7.pref \
	> /etc/apt/preferences.d/g-unity7-check.pref
grep -q "o=LP-PPA-${owner}-${name}\$" /etc/apt/preferences.d/g-unity7-check.pref \
	|| { echo "check.sh: the pin for ppa:${ppa} is missing" >&2; exit 1; }
for i in 1 2 3; do
	apt-get update -qq && break
	[[ ${i} -lt 3 ]] || exit 1
	sleep 60
done

## The binary packages that the PPA has. apt keeps the package lists compressed.
declare -A in_ppa=()
while read -r package; do
	in_ppa[${package}]=1
done < <(for list in /var/lib/apt/lists/*"${owner}_${name}"*_Packages*; do
		[[ -f ${list} ]] && /usr/lib/apt/apt-helper cat-file "${list}"
	done | sed -n 's/^Package: //p' | sort -u)
if [[ ${which} == main && -z ${in_ppa[g-unity7-desktop]:-} ]]; then
	echo "ppa:${ppa} has no g-unity7-desktop yet, nothing to check."
	exit 0
fi

if ! simulation=$(apt-get -s install g-unity7-desktop 2>&1); then
	echo "${simulation}"
	echo "check.sh: apt cannot install g-unity7-desktop from ppa:${ppa}" >&2
	exit 1
fi

problems=()
for package in "${forbidden[@]}"; do
	grep -q "^Inst ${package} " <<< "${simulation}" && problems+=( "it installs ${package}" )
done
[[ ${#in_ppa[@]} -gt 0 ]] || problems+=( "the package list of ppa:${ppa} is empty" )
## "Inst <package> (<version> <release> [<arch>])"
count=0
## Firefox and Thunderbird stay the Ubuntu packages
while read -r package version; do
	[[ -n ${in_ppa[${package}]:-} && ! ${package} =~ ^(firefox|thunderbird)(-l10n-.*)?$ ]] || continue
	count=$(( count + 1 ))
	[[ ${version} == *"+${VERSION_TAG}."* ]] || problems+=( "it installs ${package} ${version} instead of the G Unity⁷ version" )
done < <(awk '/^Inst / { v = ($3 ~ /^\[/) ? $4 : $3; gsub(/[()]/, "", v); print $2, v }' <<< "${simulation}")

if [[ ${#problems[@]} -gt 0 ]]; then
	printf 'check.sh: %s\n' "${problems[@]}" >&2
	exit 1
fi
echo "g-unity7-desktop installs from ppa:${ppa}: $(grep -c '^Inst ' <<< "${simulation}") packages, ${count} of them from the PPA in their G Unity⁷ version."
