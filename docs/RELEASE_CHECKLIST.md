# CornerFloat release checklist

> Optional maintainer workflow: publishing source code, accepting contributions,
> running CI, and using a local build do not require anything in this checklist.
> See [Build CornerFloat from Source](SOURCE_BUILD.md).

This checklist is only for a downloadable public CornerFloat binary. A local ad-hoc build is not a public release: it has no trusted Developer ID chain, notarization ticket, or signed update feed.

## One-time release setup

### Apple signing and notarization

- [ ] Enroll the release owner in the Apple Developer Program.
- [ ] Install a valid **Developer ID Application** certificate and private key in the release Keychain.
- [ ] Confirm the exact identity appears in `security find-identity -v -p codesigning`.
- [ ] Create an App Store Connect API key for notarization and keep the `.p8` file private.
- [ ] For local releases, store a notarytool profile with `xcrun notarytool store-credentials CornerFloat`.
- [ ] Keep the bundle identifier `com.calvinkai.cornerfloat` stable.

The items above are sufficient for the baseline signed and notarized release.
That release deliberately contains no
`com.apple.developer.web-browser.public-key-credential` entitlement and hides
the unavailable cross-site Passkey control. Ordinary WebKit password login and
the rest of CornerFloat do not depend on this optional managed capability.

For an optional Passkey-enabled release only:

- [ ] As the Apple Developer Account Holder, request and obtain approval for the managed `com.apple.developer.web-browser.public-key-credential` entitlement for this bundle identifier.
- [ ] Create and download the **Developer ID distribution provisioning profile** for the explicit App ID `com.calvinkai.cornerfloat` after Apple approves the managed capability. The source entitlement alone does not grant cross-site passkey access.
- [ ] Decode the profile with `security cms -D -i <profile>` and confirm it has at least 30 days of validity remaining, has `ProvisionsAllDevices = true`, belongs to the Developer ID signing team, targets the exact bundle ID, contains the signing certificate, and authorizes `com.apple.developer.web-browser.public-key-credential = true`.

