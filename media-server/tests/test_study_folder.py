"""The study folder: study materials are stored under it, and other folders are refused."""

import pytest
from fastapi import HTTPException

import main


def test_study_is_an_allowed_folder():
    assert "study" in main.ALLOWED_FOLDERS
    main.check_folder("study")  # does not raise


@pytest.mark.parametrize("folder", ["materials", "study_materials", "Study", "../study", ""])
def test_other_folders_are_refused(folder):
    with pytest.raises(HTTPException) as refused:
        main.check_folder(folder)
    assert refused.value.status_code == 400
