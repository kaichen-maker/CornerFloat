#!/usr/bin/env python3
"""Validate release identity and the generated Sparkle appcast."""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import plistlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import quote, urlsplit


SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
VERSION_ATTRIBUTE = f"{{{SPARKLE_NS}}}version"
SIGNATURE_ATTRIBUTE = f"{{{SPARKLE_NS}}}edSignature"
SHORT_VERSION_ATTRIBUTE = f"{{{SPARKLE_NS}}}shortVersionString"
DEVELOPER_ID_PATTERN = re.compile(
    r"Developer ID Application: [^\"\r\n]+ \(([A-Z0-9]{10})\)"
)
PASSKEY_ENTITLEMENT = "com.apple.developer.web-browser.public-key-credential"
MAC_APPLICATION_IDENTIFIER = "com.apple.application-identifier"
TEAM_IDENTIFIER_ENTITLEMENT = "com.apple.developer.team-identifier"
MINIMUM_PROFILE_VALIDITY = dt.timedelta(days=30)


def fail(message: str) -> None:
    raise SystemExit(f"Release validation failed: {message}")


def developer_team_id(identity: str) -> str:
    match = DEVELOPER_ID_PATTERN.fullmatch(identity)
    if not match:
        fail(
            "signing identity must exactly match "
            "'Developer ID Application: Name (TEAMID)'"
        )
    return match.group(1)


def validate_https_url(value: str, label: str, *, prefix: bool = False) -> None:
    if any(character.isspace() for character in value):
        fail(f"{label} contains whitespace")
    try:
        parsed = urlsplit(value)
        _ = parsed.port
    except ValueError as error:
        fail(f"{label} is not a valid URL: {error}")
    if parsed.scheme != "https" or not parsed.hostname:
        fail(f"{label} must be an absolute HTTPS URL")
    if parsed.username is not None or parsed.password is not None:
        fail(f"{label} must not contain credentials")
    if parsed.fragment:
        fail(f"{label} must not contain a fragment")
    if prefix and (parsed.query or value.endswith("/..") or value.endswith("/.")):
        fail(f"{label} must be a stable HTTPS directory URL without a query")


def validate_local_test_url(value: str, label: str, *, prefix: bool = False) -> None:
    """Accept only an explicit, ephemeral loopback HTTP endpoint for local E2E tests."""
    if any(character.isspace() for character in value):
        fail(f"{label} contains whitespace")
    try:
        parsed = urlsplit(value)
        port = parsed.port
    except ValueError as error:
        fail(f"{label} is not a valid URL: {error}")
    if (
        parsed.scheme != "http"
        or parsed.hostname not in {"127.0.0.1", "::1", "localhost"}
        or port is None
    ):
        fail(f"{label} must be an HTTP loopback URL with an explicit port for a local test")
    if parsed.username is not None or parsed.password is not None:
        fail(f"{label} must not contain credentials")
    if parsed.fragment:
        fail(f"{label} must not contain a fragment")
    if prefix and (parsed.query or value.endswith("/..") or value.endswith("/.")):
        fail(f"{label} must be a stable loopback directory URL without a query")


def parse_published_releases(appcast: Path) -> list[tuple[int, tuple[int, int, int]]]:
    try:
        root = ET.parse(appcast).getroot()
    except (ET.ParseError, OSError) as error:
        fail(f"cannot read appcast {appcast}: {error}")
    if root.tag != "rss":
        fail(f"previous appcast {appcast} does not have an rss root")
    items = root.findall("./channel/item")
    if not items:
        fail(f"previous appcast {appcast} has no update enclosures")
    releases: list[tuple[int, tuple[int, int, int]]] = []
    for item in items:
        enclosure = item.find("enclosure")
        if enclosure is None:
            fail(f"previous appcast {appcast} contains an item without an enclosure")
        version_element = item.find(f"{{{SPARKLE_NS}}}version")
        value = (
            version_element.text.strip()
            if version_element is not None and version_element.text
            else enclosure.get(VERSION_ATTRIBUTE)
        )
        if not value or not re.fullmatch(r"[1-9][0-9]*", value):
            fail(f"previous appcast contains an invalid build number: {value!r}")
        short_version_element = item.find(f"{{{SPARKLE_NS}}}shortVersionString")
        short_version = (
            short_version_element.text.strip()
            if short_version_element is not None and short_version_element.text
            else enclosure.get(SHORT_VERSION_ATTRIBUTE)
        )
        if not short_version or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", short_version):
            fail(f"previous appcast contains an invalid marketing version: {short_version!r}")
        releases.append((int(value), tuple(map(int, short_version.split(".")))))
    return releases


