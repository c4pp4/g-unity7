"""Unit tests of scripts/lp.py and scripts/approve.py, without network. dpkg
compares the versions, so run them on Ubuntu or Debian:

  python3 -m unittest discover -s tests/scripts -v
"""

import json
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "scripts"))
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

    def run_check(self, s, versions):
        files = ["unity-base/unity/unity-7.7.1-r261008.ebuild", "unity-base/unity/files/a.patch",
                 "eclass/ubuntu-versionator.eclass"]
        with mock.patch.object(approve, "overlay_head", return_value="h" * 40), \
                mock.patch.object(approve, "overlay_changes", return_value=(files, "https://example.org/c")), \
                mock.patch.object(lp, "ubuntu_version", side_effect=lambda source, series: versions.get(source, (None, None))):
            approve.check_drift(s, self.pkgs)

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
