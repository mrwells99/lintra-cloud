#!/bin/bash

# =============================================================================
# Lintra IT - Fedora Client Enrollment Script
# Version: 4.0 - Production Ready
# Logs to /var/log/lintra-enrollment.log
# =============================================================================

LOG_FILE="/var/log/lintra-enrollment.log"
sudo touch "$LOG_FILE" 2>/dev/null || true
sudo chmod 666 "$LOG_FILE" 2>/dev/null || true
exec > >(tee -a "$LOG_FILE") 2>&1

# Track status for summary
RESULTS=""
add_result() {
    RESULTS="${RESULTS}$1\n"
}

echo "=========================================="
echo "🚀 Lintra IT Client Enrollment"
echo "   Started: $(date)"
echo "=========================================="
echo ""

# =============================================================================
# CREDENTIALS & SECRETS
# =============================================================================
echo "🔐 Loading encrypted credentials..."

# Find USB mount point
USB_PATH=$(find /run/media -name ".env.enc" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)

if [[ -z "$USB_PATH" ]]; then
    echo "❌ ERROR: Could not find .env.enc on USB drive"
    echo "Expected location: /run/media/*/LINTRA/.env.enc"
    exit 1
fi

# Prompt for decryption password
read -sp "Enter encryption password for credentials: " ENV_PASSWORD
echo ""

# Decrypt .env to temp location
TEMP_ENV=$(mktemp)
if ! echo "$ENV_PASSWORD" | openssl enc -d -aes-256-cbc -in "$USB_PATH/.env.enc" -out "$TEMP_ENV" -pbkdf2 -pass stdin 2>/dev/null; then
    echo "❌ ERROR: Failed to decrypt credentials (wrong password?)"
    rm -f "$TEMP_ENV"
    exit 1
fi

# Source the variables
source "$TEMP_ENV"
rm -f "$TEMP_ENV"  # Clean up immediately

# Validate required variables exist (but don't test LDAP yet - need Tailscale first)
if [[ -z "$LDAP_BIND_PASSWORD" ]] || [[ -z "$TAILSCALE_AUTHKEY" ]] || [[ -z "$MESHCENTRAL_KEY" ]]; then
    echo "❌ ERROR: Missing required variables in .env"
    echo "Required: LDAP_BIND_PASSWORD, TAILSCALE_AUTHKEY, MESHCENTRAL_KEY"
    exit 1
fi

echo "✅ Credentials loaded"
add_result "✅ Credentials loaded from .env"
echo ""

# =============================================================================
# 0. HOSTNAME CONFIGURATION
# =============================================================================
echo "🖥️  Hostname Configuration"
echo "--------------------------"

CURRENT_HOSTNAME=$(hostname)
echo "Current hostname: ${CURRENT_HOSTNAME}"

read -rp "Enter new hostname for this PC (e.g. clinic-frontdesk-01): " NEW_HOSTNAME

if [[ -z "$NEW_HOSTNAME" ]]; then
    echo "⚠️  No hostname entered, keeping existing hostname"
    NEW_HOSTNAME="$CURRENT_HOSTNAME"
    add_result "⚠️ Hostname unchanged (${CURRENT_HOSTNAME})"
