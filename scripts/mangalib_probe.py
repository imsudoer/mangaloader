#!/usr/bin/env python3
"""Live probe for the MangaLib API used by the app (stdlib only).

The app talks to https://api.cdnlibs.org/api/... while the session cookies are
issued for mangalib.org, so every auth-dependent route has to be verified
against the real server instead of guessed. This script does exactly that: it
replays the app's request headers, with and without the exported cookie jar, and
prints status/redirect/body-head for each candidate route.

Cookie material is never printed -- only names and value lengths.

Usage:
    python scripts/mangalib_probe.py --summary
    python scripts/mangalib_probe.py --path /api/user/me --path /api/bookmarks
    python scripts/mangalib_probe.py --path /api/comments/1/vote --method POST --data '{"vote":1}'
    python scripts/mangalib_probe.py --host https://api.cdnlibs.org --no-cookies
    python scripts/mangalib_probe.py --user-id 12345
"""

from __future__ import annotations

import argparse
import json
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_COOKIE_FILE = os.path.join(
    os.path.expanduser("~"), "Downloads", "mangalib-cookie.json"
)
DEFAULT_HOST = "https://api.cdnlibs.org"
SITE_HOST = "https://mangalib.org"
BODY_EXCERPT = 200

APP_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:154.0) "
        "Gecko/20100101 Firefox/154.0"
    ),
    "Accept": "*/*",
    "Accept-Language": "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
    "Site-Id": "1",
    "Content-Type": "application/json",
    "Client-Time-Zone": "Europe/Moscow",
    "Origin": SITE_HOST,
    "Referer": SITE_HOST + "/",
    "Sec-Fetch-Dest": "empty",
    "Sec-Fetch-Mode": "cors",
    "Sec-Fetch-Site": "cross-site",
}

# Host-independent route candidates. {uid} is filled from --user-id.
CURRENT_USER_ROUTES = [
    "/api/user/me",
    "/api/user/profile",
    "/api/profile",
    "/api/users/me",
    "/api/user/0",
    "/api/user",
    "/api/auth/user",
]

NOTIFICATION_ROUTES = [
    "/api/notifications",
    "/api/notifications/count",
    "/api/user/notifications/count",
    "/api/notifications/unread-count",
    "/api/user/notifications",
]

BOOKMARK_ROUTES = [
    "/api/bookmarks?status=1&site_id[]=1",
    "/api/bookmarks?site_id[]=1",
    "/api/bookmarks",
    "/api/user/{uid}/bookmarks?status=1&site_id[]=1",
]

PROFILE_BY_ID_ROUTES = [
    "/api/user/{uid}",
    "/api/user/{uid}/profile",
    "/api/users/{uid}",
    "/api/user?id={uid}",
    "/api/user/{uid}/info",
]

DETAILED_PROFILE_ROUTES = [
    "/api/user/{uid}?fields[]=about&fields[]=gender&fields[]=background"
    "&fields[]=avatar_frame_id&fields[]=premium_background_id&fields[]=points",
    "/api/user/{uid}/about",
    "/api/users/{uid}/profile",
]

PRIVACY_ROUTES = [
    "/api/user/{uid}/settings/privacy",
    "/api/user/settings/privacy",
    "/api/user/{uid}/privacy",
    "/api/profile/privacy",
]

MUTATION_ROUTES = [
    ("POST", "/api/bookmarks", {"media_type": "manga", "media_slug": "x", "status": 1}),
    ("DELETE", "/api/bookmarks/0", None),
    ("POST", "/api/comments/0/vote", {"vote": 1}),
    ("POST", "/api/user/{uid}", {"update_type": "info"}),
    ("PUT", "/api/user/{uid}/settings/privacy", {}),
]


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Report 3xx instead of following it -- a redirect IS the answer we want."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _ssl_context() -> ssl.SSLContext:
    return ssl.create_default_context()


