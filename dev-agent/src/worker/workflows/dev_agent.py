import asyncio
import os
import tempfile
from datetime import timedelta
from pathlib import Path

import httpx
from mistralai import Mistral
from pydantic import BaseModel, Field

import mistralai.workflows as workflows

from worker.workflows.fixparse import extract_diff
from worker.workflows.payloads import is_self_push, parse_event

MODEL = "mistral-large-latest"
BOT_MARKER = "[dev-agent]"
GITHUB_API = "https://api.github.com"

SYSTEM_PROMPT = """You are dev-agent, a senior Swift/macOS engineer. A GitHub Actions CI run \
(macOS runner, `swift build` then `swift test`) failed for a SwiftPM package. Produce a MINIMAL \
fix as a unified git diff that makes CI pass.

Rules:
- Only touch repository files; keep the change minimal and idiomatic for the existing code style.
- Output ONLY one fenced code block with language `diff` containing the unified diff (paths a/... b/...).
- If the failure is environmental and not fixable in code, output an empty diff block and explain in one line above it.
- Never include secrets or tokens. Do not modify .github/workflows unless the workflow file itself is broken.
"""


class DevAgentInput(BaseModel):
    repo: str = "cufk/stemsplitter-macos"
    branch: str = "vibe/stemsplitter-1c69f9"
    max_iterations: int = 5
    poll_interval_seconds: int = 60
    event: dict | None = None


class DevAgentResult(BaseModel):
    status: str
    iterations: int = 0
    log: list[str] = Field(default_factory=list)


def _github_token() -> str:
    token = os.environ.get("GITHUB_TOKEN", "").strip()
    if not token:
        raise RuntimeError("GITHUB_TOKEN saknas — binda workspace-secret 'github_token' till deploymenten")
    return token


def _github_client() -> httpx.AsyncClient:
    return httpx.AsyncClient(
        base_url=GITHUB_API,
        headers={
            "Authorization": f"Bearer {_github_token()}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
        follow_redirects=True,
        timeout=60.0,
    )


def _mistral_client() -> Mistral:
    token_path = os.environ.get("MISTRAL_SA_TOKEN_PATH")
    if token_path and os.path.exists(token_path):
        with open(token_path) as handle:
            return Mistral(api_key=handle.read().strip())
    return Mistral(api_key=os.environ.get("MISTRAL_API_KEY"))


async def _run(cmd: list[str], cwd: str, env: dict) -> tuple[int, str]:
    proc = await asyncio.create_subprocess_exec(
        *cmd, cwd=cwd, env=env,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.STDOUT,
    )
    out, _ = await proc.communicate()
    return proc.returncode or 0, out.decode(errors="replace")


@workflows.activity(start_to_close_timeout=timedelta(minutes=2), retry_policy_max_attempts=3)
async def latest_ci_run(repo: str, branch: str) -> dict:
    async with _github_client() as client:
        response = await client.get(
            f"/repos/{repo}/actions/runs", params={"branch": branch, "per_page": 1}
        )
        response.raise_for_status()
        runs = response.json().get("workflow_runs", [])
        if not runs:
            return {"id": None, "status": "no_runs", "conclusion": None, "head_sha": None, "url": None}
        run = runs[0]
        return {
            "id": run["id"],
            "status": run["status"],
            "conclusion": run.get("conclusion"),
            "head_sha": run["head_sha"],
            "url": run["html_url"],
        }


@workflows.activity(start_to_close_timeout=timedelta(minutes=5), retry_policy_max_attempts=2)
async def failed_job_logs(repo: str, run_id: int, max_chars: int = 60000) -> str:
    async with _github_client() as client:
        response = await client.get(
            f"/repos/{repo}/actions/runs/{run_id}/jobs", params={"per_page": 100}
        )
        response.raise_for_status()
        chunks = []
        for job in response.json().get("jobs", []):
            if job.get("conclusion") in ("failure", "cancelled", "timed_out"):
                logs = await client.get(f"/repos/{repo}/actions/jobs/{job['id']}/logs")
                if logs.status_code == 200:
                    chunks.append(f"### Job: {job['name']}\n{logs.text}")
        text = "\n\n".join(chunks) if chunks else "No failed job logs available."
        return text[:max_chars]


@workflows.activity(start_to_close_timeout=timedelta(minutes=10), retry_policy_max_attempts=2)
async def propose_fix(repo: str, branch: str, logs: str, attempts: list[str]) -> str:
    history = ""
    if attempts:
        history = "Previous attempts (did not make CI green):\n" + "\n\n".join(
            f"--- attempt {i + 1} ---\n{a}" for i, a in enumerate(attempts)
        )
    user_message = (
        f"Repository: {repo}\nBranch: {branch}\n\n"
        f"CI failed job logs:\n{logs}\n\n{history}\n\nProduce the fix diff now."
    )
    client = _mistral_client()
    response = client.chat.complete(
        model=MODEL,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_message},
        ],
        temperature=0.2,
    )
    return response.choices[0].message.content or ""


