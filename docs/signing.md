# Signing and notarizing cl_quick

cl_quick is signed **ad hoc** today: a download needs **Open Anyway** once in System Settings ▸ Privacy & Security. The
release can sign it with a **Developer ID** and have Apple **notarize** it instead, so it opens like any other app. The
scripts are ready; what's missing is the certificate and the notary credentials, which only the account holder can make.
Nothing changes until they exist: with the two settings below unset, `build.sh` and `scripts/release.sh` run exactly as
before.

This is cl_audit's set-up, adapted (its `docs/signing.md` has the same account steps). **One certificate and one
`cl-notary` profile serve both apps**: the settings below are the same names, with the same values, for cl_audit and
cl_quick. If cl_audit's steps are done, only the check at the end is left here.

## The two settings

| Setting | What it is | Unset |
|---|---|---|
| `CL_SIGN_ID` | The Developer ID Application identity, as `security find-identity -v -p codesigning` lists it: its 40-character SHA-1 (best: after a renewal two certificates share one name), or its whole name `Developer ID Application: Your Name (TEAMID)`. Only an exact match on a Developer ID Application line counts | Ad hoc, as today |
| `CL_NOTARY_PROFILE` | The name of a notarytool keychain profile, for example `cl-notary` | No notarization |

`CL_NOTARY_PROFILE` needs `CL_SIGN_ID` (Apple notarizes Developer ID signatures only); a release with only the profile set
stops before anything is built or committed. Both are environment variables on this Mac, never in the repository or in CI:
releases run here, and the certificate's private key and the notary password stay in this Mac's Keychain.

Before a release, check the set-up (signs nothing, changes nothing):

```bash
CL_SIGN_ID="Developer ID Application: Your Name (TEAMID)" CL_NOTARY_PROFILE=cl-notary scripts/release.sh --check-signing
```

