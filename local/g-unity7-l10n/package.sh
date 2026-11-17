## Own package: translations from unity-base/unity-language-pack that no Ubuntu
##  package or language pack installs, for the ported packages. They go to
##  /usr/share/locale, where a language pack would take precedence. The other
##  translations of the ebuild are in the Ubuntu language packs, except the
##  languages that no longer have an Ubuntu language pack.
## The ebuild merges the translations of the network and sharing panels into
##  unity-control-center; the port translates these panels in their own domains
##  (*-use-own-translation-domain.patch), which no language pack has.
OVERLAY_PKG="unity-base/unity-language-pack"
GROUP="desktop"

local_prepare() {
	local tarball domain

	## <ebuild tarball> <gettext domain>
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
		unity-control-center-network-translations-261117 unity-control-center-network
		unity-control-center-sharing-translations-261117 unity-control-center-sharing
		unity-help-translations-261017 unity-help
	EOF
}
