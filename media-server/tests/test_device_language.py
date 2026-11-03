import sqlite3

import chat


def test_a_device_keeps_the_language_it_registered_with(tmp_path):
    db = chat.ChatDatabase(tmp_path / "chat.db")
    db.register_device_token("uid1", "tok-bn", device_id="phone-1", language="bn-BD")
    db.register_device_token("uid1", "tok-fr", device_id="phone-2", language="fr")

    by_token = {t["token"]: t["language"] for t in db.get_device_tokens("uid1")}
    assert by_token == {"tok-bn": "bn", "tok-fr": "en"}


def test_a_device_without_a_language_gets_english(tmp_path):
    db = chat.ChatDatabase(tmp_path / "chat.db")
    db.register_device_token("uid2", "tok-old", device_id="phone-1")

    assert db.get_device_tokens("uid2") == [
        {"token": "tok-old", "platform": "unknown", "language": "en"}
    ]


def test_a_new_registration_updates_the_language(tmp_path):
    db = chat.ChatDatabase(tmp_path / "chat.db")
    db.register_device_token("uid3", "tok", device_id="phone", language="en")
    db.register_device_token("uid3", "tok", device_id="phone", language="bn")

    assert db.get_device_tokens("uid3")[0]["language"] == "bn"


def test_an_older_database_gets_the_language_column(tmp_path):
    path = tmp_path / "chat.db"
    conn = sqlite3.connect(path)
    conn.executescript(
        """
        CREATE TABLE device_tokens (
            uid TEXT NOT NULL,
            device_id TEXT NOT NULL,
            token TEXT NOT NULL,
            email TEXT,
            platform TEXT,
            updated_at INTEGER NOT NULL,
            PRIMARY KEY (uid, device_id)
        );
        INSERT INTO device_tokens VALUES ('uid4', 'phone', 'tok-old', '', 'android', 1);
        """
    )
    conn.commit()
    conn.close()

    db = chat.ChatDatabase(path)

    columns = {row[1] for row in sqlite3.connect(path).execute("PRAGMA table_info(device_tokens)")}
    assert "language" in columns
    assert db.get_device_tokens("uid4")[0]["language"] == "en"
