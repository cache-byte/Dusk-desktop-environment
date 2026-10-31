#!/usr/bin/env bash
# Installs (or updates) Dusk: downloads the newest Dusk zip from
# https://github.com/cache-byte/Dusk-desktop-environment, unpacks it into
# ~/.local/src/dusk and runs ./build.sh install there (it asks for your
# password). After the first time, use Settings › About › Updates, or run
#   dusk-update
# (the same thing, installed with Dusk).
#   (curl ... | bash -s -- --version 0.25.4  installs a particular version)
set -euo pipefail
OWNER_REPO="${DUSK_GITHUB:-cache-byte/Dusk-desktop-environment}"
API="https://api.github.com/repos/$OWNER_REPO"
SRC="${DUSK_SRC:-$HOME/.local/src/dusk}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/dusk-update"

if [[ -t 1 ]]; then B=$'\e[1m'; R=$'\e[0m'; C=$'\e[38;5;116m'; G=$'\e[38;5;114m'; E=$'\e[38;5;203m'
else B=; R=; C=; G=; E=; fi
say() { printf '%s›%s %s\n' "$C" "$R" "$*"; }
fail() { printf '%s✗ %s%s\n' "$E" "$*" "$R" >&2; exit 1; }
command -v curl >/dev/null || fail "curl isn't installed."
mkdir -p "$CACHE"

MODE=update WANT=""
PASS=()
while (($#)); do
	case "$1" in
		--check) MODE=check ;;
		--list) MODE=list ;;
		--version) MODE=version; WANT="${2:-}"; shift ;;
		--version=*) MODE=version; WANT="${1#--version=}" ;;
		*) PASS+=("$1") ;;
	esac
	shift
