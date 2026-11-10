# Author:            Kevin Street
# Created on:        2026-11-10
# Last modified on:  2026-11-10
#
# What a deploying repository needs: the database, and the service user
# for each of its jobs with the OIDC subject that user trusts, which a
# failed sign-in can be checked against.

output "database" {
  description = "The database every schema lives in; a deploying repository's SNOWFLAKE_DATABASE."
  value       = snowflake_database.warehouse.name
}

output "service_users" {
  description = "Each deploying repository's service users, with the OIDC subject each trusts."
  value       = { for name, user in local.job_users : name => user.subject }
}
