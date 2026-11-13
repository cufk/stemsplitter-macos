"""Parsing of GitHub webhook payloads. Stdlib only, so it is unit-testable without the SDK."""


def parse_event(event: dict) -> tuple[str, str, str | None]:
    """Return (repo_full_name, branch, head_sha) from a GitHub push or pull_request payload."""
    if not isinstance(event, dict):
        return "", "", None
    repository = event.get("repository") or {}
    repo = repository.get("full_name") or ""

    ref = event.get("ref") or ""
    if ref.startswith("refs/heads/"):
        branch = ref[len("refs/heads/"):]
        return repo, branch, event.get("after") or None

    pr = event.get("pull_request")
    if isinstance(pr, dict):
        head = pr.get("head") or {}
        head_repo = head.get("repo") or {}
        return head_repo.get("full_name") or repo, head.get("ref") or "", head.get("sha")

    return repo, "", None


def is_self_push(event: dict, marker: str = "[dev-agent]") -> bool:
    """True if every commit in a push event carries the bot marker (avoids infinite loops)."""
    commits = event.get("commits")
    if not isinstance(commits, list) or not commits:
        return False
    return all(marker in (c.get("message") or "") for c in commits)
