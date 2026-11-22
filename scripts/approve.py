#!/usr/bin/python3 -I
"""Manage the G Unity⁷ approval issue: versions waiting for review before the
upload to the staging PPA, versions waiting for promotion to the main PPA,
builds that are behind Ubuntu and Debian, overlay and archive changes for the
ports, and the commands given in its comments.

Commands (in comments by the repository owner):
  /upload [<package>...]   upload the reviewed source packages to staging
  /reject <package>...     drop versions waiting for review
  /promote [<package>...] [--force] [--dry-run]
                           copy built versions from staging to the main PPA
  /retry <source> <version>
                           retry the failed builds of a version in staging
  /ported <name>...        record that the ports (or other items) of the
                           section with overlay changes were checked

Environment: GITHUB_TOKEN, GITHUB_REPOSITORY, OVERLAY_DIR (a checkout with the
history since the overlay commits in the state), LP_CREDENTIALS_FILE (for
/promote and /retry), and the GPG variables of upload.sh (for /upload).
"""

import argparse
import http.client
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import traceback
import urllib.error
import urllib.request
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lp  # noqa: E402

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPTS)
LABEL = "approve"
TITLE = "G Unity⁷ approvals"
STATE_RE = re.compile(r"<!-- g-unity7-state\n(.*?)\n-->", re.S)
## The format of the state in the issue body
STATE_VERSION = 1
## GitHub refuses an issue body of more than 65536 characters
BODY_WARN = 60000
## Pause between uploads (seconds).
UPLOAD_PAUSE = 60
## upload.sh tries dput four times with pauses. One try takes up to 10 min, plus
##  1 s per MB for the orig tarballs of Firefox and Thunderbird.
UPLOAD_TIMEOUT = 3 * 60 * 60
## GitHub stops a job after 6 hours. No upload starts after this many seconds
##  of an /upload command, so that the last one can finish and the issue is
##  saved.
UPLOAD_BUDGET = 6 * 60 * 60 - UPLOAD_TIMEOUT - 30 * 60
## Launchpad counts as down after this many packages in a row without a state.
##  The remaining packages also keep their rows from the last update.
LP_FAILURES_MAX = 3
LP_ERRORS = (urllib.error.URLError, http.client.HTTPException, TimeoutError, ConnectionError,
             ValueError)
## GitHub sometimes answers 5xx or times out, so a request is tried again after
##  these pauses (in seconds). A 4xx error is final. A POST, which could add a
##  second comment, is tried again only after a 502, 503 or 504.
GITHUB_PAUSES = (10, 30, 60)
STATE_ICONS = {"ok": "✅", "building": "⏳", "failed": "❌", "missing": "❔"}
## The groups in the order of /promote. The packages of a group in GROUP_NEEDS
##  depend on packages of another group: Firefox and Thunderbird need
##  g-unity7-apt-pin and the GTK of the desktop group.
GROUP_ORDER = ("desktop", "mozilla", "")
GROUP_NEEDS = {"mozilla": ("g-unity7-apt-pin", "gtk+3.0")}
## Copied last in its group: the metapackage depends on the other members
META = "g-unity7-meta"
## The ports were compared with the ebuilds and ehooks of the overlay on
##  2026-11-16 and follow its changes up to this commit. A port that has no
##  commit of its own in the state was checked against this one.
PORTED_BASE = "611f038323f8eb05c252c29105b88106815e7946"
OVERLAY_REPO = "c4pp4/gentoo-unity7"
## Seconds between two checks for changes of the overlay and the archive, and
##  how long a package is behind Ubuntu or Debian before the issue shows it
DRIFT_INTERVAL = 24 * 60 * 60
## GitHub disables the scheduled workflows of a public repository after 60
##  days without activity. The issue warns this many days after the last
##  commit.
INACTIVE_DAYS = 45


def config():
    """Return the variables of config.sh."""
    out = subprocess.run(
        ["bash", "-c", f'source "{REPO_ROOT}/config.sh"; '
         'echo "${SERIES[0]}"; echo "${PPA_STAGING}"; echo "${PPA_MAIN}"; echo "${VERSION_TAG}"'],
        check=True, capture_output=True, text=True).stdout.split("\n")
    return {"series": out[0], "staging": out[1], "main": out[2], "tag": out[3]}


CONFIG = config()


## GitHub API.

def github(method, path, data=None, raw=False):
    url = path if path.startswith("https://") else f"https://api.github.com{path}"
    for pause in (*GITHUB_PAUSES, None):
        request = urllib.request.Request(url, method=method,
                                         data=json.dumps(data).encode() if data is not None else None)
        request.add_unredirected_header("Authorization", f"Bearer {os.environ['GITHUB_TOKEN']}")
        request.add_header("Accept", "application/vnd.github+json")
        request.add_header("X-GitHub-Api-Version", "2022-11-28")
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                body = response.read()
            break
        except urllib.error.HTTPError as error:
            if error.code < 500 or pause is None or (method == "POST" and error.code not in (502, 503, 504)):
                raise
            reason = f"HTTP {error.code}"
        except (urllib.error.URLError, http.client.HTTPException, TimeoutError, ConnectionError) as error:
            if pause is None or method == "POST":
                raise
            reason = f"{type(error).__name__}: {error}"
        print(f"approve.py: {method} {url}: {reason}, trying again in {pause} s", file=sys.stderr)
        time.sleep(pause)
    if raw:
        return body
    return json.loads(body) if body else None


def repo():
    return os.environ["GITHUB_REPOSITORY"]


