OVERLAY_PKG="unity-lens/unity-lens-photos"
UBUNTU_SRC="unity-lens-photos"
GROUP="desktop"

## remove-goa-scopes.diff stops installing the Facebook, Flickr and Picasa scopes,
##  their files are not deleted as in the ebuild (the 1.0 source format can't
##  represent the deletion).
PATCHES=(
	Fix-timestamp-NoneType-error.patch
	remove-goa-scopes.diff
	Show-photo-in-default-file-manager.patch
	Fix-scope-crash.patch
	Fix-preview-crash.patch
)

debian_edit() {
	# Only the Facebook, Flickr and Picasa scopes need online accounts (remove-goa-scopes.diff) #
	sed -i \
		-e "/^ *gir1.2-accounts-1.0,$/d" \
		-e "/^ *gir1.2-gdata-0.0,$/d" \
		-e "/^ *gir1.2-signon-2.0,$/d" \
		-e "/^ *gir1.2-soup-2.4,$/d" \
		-e "/^ *python3-httplib2,$/d" \
		-e "/^ *python3-oauthlib,$/d" \
		debian/control || return 1
	! grep -Eq "gir1.2-(accounts|gdata|signon|soup)|python3-(httplib2|oauthlib)" debian/control || return 1
}

src_edit() {
	# Fix .desktop file name #
	sed -i \
		-e "s/shotwell\.desktop/org.gnome.Shotwell.desktop/" \
		src/unity_shotwell_daemon.py || return 1
	grep -Fq "org.gnome.Shotwell.desktop" src/unity_shotwell_daemon.py || return 1

	# Don't install the scope daemon as a top-level Python module #
	# (setuptools discovers the daemons in src, the removed scopes as well) #
	sed -i \
		-e 's/setup(name="unity-lens-photos",/setup(name="unity-lens-photos", py_modules=[],/' \
		setup.py || return 1
	grep -Fq 'setup(name="unity-lens-photos", py_modules=[],' setup.py || return 1
}
