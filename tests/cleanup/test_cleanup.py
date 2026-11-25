"""Unit tests of the functions of g-unity7-cleanup that read the output of apt,
dpkg-query and the files of Firefox and Thunderbird. tests/cleanup/test.sh runs
the whole program in an Ubuntu container.

    python3 -m unittest discover -s tests/cleanup
"""
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_copy_snap_profiles import ROOT, load

cleanup = load("g_unity7_cleanup", os.path.join(ROOT, "local/g-unity7-meta/g-unity7-cleanup"))


class Text(unittest.TestCase):
    def test_lists(self):
        self.assertEqual(cleanup.and_list([]), "")
        self.assertEqual(cleanup.and_list(["a"]), "a")
        self.assertEqual(cleanup.and_list(["a", "b", "c"]), "a, b and c")
        self.assertEqual(cleanup.in_mb(1), "1 MB")
        self.assertEqual(cleanup.in_mb(1025), "2 MB")
        self.assertEqual(cleanup.relation_text("mate-utils baobab+gnome-logs"), "mate-utils | baobab + gnome-logs")

    def test_words_side_by_side_as_apt_prints_them(self):
        self.assertEqual(cleanup.list_words("Packages", [], 20), "")
        self.assertEqual(cleanup.list_words("Packages", ["aaaa", "bbbb", "cccc", "dddd"], 14),
                         "Packages (4):\n  aaaa bbbb\n  cccc dddd\n\n")
        self.assertEqual(cleanup.list_lines("Items", ["a b", "c"]), "Items (2):\n  a b\n  c\n\n")


class AptOutput(unittest.TestCase):
    def test_relations_without_versions_architectures_and_any(self):
        text = "a (>= 1), b:any | c [amd64] (<< 2),\n  d|e\n"
        self.assertEqual(cleanup.clean_relations(text), ["a", "b c", "d e"])

    def test_fields_of_apt_cache_show(self):
        show = ("Package: x\nDepends: a, b\nRecommends: c,\n d\nDescription: x\n continued\n"
                "Suggests: e\n\n")
        self.assertEqual(cleanup.clean_relations(cleanup.show_fields(show, ["Depends", "Recommends"])),
                         ["a", "b", "c", "d"])

    def test_task_packages(self):
        show = ("Package: a\nTask: ubuntu-unity-desktop, other\n\nPackage: b\nTask: other\n\n"
                "Package: c\nTask: x,ubuntu-unity-desktop\n")
        self.assertEqual(cleanup.task_packages(show, "ubuntu-unity-desktop"), ["a", "c"])

    def test_simulated_packages(self):
        text = ("Inst a [1] (2 Ubuntu:26.10 [all])\nRemv b [1]\nPurg c [1]\nConf a (2 Ubuntu:26.10 [all])\n"
                "Inst\n")
        self.assertEqual(cleanup.simulated(text, "Purg"), ["c"])
        self.assertEqual(cleanup.simulated(text, "Remv", "Purg"), ["b", "c"])

    @unittest.skipUnless(shutil.which("dpkg"), "dpkg compares the versions")
    def test_installs_upgrades_and_downgrades_once(self):
        state = cleanup.Cleanup(False, False, [])
        state.read_installs("Inst n (1 PPA [all])\nInst u [1] (2 PPA [all])\nInst d [2:1snap1] (1:1 PPA [all])\n"
                            "Inst n (1 PPA [all])\n")
        self.assertEqual((state.installs, state.upgrades, state.downgrades), (["n"], ["u"], ["d"]))


class Options(unittest.TestCase):
    def test_the_options_and_the_usage(self):
        self.assertEqual(cleanup.parse_args(["-n", "--yes", "-k", "vlc", "--keep=eog", "--keep", "vlc"]),
                         (True, True, ["vlc", "eog"]))
        for argv in (["--keep"], ["-k", "A"], ["--keep=x"], ["--bogus"]):
            with self.subTest(argv=argv), open(os.devnull, "w") as null:
                stderr, sys.stderr = sys.stderr, null
                try:
                    with self.assertRaises(cleanup.Exit) as stop:
                        cleanup.parse_args(argv)
                finally:
                    sys.stderr = stderr
                self.assertEqual(stop.exception.status, 2)


class Profiles(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, name, text):
        path = os.path.join(self.dir, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as file:
            file.write(text)
        return path

    def test_profiles_that_a_newer_major_version_used(self):
        self.write("src/a.default/compatibility.ini", "[Compatibility]\nLastVersion=161.0_20261124054846/2026\n")
        self.write("src/b.default/compatibility.ini", "[Compatibility]\nLastVersion=153.8.0_20261120/2026\n")
        self.write("src/c.default/compatibility.ini", "[Compatibility]\nLastVersion=Safe Mode\n")
        self.write("src/d.default/prefs.js", "")
        src = os.path.join(self.dir, "src")
        self.assertEqual(cleanup.moz_newer_profiles(src, "153"), [("161", f"{src}/a.default")])
        self.assertEqual(cleanup.moz_newer_profiles(src, "161"), [])
        self.assertEqual(cleanup.moz_newer_profiles(src, "x"), [])

    def test_absolute_profiles_in_the_snap_directory(self):
        ini = self.write("profiles.ini", "[Profile0]\nIsRelative=0\nPath=/home/a/snap/firefox/x\n"
                                         "[Profile1]\nIsRelative=1\nPath=y\n[Profile2]\nIsRelative=0\nPath=/tmp/z\n")
        self.assertEqual(cleanup.moz_absolute_profiles(ini, "/home/a/snap/firefox/"), ["/home/a/snap/firefox/x"])

    def test_the_package_profile_directory(self):
        home = self.dir
        self.assertEqual(cleanup.deb_profile_dir(home, ".mozilla/firefox", ".config/mozilla/firefox"),
                         f"{home}/.mozilla/firefox")
        os.makedirs(f"{home}/.config/mozilla/firefox")
        self.assertEqual(cleanup.deb_profile_dir(home, ".mozilla/firefox", ".config/mozilla/firefox"),
                         f"{home}/.config/mozilla/firefox")
        os.makedirs(f"{home}/.mozilla")
        self.assertEqual(cleanup.deb_profile_dir(home, ".mozilla/firefox", ".config/mozilla/firefox"),
                         f"{home}/.mozilla/firefox")

    def test_the_languages_in_use(self):
        default = self.write("locale", 'LANG="cs_CZ.UTF-8"\nLANGUAGE="cs:en"\nLC_TIME=en_GB\n')
        self.write("users/alice", "[User]\nLanguage=pt_BR.UTF-8\n")
        self.write("users/.hidden", "[User]\nLanguage=de_DE.UTF-8\n")
        self.assertEqual(cleanup.used_locales(default, os.path.join(self.dir, "users")),
                         ["cs_CZ.UTF-8", "cs", "en", "pt_BR.UTF-8"])

    def test_readlink_f(self):
        os.makedirs(f"{self.dir}/real")
        os.symlink(f"{self.dir}/real", f"{self.dir}/link")
        real = os.path.realpath(f"{self.dir}/real")
        self.assertEqual(cleanup.readlink_f(f"{self.dir}/link"), real)
        self.assertEqual(cleanup.readlink_f(f"{self.dir}/link/new"), f"{real}/new")
        self.assertEqual(cleanup.readlink_f(f"{self.dir}/missing/new"), "")


if __name__ == "__main__":
    unittest.main()
