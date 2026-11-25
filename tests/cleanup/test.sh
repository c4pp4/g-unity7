#!/bin/bash
## Tests of g-unity7-cleanup and of the apt configuration of g-unity7-apt-pin
##  with dummy packages, a fake snap and a fake systemctl. Run one group of
##  scenarios as root in an Ubuntu container with the repository, for example
##  in /work:
##
##    podman run --rm -v "$PWD":/work:ro,Z docker.io/library/ubuntu:26.10 \
##      /work/tests/cleanup/test.sh <group>
##
##  or all groups with tests/cleanup/run.sh. The output is compared with
##  tests/cleanup/expected/<group>.out. With --update, it is written there
##  instead (the repository must be writable).
##
## Groups:
##  alternatives  questions about the alternatives, marking and removal
##  mozilla       the G Unity⁷ Firefox and Thunderbird packages and the copy of
##                the snap profiles
##  copies        a copy that fails, the next run that continues the switch,
##                and too little free space
##  profiles      a profile group of Firefox, profiles that profiles.ini does
##                not list or that have an absolute path, package profiles in
##                the XDG directories, and a Firefox that apt cannot install
##  locations     snap profiles in the XDG directory of the installed revision,
##                in the legacy directory, and linked to the package profiles
##  links        snap profiles with links to other files, which the copy must
##                not follow
##  scenarios     a new system: the Firefox and Thunderbird snaps that were never
##                started, and Evolution instead of Thunderbird
##  snaps         desktop files and mount units of snaps that are not
##                installed, and the configuration files of PulseAudio
##  pin           unattended-upgrades with the pins of g-unity7-apt-pin, when
##                Ubuntu publishes a security update and the PPA its rebuild

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
unset LANG LANGUAGE

update=
if [[ ${1:-} == --update ]]; then
	update=1
	shift
