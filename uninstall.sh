#!/usr/bin/env bash
# Removes Dusk completely and puts back what it changed for other desktops
# (GNOME, KDE...): GNOME's appearance settings, GTK and Qt theming files,
# terminal fonts, the cursor files, Flatpak permissions, and the login screen.
#
#   dusk-uninstall            asks first
#   dusk-uninstall -y         doesn't ask
#   dusk-uninstall --keep-themes   leaves the fonts and the Papirus / Bibata
#                                  themes Dusk downloaded (other desktops can use them)
#
# Left alone: choices you made yourself in Settings that every desktop shares
# (default apps, startup apps, your picture ~/.face), and system packages
# (they're shared libraries other programs use too).
set -u

YES=0 KEEP_THEMES=0
for a in "$@"; do
	case "$a" in
		-y|--yes) YES=1 ;;
		--keep-themes) KEEP_THEMES=1 ;;
		-h|--help) sed -n '2,15p' "$0"; exit 0 ;;
	esac
done

if [ -t 1 ]; then B=$'\e[1m' R=$'\e[0m' G=$'\e[32m' Y=$'\e[33m' C=$'\e[36m'; else B= R= G= Y= C=; fi
say()  { printf '%s›%s %s\n' "$C" "$R" "$*"; }
good() { printf '%s✓%s %s\n' "$G" "$R" "$*"; }
warn() { printf '%s!%s %s\n' "$Y" "$R" "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

printf '\n%s✦ Remove Dusk%s\n───\n' "$B" "$R"
echo "This removes Dusk and its settings, and puts GNOME's appearance settings,"
echo "GTK / Qt theming, terminal fonts and the cursor back to their defaults."
[ "$KEEP_THEMES" = 1 ] || echo "The fonts and icon / cursor themes Dusk downloaded are removed too (--keep-themes keeps them)."
if [ "$YES" != 1 ] && [ -t 0 ]; then
	read -r -p "${B}Remove Dusk? [y/N]${R} " answer
	case "$answer" in y|Y|yes|Yes) ;; *) echo "Nothing changed."; exit 0 ;; esac
fi
running=0
pgrep -u "$(id -u)" -x dusk >/dev/null 2>&1 && running=1

# ---- The programs and system files --------------------------------------------------------
say "Removing Dusk's programs (your password may be asked for)"
sudo rm -f /usr/local/bin/dusk /usr/local/bin/dusk-settings /usr/local/bin/dusk-settings-classic \
	/usr/local/bin/dusk-apply-theme /usr/local/bin/dusk-doctor /usr/local/bin/dusk-session \
	/usr/local/bin/dusk-update /usr/local/bin/dusk-uninstall \
	/usr/lib/systemd/user/dusk-session.target \
	/usr/share/wayland-sessions/dusk.desktop \
	/usr/local/share/applications/org.dusk.Settings.desktop \
	/usr/share/xdg-desktop-portal/dusk-portals.conf \
	/usr/local/share/icons/hicolor/scalable/apps/dusk.svg \
	/usr/local/share/icons/hicolor/scalable/apps/org.dusk.Settings.svg \
	/etc/pam.d/dusk-lock \
	/usr/local/bin/floe /usr/local/bin/floe-settings /usr/share/wayland-sessions/floe.desktop
sudo gtk-update-icon-cache -qtf /usr/local/share/icons/hicolor 2>/dev/null || true
# Dusk's old login screen (0.19 - 0.20), if it's still there: GDM back.
if grep -q dusk-greeter /etc/greetd/config.toml 2>/dev/null; then
	say "Putting GNOME's login screen (GDM) back"
	sudo systemctl disable greetd.service 2>/dev/null || true
	sudo systemctl enable gdm.service 2>/dev/null || sudo systemctl enable gdm3.service 2>/dev/null || true
	if [ -f /etc/greetd/config.toml.before-dusk ]; then
		sudo mv /etc/greetd/config.toml.before-dusk /etc/greetd/config.toml
	else
		sudo rm -f /etc/greetd/config.toml
	fi
	[ -f /etc/pam.d/greetd.before-dusk ] && sudo mv /etc/pam.d/greetd.before-dusk /etc/pam.d/greetd
