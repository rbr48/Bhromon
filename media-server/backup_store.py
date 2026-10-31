"""Copies the media server's databases, upload metadata and, optionally, its files.

    python3 backup_store.py --dest /var/backups/bhromon --keep 14 --include-media

Each run writes one folder named by the time it started. Every SQLite database under
the metadata root is copied with SQLite's online backup, so the copy is consistent
even while the server is writing. The metadata is archived without the database
files, which are only copied through that backup. The newest --keep runs are kept
and older ones are deleted.

Keep the destination on another disk or host. A copy beside the data does not
survive the loss of the disk.
"""

import argparse
import os
import sqlite3
import sys
import tarfile
import time
from contextlib import closing
from pathlib import Path
from typing import List, Optional

DATABASE_SUFFIXES = (".db", ".db-wal", ".db-shm")


def _stamp(now: Optional[float] = None) -> str:
    return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime(now if now is not None else time.time()))


def copy_databases(meta_root: Path, target: Path) -> List[Path]:
    """Writes a consistent copy of every SQLite database under `meta_root` into `target`."""
    copies: List[Path] = []
    for source in sorted(meta_root.rglob("*.db")):
        destination = target / source.relative_to(meta_root)
        destination.parent.mkdir(parents=True, exist_ok=True)
        with closing(sqlite3.connect(source)) as source_conn, closing(sqlite3.connect(destination)) as dest_conn:
            source_conn.backup(dest_conn)
        copies.append(destination)
    return copies


def _skip_databases(info: tarfile.TarInfo) -> Optional[tarfile.TarInfo]:
    return None if info.name.endswith(DATABASE_SUFFIXES) else info


def archive(source: Path, destination: Path, skip_databases: bool = False) -> Path:
    """Writes `source` as a gzip tar. With skip_databases, SQLite files are left out."""
    with tarfile.open(destination, "w:gz") as tar:
        tar.add(source, arcname=source.name, filter=_skip_databases if skip_databases else None)
    return destination


def prune(dest_root: Path, keep: int) -> List[Path]:
    """Deletes all but the newest `keep` backup folders. Returns the folders removed."""
    if keep < 1:
        raise ValueError("Keep at least one backup.")
    runs = sorted((p for p in dest_root.iterdir() if p.is_dir()), key=lambda p: p.name)
    removed = runs[: max(0, len(runs) - keep)]
    for run in removed:
        for path in sorted(run.rglob("*"), key=lambda p: len(p.parts), reverse=True):
            if path.is_file():
                path.unlink()
            else:
                path.rmdir()
        run.rmdir()
    return removed


def run_backup(
    meta_root: Path,
    media_root: Path,
    dest_root: Path,
    keep: int,
    include_media: bool,
    now: Optional[float] = None,
) -> Path:
    """Makes one backup run under `dest_root` and prunes the old ones. Returns the run's folder."""
    dest_root.mkdir(parents=True, exist_ok=True)
    run = dest_root / _stamp(now)
    run.mkdir()
    copy_databases(meta_root, run / "databases")
    archive(meta_root, run / "metadata.tar.gz", skip_databases=True)
    if include_media and media_root.is_dir():
        archive(media_root, run / "media.tar.gz")
    prune(dest_root, keep)
    return run


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--meta-root", default=os.getenv("MEDIA_META_ROOT", "/data/media-meta"))
    parser.add_argument("--media-root", default=os.getenv("MEDIA_ROOT", "/data/media"))
    parser.add_argument("--dest", required=True, help="Folder that receives the backup runs.")
    parser.add_argument("--keep", type=int, default=14, help="How many runs to keep.")
    parser.add_argument("--include-media", action="store_true", help="Also archive the uploaded files.")
    args = parser.parse_args(argv)

    meta_root = Path(args.meta_root)
    if not meta_root.is_dir():
        print(f"No metadata folder at {meta_root}.", file=sys.stderr)
        return 1
    run = run_backup(
        meta_root=meta_root,
        media_root=Path(args.media_root),
        dest_root=Path(args.dest),
        keep=args.keep,
        include_media=args.include_media,
    )
    print(f"Backup written to {run}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
