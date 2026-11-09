"""Tests for media_utils: video poster thumbnail generation and edge-case handling."""

import asyncio
from pathlib import Path
import subprocess
from unittest.mock import MagicMock

import media_utils


def test_generate_video_poster_missing_file(tmp_path):
    missing_video = tmp_path / "non_existent.mp4"
    output_poster = tmp_path / "poster.webp"

    result = media_utils.generate_video_poster(missing_video, output_poster)
    assert result is False
    assert not output_poster.exists()


def test_generate_video_poster_empty_file(tmp_path):
    empty_video = tmp_path / "empty.mp4"
    empty_video.write_bytes(b"")
    output_poster = tmp_path / "poster.webp"

    result = media_utils.generate_video_poster(empty_video, output_poster)
    assert result is False
    assert not output_poster.exists()


def test_generate_video_poster_ffmpeg_missing(tmp_path, monkeypatch):
    video = tmp_path / "sample.mp4"
    video.write_bytes(b"dummy video data")
    output_poster = tmp_path / "poster.webp"

    def fake_run(*args, **kwargs):
        raise FileNotFoundError("ffmpeg not found")

    monkeypatch.setattr(subprocess, "run", fake_run)

    result = media_utils.generate_video_poster(video, output_poster)
    assert result is False
    assert not output_poster.exists()


def test_generate_video_poster_timeout(tmp_path, monkeypatch):
    video = tmp_path / "sample.mp4"
    video.write_bytes(b"dummy video data")
    output_poster = tmp_path / "poster.webp"

    def fake_run(*args, **kwargs):
        raise subprocess.TimeoutExpired(cmd="ffmpeg", timeout=12.0)

    monkeypatch.setattr(subprocess, "run", fake_run)

    result = media_utils.generate_video_poster(video, output_poster)
    assert result is False


def test_generate_video_poster_success(tmp_path, monkeypatch):
    video = tmp_path / "sample.mp4"
    video.write_bytes(b"dummy video data")
    output_poster = tmp_path / "covers" / "poster.webp"

    def fake_run(cmd, *args, **kwargs):
        # Simulate ffmpeg successfully writing a valid webp file
        out_idx = cmd.index(str(output_poster))
        target = Path(cmd[out_idx])
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(b"RIFF....WEBPVP8 ...")
        mock_res = MagicMock()
        mock_res.returncode = 0
        return mock_res

    monkeypatch.setattr(subprocess, "run", fake_run)

    result = media_utils.generate_video_poster(video, output_poster)
    assert result is True
    assert output_poster.is_file()
    assert output_poster.stat().st_size > 0


def test_async_generate_video_poster(tmp_path, monkeypatch):
    video = tmp_path / "sample.mp4"
    video.write_bytes(b"dummy video data")
    output_poster = tmp_path / "poster.webp"

    def fake_run(cmd, *args, **kwargs):
        output_poster.write_bytes(b"RIFF....WEBP")
        mock_res = MagicMock()
        mock_res.returncode = 0
        return mock_res

    monkeypatch.setattr(subprocess, "run", fake_run)

    result = asyncio.run(media_utils.async_generate_video_poster(video, output_poster))
    assert result is True
    assert output_poster.exists()
