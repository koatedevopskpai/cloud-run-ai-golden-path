# cloud-run-ai-golden-path

[![CI](https://img.shields.io/github/actions/workflow/status/koatedevopskpai/cloud-run-ai-golden-path/ci.yml?branch=main)](https://github.com/koatedevopskpai/cloud-run-ai-golden-path/actions) [coverage ≥80% enforced in CI]

The blog's **Cloud Run golden path packaged for AI**: a Pydantic-validated
**FastAPI LLM endpoint**, the **Terraform module** (runtime SA, Artifact
Registry, scale-to-zero, availability + latency SLOs, 14.4× burn-rate alert)
and **keyless CI** — the same pattern covered in the blog's
*Cloud Run golden path* post.

```
client ─▶ FastAPI (/health ../generate)  Pydantic-validated
              │
              ▼
         LLM client (provider-agnostic)
        openai-compatible  │  deterministic (no keys)
              │
GitHub ─▶ WIF ─▶ Cloud Build ─▶ Artifact Registry ─▶ Cloud Run (scale-to-zero)
                                                        │
                                                        ▼
                                          SLOs + burn-rate alert ─▶ on-call
```

**Deterministic by default**: request/response schemas are strict Pydantic; the
LLM client runs in honest "deterministic mode" until you set a provider — no
keys, no network, no pretend-AI.

## Run it yourself (60s)

```bash
pip install -e ".[dev]"
python -m pytest                        # tests pass
uvicorn app.main:app --port 8080        # run
curl localhost:8080/health
curl -X POST localhost:8080/generate -H 'content-type: application/json' \
     -d '{"prompt":"summarise X","max_tokens":50}'
```

Or with Docker:

```bash
docker build -t llm-api .
docker run --rm -p 8080:8080 llm-api
```

With a real model (OpenAI / OpenRouter / vLLM / Ollama / Azure-compatible):

```bash
LLM_PROVIDER=openai-compatible LLM_MODEL=gpt-4o-mini LLM_API_KEY=sk-... uvicorn app.main:app
```

## Deploy to Cloud Run

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # fill project_id + alert_email
terraform init && terraform apply
```

Then wire the keyless workflow (`.github/workflows/deploy.yml`) with your
WIF pool + deploy SA — exactly like the blog's own CI.

## Layout

```
app/            FastAPI health + generate endpoints (Pydantic schemas)
infra/          Terraform: Cloud Run v2, AR, runtime SA, SLOs, burn alert
.github/        CI (pytest) + keyless deploy workflow
tests/          app behaviour + schema validation
```

Vertex AI / Bedrock: implement the same `generate()` contract in
`app/llm.py` (roadmap) — the endpoint and infra don't change.

## Licence

MIT — see [LICENSE](LICENSE). © 2026 Koate Kpai.