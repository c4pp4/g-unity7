#!/bin/bash
## Check that g-unity7-desktop installs from the staging PPA (or the main PPA)
##  as intended, with the apt simulation in an Ubuntu container of the series
##  (as root): apt can install it with the pins of g-unity7-apt-pin, it does not
##  pull in PulseAudio or build tools, and the packages that the PPA has come in
##  their G Unity⁷ version. Firefox and Thunderbird stay the Ubuntu packages
##  until g-unity7-cleanup installs the G Unity⁷ ones. The main PPA is checked
##  once it has g-unity7-desktop.
##
##  Each relation of g-unity7-desktop with a G Unity⁷ version must work: the
##  first package of a group in Depends or Recommends with one comes in its
##  G Unity⁷ version (apt leaves out a Recommends that it cannot satisfy, or
##  takes another alternative), the Ubuntu versions do not satisfy it, and the
##  PPA version does; Breaks applies to the Ubuntu versions and not to the PPA
##  version. With i386 builds of GTK 3 and IBus in the PPA, g-unity7-desktop
##  must also install next to their i386 libraries, which Steam and Wine
##  install (Multi-Arch: same needs the same version for each architecture).
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

## The relations of g-unity7-desktop with a G Unity⁷ version
control=$(apt-cache show --no-all-versions g-unity7-desktop)
## relations <field>: print the groups of relation field <field>, one per line
relations() {
	awk -v f="$1:" '
		take && /^ / { buf = buf $0; next }
		take { take = 0 }
		$1 == f { take = 1; sub(/^[^:]*: */, ""); buf = $0 }
		END {
			n = split(buf, groups, /,/)
			for (i = 1; i <= n; i++) { g = groups[i]; gsub(/^ +| +$/, "", g); if (g != "") print g }
		}' <<< "${control}"
}
## versions <package> <ppa|ubuntu>: print the versions of the PPA or the others
versions() {
	apt-cache madison "$1" 2>/dev/null | awk -F'|' -v ppa="/${owner}/${name}/" -v want="$2" '
		{ gsub(/ /, "", $2) }
		(index($3, ppa) > 0) == (want == "ppa") { print $2 }'
}
relation_re='^([a-z0-9.+-]+)(:any)? \(([<>=]+) ([^)]+)\)$'
checked=0
while read -r field group; do
	first=${group%%|*}
	first=${first% }
	[[ ${first} =~ ${relation_re} && ${BASH_REMATCH[4]} == *"+${VERSION_TAG}"* ]] || continue
	package=${BASH_REMATCH[1]} op=${BASH_REMATCH[3]} version=${BASH_REMATCH[4]}
	checked=$(( checked + 1 ))
	if [[ ${field} == Breaks ]]; then
		[[ ${op} == "<<" ]] || { problems+=( "Breaks: ${first} is not a << relation" ); continue; }
		while read -r v; do
			dpkg --compare-versions "${v}" lt "${version}" \
				|| problems+=( "Breaks: ${first} does not apply to ${package} ${v} from Ubuntu" )
		done < <(versions "${package}" ubuntu)
		while read -r v; do
			! dpkg --compare-versions "${v}" lt "${version}" \
				|| problems+=( "Breaks: ${first} applies to ${package} ${v} from the PPA" )
		done < <(versions "${package}" ppa)
		continue
	fi
	[[ ${op} == ">=" ]] || { problems+=( "${field}: ${first} is not a >= relation" ); continue; }
	while read -r v; do
		! dpkg --compare-versions "${v}" ge "${version}" \
			|| problems+=( "${field}: ${package} ${v} from Ubuntu satisfies ${first}, so it does not pull in the G Unity⁷ version" )
	done < <(versions "${package}" ubuntu)
	installed=$(awk -v p="${package}" '$1 == "Inst" && $2 == p { v = ($3 ~ /^\[/) ? $4 : $3; gsub(/[()]/, "", v); print v }' \
		<<< "${simulation}")
	if [[ -z ${installed} ]]; then
		problems+=( "${field}: it does not install ${package} for ${group}" )
	elif ! dpkg --compare-versions "${installed}" "${op}" "${version}"; then
		problems+=( "${field}: it installs ${package} ${installed}, which does not satisfy ${first}" )
	fi
done < <(for field in Depends Recommends Breaks; do relations "${field}" | sed "s/^/${field} /"; done)
[[ ${checked} -gt 0 ]] || problems+=( "g-unity7-desktop has no relation with a G Unity⁷ version" )

## i386: Steam and Wine install GTK 3 and IBus for i386
i386=
dpkg --add-architecture i386
for i in 1 2 3; do
	apt-get update -qq && break
	[[ ${i} -lt 3 ]] || exit 1
	sleep 60
done
gtk_i386=$(versions libgtk-3-0t64:i386 ppa | head -n 1)
ibus_i386=$(versions libibus-1.0-5:i386 ppa | head -n 1)
if [[ -n ${gtk_i386} && -n ${ibus_i386} ]]; then
	if ! simulation_i386=$(apt-get -s install g-unity7-desktop libgtk-3-0t64:i386 libibus-1.0-5:i386 2>&1); then
		echo "${simulation_i386}"
		problems+=( "apt cannot install g-unity7-desktop next to libgtk-3-0t64:i386 and libibus-1.0-5:i386" )
	else
		i386=", also next to GTK 3 and IBus for i386"
	fi
else
	echo "::warning::ppa:${ppa} has no i386 build of GTK 3 and IBus (gtk+3.0, ibus); g-unity7-desktop does not install next to their i386 libraries from Ubuntu, such as with Steam or Wine"
fi

if [[ ${#problems[@]} -gt 0 ]]; then
	printf 'check.sh: %s\n' "${problems[@]}" >&2
	exit 1
fi
echo "g-unity7-desktop installs from ppa:${ppa}: $(grep -c '^Inst ' <<< "${simulation}") packages, ${count} of them from the PPA in their G Unity⁷ version, ${checked} relations with a G Unity⁷ version checked${i386}."
