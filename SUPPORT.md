# CornerFloat Support

- Show or hide all panels globally with **Shift-Command-Space** by default; if it conflicts, choose another preset in **Settings → Global Shortcut**.
- Use the menu-bar CornerFloat icon even if all panels are hidden.
- Choose **Quit CornerFloat** to stop the app completely.
- Normal browsing requires no special macOS privacy permission. An HTTPS website
  can request microphone access for voice or dictation, but it receives no audio
  until the user approves both macOS and WebKit decisions.
- Local source builds hide release-only Passkey and automatic-update actions. An eligible signed release never requests Passkey access at launch; use **CornerFloat → Enable or Review Passkey Access…** when that action is available.

Create or edit an address-bar alias under **Windows & Library → Quick Sites**. A Quick Site accepts only an HTTP or HTTPS destination and remains in the current macOS user account.

Use **Settings → Local Data** to export, validate and import, or reveal the
CornerFloat library. Import replaces the current four library collections only;
it does not close web panels or change website cookies and sign-ins.

If passkey access was denied, open **System Settings → Privacy & Security → Passkeys Access for Web Browsers** and enable CornerFloat, then reload the affected sign-in page. If that setting is unavailable on a managed Mac, contact its administrator. A public CornerFloat build also needs Apple-approved Web Browser Public Key Credential entitlement and Developer ID signing; an ad-hoc development build cannot complete that real cross-site acceptance test.

## Website voice or dictation does not start

1. Confirm the address begins with `https://`. CornerFloat denies microphone
   requests from insecure pages and denies all camera or combined
   camera-and-microphone requests.
2. Click the website's voice, dictate, or microphone control again. CornerFloat
   itself does not request microphone access at launch, although a website can
   choose when its code asks for access.
3. Respond to both the macOS CornerFloat microphone prompt and the requesting
   website's own WebKit microphone prompt in the order they appear. These are
   separate decisions, and CornerFloat does not grant either automatically.
4. If macOS access was previously denied, quit CornerFloat, open **System
   Settings → Privacy & Security → Microphone**, enable CornerFloat, reopen it,
   and reload the HTTPS page.
5. If CornerFloat is already enabled, review the website's own microphone or
   site settings, account requirements, and service status. Test the same
   feature in the default browser to distinguish a site problem from an app
   problem.

CornerFloat does not itself record, store, or upload audio. Once both permissions
are granted, the selected website handles microphone audio under its own privacy
policy. Stop voice mode on the website when finished. If the feature requires a
camera, use a browser that supports that request because CornerFloat keeps camera
capture outside its current scope.

## Bluetooth voice sounds deep, slow, or delayed

[Apple explains](https://support.apple.com/en-us/102217) that using a Bluetooth
headset for both playback and microphone input switches it from high-quality
listening to lower-quality two-way audio. Before WebKit presents an HTTPS
website's microphone decision on a risky Bluetooth input/output route,
CornerFloat offers three choices when a built-in input is available:

- **Use Mac Microphone** temporarily changes the system default input to the
  built-in microphone, then continues to the website's WebKit decision. This
  happens only after the user clicks the button.
- **Continue with Bluetooth** leaves the current input and output unchanged and
  continues to the website's WebKit decision.
- **Cancel** denies the current website microphone request.

If no built-in microphone is available, the explanation offers only
**Continue with Bluetooth** and **Cancel**.

After a temporary switch, CornerFloat makes a best-effort attempt to restore the
previous input when the website stops microphone capture, the panel closes, or
the app quits. It restores only if the default input is still the device
CornerFloat selected. If the user changes the input in the meantime, that later
system change makes CornerFloat relinquish its restoration ownership. The
temporary default-input change is system-wide, so another audio app opened
during the session can see the Mac microphone too.

If audio remains distorted, end the website's voice session, choose the Mac's
built-in microphone under **System Settings → Sound → Input**, and start the
session again. Include the selected input and output device names in a support
report, but never include a recording of a private conversation.

For a website problem, retry in CornerFloat and then test the same page in the default browser. CornerFloat only retries an intact body-free GET/HEAD request; it will not silently replay a failed form POST. CornerFloat permits ChatGPT's Google redirect to continue in the panel and identifies itself truthfully in WebKit's user-agent; it does not impersonate Safari or Chrome, inject authentication scripts, or rewrite requests. Google may still reject OAuth in `WKWebView`, and Microsoft or an organization may apply similar policy. Use **More → Open in Default Browser** only if the provider actually refuses the session. That browser's Cookie session remains separate and cannot be imported into the panel.

For a support request, include the app version/build, macOS version, Mac architecture, exact steps, and a redacted screenshot. Never include passwords, passkeys, session cookies, or authentication codes. The in-app Support page includes a safe diagnostics copier.
