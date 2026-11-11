  *INSTALL*
	
Run this command in terminal to install:

    command -v unzip >/dev/null || sudo dnf install -y unzip; z=$(curl -fsSL https://api.github.com/repos/cache-byte/Nova-desktop-environment/contents | grep -oE 'Nova-[0-9.]+-source\.zip' | sort -uV | tail -1); d=$(mktemp -d); curl -fL -o "$d/nova.zip" "https://raw.githubusercontent.com/cache-byte/Nova-desktop-environment/main/$z" && unzip -q "$d/nova.zip" -d "$d/src" && bash "$d/src/install.sh"
		
 *UNISTALL AND UPDATE*
 
Both are don't in the settings app or by running:

    nova-update
and

    nova-unistall
