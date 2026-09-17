#!/usr/bin/env python3
"""Download official PG&E bill PDFs from My Account.

PG&E does not attach the statement PDF to paperless-billing email. The
file lives behind My Account. Login uses the same Salesforce Aura
actions as Home Assistant's Opower integration. Device cookies are
persisted so MFA is only needed about every six months (or after 90
days idle). When MFA is required, the code is read from the IMAP inbox
PG&E emails. Playwright then opens billing history and saves any new
statement PDFs.
"""

from __future__ import annotations

import argparse
import http.cookiejar
import imaplib
import json
import logging
import os
import re
import ssl
import sys
import time
from datetime import datetime, timedelta, timezone
from email import policy
from email.message import EmailMessage
from email.parser import BytesParser
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import HTTPCookieProcessor, Request, build_opener

LOG = logging.getLogger("pge-bills")

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36"
)
AURA_URL = (
    "https://myaccount.pge.com/myaccount/s/sfsites/aura"
    "?aura.ApexAction.execute=1"
)
ACCOUNT_HOME = "https://myaccount.pge.com/myaccount/s/"

BILLING_PATHS = (
    ACCOUNT_HOME,
    "https://myaccount.pge.com/myaccount/s/billingandpaymenthistory",
    "https://myaccount.pge.com/myaccount/s/billing-and-payment-history",
    "https://myaccount.pge.com/myaccount/s/bill-payment-history",
)

CUSTBILL_RE = re.compile(
    r"custbill(\d{2})(\d{2})(\d{4})\.pdf", re.IGNORECASE
)
CODE_RE = re.compile(r"\b(\d{6})\b")
PDF_NAME_RE = re.compile(r'filename\*?=(?:UTF-8\'\')?"?([^";\r\n]+)"?', re.I)


class FetchError(RuntimeError):
    """A failure that should email the operator."""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--credentials", required=True, type=Path)
    parser.add_argument("--imap-password-file", required=True, type=Path)
    parser.add_argument("--imap-user", required=True)
    parser.add_argument("--imap-host", default="heracles.mxrouting.net")
    parser.add_argument("--imap-port", type=int, default=993)
    parser.add_argument("--state-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--mail-to", required=True)
    parser.add_argument("--mail-from", required=True)
    parser.add_argument("--hostname", default=os.uname().nodename)
    parser.add_argument("--smtp-host", default="heracles.mxrouting.net")
    parser.add_argument("--smtp-port", type=int, default=465)
    parser.add_argument("--smtp-user", required=True)
    parser.add_argument("--smtp-password-file", required=True, type=Path)
    return parser.parse_args()


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def save_json(path: Path, payload: dict[str, Any]) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)


def aura_execute(opener: Any, body: dict[str, Any]) -> Any:
    payload: dict[str, str] = {}
    for key, value in body.items():
        if isinstance(value, dict):
            payload[key] = json.dumps(value, separators=(",", ":"))
        else:
            payload[key] = str(value)
    request = Request(
        AURA_URL,
        data=urlencode(payload).encode(),
        headers={
            "User-Agent": USER_AGENT,
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "Accept": "*/*",
        },
        method="POST",
    )
    try:
        with opener.open(request, timeout=60) as response:
            raw = response.read()
    except HTTPError as err:
        raw = err.read()
        raise FetchError(
            f"Aura HTTP {err.code}: {raw[:500]!r}"
        ) from err
    except URLError as err:
        raise FetchError(f"Aura request failed: {err}") from err
    try:
        return json.loads(raw)
    except json.JSONDecodeError as err:
        raise FetchError(f"Aura returned non-JSON: {raw[:500]!r}") from err


def aura_action(
    opener: Any,
    classname: str,
    method: str,
    params: dict[str, Any] | None,
    app: str,
    page_uri: str,
    token: str,
) -> Any:
    body: dict[str, Any] = {
        "message": {
            "actions": [
                {
                    "descriptor": "aura://ApexActionController/ACTION$execute",
                    "params": {
                        "classname": classname,
                        "method": method,
                        **({"params": params} if params is not None else {}),
                    },
                }
            ]
        },
        "aura.context": {"app": app},
        "aura.pageURI": page_uri,
        "aura.token": token,
    }
    # ApexAction.execute with no params must not send an empty params object.
    if params is None:
        body["message"]["actions"][0]["params"] = {
            "classname": classname,
            "method": method,
        }
    return aura_execute(opener, body)


