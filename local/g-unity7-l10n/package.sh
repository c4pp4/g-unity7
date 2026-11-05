## Own package: the translations of unity-base/unity-language-pack that no
##  package and no language pack of Ubuntu installs, for the ported packages
##  (/usr/share/locale, a language pack would take precedence). The other
##  translations of the ebuild are in the language packs of Ubuntu, except the
##  legacy ones of unity and unity-control-center (shadowed by the language
##  packs) and those of the languages Ubuntu has no language pack for any more.
OVERLAY_PKG="unity-base/unity-language-pack"
GROUP="desktop"

local_prepare() {
	local tarball domain

	## <tarball of the ebuild> <gettext domain>
	while read -r tarball domain; do
		mkdir -p po/"${domain}" || return 1
		tar -xJf "${FILESDIR}"/"${tarball}".tar.xz --strip-components=1 \
			-C po/"${domain}" --wildcards "po/*.po" || return 1
		compgen -G "po/${domain}/*.po" >/dev/null || return 1
	done <<-EOF
		activity-log-manager-translations-artful activity-log-manager
		cinnamon-session-translations-151017 unity-session-properties
		indicator-appearance-translations-261017 indicator-appearance
		indicator-notifications-translations-261017 indicator-notifications
		mate-screenshot-translations-focal mate-screenshot
		session-shortcuts-translations-artful session-shortcuts
		unity-help-translations-261017 unity-help
	EOF
}
