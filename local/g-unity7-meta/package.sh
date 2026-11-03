## Own package: g-unity7-desktop, the dependencies of unity-base/unity-meta,
##  unity-indicators/unity-indicators-meta and unity-lens/unity-lens-meta with
##  the default USE flags of the overlay (Recommends) and the rest (Suggests).
##  The ported packages are required in their G Unity⁷ version (>= ...+gu7).
##  Breaks (<< ...+gu7) of the ported packages in Recommends and Suggests: the
##  solver of apt 3 does not upgrade an installed package for a Recommends, it
##  skips the relation or takes another alternative (audacious for rhythmbox).
OVERLAY_PKG="unity-base/unity-meta"
GROUP="desktop"
