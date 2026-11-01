OVERLAY_PKG="unity-lens/unity-scope-extras"
UBUNTU_SRC="unity-scope-audacious"
## Removed from Ubuntu after xenial, the source of xenial is used.
UBUNTU_SERIES="xenial"
GROUP="desktop"

PATCHES=(
	audacious.patch
)

debian_edit() {
	# GObject introspection data of libunity 7 #
	sed -i -e "s/gir1.2-unity-5.0/gir1.2-unity-7.0/" debian/control || return 1
	! grep -Fq "gir1.2-unity-5.0" debian/control || return 1

	# The python3 sequence of debhelper is in dh-python #
	sed -i -e "s/^Build-Depends: debhelper (>= 9),$/&\n               dh-python,/" debian/control || return 1
	grep -q "^ *dh-python,$" debian/control || return 1

	# The album art is read with mutagen (audacious.patch) #
	sed -i -e "s/^\( *\)python3-dbus,$/&\n\1python3-mutagen,/" debian/control || return 1
	grep -q "^ *python3-mutagen,$" debian/control || return 1
}

src_edit() {
	# Don't install the scope daemon as a top-level Python module #
	sed -i "s/^setup(name=/setup(py_modules=[], packages=[], name=/" setup.py || return 1
	grep -Fq "setup(py_modules=[], packages=[], name=" setup.py || return 1
}
