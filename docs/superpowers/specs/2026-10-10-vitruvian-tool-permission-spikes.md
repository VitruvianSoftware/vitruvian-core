# Vitruvian tool platform: two permission spikes, and what they change

**Date:** 2026-10-10 · **Status:** findings; the roadmap change in section 5 accepted by James 2026-10-10 · **Owner:** compass
**Parent:** `docs/superpowers/specs/2026-10-08-vitruvian-tool-platform-design.md`
(section 8, "Capabilities and trust"; section 12, sub-project 0).

The platform design left two questions to be answered on a real Mac before
tools from outside could ship. Both are answered here. A decision James made
the same day is recorded too, because it changes what the answers are for.

## 1. The short version

- **A program the app launches gets the app's privacy permissions.** It can
  read the screen and drive other apps with no prompt and without going
  through the broker. macOS can be told not to do this, with one call at
  launch. Then the program has no permissions at all.
- **A sandbox can hold a launched program**: to one folder, off the network,
  and away from Accessibility and Screen Recording. It cannot limit the
  network to named hosts.
- **James will not pay for an Apple Developer ID** (2026-10-10). The first
  finding makes that matter much less for tools than the design assumed. It
  still rules out a public marketplace.

## 2. How the spikes were run

A small probe program (appendix) asks macOS three things and prints the
answers: is this process trusted for Accessibility; does a real Accessibility
read of the app in front work; is Screen Recording allowed. It can also launch
a copy of itself two ways, read or write a file, make one web request, and
echo a line from standard input. It never prompts and changes nothing.

It was run on a MacBook Pro (Mac16,5), macOS 27.0, from a shell whose
launching app holds both permissions. The probe itself is signed ad hoc, like
every Vitruvian build.

**What this does not cover.** The launcher was not Vitruvian. The mechanism is
the operating system's, so it should carry over, but nobody has run the probe
from Vitruvian. No test triggered a permission prompt, so what a person sees
when a tool asks for a permission of its own is not observed.

## 3. Spike 1: whose permissions does a launched tool get?

| How it was launched | macOS holds responsible | Accessibility | Real Accessibility read | Screen Recording |
|---|---|---|---|---|
| Ordinary child process | the launching app | trusted | worked | allowed |
| Child that answers for itself | the child | not trusted | refused | not allowed |

macOS does not grant permissions to a process. It grants them to the
**responsible process**: normally the app at the top of the chain that
launched it. An ordinary child of an app with Accessibility has Accessibility.

The second row uses `responsibility_spawnattrs_setdisclaim`, a launch option
that makes the child responsible for itself. Browsers and terminals use it so
that what they launch does not borrow their permissions. It is not in Apple's
public headers. It needs no entitlement and no signing identity.

**What it means for the design.**

- Section 8 says the broker "is the only way to reach Accessibility or Screen
  Recording through the app". For a tool launched the ordinary way that is
  false. The tool simply has them.
- Launched to answer for itself, a tool has none. Then the broker really is
  the only door, and the capability list in a manifest is enforced by macOS,
  not only reviewed by a person.
- **The runtime in sub-project 3 must launch every external tool this way.**
  It is one line at launch and it is the difference between a permission
  system and a notice.

**Decided otherwise, 2026-10-10.** James chose the opposite: an outside tool
is trusted like an app and is launched the ordinary way, so that it has the
reach of a built-in feature. The finding above stands as a description of
macOS; it is not used. See `2026-10-10-vitruvian-external-tools-design.md`,
section 3.

## 4. Spike 2: can a sandbox hold a launched tool?

`sandbox-exec` and the `sandbox_init` call behind it are marked deprecated and
are present and working on macOS 27. They take a profile: a short text of
allow and deny rules. Two profiles were tried.

| Attempt | No sandbox | Loose profile | Strict profile |
|---|---|---|---|
| Read its own folder | ok | ok | ok |
| Write its own folder | ok | ok | ok |
| Read another folder | ok | **refused** | **refused** |
| Write another folder | ok | **refused** | **refused** |
| Read a file in the home folder | ok | ok | **refused** |
| Web request | ok | **refused** | **refused** |
| Line in on standard input, line out | ok | ok | ok |
| Accessibility read (launched the ordinary way) | worked | worked | **failed** |
| A program it launches itself | free | held the same | held the same |

