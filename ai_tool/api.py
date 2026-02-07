from fastapi import FastAPI
from pydantic import BaseModel, Field


app = FastAPI(
    title="AI Tool API",
    description="Starter FastAPI service for AI-tool",
    version="0.1.0",
)


class ToolRunRequest(BaseModel):
    tool_name: str = Field(..., description="Name of the tool to execute")
    input: dict = Field(default_factory=dict, description="Input payload for the tool")


class ToolRunResponse(BaseModel):
    status: str
    tool_name: str
    output: dict


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/tools/run", response_model=ToolRunResponse)
def run_tool(payload: ToolRunRequest) -> ToolRunResponse:
    return ToolRunResponse(
        status="mocked",
        tool_name=payload.tool_name,
        output={
            "message": "Tool execution is mocked in this starter template.",
            "received_input": payload.input,
        },
    )