def load_cookie_export(path: str) -> list[dict]:
    with open(path, "r", encoding="utf-8") as fh:
        raw = fh.read().strip()
    if raw.startswith("["):
        return json.loads(raw)
    # Tolerate a plain header dump: "a=b; c=d" -> pseudo entries.
    entries = []
    for part in raw.split(";"):
        part = part.strip()
        if not part or "=" not in part:
            continue
        name, _, value = part.partition("=")
        entries.append({"name": name.strip(), "value": value.strip(), "domain": ""})
    return entries


def cookie_header_from_entries(entries: list[dict]) -> str:
    pairs = []
    for entry in entries:
        name = str(entry.get("name", "")).strip()
        value = str(entry.get("value", "")).strip()
        if name and value:
            pairs.append("{}={}".format(name, value))
    return "; ".join(pairs)


def xsrf_token_from_entries(entries: list[dict]) -> str | None:
    for entry in entries:
        if str(entry.get("name", "")).upper() == "XSRF-TOKEN":
            value = str(entry.get("value", ""))
            if value:
                # Laravel URL-encodes the cookie value; the header needs it decoded.
                return urllib.parse.unquote(value)
    return None


def cookie_header_from_manual(path: str) -> str:
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read().strip()


def describe_cookies(entries: list[dict]) -> str:
    lines = []
    for entry in entries:
        lines.append(
            "    {:<62} len={:<4} domain={:<16} httpOnly={}".format(
                str(entry.get("name", "")),
                len(str(entry.get("value", ""))),
                str(entry.get("domain", "")) or "-",
                entry.get("httpOnly", False),
            )
        )
    return "\n".join(lines)


def fingerprint(value: str) -> str:
    """Short non-reversible id so two cookie values can be compared by eye."""
    import hashlib

    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:12]


def inspect_session(headers: dict, entries: list[dict]) -> None:
    """Check whether mangalib.org accepts the stored Laravel session.

    Laravel re-issues the session cookie on every response, so a *changed* value
    means the old session id was unknown or expired -- that is the difference
    between "cookie jar is stale" and "API route is wrong", which drives every
    other verdict in this script.
    """
    sent = {
        str(entry.get("name")): str(entry.get("value"))
        for entry in entries
        if entry.get("name")
    }
    for url in (SITE_HOST + "/ru", SITE_HOST + "/ru/front/auth"):
        request = urllib.request.Request(url, method="GET")
        for key, value in headers.items():
            request.add_header(key, value)
        opener = urllib.request.build_opener(
            NoRedirect(), urllib.request.HTTPSHandler(context=_ssl_context())
        )
        try:
            response = opener.open(request, timeout=30)
            status = response.status
            raw_headers = response.headers
            body = response.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as err:
            status = err.code
            raw_headers = err.headers
            body = err.read().decode("utf-8", "replace")
        except Exception as err:
            print("  {}: request failed: {}".format(url, err))
            continue

        issued = {}
        for cookie in raw_headers.get_all("Set-Cookie") or []:
            pair = cookie.split(";")[0]
            name, _, value = pair.partition("=")
            issued[name.strip()] = value.strip()

        print("\n  GET {} -> {}".format(url, status))
        if "mangalib_session" in issued:
            mine = sent.get("mangalib_session", "")
            theirs = issued["mangalib_session"]
            print(
                "    session sent fp={} (len {}) / issued fp={} (len {}) => {}".format(
                    fingerprint(mine),
                    len(mine),
                    fingerprint(theirs),
                    len(theirs),
                    "REJECTED (server rotated the session)"
                    if mine != theirs
                    else "accepted (unchanged)",
                )
            )
        markers = {
            "logout-link": "logout" in body.lower(),
            "auth-form": "front/auth" in body,
            "login-word": "\u0432\u043e\u0439\u0442\u0438" in body.lower(),
            "nuxt-state": "window.__NUXT__" in body,
            "user-id-in-state": '"user"' in body,
        }
        print("    html markers: {}".format(
            ", ".join("{}={}".format(k, v) for k, v in markers.items())
        ))
        print("    body: {}".format(" ".join(body.split())[:BODY_EXCERPT]))


