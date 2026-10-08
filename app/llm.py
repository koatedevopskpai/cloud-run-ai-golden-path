"""Provider-agnostic LLM client.

Deterministic mode is the default (no keys, no network). The OpenAI-compatible
client covers OpenAI, OpenRouter, vLLM, Ollama and Azure-compatible endpoints
via ``base_url``/``model``. Vertex AI / Bedrock: implement the same
:func:`generate` contract in ``build_llm`` (roadmap).
"""

from __future__ import annotations

import json
import os
import urllib.request
from dataclasses import dataclass
from typing import Protocol


class LLM(Protocol):
    provider: str
    model: str
    deterministic: bool

    def generate(self, prompt: str, max_tokens: int = 128) -> str: ...


@dataclass
class DeterministicLLM:
    """Honest deterministic fallback: no pretend-AI."""

    provider: str = "deterministic"
    model: str = "none"
    deterministic: bool = True

    def generate(self, prompt: str, max_tokens: int = 128) -> str:
        return (
            f"[deterministic mode] prompt({len(prompt)} chars) "
            f"max_tokens={max_tokens}. Configure LLM_PROVIDER to use a real model."
        )


@dataclass
class OpenAICompatibleLLM:
    model: str
    base_url: str = "https://api.openai.com/v1"
    api_key: str = ""
    provider: str = "openai-compatible"
    deterministic: bool = False

    def generate(self, prompt: str, max_tokens: int = 128) -> str:
        body = json.dumps(
            {
                "model": self.model,
                "messages": [{"role": "user", "content": prompt}],
                "max_tokens": max_tokens,
                "temperature": 0.0,
            }
        ).encode("utf-8")
        request = urllib.request.Request(
            f"{self.base_url.rstrip('/')}/chat/completions",
            data=body,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.api_key}",
            },
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            payload = json.loads(response.read().decode("utf-8"))
        return payload["choices"][0]["message"]["content"]


def build_llm() -> LLM:
    provider = os.getenv("LLM_PROVIDER", "").strip().lower()
    if not provider:
        return DeterministicLLM()
    return OpenAICompatibleLLM(
        model=os.getenv("LLM_MODEL", "gpt-4o-mini"),
        base_url=os.getenv("LLM_BASE_URL", "https://api.openai.com/v1"),
        api_key=os.getenv("LLM_API_KEY", ""),
    )