fi
sudo rm -rf /usr/local/bin/dusk-greeter /usr/local/bin/dusk-login-sync \
	/usr/share/polkit-1/actions/org.dusk.login-sync.policy /etc/dusk \
	/usr/local/share/dusk-login /var/cache/dusk-greeter /var/lib/dusk-greeter /var/log/dusk-login-sync.log
good "Programs removed"

# ---- GNOME's settings (GNOME, GTK and Flatpak apps read these) -------------------------------
if have gsettings; then
	say "Putting GNOME's appearance settings back to their defaults"
	for k in color-scheme accent-color gtk-theme icon-theme cursor-theme cursor-size \
		font-name document-font-name monospace-font-name gtk-enable-primary-paste; do
		gsettings reset org.gnome.desktop.interface "$k" 2>/dev/null || true
	done
	gsettings reset org.gnome.desktop.wm.preferences button-layout 2>/dev/null || true
fi
for k in kwriteconfig6 kwriteconfig5; do
	have "$k" || continue
	"$k" --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft --delete 2>/dev/null || true
	"$k" --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight --delete 2>/dev/null || true
	break
done

# ---- GTK's files: only the parts Dusk wrote ------------------------------------------------
say "Taking Dusk's lines out of GTK, Qt, terminal and browser settings"
for v in 3.0 4.0; do
	css="$CONF/gtk-$v/gtk.css"
	if [ -f "$css" ]; then
		sed -i '/\/\* dusk-start/,/\/\* dusk-end \*\//d' "$css"
		[ -s "$css" ] || rm -f "$css"
	fi
	ini="$CONF/gtk-$v/settings.ini"
	if [ -f "$ini" ]; then
		sed -i -E '/^gtk-application-prefer-dark-theme=|^gtk-theme-name=|^gtk-font-name=|^gtk-cursor-theme-name=|^gtk-cursor-theme-size=/d' "$ini"
		# Nothing of yours left in it: gone.
		if ! grep -qvE '^\s*$|^\[Settings\]$' "$ini"; then rm -f "$ini"; fi
	fi
	rmdir "$CONF/gtk-$v" 2>/dev/null || true
done

# ---- Qt: the qt6ct / qt5ct setup Dusk made --------------------------------------------------
for q in qt6ct qt5ct; do
	if grep -q "colors/dusk.conf" "$CONF/$q/$q.conf" 2>/dev/null; then rm -f "$CONF/$q/$q.conf"; fi
	rm -f "$CONF/$q/colors/dusk.conf"
	rmdir "$CONF/$q/colors" "$CONF/$q" 2>/dev/null || true
done

# ---- Terminals ----------------------------------------------------------------------------
k="$CONF/kitty/kitty.conf"
if [ -f "$k" ]; then
	sed -i '/# dusk-start/,/# dusk-end/d' "$k"
	[ -s "$k" ] || rm -f "$k"
fi
f="$CONF/foot/foot.ini"
if [ -f "$f" ]; then
	sed -i '/^font=/d' "$f"   # Dusk's font line (foot's own default comes back)
	[ -s "$f" ] || rm -f "$f"
fi

