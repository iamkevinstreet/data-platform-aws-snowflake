# Security

## Reporting a vulnerability

Please report it privately, never in a public issue:

- **Preferred:** GitHub's private vulnerability reporting (the repository's **Security** tab, then
  **Report a vulnerability**).
- **Otherwise:** email info@kevindstreet.com with "Security" in the subject.

Include what you found, how to reproduce it, and what an attacker could do with it. You will get an
answer within 3 business days. A confirmed issue is fixed within 30 days, sooner when severe, and you
are credited in the advisory unless you would rather not be.

## Scope

In scope: the Terraform in `infra/`, the apply script, the tests and the workflows in `.github/`,
and above all any way to sign in as a service user from a repository or job not listed, to widen a
role's reach, to see a personal field unmasked, or to spend past the monthly credit quota.

Out of scope: the projects that deploy here, which have their own repositories, GitHub, AWS and
Snowflake themselves, and findings that need a compromised developer machine.

## How this repository is protected

| Risk | Control |
| --- | --- |
| A password or key for a job that could leak | None exists: each service user signs in with its workflow's GitHub OIDC token, trusted for one repository, by name and numeric id, and one job's GitHub environment, with an audience scoped to this account |
| A role that can do too much | A role and a warehouse per job: loaders write the raw schemas, builders read raw and write the models, readers read the marts; every schema has managed access, so a table's owner cannot grant on it; tests check the Terraform |
| A personal field seen | The role a project's masking policy lets see one is granted to no one, not even the administrators; a test checks no grant names it |
| A runaway bill | X-Small warehouses that suspend after a minute idle, and a monthly credit quota that suspends them all |
| Terraform's own key | Made in AWS CloudShell's home, readable by its owner only, for one service user; never printed, committed or copied; delete the user and the key when the trial ends |
| Terraform state anyone can read | The account's state bucket is private, versioned and encrypted; no state is committed |
| A committed secret | gitleaks before every commit and over the whole history in CI; anything that names an account lives in GitHub secrets only |
| A vulnerable dependency | A lockfile with hashes, `pip-audit` in CI, Dependabot every week for the Actions, the Python checks and the Terraform provider, each update landed only after the whole of CI passes on it |
| A tampered Action or tool | Actions pinned to commit SHAs; the gitleaks download checked against its published SHA-256; the Terraform zip, when CloudShell needs it, checked against HashiCorp's published SHA-256 |