def find_issue():
    """The approval issue is the oldest issue with the label."""
    issues = [i for i in github("GET", f"/repos/{repo()}/issues?labels={LABEL}&state=all&per_page=100")
              if "pull_request" not in i]
    return min(issues, key=lambda i: i["number"]) if issues else None


def load_state(issue):
    state = {}
    if issue and issue.get("body"):
        match = STATE_RE.search(issue["body"])
        if match:
            try:
                state = json.loads(match.group(1))
            except ValueError as error:
                sys.exit(f"approve.py: the state in the body of issue #{issue['number']} is not valid "
                         f"JSON ({error}); repair the body")
    if state.get("version", STATE_VERSION) > STATE_VERSION:
        sys.exit("approve.py: a newer approve.py wrote the state of the issue")
    state["version"] = STATE_VERSION
    for key in ("review", "rejected", "uptodate", "promote", "seen", "ported", "drift", "behind",
                "failed_builds"):
        state.setdefault(key, {})
    state.setdefault("stale", [])
    state.setdefault("drift_checked", "")
    state.setdefault("inactive_days", 0)
    return state


def comment(issue, text):
    github("POST", f"/repos/{repo()}/issues/{issue['number']}/comments", {"body": text})


## Packages and Launchpad.

def packages():
    out = subprocess.run([f"{SCRIPTS}/packages.sh", "--input", overlay_dir()],
                         check=True, capture_output=True, text=True).stdout
    return {p["name"]: p for p in json.loads(out)}


def newer(a, b):
    return not b or lp.version_cmp(a, b) > 0


def utc_now():
    """The time as GitHub writes it, which compares as text."""
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def seconds_since(text):
    """Return the seconds since a time written by utc_now."""
    then = time.mktime(time.strptime(text, "%Y-%m-%dT%H:%M:%SZ"))
    return time.mktime(time.gmtime()) - then


def base_of(version):
    return re.sub(rf"\+{re.escape(CONFIG['tag'])}\.\d+~[\d.]+$", "", version)


def describe_changes(new, old):
    """Describe the patch changes between new and old ({name: hash})."""
    if not old:
        return "new package"
    changes = []
    for verb, names in (("added", [n for n in new if n not in old]),
                        ("updated", [n for n in new if n in old and old[n] != new[n]]),
                        ("removed", [n for n in old if n not in new])):
        if names:
            changes.append(f"{verb}: {', '.join(names)}")
    return "; ".join(changes)


def waiting_groups(state, pkgs):
    """Return the members of each group that still wait for review. A group is
    not complete in staging until they are uploaded or rejected."""
    groups = {}
    for name in state["review"]:
        group = pkgs.get(name, {}).get("group")
        if group:
            groups.setdefault(group, []).append(name)
    return groups


def promote_rows(pkgs, old=None):
    """Return the rows of the packages whose staging version is newer than in
    the main PPA, and the names of the packages that Launchpad gave no state
    for. A row from the last update (old) with the same versions is kept
    without queries once its build is ✅, before that only its build state is
    queried. Without old, a Launchpad error is raised. With it, a package keeps
    its row. A kept row gets the group and source of package.sh, which may have
    changed."""
    series = CONFIG["series"]
    old_rows = old or {}
    rows, stale = {}, []
    try:
        staging_list = lp.ppa_sources(CONFIG["staging"], series)
        main_list = lp.ppa_sources(CONFIG["main"], series)
    except LP_ERRORS:
        if old is None:
            raise
        traceback.print_exc()
        return {name: kept(row, pkgs.get(name)) for name, row in old_rows.items()}, sorted(pkgs)
    failures = 0
    for name, pkg in pkgs.items():
        staging = staging_list.get(pkg["source"])
        main = main_list.get(pkg["source"], {})
        if not staging or (main and not newer(staging["version"], main["version"])):
            continue
        prev = old_rows.get(name)
        if not (prev and prev["staging"] == staging["version"]
                and prev["main"] == main.get("version", "")):
            prev = None
        if prev and prev["state"] == "ok":
            rows[name] = kept(prev, pkg)
            continue
        if old is not None and failures >= LP_FAILURES_MAX:
            if name in old_rows:
                rows[name] = kept(old_rows[name], pkg)
            stale.append(name)
            continue
        try:
            rows[name] = promote_row(pkg, staging, main, prev)
            failures = 0
        except LP_ERRORS:
            if old is None:
                raise
            traceback.print_exc()
            failures += 1
            if name in old_rows:
                rows[name] = kept(old_rows[name], pkg)
            stale.append(name)
    return rows, stale


def kept(row, pkg):
    """Return a row from the last update with the group and source of the
    package now."""
    return dict(row, group=pkg["group"], source=pkg["source"]) if pkg else row


def security_fix(upstream, since):
    """Return whether one of the Ubuntu or Debian changelog entries (upstream,
    newest first, from lp.parse_changelog) that are newer than version since
    names a CVE or a Mozilla security advisory."""
    for version, security in upstream:
        if version == since or lp.version_cmp(version, since) <= 0:
            return False
        if security:
            return True
    return False