def action_return(res: Any) -> dict[str, Any]:
    actions = res.get("actions") or []
    if not actions:
        raise FetchError(f"Aura response had no actions: {res!r}")
    action = actions[0]
    if action.get("state") != "SUCCESS":
        raise FetchError(f"Aura action failed: {action.get('error') or action}")
    value = (action.get("returnValue") or {}).get("returnValue")
    if not isinstance(value, dict):
        raise FetchError(f"Aura action missing returnValue: {action!r}")
    return value


def http_get(opener: Any, url: str) -> bytes:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with opener.open(request, timeout=60) as response:
        return response.read()


def cookie_value(jar: http.cookiejar.CookieJar, prefix: str) -> str | None:
    for cookie in jar:
        if cookie.name.startswith(prefix):
            return cookie.value
    return None


def select_mfa(opener: Any, login_value: dict[str, Any], option: str) -> None:
    value = action_return(
        aura_action(
            opener,
            "MyAcct_Apex_CustomMFAController",
            "handleChoiceofMFA",
            {
                "username": login_value.get("retencrUsrname"),
                "selectedChoice": option,
                "isforgotpassword": False,
            },
            "siteforce:loginApp2",
            "/myaccount/s/login/",
            "null",
        )
    )
    if str(value.get("retMessage", "")).lower() != "success":
        raise FetchError(f"MFA option {option} failed: {value}")


def submit_mfa(
    opener: Any,
    login_value: dict[str, Any],
    password: str,
    option: str,
    code: str,
) -> dict[str, str]:
    value = action_return(
        aura_action(
            opener,
            "MyAcct_Apex_CustomMFAController",
            "verifySignInCode",
            {
                "input": {
                    "authCode": code,
                    "password": password,
                    "encToken": login_value.get("encryptedTFT"),
                    "usernameVal": login_value.get("retencrUsrname"),
                    "isForgotPasswordFlow": False,
                    "otpType": option,
                }
            },
            "siteforce:loginApp2",
            "/myaccount/s/login/",
            "null",
        )
    )
    if str(value.get("returnResponse", "")).lower() != "success":
        raise FetchError(f"Invalid MFA code: {value.get('returnResponse')}")
    wrapper = value.get("wrapperObj") or {}
    return {
        "browsercookie": wrapper.get("retencrUsrname") or "",
        "validationCookie": wrapper.get("encryptedKey") or "",
        "expiryDateTime": wrapper.get("expiryDateTime") or "",
    }


def imap_latest_code(
    host: str,
    port: int,
    user: str,
    password: str,
    after: datetime,
) -> str | None:
    mailbox = imaplib.IMAP4_SSL(host, port)
    try:
        mailbox.login(user, password)
        mailbox.select("INBOX", readonly=True)
        since = (after - timedelta(days=1)).strftime("%d-%b-%Y")
        status, data = mailbox.search(
            None, f'(SINCE {since} FROM "pge.com")'
        )
        if status != "OK":
            status, data = mailbox.search(None, f"(SINCE {since})")
        if status != "OK" or not data or not data[0]:
            return None
        ids = data[0].split()
        best: tuple[datetime, str] | None = None
        for msg_id in reversed(ids[-20:]):
            status, fetched = mailbox.fetch(msg_id, "(RFC822)")
            if status != "OK" or not fetched or not fetched[0]:
                continue
            raw = fetched[0][1]
            if not isinstance(raw, (bytes, bytearray)):
                continue
            message = BytesParser(policy=policy.default).parsebytes(raw)
            from_addr = str(message.get("From", "")).lower()
            subject = str(message.get("Subject", "")).lower()
            if "pge" not in from_addr and "pge" not in subject:
                continue
            when = _message_date(message) or after
            if when < after - timedelta(seconds=15):
                continue
            body = _message_text(message)
            match = CODE_RE.search(body)
            if not match:
                continue
            if best is None or when >= best[0]:
                best = (when, match.group(1))
        return None if best is None else best[1]
    finally:
        try:
            mailbox.logout()
        except Exception:
            pass


