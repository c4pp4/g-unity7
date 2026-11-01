OVERLAY_PKG="ehooks/x11-misc/zim"
UBUNTU_SRC="zim"

debian_edit() {
	# Panel icons of Yaru #
	install -d debian/g-unity7 || return 1
	cp -r "${FILESDIR}"/icons debian/g-unity7/ || return 1
	echo "debian/g-unity7/icons usr/share/" > debian/zim.install || return 1
}