def promote_row(pkg, staging, main, prev=None):
    """Return the row of a package whose staging version (a publication from
    lp.ppa_sources) is newer than in the main PPA (a publication, or {}). The
    changes of a row with the same versions from the last update (prev) are
    kept, and only the build state is queried."""
    state = lp.build_state_of(staging)
    if prev:
        changes, security = prev["changes"], prev["security"]
    else:
        data = lp.changelog_data(staging)
        main_data = lp.changelog_data(main) if main else {}
        changes = describe_changes(data.get("patches", {}), main_data.get("patches")) if main else "new package"
        if main and not changes:
            if base_of(staging["version"]) != base_of(main["version"]):
                changes = "rebased on " + base_of(staging["version"])
            else:
                changes = "rebuild"
        security = bool(main) and security_fix(data.get("upstream", []), base_of(main["version"]))
    return {
        "source": pkg["source"],
        "group": pkg["group"],
        "staging": staging["version"],
        "main": main.get("version", ""),
        "state": state["state"],
        "builds": [b for b in state.get("builds", [])
                   if b["buildstate"] != "Successfully built"],
        "changes": changes,
        "security": security,
    }


## Overlay and archive changes that the ports may need (drift).

def overlay_dir():
    return os.environ.get("OVERLAY_DIR", os.path.join(REPO_ROOT, "..", "gentoo-unity7"))


def overlay_git(*args):
    return subprocess.run(["git", "-c", "safe.directory=*", "-C", overlay_dir(), *args],
                          check=True, capture_output=True, text=True).stdout


def overlay_head():
    """Return the commit of the overlay checkout."""
    return overlay_git("rev-parse", "HEAD").strip()


def port_pattern(overlay_pkg, variants=()):
    """Return the regular expression for the overlay files that a port follows
    by hand: those of its ebuild directory, or of its ehooks directory with the
    versioned ones (firefox-160:rapid for firefox:rapid), but not files/, which
    the input hash covers, Manifest and metadata.xml. The patches in files/
    that the port replaces with a variant of its own (variants) are followed
    too: a change of them changes the input hash, but the build with the
    variant finds the staging version up to date."""
    name, _, slot = overlay_pkg.partition(":")
    slot = f":{slot}" if slot else ""
    if name.startswith("ehooks/"):
        directory = rf"{re.escape(name)}(-[0-9][0-9.]*)?{re.escape(slot)}/"
        rest = r"(?!files/)"
    else:
        directory = rf"{re.escape(name)}/"
        rest = r"(?!files/|Manifest$|metadata\.xml$)"
    if variants:
        rest = rf"(?:{rest}|files/(?:{'|'.join(re.escape(v) for v in variants)})$)"
    return re.compile(directory + rest)


def follow_patterns(pkg):
    """Return the regular expressions of the overlay files that a package
    follows: those of its overlay package with the variants of its patches,
    and those of the overlay packages in OVERLAY_FOLLOW."""
    patterns = []
    if pkg.get("overlay_pkg"):
        patterns.append(port_pattern(pkg["overlay_pkg"], pkg.get("variants", ())))
    patterns += [port_pattern(name) for name in pkg.get("follow", ())]
    return patterns


def overlay_changes(base, head):
    """Return the files that the overlay changed from commit base to head, with
    both names of a renamed file, and the link to the comparison. The overlay
    checkout needs the history since base. The compare API of GitHub would list
    at most 300 files."""
    out = overlay_git("diff", "--name-only", "--no-renames", "-z", base, head)
    return [f for f in out.split("\0") if f], f"https://github.com/{OVERLAY_REPO}/compare/{base}...{head}"


def overlay_new_dirs(base, head):
    """Return the package directories that the overlay added from commit base
    to head: category/package with an ebuild, or the ehooks directory of a
    package."""
    out = overlay_git("diff", "--name-only", "--diff-filter=A", "-z", base, head)
    dirs = set()
    for path in filter(None, out.split("\0")):
        parts = path.split("/")
        if parts[0] == "ehooks" and len(parts) >= 4:
            dirs.add("/".join(parts[:3]))
        elif len(parts) == 3 and parts[2].endswith(".ebuild"):
            dirs.add("/".join(parts[:2]))
    return sorted(d for d in dirs if subprocess.run(
        ["git", "-c", "safe.directory=*", "-C", overlay_dir(), "cat-file", "-e", f"{base}:{d}"],
        capture_output=True).returncode)


def check_drift(state, pkgs):
    """Find what may need a change of the ports: overlay changes of the ebuilds,
    ehooks and eclasses that they follow since they were last checked, new
    packages of the overlay that no port follows, a new version of the seeds of
    Ubuntu Unity (ubuntu-unity-meta), a source of the archive with the name of a
    derived source, and a source from an older series that is back in the
    series (not for a derived source, such as unity-docs from the ubuntu-docs of
    an older series). Items checked with /ported (state["ported"]) are left out
    until they change again. Then find the ports that are behind Ubuntu and
    Debian."""
    series = CONFIG["series"]
    ported = state["ported"]
    head = overlay_head()
    drift = {}
    followed = {name: follow_patterns(pkg) for name, pkg in pkgs.items()}
    followed = {name: patterns for name, patterns in followed.items() if patterns}
    followed["eclass"] = [re.compile(r"eclass/")]
    by_base = {}
    for name in followed:
        by_base.setdefault(ported.get(name, PORTED_BASE), []).append(name)
    for base, names in sorted(by_base.items()):
        if base == head:
            continue
        files, url = overlay_changes(base, head)
        for name in sorted(names):
            changed = [f for f in files if any(p.match(f) for p in followed[name])]
            if not changed:
                continue
            shown = ", ".join(f"`{f}`" for f in changed[:5]) + (", …" if len(changed) > 5 else "")
            count = f"{len(changed)} file" + ("s" if len(changed) > 1 else "")
            drift[name] = {"value": head, "text": f"[{count} since `{base[:7]}`]({url}): {shown}"}

    base = ported.get("overlay:new", PORTED_BASE)
    if base != head:
        patterns = [p for name in followed for p in followed[name]]
        new = [d for d in overlay_new_dirs(base, head) if not any(p.match(d + "/") for p in patterns)]
        if new:
            shown = ", ".join(f"`{d}`" for d in new[:10]) + (", …" if len(new) > 10 else "")
            drift["overlay:new"] = {"value": head,
                                    "text": f"packages added since `{base[:7]}` that no port follows: {shown}"}

    seeds, _ = lp.ubuntu_version("ubuntu-unity-meta", series)
    if seeds:
        checked = ported.setdefault("ubuntu-unity-meta", seeds)
        if seeds != checked:
            drift["ubuntu-unity-meta"] = {
                "value": seeds,
                "text": f"`{seeds}` instead of `{checked}`: compare its seeds (desktop, "
                        "desktop-recommends) with `g-unity7-desktop`"}

    for name, pkg in sorted(pkgs.items()):
        found = []
        if pkg["derived"]:
            version, _ = lp.ubuntu_version(pkg["source"], series)
            if version:
                found.append(f"Ubuntu has a source `{pkg['source']}` (`{version}`), the name of this derived source")
        if pkg["older"] and not pkg["derived"]:
            version, _ = lp.ubuntu_version(pkg["ubuntu_src"], series)
            if version:
                found.append(f"{series} has `{pkg['ubuntu_src']}` again (`{version}`), UBUNTU_SERIES may go")
        key = f"archive:{name}"
        value = "; ".join(found)
        if value and ported.get(key) != value:
            drift[key] = {"value": value, "text": value}
    state["drift"] = drift
    check_behind(state, pkgs)