fi
[[ $# -eq 1 ]] || { echo "Usage: test.sh [--update] <group>" >&2; exit 2; }
group=$1
work=$(cd "$(dirname "$0")"/../.. && pwd)
meta=${work}/local/g-unity7-meta
cleanup=${meta}/g-unity7-cleanup
expected=${work}/tests/cleanup/expected/${group}.out
repos=/tmp/repo
## Timestamps of the dummy packages
export SOURCE_DATE_EPOCH=1793000000

## Leave out the output of apt and dpkg that depends on the image or the time.
##  The error of cp depends on the order of the files in a directory, which
##  differs between runs.
quiet() {
	{ grep -v -E '^(Reading package lists|Building dependency tree|Reading state information|Solving dependencies|\(Reading database|Selecting previously unselected package|Preparing to unpack|Unpacking |Setting up |Removing |Purging configuration files|Processing triggers|Get:[0-9]|Need to get|debconf: )' || true; } \
		| sed -E 's/^cp: .*/cp: (error)/'
}

## mkdeb <repository> <name> <version> [<control line>...]: build a dummy
##  package. The files in the directory ${tree}, if set, are included.
mkdeb() {
	local repo=$1 name=$2 version=$3 dir
	shift 3
	dir=$(mktemp -d)
	[[ -z ${tree:-} ]] || cp -a "${tree}/." "${dir}/"
	mkdir -p "${dir}"/DEBIAN "${repo}"
	{
		echo "Package: ${name}"
		echo "Version: ${version}"
		echo "Architecture: all"
		echo "Maintainer: Test <test@example.org>"
		[[ $# -eq 0 ]] || printf '%s\n' "$@"
		echo "Description: test package ${name}"
	} > "${dir}"/DEBIAN/control
	dpkg-deb -b --root-owner-group "${dir}" "${repo}/${name}_${version#*:}_all.deb" >/dev/null
	rm -rf "${dir}"
}

## index <repository> [<origin> [<suite>]]: write its Packages file, and a
##  Release file with the origin, which the apt pins of g-unity7-apt-pin use,
##  and the suite (default: stonking)
index() {
	(cd "$1" && apt-ftparchive packages . > Packages 2>/dev/null)
	[[ -z ${2:-} ]] || printf 'Origin: %s\nSuite: %s\n' "$2" "${3:-stonking}" > "$1"/Release
}

## use_repositories <repository>...: make them the only package sources
use_repositories() {
	local repo
	rm -f /etc/apt/sources.list.d/* /etc/apt/sources.list
	for repo in "$@"; do
		echo "deb [trusted=yes] file:${repo} ./"
	done > /etc/apt/sources.list.d/test.list
	apt-get update -qq 2>/dev/null
}

## The packages whose state the scenarios print
state_packages=()

## Print the installed packages of state_packages, with (a) if automatically
##  installed, and those that only have configuration files with (c)
state() {
	local auto name status
	auto=$(apt-mark showauto)
	for name in "${state_packages[@]}"; do
		status=$(dpkg-query -W -f='${db:Status-Status}' "${name}" 2>/dev/null) || true
		case ${status} in
			installed)
				if grep -qx "${name}" <<< "${auto}"; then
					echo -n "${name}(a) "
				else
					echo -n "${name} "
				fi
				;;
			config-files) echo -n "${name}(c) " ;;
		esac
	done
	echo
}

## run <title> <command>...: print the title, the output without the progress
##  of apt and dpkg, the exit status if it is not 0, and the package state
run() {
	local title=$1 status=0 out
	shift
	echo "### ${title}"
	out=$("$@" 2>&1) || status=$?
	quiet <<< "${out}"
	[[ ${status} -eq 0 ]] || echo "[exit ${status}]"
	echo -n "state: "
	state
	echo
}

## The environment of all groups: the tools to build the repositories, the
##  installed helper of the cleanup, and the fake snap and systemctl
setup_common() {
	apt-get update -qq 2>/dev/null
	apt-get install -y -qq --no-install-recommends apt-utils >/dev/null 2>&1
	if [[ -f ${meta}/copy-snap-profiles ]]; then
		install -D -m 755 "${meta}"/copy-snap-profiles /usr/libexec/g-unity7/copy-snap-profiles
	fi
	mkdir -p /tmp/snaps
	cat > /usr/local/bin/snap <<-'EOF'
		#!/bin/sh
		## Fake snap: /tmp/snaps/<name> has a line "<version> <revision>" for each
		##  installed revision, the current one last. /tmp/snap-list-fail makes
		##  "snap list" fail, /tmp/snap-fail-<name> makes "snap remove" fail.
		case $1 in
			list)
				[ ! -e /tmp/snap-list-fail ] || { echo "error: cannot list (test)" >&2; exit 1; }
				shift
				all=
				if [ "${1:-}" = --all ]; then
					all=1
					shift
				fi
				if [ $# -gt 0 ]; then
					[ -f "/tmp/snaps/$1" ] || { echo "error: no matching snaps installed" >&2; exit 1; }
					names=$1
				else
					names=$(ls /tmp/snaps)
				fi
				echo "Name Version Rev Tracking Publisher Notes"
				for name in ${names}; do
					if [ -n "${all}" ]; then
						lines=$(cat "/tmp/snaps/${name}")
					else
						lines=$(tail -n 1 "/tmp/snaps/${name}")
					fi
					echo "${lines}" | while read -r version revision; do
						echo "${name} ${version} ${revision} latest/stable test -"
					done
				done
				;;
			remove)
				[ -f "/tmp/snaps/$2" ] || { echo "error: snap \"$2\" is not installed" >&2; exit 1; }
				[ ! -e "/tmp/snap-fail-$2" ] || { echo "error: cannot remove \"$2\" (test)" >&2; exit 1; }
				rm -f "/tmp/snaps/$2"
				echo "$2 removed (test)"
				;;
			*)
				echo "fake snap: $* is not supported" >&2
				exit 1
				;;
		esac
	EOF
	printf '#!/bin/sh\necho "systemctl $*" >> /tmp/systemctl.log\n' > /usr/local/bin/systemctl
	chmod 755 /usr/local/bin/snap /usr/local/bin/systemctl
}

## Alternatives: the relations of a dummy g-unity7-desktop and a dummy task
group_alternatives() {
	local repo=${repos}/alternatives all base before raw
	## Czech: the translated "  Candidate: " of apt-cache policy
	apt-get install -y -qq locales >/dev/null 2>&1
	sed -i 's/^# *cs_CZ.UTF-8/cs_CZ.UTF-8/' /etc/locale.gen
	locale-gen >/dev/null 2>&1
	(cd /tmp && apt-get download -qq apt >/dev/null 2>&1 && dpkg-deb -x apt_*.deb /tmp/aptdeb \
		&& install -D -m 644 /tmp/aptdeb/usr/share/locale/cs/LC_MESSAGES/apt.mo \
			/usr/share/locale/cs/LC_MESSAGES/apt.mo)

	mkdeb "${repo}" g-unity7-desktop 1 "Recommends: a1 | a2 | a3, b1 | b2, c1 | c2 | c3, d1 | d2, e1 | e2, f1 | f2, f1 | f3, f1 | f4, g1 | g2"
	mkdeb "${repo}" ubuntu-unity-desktop 1 "Depends: dup1, eapp" \
		"Recommends: a2, a3, b2, c2, c3, ubuntu-unity-settings" "Task: ubuntu-unity-desktop"
	## Only the Ubuntu Unity image installs it
	mkdeb "${repo}" ubuntu-unity-settings 1 "Task: ubuntu-unity-desktop"
	## gparted of the image, and kdialog, which apt keeps as an alternative of
	##  "zenity | kdialog" (im-config)
	mkdeb "${repo}" gparted 1
	mkdeb "${repo}" im-config 1 "Depends: zenity | kdialog"
	mkdeb "${repo}" zenity 1
	mkdeb "${repo}" kdialog 1
	mkdeb "${repo}" dup1 1 "Depends: dupdep" "Task: ubuntu-unity-desktop"
	mkdeb "${repo}" dupdep 1 "Task: ubuntu-unity-desktop"
	mkdeb "${repo}" tool 1 "Task: ubuntu-unity-desktop"
	for name in a1 b1 b2 d1 d2; do mkdeb "${repo}" "${name}" 1; done
	for name in a3 c2 c3 a2dep; do mkdeb "${repo}" "${name}" 1 "Task: ubuntu-unity-desktop"; done
	mkdeb "${repo}" a2 1 "Depends: a2dep" "Task: ubuntu-unity-desktop"
	mkdeb "${repo}" needs-b2 1 "Depends: b2"
	## e1 | e2 as nemo-engrampa | nemo-fileroller: eapp as engrampa, eapp2 as
	##  file-roller
	mkdeb "${repo}" e1 1 "Depends: eapp"
	mkdeb "${repo}" e2 1 "Depends: eapp2" "Task: ubuntu-unity-desktop"
	mkdeb "${repo}" eapp 1 "Task: ubuntu-unity-desktop"
	mkdeb "${repo}" eapp2 1 "Task: ubuntu-unity-desktop"
	## f1 | (f2 f3 f4) as mate-utils | (gnome-screenshot baobab gnome-logs)
	for name in f1 f3 f4; do mkdeb "${repo}" "${name}" 1; done
	mkdeb "${repo}" f2 1 "Task: ubuntu-unity-desktop"
	## g1 needs glib 1, while glib 2 is installed from elsewhere: installing g1
	##  downgrades glib
	mkdeb "${repo}" g1 1 "Depends: glib (= 1)"
	mkdeb "${repo}" g2 1
	mkdeb "${repo}" glib 1
	mkdeb /tmp/other glib 2
	index "${repo}" Test
	use_repositories "${repo}"

	all=( g-unity7-desktop ubuntu-unity-desktop ubuntu-unity-settings dup1 dupdep tool a1 a2 a2dep a3 b1 b2
		c2 c3 d1 d2 needs-b2 e1 e2 eapp eapp2 f1 f2 f3 f4 g1 g2 glib gparted im-config zenity kdialog )
	state_packages=( "${all[@]}" )
	## setup <manual packages> -- <automatic packages>
	setup() {
		local manual=() auto=()
		apt-get -y -qq purge "${all[@]}" >/dev/null 2>&1 || true
		rm -rf /var/lib/g-unity7
		while [[ $1 != -- ]]; do
			manual+=( "$1" )
			shift
		done
		shift
		auto=( "$@" )
		apt-get -y -qq --no-install-recommends install "${manual[@]}" "${auto[@]}" >/dev/null 2>&1
		apt-mark manual "${manual[@]}" >/dev/null
		[[ ${#auto[@]} -eq 0 ]] || apt-mark auto "${auto[@]}" >/dev/null
	}

	base=( g-unity7-desktop ubuntu-unity-desktop dup1 dupdep tool a2 a2dep c2 c3 needs-b2 -- a1 b1 b2 d2 )
	setup "${base[@]}"
	before=$(state)
	run "dry-run: 1 1 Enter 2" bash -c "printf '1\n1\n\n2\n' | ${cleanup} --dry-run"
	if [[ $(state) == "${before}" ]]; then
		echo "dry-run changed nothing"
	else
		echo "DRY-RUN CHANGED THE STATE"
	fi
	echo
	run "dry-run: 2 2 1 1" bash -c "printf '2\n2\n1\n1\n' | ${cleanup} --dry-run"
	run "dry-run: invalid answers x 9 0, then 4 3 3 2" bash -c "printf 'x\n9\n0\n4\n3\n3\n2\n' | ${cleanup} --dry-run"
	run "dry-run: no answer" bash -c "${cleanup} --dry-run < /dev/null"
	run "--yes --dry-run" "${cleanup}" --yes --dry-run
	run "--yes" "${cleanup}" --yes
	run "again --yes" "${cleanup}" --yes

	setup "${base[@]}"
	run "answers 1 1 Enter 2, no answer to the confirmation" bash -c "printf '1\n1\n\n2\n' | ${cleanup}"
	run "answers 1 1 Enter 2, confirmation n" bash -c "printf '1\n1\n\n2\nn\n' | ${cleanup}"

	setup g-unity7-desktop a2 -- a3 d2
	run "a2 a3 without a1: 1 (install a1), 2 (keep d2), confirm" bash -c "printf '1\n2\ny\n' | ${cleanup}"

	setup g-unity7-desktop c2 -- c3
	run "c2 c3, c1 not in the archive: Enter, --dry-run" bash -c "printf '\n' | ${cleanup} --dry-run"
	run "c2 c3: --yes" "${cleanup}" --yes

	setup g-unity7-desktop -- a3 c2
	run "only a3 (a1 in the archive) and only c2 (c1 not): 1, confirm" bash -c "printf '1\ny\n' | ${cleanup}"

	setup g-unity7-desktop ubuntu-unity-desktop dup1 dupdep e2 eapp eapp2 --
	run "e2 instead of e1: 2 (keep e2), confirm" bash -c "printf '2\ny\n' | ${cleanup}"
	setup g-unity7-desktop ubuntu-unity-desktop dup1 dupdep e2 eapp eapp2 --
	run "e2 instead of e1: 1 (install e1), confirm" bash -c "printf '1\ny\n' | ${cleanup}"

	echo "### Czech apt-cache policy"
	LANG=cs_CZ.UTF-8 LC_ALL= apt-cache policy d1 | grep -i kandid
	echo
	setup g-unity7-desktop -- d2
	run "Czech: d2 instead of d1, --yes --dry-run" env LANG=cs_CZ.UTF-8 LC_ALL= "${cleanup}" --yes --dry-run

	## On a terminal, the script shows a spinner while it looks for packages
	setup g-unity7-desktop ubuntu-unity-desktop dup1 dupdep a2 a2dep tool -- a1 d2
	echo "### terminal: 1 1, confirmation n"
	raw=$(printf '1\n1\nn\n' | script -qec "${cleanup}" /dev/null 2>&1) || true
	if grep -q 'Looking for packages' <<< "${raw}"; then
		echo "spinner shown"
	else
		echo "NO SPINNER"
	fi
	grep -q 'No changes were made' <<< "${raw}" && echo "no changes made"
	echo

	## f1 | (f2 f3 f4)
	setup g-unity7-desktop f2 -- f1
	run "f1 and f2: 1 (keep f1), confirm" bash -c "printf '1\ny\n' | ${cleanup}"
	setup g-unity7-desktop f2 -- f1
	run "f1 and f2: 2 (keep f2 with f3 f4), confirm" bash -c "printf '2\ny\n' | ${cleanup}"
	setup g-unity7-desktop f2 f3 --
	run "f2 f3 without f1: --yes" "${cleanup}" --yes
	setup g-unity7-desktop f2 f3 --
	run "f2 f3 without f1: 2 (keep the set), confirm" bash -c "printf '2\ny\n' | ${cleanup}"

	## Installing an alternative that is not the first one
	setup g-unity7-desktop a2 -- a1
	run "a1 and a2: 3 (install a3), confirm" bash -c "printf '3\ny\n' | ${cleanup}"
	setup g-unity7-desktop a2 --
	run "only a2: 3 (install a3), confirm" bash -c "printf '3\ny\n' | ${cleanup}"

	## Installing g1 needs glib 1 instead of the installed glib 2. apt does not
	##  downgrade it by itself, so the simulation fails.
	setup g-unity7-desktop g2 --
	dpkg -i /tmp/other/glib_2_all.deb >/dev/null
	run "g2 instead of g1, which needs an older glib: 1 (install g1), confirm" bash -c "printf '1\ny\n' | ${cleanup}"
	## With a pin above 1000, as for the G Unity⁷ PPA, glib 1 is the candidate and
	##  apt downgrades glib. The confirmed list shows the downgrade, which
	##  apt-get -y refuses unless it is allowed.
	printf 'Package: glib\nPin: release o=Test\nPin-Priority: 1001\n' > /etc/apt/preferences.d/test.pref
	setup g-unity7-desktop g2 --
	dpkg -i /tmp/other/glib_2_all.deb >/dev/null
	run "the same with glib pinned to the repository: 1 (install g1), confirm" bash -c "printf '1\ny\n' | ${cleanup}"
	rm /etc/apt/preferences.d/test.pref

	## The packages of the Ubuntu Unity image are removed only on a system from
	##  it. Installing g-unity7-desktop has removed the task there, but not
	##  ubuntu-unity-settings, and the first run remembers it.
	unity=( g-unity7-desktop dup1 gparted im-config zenity -- dupdep kdialog )
	setup "${unity[@]}"
	run "another flavor (no task, no ubuntu-unity-settings): --yes" "${cleanup}" --yes
	setup ubuntu-unity-settings "${unity[@]}"
	run "Ubuntu Unity without the task: --yes" "${cleanup}" --yes
	ls /var/lib/g-unity7
	echo
	apt-get install -y -qq --no-install-recommends dup1 gparted >/dev/null 2>&1
	apt-mark manual dup1 gparted >/dev/null
	run "again, without ubuntu-unity-settings: --yes --dry-run" "${cleanup}" --yes --dry-run
	setup ubuntu-unity-settings "${unity[@]}"
	run "--keep gparted --keep dupdep --keep=kdialog, --yes" "${cleanup}" --keep gparted --keep dupdep --keep=kdialog --yes
	run "--keep without a package" "${cleanup}" --keep
}

## The Ubuntu Firefox and Thunderbird packages (versions of the snap
##  transitional packages), the G Unity⁷ packages with their language packages
##  and pins, and the snaps
setup_mozilla() {
	local ubuntu=${repos}/ubuntu ppa=${repos}/c4pp4/g-unity7 lang
	firefox_ppa=159.0.1-1+gu7.1~26.10
	thunderbird_ppa=1:153.8.0esr-1+gu7.1~26.10
	mkdeb "${ubuntu}" firefox 1:1snap1
	mkdeb "${ubuntu}" thunderbird 2:1snap1
	for name in firefox thunderbird; do
		tree=$(mktemp -d)
		mkdir -p "${tree}"/etc/apt/preferences.d
		ln -s /usr/share/g-unity7-apt-pin/${name}.pref "${tree}"/etc/apt/preferences.d/g-unity7-${name}.pref
		if [[ ${name} == firefox ]]; then
			mkdeb "${ppa}" firefox "${firefox_ppa}"
		else
			mkdeb "${ppa}" thunderbird "${thunderbird_ppa}"
		fi
		rm -rf "${tree}"
		tree=
	done
	for lang in cs pt-br pt-pt de; do
		mkdeb "${ppa}" firefox-l10n-${lang} "${firefox_ppa}" \
			"Depends: firefox (>= ${firefox_ppa}), firefox (<< ${firefox_ppa}.1~)"
	done
	for lang in cs pt-br; do
		mkdeb "${ppa}" thunderbird-l10n-${lang} "${thunderbird_ppa}" \
			"Depends: thunderbird (>= ${thunderbird_ppa}), thunderbird (<< ${thunderbird_ppa}.1~)"
	done
	mkdeb "${ppa}" g-unity7-desktop 1+gu7.12
	index "${ubuntu}" Ubuntu
	index "${ppa}" LP-PPA-c4pp4-g-unity7
	use_repositories "${ubuntu}" "${ppa}"
	install -D -m 644 -t /usr/share/g-unity7-apt-pin "${work}"/local/g-unity7-apt-pin/firefox.pref \
		"${work}"/local/g-unity7-apt-pin/thunderbird.pref
	install -D -m 644 -t /etc/apt/preferences.d "${work}"/local/g-unity7-apt-pin/g-unity7.pref
	apt-get install -y -qq g-unity7-desktop firefox thunderbird >/dev/null 2>&1
	## The languages in use: the system language and the one of a user
	echo 'LANG="cs_CZ.UTF-8"' > /etc/default/locale
	mkdir -p /var/lib/AccountsService/users
	state_packages=( firefox firefox-l10n-cs firefox-l10n-de firefox-l10n-pt-br firefox-l10n-pt-pt
		thunderbird thunderbird-l10n-cs thunderbird-l10n-pt-br )
}

## Print the files in the directories $@ with owner, group and mode, sorted
files() {
	find "$@" -printf '%u:%g %m %p%y\n' 2>/dev/null | sed -e 's/d$/\//' -e 's/l$/@/' -e 's/f$//' | sort -k 3 || true
}

## Firefox and Thunderbird: the choice, the language packages, the copy of
##  the profiles, a running snap and a snap that cannot be removed
group_mozilla() {
	local alice=/home/alice bob=/home/bob
	setup_mozilla
	useradd -m -u 1001 alice
	useradd -m -u 1002 bob
	## A user of a network directory may have a UID above 59999
	useradd -m -u 60001 carol 2>/dev/null
	printf '[User]\nLanguage=pt_BR.UTF-8\n' > /var/lib/AccountsService/users/bob
	printf '159.0.1-1 6000\n' > /tmp/snaps/firefox
	printf '161.0-1 400\n' > /tmp/snaps/thunderbird
	mkdir -p "${alice}"/snap/firefox/common/.mozilla/firefox/abc.default \
		"${alice}"/snap/thunderbird/common/.thunderbird/p.default \
		"${bob}"/snap/firefox/common/.mozilla/firefox/x "${bob}"/.mozilla/firefox
	echo prefs > "${alice}"/snap/firefox/common/.mozilla/firefox/abc.default/prefs.js
	printf '[General]\nStartWithLastProfile=1\nVersion=2\n\n[Profile0]\nName=default\nIsRelative=1\nPath=abc.default\nDefault=1\n\n' \
		> "${alice}"/snap/firefox/common/.mozilla/firefox/profiles.ini
	echo prefs > "${alice}"/snap/thunderbird/common/.thunderbird/p.default/prefs.js
	printf '[General]\nStartWithLastProfile=1\n\n[Profile0]\nName=default\nIsRelative=1\nPath=p.default\nDefault=1\n\n' \
		> "${alice}"/snap/thunderbird/common/.thunderbird/profiles.ini
	## Thunderbird 161 of the snap used the profile last, which the ESR package
	##  does not open
	printf '[Compatibility]\nLastVersion=161.0_20261124054846/20261124054846\n' \
		> "${alice}"/snap/thunderbird/common/.thunderbird/p.default/compatibility.ini
	chown -R alice:alice "${alice}"
	chown -R bob:bob "${bob}"
	mkdir -p /home/carol/snap/firefox/common/.mozilla/firefox/c.default
	printf '[Profile0]\nName=default\nIsRelative=1\nPath=c.default\nDefault=1\n' \
		> /home/carol/snap/firefox/common/.mozilla/firefox/profiles.ini
	chown -R carol:carol /home/carol
	## The directory of a revision that snapd does not know, which the image
	##  leaves, and that of the installed revision
	mkdir -p /var/snap/firefox/5000 /var/snap/firefox/6000

	run "dry-run as alice, without root: Enter" bash -c "printf '\n' | setpriv --reuid=alice --regid=alice --init-groups --reset-env ${cleanup} --dry-run"
	run "dry-run: Enter (Firefox; Thunderbird 161 used the snap profile)" bash -c "printf '\n' | ${cleanup} --dry-run"
	## A profile that a newer Firefox used keeps the snap until the package is
	##  updated
	printf '[Compatibility]\nLastVersion=160.0.1_20261110000000/20261110000000\n' \
		> /home/carol/snap/firefox/common/.mozilla/firefox/c.default/compatibility.ini
	run "dry-run: Firefox 160 used the snap profile of carol" bash -c "printf '\n' | ${cleanup} --dry-run"
	rm /home/carol/snap/firefox/common/.mozilla/firefox/c.default/compatibility.ini
	run "Firefox package (1), confirm" bash -c "printf '1\ny\n' | ${cleanup}"
	echo "### after the Firefox package"
	ls /etc/apt/preferences.d
	apt-cache policy firefox | grep -E '^firefox|Candidate'
	files "${alice}"/.mozilla
	echo "-- profiles.ini"
	cat "${alice}"/.mozilla/firefox/profiles.ini
	echo "-- installs.ini"
	cat "${alice}"/.mozilla/firefox/installs.ini
	echo "-- snaps: $(ls /tmp/snaps | tr '\n' ' ')"
	echo "-- /var/snap/firefox: $(ls /var/snap/firefox | tr '\n' ' ')"
	files /home/carol/.mozilla
	apt-get -s upgrade 2>&1 | grep -E '^(Inst|Remv)' || echo "apt upgrade keeps the packages"
	echo

	## The snap was updated, but not started since Thunderbird 153 used the
	##  profile: the ESR package opens it
	printf '161.0.1-1 410\n' > /tmp/snaps/thunderbird
	printf '[Compatibility]\nLastVersion=153.7.0_20261020000000/20261020000000\n' \
		> "${alice}"/snap/thunderbird/common/.thunderbird/p.default/compatibility.ini
	(exec -a /snap/thunderbird/410/thunderbird sleep 300) &
	sleeper=$!
	sleep 1
	run "Thunderbird snap 161.0.1 running, Thunderbird 153 used its profile: Enter, confirm" bash -c "printf '\ny\n' | ${cleanup}"
	kill "${sleeper}" 2>/dev/null || true
	wait "${sleeper}" 2>/dev/null || true

	## The snap is started while apt installs the package, after the analysis.
	##  apt runs the hook with sh, which has no exec -a.
	echo "DPkg::Pre-Invoke { \"bash -c '(exec -a /snap/thunderbird/410/thunderbird sleep 300) >/dev/null 2>&1 &'\"; };" \
		> /etc/apt/apt.conf.d/99test-start-snap
	run "Thunderbird snap started during the changes: 1, confirm" bash -c "printf '1\ny\n' | ${cleanup}"
	rm /etc/apt/apt.conf.d/99test-start-snap
	pkill -f /snap/thunderbird/ || true
	echo "-- snaps: $(ls /tmp/snaps | tr '\n' ' ')"
	files "${alice}"/.thunderbird
	echo

	touch /tmp/snap-fail-thunderbird
	run "Thunderbird snap stopped, snap remove fails: 1, confirm" bash -c "printf '1\ny\n' | ${cleanup}"
	rm /tmp/snap-fail-thunderbird
	echo "-- snaps: $(ls /tmp/snaps | tr '\n' ' ')"
	files "${alice}"/.thunderbird
	echo

	run "again: the package and the snap: 1, confirm" bash -c "printf '1\ny\n' | ${cleanup}"
	echo "-- snaps: $(ls /tmp/snaps | tr '\n' ' ')"
	files "${alice}"/.thunderbird
	echo "-- profiles.ini"
	cat "${alice}"/.thunderbird/profiles.ini
	echo

	run "nothing left: --dry-run" "${cleanup}" --dry-run

	## Firefox from another source, such as Mozilla's APT repository, stays
	mkdeb /tmp/mozilla firefox 161.0~build1
	apt-get -y -qq purge firefox-l10n-cs firefox-l10n-de firefox-l10n-pt-br firefox-l10n-pt-pt >/dev/null 2>&1
	dpkg -i /tmp/mozilla/firefox_161.0~build1_all.deb >/dev/null 2>&1
	run "Firefox from another source: --yes" "${cleanup}" --yes

	## copy-snap-profiles into a directory without profiles.ini, with a profile
	##  of the same name left behind: the snap profiles are added
	mkdir -p "${alice}"/src/p.default "${alice}"/dst/p.default
	echo snap > "${alice}"/src/p.default/prefs.js
	echo old > "${alice}"/dst/p.default/prefs.js
	printf '[Profile0]\nName=default\nIsRelative=1\nPath=p.default\nDefault=1\n' > "${alice}"/src/profiles.ini
	chown -R alice:alice "${alice}"/src "${alice}"/dst
	run "copy-snap-profiles: a profile left behind without profiles.ini" setpriv --reuid=alice --regid=alice \
		--init-groups --reset-env /usr/libexec/g-unity7/copy-snap-profiles "${alice}"/src "${alice}"/dst \
		FDC34C9F024745EB adopt
	files "${alice}"/dst
	echo "-- p.default/prefs.js: $(cat "${alice}"/dst/p.default/prefs.js)"
	echo "-- profiles.ini"
	cat "${alice}"/dst/profiles.ini
}

## The copies of the snap profiles: a copy that fails keeps the snap installed
##  while the copies of the other users are made, the next run continues the
##  switch without making them again, and a copy that does not fit is not
##  offered
group_copies() {
	local alice=/home/alice bob=/home/bob carol=/home/carol dir
	setup_mozilla
	useradd -m -u 1001 alice
	useradd -m -u 1002 bob
	useradd -m -u 1003 carol
	printf '159.0-1 400\n' > /tmp/snaps/thunderbird
	for dir in "${alice}" "${bob}"; do
		mkdir -p "${dir}"/snap/thunderbird/common/.thunderbird/p.default
		echo prefs > "${dir}"/snap/thunderbird/common/.thunderbird/p.default/prefs.js
		printf '[Profile0]\nName=default\nIsRelative=1\nPath=p.default\nDefault=1\n' \
			> "${dir}"/snap/thunderbird/common/.thunderbird/profiles.ini
	done
	chown -R alice:alice "${alice}"
	chown -R bob:bob "${bob}"
	## A file of the snap profile that bob cannot read stops his copy
	echo mail > "${bob}"/snap/thunderbird/common/.thunderbird/p.default/locked
	chmod 000 "${bob}"/snap/thunderbird/common/.thunderbird/p.default/locked

	run "the copy of bob fails: 2 (no Firefox), 1, confirm" bash -c "printf '2\n1\ny\n' | ${cleanup}"
	echo "-- snaps: $(ls /tmp/snaps | tr '\n' ' ')"
	echo "-- switch: $(ls /var/lib/g-unity7 | tr '\n' ' ')"
	files "${alice}"/.thunderbird "${bob}" | grep -v '/snap/'
	echo

	chmod 644 "${bob}"/snap/thunderbird/common/.thunderbird/p.default/locked
	run "again: 2, 1, confirm" bash -c "printf '2\n1\ny\n' | ${cleanup}"
	echo "-- snaps: $(ls /tmp/snaps | tr '\n' ' ')"
	echo "-- switch: $(ls /var/lib/g-unity7 | tr '\n' ' ')"
	files "${alice}"/.thunderbird "${bob}"/.thunderbird
	echo "-- profiles.ini of bob"
	cat "${bob}"/.thunderbird/profiles.ini
	echo

	## Too little free space for the copy of carol
	printf '159.0-1 401\n' > /tmp/snaps/thunderbird
	mkdir -p "${carol}"/snap/thunderbird/common/.thunderbird/c.default
	printf '[Profile0]\nName=default\nIsRelative=1\nPath=c.default\nDefault=1\n' \
		> "${carol}"/snap/thunderbird/common/.thunderbird/profiles.ini
	chown -R carol:carol "${carol}"
	cat > /usr/local/bin/df <<-'EOF'
		#!/bin/sh
		## Fake df: 50000 KiB free on /
		echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
		echo "test 1000000 950000 50000 95% /"
	EOF
	chmod 755 /usr/local/bin/df
	run "too little space: --dry-run, 2" bash -c "printf '2\n' | ${cleanup} --dry-run"
	rm /usr/local/bin/df
}

## Where the snap profiles are: the XDG directory of the installed revision,
##  where Thunderbird 160 creates new profiles (the "current" link still points
##  to the previous revision), the legacy directory, which Firefox and
##  Thunderbird use if it exists, and the link that the Thunderbird snap makes
##  to the profiles of Ubuntu's package from before the snap. The snap opens
##  the profile with Default=1 there, not the one in the install section of the
##  package.
group_locations() {
	local dave=/home/dave erin=/home/erin frank=/home/frank
	setup_mozilla
	useradd -m -u 1004 dave
	useradd -m -u 1005 erin
	useradd -m -u 1006 frank
	printf '159.0.1-1 6000\n' > /tmp/snaps/firefox
	printf '159.0-1 1331\n159.0-1 1333\n' > /tmp/snaps/thunderbird
	## profile <directory> <profile>: a profile directory with one profile
	profile() {
		mkdir -p "$1/$2"
		echo prefs > "$1/$2"/prefs.js
		printf '[General]\nStartWithLastProfile=1\nVersion=2\n\n[Profile0]\nName=default\nIsRelative=1\nPath=%s\nDefault=1\n' \
			"$2" > "$1"/profiles.ini
	}
	profile "${dave}"/snap/firefox/6000/.config/mozilla/firefox f.default
	mkdir -p "${dave}"/snap/firefox/common
	profile "${dave}"/snap/thunderbird/1331/.config/thunderbird old.default
	profile "${dave}"/snap/thunderbird/1333/.config/thunderbird new.default
	ln -s 1331 "${dave}"/snap/thunderbird/current
	profile "${erin}"/snap/thunderbird/common/.thunderbird legacy.default
	profile "${erin}"/snap/thunderbird/1333/.config/thunderbird xdg.default
	mkdir -p "${frank}"/.thunderbird/used.default "${frank}"/.thunderbird/old.default \
		"${frank}"/snap/thunderbird/common
	echo prefs > "${frank}"/.thunderbird/used.default/prefs.js
	printf '[Profile0]\nName=default\nIsRelative=1\nPath=used.default\nDefault=1\n\n[Profile1]\nName=old\nIsRelative=1\nPath=old.default\n\n[General]\nStartWithLastProfile=1\nVersion=2\n\n[InstallFDC34C9F024745EB]\nDefault=old.default\nLocked=1\n' \
		> "${frank}"/.thunderbird/profiles.ini
	ln -s "${frank}"/.thunderbird "${frank}"/snap/thunderbird/common/.thunderbird
	chown -hR dave:dave "${dave}"
	chown -hR erin:erin "${erin}"
	chown -hR frank:frank "${frank}"

	run "dry-run: Enter, Enter" bash -c "printf '\n\n' | ${cleanup} --dry-run"
	run "--yes" "${cleanup}" --yes
	echo "-- snaps: $(ls /tmp/snaps | tr '\n' ' ')"
	files "${dave}"/.mozilla "${dave}"/.thunderbird "${erin}"/.thunderbird "${frank}"/.thunderbird
	echo "-- profiles.ini of frank"
	cat "${frank}"/.thunderbird/profiles.ini
	echo "-- installs.ini of frank"
	cat "${frank}"/.thunderbird/installs.ini
}

## Profiles that the copy must not lose or hide. A profile group of Firefox
##  has profiles that only its database lists, which keep their names, so a
##  taken name stops the copy; a profile directory that profiles.ini does not
##  list is copied too; a profile with an absolute path in the snap directory
##  is named in the preview. The package profiles in the XDG directories, which
##  Firefox and Thunderbird use when the legacy ones do not exist, get the
##  copies. A G Unity⁷ Firefox that apt cannot install, as with GTK 3 for i386
##  from Ubuntu, is not offered, and the rest goes on.
group_profiles() {
	local gina=/home/gina ivan=/home/ivan hank=/home/hank ppa=${repos}/c4pp4/g-unity7
	local ffs=snap/firefox/common/.mozilla/firefox
	setup_mozilla
	useradd -m -u 1007 gina
	useradd -m -u 1008 ivan
	useradd -m -u 1009 hank
	printf '159.0.1-1 6000\n' > /tmp/snaps/firefox
	printf '159.0-1 400\n' > /tmp/snaps/thunderbird
	## gina: a profile group, a profile that profiles.ini does not list and one
	##  with an absolute path in the snap, added to her package profiles
	mkdir -p "${gina}/${ffs}"/aaa.default "${gina}/${ffs}"/bbb.work "${gina}/${ffs}"/zzz.old \
		"${gina}/${ffs}/Profile Groups" "${gina}"/snap/firefox/common/elsewhere "${gina}"/.mozilla/firefox/old.default
	echo prefs > "${gina}/${ffs}"/aaa.default/prefs.js
	echo 'user_pref("toolkit.profiles.storeID", "1a2b3c4d");' > "${gina}/${ffs}"/bbb.work/prefs.js
	echo '{}' > "${gina}/${ffs}"/zzz.old/times.json
	echo db > "${gina}/${ffs}/Profile Groups/1a2b3c4d.sqlite"
	printf '[Profile1]\nName=elsewhere\nIsRelative=0\nPath=%s\n\n[Profile0]\nName=default\nIsRelative=1\nPath=aaa.default\nDefault=1\nStoreID=1a2b3c4d\nShowSelector=1\n\n[General]\nStartWithLastProfile=1\nVersion=2\n' \
		"${gina}"/snap/firefox/common/elsewhere > "${gina}/${ffs}"/profiles.ini
	printf '[Profile0]\nName=old\nIsRelative=1\nPath=old.default\nDefault=1\n' > "${gina}"/.mozilla/firefox/profiles.ini
	## ivan: package profiles only in the XDG directories
	mkdir -p "${ivan}/${ffs}"/i.default "${ivan}"/snap/thunderbird/common/.thunderbird/t.default \
		"${ivan}"/.config/mozilla/firefox/x.default "${ivan}"/.config/thunderbird/y.default
	printf '[Profile0]\nName=default\nIsRelative=1\nPath=i.default\nDefault=1\n' > "${ivan}/${ffs}"/profiles.ini
	printf '[Profile0]\nName=default\nIsRelative=1\nPath=t.default\nDefault=1\n' \
		> "${ivan}"/snap/thunderbird/common/.thunderbird/profiles.ini
	printf '[Profile0]\nName=xdg\nIsRelative=1\nPath=x.default\nDefault=1\n' > "${ivan}"/.config/mozilla/firefox/profiles.ini
	printf '[Profile0]\nName=xdg\nIsRelative=1\nPath=y.default\nDefault=1\n' > "${ivan}"/.config/thunderbird/profiles.ini
	chown -R gina:gina "${gina}"
	chown -R ivan:ivan "${ivan}"

	## A G Unity⁷ Firefox that apt cannot install. The Release file has the
	##  checksums, so that apt-get update reads the changed Packages file.
	reindex() {
		(cd "${ppa}" && apt-ftparchive packages . > Packages 2>/dev/null \
			&& apt-ftparchive -o APT::FTPArchive::Release::Origin=LP-PPA-c4pp4-g-unity7 \
				-o APT::FTPArchive::Release::Suite=stonking release . > Release)
		apt-get update -qq 2>/dev/null
	}
	mkdeb "${ppa}" firefox 159.0.1-1+gu7.2~26.10 "Depends: libgtk-3-0t64-test-i386"
	reindex
	run "Firefox cannot be installed: --dry-run, Enter" bash -c "printf '\n' | ${cleanup} --dry-run"
	rm "${ppa}"/firefox_159.0.1-1+gu7.2~26.10_all.deb
	reindex

	run "dry-run: Enter, Enter" bash -c "printf '\n\n' | ${cleanup} --dry-run"
	run "--yes" "${cleanup}" --yes
	echo "-- snaps: $(ls /tmp/snaps | tr '\n' ' ')"
	files "${gina}"/.mozilla "${ivan}"/.mozilla "${ivan}"/.thunderbird "${ivan}"/.config
	echo "-- profiles.ini of gina"
	cat "${gina}"/.mozilla/firefox/profiles.ini
	echo "-- Firefox profiles.ini of ivan"
	cat "${ivan}"/.config/mozilla/firefox/profiles.ini
	echo

	## hank: a profile of the group has the name of one of his package profiles
	rm -rf "${gina}"/snap "${ivan}"/snap
	printf '159.0.1-1 6001\n' > /tmp/snaps/firefox
	mkdir -p "${hank}/${ffs}"/h.default "${hank}/${ffs}"/h.work "${hank}"/.mozilla/firefox/h.work
	echo 'user_pref("toolkit.profiles.storeID", "5e6f7a8b");' > "${hank}/${ffs}"/h.work/prefs.js
	printf '[Profile0]\nName=default\nIsRelative=1\nPath=h.default\nDefault=1\nStoreID=5e6f7a8b\nShowSelector=1\n' \
		> "${hank}/${ffs}"/profiles.ini
	printf '[Profile0]\nName=work\nIsRelative=1\nPath=h.work\nDefault=1\n' > "${hank}"/.mozilla/firefox/profiles.ini
	chown -R hank:hank "${hank}"
	run "a profile of the group has a taken name: --yes" "${cleanup}" --yes
	echo "-- snaps: $(ls /tmp/snaps | tr '\n' ' ')"
	files "${hank}"/.mozilla
}

## Snap profiles with links that point outside the profile of the user. The
##  copy runs as the user, so it fails and no snap is removed, and no file
##  outside the home directory changes.
group_links() {
	local mallory=/home/mallory snap_dir=/home/mallory/snap/firefox/common/.mozilla/firefox
	setup_mozilla
	useradd -m -u 1001 alice
	useradd -m -u 1003 mallory
	cp -a /etc/shadow /tmp/shadow.orig
	cp -a /root/.bashrc /tmp/bashrc.orig
	mkdir -p /home/alice/.mozilla/firefox/secret.default
	echo secret > /home/alice/.mozilla/firefox/secret.default/logins.json
	printf '[Profile0]\nName=default\nIsRelative=1\nPath=secret.default\nDefault=1\n' \
		> /home/alice/.mozilla/firefox/profiles.ini
	chown -R alice:alice /home/alice

	## A new snap profile of mallory, with the Firefox package not installed
	reset() {
		apt-get install -y -qq --allow-downgrades firefox=1:1snap1 >/dev/null 2>&1
		printf '159.0.1-1 6000\n' > /tmp/snaps/firefox
		cp -a /tmp/shadow.orig /etc/shadow
		cp -a /tmp/bashrc.orig /root/.bashrc
		chown root:root /etc
		rm -rf /etc/firefox /etc/profile.d/abc.default /etc/profile.d/profiles.ini \
			/etc/profile.d/evil.sh /etc-snap "${mallory}"/snap "${mallory}"/.mozilla
		mkdir -p "${snap_dir}"/abc.default
		echo prefs > "${snap_dir}"/abc.default/prefs.js
		printf '[Profile0]\nName=default\nIsRelative=1\nPath=abc.default\nDefault=1\n' > "${snap_dir}"/profiles.ini
	}
	## check <title>: run the cleanup with --yes and show what changed
	check() {
		chown -hR mallory:mallory "${mallory}"
		run "$1" "${cleanup}" --yes
		stat -c '%U:%G %a %n' /etc /etc/shadow /root/.bashrc
		cmp -s /etc/shadow /tmp/shadow.orig && echo "/etc/shadow unchanged" || echo "/etc/shadow CHANGED"
		cmp -s /root/.bashrc /tmp/bashrc.orig && echo "/root/.bashrc unchanged" || echo "/root/.bashrc CHANGED"
		ls -d /etc/firefox /etc/profile.d/evil.sh /etc-snap 2>/dev/null || true
		files "${mallory}"/.mozilla | grep -v -E '/(abc\.default|abc\.default-snap)/' || true
		echo "-- snaps: $(ls /tmp/snaps | tr '\n' ' ')"
		echo
	}

	reset
	ln -s /etc/shadow "${snap_dir}"/installs.ini
	check "installs.ini of the snap profile is a link to /etc/shadow"

	reset
	ln -s /etc "${mallory}"/.mozilla
	check "~/.mozilla is a link to /etc"

	reset
	mkdir -p "${mallory}"/.mozilla/firefox
	ln -s /root/.bashrc "${mallory}"/.mozilla/firefox/profiles.ini
	printf '[Profile0]\nName=x; touch /tmp/pwned;\nIsRelative=1\nPath=abc.default\nDefault=1\n' > "${snap_dir}"/profiles.ini
	check "~/.mozilla/firefox/profiles.ini is a link to /root/.bashrc"

	reset
	mkdir -p "${mallory}"/.mozilla
	ln -s /etc/profile.d "${mallory}"/.mozilla/firefox
	echo 'echo pwned' > "${snap_dir}"/evil.sh
	check "~/.mozilla/firefox is a link to /etc/profile.d"

	reset
	rm -rf "${snap_dir}"
	ln -s /home/alice/.mozilla/firefox "${snap_dir}"
	mkdir -p "${mallory}"/.mozilla/firefox
	check "the snap profile directory is a link to the profiles of alice"
	ls "${mallory}"/.mozilla/firefox

	reset
	mkdir -p "${mallory}"/.mozilla/firefox/own.default
	printf '[Profile0]\nName=own\nIsRelative=1\nPath=own.default\nDefault=1\n' > "${mallory}"/.mozilla/firefox/profiles.ini
	printf '[Profile0]\nName=up\nIsRelative=1\nPath=../../../../../../../../etc\n\n[Profile1]\nName=default\nIsRelative=1\nPath=abc.default\nDefault=1\n' \
		> "${snap_dir}"/profiles.ini
	check "a snap profile with the path ../../../../../../../../etc"
	echo "-- profiles.ini"
	cat "${mallory}"/.mozilla/firefox/profiles.ini
}

## Snaps that are not installed, and PulseAudio removed without its
##  configuration files
group_snaps() {
	local repo=${repos}/snaps units=/etc/systemd/system apps=/var/lib/snapd/desktop/applications
	mkdeb "${repo}" g-unity7-desktop 1+gu7.12
	tree=$(mktemp -d)
	mkdir -p "${tree}"/etc/xdg/autostart "${tree}"/DEBIAN
	printf '[Desktop Entry]\nExec=start-pulseaudio-x11\n' > "${tree}"/etc/xdg/autostart/pulseaudio.desktop
	echo /etc/xdg/autostart/pulseaudio.desktop > "${tree}"/DEBIAN/conffiles
	mkdeb "${repo}" pulseaudio 1
	rm -rf "${tree}"
	tree=
	index "${repo}"
	use_repositories "${repo}"
	apt-get install -y -qq g-unity7-desktop pulseaudio >/dev/null 2>&1
	apt-get remove -y -qq pulseaudio >/dev/null 2>&1
	state_packages=( g-unity7-desktop pulseaudio )

	printf '160.0-1 7000\n' > /tmp/snaps/firefox
	printf '20260101 2124\n20260601 2307\n' > /tmp/snaps/core24
	mkdir -p "${units}"/multi-user.target.wants "${units}"/snapd.mounts.target.wants \
		/var/lib/snapd/snaps "${apps}"
	touch /var/lib/snapd/snaps/core24_2307.snap /var/lib/snapd/snaps/core24_2124.snap
	## <unit> <snap> <revision>
	unit() {
		printf '[Mount]\nWhat=/var/lib/snapd/snaps/%s_%s.snap\nWhere=/snap/%s/%s\n' "$2" "$3" "$2" "$3" > "${units}/$1"
		ln -s "${units}/$1" "${units}"/snapd.mounts.target.wants/"$1"
		ln -s "${units}/$1" "${units}"/multi-user.target.wants/"$1"
	}
	## Not installed, no .snap: removed
	unit snap-firefox-9036.mount firefox 9036
	unit snap-thunderbird-1282.mount thunderbird 1282
	## Installed revisions, and one whose .snap is missing: kept
	unit snap-core24-2124.mount core24 2124
	unit snap-core24-2307.mount core24 2307
	unit snap-firefox-7000.mount firefox 7000
	## The .snap exists, but the revision is not installed: kept
	touch /var/lib/snapd/snaps/gnome-46-2404_168.snap
	unit snap-gnome-46-2404-168.mount gnome-46-2404 168
	touch "${apps}"/firefox_firefox.desktop "${apps}"/thunderbird_thunderbird.desktop

	touch /tmp/snap-list-fail
	run "snap list fails: --dry-run" "${cleanup}" --dry-run
	rm /tmp/snap-list-fail
	run "--dry-run" "${cleanup}" --dry-run
	run "--yes" "${cleanup}" --yes
	echo "-- units"
	find "${units}" -name 'snap-*' -printf '%P\n' | sort
	echo "-- desktop files"
	ls "${apps}"
	echo "-- systemctl"
	cat /tmp/systemctl.log
	echo "-- /etc/xdg/autostart"
	ls /etc/xdg/autostart 2>/dev/null || true
	echo
	run "again: --yes" "${cleanup}" --yes
}

## unattended-upgrades with the pins of g-unity7-apt-pin: Ubuntu publishes a
##  security update of a package that the PPA has, and the PPA then publishes
##  its rebuild, without and with 51g-unity7-unattended-upgrades
group_pin() {
	local ppa=${repos}/pin-ppa security=${repos}/pin-security conf=51g-unity7-unattended-upgrades
	apt-get install -y -qq --no-install-recommends unattended-upgrades >/dev/null 2>&1
	install -D -m 644 -t /etc/apt/preferences.d "${work}"/local/g-unity7-apt-pin/g-unity7.pref
	## release <repository> <origin> <suite>: index it with a Release file that
	##  has the checksums, so that apt-get update reads a changed Packages file
	release() {
		(cd "$1" && apt-ftparchive packages . > Packages 2>/dev/null \
			&& apt-ftparchive -o APT::FTPArchive::Release::Origin="$2" \
				-o APT::FTPArchive::Release::Suite="$3" release . > Release)
	}
	## uu <title>: run unattended-upgrades and show the installed version
	uu() {
		echo "### $1"
		unattended-upgrade >/dev/null 2>&1 || echo "[unattended-upgrade failed]"
		dpkg-query -W -f='foo ${Version}\n' foo
		echo
	}
	for with_conf in "" 1; do
		rm -rf "${ppa}" "${security}"
		mkdir -p "${security}"
		mkdeb "${ppa}" foo 1.0-0ubuntu1+gu7.2~26.10
		release "${ppa}" LP-PPA-c4pp4-g-unity7 stonking
		release "${security}" Ubuntu stonking-security
		use_repositories "${ppa}" "${security}"
		apt-get install -y -qq --allow-downgrades foo=1.0-0ubuntu1+gu7.2~26.10 >/dev/null 2>&1
		if [[ -n ${with_conf} ]]; then
			install -D -m 644 -t /etc/apt/apt.conf.d "${work}"/local/g-unity7-apt-pin/"${conf}"
			echo "## With ${conf}"
		else
			rm -f /etc/apt/apt.conf.d/"${conf}"
			echo "## Without ${conf}"
		fi
		echo
		mkdeb "${security}" foo 1.0-0ubuntu2
		release "${security}" Ubuntu stonking-security
		apt-get update -qq 2>/dev/null
		uu "Ubuntu has 1.0-0ubuntu2 in stonking-security, the PPA has no rebuild yet"
		mkdeb "${ppa}" foo 1.0-0ubuntu2+gu7.1~26.10
		release "${ppa}" LP-PPA-c4pp4-g-unity7 stonking
		apt-get update -qq 2>/dev/null
		uu "The PPA has its rebuild 1.0-0ubuntu2+gu7.1~26.10"
	done
}

## A new system: the Firefox and Thunderbird snaps that were never started have
##  no profiles to copy. Then Evolution instead of Thunderbird, without its snap
##  and its package.
group_scenarios() {
	setup_mozilla
	useradd -m -u 1001 jana
	printf '160.0.1-1 7000\n' > /tmp/snaps/firefox
	printf '161.0-1 900\n' > /tmp/snaps/thunderbird
	run "snaps that were never started: 1, 1, confirm" bash -c "printf '1\n1\ny\n' | ${cleanup}"
	echo "-- snaps: $(ls /tmp/snaps | tr '\n' ' ')"
	echo

	apt-get purge -y -qq thunderbird thunderbird-l10n-cs >/dev/null 2>&1
	mkdeb /tmp/evolution evolution 3.58.1-1
	dpkg -i /tmp/evolution/evolution_3.58.1-1_all.deb >/dev/null 2>&1
	run "Evolution instead of Thunderbird: --dry-run, Enter" bash -c "printf '\n' | ${cleanup} --dry-run"
}

setup_common
out=$(mktemp)
case ${group} in
	alternatives) group_alternatives ;;
	mozilla) group_mozilla ;;
	copies) group_copies ;;
	profiles) group_profiles ;;
	locations) group_locations ;;
	links) group_links ;;
	scenarios) group_scenarios ;;
	snaps) group_snaps ;;
	pin) group_pin ;;
	*) echo "test.sh: unknown group ${group}" >&2; exit 2 ;;
esac > "${out}"

if [[ -n ${update} ]]; then
	cp "${out}" "${expected}"
	echo "${group}: written to ${expected#"${work}"/}"
elif diff -u "${expected}" "${out}"; then
	echo "${group}: passed"
else
	echo "${group}: FAILED (expected ${expected#"${work}"/})" >&2
	exit 1
fi
