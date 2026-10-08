from pydantic import BaseModel, Field


class GenerateRequest(BaseModel):
    prompt: str = Field(min_length=1, max_length=4000)
    max_tokens: int = Field(default=128, ge=1, le=2048)


class GenerateResponse(BaseModel):
    response: str
    model: str
    provider: str
    deterministic: bool