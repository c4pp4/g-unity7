## Derived source: a Qt 6 build of libdbusmenu-qt for unity-base/hud, next to
##  Ubuntu's Qt 5 packages. Qt6-migration.patch builds only Qt 6, with the qt6
##  suffix.
OVERLAY_PKG="dev-libs/libdbusmenu-qt"
UBUNTU_SRC="libdbusmenu-qt"
SOURCE_NAME="libdbusmenu-qt6"
GROUP="desktop"

PATCHES=(
	Qt6-migration.patch
)

debian_edit() {
	# packages/libdbusmenu-qt6/debian replaces the Qt 5 packaging #
	rm -f debian/libdbusmenu-qt5-* || return 1
	sed -i -e "s/@MAINTAINER@/${DEBFULLNAME} <${DEBEMAIL}>/" debian/control || return 1
	! grep -q "qt5\|@MAINTAINER@" debian/control debian/rules || return 1
}

src_edit() {
	# Redundant #
	sed -i -e "/add_subdirectory(tools)/d" CMakeLists.txt || return 1
	! grep -Fq "add_subdirectory(tools)" CMakeLists.txt || return 1
}
