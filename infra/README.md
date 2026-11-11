# infra

One Terraform root, `snowflake`, applied from AWS CloudShell by [`snowflake.sh`](snowflake.sh),
which shows Terraform's plan and waits for a yes. Its state lives in the AWS account's Terraform
state bucket, under `aws-snowflake/`, beside data-platform-aws-databricks' roots, whose bootstrap
made the bucket. CI checks the format and validates the root against the provider's schema on every
push.

## snowflake

Everything a deploying project's warehouse needs in the account.

| Role | Raw and their staging schemas | Staging, intermediate and reference | Marts | Warehouse |
| --- | --- | --- | --- | --- |
| `LOADER` | make tables and stages, and masking policies on what it loaded | nothing | nothing | `LOAD_WH` |
| `BUILDER` | read what was loaded | make tables and views | make tables and views | `BUILD_WH` |
| `READER` | nothing | nothing | read | `READ_WH` |

Reads are granted on future tables and views, so what a job makes later is covered as it is made.
Every schema has managed access, so a table's owner cannot grant on it; only this root does. The
three job roles sit under `SYSADMIN`. `PERSONAL_DATA_READER` sits under no one.

Each deploying repository gets two service users, one for its load and one for its build, each
with its job's role as its only one. A user trusts one OIDC subject, made from the repository's
owner and name with their numeric ids and the job's GitHub environment:

```text
repo:OWNER@OWNER_ID/REPOSITORY@REPOSITORY_ID:environment:snowflake-load
```

and one audience, the account's own address. The `service_users` output lists every user with its
subject, to check a refused sign-in against.

### The first apply

1. Sign up for the 30-day trial: Enterprise edition, AWS, US East (N. Virginia).
2. From AWS CloudShell:

   ```bash
   git clone https://github.com/iamkevinstreet/data-platform-aws-snowflake
   cd data-platform-aws-snowflake
   bash infra/snowflake.sh
   ```

   The script makes a key pair in CloudShell's home (`~/.snowflake/`, readable by its owner only)
   and prints three SQL statements that make `KDS_TERRAFORM`, a service user with the public key
   and the `ACCOUNTADMIN` role, which a resource monitor needs. Run them once in Snowsight with
   the `ACCOUNTADMIN` role, in a SQL file (Projects, Workspaces, + Add New, SQL File), then give
   the script the account identifier, ORGNAME-ACCOUNTNAME, from Snowsight's account menu.
3. Set what the script prints in each deploying repository: the secret `SNOWFLAKE_ACCOUNT`, the
   variable `SNOWFLAKE_DATABASE`, and the two environments, each limited to the main branch.

After that, `git pull` and `bash infra/snowflake.sh` again for any change. When the trial ends:

```bash
bash infra/snowflake.sh -destroy
```

then, in a SQL file in Snowsight, `DROP USER KDS_TERRAFORM;`, and in CloudShell,
`rm -r ~/.snowflake`.

## Not yet known

These are checked on the first apply and the first runs: whether a trial account lets a service
user sign in by GitHub's OIDC token as this root sets it up, whether the subject GitHub sends for a
job with an environment is the form above, and how many credits a day's runs use.
