from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_generate_deterministic_mode():
    r = client.post("/generate", json={"prompt": "hello"})
    assert r.status_code == 200
    body = r.json()
    assert body["deterministic"] is True
    assert body["model"] == "none"


def test_generate_pydantic_validation():
    r = client.post("/generate", json={"prompt": ""})
    assert r.status_code == 422

    r = client.post("/generate", json={"prompt": "hi", "max_tokens": 99999})
    assert r.status_code == 422