def validate_version(args: argparse.Namespace) -> None:
    try:
        with args.info_plist.open("rb") as stream:
            info = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        fail(f"cannot read Info.plist {args.info_plist}: {error}")
    version = str(info.get("CFBundleShortVersionString", ""))
    build = str(info.get("CFBundleVersion", ""))
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        fail(f"CFBundleShortVersionString is not strict SemVer: {version!r}")
    if not re.fullmatch(r"[1-9][0-9]*", build):
        fail(f"CFBundleVersion must be a positive integer: {build!r}")
    expected_tag = f"v{version}"
    if args.tag != expected_tag:
        fail(f"tag {args.tag!r} does not match {expected_tag!r}")
    if args.previous_appcast:
        if not args.previous_appcast.is_file():
            fail(f"previous appcast does not exist: {args.previous_appcast}")
        prior_releases = parse_published_releases(args.previous_appcast)
        prior_builds = [published_build for published_build, _ in prior_releases]
        if prior_builds and int(build) <= max(prior_builds):
            fail(f"build {build} is not newer than published build {max(prior_builds)}")
        prior_marketing_versions = [published_version for _, published_version in prior_releases]
        current_marketing_version = tuple(map(int, version.split(".")))
        if prior_marketing_versions and current_marketing_version < max(prior_marketing_versions):
            previous = ".".join(map(str, max(prior_marketing_versions)))
            fail(f"marketing version {version} is older than published version {previous}")
    print(f"Release identity OK: {expected_tag}, build {build}")


def validate_release_metadata(args: argparse.Namespace) -> None:
    try:
        with args.info_plist.open("rb") as stream:
            info = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        fail(f"cannot read Info.plist {args.info_plist}: {error}")
    version = str(info.get("CFBundleShortVersionString", ""))
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        fail(f"CFBundleShortVersionString is not strict SemVer: {version!r}")
    expected_tag = f"v{version}"
    if args.tag != expected_tag:
        fail(f"tag {args.tag!r} does not match {expected_tag!r}")

    try:
        release_notes = args.release_notes.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        fail(f"cannot read release notes {args.release_notes}: {error}")
    first_line = next(
        (line.strip() for line in release_notes.splitlines() if line.strip()),
        "",
    )
    expected_title = f"# CornerFloat {version}"
    if first_line != expected_title:
        fail(
            f"release notes must start with {expected_title!r}, found {first_line!r}"
        )
    preview_phrases = (
        "source preview",
        "draft notes",
        "no github tag",
        "no formal release",
        "has not been published",
    )
    lowered_notes = release_notes.casefold()
    for phrase in preview_phrases:
        if phrase in lowered_notes:
            fail(f"release notes still contain preview-only wording: {phrase!r}")

    try:
        changelog = args.changelog.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        fail(f"cannot read changelog {args.changelog}: {error}")
    heading_pattern = re.compile(
        rf"^## \[{re.escape(version)}\] - (\d{{4}}-\d{{2}}-\d{{2}})$",
        flags=re.MULTILINE,
    )
    matches = heading_pattern.findall(changelog)
    if len(matches) != 1:
        fail(
            f"changelog must contain exactly one dated [{version}] section, "
            f"found {len(matches)}"
        )
    try:
        release_date = dt.date.fromisoformat(matches[0])
    except ValueError:
        fail(f"changelog release date is invalid: {matches[0]!r}")
    if release_date > dt.date.today():
        fail(f"changelog release date {release_date.isoformat()} is in the future")
    version_heading = f"## [{version}] - {release_date.isoformat()}"
    unreleased_heading = "## [Unreleased]"
    if changelog.find(unreleased_heading) < 0:
        fail("changelog is missing an [Unreleased] section for the next cycle")
    if changelog.find(unreleased_heading) > changelog.find(version_heading):
        fail("changelog [Unreleased] section must precede the release section")
    print(
        f"Release metadata OK: {args.tag}, notes and changelog dated "
        f"{release_date.isoformat()}"
    )


