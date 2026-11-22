"""Unit tests of scripts/lp.py and scripts/approve.py, without network. dpkg
compares the versions, so run them on Ubuntu or Debian:

  python3 -m unittest discover -s tests/scripts -v
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import urllib.error
from unittest import mock

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
sys.path.insert(0, os.path.join(ROOT, "scripts"))
os.environ.setdefault("GITHUB_REPOSITORY", "c4pp4/g-unity7")

import approve  # noqa: E402
import lp  # noqa: E402

CHANGELOG = """\
unity (7.7.1-0ubuntu4+gu7.2~26.10) stonking; urgency=medium

  * G Unity⁷ patches from c4pp4/gentoo-unity7@611f038323f8,
    built from c4pp4/g-unity7@2b3f6f9aaaaa.
  * Patches:
    - one.patch [0123456789ab]
    - ebuild-edits.patch [ba9876543210]
  * G-Unity7-Fingerprint: 0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f
  * G-Unity7-Input: 1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e

 -- c4pp4 <c4pp4@example.org>  Tue, 17 Nov 2026 22:00:00 +0100

unity (7.7.1-0ubuntu4) stonking-security; urgency=medium

  * SECURITY UPDATE: a problem
    - debian/patches/CVE-2026-1234.patch: fix it
    - CVE-2026-1234

 -- Security <security@example.org>  Mon, 16 Nov 2026 10:00:00 +0000

unity (7.7.1-0ubuntu3) stonking; urgency=medium

  * A fix without a CVE.

 -- Someone <someone@example.org>  Sun, 15 Nov 2026 10:00:00 +0000

unity (7.7.1-0ubuntu2) stonking; urgency=medium

  * Fixes for mfsa2026-01, also known as an older advisory.

 -- Someone <someone@example.org>  Sat, 14 Nov 2026 10:00:00 +0000