The loose profile allows everything except the network and one named folder.
The strict profile allows nothing except the tool's own folder and the system
libraries a program needs to start.

Further findings:

- **The network can be opened by port, not by host.** A rule naming a host is
  rejected: `host must be * or localhost in network address`. Adding port 443
  to the strict profile let the web request through; the other folder stayed
  refused.
- **"Am I trusted?" is not the lock.** With only the permission service
  blocked, the probe reported "not trusted", and the Accessibility read still
  worked. What stops Accessibility inside a sandbox is blocking the lookups
  the read is made through, which the strict profile does, or launching the
  tool to answer for itself (spike 1).
- **Both together work.** A tool launched to answer for itself inside a
  sandbox has no permissions and is held to its folder.
- **Ad hoc signing is enough.** The probe is signed ad hoc and every result
  above holds.

**What it means for the design.**

- Section 8 says that if a sandbox can confine tools, "`files` and `network`
  become enforced, not advisory". `files` can be: a tool sees its own folder
  and nothing else, and the folders a person picks are added to its profile.
- `network` "to declared hosts" cannot be enforced by the sandbox. The choices
  are: all or nothing per tool; or allow the tool only `localhost` and have
  the broker make its requests, checking the host against the manifest. The
  second is the one that keeps the manifest true.
- The sandbox is a deprecated interface. Apple has kept it working for many
  releases because its own software and every browser depend on it, but it
  could change. The runtime should treat a profile that fails to apply as
  "do not launch", never as "launch without".

## 5. No Developer ID

James, 2026-10-10: he will not pay for one. The parent design's open question
2 defaulted to yes, and its sub-project 0 began with signing. That is now a
fixed constraint, not a step.

**What still holds without one.**

- Everything in sub-projects 1 and 2, which is what is built.
- External tools as separate programs, the protocol, the SDK, the broker and
  the sandbox. None needs a signing identity: spike 2 ran on an ad hoc build.
- **Tools need no permissions of their own.** This is the finding that
  matters most here. Launched to answer for itself, a tool has no privacy
  permissions and asks the broker for everything. So an unsigned tool never
  meets the "permissions reset when the program changes" problem. Only the
  app holds permissions.

**What it costs.**

- **The app's own permissions still reset on every update**, as they do
  today. Accessibility and Screen Recording are tied to the exact build. This
  is the daily cost, it is not new, and the platform does not make it worse.
- **A tool someone downloads is quarantined by macOS** and will not run until
  the person clears the flag (`xattr -d com.apple.quarantine`), or installs it
  another way, such as Homebrew. Fine for a developer. Not fine for a
  marketplace aimed at everyone.
- **No notarisation**, so nothing can vouch for a tool to a stranger.

**What this changes in the roadmap.** James accepted this table on
2026-10-10. The parent design's section 12 says the same.

| Sub-project | As designed | Without a Developer ID |
|---|---|---|
| 0 Foundations | Signing; update channel; legal opinion; two spikes | Spikes done (this document). Signing dropped. The update channel is still worth fixing. The legal opinion is needed only if tools from other people ship. |
| 3 External runtime and SDK | Tools as separate programs | Unchanged, and now with a way to enforce it: launch each tool to answer for itself, inside a sandbox |
| 4 SDK beta | Packaging and signing a tool; install from a file | Install from a folder or a Git repository the person names. No signing step. |
| 5 Marketplace | A public registry and in-app install for anyone | Not as designed. A list of tools a person adds by address, for people who can clear a quarantine flag, is the most this supports. |

## Appendix: the probe

Built with `swiftc -O -o probe probe.swift`. Modes: `report`, `child`,
`disclaimed`, `read <path>`, `write <path>`, `net`, `echo`. Run under a
profile with `sandbox-exec -f <profile> ./probe <mode>`.