def archive_base(pkg):
    """Return the Ubuntu or Debian version that plan.sh builds a port on, or
    None."""
    if pkg.get("debian_suite"):
        version, _ = lp.debian_version(pkg["ubuntu_src"], pkg["debian_suite"].split())
    else:
        version, _ = lp.ubuntu_version(pkg["ubuntu_src"], pkg.get("ubuntu_series") or CONFIG["series"])
    return version


def check_behind(state, pkgs):
    """Find the ports whose staging version is older than the Ubuntu or Debian
    version that they are built on, except those that wait for review or were
    rejected with that version. An item keeps the time when it was first
    found. Drop the up-to-date entries whose version staging no longer has,
    which plan.sh does not use."""
    staging = lp.ppa_sources(CONFIG["staging"], CONFIG["series"])
    for name in list(state["uptodate"]):
        current = staging.get(pkgs.get(name, {}).get("source", name))
        if not current or current["version"] != state["uptodate"][name]["version"]:
            del state["uptodate"][name]
    behind = {}
    for name, pkg in sorted(pkgs.items()):
        current = staging.get(pkg["source"])
        if pkg.get("local") or not pkg.get("ubuntu_src") or not current:
            continue
        base = archive_base(pkg)
        if not base or not newer(base, base_of(current["version"])):
            continue
        if any(state[section].get(name, {}).get("base") == base for section in ("review", "rejected")):
            continue
        behind[name] = {"base": base, "staging": current["version"], "hold": pkg.get("hold", ""),
                        "since": state["behind"].get(name, {}).get("since") or utc_now()}
    state["behind"] = behind


def drift_due(state):
    """Return whether the last check for drift is older than DRIFT_INTERVAL."""
    checked = state.get("drift_checked")
    return not checked or seconds_since(checked) >= DRIFT_INTERVAL


def behind_rows(state):
    """Return the lines about the packages whose last build in ppa.yml failed,
    and about those that are behind Ubuntu or Debian for longer than a day."""
    rows = []
    for name, item in sorted(state["failed_builds"].items()):
        run = f"https://github.com/{repo()}/actions/runs/{item['run_id']}"
        rows.append(f"- `{name}`: the build in `ppa.yml` failed ([run]({run})), first on {item['since'][:10]}.")
    for name, item in sorted(state["behind"].items()):
        if name in state["failed_builds"] or seconds_since(item["since"]) < DRIFT_INTERVAL:
            continue
        held = f" `HOLD`: {item['hold']}" if item.get("hold") else ""
        rows.append(f"- `{name}`: `{item['base']}` since {item['since'][:10]}, staging has "
                    f"`{item['staging']}`.{held}")
    return rows


def last_commit_time():
    """Return the time of the last commit of the repository checkout, or None."""
    out = subprocess.run(["git", "-c", "safe.directory=*", "-C", REPO_ROOT, "log", "-1", "--format=%ct"],
                         capture_output=True, text=True).stdout.strip()
    return int(out) if out.isdigit() else None


## The issue body.

