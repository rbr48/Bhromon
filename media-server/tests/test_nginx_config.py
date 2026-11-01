"""The nginx upload and copy routes must let CORS preflights through.

A browser sends an OPTIONS request with no Authorization header before each
cross-origin upload from the web app. If nginx refuses that request, the browser
never sends the upload. Unsigned real requests must still be refused.
"""

import pathlib
import re

CONF = pathlib.Path(__file__).resolve().parents[1] / "bhromon.fun.conf"
ROUTES = ("/api/media/upload", "/api/media/copy")


def _location(text: str, path: str) -> str:
    match = re.search(r"location = " + re.escape(path) + r" \{(.*?)\n    \}", text, re.S)
    assert match, f"no exact location block for {path}"
    return match.group(1)


def test_upload_and_copy_let_preflights_through_and_refuse_unsigned_requests():
    text = CONF.read_text()
    for path in ROUTES:
        block = _location(text, path)
        assert "$request_method = OPTIONS" in block, path
        assert "return 401" in block, path
        # The preflight exemption is applied before the refusal, so it wins.
        assert block.index("$request_method = OPTIONS") < block.index("return 401"), path


def _prefix_location(text: str, prefix: str) -> str:
    match = re.search(r"location " + re.escape(prefix) + r" \{(.*?)\n    \}", text, re.S)
    assert match, f"no location block for {prefix}"
    return match.group(1)


def test_the_media_server_alone_sets_cors_on_the_api_routes():
    # The media server's CORS middleware sets Access-Control-Allow-Origin once. If nginx
    # adds a second copy, browsers reject the response, so nginx sets none on these routes.
    text = CONF.read_text()
    blocks = [_location(text, path) for path in ROUTES]
    blocks.append(_prefix_location(text, "/api/media/"))
    for block in blocks:
        assert "Access-Control-Allow-Origin" not in block
