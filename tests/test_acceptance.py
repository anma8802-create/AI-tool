from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

from app.models import CreateProjectRequest
from app.service import ProjectService


@pytest.fixture()
def svc(tmp_path: Path) -> ProjectService:
    return ProjectService(root=tmp_path / "projects")


def _has_bins() -> bool:
    return shutil.which("ffmpeg") is not None and shutil.which("ffprobe") is not None


def _make_clip(path: Path, duration: float, size: str = "1080x1920", fps: int = 30):
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-f",
            "lavfi",
            "-i",
            f"color=c=black:s={size}:r={fps}",
            "-t",
            str(duration),
            str(path),
        ],
        check=True,
        capture_output=True,
    )


@pytest.mark.skipif(not _has_bins(), reason="ffmpeg/ffprobe missing")
def test_acceptance_flow(svc: ProjectService, tmp_path: Path):
    svc.create_project(
        CreateProjectRequest(project_id="P20260209-001", aspect="V", prompts="a\nb\nc")
    )
    project = svc.get_project("P20260209-001")
    assert [s["scene_id"] for s in project["scenes"]] == ["S0001", "S0002", "S0003"]

    src = tmp_path / "src"
    src.mkdir()
    _make_clip(src / "P20260209-001_V_S0001_T01.mp4", 7.8)
    _make_clip(src / "P20260209-001_V_S0001_T02.mp4", 8.1)
    _make_clip(src / "P20260209-001_V_S0002_T01.mp4", 4.0)

    result = svc.import_folder("P20260209-001", src)
    assert result["imported"] == 3

    scenes = svc.get_project("P20260209-001")["scenes"]
    s1 = next(s for s in scenes if s["scene_id"] == "S0001")
    s2 = next(s for s in scenes if s["scene_id"] == "S0002")
    assert s1["selected_take"] == "T02"
    assert s2["status"] == "QC_FAIL"

    cache = svc.build_cache("P20260209-001")
    assert cache["rebuilt_scenes"] == ["S0001"]

    with pytest.raises(Exception):
        svc.build_final("P20260209-001")

    _make_clip(src / "P20260209-001_V_S0002_T02.mp4", 8.0)
    _make_clip(src / "P20260209-001_V_S0003_T01.mp4", 8.0)
    svc.import_folder("P20260209-001", src)

    first = svc.build_cache("P20260209-001")
    assert set(first["rebuilt_scenes"]) >= {"S0002", "S0003"}

    # modify one scene only
    _make_clip(src / "P20260209-001_V_S0003_T01.mp4", 8.2)
    svc.import_folder("P20260209-001", src)
    second = svc.build_cache("P20260209-001")
    assert second["rebuilt_scenes"] == ["S0003"]

    out = svc.build_final("P20260209-001")
    assert Path(out["output"]).exists()

    report = svc.build_report("P20260209-001")
    assert Path(report["output"]).exists()
