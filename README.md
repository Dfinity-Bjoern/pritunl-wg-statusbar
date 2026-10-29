# Pritunl WG

A macOS status bar app for DFINITY's Pritunl VPN. The shield icon in your menu bar turns **green** when connected, **yellow** while connecting, and **red** when disconnected. One click to connect or disconnect.

Bundled in `Resources/`: the `pritunl-wg` Python script that handles WireGuard key exchange with the Pritunl server, and `install.sh` that sets up the Python venv, installs the script, and registers the launchd service. No separate download needed.

## Prerequisites

- macOS 13 or later
- `wireguard-tools` — with [Homebrew](https://brew.sh) the app installs it for you on first use; with Nix, install it system-wide, for example in nix-darwin's `environment.systemPackages` (per-user installs such as home-manager's `home.packages` aren't used, because the VPN service runs as root)
- Xcode Command Line Tools — setup uses their `python3`, and `build.sh` their Swift compiler:
  ```
  xcode-select --install
  ```

## Install

### Option A: build from source

```bash
git clone <this-repo>
cd PritunlStatusBar
bash build.sh --install
open /Applications/PritunlWG.app
```

### Option B: pre-built app

Download `PritunlWG.zip` from the latest release, unzip, and drag `PritunlWG.app` to `/Applications`.

**First launch on a colleague's machine:** macOS will block the app because it is not notarized. Right-click (or Control-click) `PritunlWG.app` → **Open** → **Open** to allow it. You only need to do this once.

### Option C: build with Nix

With [Nix](https://nixos.org) (flakes enabled) you can build the app without the Xcode Command Line Tools or a clone of this repo (setup still uses their `python3`). The app it builds requires macOS 14 or later, the oldest version Nixpkgs supports.

```bash
nix build github:Dfinity-Bjoern/pritunl-wg-statusbar   # or `nix build` in a clone
rm -rf /Applications/PritunlWG.app                      # remove an older copy (quit the app first)
cp -R result/Applications/PritunlWG.app /Applications/
chmod -R u+w /Applications/PritunlWG.app                # files copied from the Nix store are read-only
open /Applications/PritunlWG.app
```

With [nix-darwin](https://github.com/nix-darwin/nix-darwin), install the package from your system flake instead; nix-darwin copies the app to `/Applications/Nix Apps`. Add the input to your `flake.nix`:

```nix
inputs = {
  # ...
  pritunl-wg-statusbar.url = "github:Dfinity-Bjoern/pritunl-wg-statusbar";
  pritunl-wg-statusbar.inputs.nixpkgs.follows = "nixpkgs";
};
```

Then add `pritunl-wg-statusbar` to the arguments of `outputs`, and the package to your configuration:

```nix
environment.systemPackages = [
  pritunl-wg-statusbar.packages.${pkgs.stdenv.hostPlatform.system}.default
];
```

## First-time setup

1. Export your profile from the Pritunl web console: **Servers → your server → Export** — you will get a `.tar` file.
2. Click the shield icon in the menu bar → **Import Profile…** and select that `.tar` file (or a `.ovpn` if you have one directly).
3. You will be asked for your administrator password once. The app installs the `wireguard-tools` Homebrew package if `wg-quick` isn't installed yet, sets up the VPN service, and stores your profile at `/etc/pritunl-wg/profile.ovpn` (readable by root only).
4. Click **Connect**.

## Passwordless connect / disconnect

By default, connecting and disconnecting ask for your administrator password. To remove that prompt:

Click the shield → **Enable Passwordless Connect…** and confirm with your password once. This writes a sudoers rule to `/etc/sudoers.d/pritunl-wg` that allows members of the `admin` group to run `pritunl-wg up` and `pritunl-wg down` without re-authenticating.

To undo it:

```bash
sudo rm /etc/sudoers.d/pritunl-wg
```

## Menu reference

| Item | What it does |
|------|-------------|
| Status header | Shows state, VPN address and uptime when connected |
| Connect / Disconnect | Starts or stops the VPN |
| Last ping | How long ago the keepalive with the server succeeded |
| Import Profile… | Installs or replaces the Pritunl profile |
| Show Logs | Opens a window tailing `/var/log/pritunl-wg.log` |
| Enable Passwordless Connect… | Adds the sudoers rule (hidden once set up) |
| Quit | Stops the app (the VPN service keeps running) |

## Files on disk

| Path | Purpose |
|------|---------|
| `/etc/pritunl-wg/profile.ovpn` | Your profile (root-readable only) |
| `/usr/local/lib/pritunl-wg/` | The Python script and its venv |
| `/usr/local/bin/pritunl-wg` | Symlink to the script |
| `/Library/LaunchDaemons/local.pritunl-wg.plist` | launchd service |
| `/var/log/pritunl-wg.log` | Log (rotated at 1 MB) |
| `/var/run/pritunl-wg.status` | JSON status file read by this app |
| `/etc/sudoers.d/pritunl-wg` | Passwordless sudo rule (optional) |

## CLI fallback

```bash
sudo pritunl-wg up      # connect
sudo pritunl-wg down    # disconnect
pritunl-wg status
pritunl-wg log
```

## Uninstall

```bash
# Remove the VPN service and all installed files:
bash /Applications/PritunlWG.app/Contents/Resources/install.sh --uninstall
# or, with nix-darwin:
bash "/Applications/Nix Apps/PritunlWG.app/Contents/Resources/install.sh" --uninstall

# Remove the app (with nix-darwin: remove it from environment.systemPackages):
rm -rf /Applications/PritunlWG.app

# Remove the sudoers rule (if you set it up):
sudo rm -f /etc/sudoers.d/pritunl-wg
```

## Limitations

Inherits the same limitations as `pritunl-wg`: profiles requiring SSO, device auth, or a password/PIN/OTP are not supported. DFINITY's profile has none of these.
