## Derived source: the Qt 6 build of dee-qt (Qt6-migration.patch builds only
##  Qt 6), beside the Qt 5 packages of Ubuntu, for unity-base/hud.
OVERLAY_PKG="x11-libs/dee-qt"
UBUNTU_SRC="dee-qt"
SOURCE_NAME="dee-qt6"
GROUP="desktop"

PATCHES=(
	Qt6-migration.patch
)

debian_edit() {
	# The Qt 5 packaging is replaced by packages/dee-qt6/debian #
	rm -f debian/compat debian/libdee-qt5-3.install debian/libdee-qt5-dev.install \
		debian/qtdeclarative5-dee-plugin.install || return 1
	sed -i -e "s/@MAINTAINER@/${DEBFULLNAME} <${DEBEMAIL}>/" debian/control || return 1
	! grep -q "qt5\|@MAINTAINER@" debian/control debian/rules || return 1
}
