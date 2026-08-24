#!/usr/bin/env python3
"""
RuStore Publishing Automation Script
Handles auth, draft creation, universal APK upload, and moderation submission via RuStore Public API.
"""

import sys
import os
import re
import time
import json
import base64
from datetime import datetime, timezone
import requests
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.serialization import load_pem_private_key, load_der_private_key

RUSTORE_API_BASE = "https://public-api.rustore.ru"

def get_iso_timestamp():
    # RuStore requires ISO-8601 with timezone (e.g. 2026-08-24T19:30:00.000+00:00)
    now = datetime.now(timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "+00:00"

def parse_private_key(key_raw: str):
    """
    Robustly parses a private key in ANY format:
    - Multi-line PEM
    - Flattened single-line PEM (from GitHub Secrets)
    - Raw Base64 DER (as exported from RuStore Console)
    - Base64-encoded PEM
    - PKCS#8 or PKCS#1 (RSA)
    """
    raw = key_raw.strip()

    # 1. If it contains BEGIN and END headers (PEM format, possibly flattened with spaces)
    if "-----BEGIN" in raw and "-----END" in raw:
        header_match = re.search(r"-----BEGIN ([A-Z0-9 ]+)-----", raw)
        footer_match = re.search(r"-----END ([A-Z0-9 ]+)-----", raw)
        if header_match and footer_match:
            header = header_match.group(0)
            footer = footer_match.group(0)
            body = raw[raw.find(header) + len(header) : raw.find(footer)]
            body_cleaned = "".join(body.split())
            formatted_body = "\n".join([body_cleaned[i:i+64] for i in range(0, len(body_cleaned), 64)])
            normalized_pem = f"{header}\n{formatted_body}\n{footer}\n".encode('utf-8')
            try:
                return load_pem_private_key(normalized_pem, password=None)
            except Exception:
                pass
            try:
                der_bytes = base64.b64decode(body_cleaned)
                return load_der_private_key(der_bytes, password=None)
            except Exception:
                pass

    # 2. Try directly loading as standard PEM
    try:
        return load_pem_private_key(raw.encode('utf-8'), password=None)
    except Exception:
        pass

    # 3. Clean raw string of all whitespace/quotes
    cleaned = "".join(raw.replace('"', '').replace("'", '').split())

    # Try decoding raw base64 as DER (RuStore direct key export)
    try:
        der_bytes = base64.b64decode(cleaned)
        return load_der_private_key(der_bytes, password=None)
    except Exception:
        pass

    # 4. Wrap raw base64 in standard PEM headers
    formatted_body = "\n".join([cleaned[i:i+64] for i in range(0, len(cleaned), 64)])
    for key_type in ["RSA PRIVATE KEY", "PRIVATE KEY"]:
        pem_str = f"-----BEGIN {key_type}-----\n{formatted_body}\n-----END {key_type}-----\n"
        try:
            return load_pem_private_key(pem_str.encode('utf-8'), password=None)
        except Exception:
            pass

    # 5. Check if the secret was base64 encoded twice
    try:
        decoded_once = base64.b64decode(cleaned).decode('utf-8', errors='ignore')
        if "-----BEGIN" in decoded_once:
            return parse_private_key(decoded_once)
    except Exception:
        pass

    raise ValueError("Could not parse RuStore private key in any known format (PEM, DER, raw base64, or PKCS#8).")

def generate_signature(key_id: str, timestamp: str, private_key_pem: str) -> str:
    message = f"{key_id}{timestamp}".encode('utf-8')
    private_key = parse_private_key(private_key_pem)
    signature = private_key.sign(
        message,
        padding.PKCS1v15(),
        hashes.SHA512()
    )
    return base64.b64encode(signature).decode('utf-8')

def authenticate(key_id: str, private_key_pem: str) -> str:
    timestamp = get_iso_timestamp()
    signature = generate_signature(key_id, timestamp, private_key_pem)
    
    url = f"{RUSTORE_API_BASE}/public/auth/"
    payload = {
        "keyId": key_id,
        "timestamp": timestamp,
        "signature": signature
    }
    
    print(f"Authenticating with RuStore API (Key ID: {key_id[:6]}...)...")
    res = requests.post(url, json=payload, timeout=30)
    if res.status_code != 200:
        print(f"Auth failed: HTTP {res.status_code} - {res.text}")
        sys.exit(1)
        
    data = res.json()
    token = data.get("body", {}).get("jwe") or data.get("jwe")
    if not token:
        print(f"Auth response missing JWE token: {data}")
        sys.exit(1)
        
    print("RuStore authentication successful!")
    return token

def create_or_get_draft_version(token: str, package_name: str, whats_new: str) -> int:
    headers = {"Public-Token": token}
    whats_new_text = whats_new if whats_new else "Bug fixes and performance improvements."
    
    # 1. Query existing versions first to check for DRAFT or active versions
    print(f"Checking existing versions for {package_name}...")
    version_endpoints = [
        f"{RUSTORE_API_BASE}/public/v1/application/{package_name}/version?versionStatuses=DRAFT,MODERATION,REVIEW,READY_FOR_PUBLICATION,ACTIVE,REJECTED_BY_MODERATOR",
        f"{RUSTORE_API_BASE}/public/v1/application/{package_name}/version?versionStatuses=DRAFT",
        f"{RUSTORE_API_BASE}/public/v1/application/{package_name}/version",
    ]
    
    for v_url in version_endpoints:
        try:
            res_list = requests.get(v_url, headers=headers, timeout=30)
            if res_list.status_code == 200:
                ldata = res_list.json().get("body", {})
                items = ldata.get("content", []) if isinstance(ldata, dict) else (ldata if isinstance(ldata, list) else [])
                print(f"Found {len(items)} version(s) in RuStore via {v_url.split('?')[-1]}:")
                for item in items:
                    status = item.get("versionStatus") or item.get("status")
                    vid = item.get("versionId") or item.get("id")
                    ver_name = item.get("versionName") or item.get("version")
                    print(f"  - VersionId: {vid}, Status: {status}, VersionName: {ver_name}")
                    
                    if status == "DRAFT" and vid:
                        print(f"Reusing existing DRAFT (versionId: {vid})...")
                        # Update publish settings / whats_new for existing draft
                        try:
                            settings_url = f"{RUSTORE_API_BASE}/public/v1/application/{package_name}/version/{vid}/publish-settings"
                            requests.post(settings_url, json={"publishType": "INSTANTLY"}, headers=headers, timeout=15)
                        except Exception:
                            pass
                        return int(vid)
                    
                    if status in ("MODERATION", "REVIEW", "TAKEN_FOR_MODERATION") and vid:
                        print(f"Notice: Version {vid} is currently in {status}. RuStore may reject new drafts until moderation completes.")
        except Exception as e:
            print(f"Version query notice: {e}")

    # 2. If no existing draft found, create a new one
    print(f"Creating new RuStore version draft for {package_name}...")
    creation_attempts = [
        (f"{RUSTORE_API_BASE}/public/v1/application/{package_name}/version", {"publishType": "INSTANTLY", "whatsNew": whats_new_text}),
        (f"{RUSTORE_API_BASE}/public/v1/application/{package_name}/version?publishType=INSTANTLY", {"whatsNew": whats_new_text}),
        (f"{RUSTORE_API_BASE}/public/v1/application/{package_name}/version", {"publishType": "MANUAL", "whatsNew": whats_new_text}),
        (f"{RUSTORE_API_BASE}/public/v1/application/{package_name}/version?publishType=MANUAL", {"whatsNew": whats_new_text}),
    ]

    for create_url, payload in creation_attempts:
        res = requests.post(create_url, json=payload, headers=headers, timeout=30)
        if res.status_code in (200, 201):
            data = res.json()
            body = data.get("body")
            if isinstance(body, int):
                version_id = body
            elif isinstance(body, dict):
                version_id = body.get("versionId") or body.get("id")
            else:
                version_id = data.get("versionId")
            print(f"Successfully created version draft with versionId: {version_id}")
            return int(version_id)
        else:
            print(f"Draft creation attempt ({create_url.split('?')[-1]}): HTTP {res.status_code} - {res.text}")

    print(f"Failed to create or obtain RuStore version draft for {package_name}.")
    sys.exit(1)

def upload_apk(token: str, package_name: str, version_id: int, apk_path: str):
    headers = {"Public-Token": token}
    url = f"{RUSTORE_API_BASE}/public/v1/application/{package_name}/version/{version_id}/apk?isMainApk=true&servicesType=Unknown"
    
    file_size_mb = os.path.getsize(apk_path) / (1024 * 1024)
    print(f"Uploading APK ({file_size_mb:.2f} MB): {apk_path} -> versionId {version_id}...")
    
    with open(apk_path, "rb") as f:
        files = {"file": (os.path.basename(apk_path), f, "application/vnd.android.package-archive")}
        res = requests.post(url, headers=headers, files=files, timeout=600)
        
    if res.status_code not in (200, 201):
        print(f"Failed to upload APK: HTTP {res.status_code} - {res.text}")
        sys.exit(1)
        
    print("APK upload completed successfully!")

def commit_version(token: str, package_name: str, version_id: int):
    headers = {"Public-Token": token}
    url = f"{RUSTORE_API_BASE}/public/v1/application/{package_name}/version/{version_id}/commit?priorityUpdate=0"
    
    print(f"Submitting version {version_id} for RuStore moderation...")
    res = requests.post(url, headers=headers, timeout=60)
    if res.status_code not in (200, 201):
        print(f"Failed to submit version for moderation: HTTP {res.status_code} - {res.text}")
        sys.exit(1)
        
    print("Version successfully submitted to RuStore moderation!")

def main():
    key_id = os.environ.get("RUSTORE_KEY_ID")
    private_key = os.environ.get("RUSTORE_PRIVATE_KEY")
    package_name = os.environ.get("RUSTORE_PACKAGE_NAME", "bshv.mangaloader.app")
    apk_path = os.environ.get("RUSTORE_APK_PATH", "apks/mangaloader-android-universal.apk")
    whats_new = os.environ.get("RUSTORE_WHATS_NEW", "")
    
    if not key_id or not private_key:
        print("RuStore API credentials (RUSTORE_KEY_ID / RUSTORE_PRIVATE_KEY) not found. Skipping publish.")
        return 0
        
    if not os.path.exists(apk_path):
        print(f"Error: Target APK not found at {apk_path}")
        sys.exit(1)
        
    token = authenticate(key_id, private_key)
    version_id = create_or_get_draft_version(token, package_name, whats_new)
    upload_apk(token, package_name, version_id, apk_path)
    commit_version(token, package_name, version_id)
    print("All RuStore publication steps completed successfully!")

if __name__ == "__main__":
    main()