Apple documents the macOS embed path and App ID binding in [TN3125: Inside Code Signing — Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles), and notes that Developer ID provisioning profiles are evaluated at every launch on the [Developer ID support page](https://developer.apple.com/support/developer-id/).

### Sparkle update identity

- [ ] Generate the Sparkle EdDSA key pair with `scripts/setup-update-key.sh`.
- [ ] Export an owner-only backup explicitly, for example:

  ```bash
  SPARKLE_PRIVATE_KEY_EXPORT="$HOME/CornerFloat-Sparkle.key" scripts/setup-update-key.sh
  ```

  Move that export into encrypted/offline storage immediately. The script refuses to overwrite an existing export and writes it with mode `600`.
- [ ] Convert the exported key to the protected GitHub Environment secret only when configuring CI. Base64 is transport encoding, **not encryption**:

  ```bash
  base64 < /secure/offline/CornerFloat-Sparkle.key | tr -d '\n' | pbcopy
  ```

  Paste the clipboard into the `SPARKLE_PRIVATE_KEY_BASE64` secret, then immediately clear the clipboard with `pbcopy < /dev/null`. Do not save the base64 text in the repository, release assets, shell history, CI artifacts, or an unencrypted notes app.
- [ ] Back up the private key offline; never commit it, attach it to a release, or print it in CI logs.
- [ ] Record the public key as `SPARKLE_PUBLIC_KEY`.
- [ ] Verify the configured public key is derived from the release private key. `scripts/release.sh` refuses publication when they do not match.
- [ ] Treat the Sparkle public key as immutable after the first public release. Changing it breaks the trust path from installed versions unless a deliberate key-rotation migration is shipped first.

### Public update host

- [ ] Use a public HTTPS repository or another stable public HTTPS host. Installed apps must be able to fetch the feed without GitHub credentials or a private-session cookie.
- [ ] For the included GitHub flow, make the repository public before announcing automatic updates.
- [ ] Keep the feed URL stable: `https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml`.
- [ ] Keep update archive URLs release-specific: `https://github.com/<owner>/<repo>/releases/download/<tag>/<archive>`.
- [ ] Do not publish an appcast that points to `file://`, localhost, a private repository, or an expiring URL.

### GitHub Actions protection

- [ ] Create a GitHub Actions Environment named `release`.
- [ ] Require an authorized reviewer for the `release` environment.
- [ ] Put signing, notarization, and Sparkle private-key secrets in the protected `release` environment, not in unprotected repository variables.
- [ ] Keep workflow default permissions read-only; grant `contents: write` only to the release job.
- [ ] Keep checkout credentials disabled (`persist-credentials: false`) and pin third-party actions to reviewed commit SHAs.
- [ ] Release only through the manual `workflow_dispatch` input after the target commit on the default branch has been reviewed. Do not expose release credentials to arbitrary tag pushes or pull requests.

## Required GitHub Actions secrets

Configure these in the protected `release` environment:

- `DEVELOPER_ID_APPLICATION` — full identity, for example `Developer ID Application: Name (TEAMID)`.
- `DEVELOPER_ID_CERTIFICATE_BASE64` — base64-encoded Developer ID `.p12`.
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`.
- `DEVELOPER_ID_PROVISIONING_PROFILE_BASE64` — **optional**; configure it only for a Passkey-enabled release. It is the base64-encoded Developer ID `.provisionprofile` for the explicit CornerFloat App ID. When the workflow's Passkey option is selected, CI requires this secret, decodes it into an owner-only temporary file, derives the exact signing entitlements from it, validates both, and embeds the profile. The baseline workflow does not decode or pass this secret even if it exists.
- `BUILD_KEYCHAIN_PASSWORD` — an ephemeral CI keychain password.
- `NOTARY_API_PRIVATE_KEY_BASE64` — base64-encoded App Store Connect `.p8`.
- `NOTARY_API_KEY_ID`.
- `NOTARY_API_ISSUER_ID`.
- `SPARKLE_PUBLIC_KEY`.
- `SPARKLE_PRIVATE_KEY_BASE64` — one-line base64 of the owner-only export created by `SPARKLE_PRIVATE_KEY_EXPORT`; CI decodes it to an ephemeral mode-`600` file, unsets the encoded secret immediately, and deletes the file after signing.

## Prepare a release

- [ ] Confirm the protected workflow is using GitHub's `macos-26` runner so the release is compiled and linked with Xcode 26's AppKit design system and native Liquid Glass APIs while retaining the declared macOS 14 deployment target.
- [ ] Run `make universal` locally. It must compile `arm64-apple-macosx14.0` and `x86_64-apple-macosx14.0` with the same selected SDK, combine only the two successful thin executables, and report exact `arm64, x86_64` architecture sets for CornerFloat and every executable inside Sparkle.framework. Normal `make build` remains a fast native-only build.
- [ ] Select the reviewed commit on the repository default branch.
- [ ] Choose a strict `vX.Y.Z` tag, for example `v0.8.0`.
- [ ] Set `CFBundleShortVersionString` in `Resources/Info.plist` to the same `X.Y.Z` value.
- [ ] Increase `CFBundleVersion` to a positive integer greater than every previously published Sparkle build number.
- [ ] Increase (or at minimum never roll back) `CFBundleShortVersionString`; the validator compares it with the latest public appcast as strict `major.minor.patch` SemVer.
- [ ] Update `RELEASE_NOTES.md` with user-visible changes and known limitations.
- [ ] Move the target version from the changelog's `[Unreleased]` section into one exact dated `## [X.Y.Z] - YYYY-MM-DD` section, and start a new `[Unreleased]` section above it. The release metadata validator rejects source-preview or draft wording.
- [ ] Confirm `Package.resolved` pins the intended Sparkle version.
- [ ] Confirm `PRIVACY.md`, `SUPPORT.md`, the in-app pages, icon, and copyright are current.
- [ ] Confirm `Resources/Info.plist` still declares HTTP and HTTPS handling and contains a truthful, non-empty `NSMicrophoneUsageDescription`. Confirm the app has no camera usage description.
- [ ] Confirm `Resources/CornerFloat.entitlements` enables `com.apple.security.device.audio-input` and does not enable camera capture. Extract the final signature entitlements from baseline and Passkey-enabled candidates and confirm the same audio-input boundary survives every signing path.
- [ ] For a baseline release, confirm the release script rejects any occurrence of the managed Passkey entitlement or an embedded provisioning profile while preserving the required audio-input entitlement.
- [ ] For an optional Passkey-enabled release, confirm the release script decodes and validates the Developer ID provisioning profile before building, derives the final `com.apple.application-identifier`, team identifier, and Passkey signing entitlements from that profile, then repeats an exact profile/signature/certificate comparison against both the signed app and the app extracted from the update ZIP.
- [ ] Run `scripts/swiftpm.sh resolve` and `scripts/test.sh` locally.
- [ ] On a logged-in macOS GUI session, run `scripts/acceptance-tests.sh`. It must prove the real Carbon shortcut callback, AppKit panel/menu smoke flow, edge hide/reveal, lifecycle JSON contract, and bounded idle CPU sampling. This safe suite does not replace the hardware acceptance section below.
- [ ] Run `scripts/sparkle-e2e-test.sh`. It must show that pinned Sparkle reads `SUFeedURL` and `SUPublicEDKey` from the temporary old app (without a `--feed-url` override), selects the newer build, downloads it from the loopback-only test feed, rejects a tampered archive, and installs the untouched EdDSA-signed archive. This test uses no Keychain or release secret and does not replace Developer ID/notarization acceptance.
- [ ] Confirm `Resources/Info.plist` and the normal build contain no `SUAllowsInsecureUpdate`. The E2E script injects that key only into its throwaway loopback fixture; `release.sh` refuses to continue if it appears in a public build.
- [ ] Run `python3 scripts/validate_release.py version --info-plist Resources/Info.plist --tag vX.Y.Z`.
- [ ] Confirm the latest published release contains `appcast.xml` and that the new build number is greater than its feed build. The workflow permits the no-appcast path only when the public GitHub API proves the repository has no release history at all; API, network, missing-asset, and malformed-feed failures stop the release.

## Run the protected release workflow

1. Open **Actions → Optional: Signed Binary Release → Run workflow**.
2. Select the repository default branch.
3. Enter the exact `vX.Y.Z` tag in the required `workflow_dispatch` input.
4. Leave **Include the optional Apple-approved cross-site Passkey entitlement** off for a baseline release. Turn it on only when the protected provisioning-profile secret is configured and the Apple approval is current.
5. Review and approve the protected `release` environment request.
6. Confirm the validation/test job finishes before any signing secret is imported.
7. Confirm the release job reports either `baseline` or `passkey`, creates a draft from the validated commit, uploads and verifies every expected asset name and byte size, publishes it as the latest release, then anonymously re-downloads and verifies the public update chain.

Only one release workflow can run at a time across all tags. If draft creation, upload, verification, or publication fails, the workflow removes the incomplete release and its workflow-created tag.

The release job must stop rather than publish if any of these checks fail:

- tag, marketing version, or build number validation;
- Developer ID identity lookup;
- a missing microphone purpose string or missing/false audio-input entitlement;
- Hardened Runtime or nested Sparkle framework signing;
- a missing, duplicate, or unexpected architecture in the CornerFloat executable or any Sparkle executable; formal release artifacts must contain exactly arm64 and x86_64;
- a managed Web Browser Public Key Credential entitlement or embedded provisioning profile appearing in a baseline release;
- a half-configured Passkey profile/entitlements pair;
- for an optional Passkey-enabled release, a missing or false entitlement, or a missing, expired, device-limited, wrong-team, wrong-bundle, wrong-certificate, or Passkey-ineligible Developer ID provisioning profile, or any mismatch between that profile and the final signed application/team/Passkey entitlements;
- Sparkle private/public key match;
- notarization or ticket stapling;
- final DMG image integrity and Developer ID signature verification after stapling;
- appcast signature, build, file length, HTTPS URL, or archive-name validation;
- deterministic `SHA256SUMS.txt` generation or verification for every published asset other than the manifest itself;
- anonymous post-publication download of the stable appcast, its release-specific enclosure, and the checksum manifest, including byte-for-byte comparison with the locally verified artifacts.

## Inspect the produced artifacts

Expected release assets:

```text
CornerFloat-<version>-macOS-universal.dmg
CornerFloat-macOS-universal.zip
CornerFloat-<version>-<build>-macOS-universal.zip
CornerFloat-<version>-<build>-macOS-universal.md
appcast.xml
SHA256SUMS.txt
PRIVACY.md
SUPPORT.md
```

- [ ] Verify the app signature:

  ```bash
  codesign --verify --deep --strict --verbose=2 CornerFloat.app
  codesign --display --verbose=4 CornerFloat.app
  ```

- [ ] Confirm the displayed authority is the intended **Developer ID Application**, the Team ID is correct, and the `runtime` flag is present.
- [ ] Confirm the final signature has `com.apple.security.device.audio-input = true`, has no camera entitlement, and the final app has no camera usage description.
- [ ] For a baseline release, confirm `CornerFloat.app/Contents/embedded.provisionprofile` is absent. For a Passkey-enabled release, confirm it exists and decode it with `security cms -D -i`; confirm the Team ID, exact App ID, expiration, `ProvisionsAllDevices`, and Passkey entitlement match the final signature.
- [ ] Run `lipo -archs` on `Contents/MacOS/CornerFloat`, `Sparkle`, `Autoupdate`, `Updater`, `Installer`, and `Downloader`; every result must contain exactly `arm64 x86_64` (order is not significant).
- [ ] Validate the stapled app ticket:

  ```bash
  xcrun stapler validate CornerFloat.app
  ```

- [ ] Validate the DMG image and its ticket:

  ```bash
  hdiutil verify CornerFloat-<version>-macOS-universal.dmg
  xcrun stapler validate CornerFloat-<version>-macOS-universal.dmg
  ```

- [ ] Run Gatekeeper assessment:

  ```bash
  spctl --assess --type execute --verbose=2 CornerFloat.app
  spctl --assess --type open --context context:primary-signature --verbose=2 CornerFloat-<version>-macOS-universal.dmg
  ```

- [ ] Confirm both assessments are accepted and identify the expected Developer ID team.
- [ ] Extract the update archive separately and repeat the app signature, stapler, and Gatekeeper checks on the contained app.

## Validate the update feed

- [ ] Confirm the protected workflow anonymously downloaded the stable `appcast.xml`, the release-specific enclosure, and `SHA256SUMS.txt` after publication. It must rerun the appcast validator, verify both downloaded files against the manifest, and prove all three public byte streams exactly match the locally verified release artifacts.
- [ ] Download `appcast.xml` and its enclosure from their public HTTPS URLs without being signed in to GitHub.
- [ ] Verify the public checksum manifest against the downloaded feed and enclosure:

  ```bash
  python3 scripts/release_checksums.py verify \
    --manifest SHA256SUMS.txt \
    appcast.xml \
    CornerFloat-<version>-<build>-macOS-universal.zip
  ```

- [ ] Run the repository validator against the exact published archive:

  ```bash
  python3 scripts/validate_release.py appcast \
    --appcast appcast.xml \
    --archive CornerFloat-<version>-<build>-macOS-universal.zip \
    --build <build> \
    --download-prefix https://github.com/<owner>/<repo>/releases/download/<tag>
  ```

- [ ] Confirm the enclosure filename, byte length, build number, HTTPS URL, and 64-byte EdDSA signature match the published archive.
- [ ] Confirm the stable `/releases/latest/download/appcast.xml` URL resolves to the new feed.
- [ ] Install the previous public CornerFloat release, choose **Check for Updates…**, download the update, relaunch, and confirm the new version/build.
- [ ] Repeat the update test with automatic checks enabled and with the app installed in `/Applications`.

## Lifecycle and energy diagnostics

- [ ] Run `./scripts/lifecycle-diagnostics.sh` on the release-candidate build.
- [ ] Preserve its JSON evidence that the real AppKit panel was rehomed and sleep/wake/Space callbacks were delivered.
- [ ] Confirm the reported idle average CPU is below the configured acceptance limit.
- [ ] Complete every hardware-dependent item in [Lifecycle, display and energy verification](LIFECYCLE_AND_ENERGY_TESTING.md); the safe diagnostic deliberately does not claim to prove physical display removal or real system sleep.

## Clean-machine acceptance

Test on a Mac that does not have the development certificate or repository checkout:

- [ ] Download the DMG from the public release page.
- [ ] Open the DMG normally and drag CornerFloat into `/Applications`.
- [ ] Launch it through Finder and confirm Gatekeeper does not show an unidentified-developer warning.
- [ ] Complete onboarding and open a normal web panel without granting special macOS privacy access.
- [ ] Before using any website media control, confirm CornerFloat has not asked for microphone or camera access.
- [ ] On an HTTPS test page, click a microphone-only voice or dictate control. Confirm microphone permission is requested only after that action and that macOS and the requesting website remain separate user-controlled decisions. Respond to both prompts in the order the system presents them, then confirm audio capture starts without the web content process terminating or showing **Content failed to load**.
- [ ] Stop voice mode and confirm capture ends. Quit and reopen CornerFloat, reload the same HTTPS page, and confirm normal browsing still does not start capture.
- [ ] Repeat on a clean test account or reset privacy state, deny the macOS decision, and confirm the page remains alive. Enable CornerFloat under **System Settings → Privacy & Security → Microphone**, reload, and confirm the website can request again.
- [ ] Request camera-only and combined camera-and-microphone capture from a controlled HTTPS fixture. Confirm both are denied and no camera permission prompt appears.
- [ ] Confirm `Shift-Command-Space`, tabs, search, favorites, recents, saved workspaces, upload/download, and quit behavior.
- [ ] From a logged-out or isolated website-data profile, open ChatGPT and
      complete **Continue with Google** inside the CornerFloat panel using a
      maintainer-controlled test account. Confirm the flow reaches Google's
      account page, returns to `https://chatgpt.com/`, and shows the authenticated
      ChatGPT interface.
- [ ] Quit and relaunch the same build, reopen ChatGPT, and confirm the WebKit
      login session persists. Do not include credentials, one-time codes, OAuth
      query strings, or cookies in logs or screenshots.
- [ ] Confirm **More → Open in Default Browser** remains available as a manual
      fallback for providers or organization policies that reject the in-panel
      session.
- [ ] For a baseline release, confirm **Enable or Review Passkey Access…** is absent and the final code signature contains no `com.apple.developer.web-browser.public-key-credential` entitlement.
- [ ] For an optional Passkey-enabled release, choose **Enable or Review Passkey Access…**, verify the macOS prompt appears only from that action, and test one disposable-account passkey flow. If the state was denied, confirm the app directs the user to **Privacy & Security → Passkeys Access for Web Browsers**.
- [ ] Test multiple displays, display disconnection, Spaces, a full-screen app, sleep/wake, edge auto-hide, and resizing between Retina and non-Retina displays.

## Final publication check

- [ ] Release title and notes match the tag and `RELEASE_NOTES.md`.
- [ ] Every published asset was produced by the approved workflow run; no local replacement files were uploaded afterward.
- [ ] Privacy and support links are reachable.
- [ ] The previous public version completes one end-to-end Sparkle update.
- [ ] Only after all checks pass, announce the release.