def validate_appcast(args: argparse.Namespace) -> None:
    url_validator = validate_local_test_url if args.allow_local_test_url else validate_https_url
    prefix_label = (
        "local test update download prefix"
        if args.allow_local_test_url
        else "public update download prefix"
    )
    url_validator(args.download_prefix, prefix_label, prefix=True)
    if not re.fullmatch(r"[1-9][0-9]*", args.build):
        fail(f"build must be a positive integer: {args.build!r}")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.short_version):
        fail(f"short version is not strict SemVer: {args.short_version!r}")
    if not args.archive.is_file():
        fail(f"archive does not exist or is not a regular file: {args.archive}")
    if args.archive.suffix.lower() != ".zip":
        fail(f"update archive must be a zip file: {args.archive.name}")
    if args.archive.stat().st_size <= 0:
        fail("update archive is empty")
    try:
        root = ET.parse(args.appcast).getroot()
    except (ET.ParseError, OSError) as error:
        fail(f"cannot read appcast {args.appcast}: {error}")
    if root.tag != "rss":
        fail("appcast does not have an rss root")
    matching: list[tuple[ET.Element, ET.Element]] = []
    for item in root.findall("./channel/item"):
        enclosure = item.find("enclosure")
        if enclosure is None:
            fail("appcast contains an item without an enclosure")
        version_element = item.find(f"{{{SPARKLE_NS}}}version")
        version_value = (
            version_element.text.strip()
            if version_element is not None and version_element.text
            else enclosure.get(VERSION_ATTRIBUTE)
        )
        if version_value == args.build:
            matching.append((item, enclosure))
    if len(matching) != 1:
        fail(f"expected exactly one enclosure for build {args.build}, found {len(matching)}")
    item, enclosure = matching[0]
    expected_url = f"{args.download_prefix.rstrip('/')}/{quote(args.archive.name)}"
    download_url = enclosure.get("url", "")
    url_validator(download_url, "appcast enclosure URL")
    if download_url != expected_url:
        fail(f"download URL is {download_url!r}, expected {expected_url!r}")
    short_version_element = item.find(f"{{{SPARKLE_NS}}}shortVersionString")
    short_version = (
        short_version_element.text.strip()
        if short_version_element is not None and short_version_element.text
        else enclosure.get(SHORT_VERSION_ATTRIBUTE)
    )
    if short_version != args.short_version:
        fail(
            "short version is "
            f"{short_version!r}, expected {args.short_version!r}"
        )
    expected_length = str(args.archive.stat().st_size)
    if enclosure.get("length") != expected_length:
        fail(f"archive length is {enclosure.get('length')!r}, expected {expected_length}")
    signature = enclosure.get(SIGNATURE_ATTRIBUTE, "")
    try:
        signature_bytes = base64.b64decode(signature, validate=True)
    except ValueError:
        fail("sparkle:edSignature is not valid base64")
    if len(signature_bytes) != 64:
        fail(f"sparkle:edSignature is {len(signature_bytes)} bytes, expected 64")
    if args.appcast.stat().st_mtime_ns < args.archive.stat().st_mtime_ns:
        fail("appcast is older than the update archive; it may be a stale artifact")
    if args.print_signature:
        print(signature)
    else:
        print(f"Sparkle appcast OK: build {args.build}, signed archive {args.archive.name}")


def validate_identity(args: argparse.Namespace) -> None:
    print(developer_team_id(args.identity))


def validate_signature(args: argparse.Namespace) -> None:
    expected_team = developer_team_id(args.identity)
    signature_info = sys.stdin.read()
    if not signature_info.strip():
        fail("codesign signature information was empty")
    authorities = re.findall(r"^Authority=(.+)$", signature_info, flags=re.MULTILINE)
    if args.identity not in authorities:
        fail("code signature leaf authority does not exactly match the requested identity")
    team_ids = re.findall(r"^TeamIdentifier=([^\r\n]+)$", signature_info, flags=re.MULTILINE)
    if team_ids != [expected_team]:
        fail(f"TeamIdentifier is {team_ids!r}, expected [{expected_team!r}]")
    if args.require_runtime:
        flag_lines = re.findall(r"\bflags=([^\r\n]+)", signature_info)
        if not any(re.search(r"(?:^|[,(])runtime(?:[),]|$)", value) for value in flag_lines):
            fail("Hardened Runtime flag is missing")
    print(f"Code signature OK: {args.identity}, team {expected_team}")


