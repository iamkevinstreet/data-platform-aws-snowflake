# Changelog

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
