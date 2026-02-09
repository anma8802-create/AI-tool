from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class CreateProjectRequest(BaseModel):
    project_id: str
    aspect: Literal["V", "H"]
    prompts: str
    build_mode: Literal["STRICT"] = "STRICT"
    fps_mode: Literal["KEEP"] = "KEEP"
    global_style: str = ""
    bible: str = ""
    negative_prompt: str = "low quality, blurry, text, watermark"


class Take(BaseModel):
    take_id: str
    filepath: str
    duration: float
    width: int
    height: int
    fps: float
    qc_status: Literal["FAIL", "WARN", "OK"]
    qc_reasons: list[str] = Field(default_factory=list)


class Scene(BaseModel):
    scene_id: str
    idx: int
    prompt_raw: str
    prompt_compiled: str
    status: Literal["NOT_STARTED", "IMPORTED", "QC_FAIL", "QC_WARN", "QC_OK"]
    selected_take: str | None = None
    takes: list[Take] = Field(default_factory=list)


class ProjectConfig(BaseModel):
    project_id: str
    aspect: Literal["V", "H"]
    scene_duration_s: float = 8.0
    build_mode: Literal["STRICT"] = "STRICT"
    fps_mode: Literal["KEEP"] = "KEEP"
    global_style: str = ""
    bible: str = ""
    negative_prompt: str = "low quality, blurry, text, watermark"


class ProjectState(BaseModel):
    project: ProjectConfig
    scenes: list[Scene]


class ImportRequest(BaseModel):
    source_folder: str


class BuildResult(BaseModel):
    success: bool
    message: str
    rebuilt_scenes: list[str] = Field(default_factory=list)
    output: str | None = None
