"""Script to seed 1,000 completely unique travel quiz questions for Bhromon.

100% Unique, authentic, verified questions across:
- 64 Districts of Bangladesh (320 questions)
- Hills, Treks, Beaches & Islands (220 questions)
- Nature, Forests, Rivers, Wetlands & Heritage Architecture (260 questions)
- Regional Foods, GI Products & Outdoor Wilderness Safety (200 questions)

ZERO Repetition, ZERO templated prefix wrappers!
"""

import argparse
import json
import os
import sys
from pathlib import Path

# Add current directory to path
sys.path.insert(0, str(Path(__file__).parent))

from quiz import QuizDatabase, QUIZ_DB_PATH
from quiz_data_districts import DISTRICTS_QUESTIONS
from quiz_data_hills_beaches import HILLS_BEACHES_QUESTIONS
from quiz_data_nature_heritage import NATURE_HERITAGE_QUESTIONS
from quiz_data_food_safety import FOOD_SAFETY_QUESTIONS


def get_all_1000_unique_questions():
    """Combines all four modular quiz packages and strictly validates 100% uniqueness."""
    all_questions = (
        DISTRICTS_QUESTIONS
        + HILLS_BEACHES_QUESTIONS
        + NATURE_HERITAGE_QUESTIONS
        + FOOD_SAFETY_QUESTIONS
    )

    total_count = len(all_questions)
    assert total_count == 1000, f"Expected exactly 1000 questions, got {total_count}"

    seen_texts = set()
    for idx, q in enumerate(all_questions):
        text = q.get("question_bn", "").strip()
        assert text, f"Empty question text at index {idx}"
        assert text not in seen_texts, f"Duplicate question detected: {text}"
        seen_texts.add(text)

        opts = q.get("options_bn", [])
        assert len(opts) == 4, f"Options must be exactly 4 in: {text}"

        correct_idx = q.get("correct_index")
        assert 0 <= correct_idx <= 3, f"Invalid correct_index {correct_idx} in: {text}"

        exp = q.get("explanation_bn", "").strip()
        assert exp, f"Empty explanation in: {text}"

    assert len(seen_texts) == 1000, f"Expected 1000 unique questions, got {len(seen_texts)}"
    return all_questions


def seed_database(db_path: str = QUIZ_DB_PATH, reset: bool = True):
    print(f"Connecting to quiz database at: {db_path}...")
    db = QuizDatabase(db_path)

    questions = get_all_1000_unique_questions()
    print(f"Loaded {len(questions)} meticulously verified unique questions.")

    if reset:
        print("Clearing existing quizzes table to eliminate any legacy duplicates...")
        conn = db._get_conn()
        with conn:
            conn.execute("DELETE FROM quizzes;")

    print("Inserting 1,000 completely unique questions into SQLite...")
    inserted = db.bulk_insert_questions(questions)
    total_now = db.count_questions()
    print(f"Successfully inserted {inserted} questions! Total active questions in DB: {total_now}")

    summary = db.get_categories_summary()
    print("Database Categories Summary:")
    print(json.dumps(summary, indent=2, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description="Seed Bhromon Quiz Database with 1,000 Unique Questions")
    parser.add_argument("--db-path", default=QUIZ_DB_PATH, help="Path to SQLite database file")
    parser.add_argument("--no-reset", action="store_true", help="Do not clear existing questions before inserting")
    args = parser.parse_args()

    seed_database(db_path=args.db_path, reset=not args.no_reset)


if __name__ == "__main__":
    main()
