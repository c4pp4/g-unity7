#!/bin/bash
## Sign a source package built by build-source.sh and upload it to the
##  staging PPA.
##
## Usage: upload.sh [--series <series>] [--simulate] <package>
##
##  --simulate  sign and run dput without uploading
##
## Locally, the key stays in the gpg-agent outside the container:
##  scripts/run-local.sh --gpg scripts/upload.sh libunity

set -euo pipefail
source "$(dirname "$0")"/lib.sh

series=${SERIES[0]}
simulate=
while [[ $# -gt 0 ]]; do
	case $1 in
		--series) series=$2; shift 2 ;;
		--simulate) simulate=1; shift ;;
		-*) die "Unknown option: $1" ;;
		*) break ;;
	esac
done
[[ $# -eq 1 ]] || die "Usage: $0 [--series <series>] [--simulate] <package>"
pkg=$1
[[ -n ${GPG_KEY_ID} ]] || die "GPG_KEY_ID is not set (config.sh or environment)."

base_dir="${BUILD_DIR:-${REPO_ROOT}/build}/${series}/${pkg}"
[[ -f ${base_dir}/result.env ]] || die "Run build-source.sh ${pkg} first."
source "${base_dir}"/result.env
[[ ${STATUS} == built ]] || die "${pkg} was not built (${STATUS})."
changes="${base_dir}/${CHANGES}"
[[ -f ${changes} ]] || die "${changes} not found."

debsign_args=()
if [[ -n ${G_UNITY7_GPG_FORWARD:-} ]]; then
	## The agent forwarded by run-local.sh --gpg.
	GNUPGHOME=$(mktemp -d) || die "mktemp failed."
	export GNUPGHOME
	echo "no-autostart" > "${GNUPGHOME}"/gpg.conf
	ln -s /run/gpg-agent.extra "${GNUPGHOME}"/S.gpg-agent
	gpg --batch --quiet --import /run/gpg-pubkey.asc
elif [[ -n ${GPG_PRIVATE_KEY:-} ]]; then
	## CI: the signing subkey (gpg --export-secret-subkeys <subkey>!) and its
	##  passphrase come from the environment and are used with a loopback
	##  pinentry.
	GNUPGHOME=$(mktemp -d) || die "mktemp failed."
	export GNUPGHOME
	gpg --batch --quiet --import <<< "${GPG_PRIVATE_KEY}" || die "Cannot import GPG_PRIVATE_KEY."
	printf '%s' "${GPG_PASSPHRASE:-}" > "${GNUPGHOME}"/passphrase
	cat > "${GNUPGHOME}"/gpg-loopback <<-EOF
		#!/bin/sh
		exec gpg --batch --pinentry-mode loopback --passphrase-file "${GNUPGHOME}/passphrase" "\$@"
	EOF
	chmod 700 "${GNUPGHOME}"/gpg-loopback
	debsign_args+=( -p"${GNUPGHOME}"/gpg-loopback )
	trap 'rm -rf "${GNUPGHOME}"' EXIT
fi
gpg --batch --list-secret-keys "${GPG_KEY_ID}" >/dev/null 2>&1 \
	|| die "Secret key ${GPG_KEY_ID} is not available."

## The same version cannot be uploaded twice.
staging_version=$(python3 -I "${REPO_ROOT}"/scripts/lp.py ppa-latest "${SOURCE}" \
	--ppa "${PPA_STAGING}" --series "${series}" \
	| python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("version", ""))')
if [[ -n ${staging_version} ]] && dpkg --compare-versions "${VERSION}" le "${staging_version}"; then
	die "${PPA_STAGING} already has ${SOURCE} ${staging_version}, ${VERSION} is not newer."
fi

## A PPA source (SOURCE_ARCHIVE): copy its base version to staging first. The
##  copy brings the orig tarball, which the port is uploaded without, and
##  Launchpad marks it as a copy and shows the port's diff against it.
if [[ -n ${SOURCE_ARCHIVE:-} && -z ${simulate} ]]; then
	[[ -f ${LP_CREDENTIALS_FILE:-} ]] || die "LP_CREDENTIALS_FILE is needed to copy ${SOURCE} ${BASE_VERSION} from ppa:${SOURCE_ARCHIVE}."
	python3 -I "${REPO_ROOT}"/scripts/lp_write.py --credentials "${LP_CREDENTIALS_FILE}" copy-base \
		"${SOURCE}" "${BASE_VERSION}" --from "${SOURCE_ARCHIVE}" --to "${PPA_STAGING}" --series "${series}" >&2 \
		|| die "Cannot copy ${SOURCE} ${BASE_VERSION} from ppa:${SOURCE_ARCHIVE}."
fi

einfo "Signing ${changes##*/} with ${GPG_KEY_ID}"
debsign "${debsign_args[@]}" --re-sign -k"${GPG_KEY_ID}" "${changes}" >&2 || die "Signing failed."

dput_args=()
[[ -n ${simulate} ]] && dput_args+=( --simulate )
einfo "Uploading ${SOURCE} ${VERSION} to ppa:${PPA_STAGING}$([[ -n ${simulate} ]] && echo " (simulated)")"

## Launchpad's FTP server refuses files from uploads that follow each other
##  closely ("Upload permissions error"), so try again after a while. dput
##  reports success anyway, so check its output too. Stop a stalled transfer
##  after 10 min, because dput has no timeout.
for attempt in 1 2 3 4; do
	if timeout 600 dput --force "${dput_args[@]}" "ppa:${PPA_STAGING}" "${changes}" > "${base_dir}"/dput.log 2>&1 \
		&& ! grep -q "Upload permissions error\|Could not upload file" "${base_dir}"/dput.log; then
		cat "${base_dir}"/dput.log >&2
		break
	fi
	cat "${base_dir}"/dput.log >&2
	[[ ${attempt} -eq 4 ]] && die "Upload failed."
	ewarn "Upload refused; trying again in $(( attempt * 90 )) s."
	sleep $(( attempt * 90 ))
done

[[ -z ${simulate} ]] && echo "UPLOADED=$(date -u +%FT%TZ)" >> "${base_dir}"/result.env
einfo "Done. Launchpad sends the result to ${DEBEMAIL}."
