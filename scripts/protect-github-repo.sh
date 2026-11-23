#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Make the GitHub repository read-only for everyone except the owner.
#
#   * Only the owner has write access (no collaborators / teams). Visitors of a
#     public repo can read, fork and open PRs, but never push.
#   * Ruleset on the default branch: no deletion, no force-push, changes only via
#     pull request with passing CI. The repository admin (owner) may bypass.
#   * Workflows from fork PRs need approval for every outside contributor.
#   * Default GITHUB_TOKEN is read-only and cannot approve PRs.
#   * .github/CODEOWNERS (in the repo) makes the owner reviewer of every path.
#
# Idempotent - safe to re-run. Needs: gh (authenticated as the repo owner), jq.
# Usage: ./scripts/protect-github-repo.sh [owner/repo]
# -----------------------------------------------------------------------------
set -euo pipefail

REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
RULESET_NAME="protect-main"
echo "Repository: $REPO"

# 1. Nobody but the owner may have write access.
others=$(gh api "repos/$REPO/collaborators" --jq '[.[] | select(.role_name != "admin") | .login] | join(", ")')
if [[ -n "$others" ]]; then
  echo "WARNING: these collaborators still have access: $others" >&2
fi

# 2. Branch ruleset.
ruleset=$(jq -n --arg name "$RULESET_NAME" '{
  name: $name,
  target: "branch",
  enforcement: "active",
  conditions: { ref_name: { include: ["~DEFAULT_BRANCH"], exclude: [] } },
  bypass_actors: [
    { actor_id: 5, actor_type: "RepositoryRole", bypass_mode: "always" }
  ],
  rules: [
    { type: "deletion" },
    { type: "non_fast_forward" },
    { type: "pull_request", parameters: {
        required_approving_review_count: 0,
        dismiss_stale_reviews_on_push: true,
        require_code_owner_review: false,
        require_last_push_approval: false,
        required_review_thread_resolution: true
    } },
    { type: "required_status_checks", parameters: {
        strict_required_status_checks_policy: false,
        required_status_checks: [
          { context: "validate" },
          { context: "security-scan" }
        ]
    } }
  ]
}')

existing=$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$RULESET_NAME\") | .id")
if [[ -n "$existing" ]]; then
  echo "$ruleset" | gh api -X PUT "repos/$REPO/rulesets/$existing" --input - >/dev/null
  echo "Updated ruleset $RULESET_NAME (#$existing)"
else
  echo "$ruleset" | gh api -X POST "repos/$REPO/rulesets" --input - >/dev/null
  echo "Created ruleset $RULESET_NAME"
fi

# 3. Fork PRs: require approval before workflows run for any outside contributor.
gh api -X PUT "repos/$REPO/actions/permissions/fork-pr-contributor-approval" \
  -f approval_policy=all_external_contributors >/dev/null
echo "Fork PR workflows require approval for all external contributors"

# 4. Read-only default GITHUB_TOKEN; workflows cannot approve PRs.
gh api -X PUT "repos/$REPO/actions/permissions/workflow" \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=false >/dev/null
echo "Default GITHUB_TOKEN permissions: read"

echo "Done."
