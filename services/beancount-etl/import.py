"""ETL: pull complete rows from a Google Sheet, render them as Beancount
entries, append into total/inbox.beancount, commit + push to Forgejo, then
move imported rows to the sheet's History tab.

The Google Sheet is the queue: the main tab IS the set of rows that haven't
been imported. Move-to-history is the source-of-truth marker that an entry
has been processed, so it always runs strictly AFTER a successful push.

Dedup: every entry written to inbox carries a `sheet_row_hash` metadata
line, derived from the row's stable columns. On each run we parse the
existing inbox, collect those hashes, and skip rows we've already imported.
This makes the "push succeeded, move-to-history then crashed" case
self-healing — the next run won't re-import, but it WILL retry the move
so the sheet eventually drains. Move-to-history failures are still logged
loudly.

Auth: git pushes use HTTPS basic auth with the declarative Forgejo admin
password (already in sops as `forgejo-admin-password`). No PAT to mint or
rotate manually — re-deploying with a new admin password rotates this in
one shot.

Configuration is via env vars (set by services/beancount-etl.nix). Secrets
arrive in $CREDENTIALS_DIRECTORY thanks to systemd LoadCredential.
"""
from __future__ import annotations

import hashlib
import logging
import os
import re
import subprocess
import sys
import urllib.parse
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Optional

import gspread
import yaml
from google.oauth2.service_account import Credentials


SHEET_ID = os.environ["BEANCOUNT_ETL_SHEET_ID"]
MAIN_TAB = os.environ.get("BEANCOUNT_ETL_MAIN_TAB", "Expenses")
HISTORY_TAB = os.environ.get("BEANCOUNT_ETL_HISTORY_TAB", "History")
WORK_DIR = Path(os.environ["BEANCOUNT_ETL_WORK_DIR"])
REPO_HOST = os.environ["BEANCOUNT_ETL_REPO_HOST"]
REPO_PATH = os.environ["BEANCOUNT_ETL_REPO_PATH"]
REPO_USER = os.environ["BEANCOUNT_ETL_REPO_USER"]
GIT_AUTHOR_NAME = os.environ.get("BEANCOUNT_ETL_AUTHOR_NAME", "Beancount ETL")
GIT_AUTHOR_EMAIL = os.environ.get(
    "BEANCOUNT_ETL_AUTHOR_EMAIL", "automation@adnanshaikh.com"
)
INBOX_RELPATH = "total/inbox.beancount"
MAPPING_RELPATH = "etl/mapping.yaml"
CREDS_DIR = Path(os.environ["CREDENTIALS_DIRECTORY"])
SERVICE_ACCOUNT_FILE = CREDS_DIR / "service-account"
# We auth git pushes with the declarative Forgejo admin password rather than
# a manually-minted PAT — see services/beancount-etl.nix for rationale.
FORGEJO_PASSWORD_FILE = CREDS_DIR / "forgejo-password"

GSPREAD_SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/drive.readonly",
]

INBOX_HEADER = """\
;; ETL inbox — auto-generated. Do NOT hand-edit this file.
;;
;; Entries here are imported from the Google Sheet by services/beancount-etl
;; on shaikhlab. End-of-month reconciliation: when you parse new statements
;; for each account, move (or delete) entries from this file into the
;; appropriate per-account ledger files. The ETL re-sorts and rewrites the
;; rest on each run, so removing entries here is safe.

"""

logging.basicConfig(level=logging.INFO, format="%(message)s")
log = logging.getLogger("beancount-etl")


# ---------------------------------------------------------------------------
# Mapping
# ---------------------------------------------------------------------------


def _normalize_last_digits(raw: object) -> str:
    """Canonical form for matching `Account Last Digits` values.

    Google Sheets silently coerces all-digit strings to numbers even when the
    cell is formatted as Plain Text (any subsequent manual edit can flip it
    back), so a cell entered as `0884` round-trips through gspread as the int
    `884` and a cell entered as `0123` comes back as `123`. Strip leading
    zeros on both the sheet side AND the YAML side so `884`, `0884`, and
    `00884` all match the same mapping entry.

    Non-digit strings (e.g. account aliases) are left alone modulo
    whitespace, so this is a no-op for any caller that doesn't use a numeric
    last-N convention.
    """
    s = str(raw).strip()
    if s.isdigit():
        return s.lstrip("0") or "0"
    return s


