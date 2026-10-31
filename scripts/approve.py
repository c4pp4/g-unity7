#!/usr/bin/python3 -I
"""The approval issue of G Unity⁷: versions waiting for review before the
upload to the staging PPA, versions waiting for promotion to the main PPA,
failed builds, and the commands given in its comments.

Commands (comments of the repository owner):
  /upload [<package>...]   upload the reviewed source packages to staging
  /reject <package>...     drop versions waiting for review
  /promote [<package>...] [--force]
                           copy built versions from staging to the main PPA
  /retry <source> <version>
                           retry the failed builds of a version in staging

Environment: GITHUB_TOKEN, GITHUB_REPOSITORY, OVERLAY_DIR, LP_CREDENTIALS_FILE
(for /promote and /retry), the GPG variables of upload.sh (for /upload).
"""

import argparse
import io
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lp  # noqa: E402

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPTS)
LABEL = "approve"
TITLE = "G Unity⁷: čeká na tebe"
STATE_RE = re.compile(r"<!-- g-unity7-state\n(.*?)\n-->", re.S)
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
    for state in ("open", "closed"):
        for issue in github("GET", f"/repos/{repo()}/issues?labels={LABEL}&state={state}&per_page=100"):
            if issue["title"] == TITLE and "pull_request" not in issue:
                return issue
    return None


def load_state(issue):
    state = {}
    if issue and issue.get("body"):
        match = STATE_RE.search(issue["body"])
        if match:
            state = json.loads(match.group(1))
    for key in ("review", "rejected", "promote", "seen"):
        state.setdefault(key, {})
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
    """Describe the patch changes from the patches of new and old ({name: hash})."""
    if not old:
        return "nový balíček"
    changes = []
    for verb, names in (("added", [n for n in new if n not in old]),
                        ("updated", [n for n in new if n in old and old[n] != new[n]]),
                        ("removed", [n for n in old if n not in new])):
        if names:
            changes.append(f"{verb}: {', '.join(names)}")
    return "; ".join(changes)