def render(state, pkgs=None):
    data = json.dumps(state, ensure_ascii=False, separators=(",", ":"))
    out = [f"<!-- g-unity7-state\n{data}\n-->", ""]
    out += ["G Unity⁷ packages waiting for the owner's decision. The `review.yml` workflow "
            "updates the tables a few times a day and after each command. Give commands in "
            "comments.", ""]

    out += ["## Review before upload", ""]
    if state["review"]:
        out += ["| Package | Version | Reason | Review |", "|---|---|---|---|"]
        for name, r in sorted(state["review"].items()):
            run = f"https://github.com/{repo()}/actions/runs/{r['run_id']}"
            out.append(f"| `{name}` | `{r['version']}` | {r['reason']} | "
                       f"[run summary]({run}) · artifact `{r['artifact']}` |")
        out += ["", "`/upload` uploads all of them to staging, and `/upload <package>…` only the "
                "given ones. `/reject <package>…` drops the version.", ""]
    else:
        out += ["Nothing is waiting.", ""]

    out += ["## Waiting for promotion", ""]
    waiting = waiting_groups(state, pkgs or {})
    if state["promote"]:
        ## One table per group. Versions do not wrap, and a single version
        ##  column leaves room for the package and its changes
        groups = {}
        for name, r in state["promote"].items():
            groups.setdefault(r["group"], []).append(name)
        for group in sorted(groups, key=lambda g: g or "~"):
            out += [f"### Group `{group}`" if group else "### Without a group", ""]
            if group in waiting:
                out += [f"Still waiting for review in this group: {', '.join(f'`{n}`' for n in waiting[group])}.", ""]
            out += ["| Package | Staging<br>Main PPA | Build | Changes |", "|---|---|---|---|"]
            for name in sorted(groups[group]):
                r = state["promote"][name]
                lock = " 🔒" if r["security"] else ""
                main = f"`{r['main']}`" if r["main"] else "–"
                out.append(f"| `{name}`{lock} | `{r['staging']}`<br>{main} | "
                           f"{STATE_ICONS[r['state']]} | {r['changes']} |")
            out.append("")
        out += ["✅ built and published, ⏳ building, ❌ failed, 🔒 security fixes (the changelog "
                "names a CVE or a Mozilla security advisory since the version in the main PPA). "
                "`/promote` copies the ✅ versions to the main PPA, a group only when all its "
                "members are ✅ and none waits for review, in the order desktop, mozilla, then the "
                "packages without a group. `/promote <package>…` copies only the given ones, "
                "`--force` also from an incomplete group, and `--dry-run` only shows what it would "
                "copy.", ""]
        if state["stale"]:
            out += [f"Launchpad did not answer for {len(state['stale'])} packages. "
                    "Their rows are from the last update.", ""]
        failed = [(n, r) for n, r in sorted(state["promote"].items()) if r["state"] == "failed"]
        if failed:
            out += ["### Failed builds", ""]
            for name, r in failed:
                logs = ", ".join(f"[{b['arch_tag']}: {b['buildstate']}]({b['web_link']})"
                                 for b in r["builds"])
                out.append(f"- `{name}` `{r['staging']}`: {logs}. "
                           f"Retry: `/retry {r['source']} {r['staging']}`")
            out.append("")
        out += ["<details><summary>Testing in a VM before promotion</summary>", "",
                "```sh", f"sudo add-apt-repository ppa:{CONFIG['staging']}",
                "sudo apt full-upgrade", "# test", "sudo apt install ppa-purge",
                f"sudo ppa-purge ppa:{CONFIG['staging']}", "```", "</details>", ""]
    else:
        out += ["Nothing is waiting.", ""]

    out += ["## Behind Ubuntu and Debian", ""]
    rows = behind_rows(state)
    if rows:
        out += rows + ["", "`ppa.yml` builds a new Ubuntu or Debian version on the next day. These "
                       "packages are still behind after a day, or their last build failed. Check "
                       "the run log, `HOLD` in `package.sh`, or the port.", ""]
    else:
        out += ["Nothing is behind.", ""]

    out += ["## Overlay and archive changes to check", ""]
    if state["drift"]:
        for name, item in sorted(state["drift"].items()):
            out.append(f"- `{name}`: {item['text']}")
        out += ["", "After checking an item, and changing the port if needed, `/ported <name>…` "
                "records it; `/ported all` records all of them.", ""]
    else:
        out += ["Nothing to check.", ""]

    if state["inactive_days"] >= INACTIVE_DAYS:
        out += ["## Scheduled workflows", "",
                f"The last commit is {state['inactive_days']} days old. GitHub disables the "
                "scheduled workflows of a public repository after 60 days without activity. Push "
                "a commit to keep `ppa.yml` and `review.yml` running.", ""]
    return "\n".join(out)


def save(issue, state, pkgs=None):
    """Write the state to the issue, and create, close or reopen it."""
    body = render(state, pkgs)
    if len(body) > BODY_WARN:
        print(f"::warning::The issue body has {len(body)} characters; GitHub refuses more than 65536.")
    waiting = bool(state["review"] or state["promote"] or state["drift"] or behind_rows(state)
                   or state["inactive_days"] >= INACTIVE_DAYS)
    if not issue:
        if not waiting:
            return None
        issue = github("POST", f"/repos/{repo()}/issues",
                       {"title": TITLE, "body": body, "labels": [LABEL]})
        return issue
    update = {"title": TITLE, "body": body, "state": "open" if waiting else "closed"}
    return github("PATCH", f"/repos/{repo()}/issues/{issue['number']}", update)


def notify_new(issue, state, commit_time=None):
    """Comment on the versions that appeared since the last refresh, and once
    when the last commit gets old."""
    new = []
    for section in ("review", "promote"):
        for name, r in state[section].items():
            version = r.get("version") or r.get("staging")
            key = f"{section}:{name}"
            if state["seen"].get(key) != version:
                where = "for review" if section == "review" else "for promotion"
                new.append(f"- `{name}` `{version}` {where}"
                           + (" 🔒" if r.get("security") else ""))
                state["seen"][key] = version
    for key in list(state["seen"]):
        section, name = key.split(":", 1)
        if name not in state[section]:
            del state["seen"][key]
    if new and issue:
        comment(issue, "New versions:\n" + "\n".join(new))
    if issue and state["inactive_days"] >= INACTIVE_DAYS and state.get("inactive_warned") != commit_time:
        comment(issue, f"The last commit is {state['inactive_days']} days old. GitHub disables the "
                       "scheduled workflows after 60 days without activity. Push a commit to keep "
                       "them running.")
        state["inactive_warned"] = commit_time


