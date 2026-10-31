"""Tests for Bhromon Quiz Engine and REST endpoints."""

from pathlib import Path
import pytest
from fastapi.testclient import TestClient

from quiz import QuizDatabase
from main import app


@pytest.fixture
def temp_quiz_db(tmp_path: Path):
    db_file = tmp_path / "test_quiz.db"
    db = QuizDatabase(db_file)
    # Insert sample questions
    db.insert_question(
        category="hills_trek",
        destination_tag="sajek",
        difficulty="easy",
        question_bn="সাজেক ভ্যালি কোন জেলায় অবস্থিত?",
        options_bn=["রাঙ্গামাটি", "খাগড়াছড়ি", "বান্দরবান", "সিলেট"],
        correct_index=0,
        explanation_bn="সাজেক ভ্যালি রাঙ্গামাটি জেলার বাঘাইছড়ি উপজেলায় অবস্থিত।",
    )
    db.insert_question(
        category="beaches",
        destination_tag="coxs_bazar",
        difficulty="medium",
        question_bn="ইনানী বিচের প্রধান আকর্ষণ কী?",
        options_bn=["প্রবাল পাথর", "পাহাড়", "ঝর্ণা", "ম্যানগ্রোভ"],
        correct_index=0,
        explanation_bn="ইনানী সৈকত প্রবাল পাথরের জন্য বিখ্যাত।",
    )
    db.insert_question(
        category="general_travel",
        destination_tag="all",
        difficulty="easy",
        question_bn="বাংলাদেশে জরুরি সেবায় ডায়াল করতে হয় কোন নম্বরে?",
        options_bn=["৯৯৯", "১০০", "১১১", "২২২"],
        correct_index=0,
        explanation_bn="৯৯৯ হলো বাংলাদেশ পুলিশের জাতীয় জরুরি সেবা।",
    )
    return db


def test_quiz_database_methods(temp_quiz_db: QuizDatabase):
    assert temp_quiz_db.count_questions() == 3

    # Fetch by destination
    sajek_qs = temp_quiz_db.get_questions(destination="sajek", limit=5)
    assert len(sajek_qs) >= 1
    assert any(q["destination_tag"] == "sajek" for q in sajek_qs)

    # Fetch categories
    summary = temp_quiz_db.get_categories_summary()
    assert summary["total_questions"] == 3
    assert len(summary["categories"]) >= 2

    # Record attempt
    attempt_id = temp_quiz_db.record_attempt(
        user_uid="test_user_1",
        user_name="রফিক",
        tour_id="tour_123",
        score=5,
        total=5,
        category="hills_trek",
        destination="sajek",
    )
    assert attempt_id > 0

    # Leaderboard
    lb = temp_quiz_db.get_leaderboard(limit=10)
    assert len(lb) == 1
    assert lb[0]["user_uid"] == "test_user_1"
    assert lb[0]["total_score"] == 5


def test_quiz_api_endpoints():
    client = TestClient(app)

    # 1. Get questions
    res = client.get("/api/quiz/questions?limit=5")
    assert res.status_code == 200
    data = res.json()
    assert data["status"] == "success"
    assert isinstance(data["questions"], list)

    # 2. Get categories
    res_cat = client.get("/api/quiz/categories")
    assert res_cat.status_code == 200
    cat_data = res_cat.json()
    assert cat_data["status"] == "success"
    assert "total_questions" in cat_data["data"]

    # 3. Submit attempt
    res_sub = client.post(
        "/api/quiz/submit",
        json={
            "user_uid": "user_abc_123",
            "user_name": "তানভীর",
            "tour_id": "sajek_tour_99",
            "score": 9,
            "total": 10,
            "category": "hills_trek",
            "destination": "sajek",
        },
    )
    assert res_sub.status_code == 200
    sub_data = res_sub.json()
    assert sub_data["status"] == "success"
    assert sub_data["accuracy_percent"] == 90.0
    assert "কুইজ মাস্টার" in sub_data["badge"]

    # 4. Leaderboard
    res_lb = client.get("/api/quiz/leaderboard")
    assert res_lb.status_code == 200
    lb_data = res_lb.json()
    assert lb_data["status"] == "success"
    assert isinstance(lb_data["leaderboard"], list)
