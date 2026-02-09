from pathlib import Path

PROJECTS_ROOT = Path("projects")
SCENE_DURATION_S = 8.0
VALID_ASPECTS = {"V", "H"}
NAME_REGEX = r"^(?P<project_id>[^_]+)_(?P<aspect>[VH])_S(?P<scene>\d{4})_T(?P<take>\d{2})\.mp4$"