def _message_date(message: Any) -> datetime | None:
    value = message.get("Date")
    if not value:
        return None
    try:
        parsed = email_parsedate(value)
    except Exception:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def email_parsedate(value: str) -> datetime:
    from email.utils import parsedate_to_datetime

    return parsedate_to_datetime(value)


def _message_text(message: Any) -> str:
    parts: list[str] = []
    if message.is_multipart():
        for part in message.walk():
            ctype = part.get_content_type()
            if ctype in {"text/plain", "text/html"}:
                try:
                    parts.append(part.get_content())
                except Exception:
                    payload = part.get_payload(decode=True)
                    if payload:
                        parts.append(payload.decode("utf-8", "replace"))
    else:
        try:
            parts.append(message.get_content())
        except Exception:
            payload = message.get_payload(decode=True)
            if payload:
                parts.append(payload.decode("utf-8", "replace"))
    return "\n".join(str(p) for p in parts)


def wait_for_mfa_code(
    host: str,
    port: int,
    user: str,
    password: str,
    after: datetime,
    timeout_sec: int = 180,
) -> str:
    deadline = time.time() + timeout_sec
    while time.time() < deadline:
        code = imap_latest_code(host, port, user, password, after)
        if code:
            LOG.info("Read MFA code from IMAP")
            return code
        time.sleep(5)
    raise FetchError(
        "Timed out waiting for a PG&E MFA email. Confirm My Account "
        f"sends security codes to {user}."
    )


def finish_login(opener: Any, jar: http.cookiejar.CookieJar, redirect: str) -> None:
    LOG.info("Following login redirect")
    http_get(opener, redirect)
    LOG.info("Opening account home")
    http_get(opener, ACCOUNT_HOME)
    token = cookie_value(jar, "__Host-ERIC_PROD")
    if not token:
        raise FetchError("Logged in but no Aura token cookie was set")
    for classname, method in (
        ("MyAcct_OneTrustIntegrationController", "generateToken"),
        ("MyAcct_AccountCacheHandler", "copyToSessionCacheForUser"),
    ):
        LOG.info("Warming session %s.%s", classname, method)
        try:
            aura_action(
                opener,
                classname,
                method,
                None,
                "siteforce:communityApp",
                "/myaccount/s/",
                token,
            )
        except FetchError as err:
            LOG.warning("Session warmup %s.%s failed: %s", classname, method, err)


def login(
    opener: Any,
    jar: http.cookiejar.CookieJar,
    username: str,
    password: str,
    login_data: dict[str, str],
    imap: dict[str, Any],
    state_dir: Path,
    depth: int = 0,
) -> dict[str, str]:
    if depth > 2:
        raise FetchError("Login kept requesting MFA after a successful code")
    LOG.info("Logging in to PG&E My Account")
    value = action_return(
        aura_action(
            opener,
            "MyAcct_customLoginLWCController",
            "login",
            {
                "username": username,
                "password": password,
                "browsercookie": login_data.get("browsercookie") or "null",
                "validationCookie": login_data.get("validationCookie") or "null",
            },
            "siteforce:loginApp2",
            "/myaccount/s/login/",
            "null",
        )
    )
    message = value.get("retMessage", "")
    LOG.info("Login returned: %s", str(message)[:80])
    if message == "verifymfa :":
        option = "Email" if value.get("EmailVal") else "Phone"
        if option != "Email":
            raise FetchError(
                "PG&E asked for phone MFA. Set the My Account security "
                "code destination to email so this host can read it."
            )
        LOG.info("MFA required; requesting email code")
        select_mfa(opener, value, option)
        requested = datetime.now(timezone.utc)
        code = wait_for_mfa_code(
            imap["host"],
            imap["port"],
            imap["user"],
            imap["password"],
            requested,
        )
        login_data = submit_mfa(opener, value, password, option, code)
        save_json(state_dir / "login-data.json", login_data)
        return login(
            opener,
            jar,
            username,
            password,
            login_data,
            imap,
            state_dir,
            depth=depth + 1,
        )
    if not str(message).startswith("http"):
        raise FetchError(f"Login failed: {message}")
    finish_login(opener, jar, str(message))
    return login_data


