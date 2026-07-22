#!/usr/bin/env python3
"""Focused regression tests for release version monotonicity."""

from __future__ import annotations

import base64
import datetime as dt
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
VALIDATOR = ROOT / "scripts" / "validate_release.py"


def write_appcast(path: Path, build: str, marketing_version: str | None) -> None:
    short_version = (
        f'<sparkle:shortVersionString>{marketing_version}</sparkle:shortVersionString>'
        if marketing_version is not None
        else ""
    )
    path.write_text(
        f"""<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel><item>
    <sparkle:version>{build}</sparkle:version>
    {short_version}
    <enclosure url="https://example.com/CornerFloat.zip" length="1" type="application/octet-stream" />
  </item></channel>
</rss>
""",
        encoding="utf-8",
    )


def run_validator(info: Path, appcast: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(VALIDATOR),
            "version",
            "--info-plist",
            str(info),
            "--tag",
            "v0.5.0",
            "--previous-appcast",
            str(appcast),
        ],
        check=False,
        capture_output=True,
        text=True,
    )


def expect_failure(result: subprocess.CompletedProcess[str], fragment: str) -> None:
    if result.returncode == 0 or fragment not in result.stderr:
        raise SystemExit(
            f"expected validator failure containing {fragment!r}; "
            f"returncode={result.returncode}, stderr={result.stderr!r}"
        )


def write_signed_appcast(
    path: Path,
    archive: Path,
    download_prefix: str,
    *,
    build: str = "7",
    marketing_version: str = "0.5.0",
) -> None:
    signature = base64.b64encode(bytes(64)).decode("ascii")
    path.write_text(
        f"""<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel><item>
    <sparkle:version>{build}</sparkle:version>
    <sparkle:shortVersionString>{marketing_version}</sparkle:shortVersionString>
    <enclosure url="{download_prefix.rstrip('/')}/{archive.name}"
      length="{archive.stat().st_size}"
      type="application/octet-stream"
      sparkle:edSignature="{signature}" />
  </item></channel>
</rss>
""",
        encoding="utf-8",
    )


def run_appcast_validator(
    appcast: Path,
    archive: Path,
    download_prefix: str,
    *,
    allow_local: bool,
) -> subprocess.CompletedProcess[str]:
    command = [
        sys.executable,
        str(VALIDATOR),
        "appcast",
        "--appcast",
        str(appcast),
        "--archive",
        str(archive),
        "--build",
        "7",
        "--short-version",
        "0.5.0",
        "--download-prefix",
        download_prefix,
    ]
    if allow_local:
        command.append("--allow-local-test-url")
    return subprocess.run(command, check=False, capture_output=True, text=True)


def run_entitlements_validator(
    path: Path,
    *,
    passkey_policy: str,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(VALIDATOR),
            "entitlements",
            "--entitlements-plist",
            str(path),
            "--passkey-policy",
            passkey_policy,
        ],
        check=False,
        capture_output=True,
        text=True,
    )


def run_signing_mode_validator(
    *,
    profile: Path | None = None,
    entitlements: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    command = [sys.executable, str(VALIDATOR), "signing-mode"]
    if profile is not None:
        command.extend(["--provisioning-profile", str(profile)])
    if entitlements is not None:
        command.extend(["--signing-entitlements", str(entitlements)])
    return subprocess.run(command, check=False, capture_output=True, text=True)


def run_architecture_validator(
    architectures: str,
    *,
    required: tuple[str, ...] = ("arm64", "x86_64"),
) -> subprocess.CompletedProcess[str]:
    command = [
        sys.executable,
        str(VALIDATOR),
        "architecture-set",
        "--label",
        "test binary",
    ]
    for architecture in required:
        command.extend(["--required-architecture", architecture])
    return subprocess.run(
        command,
        input=architectures,
        check=False,
        capture_output=True,
        text=True,
    )


def run_metadata_validator(
    info: Path,
    notes: Path,
    changelog: Path,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(VALIDATOR),
            "release-metadata",
            "--info-plist",
            str(info),
            "--tag",
            "v0.5.0",
            "--release-notes",
            str(notes),
            "--changelog",
            str(changelog),
        ],
        check=False,
        capture_output=True,
        text=True,
    )


