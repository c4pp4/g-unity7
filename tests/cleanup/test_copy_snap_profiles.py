"""Unit tests of the functions of copy-snap-profiles. tests/cleanup/test.sh runs
the whole program in an Ubuntu container.

    python3 -m unittest discover -s tests/cleanup
"""
import importlib.machinery
import importlib.util
import os
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def load(name, path):
    """Load a program without the .py suffix as a module."""
    loader = importlib.machinery.SourceFileLoader(name, path)
    module = importlib.util.module_from_spec(importlib.util.spec_from_loader(name, loader))
    loader.exec_module(module)
    return module


copy = load("copy_snap_profiles", os.path.join(ROOT, "local/g-unity7-meta/copy-snap-profiles"))


class Files(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def path(self, name, text=None):
        path = os.path.join(self.dir, name)
        if text is not None:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as file:
                file.write(text)
        return path

    def text(self, name):
        with open(self.path(name), encoding="utf-8") as file:
            return file.read()


class DefaultProfile(Files):
    def test_the_profile_with_default_or_the_only_one(self):
        ini = self.path("a.ini", "[General]\nStartWithLastProfile=1\n\n[Profile1]\nName=b\nPath=b.x\n\n"
                                 "[Profile0]\nName=a\nPath=a.x\nDefault=1\n\n[InstallABC]\nDefault=old\n")
        self.assertEqual(copy.moz_default_profile(ini), "a.x")
        ini = self.path("b.ini", "[Profile0]\nPath=only\n")
        self.assertEqual(copy.moz_default_profile(ini), "only")
        ini = self.path("c.ini", "[Profile0]\nPath=a\n[Profile1]\nPath=b\n")
        self.assertEqual(copy.moz_default_profile(ini), "")
        self.assertEqual(copy.moz_default_profile(self.path("missing.ini")), "")

    def test_the_fields_are_split_at_each_equals_sign_as_awk_does(self):
        ini = self.path("a.ini", "[Profile0]\nPath=a=b\nDefault=1\n")
        self.assertEqual(copy.moz_default_profile(ini), "a")
        ## Default=01 is not Default=1, and [Profile] is not a profile section
        ini = self.path("b.ini", "[Profile]\nPath=x\n[Profile0]\nPath=a\nDefault=01\n")
        self.assertEqual(copy.moz_default_profile(ini), "a")


class SetDefault(Files):
    def test_the_section_gets_one_default_and_the_end_one_newline(self):
        ini = self.path("profiles.ini", "[General]\nVersion=2\n\n[InstallH]\nDefault=old\nLocked=1\nDefault=older\n\n\n")
        copy.ini_set_default(ini, "InstallH", "new")
        self.assertEqual(self.text("profiles.ini"),
                         "[General]\nVersion=2\n\n[InstallH]\nDefault=new\nLocked=1\n")

    def test_a_missing_section_or_file_is_added(self):
        ini = self.path("installs.ini", "[Other]\nDefault=x\n")
        copy.ini_set_default(ini, "H", "p")
        self.assertEqual(self.text("installs.ini"), "[Other]\nDefault=x\n\n[H]\nDefault=p\nLocked=1\n")
        copy.ini_set_default(self.path("new.ini"), "H", "p")
        self.assertEqual(self.text("new.ini"), "\n[H]\nDefault=p\nLocked=1\n")


class Names(Files):
    def test_a_free_name_in_the_directory_and_the_temporary_directory(self):
        dst, tmp = self.path("dst"), self.path("tmp")
        os.makedirs(dst)
        os.makedirs(tmp)
        self.assertEqual(copy.free_name("p", dst, tmp), "p")
        os.mkdir(os.path.join(dst, "p"))
        self.assertEqual(copy.free_name("p", dst, tmp), "p-snap")
        os.mkdir(os.path.join(tmp, "p-snap"))
        self.assertEqual(copy.free_name("p", dst, tmp), "p-snap2")

    def test_the_entries_as_the_globs_list_them(self):
        for name in ("b", "a", ".h", "..x", "Z"):
            os.mkdir(self.path(name))
        self.assertEqual(copy.entries(self.dir), ["Z", "a", "b", ".h", "..x"])


class Profiles(Files):
    def test_the_profile_sections_with_a_path(self):
        ini = self.path("profiles.ini", "[General]\nPath=no\n[Profile0]\nName=a=b\nIsRelative=1\nPath=p\n"
                                        "StoreID=s\nShowSelector=0\n[Profile1]\nName=no path\n[Install1]\nPath=x\n")
        self.assertEqual(copy.profile_entries(ini), [("a=b", "p", "1", "s", "0")])

    def test_the_next_profile_number(self):
        self.assertEqual(copy.next_profile_number(self.path("a.ini", "[Profile0]\n[Profile12]\n[Profile3]\n")), 13)
        self.assertEqual(copy.next_profile_number(self.path("b.ini", "[General]\n")), 0)
        self.assertEqual(copy.next_profile_number(self.path("missing.ini")), 0)

    def test_a_member_of_a_profile_group(self):
        self.path("p/prefs.js", 'user_pref("toolkit.profiles.storeID", "abc");\n')
        self.assertTrue(copy.moz_group_member(self.path("p"), ["x", "abc"]))
        self.assertFalse(copy.moz_group_member(self.path("p"), ["x"]))
        self.assertFalse(copy.moz_group_member(self.path("none"), ["abc"]))


class Newer(Files):
    def test_a_file_changed_after_the_marker(self):
        self.path("src/p/prefs.js", "x")
        marker = self.path("marker", "id src\n")
        for root, dirs, files in os.walk(self.path("src")):
            for name in dirs + files + [""]:
                os.utime(os.path.join(root, name), ns=(1, 1))
        os.utime(marker, ns=(2, 2))
        self.assertFalse(copy.newer_than(self.path("src"), marker))
        os.utime(self.path("src/p/prefs.js"), ns=(3, 3))
        self.assertTrue(copy.newer_than(self.path("src"), marker))
        self.assertFalse(copy.newer_than(self.path("src"), self.path("missing")))


if __name__ == "__main__":
    unittest.main()
