from __future__ import annotations

import json
import re
import shutil
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from fastapi import HTTPException

from app.config import NAME_REGEX, PROJECTS_ROOT, SCENE_DURATION_S, VALID_ASPECTS
from app.models import CreateProjectRequest, ProjectConfig, Scene, Take


@dataclass
class ProbeResult:
    duration: float
    width: int
    height: int
    fps: float


class ProjectService:
    def __init__(self, root: Path = PROJECTS_ROOT):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.name_pattern = re.compile(NAME_REGEX)

    def create_project(self, req: CreateProjectRequest) -> dict:
        if req.aspect not in VALID_ASPECTS:
            raise HTTPException(status_code=400, detail="Invalid aspect")

        folder = self.project_dir(req.project_id, req.aspect)
        if folder.exists():
            raise HTTPException(status_code=409, detail="Project already exists")

        for name in ["raw_imports", "imports", "cache", "builds", "report", "logs"]:
            (folder / name).mkdir(parents=True, exist_ok=True)

        prompts = [line.strip() for line in req.prompts.splitlines() if line.strip()]
        scenes = []
        for idx, prompt in enumerate(prompts, start=1):
            scenes.append(
                Scene(
                    scene_id=f"S{idx:04d}",
                    idx=idx,
                    prompt_raw=prompt,
                    prompt_compiled=prompt,
                    status="NOT_STARTED",
                ).model_dump()
            )

        project_cfg = ProjectConfig(
            project_id=req.project_id,
            aspect=req.aspect,
            scene_duration_s=SCENE_DURATION_S,
            build_mode=req.build_mode,
            fps_mode=req.fps_mode,
            global_style=req.global_style,
            bible=req.bible,
            negative_prompt=req.negative_prompt,
        ).model_dump()

        self.write_json(folder / "project.json", project_cfg)
        self.write_json(folder / "scenes.json", {"scenes": scenes})
        (folder / "prompts.txt").write_text("\n".join(prompts), encoding="utf-8")
        return {"project_folder": str(folder), "scene_count": len(scenes)}

    def get_project(self, project_id: str) -> dict:
        folder = self.find_project_folder(project_id)
        return {
            "project": self.read_json(folder / "project.json"),
            "scenes": self.read_json(folder / "scenes.json")["scenes"],
            "folder": str(folder),
        }

    def import_folder(self, project_id: str, source_folder: Path) -> dict:
        folder = self.find_project_folder(project_id)
        project = self.read_json(folder / "project.json")
        scenes_doc = self.read_json(folder / "scenes.json")
        imported = 0

        imports_dir = folder / "imports"
        source_folder = Path(source_folder)
        if not source_folder.exists():
            raise HTTPException(status_code=404, detail="Source folder not found")

        by_scene = {scene["scene_id"]: scene for scene in scenes_doc["scenes"]}

        for mp4 in source_folder.glob("*.mp4"):
            m = self.name_pattern.match(mp4.name)
            if not m:
                continue
            if m.group("project_id") != project_id or m.group("aspect") != project["aspect"]:
                continue

            scene_id = f"S{m.group('scene')}"
            take_id = f"T{m.group('take')}"
            if scene_id not in by_scene:
                continue

            target = imports_dir / mp4.name
            shutil.copy2(mp4, target)
            probe = self.ffprobe(target)
            qc_status, reasons = self.qc_take(project["aspect"], probe)
            take = Take(
                take_id=take_id,
                filepath=str(Path("imports") / mp4.name).replace("\\", "/"),
                duration=probe.duration,
                width=probe.width,
                height=probe.height,
                fps=probe.fps,
                qc_status=qc_status,
                qc_reasons=reasons,
            ).model_dump()

            scene = by_scene[scene_id]
            scene["status"] = "IMPORTED"
            scene["takes"] = [t for t in scene["takes"] if t["take_id"] != take_id]
            scene["takes"].append(take)
            scene["selected_take"] = self.select_best_take(scene["takes"])
            scene["status"] = self.scene_status_from_selected(scene)
            imported += 1

        self.write_json(folder / "scenes.json", scenes_doc)
        return {"imported": imported}

    def build_cache(self, project_id: str) -> dict:
        folder = self.find_project_folder(project_id)
        scenes_doc = self.read_json(folder / "scenes.json")
        rebuilt: list[str] = []
        for scene in scenes_doc["scenes"]:
            selected = self.get_selected_take_obj(scene)
            if not selected or selected["qc_status"] == "FAIL":
                continue
            scene_cache = folder / "cache" / f"{scene['scene_id']}.mp4"
            src = folder / selected["filepath"]
            if not scene_cache.exists() or src.stat().st_mtime > scene_cache.stat().st_mtime:
                self.transcode_scene(src, scene_cache)
                rebuilt.append(scene["scene_id"])
        return {"rebuilt_scenes": rebuilt}

    def build_final(self, project_id: str) -> dict:
        folder = self.find_project_folder(project_id)
        scenes_doc = self.read_json(folder / "scenes.json")

        files: list[Path] = []
        for scene in scenes_doc["scenes"]:
            selected = self.get_selected_take_obj(scene)
            if not selected:
                raise HTTPException(status_code=400, detail=f"Scene {scene['scene_id']} missing selected take")
            if selected["qc_status"] == "FAIL":
                raise HTTPException(status_code=400, detail=f"Scene {scene['scene_id']} selected take failed QC")
            cache_path = folder / "cache" / f"{scene['scene_id']}.mp4"
            if not cache_path.exists():
                raise HTTPException(status_code=400, detail=f"Scene {scene['scene_id']} missing cache")
            files.append(cache_path)

        concat_list = folder / "cache" / "concat.txt"
        concat_list.write_text("\n".join([f"file '{f.resolve().as_posix()}'" for f in files]), encoding="utf-8")
        out = folder / "builds" / "final.mp4"
        cmd = [
            "ffmpeg",
            "-y",
            "-f",
            "concat",
            "-safe",
            "0",
            "-i",
            str(concat_list),
            "-c",
            "copy",
            str(out),
        ]
        self.run_cmd(cmd)
        return {"output": str(out)}

    def build_report(self, project_id: str) -> dict:
        folder = self.find_project_folder(project_id)
        project = self.read_json(folder / "project.json")
        scenes_doc = self.read_json(folder / "scenes.json")
        rows = []
        for s in scenes_doc["scenes"]:
            rows.append(
                f"<tr><td>{s['scene_id']}</td><td>{s['status']}</td><td>{s['selected_take'] or '-'}</td><td>{len(s['takes'])}</td></tr>"
            )

        html = f"""<!doctype html><html><body><h1>Report {project['project_id']}</h1>
<table border='1'><tr><th>Scene</th><th>Status</th><th>Selected</th><th>#Takes</th></tr>{''.join(rows)}</table>
<p>Generated at {datetime.utcnow().isoformat()}Z</p></body></html>"""
        out = folder / "report" / "report.html"
        out.write_text(html, encoding="utf-8")
        return {"output": str(out)}

    def qc_take(self, aspect: str, p: ProbeResult) -> tuple[str, list[str]]:
        reasons: list[str] = []
        if p.duration <= 0:
            return "FAIL", ["corrupt_or_zero_duration"]

        if p.duration < 5.5 or p.duration > 10.5:
            reasons.append("duration_out_of_fail_range")
            status = "FAIL"
        elif p.duration < 7.0 or p.duration > 9.0:
            reasons.append("duration_warn")
            status = "WARN"
        else:
            status = "OK"

        if aspect == "V" and (p.height / p.width) < 1.6:
            reasons.append("aspect_fail")
            status = "FAIL"
        if aspect == "H" and (p.width / p.height) < 1.6:
            reasons.append("aspect_fail")
            status = "FAIL"
        return status, reasons

    def select_best_take(self, takes: list[dict]) -> str | None:
        if not takes:
            return None

        def rank(t: dict):
            qc_rank = 2 if t["qc_status"] == "OK" else 1 if t["qc_status"] == "WARN" else 0
            resolution = t["width"] * t["height"]
            take_no = int(t["take_id"][1:])
            return (qc_rank, -abs(t["duration"] - 8.0), resolution, take_no)

        best = sorted(takes, key=rank, reverse=True)[0]
        return best["take_id"]

    def scene_status_from_selected(self, scene: dict) -> str:
        selected = self.get_selected_take_obj(scene)
        if not selected:
            return "NOT_STARTED"
        if selected["qc_status"] == "OK":
            return "QC_OK"
        if selected["qc_status"] == "WARN":
            return "QC_WARN"
        return "QC_FAIL"

    def get_selected_take_obj(self, scene: dict) -> dict | None:
        if not scene.get("selected_take"):
            return None
        for take in scene["takes"]:
            if take["take_id"] == scene["selected_take"]:
                return take
        return None

    def ffprobe(self, path: Path) -> ProbeResult:
        cmd = [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height,r_frame_rate",
            "-show_entries",
            "format=duration",
            "-of",
            "json",
            str(path),
        ]
        try:
            out = self.run_cmd(cmd)
            data = json.loads(out)
            stream = data["streams"][0]
            duration = float(data["format"]["duration"])
            num, den = stream.get("r_frame_rate", "0/1").split("/")
            fps = float(num) / float(den)
            return ProbeResult(duration=duration, width=int(stream["width"]), height=int(stream["height"]), fps=fps)
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=400, detail=f"ffprobe failed for {path.name}: {exc}") from exc

    def transcode_scene(self, src: Path, out: Path) -> None:
        cmd = ["ffmpeg", "-y", "-i", str(src), "-c:v", "libx264", "-preset", "veryfast", "-c:a", "aac", str(out)]
        self.run_cmd(cmd)

    def run_cmd(self, cmd: list[str]) -> str:
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            raise HTTPException(status_code=400, detail=proc.stderr.strip() or f"Command failed: {' '.join(cmd)}")
        return proc.stdout

    def project_dir(self, project_id: str, aspect: str) -> Path:
        return self.root / f"{project_id}_{aspect}"

    def find_project_folder(self, project_id: str) -> Path:
        matches = list(self.root.glob(f"{project_id}_*"))
        if not matches:
            raise HTTPException(status_code=404, detail="Project not found")
        return matches[0]

    @staticmethod
    def write_json(path: Path, obj: dict) -> None:
        path.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding="utf-8")

    @staticmethod
    def read_json(path: Path) -> dict:
        return json.loads(path.read_text(encoding="utf-8"))