"""


class ParseChangelog(unittest.TestCase):
    def test_g_unity7_data(self):
        data = lp.parse_changelog(CHANGELOG)
        self.assertEqual(data["patches"], {"one.patch": "0123456789ab",
                                           "ebuild-edits.patch": "ba9876543210"})
        self.assertEqual(data["fingerprint"], "0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f")
        self.assertEqual(data["input"], "1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e1e")

    def test_upstream_entries(self):
        data = lp.parse_changelog(CHANGELOG)
        self.assertEqual(data["upstream"], [["7.7.1-0ubuntu4", True], ["7.7.1-0ubuntu3", False],
                                            ["7.7.1-0ubuntu2", True]])

    def test_only_the_first_entry(self):
        ours, ubuntu = CHANGELOG.split("\n\nunity (7.7.1-0ubuntu4) ", 1)
        data = lp.parse_changelog("unity (7.7.1-0ubuntu4) " + ubuntu + "\n\n" + ours)
        self.assertNotIn("fingerprint", data)
        self.assertEqual(data["patches"], {})


class Fetch(unittest.TestCase):
    def test_invalid_json_is_fetched_again(self):
        with mock.patch.object(lp, "fetch", side_effect=[b"{", b'{"a": 1}']), \
                mock.patch.object(lp.time, "sleep"):
            self.assertEqual(lp.get("https://example.org/a"), {"a": 1})


class GitHub(unittest.TestCase):
    def test_get_is_tried_again_after_a_server_error(self):
        response = mock.MagicMock()
        response.read.return_value = b'{"ok": true}'
        response.__enter__.return_value = response
        error = urllib.error.HTTPError("https://api.github.com/x", 502, "Bad Gateway", {}, None)
        self.addCleanup(error.close)
        with mock.patch.dict(os.environ, {"GITHUB_TOKEN": "t"}), \
                mock.patch.object(approve.urllib.request, "urlopen", side_effect=[error, response]), \
                mock.patch.object(approve.time, "sleep"):
            self.assertEqual(approve.github("GET", "/x"), {"ok": True})

    def test_post_is_not_tried_again_after_a_timeout(self):
        with mock.patch.dict(os.environ, {"GITHUB_TOKEN": "t"}), \
                mock.patch.object(approve.urllib.request, "urlopen", side_effect=TimeoutError()), \
                mock.patch.object(approve.time, "sleep") as sleep:
            with self.assertRaises(TimeoutError):
                approve.github("POST", "/x", {"body": "b"})
        sleep.assert_not_called()


class SecurityFix(unittest.TestCase):
    upstream = lp.parse_changelog(CHANGELOG)["upstream"]

    def test_cve_since_main(self):
        self.assertTrue(approve.security_fix(self.upstream, "7.7.1-0ubuntu3"))

    def test_same_base(self):
        self.assertFalse(approve.security_fix(self.upstream, "7.7.1-0ubuntu4"))

    def test_advisory_only_before_main(self):
        self.assertFalse(approve.security_fix([["7.7.1-0ubuntu3", False], ["7.7.1-0ubuntu2", True]],
                                              "7.7.1-0ubuntu2"))

    def test_main_newer_than_entries(self):
        self.assertFalse(approve.security_fix(self.upstream, "7.7.1-0ubuntu5"))


class DescribeChanges(unittest.TestCase):
    def test_new_package(self):
        self.assertEqual(approve.describe_changes({"a": "1"}, None), "new package")

    def test_changes(self):
        self.assertEqual(approve.describe_changes({"a": "2", "b": "1"}, {"a": "1", "c": "1"}),
                         "added: b; updated: a; removed: c")

    def test_no_change(self):
        self.assertEqual(approve.describe_changes({"a": "1"}, {"a": "1"}), "")


class PortPattern(unittest.TestCase):
    def test_ebuild(self):
        pattern = approve.port_pattern("unity-base/unity")
        self.assertTrue(pattern.match("unity-base/unity/unity-7.7.1-r261008.ebuild"))
        self.assertFalse(pattern.match("unity-base/unity/files/fix.patch"))
        self.assertFalse(pattern.match("unity-base/unity/Manifest"))
        self.assertFalse(pattern.match("unity-base/unity-settings/unity-settings-1.ebuild"))

    def test_ehooks_with_slot(self):
        pattern = approve.port_pattern("ehooks/www-client/firefox:rapid")
        self.assertTrue(pattern.match("ehooks/www-client/firefox:rapid/firefox.ehooks"))
        self.assertTrue(pattern.match("ehooks/www-client/firefox-160:rapid/firefox.ehooks"))
        self.assertFalse(pattern.match("ehooks/www-client/firefox:rapid/files/unity-menubar.patch"))
        self.assertFalse(pattern.match("ehooks/www-client/firefox:esr/firefox.ehooks"))
        self.assertFalse(pattern.match("ehooks/www-client/firefox-bin/firefox-bin.ehooks"))

    def test_ehooks_without_slot(self):
        pattern = approve.port_pattern("ehooks/mail-client/thunderbird")
        self.assertTrue(pattern.match("ehooks/mail-client/thunderbird-159/thunderbird.ehooks"))
        self.assertFalse(pattern.match("ehooks/mail-client/thunderbird-bin/thunderbird-bin.ehooks"))

    def test_variants(self):
        pattern = approve.port_pattern("unity-base/unity", ["set-desktop-name.patch"])
        self.assertTrue(pattern.match("unity-base/unity/unity-7.7.1-r261008.ebuild"))
        self.assertTrue(pattern.match("unity-base/unity/files/set-desktop-name.patch"))
        self.assertFalse(pattern.match("unity-base/unity/files/set-desktop-name.patch.orig"))
        self.assertFalse(pattern.match("unity-base/unity/files/other.patch"))
        self.assertFalse(pattern.match("unity-base/unity/Manifest"))
        pattern = approve.port_pattern("ehooks/x11-terms/mate-terminal", ["add-unity-list.patch"])
        self.assertTrue(pattern.match("ehooks/x11-terms/mate-terminal/files/add-unity-list.patch"))
        self.assertFalse(pattern.match("ehooks/x11-terms/mate-terminal/files/other.patch"))

    def test_follow(self):
        patterns = approve.follow_patterns({"overlay_pkg": "unity-base/unity-meta",
                                            "follow": ["unity-lens/unity-lens-meta"]})
        self.assertTrue(any(p.match("unity-lens/unity-lens-meta/unity-lens-meta-1.ebuild") for p in patterns))
        self.assertTrue(any(p.match("unity-base/unity-meta/unity-meta-1.ebuild") for p in patterns))
        self.assertFalse(approve.follow_patterns({"overlay_pkg": "", "follow": []}))


def state(**sections):
    result = approve.load_state(None)
    result.update(sections)
    return result


class Commands(unittest.TestCase):
    def test_reject(self):
        s = state(review={"unity": {"version": "1+gu7.2~26.10", "base": "1", "input": "abc"}})
        messages = approve.do_reject(s, ["unity", "hud"])
        self.assertEqual(s["review"], {})
        self.assertEqual(s["rejected"], {"unity": {"base": "1", "input": "abc"}})
        self.assertIn("`hud`: not waiting for review", messages[1])

    def test_upload_refuses_an_artifact_of_another_version(self):
        s = state(review={"unity": {"source": "unity", "version": "1-1+gu7.2~26.10", "fingerprint": "f",
                                    "input": "x", "run_id": "5", "artifact": "source-unity"}})

        def download(run_id, name, target):
            os.makedirs(target)
            with open(os.path.join(target, "result.env"), "w") as f:
                f.write("STATUS=built\nVERSION=1-1+gu7.3~26.10\nFINGERPRINT=f\nINPUT=x\n")
            return True
        real_run = subprocess.run

        def run(cmd, *args, **kwargs):
            if cmd[0].endswith("/upload.sh"):
                raise AssertionError("no upload")
            return real_run(cmd, *args, **kwargs)
        with mock.patch.object(lp, "ppa_latest", return_value={"version": "1-1+gu7.1~26.10"}), \
                mock.patch.object(approve, "download_artifact", side_effect=download), \
                mock.patch.object(approve.subprocess, "run", side_effect=run):
            messages = approve.do_upload(None, s, ["unity"], {"unity": {"input": "x"}})
        self.assertIn("does not match the reviewed version (VERSION)", messages[0])
        self.assertIn("force=true", messages[0])
        self.assertIn("unity", s["review"])

    def test_upload_without_names_only_before_the_command(self):
        s = state(review={
            "later": {"version": "1+gu7.1~26.10", "input": "x", "added": "2026-11-17T21:30:00Z"},
            "changed": {"version": "1+gu7.1~26.10", "input": "old", "added": "2026-11-17T21:00:00Z"},
        })
        pkgs = {"later": {"input": "x"}, "changed": {"input": "new"}}
        messages = approve.do_upload(None, s, [], pkgs, before="2026-11-17T21:10:00Z")
        self.assertEqual(len(messages), 2)
        self.assertIn("`later`: added for review after the command", messages[0])
        self.assertIn("`changed`: the port or the overlay changed after the review", messages[1])
        self.assertIn("later", s["review"])

    def test_command_time(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"comment": {"created_at": "2026-11-17T21:27:21Z"}}, f)
        try:
            with mock.patch.dict(os.environ, {"GITHUB_EVENT_PATH": f.name}):
                self.assertEqual(approve.command_time(), "2026-11-17T21:27:21Z")
        finally:
            os.unlink(f.name)
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertIsNone(approve.command_time())

    def test_ported(self):
        s = state(drift={"unity": {"value": "c" * 40, "text": "x"},
                         "ubuntu-unity-meta": {"value": "0.31", "text": "y"}})
        messages = approve.do_ported(s, ["unity", "hud"])
        self.assertEqual(s["ported"], {"unity": "c" * 40})
        self.assertIn("ubuntu-unity-meta", s["drift"])
        self.assertIn("`hud`: nothing to check", messages[1])
        approve.do_ported(s, ["all"])
        self.assertEqual(s["drift"], {})
        self.assertEqual(s["ported"]["ubuntu-unity-meta"], "0.31")


class CheckDrift(unittest.TestCase):
    pkgs = {
        "unity": {"source": "unity", "overlay_pkg": "unity-base/unity", "ubuntu_src": "unity",
                  "derived": False, "older": False},
        "hud": {"source": "hud", "overlay_pkg": "unity-base/hud", "ubuntu_src": "hud",
                "derived": False, "older": False},
        "nemo-engrampa": {"source": "nemo-engrampa", "overlay_pkg": "gnome-extra/nemo-engrampa",
                          "ubuntu_src": "nemo-fileroller", "derived": True, "older": False},
        "unity-docs": {"source": "unity-docs", "overlay_pkg": "", "ubuntu_src": "ubuntu-docs",
                       "derived": True, "older": True},
        "unity-scope-audacious": {"source": "unity-scope-audacious", "overlay_pkg": "",
                                  "ubuntu_src": "unity-scope-audacious", "derived": False, "older": True},
    }

    def run_check(self, s, versions, pkgs=None, new_dirs=(),
                  files=("unity-base/unity/unity-7.7.1-r261008.ebuild", "unity-base/unity/files/a.patch",
                         "eclass/ubuntu-versionator.eclass")):
        with mock.patch.object(approve, "overlay_head", return_value="h" * 40), \
                mock.patch.object(approve, "overlay_changes", return_value=(list(files), "https://example.org/c")), \
                mock.patch.object(approve, "overlay_new_dirs", return_value=list(new_dirs)), \
                mock.patch.object(approve, "check_behind"), \
                mock.patch.object(lp, "ubuntu_version", side_effect=lambda source, series: versions.get(source, (None, None))):
            approve.check_drift(s, pkgs or self.pkgs)

    def test_changes(self):
        s = state()
        self.run_check(s, {"ubuntu-unity-meta": ("0.30", "Release"),
                           "nemo-engrampa": ("1.0-1", "Release"),
                           "ubuntu-docs": ("26.10.1ubuntu", "Release"),
                           "unity-scope-audacious": ("0.2-0ubuntu1", "Release")})
        self.assertEqual(sorted(s["drift"]), ["archive:nemo-engrampa", "archive:unity-scope-audacious",
                                              "eclass", "unity"])
        self.assertIn("1 file since `611f038`", s["drift"]["unity"]["text"])
        self.assertEqual(s["ported"]["ubuntu-unity-meta"], "0.30")

    def test_checked_items_and_new_seeds(self):
        s = state(ported={"unity": "h" * 40, "eclass": "h" * 40, "ubuntu-unity-meta": "0.30",
                          "archive:nemo-engrampa": "Ubuntu has a source `nemo-engrampa` (`1.0-1`), "
                                                   "the name of this derived source"})
        self.run_check(s, {"ubuntu-unity-meta": ("0.31", "Release"),
                           "nemo-engrampa": ("1.0-1", "Release")})
        self.assertEqual(sorted(s["drift"]), ["ubuntu-unity-meta"])

    def test_render(self):
        s = state()
        self.run_check(s, {"ubuntu-unity-meta": ("0.30", "Release")})
        body = approve.render(s)
        self.assertIn("## Overlay and archive changes to check", body)
        self.assertIn("- `unity`: [1 file since `611f038`]", body)

    def test_variants_follow_and_new_packages(self):
        pkgs = dict(self.pkgs)
        pkgs["unity"] = dict(pkgs["unity"], variants=["set-desktop-name.patch"])
        pkgs["g-unity7-meta"] = {"source": "g-unity7-meta", "overlay_pkg": "unity-base/unity-meta",
                                 "follow": ["unity-lens/unity-lens-meta"], "ubuntu_src": "",
                                 "derived": False, "older": False}
        s = state()
        self.run_check(s, {"ubuntu-unity-meta": ("0.30", "Release")}, pkgs,
                       new_dirs=["unity-base/unity", "unity-indicators/indicator-new"],
                       files=["unity-base/unity/files/set-desktop-name.patch", "unity-base/unity/files/b.patch",
                              "unity-lens/unity-lens-meta/unity-lens-meta-2.ebuild"])
        self.assertEqual(sorted(s["drift"]), ["g-unity7-meta", "overlay:new", "unity"])
        self.assertIn("`unity-base/unity/files/set-desktop-name.patch`", s["drift"]["unity"]["text"])
        self.assertNotIn("b.patch", s["drift"]["unity"]["text"])
        self.assertIn("`unity-indicators/indicator-new`", s["drift"]["overlay:new"]["text"])
        self.assertNotIn("unity-base/unity`", s["drift"]["overlay:new"]["text"])


class CheckBehind(unittest.TestCase):
    pkgs = {
        "firefox": {"source": "firefox", "ubuntu_src": "firefox", "debian_suite": "sid", "ubuntu_series": "",
                    "local": False, "hold": ""},
        "unity": {"source": "unity", "ubuntu_src": "unity", "debian_suite": "", "ubuntu_series": "",
                  "local": False, "hold": ""},
        "hud": {"source": "hud", "ubuntu_src": "hud", "debian_suite": "", "ubuntu_series": "",
                "local": False, "hold": ""},
        "nux": {"source": "nux", "ubuntu_src": "nux", "debian_suite": "", "ubuntu_series": "",
                "local": False, "hold": "until a patch applies"},
        "zim": {"source": "zim", "ubuntu_src": "zim", "debian_suite": "", "ubuntu_series": "",
                "local": False, "hold": ""},
        "g-unity7-meta": {"source": "g-unity7-meta", "ubuntu_src": "", "local": True, "hold": ""},
    }
    staging = {"firefox": {"version": "160.0-1+gu7.1~26.10"}, "unity": {"version": "7.7.1-0ubuntu3+gu7.6~26.10"},
               "hud": {"version": "1-1+gu7.1~26.10"}, "nux": {"version": "4-1+gu7.1~26.10"},
               "zim": {"version": "0.76-1+gu7.1~26.10"}, "g-unity7-meta": {"version": "1+gu7.23~26.10"}}
    ubuntu = {"unity": ("7.7.1-0ubuntu4", "Security"), "hud": ("1-1", "Release"), "nux": ("4-2", "Release"),
              "zim": ("0.76-2", "Release")}

    def test_behind(self):
        s = state(review={"zim": {"base": "0.76-2"}}, behind={"unity": {"since": "2026-11-20T00:00:00Z"}},
                  uptodate={"hud": {"version": "1-1+gu7.1~26.10", "base": "1-1", "input": "a"},
                            "firefox": {"version": "159.0-1+gu7.1~26.10", "base": "159.0-1", "input": "b"},
                            "gone": {"version": "1+gu7.1~26.10", "base": "1", "input": "c"}})
        with mock.patch.object(lp, "ppa_sources", return_value=self.staging), \
                mock.patch.object(lp, "debian_version", return_value=("160.0.1-1", "unstable")) as debian, \
                mock.patch.object(lp, "ubuntu_version", side_effect=lambda source, series: self.ubuntu[source]):
            approve.check_behind(s, self.pkgs)
        debian.assert_called_once_with("firefox", ["sid"])
        self.assertEqual(sorted(s["behind"]), ["firefox", "nux", "unity"])
        self.assertEqual(s["behind"]["unity"]["since"], "2026-11-20T00:00:00Z")
        self.assertEqual(s["behind"]["firefox"]["base"], "160.0.1-1")
        self.assertEqual(s["behind"]["nux"]["hold"], "until a patch applies")
        self.assertEqual(sorted(s["uptodate"]), ["hud"])

    def test_rows_after_a_day_and_failed_builds(self):
        now = approve.utc_now()
        s = state(behind={"unity": {"base": "2", "staging": "1+gu7.1~26.10", "hold": "", "since": "2026-11-20T00:00:00Z"},
                          "hud": {"base": "2", "staging": "1+gu7.1~26.10", "hold": "", "since": now}},
                  failed_builds={"nux": {"run_id": "9", "since": "2026-11-21T03:00:00Z"}})
        rows = approve.behind_rows(s)
        self.assertEqual(len(rows), 2)
        self.assertIn("`nux`: the build in `ppa.yml` failed", rows[0])
        self.assertIn("actions/runs/9", rows[0])
        self.assertIn("`unity`: `2` since 2026-11-20", rows[1])
        self.assertIn("## Behind Ubuntu and Debian", approve.render(s))


class Plan(unittest.TestCase):
    """plan.sh with a stub lp.py: a package that the last build found up to
    date is skipped with the same base version and built for a new one."""
    STUB = """import json, os, sys