@dataclass(frozen=True)
class AccountKey:
    """Identifies a beancount account by (Institution, Last Digits).

    Payer intentionally NOT part of the key: joint-account transactions
    legitimately record whoever initiated the swipe (e.g. "Adnan paid rent
    out of the Joint Capital One 360"), so we look up the account by
    institution+last-4 alone and let the row's Payer column flow through
    as plain `payer:` metadata on the rendered entry.

    `last_digits` is normalized via _normalize_last_digits at construction
    time so sheet/YAML lookup is robust to Sheets' leading-zero stripping.
    """

    institution: str
    last_digits: str

    @classmethod
    def from_row(cls, row: dict) -> "AccountKey":
        return cls(
            institution=str(row.get("Institution", "")).strip(),
            last_digits=_normalize_last_digits(row.get("Account Last Digits", "")),
        )


ACCOUNT_PREFIXES = ("Assets:", "Liabilities:", "Equity:", "Income:", "Expenses:")
PLACEHOLDER_ACCOUNT = "Equity:Inbox:Reconcile"


@dataclass
class Mapping:
    """Mapping table.

    `accounts` is required: every (Payer, Institution, Last Digits) tuple in
    the sheet must have a beancount account associated.

    `category_overrides` is optional. By default a sheet's Category value is
    interpreted as a path under `Expenses:` (e.g. `Food:EatingOut` becomes
    `Expenses:Food:EatingOut`). If the sheet value already starts with one of
    the standard top-level prefixes (Assets:/Liabilities:/Equity:/Income:/
    Expenses:) it's used as-is — useful for non-expense rows like tax refunds
    (`Income:Isra:US:TaxRefund:CA`). Add an entry under `categories:` in the
    YAML only when you want some sheet value to remap to an unusual account.
    """

    accounts: dict[AccountKey, str]
    category_overrides: dict[str, str]
    skip_renamed_names: set[str]

    @classmethod
    def load(cls, path: Path) -> "Mapping":
        data = yaml.safe_load(path.read_text())
        accounts: dict[AccountKey, str] = {}
        for entry in data.get("accounts", []):
            key = AccountKey(
                institution=str(entry["institution"]).strip(),
                last_digits=_normalize_last_digits(entry["last_digits"]),
            )
            if key in accounts and accounts[key] != entry["account"]:
                raise ValueError(
                    f"mapping.yaml: duplicate (institution={key.institution}, "
                    f"last_digits={key.last_digits}) maps to both "
                    f"{accounts[key]!r} and {entry['account']!r}"
                )
            accounts[key] = entry["account"]
        overrides = {
            str(k).strip(): v for k, v in (data.get("categories") or {}).items()
        }
        skip = {str(s).strip() for s in (data.get("skip_renamed_names") or [])}
        return cls(
            accounts=accounts,
            category_overrides=overrides,
            skip_renamed_names=skip,
        )

    def account_for_category(self, category: str) -> str:
        """Resolve a sheet `Category` value to a beancount account name."""
        if category in self.category_overrides:
            return self.category_overrides[category]
        if category.startswith(ACCOUNT_PREFIXES):
            return category
        return f"Expenses:{category}"


# ---------------------------------------------------------------------------
# Row classification
# ---------------------------------------------------------------------------


# Columns hashed to identify a row across runs. Stable subset of the sheet
# schema — adding a column here is a breaking change (existing inbox hashes
# will no longer match).
HASH_FIELDS = (
    "Date",
    "Payer",
    "Institution",
    "Account Last Digits",
    "Original Transaction Name",
    "Renamed Transaction Name",
    "Category",
    "Price",
    "Notes",
)


def row_hash(row: dict) -> str:
    """Stable short hash of a sheet row, used for cross-run dedup."""
    parts = [str(row.get(k, "")).strip() for k in HASH_FIELDS]
    digest = hashlib.sha256("\x1f".join(parts).encode("utf-8")).hexdigest()
    return digest[:16]


