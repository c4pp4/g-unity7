## Derived source: the Qt 6 build of libdbusmenu-qt (Qt6-migration.patch builds
##  only Qt 6, with the qt6 suffix), beside the Qt 5 packages of Ubuntu, for
##  unity-base/hud.
OVERLAY_PKG="dev-libs/libdbusmenu-qt"
UBUNTU_SRC="libdbusmenu-qt"
SOURCE_NAME="libdbusmenu-qt6"
GROUP="desktop"

PATCHES=(
	Qt6-migration.patch
)

debian_edit() {
	# The Qt 5 packaging is replaced by packages/libdbusmenu-qt6/debian #
	rm -f debian/libdbusmenu-qt5-* || return 1
	sed -i -e "s/@MAINTAINER@/${DEBFULLNAME} <${DEBEMAIL}>/" debian/control || return 1
	! grep -q "qt5\|@MAINTAINER@" debian/control debian/rules || return 1
}

src_edit() {
	# Redundant #
	sed -i -e "/add_subdirectory(tools)/d" CMakeLists.txt || return 1
	! grep -Fq "add_subdirectory(tools)" CMakeLists.txt || return 1
}
