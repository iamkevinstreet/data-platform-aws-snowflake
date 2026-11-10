#!/usr/bin/env bash
########################################################################
#                                                                      #
#                          infra/terraform.sh                          #
#                                                                      #
########################################################################
# Author:            Kevin Street
# Created on:        2026-11-10
# Last modified on:  2026-11-10
#
# What the apply script needs, sourced, never run: Terraform installed
# when AWS CloudShell lacks it (a new session starts without it), and
# the account's one state bucket, which data-platform-aws-databricks'
# bootstrap made.
#
#   source "$(dirname "$0")/terraform.sh"

REPO="https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo"

# Terraform from its official zip, checked against its checksums.
install_terraform_zip() {
  local version arch dir
  version="$(curl -fsS https://checkpoint-api.hashicorp.com/v1/check/terraform \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["current_version"])')"
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *) echo "No Terraform build for $(uname -m)" >&2; exit 1 ;;
  esac
  dir="$(mktemp -d)"
  curl -fsSLo "${dir}/terraform_${version}_linux_${arch}.zip" \
    "https://releases.hashicorp.com/terraform/${version}/terraform_${version}_linux_${arch}.zip"
  curl -fsSLo "${dir}/SHA256SUMS" \
    "https://releases.hashicorp.com/terraform/${version}/terraform_${version}_SHA256SUMS"
  if ! (cd "${dir}" && grep "_linux_${arch}.zip" SHA256SUMS | sha256sum -c -); then
    echo "The Terraform download does not match HashiCorp's checksum" >&2
    exit 1
  fi
  unzip -q "${dir}/terraform_${version}_linux_${arch}.zip" -d "${dir}"
  sudo install -m 0755 "${dir}/terraform" /usr/local/bin/terraform
}

# Terraform, from HashiCorp's package repository, else its zip.
ensure_terraform() {
  if ! command -v terraform >/dev/null 2>&1; then
    if ! { sudo dnf install -y dnf-plugins-core \
      && sudo dnf config-manager --add-repo "${REPO}" \
      && sudo dnf install -y terraform; }; then
      install_terraform_zip
    fi
  fi
}

# The state bucket the bootstrap made, the account's one bucket whose
# name ends in -tfstate; stops when there is none or more than one.
state_bucket() {
  local found
  found="$(aws s3api list-buckets --query "Buckets[?ends_with(Name, '-tfstate')].Name" \
    --output text)"
  if [[ -z "${found}" || "${found}" == *[[:space:]]* ]]; then
    echo "Expected one bucket ending in -tfstate, found: ${found:-none}." >&2
    echo "data-platform-aws-databricks' infra/bootstrap.sh makes it; run that first." >&2
    exit 1
  fi
  echo "${found}"
}
