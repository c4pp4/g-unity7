#!/bin/bash
## Install Ubuntu Unity (its task ubuntu-unity-desktop), then g-unity7-desktop
##  from the staging PPA (or the main PPA) as the README says, and run
##  g-unity7-cleanup --yes, for real in an Ubuntu container of the series (as
##  root). dpkg then finds the file conflicts and the errors of the maintainer
##  scripts, which the apt simulation of check.sh does not. No service starts in
##  the container, and snapd does not run, so g-unity7-cleanup installs the
##  G Unity⁷ Firefox and Thunderbird as on a system without their snaps. The
##  main PPA is checked once it has g-unity7-desktop.
##
##    podman run --rm -v "$PWD":/work:ro,Z docker.io/library/ubuntu:26.10 \
##      /work/tests/staging/install.sh [staging|main]

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
	*) echo "usage: install.sh [staging|main]" >&2; exit 2 ;;
esac
owner=${ppa%/*} name=${ppa#*/}

## A step of the log, a group on GitHub
step() {
	[[ -z ${GITHUB_ACTIONS:-} ]] || echo "::endgroup::"
	if [[ -n ${GITHUB_ACTIONS:-} ]]; then
		echo "::group::$*"
	else
		echo "### $*"
	fi
}

update() {
	local i
	for i in 1 2 3; do
		apt-get update -qq && return
		[[ ${i} -lt 3 ]] || return 1
		sleep 60
	done
}

## No service starts in the container
printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d
chmod 755 /usr/sbin/policy-rc.d

step "Ubuntu Unity"
update
apt-get install -y -q ubuntu-unity-desktop >/dev/null

step "g-unity7-desktop from ppa:${ppa}"
## Only a test, so the PPA is not checked against its key
echo "deb [trusted=yes] https://ppa.launchpadcontent.net/${owner}/${name}/ubuntu ${series} main" \
	> /etc/apt/sources.list.d/g-unity7-install.list
## The pins of g-unity7-apt-pin for the PPA, as check.sh sets them
sed "s/o=LP-PPA-c4pp4-g-unity7\$/o=LP-PPA-${owner}-${name}/" "${work}"/local/g-unity7-apt-pin/g-unity7.pref \
	> /etc/apt/preferences.d/g-unity7-install.pref
update
if [[ ${which} == main ]] && ! apt-cache show g-unity7-desktop 2>/dev/null | grep -q '^Version: .*+gu7'; then
	step "Result"
	echo "ppa:${ppa} has no g-unity7-desktop yet, nothing to check."
	exit 0
fi
apt-get install -y -q g-unity7-desktop
apt-get full-upgrade -y -q

step "g-unity7-cleanup --yes"
g-unity7-cleanup --yes

step "Result"
problems=()
apt-get check -q || problems+=( "apt-get check failed" )
audit=$(dpkg --audit)
[[ -z ${audit} ]] || problems+=( "dpkg --audit: ${audit}" )
for package in pulseaudio ubuntu-unity-desktop; do
	[[ $(dpkg-query -W -f='${db:Status-Status}' "${package}" 2>/dev/null) != installed ]] \
		|| problems+=( "${package} is still installed" )
done
for package in g-unity7-desktop firefox thunderbird; do
	[[ $(dpkg-query -W -f='${db:Status-Status} ${Version}' "${package}" 2>/dev/null) == "installed "*+"${VERSION_TAG}".* ]] \
		|| problems+=( "the G Unity⁷ ${package} is not installed" )
done
if [[ ${#problems[@]} -gt 0 ]]; then
	printf 'install.sh: %s\n' "${problems[@]}" >&2
	exit 1
fi
echo "Ubuntu Unity, g-unity7-desktop from ppa:${ppa} and g-unity7-cleanup --yes: $(dpkg -l | grep -c '^ii') packages installed."
