#!/bin/bash
# Installs pritunl-wg: a WireGuard client for Pritunl servers on macOS.
#
#   bash install.sh <profile.tar | profile.ovpn>     install / update
#   bash install.sh --uninstall                      remove everything
#
# Run as your normal user (not with sudo). It asks for your password once.
set -euo pipefail

LIB=/usr/local/lib/pritunl-wg
BIN=/usr/local/bin/pritunl-wg
CONF=/etc/pritunl-wg
LABEL=local.pritunl-wg
PLIST=/Library/LaunchDaemons/$LABEL.plist
LOG=/var/log/pritunl-wg.log
HERE="$(cd "$(dirname "$0")" && pwd)"
# wireguard-tools from Nix (nix-darwin's system profile or the default profile)
# or Homebrew; the root-owned Nix profiles come first. Keep in sync with
# Resources/pritunl-wg and Sources/VPNController.swift.
TOOL_DIRS=(/run/current-system/sw/bin /nix/var/nix/profiles/default/bin /opt/homebrew/bin /usr/local/bin)

find_wg_quick() {
  local d
  for d in "${TOOL_DIRS[@]}"; do
    if [[ -x $d/wg-quick ]]; then echo "$d/wg-quick"; return 0; fi
  done
  return 1
}

# ------------------------------------------------------------------ root phase
# Everything that needs root runs here, in a single sudo invocation.
if [[ "${1:-}" == "--root-phase" ]]; then
  OVPN="$2"
  export HOME=/var/root PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1

  echo "==> Setting up Python environment"
  mkdir -p "$LIB" /usr/local/bin
  if [[ ! -x "$LIB/venv/bin/python3" ]]; then
    /usr/bin/python3 -m venv "$LIB/venv"
  fi
  "$LIB/venv/bin/python3" -m pip install -q --upgrade pip
  "$LIB/venv/bin/python3" -m pip install -q --upgrade pynacl cryptography

  echo "==> Installing pritunl-wg"
  { echo "#!$LIB/venv/bin/python3 -I"; tail -n +2 "$HERE/pritunl-wg"; } > "$LIB/pritunl-wg"
  chown -R root:wheel "$LIB"
  chmod 755 "$LIB/pritunl-wg"
  ln -sf "$LIB/pritunl-wg" "$BIN"

  echo "==> Installing profile"
  mkdir -p "$CONF"
  chmod 700 "$CONF"
  install -m 600 -o root -g wheel "$OVPN" "$CONF/profile.ovpn"

  echo "==> Installing launchd service"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$LIB/venv/bin/python3</string>
    <string>-I</string>
    <string>$LIB/pritunl-wg</string>
    <string>run</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict>
</plist>
EOF
  chown root:wheel "$PLIST"; chmod 644 "$PLIST"
  echo "$LOG  644  3  1024  *  J" > /etc/newsyslog.d/pritunl-wg.conf

  if launchctl print system/$LABEL >/dev/null 2>&1; then
    launchctl kickstart -k system/$LABEL   # restart with the new version
  else
    launchctl disable system/$LABEL        # only starts on: sudo pritunl-wg up
  fi
  exit 0
fi

if [[ "${1:-}" == "--root-uninstall" ]]; then
  launchctl bootout system/$LABEL 2>/dev/null || true
  launchctl disable system/$LABEL 2>/dev/null || true
  if [[ -f "$CONF/dfinity.conf" ]] && WG_QUICK=$(find_wg_quick); then
    # Homebrew's wg-quick finds its bash 4+ on PATH, Nix's names it in its shebang.
    PATH="${WG_QUICK%/*}:$PATH" "$WG_QUICK" down "$CONF/dfinity.conf" || true
  fi
  rm -rf "$LIB" "$BIN" "$CONF" "$PLIST" /etc/newsyslog.d/pritunl-wg.conf \
         /var/run/pritunl-wg.status
  exit 0
fi

# ------------------------------------------------------------------ user phase
if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user, not with sudo." >&2; exit 1
fi

if [[ "${1:-}" == "--uninstall" ]]; then
  echo "==> Removing pritunl-wg (asks for your password once)"
  sudo /bin/bash "$HERE/install.sh" --root-uninstall
  echo "Removed. (wireguard-tools stays installed; with Homebrew: brew uninstall wireguard-tools)"
  exit 0
fi

SRC="${1:-}"
if [[ -z "$SRC" || ! -f "$SRC" ]]; then
  echo "Usage: bash install.sh <profile.tar | profile.ovpn>" >&2; exit 1
fi

if ! find_wg_quick >/dev/null; then
  if ! command -v brew >/dev/null; then
    echo "wireguard-tools is required: install Homebrew (https://brew.sh), or install" \
         "wireguard-tools system-wide with Nix (e.g. nix-darwin's environment.systemPackages)" >&2; exit 1
  fi
  echo "==> Installing wireguard-tools via Homebrew"
  brew install wireguard-tools
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
case "$SRC" in
  *.tar)
    tar -xf "$SRC" -C "$TMP"
    count=$(find "$TMP" -name '*.ovpn' | wc -l | tr -d ' ')
    if [[ "$count" != "1" ]]; then
      echo "Expected exactly one .ovpn in $SRC, found $count" >&2; exit 1
    fi
    OVPN="$(find "$TMP" -name '*.ovpn')" ;;
  *.ovpn) OVPN="$SRC" ;;
  *) echo "Profile must be a .tar or .ovpn file" >&2; exit 1 ;;
esac
if ! head -1 "$OVPN" | grep -q '^#{'; then
  echo "$OVPN does not look like a Pritunl profile" >&2; exit 1
fi

echo "==> Root setup (asks for your password once)"
sudo /bin/bash "$HERE/install.sh" --root-phase "$OVPN"

cat <<EOF

Installed. Disconnect Pritunl/Viscosity first, then:

  sudo pritunl-wg up       connect (stays on across sleep and reboot)
  pritunl-wg status        check the connection
  pritunl-wg log           follow the log
  sudo pritunl-wg down     disconnect

You can now delete the downloaded profile files from Downloads.
EOF
