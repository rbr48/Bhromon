"""Bhromon Quiz Engine & REST API.

Provides high-performance, server-rendered travel quizzes with 1000+ authentic,
verified questions on Bangladesh tourism, geography, culture, historical sites,
trails, nature, cuisine, and eco-travel safety.
Bypasses Firebase Firestore rate limits by using persistent SQLite (WAL mode).
"""

import json
import logging
import os
import sqlite3
import threading
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Query
from pydantic import BaseModel, Field

logger = logging.getLogger("bhromon-quiz")

META_ROOT = Path(os.getenv("MEDIA_META_ROOT", "/data/media-meta"))
QUIZ_DB_PATH = Path(os.getenv("QUIZ_DB_PATH", str(META_ROOT / "bhromon_quiz.db")))


def _now_ms() -> int:
    return int(time.time() * 1000)


class QuizDatabase:
    """Thread-safe SQLite storage for quizzes and quiz histories."""

    def __init__(self, db_path: str | Path) -> None:
        self.db_path = str(db_path)
        os.makedirs(os.path.dirname(os.path.abspath(self.db_path)), exist_ok=True)
        self._local = threading.local()
        self._init_schema()

    def _get_conn(self) -> sqlite3.Connection:
        if not hasattr(self._local, "conn") or self._local.conn is None:
            conn = sqlite3.connect(self.db_path, timeout=30.0)
            conn.row_factory = sqlite3.Row
            conn.execute("PRAGMA journal_mode=WAL;")
            conn.execute("PRAGMA synchronous=NORMAL;")
            self._local.conn = conn
        return self._local.conn

    def _init_schema(self) -> None:
        conn = self._get_conn()
        with conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS quizzes (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    category TEXT NOT NULL,
                    destination_tag TEXT NOT NULL DEFAULT 'all',
                    difficulty TEXT NOT NULL DEFAULT 'medium',
                    question_bn TEXT NOT NULL,
                    options_bn TEXT NOT NULL,
                    correct_index INTEGER NOT NULL,
                    explanation_bn TEXT NOT NULL,
                    question_en TEXT,
                    options_en TEXT,
                    explanation_en TEXT,
                    created_at INTEGER NOT NULL
                );

                CREATE TABLE IF NOT EXISTS quiz_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_uid TEXT NOT NULL,
                    user_name TEXT,
                    tour_id TEXT,
                    score INTEGER NOT NULL,
                    total INTEGER NOT NULL,
                    category TEXT,
                    destination TEXT,
                    created_at INTEGER NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_quizzes_dest ON quizzes(destination_tag);
                CREATE INDEX IF NOT EXISTS idx_quizzes_cat ON quizzes(category);
                CREATE INDEX IF NOT EXISTS idx_quizzes_diff ON quizzes(difficulty);
                CREATE INDEX IF NOT EXISTS idx_quiz_hist_user ON quiz_history(user_uid);
                CREATE INDEX IF NOT EXISTS idx_quiz_hist_created ON quiz_history(created_at DESC);
                """
            )

    def count_questions(self) -> int:
        conn = self._get_conn()
        cur = conn.cursor()
        cur.execute("SELECT COUNT(*) AS total FROM quizzes")
        row = cur.fetchone()
        return int(row["total"]) if row else 0

    def insert_question(
        self,
        category: str,
        question_bn: str,
        options_bn: List[str],
        correct_index: int,
        explanation_bn: str,
        destination_tag: str = "all",
        difficulty: str = "medium",
        question_en: Optional[str] = None,
        options_en: Optional[List[str]] = None,
        explanation_en: Optional[str] = None,
    ) -> int:
        conn = self._get_conn()
        with conn:
            cur = conn.cursor()
            cur.execute(
                """
                INSERT INTO quizzes (
                    category, destination_tag, difficulty, question_bn, options_bn,
                    correct_index, explanation_bn, question_en, options_en, explanation_en, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    category.strip().lower(),
                    destination_tag.strip().lower(),
                    difficulty.strip().lower(),
                    question_bn.strip(),
                    json.dumps(options_bn, ensure_ascii=False),
                    correct_index,
                    explanation_bn.strip(),
                    question_en.strip() if question_en else None,
                    json.dumps(options_en, ensure_ascii=False) if options_en else None,
                    explanation_en.strip() if explanation_en else None,
                    _now_ms(),
                ),
            )
            return cur.lastrowid

    def bulk_insert_questions(self, questions: List[Dict[str, Any]]) -> int:
        conn = self._get_conn()
        now = _now_ms()
        rows = []
        for q in questions:
            rows.append(
                (
                    str(q.get("category", "general_travel")).strip().lower(),
                    str(q.get("destination_tag", "all")).strip().lower(),
                    str(q.get("difficulty", "medium")).strip().lower(),
                    str(q["question_bn"]).strip(),
                    json.dumps(q["options_bn"], ensure_ascii=False)
                    if isinstance(q["options_bn"], list)
                    else str(q["options_bn"]),
                    int(q["correct_index"]),
                    str(q.get("explanation_bn", "")).strip(),
                    q.get("question_en"),
                    json.dumps(q["options_en"], ensure_ascii=False)
                    if q.get("options_en")
                    else None,
                    q.get("explanation_en"),
                    now,
                )
            )
        with conn:
            cur = conn.cursor()
            cur.executemany(
                """
                INSERT INTO quizzes (
                    category, destination_tag, difficulty, question_bn, options_bn,
                    correct_index, explanation_bn, question_en, options_en, explanation_en, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                rows,
            )
            return len(rows)

    def get_questions(
        self,
        destination: Optional[str] = None,
        category: Optional[str] = None,
        difficulty: Optional[str] = None,
        limit: int = 10,
    ) -> List[Dict[str, Any]]:
        conn = self._get_conn()
        cur = conn.cursor()
        dest_clean = destination.strip().lower() if destination else None
        cat_clean = category.strip().lower() if category else None
        diff_clean = difficulty.strip().lower() if difficulty else None

        results: List[sqlite3.Row] = []

        # 1. If destination is requested, try exact or partial match first
        if dest_clean and dest_clean != "all":
            dest_query = """
                SELECT * FROM quizzes
                WHERE (destination_tag = ? OR ? LIKE '%' || destination_tag || '%')
            """
            params: List[Any] = [dest_clean, dest_clean]
            if diff_clean:
                dest_query += " AND difficulty = ?"
                params.append(diff_clean)
            dest_query += " ORDER BY RANDOM() LIMIT ?"
            params.append(limit)

            cur.execute(dest_query, params)
            results.extend(cur.fetchall())

        # 2. If we need more questions to reach `limit`, fill from category or general
        if len(results) < limit:
            remaining = limit - len(results)
            existing_ids = [r["id"] for r in results]
            placeholders = ",".join("?" for _ in existing_ids) if existing_ids else "0"

            fill_query = f"""
                SELECT * FROM quizzes
                WHERE id NOT IN ({placeholders})
            """
            fill_params: List[Any] = list(existing_ids)

            if cat_clean and cat_clean != "all":
                fill_query += " AND category = ?"
                fill_params.append(cat_clean)
            if diff_clean:
                fill_query += " AND difficulty = ?"
                fill_params.append(diff_clean)

            fill_query += " ORDER BY RANDOM() LIMIT ?"
            fill_params.append(remaining)

            cur.execute(fill_query, fill_params)
            results.extend(cur.fetchall())

        output = []
        for r in results:
            options_bn = []
            try:
                options_bn = json.loads(r["options_bn"])
            except Exception:
                options_bn = [r["options_bn"]]

            options_en = None
            if r["options_en"]:
                try:
                    options_en = json.loads(r["options_en"])
                except Exception:
                    options_en = None

            output.append(
                {
                    "id": r["id"],
                    "category": r["category"],
                    "destination_tag": r["destination_tag"],
                    "difficulty": r["difficulty"],
                    "question_bn": r["question_bn"],
                    "options_bn": options_bn,
                    "correct_index": r["correct_index"],
                    "explanation_bn": r["explanation_bn"],
                    "question_en": r["question_en"],
                    "options_en": options_en,
                    "explanation_en": r["explanation_en"],
                }
            )
        return output

    def get_categories_summary(self) -> Dict[str, Any]:
        conn = self._get_conn()
        cur = conn.cursor()
        cur.execute(
            """
            SELECT category, COUNT(*) as count
            FROM quizzes
            GROUP BY category
            ORDER BY count DESC
            """
        )
        cat_rows = cur.fetchall()

        cur.execute(
            """
            SELECT destination_tag, COUNT(*) as count
            FROM quizzes
            WHERE destination_tag != 'all'
            GROUP BY destination_tag
            ORDER BY count DESC
            LIMIT 25
            """
        )
        dest_rows = cur.fetchall()

        cur.execute("SELECT COUNT(*) as total FROM quizzes")
        total_q = cur.fetchone()["total"]

        return {
            "total_questions": total_q,
            "categories": [{"name": r["category"], "count": r["count"]} for r in cat_rows],
            "popular_destinations": [
                {"destination": r["destination_tag"], "count": r["count"]} for r in dest_rows
            ],
        }

    def record_attempt(
        self,
        user_uid: str,
        user_name: Optional[str],
        tour_id: Optional[str],
        score: int,
        total: int,
        category: Optional[str],
        destination: Optional[str],
    ) -> int:
        conn = self._get_conn()
        with conn:
            cur = conn.cursor()
            cur.execute(
                """
                INSERT INTO quiz_history (
                    user_uid, user_name, tour_id, score, total, category, destination, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    user_uid,
                    user_name or "ভ্রমণকারী",
                    tour_id,
                    score,
                    total,
                    category,
                    destination,
                    _now_ms(),
                ),
            )
            return cur.lastrowid

    def get_leaderboard(self, limit: int = 20) -> List[Dict[str, Any]]:
        conn = self._get_conn()
        cur = conn.cursor()
        cur.execute(
            """
            SELECT
                user_uid,
                user_name,
                SUM(score) AS total_score,
                COUNT(*) AS games_played,
                MAX(score * 1.0 / total) AS best_accuracy
            FROM quiz_history
            GROUP BY user_uid
            ORDER BY total_score DESC, games_played DESC
            LIMIT ?
            """,
            (limit,),
        )
        rows = cur.fetchall()
        return [
            {
                "user_uid": r["user_uid"],
                "user_name": r["user_name"],
                "total_score": r["total_score"],
                "games_played": r["games_played"],
                "best_accuracy": round(float(r["best_accuracy"] or 0) * 100, 1),
            }
            for r in rows
        ]


