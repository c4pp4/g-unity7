OVERLAY_PKG="unity-lens/unity-lens-applications"
UBUNTU_SRC="unity-lens-applications"
GROUP="desktop"

PATCHES=(
	remove-software-center-filter-option.patch
)

src_edit() {
	# Remove failed test #
	# (Environment.get_home_dir() returns HOME, which is not the passwd home directory in the build) #
	sed -i \
		-e "/test ~username expansion/,+4 d" \
		tests/unit/test-utils.vala || return 1
	! grep -Fq "test ~username expansion" tests/unit/test-utils.vala || return 1
}