# ---- Browsers: the dark-mode flag ---------------------------------------------------------
for n in chrome chromium brave vivaldi microsoft-edge microsoft-edge-stable opera; do
	for f in "$CONF/$n-flags.conf" "$HOME"/.var/app/*/config/"$n"-flags.conf; do
		[ -f "$f" ] && sed -i '/^--force-dark-mode$/d' "$f"
	done
done

# ---- Cursor files -------------------------------------------------------------------------
for f in "$HOME/.icons/default/index.theme" "$DATA/icons/default/index.theme"; do
	# Dusk's file is exactly "[Icon Theme] / Name=Default / Inherits=…"
	if [ -f "$f" ] && [ "$(sed -n 2p "$f")" = "Name=Default" ] && [ "$(wc -l < "$f")" -le 3 ]; then
		rm -f "$f"
		rmdir "$(dirname "$f")" 2>/dev/null || true
	fi
done
# Links Dusk made in ~/.icons to themes in ~/.local/share/icons (for Steam).
if [ -d "$HOME/.icons" ]; then
	for l in "$HOME"/.icons/*; do
		[ -L "$l" ] && case "$(readlink "$l")" in "$DATA/icons/"*) rm -f "$l" ;; esac
	done
	rmdir "$HOME/.icons" 2>/dev/null || true
fi
have xrdb && [ -n "${DISPLAY:-}" ] && xrdb -query 2>/dev/null | grep -q '^Xcursor' &&
	xrdb -query | grep -v '^Xcursor' | xrdb -load 2>/dev/null || true

# ---- Flatpak: the read access Dusk gave apps to the GTK / Qt settings -----------------------
ov="$DATA/flatpak/overrides/global"
if [ -f "$ov" ]; then
	sed -i -E 's#xdg-config/gtk-3\.0:ro;?##g; s#xdg-config/gtk-4\.0:ro;?##g; s#xdg-data/themes:ro;?##g; s#xdg-config/qt6ct:ro;?##g' "$ov"
	sed -i -E '/^filesystems=;?$/d' "$ov"
	if ! grep -qvE '^\s*$|^\[[A-Za-z ]+\]$' "$ov"; then rm -f "$ov"; fi
fi
# The GTK themes Dusk copied for Flatpak apps (the originals are in /usr/share/themes).
for t in adw-gtk3 adw-gtk3-dark Adwaita Adwaita-dark; do
	[ -d "/usr/share/themes/$t" ] && [ -d "$DATA/themes/$t" ] && rm -rf "$DATA/themes/$t"
done
rmdir "$DATA/themes" 2>/dev/null || true
good "Other apps' settings put back"

# ---- Fonts and themes Dusk downloaded -----------------------------------------------------
if [ "$KEEP_THEMES" != 1 ]; then
	say "Removing the fonts and themes Dusk downloaded"
	rm -rf "$DATA/fonts/dusk"
	rmdir "$DATA/fonts" 2>/dev/null || true
	have fc-cache && fc-cache -f >/dev/null 2>&1 || true
	# (Only the copies in your home folder: ones from the system's packages stay.)
	rm -rf "$DATA/icons/Bibata-Modern-Classic" "$DATA/icons/Bibata-Modern-Ice"
	for p in Papirus Papirus-Dark Papirus-Light ePapirus ePapirus-Dark; do rm -rf "${DATA:?}/icons/$p"; done
	rmdir "$DATA/icons" 2>/dev/null || true
fi

# ---- Dusk's own settings, notifications, clipboard history, logs, sources ------------------
say "Removing Dusk's settings and saved data"
rm -rf "$CONF/dusk" "$HOME/.local/state/dusk" "${XDG_CACHE_HOME:-$HOME/.cache}/dusk" "$HOME/.local/src/dusk"
rm -rf "$CONF/floe" "$HOME/.local/state/floe"
if [ -f "$HOME/src/dusk/meson.build" ] && head -3 "$HOME/src/dusk/meson.build" | grep -q "'dusk'"; then
	rm -rf "$HOME/src/dusk"
fi
rmdir "$HOME/src" 2>/dev/null || true
if [ -f "$HOME/.hidden" ]; then
	sed -i '/^src$/d' "$HOME/.hidden"
	[ -s "$HOME/.hidden" ] || rm -f "$HOME/.hidden"
fi
rm -f "$HOME"/Downloads/Dusk-*-source.zip "$HOME"/Downloads/Dusk-source.zip
good "Dusk's data removed"

echo
good "${B}Dusk is removed.${R}"
echo "Your default apps, startup apps and picture are unchanged. Packages that were"
echo "installed for building (Qt, wlroots…) are still there; they're shared with other programs."
if [ "$running" = 1 ]; then
	warn "Dusk is still running: log out (Super+Shift+E or the power menu) and pick GNOME on the login screen."
fi
exit 0
