from fastapi.testclient import TestClient

from ai_tool.api import app


client = TestClient(app)


def test_health() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_run_tool_mock() -> None:
    response = client.post(
        "/tools/run",
        json={
            "tool_name": "demo-tool",
            "input": {"text": "hello"},
        },
    )

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "mocked"
    assert body["tool_name"] == "demo-tool"
    assert body["output"]["received_input"] == {"text": "hello"}
