OVERLAY_PKG="unity-base/nux"
UBUNTU_SRC="nux"
GROUP="desktop"

PATCHES=(
	migrate-to-libpcre2.patch
)

debian_edit() {
	# The session of Unity is unity, not ubuntu #
	sed -i -e "s:xubuntu:xunity:" debian/50_check_unity_support || return 1
	grep -Fq '"x$DESKTOP_SESSION" = "xunity"' debian/50_check_unity_support || return 1

	# Fix AM_CXXFLAGS typo of the Debian patch #
	sed -i -e "s/^+AM_CXXFLAGS-/+AM_CXXFLAGS=/" debian/patches/drop-std.patch || return 1
	grep -Fq '+AM_CXXFLAGS="$CXXFLAGS"' debian/patches/drop-std.patch || return 1

	# Replace Debian PCRE2 migration patch (it leaked the compiled pattern) #
	sed -i -e "s/^migrate-to-libpcre2\.patch$/#migrate-to-libpcre2.patch/" debian/patches/series || return 1
	grep -Fxq "#migrate-to-libpcre2.patch" debian/patches/series || return 1
}