def validate_entitlements(args: argparse.Namespace) -> None:
    try:
        is_empty = args.entitlements_plist.stat().st_size == 0
    except OSError as error:
        fail(f"cannot read signed entitlements {args.entitlements_plist}: {error}")
    if is_empty:
        entitlements: object = {}
    else:
        try:
            with args.entitlements_plist.open("rb") as stream:
                entitlements = plistlib.load(stream)
        except (OSError, plistlib.InvalidFileException) as error:
            fail(f"cannot read signed entitlements {args.entitlements_plist}: {error}")
    if not isinstance(entitlements, dict):
        fail("signed entitlements must be a property-list dictionary")
    if args.passkey_policy == "required":
        if entitlements.get(PASSKEY_ENTITLEMENT) is not True:
            fail(
                "signed app is missing the approved Web Browser Public Key "
                f"Credential entitlement {PASSKEY_ENTITLEMENT!r}"
            )
        print(f"Signed entitlement OK: {PASSKEY_ENTITLEMENT}=true")
        return
    if PASSKEY_ENTITLEMENT in entitlements:
        fail(
            "baseline signed app must not contain the Web Browser Public Key "
            f"Credential entitlement {PASSKEY_ENTITLEMENT!r}"
        )
    print("Baseline signed entitlements OK: no managed Passkey entitlement")


def validate_signing_mode(args: argparse.Namespace) -> None:
    profile = args.provisioning_profile
    entitlements = args.signing_entitlements
    if (profile is None) != (entitlements is None):
        fail(
            "Developer ID provisioning profile and signing entitlements must be "
            "provided together for a Passkey-enabled release"
        )
    if profile is None:
        print("baseline")
        return
    for label, path in (
        ("Developer ID provisioning profile", profile),
        ("signing entitlements", entitlements),
    ):
        if path is None or not path.is_file():
            fail(f"{label} does not exist or is not a regular file: {path}")
        if path.stat().st_size <= 0:
            fail(f"{label} is empty: {path}")
    print("passkey")


def validate_architecture_set(args: argparse.Namespace) -> None:
    architectures = sys.stdin.read().split()
    if not architectures:
        fail(f"{args.label} architecture list was empty")
    if len(architectures) != len(set(architectures)):
        fail(f"{args.label} architecture list contains duplicates: {architectures!r}")
    required = args.required_architecture
    if len(required) != len(set(required)):
        fail(f"required architecture list contains duplicates: {required!r}")
    actual_set = set(architectures)
    required_set = set(required)
    if actual_set != required_set:
        fail(
            f"{args.label} architectures are {sorted(actual_set)!r}, "
            f"expected exactly {sorted(required_set)!r}"
        )
    print(f"Architecture set OK: {args.label} ({', '.join(sorted(actual_set))})")


