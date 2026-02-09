# Semi-Auto Flow Video Builder

FastAPI backend for managing scene prompts, importing rendered Flow clips, running QC, selecting takes, building scene cache, concatenating `final.mp4`, and generating an HTML report.

## Run

```bash
pip install -r requirements.txt
uvicorn app.main:app --reload
```

## API

- `POST /api/projects`
- `GET /api/projects/{id}`
- `GET /api/projects/{id}/scenes`
- `POST /api/projects/{id}/import`
- `POST /api/projects/{id}/build/cache`
- `POST /api/projects/{id}/build/final`
- `POST /api/projects/{id}/report`