def probe(
    method: str,
    url: str,
    headers: dict,
    payload: dict | None,
    body_limit: int = BODY_EXCERPT,
) -> dict:
    data = None
    if payload is not None and method.upper() in ("POST", "PUT", "PATCH", "DELETE"):
        data = json.dumps(payload).encode("utf-8")

    request = urllib.request.Request(url, data=data, method=method.upper())
    for key, value in headers.items():
        request.add_header(key, value)

    opener = urllib.request.build_opener(
        NoRedirect(), urllib.request.HTTPSHandler(context=_ssl_context())
    )
    try:
        response = opener.open(request, timeout=30)
        status = response.status
        location = response.headers.get("Location")
        server = response.headers.get("Server")
        ctype = response.headers.get("Content-Type", "")
        raw = response.read()
        header_names = list(response.headers.keys())
        set_cookie = response.headers.get_all("Set-Cookie") or []
    except urllib.error.HTTPError as err:
        status = err.code
        location = err.headers.get("Location") if err.headers else None
        server = err.headers.get("Server") if err.headers else None
        ctype = err.headers.get("Content-Type", "") if err.headers else ""
        raw = err.read()
        header_names = list(err.headers.keys()) if err.headers else []
        set_cookie = (err.headers.get_all("Set-Cookie") or []) if err.headers else []
    except Exception as err:  # network/DNS/TLS failures must not kill the run
        return {
            "status": 0,
            "location": None,
            "server": None,
            "kind": "error",
            "body": "{}: {}".format(type(err).__name__, err),
        }

    body = raw.decode("utf-8", "replace")
    kind = classify(body, ctype, status)
    return {
        "status": status,
        "location": location,
        "server": server,
        "kind": kind,
        "body": " ".join(body.split())[:body_limit],
        "header_names": header_names,
        "set_cookie_names": [cookie.split(";")[0].split("=")[0] for cookie in set_cookie],
    }


def classify(body: str, ctype: str, status: int) -> str:
    """Status first: 401 vs 404 is what separates "auth required" from "wrong URL"
    on this API, because both answers carry a JSON toast body."""
    if status == 0:
        return "error"
    if 300 <= status < 400:
        return "redirect"
    if status in (401, 419):
        return "auth-required"
    if status == 403:
        return "forbidden"
    if status == 404:
        return "not-found"
    if status == 405:
        return "wrong-method"
    if status == 422:
        return "validation"
    if status >= 500:
        return "server-error"

    stripped = body.lstrip()
    if stripped.startswith("{") or stripped.startswith("["):
        try:
            parsed = json.loads(body)
        except ValueError:
            return "broken-json"
        if isinstance(parsed, dict) and isinstance(parsed.get("data"), dict):
            return "json+data"
        if isinstance(parsed, dict) and isinstance(parsed.get("data"), list):
            return "json+data[]"
        return "json"
    if stripped.startswith("<"):
        return "html"
    return "text"


