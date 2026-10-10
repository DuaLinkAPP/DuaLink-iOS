# SPDX-License-Identifier: MPL-2.0
"""Read-only source audit. Findings show category/path/line, never secret values."""
from pathlib import Path
from collections import Counter
import json
import re
import sys
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
EXCLUDED_DIRECTORIES = {".git", ".build", ".swiftpm", "xcuserdata", "build", "__pycache__"}
PRIVATE_SUFFIXES = {".p8", ".p12", ".pem", ".key", ".cer", ".mobileprovision", ".ipa", ".log", ".xcuserstate"}
DOCUMENT_HOSTS = {"developer.apple.com", "www.apple.com", "apps.apple.com", "mozilla.org", "www.mozilla.org",
                  "opensource.org", "spdx.org", "www.w3.org"}
WEB_URL = re.compile(r"(?:https?|wss?)://[^\s<>\"\)]+")
NETWORK_CLIENT = re.compile(r"\b(?:URLSession|NSURLConnection|NWConnection|NWListener|CFHTTPMessage|WebSocket|Alamofire|Moya)\b")
PATTERNS = {
    "absolute-home-path": re.compile(r"/(?:Users|home)/[A-Za-z0-9_.-]+/"),
    "email-address": re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"),
    "private-key": re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    "github-token": re.compile(r"(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{40,})"),
    "aws-access-key": re.compile(r"(?:AKIA|ASIA)[A-Z0-9]{16}"),
    "physical-iphone-udid": re.compile(r"\b00008[0-9A-Fa-f]{3}-[0-9A-Fa-f]{16}\b"),
    "literal-mobile-number": re.compile(r"\b1[3-9][0-9]{9}\b"),
    "hardcoded-team": re.compile(r"DEVELOPMENT_TEAM\s*=\s*[\"']?[A-Z0-9]{10}\b"),
    "named-certificate": re.compile(r"(?:Apple Development|Apple Distribution|iPhone Developer|iPhone Distribution):\s*[^\n\";]+"),
    "certificate-fingerprint": re.compile(r"CODE_SIGN_IDENTITY\s*=\s*[\"']?[A-Fa-f0-9]{40}\b"),
    "hardcoded-profile": re.compile(r"PROVISIONING_PROFILE(?:_SPECIFIER)?\s*=\s*[\"']?[A-Za-z0-9][^;\n]*"),
    "personal-author-header": re.compile(r"Created\s+by\s+.+\s+on\s"),
}


def exclusion_reason(path):
    parts = path.relative_to(ROOT).parts
    if ".git" in parts:
        return "git-history"
    if "xcuserdata" in parts or path.name == ".DS_Store":
        return "generated-user-metadata"
    if path.name.startswith(".env") and not path.name.endswith(".example"):
        return "local-environment"
    if path == ROOT / "Config/Local.xcconfig":
        return "local-signing-config"
    if any(part in EXCLUDED_DIRECTORIES or part.startswith("DerivedData") for part in parts):
        return "build-or-tool-cache"
    return None


def source_files():
    for path in sorted(ROOT.rglob("*")):
        if path.is_file() and exclusion_reason(path) is None:
            yield path


def audit():
    findings = []
    files = list(source_files())
    for path in files:
        relative = str(path.relative_to(ROOT))
        if path.is_symlink():
            findings.append({"category": "symbolic-link", "path": relative})
        if path.suffix.lower() in PRIVATE_SUFFIXES:
            findings.append({"category": "private-or-generated-file", "path": relative})
        if "Validation" in path.parts or "Experiments" in path.parts:
            findings.append({"category": "captured-experiment-material", "path": relative})
        if path.suffix.lower() in {".png", ".jpg", ".jpeg"}:
            # Published image provenance/visual contents require a separate review.
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            findings.append({"category": "unexpected-binary", "path": relative})
            continue
        for category, pattern in PATTERNS.items():
            for match in pattern.finditer(text):
                findings.append({"category": category, "path": relative,
                                 "line": text.count("\n", 0, match.start()) + 1})
        for match in WEB_URL.finditer(text):
            # Documentation/license URLs and Apple's plist DTD are references,
            # not executable network endpoints. Swift runtime URLs are forbidden.
            host = urlsplit(match.group().rstrip(".,;")).hostname
            if path.suffix == ".swift" or host not in DOCUMENT_HOSTS:
                findings.append({"category": "runtime-or-unreviewed-web-url", "path": relative,
                                 "line": text.count("\n", 0, match.start()) + 1})
        if path.suffix == ".swift" and NETWORK_CLIENT.search(text):
            findings.append({"category": "network-client-implementation", "path": relative})
    # Exclusions are reported as counts rather than private paths. A clean
    # public snapshot does not imply every local Xcode/cache file is public-safe.
    exclusions = Counter(exclusion_reason(path) for path in ROOT.rglob("*") if path.is_file())
    exclusions.pop(None, None)
    return {"source_file_count": len(files), "excluded_local_file_counts": dict(exclusions),
            "findings": findings}


if __name__ == "__main__":
    result = audit()
    print(json.dumps(result, ensure_ascii=False, indent=2))
    sys.exit(bool(result["findings"]))
