OVERLAY_PKG="unity-base/unity"
UBUNTU_SRC="unity"
GROUP="desktop"

## The default USE flags of the ebuild: -classic-dash -classic-panel +hud
##  -systray -bfb2013 -bfb2023 +uwidgets. set-desktop-name.patch is the
##  variant of packages/unity/patches (G Unity⁷ Desktop).
PATCHES=(
	add-nemo-support.patch
	add-unity-version-xml.patch
	fix-dash-preview-thumbnails.patch
	fix-recently-used-tracking-for-DBusActivatable-apps.patch
	prevent-compiz-segfault-by-guarding-pthread_join.patch
	prevent-duplicate-reboot-shutdown-dialog.patch
	remove-all-code-related-to-online-search.patch
	revert-unwanted-ubuntu-unity-changes.patch
	set-desktop-name.patch
	dash-and-hud-border-fixes.patch
	transparent-panel-fixes.patch
)

debian_edit() {
	local f

	# compiz-dev of Ubuntu was built with CMake 4.2 and installs FindCompiz.cmake #
	#  into /usr/share/cmake-4.2/Modules, CMake 4.3 does not find it there #
	sed -i \
		-e "s/^\( *\)compiz-dev (>= [^)]*),$/\1compiz-dev (>= 1:0.9.14.2+25.10.20250930-0ubuntu3+gu7),/" \
		debian/control || return 1
	grep -q "^ *compiz-dev (>= 1:0.9.14.2+25.10.20250930-0ubuntu3+gu7),$" debian/control || return 1

	# Release shown in the Details panel of unity-control-center (add-unity-version-xml.patch) #
	sed -i \
		-e "s/^cmake_options += -DENABLE_UNIT_TESTS=OFF$/&\ncmake_options += -DUNITY_RELEASE=\"${series_version} ${series^}\"/" \
		debian/rules || return 1
	grep -Fqx "cmake_options += -DUNITY_RELEASE=\"${series_version} ${series^}\"" debian/rules || return 1
	echo "usr/share/unity/unity-version.xml" >> debian/unity.install || return 1

	# Hidden logo of the lock-screen and the Dash and Hud border #
	install -d debian/g-unity7 || return 1
	install -m 644 "${FILESDIR}"/branding/empty_cof.png debian/g-unity7/lockscreen_cof.png || return 1
	for f in "${FILESDIR}"/resources/dash_*.png; do
		install -m 644 "${f}" debian/g-unity7/ || return 1
	done
	printf '\n%s\n\t%s\n' \
		"execute_after_dh_install:" \
		"install -m 644 debian/g-unity7/*.png debian/libunity-core-6.0-9/usr/share/unity/icons/" \
		>> debian/rules || return 1
	grep -Pq "^\tinstall -m 644 debian/g-unity7/\*\.png " debian/rules || return 1
}

src_edit() {
	# Tweak preview width #
	sed -i \
		-e "/preview_width =/{s/770/700/}" \
		unity-shared/PreviewStyle.cpp || return 1
	grep -Fq "const RawPixel preview_width = 700_em;" unity-shared/PreviewStyle.cpp || return 1

	# Setup Unity side launcher default applications #
	sed -i \
		-e "s/org.gnome.Nautilus/nemo/" \
		-e "/firefox/r ${PKG_DIR}/www-clients" \
		-e '/ubiquity/d' \
		-e '/org.gnome.Software/d' \
		data/com.canonical.Unity.gschema.xml || return 1
	grep -Fq "'application://nemo.desktop'" data/com.canonical.Unity.gschema.xml || return 1
	grep -Fq "'application://firefox_firefox.desktop'" data/com.canonical.Unity.gschema.xml || return 1
	! grep -q "ubiquity\|org.gnome.Software" data/com.canonical.Unity.gschema.xml || return 1

	# Change ubuntu to unity #
	sed -i \
		-e 's:SESSION=ubuntu:SESSION=unity:g' \
		{data/unity7.conf.in,services/unity-panel-service.conf.in} || return 1
	! grep -Fq "SESSION=ubuntu" {data/unity7.conf.in,services/unity-panel-service.conf.in} || return 1

	sed -i \
		-e 's:ubuntu.session:unity.session:g' \
		-e 's:gnome-session:cinnamon-session:g' \
		tools/{systemd,upstart}-prestart-check || return 1
	grep -Fq "/usr/share/cinnamon-session/sessions/unity.session" tools/systemd-prestart-check || return 1

	# Stop unity-panel-service before the indicator services #
	#  It re-activates them via D-Bus while they are stopping #
	sed -i \
		-e "/^After=/{s/$/ indicator-application.service indicator-bluetooth.service indicator-datetime.service indicator-keyboard.service indicator-messages.service indicator-power.service indicator-printers.service indicator-session.service indicator-sound.service/}" \
		services/unity-panel-service.service.in || return 1
	grep -q "^After=unity7.service indicator-application.service .* indicator-sound.service$" services/unity-panel-service.service.in || return 1

	# unity-gtk-module is replaced by appmenu-gtk-module #
	sed -i \
		-e 's:unity-gtk-module.service ::' \
		data/unity7.service.in || return 1
	! grep -Fq "unity-gtk-module.service" data/unity7.service.in || return 1

	# Use 12px font size for multirange filter option #
	sed -i \
		-e "/const int FONT_SIZE_PX/{s/10/12/}" \
		dash/FilterMultiRangeButton.cpp || return 1
	grep -Fq "const int FONT_SIZE_PX = 12;" dash/FilterMultiRangeButton.cpp || return 1

	# Fix warning: the address of ‘nux::Event::text’ will never be NULL #
	sed -i \
		-e "s/event->text && //" \
		a11y/unity-util-accessible.cpp || return 1

	# Remove upstart integration #
	sed -i "/[Uu]pstart/d" lockscreen/LockScreenController.{cpp,h} || return 1
}
