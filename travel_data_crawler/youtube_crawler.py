"""
Bhromon Travel Crawler — YouTube scraper using yt-dlp.
Downloads video metadata, thumbnails, and subtitles (no video files by default).
"""
import os
import json
import re
from datetime import datetime

import yt_dlp

from config import YOUTUBE_QUERIES, YOUTUBE_CHANNELS, YOUTUBE_DIR, TRAVEL_KEYWORDS
from database import save_video, log_crawl


def _slug(text: str, maxlen: int = 60) -> str:
    text = re.sub(r'[^\w\s-]', '', text.lower())
    text = re.sub(r'[\s_]+', '-', text).strip('-')
    return text[:maxlen]


def _is_travel_related(title: str, description: str) -> bool:
    combined = (title + " " + description).lower()
    return any(kw.lower() in combined for kw in TRAVEL_KEYWORDS)


def _ydl_opts(out_dir: str) -> dict:
    return {
        "quiet": True,
        "no_warnings": True,
        "extract_flat": False,
        "skip_download": True,         # Metadata + thumbnail only, no video file
        "writethumbnail": True,
        "writeinfojson": True,
        "writesubtitles": True,
        "subtitleslangs": ["en", "bn"],
        "outtmpl": os.path.join(out_dir, "%(id)s", "%(title).60s"),
        "ignoreerrors": True,
        "sleep_interval": 2,
        "max_sleep_interval": 5,
        "postprocessors": [{
            "key": "FFmpegThumbnailsConvertor",
            "format": "jpg",
        }],
    }


def crawl_youtube_query(query: str) -> int:
    """Search YouTube for a query and collect video metadata."""
    out_dir = os.path.join(YOUTUBE_DIR, "search", re.sub(r'\W+', '_', query)[:40])
    os.makedirs(out_dir, exist_ok=True)

    search_url = f"ytsearch50:{query}"  # Top 50 results per query
    opts = _ydl_opts(out_dir)
    opts["extract_flat"] = "in_playlist"

    saved = 0
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(search_url, download=False)
            if not info or "entries" not in info:
                return 0

            for entry in info.get("entries", []):
                if not entry:
                    continue
                title = entry.get("title", "")
                desc  = entry.get("description", "")

                if not _is_travel_related(title, desc):
                    continue

                video_id = entry.get("id", "")
                thumbnail_path = os.path.join(out_dir, video_id, f"{video_id}.jpg")

                # Download thumbnail
                try:
                    video_url = f"https://www.youtube.com/watch?v={video_id}"
                    with yt_dlp.YoutubeDL({**opts, "outtmpl": os.path.join(out_dir, video_id, "%(title).60s")}) as dl:
                        dl.extract_info(video_url, download=True)
                except Exception:
                    pass

                data = {
                    "video_id":    video_id,
                    "platform":    "youtube",
                    "title":       title,
                    "description": desc[:1000],
                    "channel":     entry.get("uploader") or entry.get("channel", ""),
                    "url":         f"https://www.youtube.com/watch?v={video_id}",
                    "thumbnail_path": thumbnail_path if os.path.exists(thumbnail_path) else "",
                    "duration":    entry.get("duration", 0),
                    "view_count":  entry.get("view_count", 0),
                    "published_at": entry.get("upload_date", ""),
                    "keywords":    [kw for kw in TRAVEL_KEYWORDS if kw.lower() in (title + desc).lower()],
                }
                save_video(data)
                log_crawl("youtube", data["url"], "ok")
                saved += 1
                print(f"    [YT] {title[:70]}")

    except Exception as e:
        log_crawl("youtube_search", query, "error", str(e))
        print(f"  [YT Error] {query}: {e}")

    return saved


def crawl_youtube_channel(channel_url: str) -> int:
    """Crawl an entire YouTube channel."""
    out_dir = os.path.join(YOUTUBE_DIR, "channels",
                           re.sub(r'\W+', '_', channel_url.split("/")[-1])[:40])
    os.makedirs(out_dir, exist_ok=True)

    opts = _ydl_opts(out_dir)
    saved = 0
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(channel_url, download=False)
            if not info:
                return 0
            entries = info.get("entries", [])
            for entry in entries:
                if not entry:
                    continue
                title = entry.get("title", "")
                desc  = entry.get("description", "")
                if not _is_travel_related(title, desc):
                    continue
                video_id = entry.get("id", "")
                data = {
                    "video_id":    video_id,
                    "platform":    "youtube",
                    "title":       title,
                    "description": desc[:1000],
                    "channel":     info.get("channel") or info.get("title", ""),
                    "url":         f"https://www.youtube.com/watch?v={video_id}",
                    "thumbnail_path": "",
                    "duration":    entry.get("duration", 0),
                    "view_count":  entry.get("view_count", 0),
                    "published_at": entry.get("upload_date", ""),
                    "keywords":    [kw for kw in TRAVEL_KEYWORDS if kw.lower() in (title + desc).lower()],
                }
                save_video(data)
                saved += 1
                print(f"    [YT Channel] {title[:70]}")
    except Exception as e:
        log_crawl("youtube_channel", channel_url, "error", str(e))
        print(f"  [YT Channel Error] {channel_url}: {e}")

    return saved


def crawl_all_youtube() -> int:
    total = 0
    print("\n[YOUTUBE] Crawling search queries...")
    for query in YOUTUBE_QUERIES:
        print(f"  Searching: {query}")
        total += crawl_youtube_query(query)

    print("\n[YOUTUBE] Crawling channels...")
    for ch in YOUTUBE_CHANNELS:
        print(f"  Channel: {ch}")
        total += crawl_youtube_channel(ch)

    print(f"[YOUTUBE] Done. Total videos: {total}")
    return total
