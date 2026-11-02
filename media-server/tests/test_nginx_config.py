"""The nginx upload and copy routes must let CORS preflights through.

A browser sends an OPTIONS request with no Authorization header before each
cross-origin upload from the web app. If nginx refuses that request, the browser
never sends the upload. Unsigned real requests must still be refused.
"""

import pathlib
import pytest
import re

CONF = pathlib.Path(__file__).resolve().parents[1] / "bhromon.fun.conf"
ROUTES = ("/api/media/upload", "/api/media/copy")


def _location(text: str, path: str) -> str:
    match = re.search(r"location = " + re.escape(path) + r" \{(.*?)\n    \}", text, re.S)
    assert match, f"no exact location block for {path}"
    return match.group(1)


def test_upload_and_copy_let_preflights_through_and_refuse_unsigned_requests():
    if not CONF.exists():
        pytest.skip("bhromon.fun.conf is a private host configuration kept on local server only")
    text = CONF.read_text()
    for path in ROUTES:
        block = _location(text, path)
        assert "$request_method = OPTIONS" in block, path
        assert "return 401" in block, path
        # The preflight exemption is applied before the refusal, so it wins.
        assert block.index("$request_method = OPTIONS") < block.index("return 401"), path
