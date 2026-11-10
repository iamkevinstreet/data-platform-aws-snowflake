# Data platform: AWS with Snowflake

[![ci](https://github.com/iamkevinstreet/data-platform-aws-snowflake/actions/workflows/ci.yml/badge.svg)](https://github.com/iamkevinstreet/data-platform-aws-snowflake/actions/workflows/ci.yml)
[![codeql](https://github.com/iamkevinstreet/data-platform-aws-snowflake/actions/workflows/codeql.yml/badge.svg)](https://github.com/iamkevinstreet/data-platform-aws-snowflake/actions/workflows/codeql.yml)

Where projects run on Snowflake, in a Snowflake account on AWS. Every project follows the same
blueprint, and this is its bottom layer: the place its data lands and its warehouse runs. This
repository provisions it, in Terraform: a database with a schema per layer, a small warehouse for
each job under a monthly credit quota, a role for each job, and a service user for each project's
jobs that signs in with its GitHub workflow's token, so no password or key exists for any job. It
is the second of six platform repositories, one for each pairing of AWS, Azure or Google Cloud with
Databricks or Snowflake.

## Status

| Part | State |
| --- | --- |
| The snowflake root | Written and tested without an account; applied once the 30-day trial starts |
| Deploying here | Next: [eeoc-charge-intake](https://github.com/iamkevinstreet/eeoc-charge-intake) and [ai-operations](https://github.com/iamkevinstreet/ai-operations), each loading and building here every day beside DuckDB and Databricks |

The trial is chosen at sign-up: Enterprise edition, which masking policies need, on AWS in US East
(N. Virginia), beside the lake. It ends after 30 days or when its free credit runs out, whichever
comes first; everything here is then torn down with Terraform unless kept on purpose.

## What it provides

| Piece | What it is | Where |
| --- | --- | --- |
| Database `KDS` | A schema per layer (raw, staging, intermediate, reference, the marts) and one for each load's staging, each with managed access | [infra/snowflake/main.tf](infra/snowflake/main.tf) |
| Warehouses | `LOAD_WH`, `BUILD_WH` and `READ_WH`, X-Small, suspended after a minute idle, so each job's credits show on their own | [infra/snowflake/main.tf](infra/snowflake/main.tf) |
| Credit quota | `KDS_MONTHLY`: a notice at half and four fifths, every warehouse suspended at the quota (20 credits a month by default) | [infra/snowflake/main.tf](infra/snowflake/main.tf) |
| Roles | `LOADER` writes raw, `BUILDER` reads raw and writes the models, `READER` reads the marts; `PERSONAL_DATA_READER`, granted to no one, is the one role a project's masking policy shows a personal field to | [infra/snowflake/main.tf](infra/snowflake/main.tf) |
| Service users | One per deploying repository and job, such as `EEOC_CHARGE_INTAKE_LOAD`, signed in by GitHub's OIDC token: the subject names the repository by name and id and the job's GitHub environment | [infra/snowflake/main.tf](infra/snowflake/main.tf) |
| Deployers | The repositories with service users, each by owner/name and numeric id | [infra/snowflake/variables.tf](infra/snowflake/variables.tf) |
| Apply script | Applies the root from AWS CloudShell, signing Terraform in with a key that never leaves CloudShell | [infra/snowflake.sh](infra/snowflake.sh) |

## How a project deploys here

1. Add its repository to `deployers` in [infra/snowflake/variables.tf](infra/snowflake/variables.tf),
   by owner/name and numeric id (`gh api repos/OWNER/NAME --jq .id`), and apply again.
2. In that repository's settings, set the secret `SNOWFLAKE_ACCOUNT` (ORGNAME-ACCOUNTNAME) and the
   variable `SNOWFLAKE_DATABASE` (`KDS`), and make two environments, `snowflake-load` and
   `snowflake-build`, each limited to the main branch.
3. Run the load in a job with `environment: snowflake-load` and the build in one with
   `environment: snowflake-build`, each with `id-token: write`. Each asks GitHub for a token whose
   audience is the account's address, `https://orgname-accountname.snowflakecomputing.com`, and
   signs in with it (`authenticator: workload_identity`, provider `OIDC`), as its own service user
   with its own role. No other credential is needed.

Anything that names the account is a secret, not a variable, because a public repository's logs
are public.

## Set up or change it

From AWS CloudShell, as [infra/README.md](infra/README.md) describes: clone this repository and run
`bash infra/snowflake.sh`. The first time, it prints the SQL that makes Terraform's own service user,
to run once in a Snowsight worksheet. Terraform shows its plan and waits for a yes; read the plan
before answering, as it should change only what was edited.

## The pairings

The same projects, deployed on each pairing and measured the same way. This repository's row is
in bold.

| Pairing | Setup | The EEOC warehouse's daily run | Cost | Who the jobs run as |
| --- | --- | --- | --- | --- |
| [AWS with Databricks](https://github.com/iamkevinstreet/data-platform-aws-databricks) (Free Edition) | Terraform from CloudShell with a workspace token; account groups made by hand | Both loads in 58 s and 26 s, all 126 seeds, models and tests in 64 s (Nov 10) | Nothing | One person's token, the owner of what it makes; a column mask hides names from everyone |
| **AWS with Snowflake (trial)** | **Terraform from CloudShell with a key that never leaves it** | **Not yet run** | **Trial credits, under a 20-credit monthly quota** | **A service user per job, by GitHub's OIDC token; a masking policy hides names from every role** |

## Costs

An X-Small warehouse uses one credit an hour while it runs and suspends after a minute idle, so a
daily run of a minute or two uses a small fraction of a credit. Storage for a few megabytes is
negligible. The monthly quota suspends every warehouse before the trial's credit can run out.

## Layout

```text
infra/snowflake/    the database, warehouses, quota, roles, grants and service users
infra/snowflake.sh  every apply, and the teardown, from AWS CloudShell
infra/terraform.sh  what the script sources: Terraform's install and the state bucket
tests/              the Terraform read without a Snowflake account
```

## Testing

```bash
make install   # the checks' environment, from uv.lock
make check     # lint, format, strict types and the code standard
make test      # 8 tests: the Terraform parsed and its rules checked
```

CI also runs `terraform fmt` and `terraform validate` on the root.

## Changelog and license

[CHANGELOG.md](CHANGELOG.md) lists every change, and [SECURITY.md](SECURITY.md) how to report a
vulnerability. Apache 2.0: see [LICENSE](LICENSE) and [NOTICE](NOTICE).