if sys.argv[1] == "ubuntu-version":
    print(os.environ["STUB_BASE"], "Release")
elif sys.argv[1] == "ppa-latest":
    print(json.dumps({"version": os.environ["STUB_STAGING"], "input": "other"}))
"""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        os.makedirs(os.path.join(self.tmp, "scripts"))
        for name in ("plan.sh", "lib.sh"):
            shutil.copy(os.path.join(ROOT, "scripts", name), os.path.join(self.tmp, "scripts"))
        shutil.copy(os.path.join(ROOT, "config.sh"), self.tmp)
        with open(os.path.join(self.tmp, "scripts", "lp.py"), "w") as f:
            f.write(self.STUB)
        os.makedirs(os.path.join(self.tmp, "packages", "foo"))
        with open(os.path.join(self.tmp, "packages", "foo", "package.sh"), "w") as f:
            f.write('OVERLAY_PKG="unity-base/foo"\nUBUNTU_SRC="foo"\n')
        os.makedirs(os.path.join(self.tmp, "overlay"))

    def plan(self, base, staging, uptodate):
        state_file = os.path.join(self.tmp, "state.json")
        with open(state_file, "w") as f:
            json.dump({"uptodate": {"foo": uptodate}}, f)
        env = dict(os.environ, OVERLAY_DIR=os.path.join(self.tmp, "overlay"), STUB_BASE=base,
                   STUB_STAGING=staging)
        out = subprocess.run([os.path.join(self.tmp, "scripts", "plan.sh"), "--state", state_file],
                             env=env, capture_output=True, text=True, check=True).stdout
        return json.loads(out)

    def test_uptodate(self):
        input_hash = subprocess.run(["bash", "-c", "source scripts/lib.sh; load_package foo; input_hash overlay"],
                                    cwd=self.tmp, capture_output=True, text=True, check=True).stdout.strip()
        uptodate = {"version": "1.0-1+gu7.1~26.10", "base": "1.0-1", "input": input_hash}
        self.assertEqual(self.plan("1.0-1", "1.0-1+gu7.1~26.10", uptodate), [])
        self.assertEqual(self.plan("1.0-2", "1.0-1+gu7.1~26.10", uptodate), ["foo"])
        self.assertEqual(self.plan("1.0-1", "1.0-1+gu7.1~26.10", dict(uptodate, input="other")), ["foo"])


class AddReview(unittest.TestCase):
    def test_uptodate_drops_the_version_for_review_and_records_failed_builds(self):
        s = state(review={"unity": {"version": "1-1+gu7.3~26.10", "base": "1-1", "input": "old"}},
                  failed_builds={"hud": {"run_id": "1", "since": "2026-11-20T00:00:00Z"}})
        jobs = {"jobs": [{"name": "plan", "conclusion": "success"},
                         {"name": "build (unity)", "conclusion": "success"},
                         {"name": "build (hud)", "conclusion": "success"},
                         {"name": "build (nux)", "conclusion": "failure"}]}
        with tempfile.TemporaryDirectory() as tmp:
            directory = os.path.join(tmp, "unity")
            os.makedirs(directory)
            with open(os.path.join(directory, "result.env"), "w") as f:
                f.write("STATUS=uptodate\nPACKAGE=unity\nSOURCE=unity\nVERSION=1-1+gu7.2~26.10\nINPUT=new\n")
            args = argparse.Namespace(run_id="7", artifact_prefix="source-", dirs=[directory],
                                      planned=json.dumps(["unity", "hud", "nux"]))
            with mock.patch.object(approve, "find_issue", return_value=None), \
                    mock.patch.object(approve, "load_state", return_value=s), \
                    mock.patch.object(approve, "github", return_value=jobs), \
                    mock.patch.object(approve, "refresh"):
                approve.cmd_add_review(args)
        self.assertNotIn("unity", s["review"])
        self.assertEqual(s["uptodate"]["unity"], {"version": "1-1+gu7.2~26.10", "base": "1-1", "input": "new"})
        self.assertEqual(sorted(s["failed_builds"]), ["nux"])
        self.assertEqual(s["failed_builds"]["nux"]["run_id"], "7")


class Promote(unittest.TestCase):
    pkgs = {"unity": {"source": "unity", "group": "desktop"},
            "g-unity7-meta": {"source": "g-unity7-meta", "group": "desktop"},
            "g-unity7-apt-pin": {"source": "g-unity7-apt-pin", "group": "desktop"},
            "firefox": {"source": "firefox", "group": "mozilla"},
            "hud": {"source": "hud", "group": ""}}

    @staticmethod
    def row(name, group, staging="1+gu7.2~26.10", main="", build="ok"):
        return {"source": name, "group": group, "staging": staging, "main": main, "state": build,
                "builds": [], "changes": "new package", "security": False}

    def rows(self):
        return {name: self.row(name, pkg["group"]) for name, pkg in self.pkgs.items()}

    def promote(self, table, current, names=(), force=False, dry_run=False, fail=()):
        s = state(promote=table)
        copied = []
        real_run = subprocess.run

        def run(cmd, *args, **kwargs):
            if not cmd[0].endswith("/lp_write.py"):
                return real_run(cmd, *args, **kwargs)
            source = cmd[cmd.index("copy") + 1]
            copied.append(source)
            return subprocess.CompletedProcess(cmd, 1 if source in fail else 0, stdout="Pending\n",
                                               stderr="copy error")
        with mock.patch.object(approve, "promote_rows", return_value=(current, [])), \
                mock.patch.object(approve.subprocess, "run", side_effect=run):
            messages = approve.do_promote(s, list(names), force, self.pkgs, dry_run)
        return messages, copied

    def test_order(self):
        messages, copied = self.promote(self.rows(), self.rows())
        self.assertEqual(copied, ["unity", "g-unity7-apt-pin", "g-unity7-meta", "firefox", "hud"])
        self.assertEqual(len(messages), 5)

    def test_member_new_in_staging_stops_its_group_and_the_mozilla_group(self):
        current = self.rows()
        current["g-unity7-settings"] = self.row("g-unity7-settings", "desktop")
        messages, copied = self.promote(self.rows(), current)
        self.assertEqual(copied, ["hud"])
        self.assertIn("group `desktop` is incomplete (g-unity7-settings)", messages[0])
        self.assertTrue(any("`firefox`: needs `g-unity7-apt-pin`" in m for m in messages))

    def test_changed_staging_version(self):
        table = self.rows()
        table["unity"] = self.row("unity", "desktop", staging="1+gu7.1~26.10")
        messages, copied = self.promote(table, self.rows(), names=["unity"])
        self.assertEqual(copied, [])
        self.assertIn("staging now has `1+gu7.2~26.10` instead of `1+gu7.1~26.10`", messages[0])

    def test_failed_copy_stops_the_group_and_the_packages_that_need_it(self):
        messages, copied = self.promote(self.rows(), self.rows(), fail=["unity"])
        self.assertEqual(copied, ["unity", "hud"])
        self.assertTrue(any("`g-unity7-meta`: not copied, because a copy in group `desktop` failed" in m
                            for m in messages))
        self.assertTrue(any("`firefox`: not copied, because `g-unity7-apt-pin` was not copied" in m
                            for m in messages))

    def test_dry_run(self):
        messages, copied = self.promote(self.rows(), self.rows(), dry_run=True)
        self.assertEqual(copied, [])
        self.assertIn("`unity` `1+gu7.2~26.10` would be copied", messages[0])


class StateFormat(unittest.TestCase):
    def test_round_trip(self):
        s = state(review={"unity": {"version": "1+gu7.2~26.10", "base": "1", "input": "abc", "run_id": "1",
                                    "reason": "new package", "artifact": "source-unity"}})
        body = approve.render(s)
        self.assertEqual(approve.load_state({"number": 1, "body": body}), s)
        self.assertEqual(s["version"], approve.STATE_VERSION)


class PromoteRows(unittest.TestCase):
    def test_kept_row_takes_the_group_of_package_sh(self):
        old = {"nemo-engrampa": {"source": "nemo-engrampa", "group": "", "staging": "6.6.0-1+gu7.1~26.10",
                                 "main": "", "state": "ok", "builds": [], "changes": "new package",
                                 "security": False}}
        pkgs = {"nemo-engrampa": {"source": "nemo-engrampa", "group": "desktop"}}
        listings = {"c4pp4/g-unity7-staging": {"nemo-engrampa": {"version": "6.6.0-1+gu7.1~26.10"}},
                    "c4pp4/g-unity7": {}}
        with mock.patch.object(lp, "ppa_sources", side_effect=lambda ppa, series: listings[ppa]), \
                mock.patch.object(lp, "build_state_of", side_effect=AssertionError("no query")), \
                mock.patch.object(lp, "changelog_data", side_effect=AssertionError("no query")):
            rows, stale = approve.promote_rows(pkgs, old)
        self.assertEqual(rows["nemo-engrampa"]["group"], "desktop")
        self.assertEqual(old["nemo-engrampa"]["group"], "")
        self.assertEqual(stale, [])


class DebianVersion(unittest.TestCase):
    def test_prerelease_left_out(self):
        madison = [{"thunderbird": {"experimental": {"1:132.0~b6-1": {}, "1:131.0-1": {}}}}]
        with mock.patch.object(lp, "get", return_value=madison):
            self.assertEqual(lp.debian_version("thunderbird", ["experimental"]),
                             ("1:131.0-1", "experimental"))


if __name__ == "__main__":
    unittest.main()