def validate_provisioning_profile(args: argparse.Namespace) -> None:
    if not re.fullmatch(r"[A-Z0-9]{10}", args.team_id):
        fail(f"team ID is not a 10-character Apple Team ID: {args.team_id!r}")
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", args.bundle_id):
        fail(f"bundle ID is not a valid reverse-DNS identifier: {args.bundle_id!r}")
    try:
        with args.profile_plist.open("rb") as stream:
            profile = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException) as error:
        fail(f"cannot read decoded provisioning profile {args.profile_plist}: {error}")
    if not isinstance(profile, dict):
        fail("decoded provisioning profile must be a property-list dictionary")

    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, dt.datetime):
        fail("provisioning profile ExpirationDate is missing or is not a date")
    if expiration.tzinfo is None:
        expiration_utc = expiration.replace(tzinfo=dt.timezone.utc)
    else:
        expiration_utc = expiration.astimezone(dt.timezone.utc)
    now_utc = dt.datetime.now(dt.timezone.utc)
    if expiration_utc <= now_utc:
        fail(f"provisioning profile expired at {expiration_utc.isoformat()}")
    if expiration_utc - now_utc < MINIMUM_PROFILE_VALIDITY:
        fail("provisioning profile expires in less than 30 days")

    team_identifiers = profile.get("TeamIdentifier")
    if team_identifiers != [args.team_id]:
        fail(
            f"provisioning profile TeamIdentifier is {team_identifiers!r}, "
            f"expected [{args.team_id!r}]"
        )
    if profile.get("ProvisionsAllDevices") is not True:
        fail("provisioning profile is not a Developer ID all-device distribution profile")
    if "ProvisionedDevices" in profile:
        fail("provisioning profile is device-limited, not a Developer ID distribution profile")

    developer_certificates = profile.get("DeveloperCertificates")
    if (
        not isinstance(developer_certificates, list)
        or not developer_certificates
        or any(
            not isinstance(certificate, bytes) or not certificate
            for certificate in developer_certificates
        )
    ):
        fail("provisioning profile contains no valid DeveloperCertificates")
    if args.signing_certificate_der:
        try:
            signing_certificate = args.signing_certificate_der.read_bytes()
        except OSError as error:
            fail(
                f"cannot read signing certificate {args.signing_certificate_der}: {error}"
            )
        if not signing_certificate:
            fail("extracted signing certificate is empty")
        if signing_certificate not in developer_certificates:
            fail("provisioning profile does not include the certificate that signed the app")

    prefixes = profile.get("ApplicationIdentifierPrefix")
    if not isinstance(prefixes, list) or not prefixes or any(
        not isinstance(prefix, str) or not prefix for prefix in prefixes
    ):
        fail(
            "provisioning profile ApplicationIdentifierPrefix must contain "
            "one or more non-empty prefixes"
        )
    if len(set(prefixes)) != len(prefixes):
        fail("provisioning profile ApplicationIdentifierPrefix contains duplicates")

    entitlements = profile.get("Entitlements")
    if not isinstance(entitlements, dict):
        fail("provisioning profile Entitlements is missing or is not a dictionary")
    application_identifier = entitlements.get(MAC_APPLICATION_IDENTIFIER)
    bundle_suffix = f".{args.bundle_id}"
    if not isinstance(application_identifier, str) or not application_identifier.endswith(
        bundle_suffix
    ):
        fail(
            f"provisioning profile {MAC_APPLICATION_IDENTIFIER} is "
            f"{application_identifier!r}, expected an explicit App ID for {args.bundle_id!r}"
        )
    application_prefix = application_identifier[: -len(bundle_suffix)]
    if not application_prefix or application_prefix not in prefixes:
        fail(
            f"provisioning profile {MAC_APPLICATION_IDENTIFIER} prefix "
            f"{application_prefix!r} is not authorized by ApplicationIdentifierPrefix"
        )
    expected_application_identifier = application_identifier
    profile_team = entitlements.get(TEAM_IDENTIFIER_ENTITLEMENT)
    if profile_team != args.team_id:
        fail(
            f"provisioning profile {TEAM_IDENTIFIER_ENTITLEMENT} is "
            f"{profile_team!r}, expected {args.team_id!r}"
        )
    if entitlements.get(PASSKEY_ENTITLEMENT) is not True:
        fail(
            "provisioning profile does not authorize the managed Web Browser "
            f"Public Key Credential entitlement {PASSKEY_ENTITLEMENT!r}"
        )
    required_signed_entitlements = {
        MAC_APPLICATION_IDENTIFIER: expected_application_identifier,
        TEAM_IDENTIFIER_ENTITLEMENT: args.team_id,
        PASSKEY_ENTITLEMENT: True,
    }
    if args.signed_entitlements_plist:
        try:
            with args.signed_entitlements_plist.open("rb") as stream:
                signed_entitlements = plistlib.load(stream)
        except (OSError, plistlib.InvalidFileException) as error:
            fail(
                "cannot read signed app entitlements "
                f"{args.signed_entitlements_plist}: {error}"
            )
        if not isinstance(signed_entitlements, dict):
            fail("signed app entitlements must be a property-list dictionary")
        for key, expected_value in required_signed_entitlements.items():
            actual_value = signed_entitlements.get(key)
            if actual_value != expected_value:
                fail(
                    f"signed app entitlement {key} is {actual_value!r}, "
                    f"expected {expected_value!r} from the provisioning profile"
                )
    if args.write_signing_entitlements:
        try:
            with args.write_signing_entitlements.open("wb") as stream:
                plistlib.dump(required_signed_entitlements, stream, sort_keys=True)
        except OSError as error:
            fail(
                "cannot write generated signing entitlements "
                f"{args.write_signing_entitlements}: {error}"
            )
    print(
        "Developer ID provisioning profile OK: "
        f"{args.bundle_id}, team {args.team_id}, expires {expiration_utc.date().isoformat()}"
    )