def cookies_for_playwright(jar: http.cookiejar.CookieJar) -> list[dict[str, Any]]:
    cookies: list[dict[str, Any]] = []
    for cookie in jar:
        domain = (cookie.domain or "myaccount.pge.com").lstrip(".")
        item: dict[str, Any] = {
            "name": cookie.name,
            "value": cookie.value,
            "domain": domain,
            "path": cookie.path or "/",
            "secure": bool(cookie.secure),
        }
        rest = {str(k).lower(): v for k, v in getattr(cookie, "_rest", {}).items()}
        if "httponly" in rest:
            item["httpOnly"] = True
        cookies.append(item)
    return cookies


def archive_name(filename: str) -> str | None:
    match = CUSTBILL_RE.search(filename)
    if not match:
        return None
    month, day, year = match.group(1), match.group(2), match.group(3)
    return f"{year}-{month}-{day}.bill.pdf"


def write_pdf(output_dir: Path, filename: str, data: bytes) -> Path | None:
    if not data.startswith(b"%PDF"):
        LOG.warning("Skipping non-PDF download named %s", filename)
        return None
    name = archive_name(filename) or _fallback_name(output_dir, filename)
    dest = output_dir / name
    if dest.exists() and dest.stat().st_size == len(data):
        LOG.info("Already have %s", dest.name)
        return None
    tmp = dest.with_suffix(".tmp.pdf")
    tmp.write_bytes(data)
    tmp.replace(dest)
    LOG.info("Wrote %s (%d bytes)", dest.name, len(data))
    return dest


def _fallback_name(output_dir: Path, filename: str) -> str:
    stem = Path(filename).stem or "bill"
    stem = re.sub(r"[^A-Za-z0-9._-]+", "_", stem)[:80]
    candidate = f"{stem}.bill.pdf"
    if not (output_dir / candidate).exists():
        return candidate
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return f"{stem}-{stamp}.bill.pdf"


def download_pdfs(
    jar: http.cookiejar.CookieJar,
    output_dir: Path,
    state_dir: Path,
) -> list[Path]:
    from playwright.sync_api import TimeoutError as PlaywrightTimeout
    from playwright.sync_api import sync_playwright

    saved: list[Path] = []
    found_controls = False
    already = 0

    def keep(filename: str, data: bytes) -> None:
        nonlocal already
        named = archive_name(filename)
        if named and (output_dir / named).exists():
            already += 1
            LOG.info("Already have %s", named)
            return
        path = write_pdf(output_dir, filename, data)
        if path is not None:
            saved.append(path)

    with sync_playwright() as playwright:
        launch: dict[str, Any] = {
            "headless": True,
            "args": [
                "--no-sandbox",
                "--disable-dev-shm-usage",
                "--disable-gpu",
                "--disable-extensions",
            ],
        }
        chromium_bin = os.environ.get("CHROMIUM_BIN")
        if chromium_bin:
            launch["executable_path"] = chromium_bin
        browser = playwright.chromium.launch(**launch)
        context = browser.new_context(
            accept_downloads=True,
            user_agent=USER_AGENT,
            viewport={"width": 1440, "height": 900},
        )
        context.add_cookies(cookies_for_playwright(jar))
        page = context.new_page()

        def on_response(response: Any) -> None:
            try:
                headers = {k.lower(): v for k, v in response.headers.items()}
                ctype = headers.get("content-type", "")
                url = response.url
                if "application/pdf" not in ctype and ".pdf" not in url.lower():
                    return
                data = response.body()
                filename = _filename_from_headers(headers.get("content-disposition", ""))
                if not filename:
                    filename = url.rsplit("/", 1)[-1].split("?", 1)[0] or "bill.pdf"
                keep(filename, data)
            except Exception as err:
                LOG.debug("PDF response capture skipped: %s", err)

        page.on("response", on_response)

        last_error: Exception | None = None
        opened = False
        for url in BILLING_PATHS:
            try:
                LOG.info("Opening %s", url)
                page.goto(url, wait_until="domcontentloaded", timeout=60_000)
                page.wait_for_timeout(4_000)
                if page.get_by_text(re.compile(r"sign\s*in", re.I)).count() and (
                    "login" in page.url.lower()
                ):
                    raise FetchError("Session expired; landed on the login page")
                opened = True
                _click_history(page)
                found_controls = found_controls or _download_pdf_buttons(page, keep) > 0
                if saved:
                    break
            except PlaywrightTimeout as err:
                last_error = err
                LOG.warning("Timeout on %s: %s", url, err)
            except FetchError:
                _dump_failure(page, state_dir)
                raise
            except Exception as err:
                last_error = err
                LOG.warning("Billing page %s failed: %s", url, err)
        if not saved and already == 0:
            _dump_failure(page, state_dir)
            if not opened and last_error is not None:
                raise FetchError(
                    f"Could not open billing pages: {last_error}"
                ) from last_error
            raise FetchError(
                "Logged in but found no bill PDFs. Selectors may need a "
                "refresh; see last-failure.png in the state directory."
            )
        browser.close()
    return saved


