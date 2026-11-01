OVERLAY_PKG="ehooks/gnome-extra/evolution-data-server"
UBUNTU_SRC="evolution-data-server"

## Use-libnotify-when-available.patch is the variant of
##  packages/evolution-data-server/patches (the context of the libnotify include).
PATCHES=(
	Use-libnotify-when-available.patch
)

debian_edit() {
	# Plain reminder notifications in Unity (Use-libnotify-when-available.patch) #
	sed -i -e "s/^\( *\)libnspr4-dev,$/\1libnotify-dev,\n&/" debian/control || return 1
	grep -q "^ *libnotify-dev,$" debian/control || return 1
}
