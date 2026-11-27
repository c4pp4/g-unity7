OVERLAY_PKG="x11-misc/gtk-nocsd"
UBUNTU_SRC="gtk-nocsd"
GROUP="desktop"

## keep-the-corner-radius-of-menu-windows.patch: GTK publishes the corner
##  radius of a menu window to Unity, which draws the shadow of the menu with it
##  (unity, yaru-theme), and the CSS of gtk-nocsd removed the radius. The
##  ebuild's 51-gtk-nocsd preloads the library in the X session on Gentoo;
##  Ubuntu's libgtk-nocsd0 does it in /usr/lib/environment.d/50-gtk-nocsd.conf.
PATCHES=(
	keep-the-corner-radius-of-menu-windows.patch
)