done
if [[ "$MODE" == version && ! "$WANT" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then fail "Which version? (dusk-update --version 0.25.4)"; fi

# The Dusk installed now (./build.sh install notes it), if any.
installed_version() {
	local f="$HOME/.local/state/dusk/installed"
	[[ -f "$f" ]] && head -1 "$f" | tr -d '[:space:]'
}
# a is newer than b
newer() { [[ "$1" != "$2" && "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" == "$1" ]]; }

# Every .zip the repository offers: "url<TAB>name", from the newest release's
# files and from the top of the repository.
list_zips() {
	{
		curl -fsSL "$API/releases/latest" 2>/dev/null |
			grep -o '"browser_download_url": *"[^"]*\.zip"' | sed 's/.*"\(https[^"]*\)"/\1/' || true
		curl -fsSL "$API/contents/" 2>/dev/null |
			grep -o '"download_url": *"[^"]*\.zip"' | sed 's/.*"\(https[^"]*\)"/\1/' || true
	} | while read -r url; do printf '%s\t%s\n' "$url" "$(basename "$url")"; done
}

# The version in a zip: from its name (Dusk-0.21.2-source.zip), else from the
# meson.build inside it.
zip_version() {
	local name="$2" v
	v=$(grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' <<<"$name" | head -1 || true)
	if [[ -z "$v" && -f "$1" ]]; then
		v=$(unzip -p "$1" '*meson.build' 2>/dev/null | sed -n "s/^[[:space:]]*version: '\([^']*\)'.*/\1/p" | head -1)
	fi
	echo "${v:-0}"
}

# Every zip with its version: "url<TAB>name<TAB>version", newest first
# (one version once: a release's copy and the repository's are the same).
all_zips() {
	local url name v file
	while IFS=$'\t' read -r url name; do
		[[ -n "$url" ]] || continue
		v=$(zip_version "" "$name")
		if [[ "$v" == 0 ]]; then
			file="$CACHE/$name"
			curl -fsSL -o "$file" "$url" || continue
			v=$(zip_version "$file" "$name")
		fi
		printf '%s\t%s\t%s\n' "$url" "$name" "$v"
	done < <(list_zips) | sort -t$'\t' -k3,3Vr | awk -F'\t' '!seen[$3]++'
}

# The newest zip: "url<TAB>name<TAB>version" (downloads it to look inside when
# its name doesn't say).
newest_zip() {
	local best="" best_v="0" url name v file
	while IFS=$'\t' read -r url name; do
		[[ -n "$url" ]] || continue
		v=$(zip_version "" "$name")
		if [[ "$v" == 0 ]]; then
			file="$CACHE/$name"
			curl -fsSL -o "$file" "$url" || continue
			v=$(zip_version "$file" "$name")
		fi
		if [[ -z "$best" ]] || [[ "$v" != "$best_v" && "$(printf '%s\n%s\n' "$best_v" "$v" | sort -V | tail -1)" == "$v" ]]; then
			best="$url"$'\t'"$name"$'\t'"$v"; best_v="$v"
		fi
	done < <(list_zips)
	[[ -n "$best" ]] || return 1
	# What's really inside it counts (a zip renamed by hand can say otherwise).
	IFS=$'\t' read -r url name v <<<"$best"
	file="$CACHE/$name"
	if curl -fsSL -o "$file.part" "$url"; then
		mv "$file.part" "$file"
		local inner
		inner=$(unzip -p "$file" '*meson.build' 2>/dev/null | sed -n "s/^[[:space:]]*version: '\([^']*\)'.*/\1/p" | head -1 || true)
		[[ -n "$inner" ]] && v="$inner"
	fi
	printf '%s\t%s\t%s\n' "$url" "$name" "$v"
}

if [[ "$MODE" == list ]]; then
	have=$(installed_version || true)
	listed=$(all_zips || true)
	[[ -n "$listed" ]] || fail "Couldn't find any Dusk zips on GitHub ($OWNER_REPO)."
	[[ -n "$have" ]] && echo "installed $have"
	while IFS=$'\t' read -r url name v; do echo "zip $v $name"; done <<<"$listed"
	exit 0
fi

if [[ "$MODE" == version ]]; then
	found=$(all_zips | awk -F'\t' -v w="$WANT" '$3 == w' | head -1 || true)
	[[ -n "$found" ]] || fail "Dusk $WANT isn't on GitHub. See what is: dusk-update --list"
else
	found=$(newest_zip || true)
fi

if [[ "$MODE" == check ]]; then
	if [[ -n "$found" ]]; then
		echo "latest $(cut -f3 <<<"$found")"
		exit 0
	fi
	# No zips: the source itself in the repository.
	v=$(curl -fsSL "https://raw.githubusercontent.com/$OWNER_REPO/HEAD/meson.build" 2>/dev/null ||
		curl -fsSL "https://raw.githubusercontent.com/$OWNER_REPO/HEAD/dusk/meson.build" 2>/dev/null || true)
	v=$(sed -n "s/^[[:space:]]*version: '\([^']*\)'.*/\1/p" <<<"$v" | head -1)
	[[ -n "$v" ]] || fail "Couldn't find Dusk on GitHub ($OWNER_REPO)."
	echo "latest $v"
	exit 0
fi

have=$(installed_version || true)
if [[ "$MODE" == update && -n "$found" && -n "$have" ]]; then
	latest=$(cut -f3 <<<"$found")
	if ! newer "$latest" "$have"; then
		# Never back to an older one by itself (that's what --version is for).
		printf '%s✓%s You have Dusk %s%s%s, the newest on GitHub is %s: nothing to update.\n' "$G" "$R" "$B" "$have" "$R" "$latest"
		echo "  Every version there:  dusk-update --list    Install one:  dusk-update --version $latest"
		exit 0
	fi
fi
if [[ "$MODE" == version ]]; then
	printf '\n%s%sInstalling Dusk %s from GitHub%s  %s\n' "$B" "$C" "$WANT" "$R" "https://github.com/$OWNER_REPO"
	[[ -n "$have" ]] && newer "$have" "$WANT" && printf '%s(older than the Dusk %s you have: your settings stay as they are)%s\n' "$C" "$have" "$R"
	echo
else
printf '\n%s%sUpdating Dusk from GitHub%s  %s\n\n' "$B" "$C" "$R" "https://github.com/$OWNER_REPO"
fi
mkdir -p "$(dirname "$SRC")"
if [[ -n "$found" ]]; then
	command -v unzip >/dev/null || fail "unzip isn't installed (Fedora: sudo dnf install unzip)."
	IFS=$'\t' read -r url name version <<<"$found"
	file="$CACHE/$name"
	say "Downloading $name (Dusk $version)"
	curl -fL --progress-bar -o "$file.part" "$url" && mv "$file.part" "$file" || fail "The download didn't work."
	unpack="$CACHE/unpacked"
	rm -rf "$unpack" && mkdir -p "$unpack"
	unzip -q -o "$file" -d "$unpack" || fail "Couldn't unpack $name."
	top=""
	for t in "$unpack" "$unpack"/*; do
		if [[ -f "$t/build.sh" ]]; then top="$t"; break; fi
	done
	[[ -f "$top/build.sh" ]] || fail "No build.sh in $name."
	# Swapped in whole; the old build folder comes along (a quicker build).
	if [[ -d "$SRC/build" ]]; then mv "$SRC/build" "$top/build"; fi
	rm -rf "$SRC"
	mv "$top" "$SRC"
	dir="$SRC"
else
	# The repository has the source itself in it.
	command -v git >/dev/null || fail "git isn't installed (Fedora: sudo dnf install git)."
	repo="https://github.com/$OWNER_REPO.git"
	if [[ -d "$SRC/.git" ]]; then
		say "Getting the newest version into $SRC"
		git -C "$SRC" fetch --depth 1 origin HEAD && git -C "$SRC" reset --hard FETCH_HEAD
	else
		rm -rf "$SRC"
		say "Downloading Dusk into $SRC"
		git clone --depth 1 "$repo" "$SRC"
	fi
	if [[ -f "$SRC/build.sh" ]]; then dir="$SRC"; elif [[ -f "$SRC/dusk/build.sh" ]]; then dir="$SRC/dusk"; else fail "No build.sh in the repository."; fi
fi
chmod +x "$dir/build.sh"
printf '%s✓%s Got Dusk %s%s%s\n\n' "$G" "$R" "$B" "$(sed -n "s/^[[:space:]]*version: '\([^']*\)'.*/\1/p" "$dir/meson.build" | head -1)" "$R"
cd "$dir"
exec ./build.sh install "${PASS[@]}"
