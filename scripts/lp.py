#!/usr/bin/python3 -I
"""Read-only Launchpad and Debian archive queries for the G Unity⁷ scripts
(anonymous web APIs)."""

import argparse
import datetime
import functools
import http.client
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


## Launchpad sometimes answers 503, times out or breaks off a response, so a
##  request is tried again after these pauses (in seconds). A 4xx error is
##  final.
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
        except (urllib.error.URLError, http.client.HTTPException, TimeoutError, ConnectionError) as error:
            if pause is None:
                raise
            reason = f"{type(error).__name__}: {error}"
        print(f"lp.py: {request.full_url}: {reason}, trying again in {pause} s", file=sys.stderr)
        time.sleep(pause)


def get(url, params=None):
    """Return the JSON of a request, trying again after an incomplete answer."""
    if params:
        url += "?" + urllib.parse.urlencode(params)
    for pause in (*RETRY_PAUSES, None):
        body = fetch(urllib.request.Request(url, headers=HEADERS))
        try:
            return json.loads(body)
        except ValueError:
            if pause is None:
                raise
        print(f"lp.py: {url}: the answer is not valid JSON, trying again in {pause} s", file=sys.stderr)
        time.sleep(pause)


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
    """Compare two Debian versions as dpkg does: -1, 0 or 1. Versions that dpkg
    sorts the same, such as 26.10.2ubuntu and 26.10.2ubuntu0, are equal."""
    if a == b:
        return 0
    for op, result in (("lt", -1), ("gt", 1)):
        if subprocess.run(["dpkg", "--compare-versions", a, op, b]).returncode == 0:
            return result
    return 0


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


## An Ubuntu or Debian changelog entry that fixes security issues names a CVE,
##  or for Firefox and Thunderbird a Mozilla Foundation Security Advisory.
SECURITY_RE = re.compile(r"CVE-\d{4}-\d+|mfsa\d{4}-\d+", re.I)
## The entries after the G Unity⁷ entry that parse_changelog reads, enough to
##  reach the version in the main PPA
UPSTREAM_ENTRIES = 30


def parse_changelog(text):
    """Return the G Unity⁷ data of the first changelog entry (patches,
    fingerprint, input, and the Ubuntu or Debian version that it was built on,
    base), and the version of each following entry with whether it names a CVE
    or a Mozilla security advisory (upstream). Versions built before
    G-Unity7-Base have no base."""
    entry = re.split(r"\n(?=\S)", text.strip())
    head = entry[0]
    data = {"patches": {}, "upstream": []}
    for key in ("Fingerprint", "Input", "Base"):
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
    for item in entry[1:]:
        match = re.match(r"\S+ \(([^)\s]+)\)", item)
        if not match:
            continue
        data["upstream"].append([match.group(1), bool(SECURITY_RE.search(item))])
        if len(data["upstream"]) >= UPSTREAM_ENTRIES:
            break
    return data


def cmd_ubuntu_version(args):
    version, pocket = ubuntu_version(args.source, args.series)
    if not version:
        sys.exit(f"lp.py: {args.source} is not published in {args.series}")
    print(version, pocket)


def ppa_archive(ppa):
    owner, name = ppa.split("/")
    return f"{API}/~{owner}/+archive/ubuntu/{name}"


def publication(entry):
    """Return the fields of a source publication that the scripts use."""
    return {
        "version": entry["source_package_version"],
        "status": entry["status"],
        "pocket": entry["pocket"],
        "self_link": entry["self_link"],
    }


def changelog_data(entry):
    """Return the G Unity⁷ data of the changelog of a source publication (see
    parse_changelog), or {} if Launchpad has no changelog."""
    changelog_url = get(entry["self_link"], {"ws.op": "changelogUrl"})
    return parse_changelog(get_text(changelog_url)) if changelog_url else {}


def ppa_latest(source, ppa, series):
    """Return the latest version in a PPA with its G Unity⁷ data, or {} if none."""
    try:
        entries = published_sources(ppa_archive(ppa), source, series, ["Pending", "Published"])
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        print(f"lp.py: PPA {ppa} not found", file=sys.stderr)
        entries = []
    result = {}
    if entries:
        result = publication(newest(entries))
        result.update(changelog_data(result))
    return result


def ppa_sources(ppa, series):
    """Return the latest Pending or Published version of each source in a PPA
    series, {source: publication}. One listing instead of the queries for each
    source."""
    params = {"ws.op": "getPublishedSources", "distro_series": f"{API}/ubuntu/{series}",
              "ws.size": "300"}
    latest = {}
    try:
        for status in ("Pending", "Published"):
            for entry in collection(ppa_archive(ppa), dict(params, status=status)):
                name = entry["source_package_name"]
                if name not in latest or version_cmp(entry["source_package_version"],
                                                     latest[name]["source_package_version"]) > 0:
                    latest[name] = entry
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        print(f"lp.py: PPA {ppa} not found", file=sys.stderr)
    return {name: publication(entry) for name, entry in latest.items()}


