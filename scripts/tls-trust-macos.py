#!/usr/bin/env python3
"""Distrust four removed roots in macOS's native PEM bundle and System keychain.

Run as root through nix-darwin activation. --check is read-only. Alternate
--bundle and --security paths allow non-destructive tests with a command stub.
"""

import argparse
import hashlib
import os
from pathlib import Path
import re
import ssl
import stat
import subprocess
import sys
import tempfile


DEFAULT_BUNDLE = Path("/etc/ssl/cert.pem")
DEFAULT_SECURITY = "/usr/bin/security"
DEFAULT_ROOTS = Path(__file__).resolve().parents[1] / "common/system-darwin/tls-distrust-roots.pem"
KEYCHAIN = "/Library/Keychains/System.keychain"
BACKUP_SUFFIX = ".before-emudhra-20261020"
BLOCKED = {
    "d7a7a0fb5d7e2731d771e9484ebcdef71d5f0c3e0a2948782bc83ee0ea699ef4": "Comodo AAA Services root",
    "86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b": "emSign ECC Root CA - G3",
    "125609aa301da0a249b97a8239cb6a34216f44dcac9f3954b14292f2e8c8608f": "emSign Root CA - C1",
    "bc4d809b15189d78db3e1d8cf4f9726a795da1643ca5f1358e1ddb0edc0d7eb3": "emSign ECC Root CA - C3",
}
PEM = re.compile(br"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", re.DOTALL)


def read_regular(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as stream:
        metadata = os.fstat(stream.fileno())
        if not stat.S_ISREG(metadata.st_mode):
            raise ValueError(f"Expected a regular file: {path}")
        return stream.read(), metadata


def certificates(content):
    matches = list(PEM.finditer(content))
    if not matches:
        raise ValueError("CA bundle contains no certificates")
    if (content.count(b"-----BEGIN CERTIFICATE-----") != len(matches)
            or content.count(b"-----END CERTIFICATE-----") != len(matches)):
        raise ValueError("CA bundle contains an incomplete PEM certificate")
    result = []
    for match in matches:
        der = ssl.PEM_cert_to_DER_cert(match.group().decode("ascii"))
        result.append((match, hashlib.sha256(der).hexdigest()))
    return result


def preserve_metadata(descriptor, metadata):
    current = os.fstat(descriptor)
    if (current.st_uid, current.st_gid) != (metadata.st_uid, metadata.st_gid):
        os.fchown(descriptor, metadata.st_uid, metadata.st_gid)
    os.fchmod(descriptor, stat.S_IMODE(metadata.st_mode))


def backup_once(path, content, metadata):
    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    except FileExistsError:
        return read_regular(path)[0]
    try:
        with os.fdopen(descriptor, "wb") as stream:
            stream.write(content)
            stream.flush()
            preserve_metadata(stream.fileno(), metadata)
            os.fsync(stream.fileno())
    except BaseException:
        path.unlink()
        raise
    return content


def signature(metadata):
    return (metadata.st_dev, metadata.st_ino, metadata.st_size, metadata.st_mtime_ns,
            metadata.st_ctime_ns)


def apply(bundle, security, check=False, roots=DEFAULT_ROOTS):
    content, metadata = read_regular(bundle)
    parsed = certificates(content)
    present = {fingerprint for _, fingerprint in parsed if fingerprint in BLOCKED}
    if check:
        for fingerprint in sorted(present):
            print(f"Blocked root remains: {BLOCKED[fingerprint]} ({fingerprint})")
        if not present:
            print("Native PEM bundle excludes all four blocked root fingerprints.")
        return 1 if present else 0

    if (bundle.absolute() == DEFAULT_BUNDLE or security == DEFAULT_SECURITY) and os.geteuid() != 0:
        raise PermissionError("Native macOS trust changes require root")
    if bundle.absolute() != DEFAULT_BUNDLE and security == DEFAULT_SECURITY:
        raise ValueError("Alternate bundles require an explicit --security test stub")

    # Authenticate the packaged public PEMs, never relying on current Apple roots.
    public_roots = {}
    for match, fingerprint in certificates(read_regular(roots)[0]):
        if fingerprint not in BLOCKED or fingerprint in public_roots:
            raise ValueError("Distrust root source contains an unexpected or duplicate certificate")
        public_roots[fingerprint] = match.group()
    if set(public_roots) != set(BLOCKED):
        raise ValueError("Distrust root source must contain all four authenticated certificates")

    backup = bundle.with_name(bundle.name + BACKUP_SUFFIX)
    backup_once(backup, content, metadata)

    # Apply explicit administrator distrust before filtering the native bundle.
    with tempfile.TemporaryDirectory(prefix="macos-root-distrust-") as temporary:
        for fingerprint, pem in sorted(public_roots.items()):
            certificate = Path(temporary) / (fingerprint + ".pem")
            certificate.write_bytes(pem + b"\n")
            subprocess.run(
                [security, "add-trusted-cert", "-d", "-r", "deny", "-k", KEYCHAIN,
                 str(certificate)],
                check=True,
                timeout=120,
            )

    filtered = PEM.sub(
        lambda match: b"" if hashlib.sha256(
            ssl.PEM_cert_to_DER_cert(match.group().decode("ascii"))
        ).hexdigest() in BLOCKED else match.group(),
        content,
    )
    if not certificates(filtered):
        raise ValueError("Refusing to write an empty CA bundle")
    if filtered != content:
        descriptor, temporary = tempfile.mkstemp(prefix=".cert.pem-", dir=bundle.parent)
        temporary = Path(temporary)
        try:
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(filtered)
                stream.flush()
                preserve_metadata(stream.fileno(), metadata)
                os.fsync(stream.fileno())
            if signature(bundle.lstat()) != signature(metadata):
                raise ValueError("CA bundle changed during distrust activation; retry")
            os.replace(temporary, bundle)
        finally:
            temporary.unlink(missing_ok=True)

    print(f"Removed {len(present)} native bundle roots; applied {len(public_roots)} System keychain denies.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, default=DEFAULT_BUNDLE)
    parser.add_argument("--security", default=DEFAULT_SECURITY)
    parser.add_argument("--roots", type=Path, default=DEFAULT_ROOTS,
                        help="Public PEMs for all four fingerprint-authenticated distrust roots")
    parser.add_argument("--check", action="store_true", help="Only inspect the PEM bundle")
    arguments = parser.parse_args()
    try:
        return apply(arguments.bundle, arguments.security, arguments.check, arguments.roots)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"macOS trust mitigation failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
