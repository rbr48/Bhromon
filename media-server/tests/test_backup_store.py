"""The backup script keeps a consistent copy of the databases and the metadata, and prunes old runs."""

import sqlite3
import tarfile
from pathlib import Path

import backup_store

DAY = 86400
START = 1_700_000_000


def make_store(root: Path) -> Path:
    meta = root / "meta"
    (meta / "t1" / "posts").mkdir(parents=True)
    (meta / "t1" / "posts" / "a.jpg.json").write_text('{"uploaderEmail": "a@x.com"}')
    db = sqlite3.connect(meta / "bhromon_chat.db")
    db.execute("CREATE TABLE messages (id TEXT)")
    db.execute("INSERT INTO messages VALUES ('m1')")
    db.commit()
    db.close()
    return meta


def test_a_run_holds_a_consistent_copy_of_the_databases_and_the_metadata(tmp_path):
    meta = make_store(tmp_path)
    media = tmp_path / "media"
    (media / "t1").mkdir(parents=True)
    (media / "t1" / "x.jpg").write_bytes(b"x")

    run = backup_store.run_backup(meta, media, tmp_path / "dest", keep=5, include_media=True, now=START)

    copy = sqlite3.connect(run / "databases" / "bhromon_chat.db")
    assert copy.execute("SELECT id FROM messages").fetchall() == [("m1",)]
    copy.close()
    with tarfile.open(run / "metadata.tar.gz") as tar:
        names = tar.getnames()
    assert "meta/t1/posts/a.jpg.json" in names
    assert not [name for name in names if name.endswith(backup_store.DATABASE_SUFFIXES)]
    assert (run / "media.tar.gz").is_file()


def test_media_is_left_out_unless_asked_for(tmp_path):
    meta = make_store(tmp_path)
    run = backup_store.run_backup(meta, tmp_path / "media", tmp_path / "dest", keep=5, include_media=False, now=START)
    assert not (run / "media.tar.gz").exists()


def test_old_runs_are_pruned_and_the_newest_are_kept(tmp_path):
    meta = make_store(tmp_path)
    dest = tmp_path / "dest"
    for day in range(1, 6):
        backup_store.run_backup(meta, tmp_path / "media", dest, keep=3, include_media=False, now=START + day * DAY)
    kept = sorted(p.name for p in dest.iterdir())
    assert len(kept) == 3
    assert kept == sorted(backup_store._stamp(START + day * DAY) for day in (3, 4, 5))


def test_keeping_no_runs_is_refused(tmp_path):
    try:
        backup_store.prune(tmp_path, 0)
    except ValueError:
        return
    raise AssertionError("prune should refuse to keep zero runs")


def test_a_missing_metadata_folder_is_reported(tmp_path):
    assert backup_store.main(["--meta-root", str(tmp_path / "nope"), "--dest", str(tmp_path / "d")]) == 1
