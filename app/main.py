from fastapi import FastAPI

from .llm import build_llm
from .schemas import GenerateRequest, GenerateResponse

app = FastAPI(title="Cloud Run AI golden path", version="0.1.0")
llm = build_llm()


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "provider": llm.provider, "deterministic": llm.deterministic}


@app.post("/generate", response_model=GenerateResponse)
async def generate(req: GenerateRequest) -> GenerateResponse:
    text = llm.generate(req.prompt, max_tokens=req.max_tokens)
    return GenerateResponse(
        response=text,
        model=llm.model,
        provider=llm.provider,
        deterministic=llm.deterministic,
    )