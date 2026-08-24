#!/usr/bin/env python3
"""
RuStore Publishing Automation Script
Handles auth, draft creation, universal APK upload, and moderation submission via RuStore Public API.
"""

import sys
import os
import time
import json
import base64
from datetime import datetime, timezone
import requests
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.serialization import load_pem_private_key

RUSTORE_API_BASE = "https://public-api.rustore.ru"

def get_iso_timestamp():
    now = datetime.now(timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "+00:00"

def generate_signature(key_id: str, timestamp: str, private_key_pem: str) -> str:
    message = f"{key_id}{timestamp}".encode('utf-8')
    pem_bytes = private_key_pem.strip().encode('utf-8')
    
    if not pem_bytes.startswith(b"-----BEGIN"):
        try:
            decoded = base64.b64decode(pem_bytes)
            if b"-----BEGIN" in decoded:
                pem_bytes = decoded
        except Exception:
            pass

    private_key = load_pem_private_key(pem_bytes, password=None)
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
    
    list_url = f"{RUSTORE_API_BASE}/public/v1/application/{package_name}/version?versionStatus=DRAFT"
    try:
        res = requests.get(list_url, headers=headers, timeout=30)
        if res.status_code == 200:
            body = res.json().get("body", {})
            drafts = body.get("content", []) if isinstance(body, dict) else body
            if drafts and len(drafts) > 0:
                version_id = drafts[0].get("versionId") or drafts[0].get("id")
                print(f"Reusing existing draft versionId: {version_id}")
                return int(version_id)
    except Exception as e:
        print(f"Draft check notice: {e}")
            
    create_url = f"{RUSTORE_API_BASE}/public/v1/application/{package_name}/version"
    payload = {
        "publishType": "AUTOMATICALLY",
        "whatsNew": whats_new if whats_new else "Bug fixes and performance improvements."
    }
    
    print(f"Creating new RuStore draft for {package_name}...")
    res = requests.post(create_url, json=payload, headers=headers, timeout=30)
    if res.status_code not in (200, 201):
        print(f"Failed to create version draft: HTTP {res.status_code} - {res.text}")
        sys.exit(1)
        
    data = res.json()
    version_id = data.get("body", {}).get("versionId") or data.get("body") or data.get("versionId")
    print(f"Created version draft with versionId: {version_id}")
    return int(version_id)

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