def promote_rows(pkgs):
    """Versions of the staging PPA newer than in the main PPA."""
    rows = {}
    series = CONFIG["series"]
    for name, pkg in pkgs.items():
        staging = lp.ppa_latest(pkg["source"], CONFIG["staging"], series)
        if not staging:
            continue
        main = lp.ppa_latest(pkg["source"], CONFIG["main"], series)
        if not newer(staging["version"], main.get("version")):
            continue
        state = lp.build_state(pkg["source"], staging["version"], CONFIG["staging"], series)
        changes = describe_changes(staging.get("patches", {}), main.get("patches")) if main else "nový balíček"
        if main and not changes:
            changes = "rebased on " + base_of(staging["version"])
        security = False
        if not pkg["local"]:
            version, pocket = lp.ubuntu_version(pkg["source"], series)
            security = pocket == "Security" and base_of(staging["version"]) == version
        rows[name] = {
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
    return rows


## The issue body.

def render(state):
    out = [f"<!-- g-unity7-state\n{json.dumps(state, indent=1, ensure_ascii=False)}\n-->", ""]
    out += ["Stav balíčků G Unity⁷, které čekají na tvé rozhodnutí. Tabulky aktualizuje "
            "workflow `review.yml` každou hodinu, příkazy se píší do komentářů.", ""]

    out += ["## Ke kontrole před nahráním", ""]
    if state["review"]:
        out += ["| Balíček | Verze | Důvod | Review |", "|---|---|---|---|"]
        for name, r in sorted(state["review"].items()):
            run = f"https://github.com/{repo()}/actions/runs/{r['run_id']}"
            out.append(f"| `{name}` | `{r['version']}` | {r['reason']} | "
                       f"[souhrn běhu]({run}) · artefakt `{r['artifact']}` |")
        out += ["", "`/upload` nahraje vše, `/upload <balíček>…` jen vybrané, "
                "`/reject <balíček>…` verzi zahodí.", ""]
    else:
        out += ["Nic nečeká.", ""]

    out += ["## Čeká na povýšení", ""]
    if state["promote"]:
        out += ["| Skupina | Balíček | Staging | Hlavní PPA | Build | Změny |",
                "|---|---|---|---|---|---|"]
        for name, r in sorted(state["promote"].items(), key=lambda i: (i[1]["group"] or "~", i[0])):
            lock = " 🔒" if r["security"] else ""
            out.append(f"| {r['group'] or '–'} | `{name}`{lock} | `{r['staging']}` | "
                       f"`{r['main'] or '–'}` | {STATE_ICONS[r['state']]} | {r['changes']} |")
        out += ["", "✅ sestaveno a publikováno, ⏳ build běží, ❌ selhal, 🔒 bezpečnostní "
                "oprava z Ubuntu. `/promote` zkopíruje vše ✅ s kompletní skupinou, "
                "`/promote <balíček>…` jen vybrané, `--force` i s neúplnou skupinou.", ""]
        failed = [(n, r) for n, r in sorted(state["promote"].items()) if r["state"] == "failed"]
        if failed:
            out += ["### Selhané buildy", ""]
            for name, r in failed:
                logs = ", ".join(f"[{b['arch_tag']}: {b['buildstate']}]({b['web_link']})"
                                 for b in r["builds"])
                out.append(f"- `{name}` `{r['staging']}`: {logs}. "
                           f"Opakování: `/retry {r['source']} {r['staging']}`")
            out.append("")
        out += ["<details><summary>Test ve VM před povýšením</summary>", "",
                "```sh", f"sudo add-apt-repository ppa:{CONFIG['staging']}",
                "sudo apt full-upgrade", "# test", "sudo apt install ppa-purge",
                f"sudo ppa-purge ppa:{CONFIG['staging']}", "```", "</details>", ""]
    else:
        out += ["Nic nečeká.", ""]
    return "\n".join(out)


def save(issue, state):
    """Write the state to the issue, create, close or reopen it."""
    body = render(state)
    waiting = bool(state["review"] or state["promote"])
    if not issue:
        if not waiting:
            return None
        issue = github("POST", f"/repos/{repo()}/issues",
                       {"title": TITLE, "body": body, "labels": [LABEL]})
        return issue
    update = {"body": body, "state": "open" if waiting else "closed"}
    return github("PATCH", f"/repos/{repo()}/issues/{issue['number']}", update)


def notify_new(issue, state):
    """Comment on versions that appeared since the last refresh."""
    new = []
    for section in ("review", "promote"):
        for name, r in state[section].items():
            version = r.get("version") or r.get("staging")
            key = f"{section}:{name}"
            if state["seen"].get(key) != version:
                where = "ke kontrole" if section == "review" else "k povýšení"
                new.append(f"- `{name}` `{version}` {where}"
                           + (" 🔒" if r.get("security") else ""))
                state["seen"][key] = version
    for key in list(state["seen"]):
        section, name = key.split(":", 1)
        if name not in state[section]:
            del state["seen"][key]
    if new and issue:
        comment(issue, "Nové verze:\n" + "\n".join(new))


def refresh(issue, state, pkgs=None):
    pkgs = pkgs or packages()
    state["promote"] = promote_rows(pkgs)
    issue = save(issue, state)
    notify_new(issue, state)
    return save(issue, state)


## Commands.

def read_result(path):
    result = {}
    with open(path) as f:
        for line in f:
            key, _, value = line.rstrip("\n").partition("=")
            result[key] = value
    return result


def cmd_add_review(args):
    """Put the built versions needing review (build directories) in the issue."""
    issue = find_issue()
    state = load_state(issue)
    for directory in args.dirs:
        name = os.path.basename(directory.rstrip("/"))
        result = read_result(os.path.join(directory, "result.env"))
        with open(os.path.join(directory, "patches.txt")) as f:
            new = dict(line.split(" ", 1) for line in f.read().split("\n") if line)
        staging = lp.ppa_latest(result["SOURCE"], CONFIG["staging"], CONFIG["series"])
        reason = describe_changes(new, staging.get("patches")) if staging else "nový balíček"
        state["review"][name] = {
            "source": result["SOURCE"],
            "version": result["VERSION"],
            "base": base_of(result["VERSION"]),
            "fingerprint": result["FINGERPRINT"],
            "input": result["INPUT"],
            "run_id": args.run_id,
            "artifact": args.artifact_prefix + name,
            "reason": reason or "změna mimo patche",
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
            messages.append(f"- `{name}`: nečeká na kontrolu.")
            continue
        if name not in pkgs or pkgs[name]["input"] != r["input"]:
            messages.append(f"- `{name}`: port nebo overlay se od review změnil, "
                            f"spusť nové sestavení (`gh workflow run ppa.yml -f packages={name}`).")
            continue
        staging = lp.ppa_latest(r["source"], CONFIG["staging"], CONFIG["series"])
        if staging and not newer(r["version"], staging["version"]):
            messages.append(f"- `{name}`: staging už má `{staging['version']}`.")
            del state["review"][name]
            continue
        with tempfile.TemporaryDirectory() as build_dir:
            target = os.path.join(build_dir, CONFIG["series"], name)
            if not download_artifact(r["run_id"], r["artifact"], target):
                messages.append(f"- `{name}`: artefakt vypršel, spusť nové sestavení "
                                f"(`gh workflow run ppa.yml -f packages={name}`).")
                continue
            proc = subprocess.run([f"{SCRIPTS}/upload.sh", name], env=dict(os.environ, BUILD_DIR=build_dir),
                                  capture_output=True, text=True)
        if proc.returncode:
            messages.append(f"- `{name}`: nahrání selhalo:\n```\n{proc.stderr[-1500:]}\n```")
            continue
        messages.append(f"- `{name}` `{r['version']}` nahrán do `ppa:{CONFIG['staging']}`.")
        del state["review"][name]
    return messages


def do_reject(state, names):
    messages = []
    for name in names:
        r = state["review"].pop(name, None)
        if not r:
            messages.append(f"- `{name}`: nečeká na kontrolu.")
            continue
        state["rejected"][name] = {"base": r["base"], "input": r["input"]}
        messages.append(f"- `{name}` `{r['version']}` zahozen, znovu se nabídne po změně portu nebo overlaye.")
    return messages


def do_promote(state, names, force, pkgs):
    messages = []
    table = state["promote"]
    current = promote_rows(pkgs)
    candidates = names or sorted(table)
    groups = {}
    for name, r in current.items():
        if r["group"]:
            groups.setdefault(r["group"], []).append(name)
    credentials = os.environ.get("LP_CREDENTIALS_FILE")
    for name in candidates:
        r = current.get(name)
        if not r:
            messages.append(f"- `{name}`: nečeká na povýšení.")
            continue
        if name in table and table[name]["staging"] != r["staging"]:
            messages.append(f"- `{name}`: ve stagingu je mezitím `{r['staging']}` místo "
                            f"`{table[name]['staging']}`, zkontroluj ho a zadej příkaz znovu.")
            continue
        if r["state"] != "ok":
            messages.append(f"- `{name}`: build není hotový ({STATE_ICONS[r['state']]}).")
            continue
        incomplete = [n for n in groups.get(r["group"], []) if current[n]["state"] != "ok"
                      or (names and n not in names)]
        if incomplete and not force:
            messages.append(f"- `{name}`: skupina `{r['group']}` není kompletní "
                            f"({', '.join(incomplete)}), použij `--force`.")
            continue
        proc = subprocess.run([f"{SCRIPTS}/lp_write.py", "--credentials", credentials, "copy",
                               r["source"], r["staging"], "--from", CONFIG["staging"],
                               "--to", CONFIG["main"], "--series", CONFIG["series"]],
                              capture_output=True, text=True)
        if proc.returncode:
            messages.append(f"- `{name}`: kopírování selhalo:\n```\n{proc.stderr[-1500:]}\n```")
            continue
        messages.append(f"- `{name}` `{r['staging']}` zkopírován do `ppa:{CONFIG['main']}`.")
    return messages


def do_retry(source, version):
    proc = subprocess.run([f"{SCRIPTS}/lp_write.py", "--credentials", os.environ.get("LP_CREDENTIALS_FILE"),
                           "retry", source, version, "--ppa", CONFIG["staging"],
                           "--series", CONFIG["series"]], capture_output=True, text=True)
    if proc.returncode:
        return [f"- `{source}` `{version}`: {proc.stderr.strip()[-500:]}"]
    return [f"- `{source}` `{version}`: build spuštěn znovu."]


def run_command(issue, state, text):
    """Run the command of a comment, return the reply."""
    line = text.strip().splitlines()[0] if text.strip() else ""
    words = line.split()
    if not words or not words[0].startswith("/"):
        return None
    command, args = words[0], words[1:]
    pkgs = packages()
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
        messages = [f"Neznámý příkaz `{line}`, viz popis issue."]
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