def validate_url(args: argparse.Namespace) -> None:
    validate_https_url(args.url, args.label, prefix=args.prefix)
    print(f"HTTPS URL OK: {args.url}")


def validate_local_url(args: argparse.Namespace) -> None:
    validate_local_test_url(args.url, args.label, prefix=args.prefix)
    print(f"Loopback test URL OK: {args.url}")


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    version_parser = subparsers.add_parser("version")
    version_parser.add_argument("--info-plist", type=Path, required=True)
    version_parser.add_argument("--tag", required=True)
    version_parser.add_argument("--previous-appcast", type=Path)
    version_parser.set_defaults(handler=validate_version)

    metadata_parser = subparsers.add_parser("release-metadata")
    metadata_parser.add_argument("--info-plist", type=Path, required=True)
    metadata_parser.add_argument("--tag", required=True)
    metadata_parser.add_argument("--release-notes", type=Path, required=True)
    metadata_parser.add_argument("--changelog", type=Path, required=True)
    metadata_parser.set_defaults(handler=validate_release_metadata)

    appcast_parser = subparsers.add_parser("appcast")
    appcast_parser.add_argument("--appcast", type=Path, required=True)
    appcast_parser.add_argument("--archive", type=Path, required=True)
    appcast_parser.add_argument("--build", required=True)
    appcast_parser.add_argument("--short-version", required=True)
    appcast_parser.add_argument("--download-prefix", required=True)
    appcast_parser.add_argument("--print-signature", action="store_true")
    appcast_parser.add_argument(
        "--allow-local-test-url",
        action="store_true",
        help="accept only loopback HTTP enclosure URLs with an explicit port",
    )
    appcast_parser.set_defaults(handler=validate_appcast)

    identity_parser = subparsers.add_parser("identity")
    identity_parser.add_argument("--identity", required=True)
    identity_parser.set_defaults(handler=validate_identity)

    signature_parser = subparsers.add_parser("signature")
    signature_parser.add_argument("--identity", required=True)
    signature_parser.add_argument("--require-runtime", action="store_true")
    signature_parser.set_defaults(handler=validate_signature)

    entitlements_parser = subparsers.add_parser("entitlements")
    entitlements_parser.add_argument("--entitlements-plist", type=Path, required=True)
    entitlements_parser.add_argument(
        "--passkey-policy",
        choices=("required", "forbidden"),
        required=True,
    )
    entitlements_parser.set_defaults(handler=validate_entitlements)

    signing_mode_parser = subparsers.add_parser("signing-mode")
    signing_mode_parser.add_argument("--provisioning-profile", type=Path)
    signing_mode_parser.add_argument("--signing-entitlements", type=Path)
    signing_mode_parser.set_defaults(handler=validate_signing_mode)

    architecture_parser = subparsers.add_parser("architecture-set")
    architecture_parser.add_argument("--label", default="binary")
    architecture_parser.add_argument(
        "--required-architecture",
        choices=("arm64", "x86_64"),
        action="append",
        required=True,
    )
    architecture_parser.set_defaults(handler=validate_architecture_set)

    profile_parser = subparsers.add_parser("profile")
    profile_parser.add_argument("--profile-plist", type=Path, required=True)
    profile_parser.add_argument("--bundle-id", required=True)
    profile_parser.add_argument("--team-id", required=True)
    profile_parser.add_argument("--signed-entitlements-plist", type=Path)
    profile_parser.add_argument("--signing-certificate-der", type=Path)
    profile_parser.add_argument("--write-signing-entitlements", type=Path)
    profile_parser.set_defaults(handler=validate_provisioning_profile)

    url_parser = subparsers.add_parser("https-url")
    url_parser.add_argument("--url", required=True)
    url_parser.add_argument("--label", default="URL")
    url_parser.add_argument("--prefix", action="store_true")
    url_parser.set_defaults(handler=validate_url)

    local_url_parser = subparsers.add_parser("local-test-url")
    local_url_parser.add_argument("--url", required=True)
    local_url_parser.add_argument("--label", default="local test URL")
    local_url_parser.add_argument("--prefix", action="store_true")
    local_url_parser.set_defaults(handler=validate_local_url)

    args = parser.parse_args()
    args.handler(args)


if __name__ == "__main__":
    main()
