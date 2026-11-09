"""Media utility helpers for video poster thumbnail extraction and image processing.

Uses ffmpeg when available on the host system to extract standardized 720x1280
WebP video poster thumbnails, offloading client devices and ensuring crisp
letterboxed previews.
"""

import asyncio
import logging
from pathlib import Path
import subprocess

logger = logging.getLogger("media-server")


def generate_video_poster(
    video_path: Path,
    output_path: Path,
    target_width: int = 720,
    target_height: int = 1280,
    timestamp: str = "00:00:01",
    timeout_seconds: float = 12.0,
) -> bool:
    """Extracts a standardized WebP poster frame from [video_path] into [output_path].

    Returns True if the output file was successfully created. If ffmpeg is
    missing, the file is invalid/empty, or extraction fails, logs a warning
    and returns False without raising exceptions.
    """
    video_file = Path(video_path)
    output_file = Path(output_path)

    if not video_file.is_file() or video_file.stat().st_size <= 0:
        logger.debug("Cannot generate poster: video file %s is missing or empty.", video_file)
        return False

    output_file.parent.mkdir(parents=True, exist_ok=True)

    # Filter: scale keeping aspect ratio, then pad to target resolution with black bars
    vf_filter = (
        f"scale={target_width}:{target_height}:force_original_aspect_ratio=decrease,"
        f"pad={target_width}:{target_height}:(ow-iw)/2:(oh-ih)/2:black"
    )

    attempts = [timestamp, "00:00:00.100", "00:00:00"]
    for ts in attempts:
        cmd = [
            "ffmpeg",
            "-v", "error",
            "-ss", ts,
            "-i", str(video_file),
            "-vf", vf_filter,
            "-vframes", "1",
            "-c:v", "webp",
            "-q:v", "80",
            "-y",
            str(output_file),
        ]
        try:
            res = subprocess.run(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout_seconds,
                check=False,
            )
            if res.returncode == 0 and output_file.is_file() and output_file.stat().st_size > 0:
                logger.info("Successfully extracted video poster for %s to %s", video_file.name, output_file.name)
                return True
        except FileNotFoundError:
            logger.warning("ffmpeg binary not found on PATH. Video poster generation skipped.")
            return False
        except subprocess.TimeoutExpired:
            logger.warning("ffmpeg timed out extracting poster for %s at %s", video_file.name, ts)
        except Exception as ex:
            logger.warning("Unexpected error during video poster generation: %s", ex)

    # Clean up empty/partial output file if any
    if output_file.is_file() and output_file.stat().st_size == 0:
        output_file.unlink(missing_ok=True)

    return False


async def async_generate_video_poster(
    video_path: Path,
    output_path: Path,
    target_width: int = 720,
    target_height: int = 1280,
) -> bool:
    """Asynchronously generates a video poster on a background thread."""
    return await asyncio.to_thread(
        generate_video_poster,
        video_path=video_path,
        output_path=output_path,
        target_width=target_width,
        target_height=target_height,
    )