def ppa_max_n(source, ppa, base, tag):
    """Return the highest N of the versions <base>+<tag>.<N>~<series version> of
    a source in a PPA in any series and state, also deleted, or 0. Launchpad
    refuses a version that the PPA had. N counts across the series, so that the
    version for a newer series is higher than for an older one with the same
    base (+gu7.1~27.04 would be lower than +gu7.7~26.10)."""
    params = {"ws.op": "getPublishedSources", "source_name": source, "exact_match": "true"}
    version_re = re.compile(rf"{re.escape(base)}\+{re.escape(tag)}\.(\d+)~[\d.]+")
    highest = 0
    try:
        for entry in collection(ppa_archive(ppa), params):
            match = version_re.fullmatch(entry["source_package_version"])
            if match:
                highest = max(highest, int(match.group(1)))
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
    return highest


def ubuntu_version(source, series):
    """Return (version, pocket) of the latest version in an Ubuntu series."""
    url = f"{API}/ubuntu/+archive/primary"
    entries = [e for e in published_sources(url, source, series, ["Published"])
               if e["pocket"] in UBUNTU_POCKETS]
    if not entries:
        return None, None
    entry = newest(entries)
    return entry["source_package_version"], entry["pocket"]


## Debian archive (ftp-master's madison), for ports with DEBIAN_SUITE.
MADISON = "https://api.ftp-master.debian.org/madison"
DEBIAN_SUITES = {"sid": "unstable", "unstable": "unstable", "experimental": "experimental"}
## Prereleases are not built. Debian uploaded Thunderbird betas to experimental.
PRERELEASE_RE = re.compile(r"~(a|b|rc)\d")


def debian_version(source, suites):
    """Return (version, suite) of the newest version of a source in the given
    Debian suites (sid, experimental), or (None, None)."""
    data = get(MADISON, {"package": source, "s": ",".join(DEBIAN_SUITES[s] for s in suites),
                         "a": "source", "f": "json"})
    found = []
    for item in data:
        for suite, versions in item.get(source, {}).items():
            found += [{"source_package_version": v, "suite": suite} for v in versions
                      if not PRERELEASE_RE.search(v)]
    if not found:
        return None, None
    entry = newest(found)
    return entry["source_package_version"], entry["suite"]


def cmd_debian_version(args):
    version, suite = debian_version(args.source, args.suite.split())
    if not version:
        sys.exit(f"lp.py: {args.source} is not in Debian {args.suite}")
    print(version, suite)


def cmd_ppa_latest(args):
    print(json.dumps(ppa_latest(args.source, args.ppa, args.series)))


def cmd_ppa_max_n(args):
    print(ppa_max_n(args.source, args.ppa, args.base, args.tag))


def cmd_ppa_sources(args):
    print(json.dumps({name: entry["version"] for name, entry in ppa_sources(args.ppa, args.series).items()}))


## Launchpad build states.
BUILDING = ("Needs building", "Currently building", "Uploading build", "Gathering build output")
FAILED = ("Failed to build", "Chroot problem", "Failed to upload", "Cancelled build",
          "Build for superseded Source", "Cancelling build")
DEPWAIT_LIMIT = datetime.timedelta(hours=24)


def build_state(source_name, version, ppa, series):
    """Return the build state of a version in a PPA (see build_state_of), or
    missing."""
    entries = [e for e in published_sources(ppa_archive(ppa), source_name, series, ["Pending", "Published"])
               if e["source_package_version"] == version]
    if not entries:
        return {"state": "missing"}
    return build_state_of(publication(entries[0]))


def build_state_of(source):
    """Return the build state of a source publication: ok (built, with the
    binaries published), building or failed."""
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
    p.set_defaults(func=cmd_ubuntu_version)

    p = sub.add_parser("debian-version", help="newest version in Debian suites")
    p.add_argument("source")
    p.add_argument("--suite", required=True, help="sid, experimental, or both separated by a space")
    p.set_defaults(func=cmd_debian_version)

    p = sub.add_parser("ppa-latest", help="latest version in a PPA with its fingerprint")
    p.add_argument("source")
    p.add_argument("--ppa", required=True)
    p.add_argument("--series", required=True)
    p.set_defaults(func=cmd_ppa_latest)

    p = sub.add_parser("ppa-sources", help="latest version of each source in a PPA series, as JSON")
    p.add_argument("--ppa", required=True)
    p.add_argument("--series", required=True)
    p.set_defaults(func=cmd_ppa_sources)

    p = sub.add_parser("ppa-max-n", help="highest N of a base version in a PPA, in any series and state")
    p.add_argument("source")
    p.add_argument("--ppa", required=True)
    p.add_argument("--base", required=True)
    p.add_argument("--tag", required=True)
    p.set_defaults(func=cmd_ppa_max_n)

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
