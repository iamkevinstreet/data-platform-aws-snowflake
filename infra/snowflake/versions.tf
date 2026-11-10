# Author:            Kevin Street
# Created on:        2026-11-10
# Last modified on:  2026-11-10
#
# Terraform and the Snowflake provider this root needs. The provider
# reads the account, the user, its role and its private key from the
# environment, which infra/snowflake.sh sets; nothing here names the
# account.

terraform {
  required_version = ">= 1.10"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = ">= 2.19, < 3.0"
    }
  }

  backend "s3" {}
}

provider "snowflake" {}
