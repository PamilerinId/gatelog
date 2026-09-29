from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health():
    assert client.get("/health").json() == {"status": "ok"}


def test_accepts_valid_request_and_normalises_phone():
    r = client.post("/v1/demo-requests", json={"name": "Adaeze Okafor", "estate": "Magodo Phase 2", "phone": "0803 123 4567"})
    assert r.status_code == 202
    assert r.json()["ok"] is True


def test_rejects_non_nigerian_number():
    r = client.post("/v1/demo-requests", json={"name": "Adaeze", "estate": "Magodo", "phone": "+44 7700 900123"})
    assert r.status_code == 422


def test_requires_token_when_configured(monkeypatch):
    monkeypatch.setenv("API_INTERNAL_TOKEN", "s3cret")
    body = {"name": "Adaeze", "estate": "Magodo", "phone": "08031234567"}
    assert client.post("/v1/demo-requests", json=body).status_code == 401
    ok = client.post("/v1/demo-requests", json=body, headers={"Authorization": "Bearer s3cret"})
    assert ok.status_code == 202