def _filename_from_headers(disposition: str) -> str:
    match = PDF_NAME_RE.search(disposition or "")
    if not match:
        return ""
    return match.group(1).strip()


def _click_history(page: Any) -> None:
    for label in (
        "All billing tasks",
        "All payments tasks",
        "Billing & Payment History",
        "Billing and Payment History",
        "View 24 month history",
        "View 24-month history",
    ):
        loc = page.get_by_text(label, exact=False)
        try:
            if loc.count() == 0:
                continue
            loc.first.click(timeout=5_000)
            page.wait_for_timeout(2_000)
            LOG.info("Clicked %s", label)
        except Exception:
            continue


def _download_pdf_buttons(page: Any, keep: Any) -> int:
    from playwright.sync_api import TimeoutError as PlaywrightTimeout

    labels = (
        "View Bill PDF",
        "View Current Bill",
        "View bill PDF",
    )
    seen = 0
    for label in labels:
        loc = page.get_by_text(label, exact=False)
        try:
            count = loc.count()
        except Exception:
            continue
        if count == 0:
            continue
        seen += count
        LOG.info("Found %d '%s' control(s)", count, label)
        for index in range(count):
            try:
                with page.expect_download(timeout=20_000) as download_info:
                    loc.nth(index).click(timeout=8_000)
                download = download_info.value
                path = download.path()
                if path:
                    keep(
                        download.suggested_filename or "bill.pdf",
                        Path(path).read_bytes(),
                    )
            except PlaywrightTimeout:
                page.wait_for_timeout(2_000)
            except Exception as err:
                LOG.warning("Click '%s' #%d failed: %s", label, index, err)
    return seen


def _dump_failure(page: Any, state_dir: Path) -> None:
    try:
        page.screenshot(path=str(state_dir / "last-failure.png"), full_page=True)
        (state_dir / "last-failure.html").write_text(page.content())
        (state_dir / "last-failure.url").write_text(page.url + "\n")
        LOG.info("Wrote failure dump under %s", state_dir)
    except Exception as err:
        LOG.warning("Could not dump failure artifacts: %s", err)


def send_mail(
    smtp_host: str,
    smtp_port: int,
    smtp_user: str,
    smtp_password: str,
    mail_from: str,
    mail_to: str,
    subject: str,
    body: str,
    attachments: list[Path],
) -> None:
    import smtplib

    msg = EmailMessage()
    msg["From"] = mail_from
    msg["To"] = mail_to
    msg["Subject"] = subject
    msg.set_content(body)
    for path in attachments:
        msg.add_attachment(
            path.read_bytes(),
            maintype="application",
            subtype="pdf",
            filename=path.name,
        )
    context = ssl.create_default_context()
    with smtplib.SMTP_SSL(smtp_host, smtp_port, context=context) as smtp:
        smtp.login(smtp_user, smtp_password)
        smtp.send_message(msg)


