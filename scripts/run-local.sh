#!/bin/bash
## Run a script in the Ubuntu build container (rootless podman), for example:
##  scripts/run-local.sh scripts/build-source.sh libunity
##
## Options before the command:
##  --rebuild  rebuild the container image first
##  --root     run as root in the container (to install build dependencies)
##  --gpg      forward the gpg-agent (extra socket) and the public key of
##             GPG_KEY_ID; the secret key stays outside the container
##  --shell    start an interactive shell instead of a command
##
## Environment:
##  OVERLAY_DIR  gentoo-unity7 checkout (default: ../gentoo-unity7)
##  BUILD_DIR    output directory, also outside the repository (default: build/,
##               which may be a symlink to another disk)

set -euo pipefail
source "$(dirname "$0")"/lib.sh

image="localhost/g-unity7-build:latest"
rebuild=
root=
gpg=
shell=
while [[ $# -gt 0 ]]; do
	case $1 in
		--rebuild) rebuild=1; shift ;;
		--root) root=1; shift ;;
		--gpg) gpg=1; shift ;;
		--shell) shell=1; shift ;;
		*) break ;;
	esac
done
[[ -n ${shell} || $# -gt 0 ]] || die "Usage: $0 [--rebuild] [--shell] <command> [args...]"

overlay=$(realpath "${OVERLAY_DIR:-${REPO_ROOT}/../gentoo-unity7}")

if [[ -n ${rebuild} ]] || ! podman image exists "${image}"; then
	einfo "Building ${image}"
	podman build --pull=newer -t "${image}" -f "${REPO_ROOT}"/Containerfile "${REPO_ROOT}"
fi

args=(
	--rm
	-v "${REPO_ROOT}:/work"
	-v "${overlay}:/overlay:ro"
	-e OVERLAY_DIR=/overlay
	-e HOME=/tmp
	-e DEBEMAIL="${DEBEMAIL}"
	-e DEBFULLNAME="${DEBFULLNAME}"
	-w /work
)
## The container sees only the repository and the overlay. Mount BUILD_DIR as
##  /build, and the target of a build/ symlink at the same path, so that the
##  link resolves in the container.
if [[ -n ${BUILD_DIR:-} ]]; then
	mkdir -p "${BUILD_DIR}"
	args+=( -v "$(realpath "${BUILD_DIR}"):/build" -e BUILD_DIR=/build )
elif [[ -L ${REPO_ROOT}/build ]]; then
	build_target=$(realpath "${REPO_ROOT}/build")
	[[ -d ${build_target} ]] || die "build/ links to ${build_target}, which is not a directory."
	args+=( -v "${build_target}:${build_target}" )
fi
## Root in a rootless container is the user outside, so files keep their owner.
[[ -n ${root} ]] || args+=( --userns=keep-id )
if [[ -n ${gpg} ]]; then
	[[ -n ${GPG_KEY_ID} ]] || die "GPG_KEY_ID is not set (config.sh or environment)."
	socket=$(gpgconf --list-dirs agent-extra-socket)
	gpg-connect-agent /bye >/dev/null 2>&1 || die "gpg-agent is not running."
	pubkey="${REPO_ROOT}/build/.gpg-pubkey.asc"
	mkdir -p "${REPO_ROOT}"/build
	gpg --batch --armor --export "${GPG_KEY_ID}" > "${pubkey}"
	[[ -s ${pubkey} ]] || die "Public key ${GPG_KEY_ID} not found."
	args+=(
		-v "${socket}:/run/gpg-agent.extra"
		-v "${pubkey}:/run/gpg-pubkey.asc:ro"
		-e G_UNITY7_GPG_FORWARD=1
		-e GPG_KEY_ID="${GPG_KEY_ID}"
	)
fi
if [[ -n ${shell} ]]; then
	exec podman run -it "${args[@]}" "${image}" bash
fi
[[ -t 1 ]] && args+=( -t )
exec podman run "${args[@]}" "${image}" "$@"
