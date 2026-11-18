# dev-agent — Mistral Workflow som fixar CI tills den är grön

En durable workflow (`dev-agent`) som bevakar CI för detta repo och, när bygget/testerna failar:

1. läser senaste workflow-run för branchen via GitHub API,
2. hämtar loggarna för failade jobb,
3. ber en Mistral-modell (`mistral-large-latest`) föreslå en minimal fix som unified diff,
4. klonar repot, applicerar diffen, committar med `[dev-agent]`-markör och pushar,
5. väntar på nästa CI-körning och loopar (max `max_iterations`, default 5) tills CI är grön,
6. kommenterar på öppen PR med resultatet.

Pushar från agenten själv detekteras via `[dev-agent]` i commit-meddelandet och startar ingen ny loop.

## Struktur

```
dev-agent/
  pyproject.toml          beroenden (mistralai-workflows>=3.10, mistralai, httpx, pydantic)
  Dockerfile              managed-deployment-bild (python:3.12-slim + git)
  src/worker/
    entrypoints/worker.py auto-discover + run_worker
    workflows/dev_agent.py själva workflowen + activities
    workflows/payloads.py  webhook-payload-parsing (stdlib-only, testad)
    workflows/fixparse.py  extraherar diff ur LLM-svar (stdlib-only, testad)
  tests/test_payloads.py  unittest för payloads/fixparse (körs utan SDK)
```

## Köra lokalt

```sh
cd dev-agent
python3 -m unittest discover -s tests -v   # enhetstester (ingen SDK behövs)
uv sync                                     # eller: pip install -e ".[dev]"
MISTRAL_API_KEY=... python -m worker.entrypoints.worker
```

## Driftsättning (managed deployment)

Kräver:

- **Workspace secret `github_token`** i Mistral Studio: en GitHub PAT (classic, scope `repo`) eller fine-grained PAT med åtkomst till `cufk/stemsplitter-macos` (läsa Actions-loggar + pusha commits). Bind den till deploymenten som env-variabeln `GITHUB_TOKEN`.
- Mistral GitHub App installerad på repot (klonar vid build).

Deployment bygger från detta repo med `build_directory=dev-agent`, `dockerfile_path=Dockerfile`, på den pushade commiten.

Trigger: GitHub-webhook (push/pull_request på `cufk/stemsplitter-macos`) eller ett schema (cron). Workflow-input kan också ges manuellt: `{ "repo": ..., "branch": ... }`.
