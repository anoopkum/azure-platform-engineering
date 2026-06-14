import pytest
from app.main import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def test_index_returns_200(client):
    response = client.get("/")
    assert response.status_code == 200


def test_index_json_fields(client):
    data = client.get("/").get_json()
    assert data["app"] == "hello-platform"
    assert "version" in data
    assert "env" in data


def test_health_returns_200(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json()["status"] == "ok"


def test_ready_returns_200(client):
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.get_json()["status"] == "ready"


def test_health_does_not_return_500(client):
    response = client.get("/health")
    assert response.status_code != 500
