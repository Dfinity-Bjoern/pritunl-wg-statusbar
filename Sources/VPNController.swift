import AppKit
import Foundation

private let pritunlBin = "/usr/local/bin/pritunl-wg"
private let sudoersPath = "/etc/sudoers.d/pritunl-wg"
private let sudoersContent = "%admin ALL=(ALL) NOPASSWD: /usr/local/bin/pritunl-wg up, /usr/local/bin/pritunl-wg down"
// wireguard-tools from Nix (nix-darwin's system profile or the default profile)
// or Homebrew; the root-owned Nix profiles come first. Keep in sync with
// Resources/pritunl-wg and Resources/install.sh.
private let toolDirs = ["/run/current-system/sw/bin", "/nix/var/nix/profiles/default/bin",
                        "/opt/homebrew/bin", "/usr/local/bin"]

class VPNController {

    func connect() {
        if !sudoNoPassword(pritunlBin, "up") {
            runPrivileged("sudo \(pritunlBin) up")
        }
    }

    func disconnect() {
        if !sudoNoPassword(pritunlBin, "down") {
            runPrivileged("sudo \(pritunlBin) down")
        }
    }

    func isPasswordlessEnabled() -> Bool {
        // The file is root-readable only (440), so check existence rather than contents.
        FileManager.default.fileExists(atPath: sudoersPath)
    }

    func enablePasswordless(completion: @escaping (Error?) -> Void) {
        // echo avoids printf's % format-specifier interpretation.
        // The command is a single line so it doesn't break the AppleScript string literal.
        let cmd = "echo '\(sudoersContent)' | tee \(sudoersPath) > /dev/null && chmod 440 \(sudoersPath)"
        DispatchQueue.global(qos: .userInitiated).async {
            self.runPrivilegedSync(cmd) { err in
                DispatchQueue.main.async { completion(err) }
            }
        }
    }

    // Installs the script + profile. Accepts a .tar or .ovpn exported from Pritunl.
    // The user-phase steps (extract, brew install) run as the current user;
    // only the root-phase (venv, profile copy, launchd) runs with admin privileges.
    func installProfile(_ profileURL: URL, completion: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let ovpnURL = try self.extractOvpn(from: profileURL)
                try self.ensureWireguardTools()
                try self.runRootPhase(ovpn: ovpnURL)
                DispatchQueue.main.async { completion(nil) }
            } catch {
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    // MARK: - Install helpers

    private func extractOvpn(from url: URL) throws -> URL {
        guard url.pathExtension.lowercased() == "tar" else { return url }

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pritunl-wg-extract")
        try? FileManager.default.removeItem(at: tmp)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        p.arguments = ["-xf", url.path, "-C", tmp.path]
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw fail("Failed to extract .tar (exit \(p.terminationStatus))")
        }

        let all = FileManager.default.subpaths(atPath: tmp.path) ?? []
        guard let rel = all.first(where: { $0.hasSuffix(".ovpn") }) else {
            throw fail("No .ovpn file found inside the .tar")
        }
        return tmp.appendingPathComponent(rel)
    }

    private func ensureWireguardTools() throws {
        if toolDirs.contains(where: { FileManager.default.isExecutableFile(atPath: $0 + "/wg-quick") }) { return }

        let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        guard let brew = brewPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw fail("wireguard-tools not found. Install Homebrew (https://brew.sh), or install wireguard-tools system-wide with Nix (e.g. nix-darwin's environment.systemPackages), then try again.")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: brew)
        p.arguments = ["install", "wireguard-tools"]
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw fail("brew install wireguard-tools failed")
        }
    }

    private func runRootPhase(ovpn: URL) throws {
        guard let installSh = Bundle.main.path(forResource: "install", ofType: "sh"),
              let pritunlWg = Bundle.main.path(forResource: "pritunl-wg", ofType: nil)
        else { throw fail("Bundled install script not found") }

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pritunl-wg-install")
        try? FileManager.default.removeItem(at: tmpDir)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: installSh,
                                         toPath: tmpDir.appendingPathComponent("install.sh").path)
        try FileManager.default.copyItem(atPath: pritunlWg,
                                         toPath: tmpDir.appendingPathComponent("pritunl-wg").path)

        let sh  = tmpDir.appendingPathComponent("install.sh").path.shellEscaped
        let ovp = ovpn.path.shellEscaped
        // --root-phase runs as root and does NOT check EUID, so osascript works fine here.
        try runPrivilegedThrowing("bash \(sh) --root-phase \(ovp)")
    }

    // MARK: - Privileged execution

    @discardableResult
    private func sudoNoPassword(_ args: String...) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n"] + args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private func runPrivileged(_ cmd: String) {
        guard let script = NSAppleScript(source: appleScriptSource(cmd)) else { return }
        var err: NSDictionary?
        script.executeAndReturnError(&err)
        if let err { NSLog("privileged run error: %@", err) }
    }

    private func runPrivilegedSync(_ cmd: String, completion: (Error?) -> Void) {
        guard let script = NSAppleScript(source: appleScriptSource(cmd)) else {
            completion(fail("Could not create AppleScript")); return
        }
        var errDict: NSDictionary?
        script.executeAndReturnError(&errDict)
        if let d = errDict {
            let msg = (d[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
            completion(fail(msg))
        } else {
            completion(nil)
        }
    }

    private func runPrivilegedThrowing(_ cmd: String) throws {
        guard let script = NSAppleScript(source: appleScriptSource(cmd)) else {
            throw fail("Could not create AppleScript")
        }
        var errDict: NSDictionary?
        script.executeAndReturnError(&errDict)
        if let d = errDict {
            let msg = (d[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
            throw fail(msg)
        }
    }

    private func appleScriptSource(_ cmd: String) -> String {
        let escaped = cmd
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }

    private func fail(_ msg: String) -> Error {
        NSError(domain: "PritunlWG", code: 1,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }
}

private extension String {
    var shellEscaped: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
