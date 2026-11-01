OVERLAY_PKG="unity-lens/unity-lens-video"
UBUNTU_SRC="unity-lens-video"
GROUP="desktop"

PATCHES=(
	Remove-remote-video-support.patch
	Use-Nemo-thumbnail-factory.patch
)

debian_edit() {
	# The remote video scope is removed (Remove-remote-video-support.patch) #
	sed -i \
		-e "/^Recommends: unity-scope-video-remote$/d" \
		-e "/^Package: unity-scope-video-remote$/,\$d" \
		debian/control || return 1
	sed -i -e "\$d" debian/control || return 1
	rm debian/unity-scope-video-remote.install || return 1
	! grep -Fq "unity-scope-video-remote" debian/control || return 1
	# debhelper installs a single binary package to debian/<package>, debian/*.install #
	#  (dh_install --fail-missing) take the files from debian/tmp #
	printf '\n%s\n\t%s\n' \
		"override_dh_auto_install:" \
		"dh_auto_install --destdir=debian/tmp" \
		>> debian/rules || return 1
	grep -Pqx "\tdh_auto_install --destdir=debian/tmp" debian/rules || return 1

	# libsoup-gnome is used only by the remote video scope, the thumbnail factory #
	#  of cinnamon-desktop is used instead of totem-video-thumbnailer (Use-Nemo-thumbnail-factory.patch) #
	sed -i -e "s/^\( *\)libsoup-gnome2.4-dev,$/\1libcinnamon-desktop-dev,/" debian/control || return 1
	grep -q "^ *libcinnamon-desktop-dev,$" debian/control || return 1
}

src_edit() {
	# Wait for updatedb, a search runs locate right after it #
	# (the first search found nothing, the database didn't exist yet) #
	sed -i "/updatedb_bin/{s/async/sync/}" src/locate.vala || return 1
	grep -Fq 'GLib.Process.spawn_command_line_sync (@"$updatedb_bin' src/locate.vala || return 1
}
