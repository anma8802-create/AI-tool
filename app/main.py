from pathlib import Path

from fastapi import FastAPI

from app.models import CreateProjectRequest, ImportRequest
from app.service import ProjectService

app = FastAPI(title="Semi-Auto Flow Video Builder")
svc = ProjectService()


@app.post("/api/projects")
def create_project(req: CreateProjectRequest):
    return svc.create_project(req)


@app.get("/api/projects/{project_id}")
def get_project(project_id: str):
    return svc.get_project(project_id)


@app.get("/api/projects/{project_id}/scenes")
def get_scenes(project_id: str):
    return {"scenes": svc.get_project(project_id)["scenes"]}


@app.post("/api/projects/{project_id}/import")
def import_clips(project_id: str, req: ImportRequest):
    return svc.import_folder(project_id, Path(req.source_folder))


@app.post("/api/projects/{project_id}/build/cache")
def build_cache(project_id: str):
    return svc.build_cache(project_id)


@app.post("/api/projects/{project_id}/build/final")
def build_final(project_id: str):
    return svc.build_final(project_id)


@app.post("/api/projects/{project_id}/report")
def build_report(project_id: str):
    return svc.build_report(project_id)
