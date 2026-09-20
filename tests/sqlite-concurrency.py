#!/usr/bin/env python3
"""Exercise the shipped SQLite schema with concurrent short-lived writers.

This is a release-validation helper, not a runtime component.  It uses only the
Python standard library so the schema and WAL behaviour can still be tested in a
build environment where the Perl DBI/DBD::SQLite modules are unavailable.

Each worker opens its own connection, mirroring separate nnrpd processes.  Every
article is inserted in a short BEGIN IMMEDIATE/COMMIT transaction.  The helper
reports any SQLITE_BUSY/locked failures and verifies the exact final row count.
The release suite deliberately invokes a moderate concurrency smoke profile;
larger --workers/--articles-per-worker values are useful as host-specific soak
tests but are not portable pass/fail criteria because storage latency varies.
"""

from __future__ import annotations

import argparse
import json
import multiprocessing as mp
import sqlite3
import tempfile
import time
from pathlib import Path
from typing import Any


def apply_migrations(database_path: Path, migrations_directory: Path) -> None:
    """Create a new database by applying every shipped SQL migration in order."""

    connection = sqlite3.connect(database_path)
    try:
        for migration in sorted(migrations_directory.glob("[0-9][0-9][0-9]-*.sql")):
            connection.executescript(migration.read_text(encoding="utf-8"))
        connection.execute("PRAGMA journal_mode=WAL")
        connection.execute("PRAGMA synchronous=FULL")
        connection.commit()
    finally:
        connection.close()


def writer(
    database_path: str,
    worker_number: int,
    article_count: int,
    result_queue: mp.Queue,
) -> None:
    """Insert one worker's events and return failures/maximum transaction time."""

    connection = sqlite3.connect(database_path, timeout=10.0, isolation_level=None)
    connection.execute("PRAGMA busy_timeout=10000")
    connection.execute("PRAGMA journal_mode=WAL")

    failures: list[str] = []
    maximum_latency_ms = 0.0

    try:
        for sequence in range(article_count):
            article_type = "binary" if (worker_number + sequence) % 2 else "text"
            started = time.perf_counter()
            try:
                connection.execute("BEGIN IMMEDIATE")
                connection.execute(
                    """
                    INSERT INTO article_events(
                        received_at,
                        message_id,
                        message_id_hash,
                        article_type,
                        group_count,
                        followup_count,
                        body_size,
                        header_size,
                        total_size,
                        technical_verdict,
                        final_action,
                        nntp_result,
                        reason_code,
                        legacy_code,
                        audit_mode,
                        would_reject,
                        tor
                    ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    """,
                    (
                        time.time(),
                        f"<stress-{worker_number}-{sequence}@example.invalid>",
                        f"stress-{worker_number}-{sequence}",
                        article_type,
                        1,
                        0,
                        10_485_760 if article_type == "binary" else 1024,
                        512,
                        10_486_272 if article_type == "binary" else 1536,
                        "pass",
                        "accept",
                        "accepted",
                        "PF-ACCEPT-000",
                        0,
                        0,
                        0,
                        0,
                    ),
                )
                connection.execute("COMMIT")
            except Exception as error:  # pragma: no cover - reported to parent
                try:
                    connection.execute("ROLLBACK")
                except sqlite3.Error:
                    pass
                failures.append(f"{type(error).__name__}: {error}")

            elapsed_ms = (time.perf_counter() - started) * 1000.0
            maximum_latency_ms = max(maximum_latency_ms, elapsed_ms)
    finally:
        connection.close()

    result_queue.put(
        {
            "failures": failures,
            "maximum_latency_ms": maximum_latency_ms,
            "worker": worker_number,
        }
    )


def run(root: Path, workers: int, articles_per_worker: int) -> dict[str, Any]:
    """Run the complete stress test and return a JSON-serialisable summary."""

    with tempfile.TemporaryDirectory(prefix="postfilter-sqlite-stress-") as directory:
        database_path = Path(directory) / "postfilter.sqlite3"
        apply_migrations(database_path, root / "migrations")

        queue: mp.Queue = mp.Queue()
        processes = [
            mp.Process(
                target=writer,
                args=(str(database_path), worker, articles_per_worker, queue),
            )
            for worker in range(workers)
        ]

        started = time.perf_counter()
        for process in processes:
            process.start()
        for process in processes:
            process.join()

        results = [queue.get() for _ in processes]
        elapsed_seconds = time.perf_counter() - started
        failures = [failure for result in results for failure in result["failures"]]

        connection = sqlite3.connect(database_path)
        try:
            row_count = connection.execute(
                "SELECT COUNT(*) FROM article_events"
            ).fetchone()[0]
            type_counts = dict(
                connection.execute(
                    "SELECT article_type, COUNT(*) FROM article_events GROUP BY article_type"
                ).fetchall()
            )

            # Exercise the independently typed saved-article metadata added by
            # migration 004.  The paths are diagnostic placeholders inside the
            # temporary test database; no article files are created.
            for article_type in ("text", "binary"):
                event_id = connection.execute(
                    "SELECT MIN(id) FROM article_events WHERE article_type = ?",
                    (article_type,),
                ).fetchone()[0]
                connection.execute(
                    """
                    INSERT INTO saved_articles(
                        event_id,
                        article_type,
                        path,
                        file_sha256,
                        file_size,
                        created_at
                    ) VALUES(?,?,?,?,?,?)
                    """,
                    (
                        event_id,
                        article_type,
                        f"/{article_type}/diagnostic.post",
                        article_type * 32,
                        1024,
                        time.time(),
                    ),
                )
            connection.commit()
            saved_type_counts = dict(
                connection.execute(
                    "SELECT article_type, COUNT(*) FROM saved_articles GROUP BY article_type"
                ).fetchall()
            )
            integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        finally:
            connection.close()

        expected = workers * articles_per_worker
        return {
            "articles_per_worker": articles_per_worker,
            "elapsed_seconds": elapsed_seconds,
            "expected_rows": expected,
            "failures": failures,
            "integrity_check": integrity,
            "maximum_transaction_latency_ms": max(
                result["maximum_latency_ms"] for result in results
            ),
            "ok": not failures and row_count == expected and integrity == "ok",
            "row_count": row_count,
            "saved_type_counts": saved_type_counts,
            "type_counts": type_counts,
            "workers": workers,
        }


def main() -> int:
    """Parse command-line options, execute the stress test and print JSON."""

    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--workers", type=int, default=16)
    parser.add_argument("--articles-per-worker", type=int, default=100)
    arguments = parser.parse_args()

    summary = run(
        arguments.root.resolve(),
        max(1, arguments.workers),
        max(1, arguments.articles_per_worker),
    )
    print(json.dumps(summary, indent=2, sort_keys=True))
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