def already_logged_in(jar: http.cookiejar.CookieJar, opener: Any) -> bool:
    if not cookie_value(jar, "__Host-ERIC_PROD"):
        return False
    try:
        body = http_get(opener, ACCOUNT_HOME).decode("utf-8", "replace").lower()
    except Exception:
        return False
    if "myacct_customlogin" in body or "/myaccount/s/login" in body:
        return False
    return True


def main() -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    args = parse_args()
    os.environ["OUTPUT_DIR"] = str(args.output_dir)
    os.environ["STATE_DIR"] = str(args.state_dir)
    args.state_dir.mkdir(parents=True, exist_ok=True)
    args.output_dir.mkdir(parents=True, exist_ok=True)

    mailbox_password = args.imap_password_file.read_text().strip()
    smtp_password = args.smtp_password_file.read_text().strip()
    creds = load_json(args.credentials)
    username = creds.get("username") or creds.get("user")
    password = creds.get("password")
    imap = {
        "host": creds.get("imap_host") or args.imap_host,
        "port": int(creds.get("imap_port") or args.imap_port),
        "user": creds.get("imap_user") or args.imap_user,
        "password": creds.get("imap_password") or mailbox_password,
    }

    jar_path = args.state_dir / "cookies.txt"
    jar = http.cookiejar.LWPCookieJar(str(jar_path))
    if jar_path.exists():
        try:
            jar.load(ignore_discard=True, ignore_expires=True)
        except Exception as err:
            LOG.warning("Could not load cookies: %s", err)
    opener = build_opener(HTTPCookieProcessor(jar))
    opener.addheaders = [("User-Agent", USER_AGENT)]

    login_path = args.state_dir / "login-data.json"
    login_data = load_json(login_path) if login_path.exists() else {}

    try:
        if not username or not password:
            raise FetchError("credentials file must contain username and password")
        if not already_logged_in(jar, opener):
            login_data = login(
                opener,
                jar,
                username,
                password,
                login_data,
                imap,
                args.state_dir,
            )
            save_json(login_path, login_data)
        else:
            LOG.info("Existing session still valid")
        try:
            jar.save(ignore_discard=True, ignore_expires=True)
        except Exception as err:
            LOG.warning("Could not save cookies: %s", err)

        existing = {path.name for path in args.output_dir.glob("*.bill.pdf")}
        saved = download_pdfs(jar, args.output_dir, args.state_dir)
        # download_pdfs also writes via the response listener; re-scan.
        new_files = sorted(
            path
            for path in args.output_dir.glob("*.bill.pdf")
            if path.name not in existing
        )
        if saved:
            seen = {path.resolve() for path in new_files}
            for path in saved:
                if path.resolve() not in seen:
                    new_files.append(path)
        if new_files:
            names = ", ".join(path.name for path in new_files)
            send_mail(
                args.smtp_host,
                args.smtp_port,
                args.smtp_user,
                smtp_password,
                args.mail_from,
                args.mail_to,
                f"[{args.hostname}] PG&E bill {new_files[-1].name}",
                f"Archived {len(new_files)} new PG&E statement(s) to "
                f"{args.output_dir}:\n\n{names}\n",
                new_files,
            )
            LOG.info("Emailed %d new bill(s)", len(new_files))
        else:
            LOG.info("No new bills")
        return 0
    except FetchError as err:
        LOG.error("%s", err)
        try:
            send_mail(
                args.smtp_host,
                args.smtp_port,
                args.smtp_user,
                smtp_password,
                args.mail_from,
                args.mail_to,
                f"[{args.hostname}] PG&E bill fetch failed",
                f"{err}\n",
                [],
            )
        except Exception:
            LOG.exception("Could not send failure email")
        return 1
    except Exception as err:
        LOG.exception("Unexpected failure")
        try:
            send_mail(
                args.smtp_host,
                args.smtp_port,
                args.smtp_user,
                smtp_password,
                args.mail_from,
                args.mail_to,
                f"[{args.hostname}] PG&E bill fetch failed",
                f"{type(err).__name__}: {err}\n",
                [],
            )
        except Exception:
            LOG.exception("Could not send failure email")
        return 1


if __name__ == "__main__":
    sys.exit(main())
