#!/bin/bash
## Run the tests of g-unity7-cleanup (test.sh), one container per group, with
##  podman or docker.
##
## Usage: tests/cleanup/run.sh [--update] [<group>...]
##
##  --update  write the outputs to tests/cleanup/expected/ instead of comparing
##            them; review the changes with git diff

set -euo pipefail
cd "$(dirname "$0")/../.."

update=
if [[ ${1:-} == --update ]]; then
	update=--update
	shift
fi
groups=( "$@" )
[[ ${#groups[@]} -gt 0 ]] || groups=( alternatives mozilla links snaps pin )
engine=$(command -v podman || command -v docker) || { echo "run.sh: podman or docker is needed" >&2; exit 1; }
mode=ro
[[ -z ${update} ]] || mode=rw

failed=()
for group in "${groups[@]}"; do
	"${engine}" run --rm -v "${PWD}:/work:${mode},Z" docker.io/library/ubuntu:26.10 \
		/work/tests/cleanup/test.sh ${update} "${group}" || failed+=( "${group}" )
done
if [[ ${#failed[@]} -gt 0 ]]; then
	echo "run.sh: failed: ${failed[*]}" >&2
	exit 1
fi