def scan_bookmark_shape(headers: dict, args) -> None:
    """Find a user whose bookmark list is public and dump one item's keys.

    The Rust side parses `item.media` and falls back to the item itself, so the
    nesting has to be observed rather than guessed.
    """
    url = args.host + "/api/user?q=an&page=1"
    request = urllib.request.Request(url, method="GET")
    for key, value in headers.items():
        request.add_header(key, value)
    opener = urllib.request.build_opener(
        NoRedirect(), urllib.request.HTTPSHandler(context=_ssl_context())
    )
    try:
        with opener.open(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8", "replace"))
    except Exception as err:
        print("  user search failed: {}".format(err))
        return

    candidates = [
        int(user["id"]) for user in payload.get("data", []) if user.get("id")
    ][:12]
    print("  candidates: {}".format(candidates))
    for uid in candidates:
        route = "/api/bookmarks?user_id={}&status=1&site_id[]=1".format(uid)
        result = probe("GET", args.host + route, headers, None, args.body_limit)
        print("  {:<52} {:>3} {}".format(route, result["status"], result["kind"]))
        if result["status"] != 200:
            continue
        # probe() only keeps an excerpt; re-fetch for a structural answer.
        request = urllib.request.Request(args.host + route, method="GET")
        for key, value in headers.items():
            request.add_header(key, value)
        try:
            with opener.open(request, timeout=30) as response:
                payload = json.loads(response.read().decode("utf-8", "replace"))
        except Exception:
            continue
        items = payload.get("data") or []
        if not items:
            continue
        item = items[0]
        print("    item keys: {}".format(sorted(item.keys())))
        if isinstance(item.get("media"), dict):
            print("    media keys: {}".format(sorted(item["media"].keys())[:18]))
            print("    media.id={} status={}".format(
                item["media"].get("id"), item.get("status")
            ))
        print("    meta: {}".format(json.dumps(payload.get("meta"), ensure_ascii=False)[:160]))
        return
    print("  no public non-empty bookmark list found among candidates")


def fetch_with_jar(url: str, headers: dict, jar: dict, method: str = "GET") -> tuple:
    """Like probe(), but folds Set-Cookie back into `jar` (name -> value).

    Laravel rotates `mangalib_session` and DDoS-Guard issues per-host `__ddg*`
    cookies on every response, so a single-shot request cannot tell "stale
    cookie" from "wrong route". Returning the updated jar makes that testable.
    """
    request = urllib.request.Request(url, method=method)
    for key, value in headers.items():
        if key.lower() == "cookie":
            continue
        request.add_header(key, value)
    if jar:
        request.add_header("Cookie", "; ".join("{}={}".format(k, v) for k, v in jar.items()))

    opener = urllib.request.build_opener(
        NoRedirect(), urllib.request.HTTPSHandler(context=_ssl_context())
    )
    try:
        response = opener.open(request, timeout=30)
        status, raw_headers, raw = response.status, response.headers, response.read()
    except urllib.error.HTTPError as err:
        status, raw_headers, raw = err.code, err.headers, err.read()
    except Exception as err:
        return 0, None, "", "{}: {}".format(type(err).__name__, err)

    updated = []
    for cookie in raw_headers.get_all("Set-Cookie") or []:
        pair = cookie.split(";")[0]
        name, _, value = pair.partition("=")
        name, value = name.strip(), value.strip()
        if name and value and jar.get(name) != value:
            updated.append(name)
        if name and value:
            jar[name] = value
    return status, raw_headers.get("Location"), raw.decode("utf-8", "replace"), updated


def probe_with_refresh(args, jar: dict, paths: list[str]) -> None:
    """Refresh the jar like a browser would, then re-probe auth routes.

    Order matters: mangalib.org hands out the Laravel session (and can rebuild
    it from remember_web_*), api.cdnlibs.org hands out the __ddg* cookies that
    DDoS-Guard expects on the API host.
    """
    base_headers = {k: v for k, v in APP_HEADERS.items() if k.lower() != "cookie"}
    print("\n== session refresh ==")
    status, location, body, updated = fetch_with_jar(SITE_HOST + "/ru", base_headers, jar)
    print("  GET {} -> {} updated=[{}]".format(SITE_HOST + "/ru", status, ", ".join(updated)))
    status, location, body, updated = fetch_with_jar(DEFAULT_HOST + "/api/", base_headers, jar)
    print("  GET {}/api/ -> {} updated=[{}]".format(DEFAULT_HOST, status, ", ".join(updated)))
    print("  jar names now: {}".format(", ".join(sorted(jar))))

    for path in paths:
        url = DEFAULT_HOST + path
        status, location, body, _ = fetch_with_jar(url, base_headers, jar)
        kind = classify(body, "", status)
        print(
            "  {:<56} {:>3} {:<16} {}".format(
                path, status, kind, VERDICT.get(kind, kind)
            )
        )
        if location:
            print("      -> Location: {}".format(location))
        print("      body: {}".format(" ".join(body.split())[:BODY_EXCERPT]))


VERDICT = {
    "json+data": "works",
    "json+data[]": "works",
    "json": "works (no data key)",
    "redirect": "auth required (302 to login)",
    "auth-required": "exists, auth required",
    "forbidden": "exists, access denied",
    "not-found": "does not exist",
    "wrong-method": "exists, wrong HTTP method",
    "validation": "exists, payload rejected",
    "server-error": "server error (often a non-numeric route param)",
    "html": "html page, not API json",
    "broken-json": "bad json",
    "text": "unexpected",
    "error": "network error",
}


def run_block(title: str, routes: list[str], args, headers_cookie: dict, anon: dict) -> list[tuple]:
    rows = []
    print("\n== {} ==".format(title))
    for route in routes:
        path = route.replace("{uid}", str(args.user_id))
        for label, headers in (("with-cookies", headers_cookie), ("no-cookies", anon)):
            if label == "no-cookies" and not args.both:
                continue
            url = args.host + path
            result = probe("GET", url, headers, None, args.body_limit)
            verdict = VERDICT.get(result["kind"], result["kind"])
            rows.append((label, "GET", path, result, verdict))
            print(
                "{:<13} GET    {:<58} {:>3} {:<20} {}".format(
                    label, path, result["status"], result["kind"], verdict
                )
            )
            if result["location"]:
                print("              -> Location: {}".format(result["location"]))
            print("              body: {}".format(result["body"] or "<empty>"))
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe MangaLib API routes")
    parser.add_argument("--cookie-file", default=DEFAULT_COOKIE_FILE)
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--user-id", type=int, default=0)
    parser.add_argument("--path", action="append", default=[], help="extra/only path to probe")
    parser.add_argument("--method", default="GET")
    parser.add_argument("--data", default=None, help="JSON body for --path")
    parser.add_argument("--no-cookies", action="store_true")
    parser.add_argument("--both", action="store_true", help="probe anonymously too")
    parser.add_argument("--summary", action="store_true", help="run every candidate group")
    parser.add_argument("--cookies-only", action="store_true", help="just print cookie inventory")
    parser.add_argument("--url", action="append", default=[], help="raw absolute URL (any host)")
    parser.add_argument("--dump-headers", action="store_true", help="print response header names")
    parser.add_argument("--inspect-session", action="store_true", help="is the stored Laravel session still valid?")
    parser.add_argument("--scan-bookmarks", action="store_true", help="dump the bookmark item shape of a public user")
    parser.add_argument("--refresh-session", action="store_true", help="refresh the jar (session + __ddg*) then re-probe")
    parser.add_argument("--body-limit", type=int, default=BODY_EXCERPT, help="characters of body to print")
    args = parser.parse_args()

    if not os.path.exists(args.cookie_file):
        print("cookie file not found: {}".format(args.cookie_file), file=sys.stderr)
        return 2

    header = cookie_header_from_manual(args.cookie_file)
    entries: list[dict] = []
    if header.startswith("["):
        entries = load_cookie_export(args.cookie_file)
        header = cookie_header_from_entries(entries)
    elif header.count("=") > 1 and ";" in header:
        entries = load_cookie_export(args.cookie_file)

    xsrf = xsrf_token_from_entries(entries)
    print("cookie file : {}".format(args.cookie_file))
    print("cookie names:")
    print(describe_cookies(entries) if entries else "    <none parsed>")
    print("header len  : {}".format(len(header)))
    print("XSRF token  : {}".format("present (len {})".format(len(xsrf)) if xsrf else "absent"))
    if args.cookies_only:
        return 0

    headers_cookie = dict(APP_HEADERS)
    if not args.no_cookies:
        headers_cookie["Cookie"] = header
    if xsrf:
        headers_cookie["X-XSRF-TOKEN"] = xsrf
        headers_cookie["X-Requested-With"] = "XMLHttpRequest"
    anon = dict(APP_HEADERS)

    if args.inspect_session:
        inspect_session(headers_cookie, entries)
        return 0

    if args.scan_bookmarks:
        scan_bookmark_shape(headers_cookie, args)
        return 0

    if args.refresh_session:
        jar = {
            str(entry.get("name")): str(entry.get("value"))
            for entry in entries
            if entry.get("name")
        }
        probe_with_refresh(
            args,
            jar,
            [
                "/api/notifications/count",
                "/api/notifications",
                "/api/user/me",
                "/api/user/{}".format(args.user_id or 12168054),
                "/api/bookmarks?user_id={}&status=1&site_id[]=1".format(args.user_id or 12168054),
                "/api/user/{}/settings/privacy".format(args.user_id or 12168054),
            ],
        )
        return 0

    if args.url:
        for url in args.url:
            payload = json.loads(args.data) if args.data else None
            for use_cookies in (not args.no_cookies, False):
                if not use_cookies and not (args.both or args.no_cookies):
                    continue
                headers = dict(headers_cookie) if use_cookies else dict(anon)
                result = probe(args.method, url, headers, payload, args.body_limit)
                label = "with-cookies" if use_cookies else "no-cookies"
                print(
                    "{:<13} {:<6} {:<70} {:>3} {:<20} {}".format(
                        label, args.method.upper(), url, result["status"],
                        result["kind"], VERDICT.get(result["kind"], result["kind"])
                    )
                )
                print("              server: {}".format(result["server"]))
                if result["location"]:
                    print("              -> Location: {}".format(result["location"]))
                if args.dump_headers:
                    print("              header names: {}".format(", ".join(result.get("header_names", []))))
                    print("              set-cookie names: {}".format(", ".join(result.get("set_cookie_names", []))))
                print("              body: {}".format(result["body"] or "<empty>"))
                if args.no_cookies:
                    break
        return 0

    if args.path:
        for path in args.path:
            payload = json.loads(args.data) if args.data else None
            for label, headers in (("with-cookies", headers_cookie), ("no-cookies", anon)):
                if label == "no-cookies" and not (args.both or args.no_cookies):
                    continue
                if args.no_cookies:
                    headers = anon
                url = args.host + path.replace("{uid}", str(args.user_id))
                result = probe(args.method, url, headers, payload, args.body_limit)
                verdict = VERDICT.get(result["kind"], result["kind"])
                print(
                    "{:<13} {:<6} {:<58} {:>3} {:<20} {}".format(
                        label, args.method.upper(), path, result["status"], result["kind"], verdict
                    )
                )
                if result["location"]:
                    print("              -> Location: {}".format(result["location"]))
                print("              body: {}".format(result["body"] or "<empty>"))
                if args.no_cookies:
                    break
        return 0

    run_block("current user", CURRENT_USER_ROUTES, args, headers_cookie, anon)
    run_block("notifications", NOTIFICATION_ROUTES, args, headers_cookie, anon)
    run_block("bookmarks", BOOKMARK_ROUTES, args, headers_cookie, anon)
    if args.user_id:
        run_block("profile by id", PROFILE_BY_ID_ROUTES, args, headers_cookie, anon)
        run_block("detailed profile", DETAILED_PROFILE_ROUTES, args, headers_cookie, anon)
        run_block("privacy settings", PRIVACY_ROUTES, args, headers_cookie, anon)
    else:
        print("\n(skipping id-based groups: pass --user-id)")

    if args.summary:
        print("\n== mutations (CSRF required) ==")
        for method, route, payload in MUTATION_ROUTES:
            path = route.replace("{uid}", str(args.user_id))
            if payload is None and method == "DELETE":
                continue  # would touch a real id; run manually with --path
            url = args.host + path
            result = probe(method, url, headers_cookie, payload, args.body_limit)
            verdict = VERDICT.get(result["kind"], result["kind"])
            print(
                "{:<13} {:<6} {:<58} {:>3} {:<20} {}".format(
                    "with-cookies", method, path, result["status"], result["kind"], verdict
                )
            )
            if result["location"]:
                print("              -> Location: {}".format(result["location"]))
            print("              body: {}".format(result["body"] or "<empty>"))
    return 0


if __name__ == "__main__":
    sys.exit(main())