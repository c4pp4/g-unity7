#!/usr/bin/python3 -I
"""Read-only Launchpad queries for the G Unity⁷ scripts (anonymous web API)."""

import argparse
import datetime
import functools
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.launchpad.net/devel"

## Pockets of a stable series that the base version is taken from.
UBUNTU_POCKETS = ("Release", "Updates", "Security")


## The Launchpad proxy caches anonymous responses for minutes. Without
##  no-cache, the state right after an upload or a build would be missed.
HEADERS = {"Accept": "application/json", "Cache-Control": "no-cache"}


## Launchpad sometimes answers 503 or times out, so a request is tried again
##  after these pauses (in seconds). A 4xx error is final.
RETRY_PAUSES = (10, 30, 60)


def fetch(request):
    """Return the body of a request, trying again after a temporary error."""
    for pause in (*RETRY_PAUSES, None):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            if error.code < 500 and error.code != 429 or pause is None:
                raise
            reason = f"HTTP {error.code}"
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            if pause is None:
                raise
            reason = str(error)
        print(f"lp.py: {request.full_url}: {reason}, trying again in {pause} s", file=sys.stderr)
        time.sleep(pause)


def get(url, params=None):
    if params:
        url += "?" + urllib.parse.urlencode(params)
    return json.loads(fetch(urllib.request.Request(url, headers=HEADERS)))


def get_text(url):
    request = urllib.request.Request(url, headers={"Cache-Control": "no-cache"})
    return fetch(request).decode("utf-8", "replace")


def collection(url, params):
    data = get(url, params)
    while True:
        yield from data["entries"]
        if "next_collection_link" not in data:
            break
        data = get(data["next_collection_link"])


def version_cmp(a, b):
    if a == b:
        return 0
    lt = subprocess.run(["dpkg", "--compare-versions", a, "lt", b]).returncode == 0
    return -1 if lt else 1


def newest(entries):
    return max(entries, key=functools.cmp_to_key(
        lambda x, y: version_cmp(x["source_package_version"], y["source_package_version"])))


def published_sources(archive, source, series, statuses):
    params = {
        "ws.op": "getPublishedSources",
        "source_name": source,
        "exact_match": "true",
        "distro_series": f"{API}/ubuntu/{series}",
    }
    entries = []
    for status in statuses:
        entries += collection(archive, dict(params, status=status))
    return entries


def parse_changelog(text):
    """Return the G Unity⁷ data of the first changelog entry."""
    entry = re.split(r"\n(?=\S)", text.strip(), maxsplit=2)
    head = "\n".join(entry[:2])
    data = {"patches": {}}
    for key in ("Fingerprint", "Input"):
        match = re.search(rf"G-Unity7-{key}: (\S+)", head)
        if match:
            data[key.lower()] = match.group(1)
    in_patches = False
    for line in head.splitlines():
        if line.startswith("  * "):
            in_patches = line.startswith("  * Patches:")
        elif in_patches:
            match = re.match(r"\s+- (\S+) \[(\w+)\]$", line)
            if match:
                data["patches"][match.group(1)] = match.group(2)
    return data


def cmd_ubuntu_version(args):
    version, pocket = ubuntu_version(args.source, args.series, args.archive)
    if not version:
        sys.exit(f"lp.py: {args.source} is not published in {args.series}")
    print(version, pocket)


def ppa_latest(source, ppa, series):
    """Return the latest version in a PPA with its G Unity⁷ data, or {} if none."""
    owner, name = ppa.split("/")
    archive = f"{API}/~{owner}/+archive/ubuntu/{name}"
    try:
        entries = published_sources(archive, source, series, ["Pending", "Published"])
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        print(f"lp.py: PPA {ppa} not found", file=sys.stderr)
        entries = []
    result = {}
    if entries:
        entry = newest(entries)
        result = {
            "version": entry["source_package_version"],
            "status": entry["status"],
            "pocket": entry["pocket"],
            "self_link": entry["self_link"],
        }
        changelog_url = get(entry["self_link"], {"ws.op": "changelogUrl"})
        if changelog_url:
            result.update(parse_changelog(get_text(changelog_url)))
    return result


def ubuntu_version(source, series, archive=None):
    """Return (version, pocket) of the latest version in an Ubuntu series, or
    in the given PPA archive (owner/name, such as mozillateam/ppa)."""
    if archive:
        owner, name = archive.split("/")
        url = f"{API}/~{owner}/+archive/ubuntu/{name}"
    else:
        url = f"{API}/ubuntu/+archive/primary"
    entries = [e for e in published_sources(url, source, series, ["Published"])
               if e["pocket"] in UBUNTU_POCKETS]
    if not entries:
        return None, None
    entry = newest(entries)
    return entry["source_package_version"], entry["pocket"]


def cmd_ppa_latest(args):
    print(json.dumps(ppa_latest(args.source, args.ppa, args.series)))


## Launchpad build states.
BUILDING = ("Needs building", "Currently building", "Uploading build", "Gathering build output")
FAILED = ("Failed to build", "Chroot problem", "Failed to upload", "Cancelled build",
          "Build for superseded Source", "Cancelling build")
DEPWAIT_LIMIT = datetime.timedelta(hours=24)


def build_state(source_name, version, ppa, series):
    """Return the build state of a version in a PPA: ok (built, with the
    binaries published), building, failed or missing."""
    owner, name = ppa.split("/")
    archive = f"{API}/~{owner}/+archive/ubuntu/{name}"
    entries = [e for e in published_sources(archive, source_name, series, ["Pending", "Published"])
               if e["source_package_version"] == version]
    if not entries:
        return {"state": "missing"}
    source = entries[0]
    now = datetime.datetime.now(datetime.timezone.utc)
    builds = []
    state = "ok"
    for build in collection(source["self_link"], {"ws.op": "getBuilds"}):
        item = {key: build.get(key) for key in ("arch_tag", "buildstate", "web_link", "build_log_url")}
        builds.append(item)
        if build["buildstate"] in FAILED:
            state = "failed"
        elif build["buildstate"] == "Dependency wait":
            created = datetime.datetime.fromisoformat(build["datecreated"])
            if now - created > DEPWAIT_LIMIT:
                state = "failed"
            elif state != "failed":
                state = "building"
        elif build["buildstate"] != "Successfully built" and state != "failed":
            state = "building"
    if not builds and state == "ok":
        state = "building"
    if state == "ok":
        binaries = list(collection(source["self_link"], {"ws.op": "getPublishedBinaries"}))
        if source["status"] != "Published" or not binaries \
                or any(b["status"] != "Published" for b in binaries):
            state = "building"
    return {"state": state, "source_status": source["status"], "builds": builds}


def cmd_build_state(args):
    print(json.dumps(build_state(args.source, args.version, args.ppa, args.series)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(required=True)

    p = sub.add_parser("ubuntu-version", help="latest version in a stable Ubuntu series")
    p.add_argument("source")
    p.add_argument("--series", required=True)
    p.add_argument("--archive", help="a PPA (owner/name) instead of the Ubuntu archive")
    p.set_defaults(func=cmd_ubuntu_version)

    p = sub.add_parser("ppa-latest", help="latest version in a PPA with its fingerprint")
    p.add_argument("source")
    p.add_argument("--ppa", required=True)
    p.add_argument("--series", required=True)
    p.set_defaults(func=cmd_ppa_latest)

    p = sub.add_parser("build-state", help="build state of a version in a PPA")
    p.add_argument("source")
    p.add_argument("version")
    p.add_argument("--ppa", required=True)
    p.add_argument("--series", required=True)
    p.set_defaults(func=cmd_build_state)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