@workflows.activity(start_to_close_timeout=timedelta(minutes=10), retry_policy_max_attempts=1)
async def apply_fix_and_push(repo: str, branch: str, diff: str) -> dict:
    token = _github_token()
    header = f"AUTHORIZATION: bearer {token}"
    env = {**os.environ, "GIT_TERMINAL_PROMPT": "0"}
    workdir = tempfile.mkdtemp(prefix="dev-agent-")
    url = f"https://github.com/{repo}.git"

    code, out = await _run(
        ["git", "-c", f"http.extraheader={header}", "clone", "--depth", "50", "--branch", branch, url, workdir],
        cwd="/tmp", env=env,
    )
    if code != 0:
        return {"pushed": False, "error": f"clone failed: {out[-2000:]}"}

    diff_path = Path(workdir) / "fix.diff"
    diff_path.write_text(diff)
    code, out = await _run(["git", "apply", "--check", "fix.diff"], cwd=workdir, env=env)
    if code != 0:
        code, out = await _run(["git", "apply", "fix.diff"], cwd=workdir, env=env)
        if code != 0:
            return {"pushed": False, "error": f"git apply failed: {out[-2000:]}"}
    else:
        await _run(["git", "apply", "fix.diff"], cwd=workdir, env=env)

    await _run(["git", "add", "-A"], cwd=workdir, env=env)
    code, out = await _run(
        ["git", "-c", "user.name=dev-agent", "-c", "user.email=dev-agent@users.noreply.github.com",
         "commit", "-m", f"fix(ci): automated fix {BOT_MARKER}"],
        cwd=workdir, env=env,
    )
    if code != 0 and "nothing to commit" not in out:
        return {"pushed": False, "error": f"commit failed: {out[-2000:]}"}

    code, out = await _run(
        ["git", "-c", f"http.extraheader={header}", "push", "origin", f"HEAD:{branch}"],
        cwd=workdir, env=env,
    )
    if code != 0:
        return {"pushed": False, "error": f"push failed: {out[-2000:]}"}

    _, sha = await _run(["git", "rev-parse", "HEAD"], cwd=workdir, env=env)
    return {"pushed": True, "sha": sha.strip()}


@workflows.activity(start_to_close_timeout=timedelta(minutes=2), retry_policy_max_attempts=3)
async def comment_on_pr(repo: str, branch: str, body: str) -> dict:
    owner = repo.split("/")[0]
    async with _github_client() as client:
        response = await client.get(
            f"/repos/{repo}/pulls", params={"head": f"{owner}:{branch}", "state": "open"}
        )
        response.raise_for_status()
        prs = response.json()
        if not prs:
            return {"commented": False, "reason": "no open PR for branch"}
        number = prs[0]["number"]
        created = await client.post(
            f"/repos/{repo}/issues/{number}/comments", json={"body": body[:60000]}
        )
        created.raise_for_status()
        return {"commented": True, "pr": number}


@workflows.workflow.define(
    name="dev-agent",
    workflow_display_name="Dev Agent (CI fix loop)",
    workflow_description="Watch CI for a branch; on failure, propose a diff with an LLM, push it, and repeat until CI is green.",
    execution_timeout=timedelta(hours=3),
)
class DevAgentWorkflow:
    @workflows.workflow.entrypoint
    async def run(self, input: DevAgentInput) -> DevAgentResult:
        log: list[str] = []
        repo, branch = input.repo, input.branch
        if input.event:
            event_repo, event_branch, _ = parse_event(input.event)
            if event_repo:
                repo = event_repo
            if event_branch:
                branch = event_branch
            if is_self_push(input.event):
                return DevAgentResult(status="skipped_self_push", log=["push from dev-agent itself; skipping"])

        attempts: list[str] = []
        for iteration in range(input.max_iterations):
            run = await latest_ci_run(repo, branch)
            log.append(
                f"iter {iteration}: run={run['id']} status={run['status']} conclusion={run['conclusion']}"
            )
            if run["status"] != "completed":
                await asyncio.sleep(input.poll_interval_seconds)
                continue
            if run["conclusion"] == "success":
                await comment_on_pr(
                    repo, branch,
                    f"dev-agent: CI is green ✅ (run {run['id']}) after {iteration} iteration(s).",
                )
                return DevAgentResult(status="ci_green", iterations=iteration, log=log)
            if run["conclusion"] in ("failure", "cancelled", "timed_out"):
                logs = await failed_job_logs(repo, run["id"])
                proposal = await propose_fix(repo, branch, logs, attempts)
                diff = extract_diff(proposal)
                if not diff:
                    log.append(f"iter {iteration}: no diff in proposal: {proposal[:300]}")
                    attempts.append(proposal)
                    await asyncio.sleep(input.poll_interval_seconds)
                    continue
                attempts.append(diff)
                result = await apply_fix_and_push(repo, branch, diff)
                if result.get("pushed"):
                    log.append(f"iter {iteration}: pushed fix {result.get('sha')}")
                else:
                    log.append(f"iter {iteration}: apply/push failed: {result.get('error')}")
                await asyncio.sleep(input.poll_interval_seconds)
            else:
                await asyncio.sleep(input.poll_interval_seconds)

        await comment_on_pr(
            repo, branch,
            "dev-agent: gave up after max iterations; CI is still failing. See execution log for details.",
        )
        return DevAgentResult(status="gave_up", iterations=input.max_iterations, log=log)