quiz_db = QuizDatabase(QUIZ_DB_PATH)
quiz_router = APIRouter(tags=["quiz"])


# ── Pydantic Request Models ───────────────────────────────────────────────────


class QuizSubmitRequest(BaseModel):
    user_uid: str
    user_name: Optional[str] = None
    tour_id: Optional[str] = None
    score: int = Field(..., ge=0)
    total: int = Field(..., gt=0)
    category: Optional[str] = None
    destination: Optional[str] = None


class SingleQuestionCreate(BaseModel):
    category: str
    destination_tag: str = "all"
    difficulty: str = "medium"
    question_bn: str
    options_bn: List[str]
    correct_index: int
    explanation_bn: str
    question_en: Optional[str] = None
    options_en: Optional[List[str]] = None
    explanation_en: Optional[str] = None


# ── Endpoints ─────────────────────────────────────────────────────────────────


@quiz_router.get("/questions")
def get_quiz_questions(
    destination: Optional[str] = Query(None, description="Destination filter (e.g. sajek, coxs_bazar, sylhet)"),
    category: Optional[str] = Query(None, description="Category filter"),
    difficulty: Optional[str] = Query(None, description="easy, medium, or hard"),
    limit: int = Query(10, ge=1, le=50, description="Number of questions"),
):
    """Fetches randomized travel quiz questions matching destination or category."""
    questions = quiz_db.get_questions(
        destination=destination,
        category=category,
        difficulty=difficulty,
        limit=limit,
    )
    return {
        "status": "success",
        "count": len(questions),
        "destination": destination,
        "category": category,
        "questions": questions,
    }