def refresh(issue, state, pkgs=None):
    pkgs = pkgs or packages()
    state["promote"], state["stale"] = promote_rows(pkgs, state["promote"])
    ## A build that failed is retried every day, except for a held package
    for name in list(state["failed_builds"]):
        if name not in pkgs or pkgs[name].get("hold"):
            del state["failed_builds"][name]
    if drift_due(state):
        try:
            check_drift(state, pkgs)
            state["drift_checked"] = utc_now()
        except (*LP_ERRORS, subprocess.CalledProcessError):
            traceback.print_exc()
            print("::warning::The check for overlay and archive changes failed. "
                  "The section keeps the items of the last check.")
    if state["stale"]:
        print(f"::warning::Launchpad gave no state for {len(state['stale'])} packages. "
              "They keep their rows from the last update.")
    commit_time = last_commit_time()
    state["inactive_days"] = int((time.time() - commit_time) // 86400) if commit_time else 0
    issue = save(issue, state, pkgs)
    notify_new(issue, state, commit_time)
    return save(issue, state, pkgs)


## Commands.

def read_result(path):
    result = {}
    with open(path) as f:
        for line in f:
            key, _, value = line.rstrip("\n").partition("=")
            result[key] = value
    return result


def build_conclusions(run_id):
    """Return the conclusion of the build job of each package in a ppa.yml run."""
    conclusions, page = {}, 1
    while True:
        data = github("GET", f"/repos/{repo()}/actions/runs/{run_id}/jobs?per_page=100&page={page}")
        for job in data["jobs"]:
            match = re.fullmatch(r"build \((.+)\)", job["name"])
            if match:
                conclusions[match.group(1)] = job["conclusion"]
        if len(data["jobs"]) < 100:
            return conclusions
        page += 1


def cmd_add_review(args):
    """Record the builds of a ppa.yml run: the planned packages whose build job
    failed (--planned), and the built versions that need review (build
    directories). A build that found the staging version up to date (the same
    fingerprint, but another input hash, such as after a comment change in
    package.sh) is only remembered, so that plan.sh does not build it again
    every day."""
    issue = find_issue()
    state = load_state(issue)
    planned = json.loads(args.planned) if args.planned else []
    if planned:
        conclusions = build_conclusions(args.run_id)
        for name in planned:
            if conclusions.get(name) in ("failure", "timed_out"):
                since = state["failed_builds"].get(name, {}).get("since") or utc_now()
                state["failed_builds"][name] = {"run_id": args.run_id, "since": since}
            elif conclusions.get(name) == "success":
                state["failed_builds"].pop(name, None)
    for directory in args.dirs:
        name = os.path.basename(directory.rstrip("/"))
        result = read_result(os.path.join(directory, "result.env"))
        if result.get("STATUS") == "uptodate":
            state["uptodate"][name] = {
                "version": result["VERSION"],
                "base": base_of(result["VERSION"]),
                "input": result["INPUT"],
            }
            ## A version that waits for review was built from another input
            state["review"].pop(name, None)
            continue
        state["uptodate"].pop(name, None)
        with open(os.path.join(directory, "patches.txt")) as f:
            new = dict(line.split(" ", 1) for line in f.read().split("\n") if line)
        staging = lp.ppa_latest(result["SOURCE"], CONFIG["staging"], CONFIG["series"])
        reason = describe_changes(new, staging.get("patches")) if staging else "new package"
        state["review"][name] = {
            "source": result["SOURCE"],
            "version": result["VERSION"],
            "base": base_of(result["VERSION"]),
            "fingerprint": result["FINGERPRINT"],
            "input": result["INPUT"],
            "run_id": args.run_id,
            "artifact": args.artifact_prefix + name,
            "reason": reason or "change outside the patches",
            "added": utc_now(),
        }
        state["rejected"].pop(name, None)
    refresh(issue, state)


def download_artifact(run_id, name, target):
    artifacts = github("GET", f"/repos/{repo()}/actions/runs/{run_id}/artifacts?per_page=100")
    for artifact in artifacts["artifacts"]:
        if artifact["name"] == name and not artifact["expired"]:
            data = github("GET", artifact["archive_download_url"], raw=True)
            zipfile.ZipFile(io.BytesIO(data)).extractall(target)
            return True
    return False


def command_time():
    """Return the time of the comment with the command, or None."""
    path = os.environ.get("GITHUB_EVENT_PATH")
    if not path:
        return None
    try:
        with open(path) as f:
            event = json.load(f)
    except (OSError, ValueError):
        return None
    return (event.get("comment") or {}).get("created_at")


def rebuild_hint(name):
    """Return the command that builds a version for review again."""
    return f"`gh workflow run ppa.yml -f packages={name} -f force=true`"


def do_upload(issue, state, names, pkgs, before=None):
    """Upload the given versions, or without names those that were added for
    review before the command (before), which the owner could see."""
    messages = []
    started = time.monotonic()
    if not names:
        names = sorted(n for n, r in state["review"].items() if not before or r.get("added", "") <= before)
        messages += [f"- `{n}`: added for review after the command. Check it and give the command again."
                     for n, r in sorted(state["review"].items()) if before and r.get("added", "") > before]
    for index, name in enumerate(names):
        r = state["review"].get(name)
        if not r:
            messages.append(f"- `{name}`: not waiting for review.")
            continue
        if name not in pkgs or pkgs[name]["input"] != r["input"]:
            messages.append(f"- `{name}`: the port or the overlay changed after the review. "
                            f"Build it again (`gh workflow run ppa.yml -f packages={name}`).")
            continue
        if time.monotonic() - started > UPLOAD_BUDGET:
            messages.append(f"- `{name}`: not uploaded, because the job would run longer than GitHub "
                            "allows. Give the command again.")
            continue
        try:
            staging = lp.ppa_latest(r["source"], CONFIG["staging"], CONFIG["series"])
            if staging and not newer(r["version"], staging["version"]):
                messages.append(f"- `{name}`: staging already has `{staging['version']}`.")
                del state["review"][name]
                continue
            with tempfile.TemporaryDirectory() as build_dir:
                target = os.path.join(build_dir, CONFIG["series"], name)
                if not download_artifact(r["run_id"], r["artifact"], target):
                    messages.append(f"- `{name}`: the artifact has expired. Build it again ({rebuild_hint(name)}).")
                    continue
                ## The artifact of the run must be the version that was reviewed
                result = read_result(os.path.join(target, "result.env"))
                differs = [key for key, field in (("VERSION", "version"), ("FINGERPRINT", "fingerprint"),
                                                  ("INPUT", "input")) if result.get(key) != r.get(field)]
                if differs:
                    messages.append(f"- `{name}`: the artifact does not match the reviewed version "
                                    f"({', '.join(differs)}). Build it again ({rebuild_hint(name)}).")
                    continue
                proc = subprocess.run([f"{SCRIPTS}/upload.sh", name], env=dict(os.environ, BUILD_DIR=build_dir),
                                      capture_output=True, text=True, timeout=UPLOAD_TIMEOUT)
        except subprocess.TimeoutExpired as e:
            stderr = e.stderr.decode(errors="replace") if isinstance(e.stderr, bytes) else (e.stderr or "")
            messages.append(f"- `{name}`: the upload did not finish within {UPLOAD_TIMEOUT // 60} min:\n"
                            f"```\n{stderr[-1500:]}\n```")
            continue
        except Exception as e:  # noqa: BLE001 - report it and go on with the other packages
            traceback.print_exc()
            messages.append(f"- `{name}`: the upload failed: `{type(e).__name__}: {e}`")
            continue
        sys.stderr.write(proc.stderr)
        if proc.returncode:
            messages.append(f"- `{name}`: the upload failed:\n```\n{proc.stderr[-1500:]}\n```")
            continue
        messages.append(f"- `{name}` `{r['version']}` uploaded to `ppa:{CONFIG['staging']}`.")
        del state["review"][name]
        ## Launchpad refuses uploads that follow each other closely.
        if index < len(names) - 1:
            time.sleep(UPLOAD_PAUSE)
    return messages


def do_reject(state, names):
    messages = []
    for name in names:
        r = state["review"].pop(name, None)
        if not r:
            messages.append(f"- `{name}`: not waiting for review.")
            continue
        state["rejected"][name] = {"base": r["base"], "input": r["input"]}
        messages.append(f"- `{name}` `{r['version']}` dropped. It is offered again after the port or the overlay changes.")
    return messages


def promote_order(names, current):
    """Return the names in the order of the copies: the groups in GROUP_ORDER,
    and in a group the ports first, then the own packages, the metapackage
    last."""
    def key(name):
        group = current[name]["group"]
        rank = GROUP_ORDER.index(group) if group in GROUP_ORDER else GROUP_ORDER.index("")
        return (rank, group, name == META, name.startswith("g-unity7-"), name)
    return sorted(names, key=key)


def do_promote(state, names, force, pkgs, dry_run=False):
    """Copy the ✅ versions from staging to the main PPA: the given ones, or
    without names those of the table. A group is copied only when each member
    is ✅ with its version in the table and none waits for review (--force
    also copies from an incomplete group). A group in GROUP_NEEDS waits for the
    packages that it needs if the main PPA has no version of them. A failed
    copy stops the rest of its group and the packages that need it. With
    dry_run, nothing is copied."""
    messages = []
    table = state["promote"]
    current, _ = promote_rows(pkgs)
    waiting = waiting_groups(state, pkgs)
    problems = {}
    for name, r in current.items():
        if name not in table:
            problems[name] = "new in staging since the last update of the issue. Check it and give the command again"
        elif table[name]["staging"] != r["staging"]:
            problems[name] = (f"staging now has `{r['staging']}` instead of `{table[name]['staging']}`. "
                              "Check it and give the command again")
        elif r["state"] != "ok":
            problems[name] = f"the build has not finished ({STATE_ICONS[r['state']]})"
    groups = {}
    for name, r in current.items():
        if r["group"]:
            groups.setdefault(r["group"], []).append(name)
    selected = []
    for name in names or sorted(table):
        r = current.get(name)
        if not r:
            messages.append(f"- `{name}`: not waiting for promotion.")
            continue
        if name in problems:
            messages.append(f"- `{name}`: {problems[name]}.")
            continue
        incomplete = [n for n in sorted(groups.get(r["group"], []))
                      if n in problems or (names and n not in names)]
        incomplete += [f"{n} (waiting for review)" for n in waiting.get(r["group"], [])]
        if incomplete and not force:
            messages.append(f"- `{name}`: group `{r['group']}` is incomplete "
                            f"({', '.join(incomplete)}). Use `--force` to promote it anyway.")
            continue
        selected.append(name)
    for name in list(selected):
        needed = [n for n in GROUP_NEEDS.get(current[name]["group"], ())
                  if n in current and not current[n]["main"] and n not in selected]
        if needed and not force:
            messages.append(f"- `{name}`: needs {', '.join(f'`{n}`' for n in needed)}, which the main PPA "
                            "does not have yet. Promote it first, or use `--force`.")
            selected.remove(name)
    credentials = os.environ.get("LP_CREDENTIALS_FILE")
    failed, failed_groups = set(), set()
    for name in promote_order(selected, current):
        r = current[name]
        ## A package that is not copied stops the packages that need it too
        if r["group"] and r["group"] in failed_groups:
            messages.append(f"- `{name}`: not copied, because a copy in group `{r['group']}` failed.")
            failed.add(name)
            continue
        missing = [n for n in GROUP_NEEDS.get(r["group"], ()) if n in failed]
        if missing:
            messages.append(f"- `{name}`: not copied, because {', '.join(f'`{n}`' for n in missing)} "
                            "was not copied.")
            failed.add(name)
            if r["group"]:
                failed_groups.add(r["group"])
            continue
        if dry_run:
            messages.append(f"- `{name}` `{r['staging']}` would be copied to `ppa:{CONFIG['main']}`.")
            continue
        proc = subprocess.run([f"{SCRIPTS}/lp_write.py", "--credentials", credentials, "copy",
                               r["source"], r["staging"], "--from", CONFIG["staging"],
                               "--to", CONFIG["main"], "--series", CONFIG["series"]],
                              capture_output=True, text=True)
        if proc.returncode:
            messages.append(f"- `{name}`: the copy failed:\n```\n{proc.stderr[-1500:]}\n```")
            failed.add(name)
            if r["group"]:
                failed_groups.add(r["group"])
            continue
        status = proc.stdout.strip()
        messages.append(f"- `{name}` `{r['staging']}` copied to `ppa:{CONFIG['main']}`"
                        + (" (Launchpad is publishing it)." if status == "Pending" else "."))
    return messages


def do_ported(state, names):
    """Record that items of the section with overlay and archive changes were
    checked: the overlay commit for a port, an eclass or new packages, the
    version for the seeds and the archive items."""
    messages = []
    if names == ["all"]:
        names = sorted(state["drift"])
    for name in names:
        item = state["drift"].pop(name, None)
        if not item:
            messages.append(f"- `{name}`: nothing to check.")
            continue
        state["ported"][name] = item["value"]
        messages.append(f"- `{name}`: checked (`{item['value'][:40]}`).")
    return messages


def do_retry(source, version):
    proc = subprocess.run([f"{SCRIPTS}/lp_write.py", "--credentials", os.environ.get("LP_CREDENTIALS_FILE"),
                           "retry", source, version, "--ppa", CONFIG["staging"],
                           "--series", CONFIG["series"]], capture_output=True, text=True)
    if proc.returncode:
        return [f"- `{source}` `{version}`: {proc.stderr.strip()[-500:]}"]
    return [f"- `{source}` `{version}`: retrying the build."]


def run_command(issue, state, text):
    """Run the command in a comment and return the reply."""
    line = text.strip().splitlines()[0] if text.strip() else ""
    words = line.split()
    if not words or not words[0].startswith("/"):
        return None
    command, args = words[0], words[1:]
    pkgs = None
    ## Save the issue state and send the reply even if the command fails.
    try:
        pkgs = packages()
        if command == "/upload":
            messages = do_upload(issue, state, args, pkgs, command_time())
        elif command == "/reject" and args:
            messages = do_reject(state, args)
        elif command == "/promote":
            names = [a for a in args if a not in ("--force", "--dry-run")]
            messages = do_promote(state, names, "--force" in args, pkgs, "--dry-run" in args)
        elif command == "/retry" and len(args) == 2:
            messages = do_retry(*args)
        elif command == "/ported" and args:
            messages = do_ported(state, args)
        else:
            messages = [f"Unknown command `{line}`. See the issue description."]
    except Exception as e:  # noqa: BLE001
        traceback.print_exc()
        messages = [f"The command failed: `{type(e).__name__}: {e}`. See the run log."]
    try:
        refresh(issue, state, pkgs)
    except Exception as e:  # noqa: BLE001 - the reply is sent anyway
        traceback.print_exc()
        messages.append(f"Updating the issue failed: `{type(e).__name__}: {e}`. See the run log.")
    return f"`{line}`\n\n" + "\n".join(messages)


def cmd_comment(args):
    issue = find_issue()
    if not issue:
        sys.exit("approve.py: the approval issue does not exist")
    state = load_state(issue)
    reply = run_command(issue, state, args.text)
    if reply:
        comment(issue, reply)


def cmd_refresh(args):
    issue = find_issue()
    refresh(issue, load_state(issue))


def cmd_state(args):
    print(json.dumps(load_state(find_issue())))


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(required=True)

    p = sub.add_parser("refresh", help="update the issue")
    p.set_defaults(func=cmd_refresh)

    p = sub.add_parser("state", help="print the state JSON of the issue")
    p.set_defaults(func=cmd_state)

    p = sub.add_parser("add-review", help="record the builds of a ppa.yml run: put built versions in "
                                          "the issue for review, and remember the up-to-date ones")
    p.add_argument("--run-id", required=True)
    p.add_argument("--artifact-prefix", default="source-")
    p.add_argument("--planned", help="JSON list of the packages that the run built, whose failed "
                                     "builds the issue shows")
    p.add_argument("dirs", nargs="*", help="build directories (build/<series>/<package>)")
    p.set_defaults(func=cmd_add_review)

    p = sub.add_parser("comment", help="run the command of a comment")
    p.add_argument("text")
    p.set_defaults(func=cmd_comment)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