# "-$7.89" / "$5.00" / "1,234.56" / "-1234.56"
PRICE_RE = re.compile(r"^\s*(-)?\s*\$?\s*([0-9]{1,3}(?:,?[0-9]{3})*(?:\.[0-9]+)?)\s*$")


def parse_price(raw: str) -> Optional[Decimal]:
    m = PRICE_RE.match(str(raw))
    if not m:
        return None
    sign, body = m.groups()
    try:
        amount = Decimal(body.replace(",", ""))
    except InvalidOperation:
        return None
    return -amount if sign else amount


def parse_date(raw: str) -> Optional[str]:
    """Return YYYY-MM-DD or None. Accepts M/D/YYYY and YYYY-MM-DD."""
    s = str(raw).strip()
    for fmt in ("%m/%d/%Y", "%Y-%m-%d", "%m/%d/%y"):
        try:
            return datetime.strptime(s, fmt).date().isoformat()
        except ValueError:
            continue
    return None


@dataclass
class Classified:
    """One sheet row, classified for either import or skip."""

    sheet_row_idx: int  # 1-indexed spreadsheet row (header is row 1)
    raw: dict
    sheet_row_hash: str
    # "ready" — render emitted; "incomplete" / "bad_date" / "bad_price" /
    # "unknown_account" / "liability_not_open" / "skip_renamed" — skipped.
    status: str
    rendered: Optional[str] = None  # only when status == "ready"
    iso_date: Optional[str] = None  # only when status == "ready"


def classify_rows(
    records: list[dict],
    mapping: Mapping,
    open_accounts: set[str],
) -> list[Classified]:
    out = []
    for i, row in enumerate(records):
        sheet_row_idx = i + 2  # +1 for header, +1 for 1-indexed
        h = row_hash(row)
        renamed = str(row.get("Renamed Transaction Name", "")).strip()
        category = str(row.get("Category", "")).strip()
        original = str(row.get("Original Transaction Name", "")).strip()

        if renamed in mapping.skip_renamed_names:
            out.append(Classified(sheet_row_idx, row, h, "skip_renamed"))
            continue
        if not renamed or not category:
            out.append(Classified(sheet_row_idx, row, h, "incomplete"))
            continue

        iso_date = parse_date(row.get("Date", ""))
        if iso_date is None:
            out.append(Classified(sheet_row_idx, row, h, "bad_date"))
            continue

        amount = parse_price(row.get("Price", ""))
        if amount is None:
            out.append(Classified(sheet_row_idx, row, h, "bad_price"))
            continue

        ak = AccountKey.from_row(row)
        liability_account = mapping.accounts.get(ak)
        if liability_account is None:
            out.append(Classified(sheet_row_idx, row, h, "unknown_account"))
            continue

        # Defense in depth: if mapping.yaml points at a non-existent account,
        # skip the row rather than write a transaction that breaks fava load
        # for everything downstream.
        if liability_account not in open_accounts:
            log.warning(
                "row %d: liability %s is not opened in the ledger; "
                "fix mapping.yaml or open the account. Skipping.",
                sheet_row_idx, liability_account,
            )
            out.append(Classified(sheet_row_idx, row, h, "liability_not_open"))
            continue

        target_account = mapping.account_for_category(category)
        placeholder_category: Optional[str] = None
        if target_account not in open_accounts:
            # Either the user typed a placeholder (Savings, CreditCardPayOff,
            # etc.) or a real account that isn't opened yet. Either way: park
            # the entry on the placeholder account and tag the original
            # category in metadata so reconciliation is a grep away.
            placeholder_category = category
            target_account = PLACEHOLDER_ACCOUNT

        rendered = render_entry(
            iso_date=iso_date,
            payer=str(row.get("Payer", "")).strip(),
            payee=original,
            narration=renamed,
            notes=str(row.get("Notes", "")).strip(),
            liability_account=liability_account,
            amount=amount,
            target_account=target_account,
            sheet_row_hash=h,
            placeholder_category=placeholder_category,
        )
        out.append(
            Classified(
                sheet_row_idx, row, h, "ready",
                rendered=rendered, iso_date=iso_date,
            )
        )
    return out