```swift
// A throwaway probe for two questions about macOS privacy grants (TCC):
// does a launched program get its launcher's grants, and can a sandbox hold it.
// It only asks; it never prompts and changes nothing.
import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation

@_silgen_name("responsibility_get_pid_responsible_for_pid")
func responsibility_get_pid_responsible_for_pid(_ pid: pid_t) -> pid_t
@_silgen_name("responsibility_spawnattrs_setdisclaim")
func responsibility_spawnattrs_setdisclaim(_ attrs: UnsafeMutablePointer<posix_spawnattr_t?>, _ disclaim: Int32) -> Int32

func name(of pid: pid_t) -> String {
    var buffer = [CChar](repeating: 0, count: 4096)
    let n = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    return n > 0 ? (String(cString: buffer) as NSString).lastPathComponent : "?"
}

func report(_ label: String) {
    let me = getpid()
    let responsible = responsibility_get_pid_responsible_for_pid(me)
    // A real Accessibility call, not only the yes/no: the app in front.
    var role: CFTypeRef?
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 1
    let ax = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(front),
                                           kAXRoleAttribute as CFString, &role)
    print("[\(label)] pid \(me) (\(name(of: me))), parent \(getppid()) (\(name(of: getppid()))), "
          + "responsible \(responsible) (\(name(of: responsible)))")
    print("[\(label)]   accessibility trusted: \(AXIsProcessTrusted()); reading the front app over Accessibility: \(ax == .success ? "worked" : (ax == .apiDisabled ? "refused (not trusted)" : "error \(ax.rawValue)"))")
    print("[\(label)]   screen recording allowed: \(CGPreflightScreenCaptureAccess())")
}

func spawn(_ path: String, _ args: [String], disclaim: Bool) -> Int32 {
    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    if disclaim { _ = responsibility_spawnattrs_setdisclaim(&attr, 1) }
    var argv: [UnsafeMutablePointer<CChar>?] = ([path] + args).map { strdup($0) } + [nil]
    var pid: pid_t = 0
    let rc = posix_spawn(&pid, path, nil, &attr, &argv, environ)
    guard rc == 0 else { print("spawn failed: \(String(cString: strerror(rc)))"); return -1 }
    var status: Int32 = 0
    waitpid(pid, &status, 0)
    return status
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "report" {
case "report":
    report(args.count > 2 ? args[2] : "probe")
case "child":       // report, then spawn myself as an ordinary child
    report("launcher")
    _ = spawn(args[0], ["report", "ordinary child"], disclaim: false)
case "disclaimed":  // report, then spawn myself as a child that answers for itself
    report("launcher")
    _ = spawn(args[0], ["report", "child that answers for itself"], disclaim: true)
case "read":        // try to read a file
    let path = args[2]
    do { let s = try String(contentsOfFile: path, encoding: .utf8); print("read \(path): OK (\(s.count) chars)") }
    catch { print("read \(path): REFUSED (\((error as NSError).localizedDescription))") }
case "write":
    let path = args[2]
    do { try "x".write(toFile: path, atomically: false, encoding: .utf8); print("write \(path): OK") }
    catch { print("write \(path): REFUSED (\((error as NSError).localizedDescription))") }
case "net":         // try one outbound connection
    let sem = DispatchSemaphore(value: 0)
    var out = "no answer"
    let task = URLSession(configuration: .ephemeral).dataTask(with: URL(string: "https://example.com/")!) { _, resp, err in
        out = err.map { "REFUSED (\(($0 as NSError).localizedDescription))" } ?? "OK (HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0))"
        sem.signal()
    }
    task.resume()
    _ = sem.wait(timeout: .now() + 8)
    print("network to example.com: \(out)")
case "echo":        // stand in for a tool talking over stdin/stdout
    if let line = readLine() { print("echo: \(line)") }
default:
    print("unknown mode")
}
```

The loose profile (`<dir>` is the folder holding the probe):

```scheme
(version 1)
(allow default)
(deny network*)
(deny file-read* (subpath "<dir>/private"))
(deny file-write* (subpath "<dir>/private"))
```

The strict profile:

```scheme
(version 1)
(deny default)
(import "system.sb")
(allow process-exec (literal "<dir>/probe"))
(allow file-read* (literal "<dir>/probe") (subpath "<dir>/allowed")
       (subpath "/usr/lib") (subpath "/System/Library")
       (subpath "/Library/Apple") (subpath "/private/var/db/dyld"))
(allow file-read-metadata)
(allow file-write* (subpath "<dir>/allowed"))
```