@quiz_router.get("/categories")
def get_categories():
    """Returns categories summary, question counts, and destinations."""
    return {
        "status": "success",
        "data": quiz_db.get_categories_summary(),
    }


@quiz_router.post("/submit")
def submit_quiz_attempt(req: QuizSubmitRequest):
    """Submits a quiz score and records it in history."""
    attempt_id = quiz_db.record_attempt(
        user_uid=req.user_uid,
        user_name=req.user_name,
        tour_id=req.tour_id,
        score=req.score,
        total=req.total,
        category=req.category,
        destination=req.destination,
    )
    accuracy = round((req.score / req.total) * 100, 1)

    # Determine achievement badge
    badge = "অভিযাত্রী"
    if accuracy >= 90:
        badge = "কুইজ মাস্টার 🏆"
    elif accuracy >= 70:
        badge = "ভ্রমণ বিশেষজ্ঞ 🌟"
    elif accuracy >= 50:
        badge = "উৎসুক পরিব্রাজক 🧭"

    return {
        "status": "success",
        "attempt_id": attempt_id,
        "score": req.score,
        "total": req.total,
        "accuracy_percent": accuracy,
        "badge": badge,
    }


@quiz_router.get("/leaderboard")
def get_leaderboard(limit: int = Query(20, ge=1, le=100)):
    """Returns top quiz champions."""
    return {
        "status": "success",
        "leaderboard": quiz_db.get_leaderboard(limit=limit),
    }


@quiz_router.get("/stats")
def get_quiz_stats():
    """Returns total question count and database statistics."""
    return {
        "status": "success",
        "total_questions": quiz_db.count_questions(),
    }
