"""The reader and the web proxy fetch only from the newspapers in the catalog."""

import urllib.request

import pytest
from fastapi.testclient import TestClient

import main
import news


@pytest.mark.parametrize(
    "url",
    [
        "https://www.prothomalo.com/bangladesh/article",
        "https://bangla.bdnews24.com/feed",
        "http://www.thedailystar.net/news",
        "https://edition.cnn.com/world",
        "https://www.bbc.co.uk/bengali/story",
        "https://www.dw.com/bn/story",
    ],
)
def test_catalog_sites_may_be_read(url):
    assert news.check_fetch_url(url).hostname


@pytest.mark.parametrize(
    "url",
    [
        "http://127.0.0.1:8220/",
        "http://127.0.0.2:8085/",
        "http://localhost/",
        "http://169.254.169.254/latest/meta-data/",
        "http://172.17.0.2:8220/health",
        "http://2130706433/",
        "http://127.1/",
        "http://0x7f000001/",
        "http://[::1]/",
        "http://prothomalo.com.evil.example/",
        "http://evil.example/",
        "ftp://www.prothomalo.com/x",
        "file:///etc/passwd",
        "https://user:secret@www.prothomalo.com/",
        "http://www.prothomalo.com:8220/",
        "https://www.prothomalo.com:notaport/",
    ],
)
def test_everything_else_is_refused(url):
    with pytest.raises(news.UnsafeUrl):
        news.check_fetch_url(url)


def test_a_redirect_out_of_the_catalog_is_refused():
    handler = news._CheckedRedirects()
    request = urllib.request.Request("https://www.prothomalo.com/a")
    with pytest.raises(news.UnsafeUrl):
        handler.redirect_request(request, None, 302, "Found", {}, "http://127.0.0.1:8220/")


def test_a_redirect_to_another_catalog_site_is_followed():
    handler = news._CheckedRedirects()
    request = urllib.request.Request("https://www.prothomalo.com/a")
    followed = handler.redirect_request(request, None, 302, "Found", {}, "https://www.thedailystar.net/x")
    assert followed.full_url == "https://www.thedailystar.net/x"


@pytest.fixture
def news_client():
    return TestClient(main.app)


def test_the_reader_refuses_a_private_address(news_client):
    assert news_client.get("/api/news/reader", params={"url": "http://127.0.0.1:8220/"}).status_code == 403


def test_the_proxy_refuses_a_metadata_address(news_client):
    assert news_client.get("/api/news/proxy", params={"url": "http://169.254.169.254/"}).status_code == 403


def test_the_proxy_refuses_a_site_outside_the_catalog(news_client):
    assert news_client.get("/api/news/proxy", params={"url": "https://example.org/"}).status_code == 403


def test_the_reader_view_renders_the_extracted_article(news_client, monkeypatch):
    article = {
        "title": "Headline",
        "sourceName": "Prothom Alo",
        "heroImageUrl": "https://www.prothomalo.com/img.jpg",
        "paragraphs": ["First paragraph."],
    }
    monkeypatch.setattr(news, "extract_adfree_article", lambda url: article)
    response = news_client.get("/api/news/reader-view", params={"url": "https://www.prothomalo.com/a"})
    assert response.status_code == 200
    assert "<p>First paragraph.</p>" in response.text
    assert "Headline" in response.text


def test_a_news_sync_needs_a_platform_admin(client, monkeypatch):
    started = []
    monkeypatch.setattr(news.news_aggregator, "sync_all", lambda background=True: started.append(background) or 1)
    assert client.post("/api/news/sync").status_code in (401, 403)
    assert client.post("/api/news/sync", headers={"Authorization": "Bearer tok-alice"}).status_code == 403
    assert started == []
    assert client.post("/api/news/sync", headers={"Authorization": "Bearer tok-admin"}).status_code == 200
    assert started == [True]
