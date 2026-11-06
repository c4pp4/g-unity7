#!/usr/bin/python3 -I
"""Manage the G Unity⁷ approval issue: versions waiting for review before the
upload to the staging PPA, versions waiting for promotion to the main PPA,
failed builds, and the commands given in its comments.

Commands (in comments by the repository owner):
  /upload [<package>...]   upload the reviewed source packages to staging
  /reject <package>...     drop versions waiting for review
  /promote [<package>...] [--force]
                           copy built versions from staging to the main PPA
  /retry <source> <version>
                           retry the failed builds of a version in staging

Environment: GITHUB_TOKEN, GITHUB_REPOSITORY, OVERLAY_DIR, LP_CREDENTIALS_FILE
(for /promote, /retry and deleting the base copies of ports from another PPA
on every update), and the GPG variables of upload.sh (for /upload).
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
## Pause between uploads (seconds).
UPLOAD_PAUSE = 60
## upload.sh tries dput four times with pauses (at most 4 × 10 min + 9 min).
UPLOAD_TIMEOUT = 60 * 60
## Launchpad counts as down after this many packages in a row without a state.
##  The remaining packages also keep their rows from the last update.
LP_FAILURES_MAX = 3
LP_ERRORS = (urllib.error.URLError, http.client.HTTPException, TimeoutError, ConnectionError,
             ValueError)
STATE_ICONS = {"ok": "✅", "building": "⏳", "failed": "❌", "missing": "❔"}


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
    request = urllib.request.Request(url, method=method,
                                     data=json.dumps(data).encode() if data is not None else None)
    request.add_unredirected_header("Authorization", f"Bearer {os.environ['GITHUB_TOKEN']}")
    request.add_header("Accept", "application/vnd.github+json")
    request.add_header("X-GitHub-Api-Version", "2022-11-28")
    with urllib.request.urlopen(request, timeout=120) as response:
        body = response.read()
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
            state = json.loads(match.group(1))
    for key in ("review", "rejected", "promote", "seen"):
        state.setdefault(key, {})
    state.setdefault("stale", [])
    return state


def comment(issue, text):
    github("POST", f"/repos/{repo()}/issues/{issue['number']}/comments", {"body": text})


## Packages and Launchpad.

def packages():
    out = subprocess.run([f"{SCRIPTS}/packages.sh", "--input", os.environ.get("OVERLAY_DIR", os.path.join(REPO_ROOT, "..", "gentoo-unity7"))],
                         check=True, capture_output=True, text=True).stdout
    return {p["name"]: p for p in json.loads(out)}


def newer(a, b):
    return not b or lp.version_cmp(a, b) > 0


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
    """Return the staging versions that are newer than in the main PPA, and the
    names of the packages that Launchpad gave no state for. Without the rows
    from the last update (old), a Launchpad error is raised. With them, the
    package keeps its row."""
    rows, stale = {}, []
    failures = 0
    for name, pkg in pkgs.items():
        if old is None:
            row = promote_row(pkg)
        elif failures < LP_FAILURES_MAX:
            try:
                row = promote_row(pkg)
                failures = 0
            except LP_ERRORS:
                traceback.print_exc()
                failures += 1
                row = old.get(name)
                stale.append(name)
        else:
            row = old.get(name)
            stale.append(name)
        if row:
            rows[name] = row
    return rows, stale


def promote_row(pkg):
    """Return the row of a package whose staging version is newer than in the
    main PPA, or None."""
    series = CONFIG["series"]
    staging = lp.ppa_latest(pkg["source"], CONFIG["staging"], series)
    if not staging:
        return None
    main = lp.ppa_latest(pkg["source"], CONFIG["main"], series)
    if not newer(staging["version"], main.get("version")):
        return None
    state = lp.build_state(pkg["source"], staging["version"], CONFIG["staging"], series)
    changes = describe_changes(staging.get("patches", {}), main.get("patches")) if main else "new package"
    if main and not changes:
        if base_of(staging["version"]) != base_of(main["version"]):
            changes = "rebased on " + base_of(staging["version"])
        else:
            changes = "rebuild"
    security = False
    if not pkg["local"]:
        version, pocket = lp.ubuntu_version(pkg["source"], series)
        security = pocket == "Security" and base_of(staging["version"]) == version
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


## The issue body.

def render(state, pkgs=None):
    out = [f"<!-- g-unity7-state\n{json.dumps(state, indent=1, ensure_ascii=False)}\n-->", ""]
    out += ["G Unity⁷ packages waiting for the owner's decision. The `review.yml` workflow "
            "updates the tables every hour. Give commands in comments.", ""]

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
        out += ["✅ built and published, ⏳ building, ❌ failed, 🔒 Ubuntu security update. "
                "`/promote` copies all ✅ versions of complete groups to the main PPA, and "
                "`/promote <package>…` only the given ones. `--force` also promotes from an "
                "incomplete group.", ""]
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
    return "\n".join(out)


def save(issue, state, pkgs=None):
    """Write the state to the issue, and create, close or reopen it."""
    body = render(state, pkgs)
    waiting = bool(state["review"] or state["promote"])
    if not issue:
        if not waiting:
            return None
        issue = github("POST", f"/repos/{repo()}/issues",
                       {"title": TITLE, "body": body, "labels": [LABEL]})
        return issue
    update = {"title": TITLE, "body": body, "state": "open" if waiting else "closed"}
    return github("PATCH", f"/repos/{repo()}/issues/{issue['number']}", update)


def notify_new(issue, state):
    """Comment on the versions that appeared since the last refresh."""
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


def prune_bases(issue, pkgs):
    """Delete the base copies of ports from another PPA (copy-base) in the
    staging PPA once the ports are published there (lp_write.py prune-base),
    and say so in the issue."""
    credentials = os.environ.get("LP_CREDENTIALS_FILE")
    if not credentials:
        return
    deleted = []
    for pkg in pkgs.values():
        if not pkg.get("source_archive"):
            continue
        proc = subprocess.run([f"{SCRIPTS}/lp_write.py", "--credentials", credentials, "prune-base",
                               pkg["source"], "--ppa", CONFIG["staging"], "--series", CONFIG["series"],
                               "--tag", CONFIG["tag"]], capture_output=True, text=True)
        if proc.returncode:
            print(f"::warning::Cannot delete the base copies of {pkg['source']}: "
                  f"{proc.stderr.strip()[-500:]}")
            continue
        deleted += [f"- `{pkg['source']}` `{v}` from `ppa:{pkg['source_archive']}`"
                    for v in proc.stdout.split()]
    if deleted and issue:
        comment(issue, "Deleted base copies that the published ports no longer need "
                       "(the ports keep the orig tarball):\n" + "\n".join(deleted))


def refresh(issue, state, pkgs=None):
    pkgs = pkgs or packages()
    prune_bases(issue, pkgs)
    state["promote"], state["stale"] = promote_rows(pkgs, state["promote"])
    if state["stale"]:
        print(f"::warning::Launchpad gave no state for {len(state['stale'])} packages. "
              "They keep their rows from the last update.")
    issue = save(issue, state, pkgs)
    notify_new(issue, state)
    return save(issue, state, pkgs)


## Commands.

def read_result(path):
    result = {}
    with open(path) as f:
        for line in f:
            key, _, value = line.rstrip("\n").partition("=")
            result[key] = value
    return result


def cmd_add_review(args):
    """Add the built versions that need review (build directories) to the issue."""
    issue = find_issue()
    state = load_state(issue)
    for directory in args.dirs:
        name = os.path.basename(directory.rstrip("/"))
        result = read_result(os.path.join(directory, "result.env"))
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


def do_upload(issue, state, names, pkgs):
    messages = []
    names = names or sorted(state["review"])
    for name in names:
        r = state["review"].get(name)
        if not r:
            messages.append(f"- `{name}`: not waiting for review.")
            continue
        if name not in pkgs or pkgs[name]["input"] != r["input"]:
            messages.append(f"- `{name}`: the port or the overlay changed after the review. "
                            f"Build it again (`gh workflow run ppa.yml -f packages={name}`).")
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
                    messages.append(f"- `{name}`: the artifact has expired. Build it again "
                                    f"(`gh workflow run ppa.yml -f packages={name}`).")
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


def do_promote(state, names, force, pkgs):
    messages = []
    table = state["promote"]
    current, _ = promote_rows(pkgs)
    candidates = names or sorted(table)
    groups = {}
    for name, r in current.items():
        if r["group"]:
            groups.setdefault(r["group"], []).append(name)
    waiting = waiting_groups(state, pkgs)
    credentials = os.environ.get("LP_CREDENTIALS_FILE")
    for name in candidates:
        r = current.get(name)
        if not r:
            messages.append(f"- `{name}`: not waiting for promotion.")
            continue
        if name in table and table[name]["staging"] != r["staging"]:
            messages.append(f"- `{name}`: staging now has `{r['staging']}` instead of "
                            f"`{table[name]['staging']}`. Check it and give the command again.")
            continue
        if r["state"] != "ok":
            messages.append(f"- `{name}`: the build has not finished ({STATE_ICONS[r['state']]}).")
            continue
        incomplete = [n for n in groups.get(r["group"], []) if current[n]["state"] != "ok"
                      or (names and n not in names)]
        incomplete += [f"{n} (waiting for review)" for n in waiting.get(r["group"], [])]
        if incomplete and not force:
            messages.append(f"- `{name}`: group `{r['group']}` is incomplete "
                            f"({', '.join(incomplete)}). Use `--force` to promote it anyway.")
            continue
        proc = subprocess.run([f"{SCRIPTS}/lp_write.py", "--credentials", credentials, "copy",
                               r["source"], r["staging"], "--from", CONFIG["staging"],
                               "--to", CONFIG["main"], "--series", CONFIG["series"]],
                              capture_output=True, text=True)
        if proc.returncode:
            messages.append(f"- `{name}`: the copy failed:\n```\n{proc.stderr[-1500:]}\n```")
            continue
        status = proc.stdout.strip()
        messages.append(f"- `{name}` `{r['staging']}` copied to `ppa:{CONFIG['main']}`"
                        + (" (Launchpad is publishing it)." if status == "Pending" else "."))
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
    pkgs = packages()
    ## Save the issue state and send the reply even if the command fails.
    try:
        if command == "/upload":
            messages = do_upload(issue, state, args, pkgs)
        elif command == "/reject" and args:
            messages = do_reject(state, args)
        elif command == "/promote":
            force = "--force" in args
            messages = do_promote(state, [a for a in args if a != "--force"], force, pkgs)
        elif command == "/retry" and len(args) == 2:
            messages = do_retry(*args)
        else:
            messages = [f"Unknown command `{line}`. See the issue description."]
    except Exception as e:  # noqa: BLE001
        traceback.print_exc()
        messages = [f"The command failed: `{type(e).__name__}: {e}`. See the run log."]
    refresh(issue, state, pkgs)
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

    p = sub.add_parser("add-review", help="put built versions in the issue for review")
    p.add_argument("--run-id", required=True)
    p.add_argument("--artifact-prefix", default="source-")
    p.add_argument("dirs", nargs="+", help="build directories (build/<series>/<package>)")
    p.set_defaults(func=cmd_add_review)

    p = sub.add_parser("comment", help="run the command of a comment")
    p.add_argument("text")
    p.set_defaults(func=cmd_comment)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