elif [[ "$NEW_HOSTNAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
    echo "🔧 Setting hostname to: $NEW_HOSTNAME"
    sudo hostnamectl set-hostname "$NEW_HOSTNAME"
    add_result "✅ Hostname set to $NEW_HOSTNAME"
else
    echo "❌ Invalid hostname (letters, numbers, hyphens only)"
    NEW_HOSTNAME="$CURRENT_HOSTNAME"
    add_result "❌ Hostname not changed (invalid input)"
fi
echo ""

# =============================================================================
# 1. SYSTEM UPDATE
# =============================================================================
echo "📦 Running system update..."
sudo dnf update -y

# Clean and rebuild cache after major updates
echo "🔄 Refreshing package cache..."
sudo dnf clean all
sudo dnf makecache

add_result "✅ System updated"
echo ""

# =============================================================================
# 1.5 TIMEZONE & TIME SYNC
# =============================================================================
echo "🕒 Configuring system time and timezone..."

# Force timezone to Chicago
sudo timedatectl set-timezone America/Chicago

# Ensure NTP is enabled
sudo timedatectl set-ntp true

# Optional: restart time sync service to be safe
sudo systemctl restart systemd-timesyncd 2>/dev/null || true

# Log status for sanity
timedatectl status | grep -E "Time zone|System clock synchronized"

add_result "✅ Timezone set to America/Chicago and NTP enabled"
echo ""

# =============================================================================
# 2. X11 STACK
# =============================================================================
echo "🖥️ Installing X11 stack (required for SDDM + remote support)..."

sudo dnf install -y --best --allowerasing \
    xorg-x11-server-Xorg \
    xorg-x11-xauth \
    xorg-x11-utils \
    xorg-x11-drv-libinput \
    mesa-dri-drivers \
    xorg-x11-drv-intel \
    xorg-x11-drv-amdgpu

add_result "✅ X11 stack installed"
echo ""

# =============================================================================
# 2.5. PLASMA X11 SUPPORT
# =============================================================================
echo "🖥️ Installing Plasma X11 support packages..."

sudo dnf install -y --best --allowerasing \
    plasma-workspace-x11 \
    kwin-x11

add_result "✅ Plasma X11 support installed"
echo ""

# =============================================================================
# 3. APPLICATION SOFTWARE
# =============================================================================
echo "📦 Installing application software..."

# Nextcloud Desktop
sudo dnf install -y --best --allowerasing nextcloud-client

if command -v nextcloud >/dev/null 2>&1; then
    add_result "✅ Nextcloud Desktop installed"
else
    add_result "⚠️ Nextcloud Desktop may need manual verification"
fi
echo ""

# =============================================================================
# 4. SSH DAEMON
# =============================================================================
echo "🔐 Enabling SSH daemon..."

sudo dnf install -y openssh-server
sudo systemctl enable --now sshd

if systemctl is-active sshd >/dev/null 2>&1; then
    add_result "✅ SSH daemon running"
else
    add_result "❌ SSH daemon failed to start"
fi
echo ""

# =============================================================================
# 5. TAILSCALE
# =============================================================================
echo "📡 Installing Tailscale..."

if command -v tailscale &>/dev/null && tailscale status &>/dev/null; then
    echo "Tailscale already installed and connected"
    add_result "✅ Tailscale (already configured)"
else
    curl -fsSL https://tailscale.com/install.sh | sh
    sudo systemctl enable --now tailscaled

    if command -v tailscale &>/dev/null; then
        echo "🔐 Connecting to Tailscale network..."
        sudo tailscale up --authkey="$TAILSCALE_AUTHKEY" --hostname="$NEW_HOSTNAME" --accept-dns=false --accept-routes=false

        if tailscale status &>/dev/null; then
            add_result "✅ Tailscale connected"
        else
            add_result "❌ Tailscale failed to connect"
        fi
    else
        add_result "❌ Tailscale install failed"
    fi
fi
echo ""

# =============================================================================
# 5.5. INSTALL LDAP CLIENT TOOLS
# =============================================================================
echo "📦 Installing LDAP client tools..."
sudo dnf install -y openldap-clients
echo ""

# =============================================================================
# 6. /etc/hosts
# =============================================================================
echo "📝 Updating /etc/hosts..."
if ! grep -q "nextcloud.lintra" /etc/hosts; then
    sudo tee -a /etc/hosts > /dev/null <<EOF

# Lintra IT Services
100.123.120.24 auth.tailfa3d50.ts.net
100.100.130.90 nextcloud.lintra
100.100.130.90 status.lintra
100.100.130.90 fleet.lintra
100.65.58.104 meshcentral.lintra
EOF
    add_result "✅ /etc/hosts updated"
else
    add_result "✅ /etc/hosts (already configured)"
fi
echo ""

# =============================================================================
# 7. VALIDATE LDAP CONNECTION
# =============================================================================
echo "🔍 Validating LDAP credentials..."
if ! ldapsearch -x -H ldap://100.100.130.90:3389 -D "cn=Directory Manager" -w "$LDAP_BIND_PASSWORD" -b "dc=lintra,dc=local" -s base dn >/dev/null 2>&1; then
    echo "❌ ERROR: LDAP authentication failed - check LDAP_BIND_PASSWORD in .env"
    exit 1
fi

echo "✅ LDAP credentials validated"
add_result "✅ LDAP credentials validated"
echo ""

# =============================================================================
# 8. SSH KEY FOR LINTRA ADMIN
# =============================================================================
echo "🔑 Installing Lintra admin SSH key..."

LINTRA_HOME="/home/lintra"
SSH_DIR="$LINTRA_HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
PUBKEY_URL="http://100.100.130.90:8080/lintra-admin.pub"

sudo mkdir -p "$SSH_DIR"
sudo chmod 700 "$SSH_DIR"
sudo chown lintra:lintra "$SSH_DIR"

curl -fsSL "$PUBKEY_URL" | sudo tee "$AUTHORIZED_KEYS" >/dev/null

sudo chmod 600 "$AUTHORIZED_KEYS"
sudo chown lintra:lintra "$AUTHORIZED_KEYS"

if grep -q "ssh-" "$AUTHORIZED_KEYS"; then
    add_result "✅ SSH key installed for lintra"
else
    add_result "❌ SSH key install failed"
fi
echo ""

# =============================================================================
# 9. CA CERTIFICATES
# =============================================================================
echo "📥 Downloading CA certificates..."
curl -so /tmp/lintra-rootCA.crt http://100.100.130.90:8080/lintra-rootCA.crt
curl -so /tmp/meshcentral-rootCA.crt http://100.100.130.90:8080/root-cert-public.crt

echo "🔒 Installing CA certificates..."
sudo cp /tmp/lintra-rootCA.crt /etc/pki/ca-trust/source/anchors/
sudo cp /tmp/meshcentral-rootCA.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust

rm -f /tmp/lintra-rootCA.crt /tmp/meshcentral-rootCA.crt
add_result "✅ CA certificates installed"
echo ""

# =============================================================================
# 10. BRANDING ASSETS
# =============================================================================
echo "🎨 Installing branding assets..."

sudo mkdir -p /usr/share/lintra

# Use USB_PATH we found earlier
if [[ -n "$USB_PATH" ]] && [[ -f "$USB_PATH/logo.png" ]]; then
    sudo cp "$USB_PATH/logo.png" /usr/share/lintra/ 2>/dev/null
    sudo cp "$USB_PATH/wallpaper.png" /usr/share/lintra/ 2>/dev/null
    sudo chmod 644 /usr/share/lintra/*.png 2>/dev/null
    add_result "✅ Branding assets installed"
else
    add_result "⚠️ Branding assets not found on USB"
fi
echo ""

# =============================================================================
# 11. PACKAGES
# =============================================================================
echo "📦 Installing SSSD and LDAP packages..."
sudo dnf install -y \
    sssd \
    sssd-ldap \
    oddjob-mkhomedir \
    clamav \
    clamd \
    clamav-update

add_result "✅ Packages installed"
echo ""

# =============================================================================
# 12. SELINUX
# =============================================================================
echo "🔧 Configuring SELinux..."
sudo setsebool -P sssd_connect_all_unreserved_ports 1
add_result "✅ SELinux configured"
echo ""

# =============================================================================
# 13. SSSD CONFIGURATION
# =============================================================================
echo "⚙ Configuring SSSD..."
sudo tee /etc/sssd/sssd.conf > /dev/null <<EOF
[sssd]
config_file_version = 2
domains = lintra.local
services = nss, pam

[domain/lintra.local]
id_provider = ldap
auth_provider = ldap
ldap_uri = ldap://100.100.130.90:3389
ldap_search_base = dc=lintra,dc=local
ldap_default_bind_dn = cn=Directory Manager
ldap_default_authtok = ${LDAP_BIND_PASSWORD}
ldap_user_search_base = ou=people,dc=lintra,dc=local
ldap_group_search_base = ou=groups,dc=lintra,dc=local
ldap_tls_reqcert = never
cache_credentials = true
enumerate = false
override_homedir = /home/%u

[nss]
filter_users = root
filter_groups = root

[pam]
offline_credentials_expiration = 2
EOF
sudo chmod 600 /etc/sssd/sssd.conf
sudo chown root:root /etc/sssd/sssd.conf
add_result "✅ SSSD configured"
echo ""

echo "⚙ Fixing SDDM PAM configuration..."
# Remove KDE Wallet modules and ensure mkhomedir is present
sudo cp /etc/pam.d/sddm /etc/pam.d/sddm.backup 2>/dev/null || true
sudo sed -i '/pam_kwallet/d' /etc/pam.d/sddm

# Add mkhomedir if not present
if ! grep -q "pam_oddjob_mkhomedir" /etc/pam.d/sddm; then
    sudo sed -i '/^session.*required.*pam_loginuid.so/a session     optional      pam_oddjob_mkhomedir.so umask=0077' /etc/pam.d/sddm
fi
add_result "✅ SDDM PAM configured"
echo ""

# =============================================================================
# 14. AUTHSELECT
# =============================================================================
echo "🏠 Configuring authselect with mkhomedir..."
sudo authselect select sssd with-mkhomedir --force
sudo systemctl enable --now oddjobd
add_result "✅ Authselect configured"
echo ""

# =============================================================================
# 15. SSH HARDENING
# =============================================================================
echo "🔐 Hardening SSH..."
sudo tee /etc/ssh/sshd_config.d/99-lintra-hardening.conf > /dev/null <<EOF
# Lintra IT SSH Hardening
PasswordAuthentication no
PermitRootLogin no
AllowUsers lintra
PubkeyAuthentication yes
EOF

if systemctl is-active sshd &>/dev/null; then
    sudo systemctl reload sshd
fi
add_result "✅ SSH hardened"
echo ""

# =============================================================================
# 16. PAM_WHEEL
# =============================================================================
echo "🔒 Configuring pam_wheel..."
sudo sed -i 's/^#auth\s*required\s*pam_wheel.so use_uid/auth required pam_wheel.so use_uid/' /etc/pam.d/su
add_result "✅ pam_wheel enforced"
echo ""

# =============================================================================
# 17. X11 SESSION FILE CREATION
# =============================================================================
echo "🖥️ Creating Plasma X11 session file..."

sudo tee /usr/share/xsessions/plasmax11.desktop > /dev/null <<'EOF'
[Desktop Entry]
Type=XSession
Exec=/usr/bin/startplasma-x11
TryExec=/usr/bin/startplasma-x11
DesktopNames=KDE
Name=Plasma (X11)
Comment=Plasma by KDE (X11)
EOF

add_result "✅ Plasma X11 session file created"
echo ""

# =============================================================================
# 18. SDDM CONFIGURATION
# =============================================================================
echo "🖥️ Configuring SDDM..."

sudo mkdir -p /etc/sddm.conf.d
sudo tee /etc/sddm.conf.d/10-lintra.conf > /dev/null <<EOF
[General]
DisplayServer=x11

[Theme]
Current=breeze

[Users]
RememberLastUser=true
HideUsers=lintra
[X11]
ServerArguments=-listen tcp
EOF

# Remove Wayland session files to force X11
echo "🚫 Disabling Wayland sessions..."
sudo rm -f /usr/share/wayland-sessions/*.desktop 2>/dev/null || true

# Update SDDM state to use X11 session
if [[ -f /var/lib/sddm/state.conf ]]; then
    sudo sed -i 's|Session=.*|Session=/usr/share/xsessions/plasmax11.desktop|' /var/lib/sddm/state.conf
fi

add_result "✅ SDDM configured for X11"
echo ""

# =============================================================================
# 18.1 SDDM THEME BACKGROUND (BREEZE)
# =============================================================================
echo "🎨 Configuring SDDM Breeze background..."

BREEZE_THEME_CONF="/usr/share/sddm/themes/breeze/theme.conf"

if [[ -f "$BREEZE_THEME_CONF" ]]; then
    sudo sed -i "s|^background=.*|background=/usr/share/lintra/wallpaper.png|" "$BREEZE_THEME_CONF"

    # If background key doesn't exist, append it
    if ! grep -q "^background=" "$BREEZE_THEME_CONF"; then
        echo "background=/usr/share/lintra/wallpaper.png" | sudo tee -a "$BREEZE_THEME_CONF" >/dev/null
    fi

    add_result "✅ SDDM Breeze background set"
else
    add_result "⚠️ SDDM Breeze theme not found"
fi

echo ""

# =============================================================================
# 18.5. DISABLE KDE WALLET
# =============================================================================
echo "🚫 Disabling KDE Wallet..."

sudo mkdir -p /etc/xdg
sudo tee /etc/xdg/kwalletrc > /dev/null <<EOF
[Wallet]
Enabled=false
First Use=false
Prompt on Open=false
EOF

add_result "✅ KDE Wallet disabled"
echo ""

# =============================================================================
# 18.6 KDE LOCKSCREEN WALLPAPER (ALL USERS)
# =============================================================================
echo "🔒 Configuring KDE lock screen wallpaper..."

# System-wide default for new users
sudo tee /etc/xdg/kscreenlockerrc > /dev/null <<'EOF'
[Greeter][Wallpaper][org.kde.image][General]
Image=file:///usr/share/lintra/wallpaper.png
PreviewImage=file:///usr/share/lintra/wallpaper.png
EOF

# Force for existing users
for u in /home/*; do
    USERNAME=$(basename "$u")
    [[ "$USERNAME" == "lost+found" ]] && continue
    [[ ! -d "$u" ]] && continue

    mkdir -p "$u/.config"
    tee "$u/.config/kscreenlockerrc" > /dev/null <<'EOF'
[Greeter][Wallpaper][org.kde.image][General]
Image=file:///usr/share/lintra/wallpaper.png
PreviewImage=file:///usr/share/lintra/wallpaper.png
EOF
    chown "$USERNAME:$USERNAME" "$u/.config/kscreenlockerrc"
done

add_result "✅ KDE lock screen wallpaper configured"

# =============================================================================
# 18.7 DISABLE FEDORA / KDE FIRST-LOGIN WELCOME SCREENS
# =============================================================================
echo "🚫 Disabling Fedora first-login / welcome screens..."

sudo dnf remove -y \
  fedora-welcome \
  plasma-welcome \
  gnome-initial-setup \
  initial-setup-gui \
  initial-setup 2>/dev/null || true

sudo rm -f /etc/xdg/autostart/fedora-welcome.desktop
sudo rm -f /etc/xdg/autostart/plasma-welcome.desktop
sudo rm -f /etc/xdg/autostart/gnome-initial-setup.desktop

sudo mkdir -p /etc/xdg
sudo tee /etc/xdg/lintra-setup-complete > /dev/null <<EOF
Lintra enrollment complete
EOF

echo "✅ First-login welcome screens disabled"

add_result "✅ KDE taskbar defaults set (Firefox, Dolphin, System Settings)"
echo ""

# =============================================================================
# 18.8 KDE PANEL DEFAULT CLEANUP (TASKBAR)
# =============================================================================
echo "🧹 Configuring KDE default taskbar layout..."

KDE_DEFAULT_DIR="/etc/xdg/plasma-workspace"
KDE_DEFAULT_PANEL="$KDE_DEFAULT_DIR/plasma-org.kde.plasma.desktop-appletsrc"

sudo mkdir -p "$KDE_DEFAULT_DIR"

sudo tee "$KDE_DEFAULT_PANEL" > /dev/null <<'EOF'
[Containments][1]
activityId=
formfactor=2
immutability=1
location=4
plugin=org.kde.panel

[Containments][1][Applets][1]
immutability=1
plugin=org.kde.plasma.kickoff

[Containments][1][Applets][2]
immutability=1
plugin=org.kde.plasma.taskmanager

[Containments][1][Applets][2][Configuration][General]
launchers=applications:firefox.desktop,applications:org.kde.dolphin.desktop,applications:systemsettings.desktop

[Containments][1][Applets][3]
immutability=1
plugin=org.kde.plasma.systemtray

[Containments][1][Applets][4]
immutability=1
plugin=org.kde.plasma.digitalclock
EOF

add_result "✅ KDE taskbar defaults set (Firefox, Dolphin, System Settings)"
echo ""

# =============================================================================
# 19. NEXTCLOUD USER INTEGRATION (SYSTEMD USER SERVICE – FINAL)
# =============================================================================
echo "🧠 Installing Lintra Nextcloud user integration..."

# ------------------------------------------------------------------
# 19.1 User-side finalizer script (WITH QUICK ACCESS)
# ------------------------------------------------------------------
sudo tee /usr/local/bin/lintra-nextcloud-finalize.sh > /dev/null <<'EOF'
#!/bin/bash
set -e

NC="$HOME/Nextcloud"
DOCS="$NC/Documents"
MARKER="$HOME/.lintra_nc_finalized"

# Stop forever once done
[ -f "$MARKER" ] && exit 0

# Wait until real sync happened
[ -d "$DOCS" ] || exit 1

echo "🔗 Nextcloud sync detected — finalizing folders"

mkdir -p "$NC"/{Desktop,Documents,Downloads,Pictures,Music,Videos}

for dir in Desktop Documents Downloads Pictures Music Videos; do
    if [ -d "$HOME/$dir" ] && [ ! -L "$HOME/$dir" ]; then
        mv "$HOME/$dir"/* "$NC/$dir"/ 2>/dev/null || true
        rmdir "$HOME/$dir" 2>/dev/null || true
    fi

    rm -rf "$HOME/$dir"
    ln -s "$NC/$dir" "$HOME/$dir"
done

mkdir -p "$HOME/.config"
cat > "$HOME/.config/user-dirs.dirs" <<EOD
XDG_DESKTOP_DIR="\$HOME/Nextcloud/Desktop"
XDG_DOCUMENTS_DIR="\$HOME/Nextcloud/Documents"
XDG_DOWNLOAD_DIR="\$HOME/Nextcloud/Downloads"
XDG_PICTURES_DIR="\$HOME/Nextcloud/Pictures"
XDG_MUSIC_DIR="\$HOME/Nextcloud/Music"
XDG_VIDEOS_DIR="\$HOME/Nextcloud/Videos"
EOD

# Pin Nextcloud to Quick Access (KDE Dolphin sidebar)
PLACES_FILE="$HOME/.local/share/user-places.xbel"
mkdir -p "$(dirname "$PLACES_FILE")"

if [ ! -f "$PLACES_FILE" ]; then
    # Create new places file with Nextcloud
    cat > "$PLACES_FILE" <<'PLACES'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE xbel>
<xbel xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks" xmlns:mime="http://www.freedesktop.org/standards/shared-mime-info">
 <bookmark href="file://HOMEDIR/Nextcloud">
  <title>Nextcloud</title>
  <info>
   <metadata owner="http://freedesktop.org">
    <bookmark:icon name="folder-cloud"/>
   </metadata>
  </info>
 </bookmark>
</xbel>
PLACES
    sed -i "s|HOMEDIR|$HOME|g" "$PLACES_FILE"
    echo "📌 Nextcloud pinned to Quick Access"
elif ! grep -q "Nextcloud" "$PLACES_FILE"; then
    # Append to existing file
    sed -i "s|</xbel>| <bookmark href=\"file://$HOME/Nextcloud\">\n  <title>Nextcloud</title>\n  <info>\n   <metadata owner=\"http://freedesktop.org\">\n    <bookmark:icon name=\"folder-cloud\"/>\n   </metadata>\n  </info>\n </bookmark>\n</xbel>|" "$PLACES_FILE"
    echo "📌 Nextcloud pinned to Quick Access"
fi

touch "$MARKER"
echo "✅ Nextcloud integration complete"
EOF

sudo chmod 755 /usr/local/bin/lintra-nextcloud-finalize.sh

# ------------------------------------------------------------------
# 19.2 systemd USER service – Nextcloud FINALIZER (UNCHANGED)
# ------------------------------------------------------------------
sudo tee /etc/systemd/user/lintra-nextcloud-finalize.service > /dev/null <<'EOF'
[Unit]
Description=Lintra Nextcloud Folder Finalizer
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/lintra-nextcloud-finalize.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

sudo systemctl --global enable lintra-nextcloud-finalize.service

# ------------------------------------------------------------------
# 19.3 FIX #1 — Nextcloud DESKTOP AUTOSTART (SYSTEMD USER)
# ------------------------------------------------------------------
sudo tee /etc/systemd/user/nextcloud-client.service > /dev/null <<'EOF'
[Unit]
Description=Nextcloud Desktop Client
After=graphical-session.target plasma-workspace.target
Wants=network-online.target

[Service]
Type=simple
ExecStartPre=/bin/sleep 10
ExecStart=/usr/bin/nextcloud
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

sudo systemctl --global enable nextcloud-client.service

# ------------------------------------------------------------------
# 19.4 FIX #2 — KDE WALLPAPER (DELAYED, RELIABLE)
# ------------------------------------------------------------------
sudo tee /etc/systemd/user/lintra-wallpaper.service > /dev/null <<'EOF'
[Unit]
Description=Lintra Wallpaper
After=graphical-session.target plasma-workspace.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'sleep 8 && /usr/bin/plasma-apply-wallpaperimage /usr/share/lintra/wallpaper.png'

[Install]
WantedBy=default.target
EOF

sudo systemctl --global enable lintra-wallpaper.service

echo "✅ Step 19 complete — Nextcloud auto-start + wallpaper fixed"

# =============================================================================
# 20. CLAMAV
# =============================================================================
echo "🛡️ Configuring ClamAV..."
sudo freshclam || true

sudo tee /etc/systemd/system/clamav-scan.service > /dev/null <<'EOF'
[Unit]
Description=ClamAV Daily Scan

[Service]
Type=oneshot
ExecStart=/usr/bin/clamscan -r / \
  --exclude-dir=^/sys \
  --exclude-dir=^/proc \
  --exclude-dir=^/dev \
  --exclude-dir=^/run \
  --exclude-dir=^/var/lib/clamav \
  --log=/var/log/clamav-scan.log \
  --infected \
  --remove=no
EOF

sudo tee /etc/systemd/system/clamav-scan.timer > /dev/null <<'EOF'
[Unit]
Description=Run ClamAV scan daily

[Timer]
OnCalendar=*-*-* 19:00:00
RandomizedDelaySec=1800
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Create log file for Wazuh monitoring
sudo touch /var/log/clamav-scan.log

# Log rotation to prevent log file growing forever
sudo tee /etc/logrotate.d/clamav-scan > /dev/null <<'EOF'
/var/log/clamav-scan.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
}
EOF

sudo systemctl daemon-reload
sudo systemctl enable clamav-scan.timer
sudo systemctl start clamav-scan.timer || true
add_result "✅ ClamAV configured"
echo ""
# =============================================================================
# 21. SSSD SERVICE
# =============================================================================
echo "🚀 Starting SSSD service..."
sudo systemctl enable sssd
sudo systemctl restart sssd
add_result "✅ SSSD running"
echo ""

# =============================================================================
# 22. MESHCENTRAL AGENT
# =============================================================================
echo "🖥️ Installing MeshCentral agent..."
cd /tmp
if wget -q "https://meshcentral.lintra/meshagents?script=1" -O ./meshinstall.sh 2>/dev/null; then
    chmod 755 ./meshinstall.sh
    if sudo -E ./meshinstall.sh https://meshcentral.lintra "$MESHCENTRAL_KEY" 2>&1 | tee /tmp/mesh-install.log; then
        if sudo systemctl is-active meshagent >/dev/null 2>&1; then
            add_result "✅ MeshCentral agent installed and running"
        else
            add_result "⚠️ MeshCentral agent installed but not running"
        fi
    else
        add_result "❌ MeshCentral agent installation failed"
    fi
    rm -f ./meshinstall.sh ./meshagent
else
    add_result "❌ MeshCentral agent download failed"
fi
echo ""

# =============================================================================
# 23. WAZUH AGENT
# =============================================================================
echo "🛡️ Installing Wazuh agent..."
WAZUH_MANAGER="100.100.229.85"
WAZUH_GROUP="lintra-workstations"

# Add Wazuh repo
sudo rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH
cat <<EOF | sudo tee /etc/yum.repos.d/wazuh.repo
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=Wazuh repository
baseurl=https://packages.wazuh.com/4.x/yum/
protect=1
EOF

# Install specific version to match manager
sudo WAZUH_MANAGER="$WAZUH_MANAGER" WAZUH_AGENT_GROUP="$WAZUH_GROUP" dnf install -y wazuh-agent-4.7.5-1

# Add ClamAV log monitoring to Wazuh agent
sudo touch /var/log/clamav-scan.log
if ! grep -q "clamav-scan.log" /var/ossec/etc/ossec.conf; then
    sudo sed -i '/<\/ossec_config>/i \  <localfile>\n    <log_format>syslog</log_format>\n    <location>/var/log/clamav-scan.log</location>\n  </localfile>' /var/ossec/etc/ossec.conf
fi

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-agent

if systemctl is-active wazuh-agent >/dev/null 2>&1; then
    add_result "✅ Wazuh agent installed"
else
    add_result "⚠️ Wazuh agent may need manual check"
fi
echo ""
# =============================================================================
# 24. FIREFOX MANAGED BOOKMARKS
# =============================================================================
echo "🦊 Configuring Firefox managed bookmarks..."

sudo mkdir -p /etc/firefox/policies
sudo tee /etc/firefox/policies/policies.json > /dev/null <<'EOF'
{
  "policies": {
    "NoDefaultBookmarks": true,
    "ManagedBookmarks": [
      {
        "toplevel_name": "Lintra Quick Links"
      },
      {
        "name": "Gmail - Workspace Email",
        "url": "https://mail.google.com"
      },
      {
        "name": "Nextcloud - File Storage",
        "url": "https://nextcloud.lintra"
      }
    ]
  }
}
EOF

sudo chmod 644 /etc/firefox/policies/policies.json
add_result "✅ Firefox bookmarks configured"
echo ""

# =============================================================================
# 25. TPM AUTO-UNLOCK (OPTIONAL - AUTO-DETECTED)
# =============================================================================
echo "🔐 Checking TPM auto-unlock eligibility..."

TPM_SKIP=""

# Config toggle
if [[ "${ENABLE_TPM_ENROLLMENT:-true}" != "true" ]]; then
    add_result "⏭ TPM auto-unlock (disabled in config)"
    TPM_SKIP=1
fi

# TPM presence
if [[ -z "$TPM_SKIP" ]] && [[ ! -c /dev/tpm0 ]]; then
    add_result "⏭ TPM auto-unlock (no TPM device)"
    TPM_SKIP=1
fi

# TPM usability
if [[ -z "$TPM_SKIP" ]]; then
    if ! command -v tpm2_getcap >/dev/null 2>&1; then
        echo "📦 Installing tpm2-tools..."
        if ! sudo dnf install -y tpm2-tools >/dev/null 2>&1; then
            add_result "⏭ TPM auto-unlock (tpm2-tools unavailable)"
            TPM_SKIP=1
        fi
    fi
fi

if [[ -z "$TPM_SKIP" ]] && ! tpm2_getcap properties-fixed >/dev/null 2>&1; then
    add_result "⚠ TPM auto-unlock (TPM unusable)"
    TPM_SKIP=1
fi

# Resolve LUKS backing device
if [[ -z "$TPM_SKIP" ]]; then
    ROOT_MAPPER=$(findmnt -n -o SOURCE / | sed 's|\[.*||')
    MAPPER_NAME=$(basename "$ROOT_MAPPER")

    if [[ ! -b "$ROOT_MAPPER" ]]; then
        add_result "⏭ TPM auto-unlock (root mapper missing)"
        TPM_SKIP=1
    fi
fi

if [[ -z "$TPM_SKIP" ]]; then
    LUKS_DEVICE=$(sudo cryptsetup status "$MAPPER_NAME" 2>/dev/null | awk '/device:/ {print $2}')

    if [[ -z "$LUKS_DEVICE" ]]; then
        add_result "⏭ TPM auto-unlock (cannot resolve LUKS device)"
        TPM_SKIP=1
    elif ! sudo cryptsetup isLuks "$LUKS_DEVICE" >/dev/null 2>&1; then
        add_result "⏭ TPM auto-unlock (disk not encrypted)"
        TPM_SKIP=1
    fi
fi

# Actually enroll if we passed all checks
if [[ -z "$TPM_SKIP" ]]; then
    echo "✅ TPM usable"
    echo "✅ LUKS device detected: $LUKS_DEVICE"
    echo "🔐 Enrolling TPM keyslot..."

    if sudo systemd-cryptenroll --tpm2-device=auto "$LUKS_DEVICE"; then
        echo "🔄 Rebuilding initramfs..."
        sudo dracut --force >/dev/null 2>&1
        add_result "✅ TPM auto-unlock configured"
    else
        add_result "⚠ TPM auto-unlock (enrollment failed)"
    fi
fi

echo ""

# =============================================================================
# 26. TESTS
# =============================================================================
echo "🧪 Running tests..."

echo "Testing LDAP connectivity..."
if ldapsearch -x -H ldap://100.100.130.90:3389 -D "cn=Directory Manager" -w "$LDAP_BIND_PASSWORD" -b "dc=lintra,dc=local" "(uid=finaltest)" uid 2>/dev/null | grep -q "uid: finaltest"; then
    add_result "✅ LDAP connection successful"
else
    add_result "❌ LDAP connection failed"
fi

echo "Testing user lookup..."
if id finaltest &>/dev/null; then
    add_result "✅ LDAP user lookup successful"
else
    add_result "⚠️ LDAP user lookup (may need reboot)"
fi
echo ""

# =============================================================================
# SUMMARY
# =============================================================================
echo "=========================================="
echo "📋 ENROLLMENT SUMMARY"
echo "=========================================="
echo ""
echo -e "$RESULTS"
echo "=========================================="
echo "✅ Enrollment Complete!"
echo "=========================================="
echo ""
echo "⚠️  REBOOT REQUIRED for all changes to take effect"
echo ""
echo "After reboot:"
echo "  1. Login with LDAP credentials"
echo "  2. First login will auto-configure ~/Nextcloud folder"
echo "  3. Nextcloud will auto-start and prompt for OAuth login"
echo "  4. Firefox will have Gmail + Nextcloud bookmarks"
echo "  5. Wallpaper will be applied automatically"
echo ""
echo "Services available:"
echo "  📁 Nextcloud:   https://nextcloud.lintra"
echo "  📊 Fleet:       https://fleet.lintra"
echo "  🖥️  MeshCentral: https://meshcentral.lintra"
echo "  📈 Status:      https://status.lintra"
echo ""
echo "Log file: $LOG_FILE"
echo ""

echo ""
echo "Press SPACE to reboot (or Ctrl+C to cancel)..."
while true; do
    read -n1 -s key
    if [[ "$key" == " " ]]; then
        echo ""
        echo "🔄 Rebooting..."
        sudo reboot
    fi
done