# ---------------------------------------------------------------------------
# Beancount rendering
# ---------------------------------------------------------------------------


def beancount_quote(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def render_entry(
    *,
    iso_date: str,
    payer: str,
    payee: str,
    narration: str,
    notes: str,
    liability_account: str,
    amount: Decimal,
    target_account: str,
    sheet_row_hash: str,
    placeholder_category: Optional[str] = None,
) -> str:
    # 2 decimal places matches the existing ledger style.
    amount_s = f"{amount:.2f}"
    lines = [
        f'{iso_date} * "{beancount_quote(payee)}" "{beancount_quote(narration)}"',
        f'  payer: "{beancount_quote(payer)}"',
        f'  sheet_row_hash: "{sheet_row_hash}"',
    ]
    if placeholder_category is not None:
        lines.append(
            f'  placeholder_category: "{beancount_quote(placeholder_category)}"'
        )
    if notes:
        lines.append(f'  note: "{beancount_quote(notes)}"')
    lines.append(f"  {liability_account}  {amount_s} USD")
    lines.append(f"  {target_account}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Inbox file I/O
# ---------------------------------------------------------------------------


ENTRY_HEADER_RE = re.compile(r"^(\d{4}-\d{2}-\d{2}) \* ", re.MULTILINE)
HASH_META_RE = re.compile(
    r'^\s*sheet_row_hash:\s*"([0-9a-fA-F]+)"\s*$', re.MULTILINE
)
OPEN_RE = re.compile(r"^\d{4}-\d{2}-\d{2}\s+open\s+(\S+)", re.MULTILINE)


def collect_open_accounts(repo_root: Path) -> set[str]:
    """Walk every .beancount file under repo_root and collect open directives.

    Used to validate that an entry's target account is declared somewhere in
    the ledger before writing to inbox. Cheap regex scan, no full beancount
    load — order-of-magnitude faster and we don't need any of beancount's
    semantic checks here.
    """
    accounts: set[str] = set()
    for path in repo_root.rglob("*.beancount"):
        try:
            text = path.read_text()
        except OSError:
            continue
        accounts.update(OPEN_RE.findall(text))
    return accounts


@dataclass
class Entry:
    date: str
    text: str  # full entry text (no trailing blank line)
    sheet_row_hash: Optional[str] = None  # parsed from text if present


def read_existing_entries(path: Path) -> list[Entry]:
    """Parse the inbox file by splitting on dated transaction headers.

    Anything before the first dated header is treated as preamble and dropped
    (we re-emit our canonical header). Entries are blocks until the next
    dated header (or EOF). The sheet_row_hash metadata, if present, is
    extracted so callers can dedup against prior runs.
    """
    if not path.exists():
        return []
    text = path.read_text()
    starts = [(m.start(), m.group(1)) for m in ENTRY_HEADER_RE.finditer(text)]
    if not starts:
        return []
    entries = []
    for i, (start, date) in enumerate(starts):
        end = starts[i + 1][0] if i + 1 < len(starts) else len(text)
        block = text[start:end].rstrip()
        m = HASH_META_RE.search(block)
        entries.append(
            Entry(date=date, text=block, sheet_row_hash=m.group(1) if m else None)
        )
    return entries


def write_inbox(path: Path, entries: list[Entry]) -> None:
    """Sort and rewrite the inbox.

    Sort key is (date, sheet_row_hash) so same-day entries have a stable
    deterministic order across runs; this keeps the file diff-clean and
    lets `commit_and_push` correctly skip when nothing actually changed.
    """
    sorted_entries = sorted(entries, key=lambda e: (e.date, e.sheet_row_hash or ""))
    body = "\n\n".join(e.text for e in sorted_entries)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(INBOX_HEADER + body + "\n")


# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------


def run_git(args: list[str], cwd: Path, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=cwd, check=check, capture_output=True, text=True)


def setup_working_copy(repo_url: str) -> None:
    if not (WORK_DIR / ".git").is_dir():
        WORK_DIR.parent.mkdir(parents=True, exist_ok=True)
        log.info("cloning %s -> %s", scrub_url(repo_url), WORK_DIR)
        subprocess.run(
            ["git", "clone", "--quiet", "--branch", "main", repo_url, str(WORK_DIR)],
            check=True,
        )
    else:
        run_git(["remote", "set-url", "origin", repo_url], cwd=WORK_DIR)
        run_git(["fetch", "--quiet", "origin", "main"], cwd=WORK_DIR)
        run_git(["reset", "--hard", "--quiet", "origin/main"], cwd=WORK_DIR)
    # Pin author identity on this checkout (don't touch global config).
    run_git(["config", "user.name", GIT_AUTHOR_NAME], cwd=WORK_DIR)
    run_git(["config", "user.email", GIT_AUTHOR_EMAIL], cwd=WORK_DIR)


def scrub_url(url: str) -> str:
    """Strip credentials before logging."""
    return re.sub(r"://[^@/]+@", "://<redacted>@", url)


def commit_and_push(message: str) -> None:
    run_git(["add", INBOX_RELPATH], cwd=WORK_DIR)
    status = run_git(["status", "--porcelain", INBOX_RELPATH], cwd=WORK_DIR).stdout
    if not status.strip():
        log.info("inbox unchanged after rewrite; skipping commit")
        return
    run_git(["commit", "--quiet", "-m", message], cwd=WORK_DIR)
    run_git(["push", "--quiet", "origin", "main"], cwd=WORK_DIR)
    log.info("pushed: %s", message)


# ---------------------------------------------------------------------------
# Sheets I/O
# ---------------------------------------------------------------------------


def open_sheets() -> tuple[gspread.Worksheet, gspread.Worksheet]:
    creds = Credentials.from_service_account_file(
        str(SERVICE_ACCOUNT_FILE), scopes=GSPREAD_SCOPES
    )
    gc = gspread.authorize(creds)
    sh = gc.open_by_key(SHEET_ID)
    return sh.worksheet(MAIN_TAB), sh.worksheet(HISTORY_TAB)


def move_rows_to_history(
    main_ws: gspread.Worksheet,
    history_ws: gspread.Worksheet,
    rows: list[Classified],
) -> None:
    """Append rows to History (with Imported At) then delete from main.

    Both halves are idempotent so a previous run that crashed mid-cleanup
    (e.g. a 429 from Sheets' 60-write/min/user quota partway through
    delete_rows) can be safely re-run without producing duplicates:

      * History append dedupes against rows already in History by
        recomputing row_hash() on each existing History record (the
        History tab carries the same columns as Expenses plus an
        Imported At column, so the hash inputs are identical).
      * Deletions are coalesced into contiguous range requests and sent
        as a single batch_update HTTP call rather than ~N individual
        delete_rows calls. Naive per-row deletion blew the per-minute
        write quota on the first run with ~170 rows.
    """
    if not rows:
        return

    # Idempotency for the append: skip rows whose hash already lives in
    # History. Cheap one read API call regardless of row count.
    history_records = history_ws.get_all_records()
    existing_history_hashes = {row_hash(r) for r in history_records}

    todo = [c for c in rows if c.sheet_row_hash not in existing_history_hashes]
    if todo:
        timestamp = datetime.now(timezone.utc).isoformat(timespec="seconds")
        main_header = main_ws.row_values(1)
        history_rows = [
            [str(c.raw.get(col, "")) for col in main_header] + [timestamp]
            for c in todo
        ]
        try:
            history_ws.append_rows(history_rows, value_input_option="RAW")
            log.info("appended %d rows to %s", len(history_rows), HISTORY_TAB)
        except Exception:
            log.exception(
                "FAILED to append rows to %s; next run will retry idempotently.",
                HISTORY_TAB,
            )
            raise
    else:
        log.info(
            "all %d ready rows already in %s; skipping append",
            len(rows), HISTORY_TAB,
        )

    # Coalesce contiguous main-tab indices into ranges and apply
    # highest-first so earlier indices stay valid as later ranges shift up.
    # Single batch_update call regardless of how many ranges.
    sorted_idx = sorted({c.sheet_row_idx for c in rows})
    ranges: list[list[int]] = []  # inclusive 1-based [start, end] pairs
    for idx in sorted_idx:
        if ranges and idx == ranges[-1][1] + 1:
            ranges[-1][1] = idx
        else:
            ranges.append([idx, idx])
    ranges.sort(reverse=True)
    requests = [
        {
            "deleteDimension": {
                "range": {
                    "sheetId": main_ws.id,
                    "dimension": "ROWS",
                    "startIndex": start - 1,  # API uses 0-based half-open
                    "endIndex": end,
                }
            }
        }
        for start, end in ranges
    ]
    try:
        main_ws.spreadsheet.batch_update({"requests": requests})
        log.info(
            "removed %d rows from %s in %d range(s) via 1 batch_update call",
            sum(e - s + 1 for s, e in ranges),
            MAIN_TAB,
            len(ranges),
        )
    except Exception:
        log.exception(
            "FAILED to delete rows from %s. Those rows will reappear as "
            "ready next run; inbox hash-dedup + History append idempotency "
            "above keep the retry safe (no duplicate inbox/History entries).",
            MAIN_TAB,
        )
        raise


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> int:
    # quote() because admin passwords aren't constrained to URL-safe charsets;
    # leaving raw `:` or `@` in there would corrupt the userinfo segment.
    password = urllib.parse.quote(
        FORGEJO_PASSWORD_FILE.read_text().strip(), safe=""
    )
    repo_url = f"https://{REPO_USER}:{password}@{REPO_HOST}/{REPO_PATH}"
    setup_working_copy(repo_url)

    mapping_path = WORK_DIR / MAPPING_RELPATH
    if not mapping_path.exists():
        log.error("mapping file missing: %s", mapping_path)
        return 1
    mapping = Mapping.load(mapping_path)
    log.info(
        "mapping loaded: %d accounts, %d category overrides",
        len(mapping.accounts),
        len(mapping.category_overrides),
    )

    open_accounts = collect_open_accounts(WORK_DIR)
    log.info("found %d open account directives in ledger", len(open_accounts))
    if PLACEHOLDER_ACCOUNT not in open_accounts:
        log.warning(
            "%s is not opened in the ledger; rows whose target account is "
            "missing will produce entries that fail to load. Add an `open` "
            "directive (e.g. in common/src/accounts.beancount).",
            PLACEHOLDER_ACCOUNT,
        )

    main_ws, history_ws = open_sheets()
    records = main_ws.get_all_records()
    log.info("read %d rows from %s", len(records), MAIN_TAB)
    if not records:
        return 0

    classified = classify_rows(records, mapping, open_accounts)

    counts = {}
    for c in classified:
        counts[c.status] = counts.get(c.status, 0) + 1
    log.info("classification: %s", counts)

    ready = [c for c in classified if c.status == "ready"]
    if not ready:
        return 0

    inbox_path = WORK_DIR / INBOX_RELPATH
    existing = read_existing_entries(inbox_path)
    existing_hashes = {e.sheet_row_hash for e in existing if e.sheet_row_hash}

    # Rows whose hash is already in inbox are leftovers from a prior run that
    # pushed but failed to drain the sheet — don't re-import them, but DO
    # move them to History on this run so the sheet eventually catches up.
    to_write = [c for c in ready if c.sheet_row_hash not in existing_hashes]
    skipped_dupes = len(ready) - len(to_write)
    if skipped_dupes:
        log.info(
            "skipping %d row(s) already in inbox (carry-over from a prior run "
            "where move-to-history failed); will retry move this run",
            skipped_dupes,
        )

    if to_write:
        new_entries = [
            Entry(date=c.iso_date, text=c.rendered, sheet_row_hash=c.sheet_row_hash)
            for c in to_write
        ]
        write_inbox(inbox_path, existing + new_entries)
        dates = sorted({e.date for e in new_entries})
        span = dates[0] if len(dates) == 1 else f"{dates[0]}..{dates[-1]}"
        commit_and_push(f"etl: import {len(new_entries)} transactions ({span})")
    else:
        log.info("no new entries to write; only retrying move-to-history")

    move_rows_to_history(main_ws, history_ws, ready)
    return 0


if __name__ == "__main__":
    sys.exit(main())
