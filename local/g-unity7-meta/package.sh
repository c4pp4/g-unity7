## Own package: g-unity7-desktop, with the dependencies of unity-base/unity-meta,
##  unity-indicators/unity-indicators-meta and unity-lens/unity-lens-meta. The
##  overlay's default USE flags go to Recommends, the rest to Suggests. The
##  gnome USE flag counts as a default one, because the desktop/gnome parent
##  profile enables it. Recommends also has
##  compizconfig-settings-manager, which the overlay installs with
##  unity-base/compiz. debian/control groups the relations with comments. Ported
##  packages are required in their G Unity⁷ version (>= ...+gu7). Ported packages
##  in Recommends and Suggests also get Breaks (<< ...+gu7), because the apt 3
##  solver does not upgrade an installed package for a Recommends. It skips the
##  relation or picks another alternative instead (audacious for rhythmbox).
##  system-config-printer-common gets Breaks too: Ubuntu installs it with
##  gnome-control-center, and system-config-printer needs the same version.
OVERLAY_PKG="unity-base/unity-meta"
GROUP="desktop"
