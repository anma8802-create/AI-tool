# AI-tool (FastAPI starter)

A minimal FastAPI starter project with:

- `GET /health`
- `POST /tools/run` (mock execution)
- auto-generated Swagger/OpenAPI docs

## Requirements

- Python 3.10+

## Setup

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Run the API

```bash
uvicorn ai_tool.api:app --reload
```

API will be available at:

- `http://127.0.0.1:8000/health`
- `http://127.0.0.1:8000/docs` (Swagger UI)
- `http://127.0.0.1:8000/openapi.json`

## Example request

```bash
curl -X POST http://127.0.0.1:8000/tools/run \
  -H "Content-Type: application/json" \
  -d '{"tool_name":"demo-tool","input":{"text":"hello"}}'
```

## Run tests

```bash
pytest
```
