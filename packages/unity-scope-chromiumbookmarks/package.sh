OVERLAY_PKG="unity-lens/unity-scope-extras"
UBUNTU_SRC="unity-scope-chromiumbookmarks"
## Removed from Ubuntu after bionic, the source of bionic is used.
UBUNTU_SERIES="bionic"
GROUP="desktop"

## snap-profiles.patch in packages/unity-scope-chromiumbookmarks/patches is our own patch for Ubuntu.
PATCHES=(
	chromiumbookmarks.patch
	snap-profiles.patch
)

debian_edit() {
	# GObject introspection data of libunity 7 #
	sed -i -e "s/gir1.2-unity-5.0/gir1.2-unity-7.0/" debian/control || return 1
	! grep -Fq "gir1.2-unity-5.0" debian/control || return 1

	# The python3 sequence of debhelper is in dh-python #
	sed -i -e "s/^Build-Depends: debhelper (>= 9),$/&\n               dh-python,/" debian/control || return 1
	grep -q "^ *dh-python,$" debian/control || return 1
}

src_edit() {
	# Don't install the scope daemon as a top-level Python module #
	sed -i "s/^setup(name=/setup(py_modules=[], packages=[], name=/" setup.py || return 1
	grep -Fq "setup(py_modules=[], packages=[], name=" setup.py || return 1
}
