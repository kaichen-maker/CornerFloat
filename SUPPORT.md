# CornerFloat Support

- Show or hide all panels globally with **Shift-Command-Space** by default; if it conflicts, choose another preset in **Settings → Global Shortcut**.
- Use the menu-bar CornerFloat icon even if all panels are hidden.
- Choose **Quit CornerFloat** to stop the app completely.
- Normal web panels require no special macOS privacy permission.
- Local source builds hide release-only Passkey and automatic-update actions. An eligible signed release never requests Passkey access at launch; use **CornerFloat → Enable or Review Passkey Access…** when that action is available.

Create or edit an address-bar alias under **Windows & Library → Quick Sites**. A Quick Site accepts only an HTTP or HTTPS destination and remains in the current macOS user account.

Use **Settings → Local Data** to export, validate and import, or reveal the
CornerFloat library. Import replaces the current four library collections only;
it does not close web panels or change website cookies and sign-ins.

If passkey access was denied, open **System Settings → Privacy & Security → Passkeys Access for Web Browsers** and enable CornerFloat, then reload the affected sign-in page. If that setting is unavailable on a managed Mac, contact its administrator. A public CornerFloat build also needs Apple-approved Web Browser Public Key Credential entitlement and Developer ID signing; an ad-hoc development build cannot complete that real cross-site acceptance test.

For a website problem, retry in CornerFloat and then test the same page in the default browser. CornerFloat only retries an intact body-free GET/HEAD request; it will not silently replay a failed form POST. CornerFloat permits ChatGPT's Google redirect to continue in the panel and identifies itself truthfully in WebKit's user-agent; it does not impersonate Safari or Chrome, inject authentication scripts, or rewrite requests. Google may still reject OAuth in `WKWebView`, and Microsoft or an organization may apply similar policy. Use **More → Open in Default Browser** only if the provider actually refuses the session. That browser's Cookie session remains separate and cannot be imported into the panel.

For a support request, include the app version/build, macOS version, Mac architecture, exact steps, and a redacted screenshot. Never include passwords, passkeys, session cookies, or authentication codes. The in-app Support page includes a safe diagnostics copier.