def write_profile(
    path: Path,
    *,
    team_id: str = "ABCDE12345",
    bundle_id: str = "com.calvinkai.cornerfloat",
    prefix: str = "ZYXWV98765",
    expires_in_days: int = 365,
    passkey: bool = True,
    application_identifier: str | None = None,
    all_devices: bool = True,
    provisioned_devices: list[str] | None = None,
) -> None:
    entitlements = {
        "com.apple.application-identifier": (
            application_identifier or f"{prefix}.{bundle_id}"
        ),
        "com.apple.developer.team-identifier": team_id,
        "com.apple.developer.web-browser.public-key-credential": passkey,
    }
    profile: dict[str, object] = {
        "ApplicationIdentifierPrefix": [prefix],
        "DeveloperCertificates": [b"certificate-der"],
        "Entitlements": entitlements,
        "ExpirationDate": (
            dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)
            + dt.timedelta(days=expires_in_days)
        ),
        "ProvisionsAllDevices": all_devices,
        "TeamIdentifier": [team_id],
    }
    if provisioned_devices is not None:
        profile["ProvisionedDevices"] = provisioned_devices
    with path.open("wb") as stream:
        plistlib.dump(profile, stream)


def run_profile_validator(
    path: Path,
    *,
    team_id: str = "ABCDE12345",
    bundle_id: str = "com.calvinkai.cornerfloat",
    signed_entitlements: Path | None = None,
    signing_certificate: Path | None = None,
    write_signing_entitlements: Path | None = None,
) -> subprocess.CompletedProcess[str]:
    command = [
        sys.executable,
        str(VALIDATOR),
        "profile",
        "--profile-plist",
        str(path),
        "--bundle-id",
        bundle_id,
        "--team-id",
        team_id,
    ]
    if signed_entitlements is not None:
        command.extend(["--signed-entitlements-plist", str(signed_entitlements)])
    if signing_certificate is not None:
        command.extend(["--signing-certificate-der", str(signing_certificate)])
    if write_signing_entitlements is not None:
        command.extend(["--write-signing-entitlements", str(write_signing_entitlements)])
    return subprocess.run(
        command,
        check=False,
        capture_output=True,
        text=True,
    )


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="CornerFloat-validator-test-") as temporary:
        root = Path(temporary)
        info = root / "Info.plist"
        with info.open("wb") as stream:
            plistlib.dump(
                {
                    "CFBundleShortVersionString": "0.5.0",
                    "CFBundleVersion": "7",
                },
                stream,
            )

        previous = root / "appcast.xml"
        write_appcast(previous, "6", "0.4.9")
        passing = run_validator(info, previous)
        if passing.returncode != 0:
            raise SystemExit(f"valid release was rejected: {passing.stderr}")

        write_appcast(previous, "6", "0.6.0")
        expect_failure(run_validator(info, previous), "marketing version 0.5.0 is older")

        write_appcast(previous, "7", "0.4.9")
        expect_failure(run_validator(info, previous), "build 7 is not newer")

        write_appcast(previous, "6", None)
        expect_failure(run_validator(info, previous), "invalid marketing version")

        release_notes = root / "RELEASE_NOTES.md"
        changelog = root / "CHANGELOG.md"
        release_notes.write_text(
            "# CornerFloat 0.5.0\n\nA release-ready summary.\n",
            encoding="utf-8",
        )
        changelog.write_text(
            "# Changelog\n\n## [Unreleased]\n\n## [0.5.0] - 2026-07-20\n",
            encoding="utf-8",
        )
        metadata_result = run_metadata_validator(info, release_notes, changelog)
        if metadata_result.returncode != 0:
            raise SystemExit(f"valid release metadata was rejected: {metadata_result.stderr}")
        release_notes.write_text(
            "# CornerFloat 0.5.0 source preview\n\nDraft notes.\n",
            encoding="utf-8",
        )
        expect_failure(
            run_metadata_validator(info, release_notes, changelog),
            "release notes must start with",
        )
        release_notes.write_text(
            "# CornerFloat 0.5.0\n\nThese are draft notes for a source preview.\n",
            encoding="utf-8",
        )
        expect_failure(
            run_metadata_validator(info, release_notes, changelog),
            "preview-only wording",
        )
        release_notes.write_text(
            "# CornerFloat 0.5.0\n\nA release-ready summary.\n",
            encoding="utf-8",
        )
        changelog.write_text(
            "# Changelog\n\n## [Unreleased]\n",
            encoding="utf-8",
        )
        expect_failure(
            run_metadata_validator(info, release_notes, changelog),
            "exactly one dated [0.5.0] section",
        )

        archive = root / "CornerFloat-0.5.0-7-macOS-arm64.zip"
        archive.write_bytes(b"archive")
        local_prefix = "http://127.0.0.1:49321/updates"
        signed_appcast = root / "signed-appcast.xml"
        write_signed_appcast(signed_appcast, archive, local_prefix)
        local_result = run_appcast_validator(
            signed_appcast,
            archive,
            local_prefix,
            allow_local=True,
        )
        if local_result.returncode != 0:
            raise SystemExit(f"valid loopback test appcast was rejected: {local_result.stderr}")

        expect_failure(
            run_appcast_validator(
                signed_appcast,
                archive,
                local_prefix,
                allow_local=False,
            ),
            "must be an absolute HTTPS URL",
        )

        non_loopback_prefix = "http://example.com:49321/updates"
        write_signed_appcast(signed_appcast, archive, non_loopback_prefix)
        expect_failure(
            run_appcast_validator(
                signed_appcast,
                archive,
                non_loopback_prefix,
                allow_local=True,
            ),
            "must be an HTTP loopback URL",
        )

        entitlements = root / "signed-entitlements.plist"
        passkey_key = "com.apple.developer.web-browser.public-key-credential"
        audio_input_key = "com.apple.security.device.audio-input"
        camera_key = "com.apple.security.device.camera"
        with entitlements.open("wb") as stream:
            plistlib.dump(
                {
                    audio_input_key: True,
                    passkey_key: True,
                },
                stream,
            )
        entitlement_result = run_entitlements_validator(
            entitlements,
            passkey_policy="required",
        )
        if entitlement_result.returncode != 0:
            raise SystemExit(
                f"valid signed entitlement was rejected: {entitlement_result.stderr}"
            )
        expect_failure(
            run_entitlements_validator(
                entitlements,
                passkey_policy="forbidden",
            ),
            "baseline signed app must not contain",
        )

        with entitlements.open("wb") as stream:
            plistlib.dump(
                {
                    audio_input_key: True,
                    passkey_key: False,
                },
                stream,
            )
        expect_failure(
            run_entitlements_validator(
                entitlements,
                passkey_policy="required",
            ),
            "signed app is missing the approved Web Browser Public Key Credential entitlement",
        )
        expect_failure(
            run_entitlements_validator(
                entitlements,
                passkey_policy="forbidden",
            ),
            "baseline signed app must not contain",
        )

        with entitlements.open("wb") as stream:
            plistlib.dump(
                {
                    audio_input_key: True,
                    "com.apple.security.cs.disable-library-validation": True,
                },
                stream,
            )
        baseline_result = run_entitlements_validator(
            entitlements,
            passkey_policy="forbidden",
        )
        if baseline_result.returncode != 0:
            raise SystemExit(
                "baseline signed app with audio input and without a Passkey entitlement "
                "was rejected: "
                f"{baseline_result.stderr}"
            )

        with entitlements.open("wb") as stream:
            plistlib.dump(
                {"com.apple.security.cs.disable-library-validation": True},
                stream,
            )
        expect_failure(
            run_entitlements_validator(
                entitlements,
                passkey_policy="forbidden",
            ),
            audio_input_key,
        )

        with entitlements.open("wb") as stream:
            plistlib.dump({audio_input_key: False}, stream)
        expect_failure(
            run_entitlements_validator(
                entitlements,
                passkey_policy="forbidden",
            ),
            audio_input_key,
        )

        with entitlements.open("wb") as stream:
            plistlib.dump(
                {
                    audio_input_key: True,
                    camera_key: True,
                },
                stream,
            )
        expect_failure(
            run_entitlements_validator(
                entitlements,
                passkey_policy="forbidden",
            ),
            camera_key,
        )

        entitlements.write_bytes(b"")
        expect_failure(
            run_entitlements_validator(
                entitlements,
                passkey_policy="forbidden",
            ),
            audio_input_key,
        )
        expect_failure(
            run_entitlements_validator(
                entitlements,
                passkey_policy="required",
            ),
            audio_input_key,
        )

        signing_mode_result = run_signing_mode_validator()
        if signing_mode_result.returncode != 0 or signing_mode_result.stdout.strip() != "baseline":
            raise SystemExit(
                "empty optional signing inputs did not select the baseline mode: "
                f"stdout={signing_mode_result.stdout!r}, stderr={signing_mode_result.stderr!r}"
            )

        architecture_result = run_architecture_validator("x86_64 arm64\n")
        if architecture_result.returncode != 0:
            raise SystemExit(
                f"valid Universal 2 architecture set was rejected: {architecture_result.stderr}"
            )
        native_architecture_result = run_architecture_validator(
            "arm64\n",
            required=("arm64",),
        )
        if native_architecture_result.returncode != 0:
            raise SystemExit(
                "valid native architecture set was rejected: "
                f"{native_architecture_result.stderr}"
            )
        expect_failure(
            run_architecture_validator("arm64\n"),
            "expected exactly ['arm64', 'x86_64']",
        )
        expect_failure(
            run_architecture_validator("arm64 x86_64 arm64\n"),
            "contains duplicates",
        )
        expect_failure(
            run_architecture_validator("arm64 x86_64 arm64e\n"),
            "architectures are",
        )
        expect_failure(
            run_architecture_validator(""),
            "architecture list was empty",
        )

        profile = root / "DeveloperID.provisionprofile.plist"
        write_profile(profile)
        generated_entitlements = root / "generated-signing-entitlements.plist"
        profile_result = run_profile_validator(
            profile,
            write_signing_entitlements=generated_entitlements,
        )
        if profile_result.returncode != 0:
            raise SystemExit(
                f"valid Developer ID profile was rejected: {profile_result.stderr}"
            )
        with generated_entitlements.open("rb") as stream:
            generated = plistlib.load(stream)
        expected_generated = {
            "com.apple.application-identifier": (
                "ZYXWV98765.com.calvinkai.cornerfloat"
            ),
            "com.apple.developer.team-identifier": "ABCDE12345",
            "com.apple.developer.web-browser.public-key-credential": True,
            "com.apple.security.device.audio-input": True,
        }
        if generated != expected_generated:
            raise SystemExit(
                f"profile-derived signing entitlements are wrong: {generated!r}"
            )
        passkey_mode_result = run_signing_mode_validator(
            profile=profile,
            entitlements=generated_entitlements,
        )
        if (
            passkey_mode_result.returncode != 0
            or passkey_mode_result.stdout.strip() != "passkey"
        ):
            raise SystemExit(
                "complete profile/entitlements inputs did not select Passkey mode: "
                f"stdout={passkey_mode_result.stdout!r}, "
                f"stderr={passkey_mode_result.stderr!r}"
            )
        expect_failure(
            run_signing_mode_validator(profile=profile),
            "must be provided together",
        )
        expect_failure(
            run_signing_mode_validator(entitlements=generated_entitlements),
            "must be provided together",
        )
        missing_profile = root / "missing.provisionprofile"
        expect_failure(
            run_signing_mode_validator(
                profile=missing_profile,
                entitlements=generated_entitlements,
            ),
            "does not exist or is not a regular file",
        )
        empty_entitlements = root / "empty-entitlements.plist"
        empty_entitlements.write_bytes(b"")
        expect_failure(
            run_signing_mode_validator(
                profile=profile,
                entitlements=empty_entitlements,
            ),
            "signing entitlements is empty",
        )
        signed_profile_result = run_profile_validator(
            profile,
            signed_entitlements=generated_entitlements,
        )
        if signed_profile_result.returncode != 0:
            raise SystemExit(
                "valid profile-derived signed entitlements were rejected: "
                f"{signed_profile_result.stderr}"
            )

        signing_certificate = root / "signing-certificate.der"
        signing_certificate.write_bytes(b"certificate-der")
        matching_certificate_result = run_profile_validator(
            profile,
            signing_certificate=signing_certificate,
        )
        if matching_certificate_result.returncode != 0:
            raise SystemExit(
                "profile rejected its authorized signing certificate: "
                f"{matching_certificate_result.stderr}"
            )
        signing_certificate.write_bytes(b"different-certificate")
        expect_failure(
            run_profile_validator(
                profile,
                signing_certificate=signing_certificate,
            ),
            "does not include the certificate that signed the app",
        )

        with generated_entitlements.open("wb") as stream:
            plistlib.dump(
                {
                    **expected_generated,
                    "com.apple.application-identifier": (
                        "ZYXWV98765.com.example.wrong"
                    ),
                },
                stream,
            )
        expect_failure(
            run_profile_validator(
                profile,
                signed_entitlements=generated_entitlements,
            ),
            "signed app entitlement com.apple.application-identifier",
        )

        write_profile(profile, expires_in_days=-1)
        expect_failure(run_profile_validator(profile), "provisioning profile expired")

        write_profile(profile, expires_in_days=1)
        expect_failure(
            run_profile_validator(profile),
            "provisioning profile expires in less than 30 days",
        )

        write_profile(profile, team_id="ZZZZZ99999")
        expect_failure(
            run_profile_validator(profile),
            "provisioning profile TeamIdentifier",
        )

        write_profile(profile, passkey=False)
        expect_failure(
            run_profile_validator(profile),
            "does not authorize the managed Web Browser Public Key Credential entitlement",
        )

        write_profile(
            profile,
            application_identifier="ZYXWV98765.com.calvinkai.*",
        )
        expect_failure(
            run_profile_validator(profile),
            "com.apple.application-identifier",
        )

        write_profile(profile, all_devices=False)
        expect_failure(
            run_profile_validator(profile),
            "not a Developer ID all-device distribution profile",
        )

        write_profile(profile, provisioned_devices=["TEST-DEVICE"])
        expect_failure(
            run_profile_validator(profile),
            "device-limited, not a Developer ID distribution profile",
        )

    print(
        "CornerFloat release-validator tests OK: versions and metadata are "
        "release-ready, architecture sets are exact, the local-test URL exception "
        "is loopback-only, every signature requires audio input, baseline signatures "
        "forbid Passkey entitlements, and enhanced signatures require a matching "
        "Developer ID profile/entitlements pair"
    )


if __name__ == "__main__":
    main()
