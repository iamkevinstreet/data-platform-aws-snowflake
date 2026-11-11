# Changelog

## Unreleased

- **First applied, Nov 10:** 65 resources, on an Enterprise trial. eeoc-charge-intake and
  ai-operations then loaded and built here, each job signed in as its own service user with its
  workflow's OIDC token: the EEOC's 127 seeds, models and tests in 30 s, the charging party's name
  masked by a masking policy, and AI operations' 128 in 32 s. The README's pairings table now holds
  both projects' measured times beside Databricks', from the same runs, and the credits used.
- **Each project's credits,** from the scheduled runs of Nov 11, in the pairings table and under
  Costs: 0.082 for the EEOC's daily run and 0.079 for AI operations', warehouse time and cloud
  services together, as Snowflake's metering reports them by the hour. They replace Nov 10's 0.19,
  which was read before all of that day's cloud services had been metered: the complete figure for
  its three loads and three builds is 0.23.
- **A link to the case study** on kevindstreet.com, under the README's first paragraph.
- **Where the first SQL runs,** in the README, the setup notes and the script's own words: a SQL
  file in Snowsight's Workspaces, which have replaced its worksheets.

## v0.1.0, Nov 10, 2026

- **The snowflake root,** for a Snowflake account on AWS: the `KDS` database with a schema per
  layer and one for each load's staging, every schema with managed access; an X-Small warehouse for
  each job (`LOAD_WH`, `BUILD_WH`, `READ_WH`) that suspends after a minute idle, under a monthly
  credit quota (20 by default) that suspends them all; a role for each job, `LOADER`, `BUILDER` and
  `READER`, with what each may do; and `PERSONAL_DATA_READER`, granted to no one, for the projects'
  masking policies.
- **Secretless service users:** one per deploying repository and job, signed in with the
  workflow's GitHub OIDC token through Snowflake's workload identity federation. Each trusts one
  subject, the repository by name and id and the job's GitHub environment, `snowflake-load` or
  `snowflake-build`, with an audience scoped to the account. No password or key exists for them.
- **`infra/snowflake.sh` applies it** from AWS CloudShell, its state in the account's Terraform
  state bucket under `aws-snowflake/`. Terraform signs in as `KDS_TERRAFORM`, with a key pair made
  in CloudShell's home that never leaves it; the script prints the SQL that makes the user, to run
  once in a Snowsight worksheet. `-destroy` tears everything down when the trial ends.
- 8 tests: the Terraform parsed and its rules checked without an account.
