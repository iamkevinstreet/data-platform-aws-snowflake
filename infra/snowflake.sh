#!/usr/bin/env bash
########################################################################
#                                                                      #
#                          infra/snowflake.sh                          #
#                                                                      #
########################################################################
# Author:            Kevin Street
# Created on:        2026-11-10
# Last modified on:  2026-11-10
#
# Applies the snowflake root from AWS CloudShell, its state in the
# account's Terraform state bucket under aws-snowflake/. Terraform signs
# in as KDS_TERRAFORM, a service user with a key pair made here: the
# private key stays in CloudShell's home, readable by its owner only,
# and never leaves it. The first time, the script prints the SQL that
# makes the user with the public key, to run once in a Snowsight
# worksheet. Then Terraform shows its plan and waits for a yes.
#
#   bash infra/snowflake.sh
#
# Arguments are passed to terraform apply. To tear everything down when
# the trial ends: bash infra/snowflake.sh -destroy

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/snowflake" && pwd)"
# shellcheck source=infra/terraform.sh
source "$(dirname "$0")/terraform.sh"

USER_NAME="KDS_TERRAFORM"
KEY_DIR="${HOME}/.snowflake"
KEY="${KEY_DIR}/kds-terraform.p8"

# The state bucket, and its region, which the backend needs.
STATE="$(state_bucket)"
REGION="$(aws s3api get-bucket-location --bucket "${STATE}" \
  --query LocationConstraint --output text)"
if [[ "${REGION}" == "None" ]]; then
  REGION="us-east-1"
fi

# The key pair, made once; the private key is unencrypted but readable
# by CloudShell's user alone.
if [[ ! -f "${KEY}" ]]; then
  mkdir -p "${KEY_DIR}"
  chmod 700 "${KEY_DIR}"
  (umask 077 && openssl genrsa 2048 2>/dev/null | openssl pkcs8 -topk8 -nocrypt -out "${KEY}")
fi
PUBLIC="$(openssl rsa -in "${KEY}" -pubout 2>/dev/null | grep -v -- '-----' | tr -d '\n')"

cat <<EOF

Once, in a Snowsight worksheet with the ACCOUNTADMIN role, run:

  CREATE USER IF NOT EXISTS ${USER_NAME} TYPE = SERVICE DEFAULT_ROLE = ACCOUNTADMIN
    COMMENT = 'Terraform, from AWS CloudShell: data-platform-aws-snowflake.';
  ALTER USER ${USER_NAME} SET RSA_PUBLIC_KEY = '${PUBLIC}';
  GRANT ROLE ACCOUNTADMIN TO USER ${USER_NAME};

Running it again is safe.

EOF

# The account, as Snowsight's account menu shows it: ORGNAME-ACCOUNTNAME.
read -rp "Snowflake account identifier, ORGNAME-ACCOUNTNAME: " account
account="$(tr '[:lower:]' '[:upper:]' <<<"${account// /}")"
if [[ ! "${account}" =~ ^[A-Z0-9]+-[A-Z0-9_]+$ ]]; then
  echo "Expected ORGNAME-ACCOUNTNAME, such as MYORG-MYACCOUNT; got ${account}." >&2
  exit 1
fi
read -rp "Press Enter once the worksheet has run. " _

export SNOWFLAKE_ORGANIZATION_NAME="${account%%-*}"
export SNOWFLAKE_ACCOUNT_NAME="${account#*-}"
export SNOWFLAKE_USER="${USER_NAME}"
export SNOWFLAKE_ROLE="ACCOUNTADMIN"
export SNOWFLAKE_AUTHENTICATOR="SNOWFLAKE_JWT"
SNOWFLAKE_PRIVATE_KEY="$(cat "${KEY}")"
export SNOWFLAKE_PRIVATE_KEY

# The audience a deploying workflow's token is made for: this account.
AUDIENCE="https://$(tr '[:upper:]' '[:lower:]' <<<"${account}").snowflakecomputing.com"

# Terraform, installed when this CloudShell session lacks it.
ensure_terraform

# Providers run to hundreds of megabytes: keep them out of the home.
export TF_DATA_DIR="${TMPDIR:-/tmp}/data-platform-aws-snowflake-terraform/snowflake"

# The root's backend, written beside it; git ignores backend.hcl.
cat > "${ROOT}/backend.hcl" <<EOF
bucket       = "${STATE}"
key          = "aws-snowflake/snowflake/terraform.tfstate"
region       = "${REGION}"
encrypt      = true
use_lockfile = true
EOF

terraform -chdir="${ROOT}" init -input=false -backend-config=backend.hcl
# Shows the plan and waits for a yes; -input=false would refuse instead.
terraform -chdir="${ROOT}" apply -var "oidc_audience=${AUDIENCE}" "$@"

# Nothing to set after a teardown.
if [[ " $* " == *" -destroy "* ]]; then
  exit 0
fi

echo
echo "Done. In each deploying repository: Settings, Secrets and variables, Actions."
echo "  Secret    SNOWFLAKE_ACCOUNT  = ${account}"
echo "  Variable  SNOWFLAKE_DATABASE = $(terraform -chdir="${ROOT}" output -raw database)"
echo "And two environments, snowflake-load and snowflake-build, each limited to main."