It says whether the identity is in the Keychain and whether the profile answers (one call to Apple's notary service), and
lists what it would sign, in order. `./build.sh --check-signing` prints the same.

A release with both:

```bash
CL_SIGN_ID="Developer ID Application: Your Name (TEAMID)" CL_NOTARY_PROFILE=cl-notary scripts/release.sh --push
```

To try the whole chain (sign, notarize, staple, Gatekeeper's checks) on the current tree without a version change, a
commit, a tag or a push, use `--local` with the same two settings: it leaves `dist/cl_quick.zip` and `dist/cl_quick.dmg`.

## What the scripts do with them

`build.sh` signs `cl_quick.app` with `codesign --force --sign "$CL_SIGN_ID" --options runtime --timestamp` (the hardened
runtime and a secure timestamp, which notarization requires; the timestamp needs the network during the build). Without
`CL_SIGN_ID` it is the `codesign --force --sign -` it always ran. There is nothing to sign inside out:
the app is one program (`Contents/MacOS/cl_quick`) and an `Info.plist`; the shared modules from cl_kit are static
libraries linked into it, and there is no helper app, login-item helper, plug-in, framework or dylib. If one is ever added
it goes into `sign_plan` in `scripts/signing.sh` and into `build.sh`, before the app, never with `--deep`.

`scripts/release.sh --push` (and `--local`, which `--push` runs), before anything is pushed (a failure undoes the release
commit and tag, as today):

1. checks the set-up first: the identity is in the Keychain and the profile answers, before the build starts;
2. builds the app and checks its signature is the Developer ID's with the hardened runtime, and that
   `codesign --verify --deep --strict -R` finds the whole app signed by the identity's team;
3. zips it and sends the zip to Apple: `xcrun notarytool submit … --keychain-profile "$CL_NOTARY_PROFILE" --wait`.
   Anything but **Accepted** stops the release, with the command that shows Apple's log;
4. staples the ticket into the app (`xcrun stapler staple`, three tries 20 s apart) and zips the stapled app again;
5. makes the disk image from the stapled app, signs it, notarizes it and staples it, so the zip and the disk image both
   carry the notarized, stapled app;
6. checks what a downloader's Mac will say: `spctl -a -vv -t exec` on the app, `spctl -a -vv -t open
   --context context:primary-signature` on the disk image, `xcrun stapler validate` on both and on the image's app, and
   (as today) the same code directory hash in the zip's and the image's app, and `codesign --verify --deep --strict` on
   the image's;
7. writes the release notes without the Open Anyway step, then pushes and publishes as today.

## Entitlements under the hardened runtime

cl_quick needs **none**, so there is no entitlements file and none is passed to `codesign`. The hardened runtime blocks a
few things unless an entitlement allows them; what cl_quick does, checked one by one in `Sources/` and in the cl_kit
modules it links:

| What cl_quick does | Under the hardened runtime | Entitlement |
|---|---|---|
| Receives a `cl-quick://` link (`kAEGetURL`, `handleURLEvent`) | Receiving Apple Events is allowed | None |
| Sends Apple Events | It doesn't: no `NSAppleScript`, no `AESend`, no Scripting Bridge in `Sources/`. cl_kit's sign-in can open Terminal through `/usr/bin/osascript`, but only for its `.scripted` window, which cl_quick doesn't use: it takes the default `.settingsFile` window (Terminal opens a settings file like any document) | None: no `com.apple.security.automation.apple-events`, no `NSAppleEventsUsageDescription` |
| Runs `claude` (the chat, the sign-in) and other tools as child processes | Allowed: they are separate programs with their own signatures; the runtime's limits don't pass to them | None |
| WebKit (`WKWebView` in the HTML preview and the inline pages) | The page runs in WebKit's own processes, which hold their own JIT rights; the app itself maps no executable memory | None (no `allow-jit`) |
| Carbon hot key (`RegisterEventHotKey`, `Shortcut.swift`) | Allowed, and needs no Accessibility permission | None |
| Distributed notifications (`DictationIMNotificationDidEnterDictationMode` and its twin, `Dictation.swift`) | Allowed: it only listens to what macOS posts | None |
| Reading aloud (`AVSpeechSynthesizer`), Dictation (`startDictation:`, macOS's own) | Speech out and macOS's Dictation, which listens, not the app: the app never records audio | None (no `audio-input`) |
| Open at login (`SMAppService.mainApp`), the Services entry | Allowed | None |
| Loads code | Only Apple's frameworks; the modules are linked in statically. No `dlopen`, no plug-ins | None (library validation stays on) |
| JIT, unsigned memory, DYLD variables, debugging | Not used | None |
| Files and network | cl_quick isn't sandboxed (it reads the Claude Code folders and talks to GitHub for the update check) | None; no App Sandbox entitlements either |

This is read from the code, not yet tried under a Developer ID. The first hardened build should be tried once: a chat
(starts `claude`), Add an account… (the sign-in's Terminal window), the HTML preview, the global shortcut, Dictation and
Read aloud, Open at login, the Ask cl_quick service. If a feature is blocked, macOS's log says which entitlement
(`log stream --predicate 'process == "cl_quick"'`), and it goes into a `Signing/cl_quick.entitlements` file that
`build.sh` passes under a Developer ID only.

**Bundle identifier** stays `local.n-uf.cl-quick`. A Developer ID signature doesn't need it registered with Apple.

## What users see once, when the signature changes

The first notarized release replaces an ad hoc signature (identified by its code hash) with a Developer ID one
(identified by its team). macOS treats it as a new identity once:

- **Open at login:** a user who turned it on may see "Background Items Added" again, now with the developer's name. From
  then on, updates signed by the same team don't ask again.
- **Automation:** no question, cl_quick sends no Apple Events itself.
- **Keychain:** cl_quick never reads the Keychain; `claude` does that itself.
- **Open Anyway** is no longer needed, and the release notes stop saying so. Update README ▸ Install after the first
  notarized release.

## Updates

cl_quick has no update framework (no Sparkle, no appcast): its update check only tells you a newer release exists and
opens the release's page, and an update is a new download from GitHub Releases
(`releases/latest/download/cl_quick.dmg` or `.zip`) or a build from source, so nothing else needs signing.

## Steps only the account holder can do

Done once, on this Mac, **for both apps**: if cl_audit's `docs/signing.md` steps are done, steps 1 to 5 are done too and
only step 6 is new. None of them can be done by a script: they need the Apple Account, its password and two-factor
sign-in. Never paste a password into a chat or a file.

### 1. Join the Apple Developer Program

1. Open <https://developer.apple.com/programs/enroll/> in Safari and click **Start Your Enrollment**.
2. Sign in with the Apple Account that will own the certificate (two-factor authentication must be on).
3. Choose **Individual / Sole Proprietor** (or **Organization**, which needs a D-U-N-S number), confirm the details and pay
   the yearly fee (99 USD).
4. Wait for the confirmation email (from minutes to two days). Then
   <https://developer.apple.com/account> ▸ **Membership details** shows the **Team ID**: ten characters, needed below.

### 2. The Developer ID Application certificate (Xcode)

1. Open **Xcode** ▸ **Settings…** (⌘,) ▸ **Accounts**.
2. Click **+** at the bottom left ▸ **Apple ID** ▸ **Continue**, and sign in with the same Apple Account.
3. Select the account ▸ select the team on the right ▸ **Manage Certificates…**.
4. Click **+** at the bottom left ▸ **Developer ID Application**. Xcode makes the key in this Mac's login Keychain and the
   certificate with Apple. Click **Done**.
5. Optional but wise: in **Keychain Access** ▸ login ▸ **My Certificates**, right-click "Developer ID Application: …" ▸
   **Export…** and keep the `.p12` with a strong password somewhere safe (not in a repository). Without it, a new Mac means
   a new certificate.

Only the account holder can make a Developer ID certificate, and a team can have only a few. Don't revoke it: apps signed
with a revoked Developer ID stop opening.

### 3. The identity string

In Terminal:

```bash
security find-identity -v -p codesigning
```

On the line with `"Developer ID Application: Your Name (TEAMID)"`, the 40-character hash before the name is the best
value for `CL_SIGN_ID`: when the certificate is renewed, the old and the new one share the name, and the hash still
names one. The whole name in the quotes works too. The list shows names and hashes only, no key.

### 4. An app-specific password for notarytool

1. Open <https://account.apple.com> ▸ **Sign-In and Security** ▸ **App-Specific Passwords** ▸ **+**.
2. Name it `n-uf notary` and click **Create**. Copy the password it shows (once only).

### 5. The notary profile in the Keychain

In Terminal (it asks for the app-specific password and stores it in the login Keychain; nothing goes into a file):

```bash
xcrun notarytool store-credentials cl-notary --apple-id "<apple-account-address>" --team-id "TEAMID"
```

Use the Apple Account's address and the Team ID from step 1. `cl-notary` is then the value for `CL_NOTARY_PROFILE`, for
cl_quick and cl_audit alike. Check it:

```bash
xcrun notarytool history --keychain-profile cl-notary
```

An empty list is fine ("No submission history"); an error means the profile or the password is wrong.

### 6. Check, then try, then release

```bash
CL_SIGN_ID="Developer ID Application: Your Name (TEAMID)" CL_NOTARY_PROFILE=cl-notary scripts/release.sh --check-signing
```

Both lines should say found / answers. Then, once, the whole chain without a release (a few minutes at Apple):

```bash
CL_SIGN_ID="Developer ID Application: Your Name (TEAMID)" CL_NOTARY_PROFILE=cl-notary scripts/release.sh --local
```

The first signing may ask whether codesign may use the key: **Always Allow**. Then try the hardened app as the
Entitlements section says, and release as usual with the two settings in front of `scripts/release.sh --push`. They hold
no secret themselves.

Prefer setting them on the release command, not exporting them from a shell profile: with `CL_SIGN_ID` exported, every
local `./build.sh` signs with the Developer ID too. It then needs the network (Apple's timestamp server) and installs a
hardened build.

After the first notarized release, update README ▸ Install: the Open Anyway step goes away.
