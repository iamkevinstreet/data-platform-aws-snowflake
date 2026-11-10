# Author:            Kevin Street
# Created on:        2026-11-10
# Last modified on:  2026-11-10
#
# What changes between accounts: the database's name, the repositories
# whose workflows load and build here, by name and by GitHub's numeric
# ids, the audience their tokens are made for, and the most credits the
# warehouses may spend in a month.

variable "database" {
  description = "The database every schema lives in; a deploying repository's SNOWFLAKE_DATABASE."
  type        = string
  default     = "KDS"
}

variable "deployers" {
  description = "Repositories whose workflows load and build here, by owner/name and id."
  type = list(object({
    repository = string
    id         = number
  }))
  default = [
    { repository = "iamkevinstreet/ai-operations", id = 1450000844 },
    { repository = "iamkevinstreet/eeoc-charge-intake", id = 1418185196 },
  ]

  validation {
    condition = length(var.deployers) > 0 && alltrue([
      for d in var.deployers : length(split("/", d.repository)) == 2
    ]) && length(distinct([for d in var.deployers : d.id])) == length(var.deployers)
    error_message = "Name at least one deployer, each as owner/name, each repository once."
  }
}

variable "github_owner_id" {
  description = "The repositories' owner's numeric GitHub id, part of the OIDC subject."
  type        = number
  default     = 747156
}

variable "oidc_audience" {
  description = "The audience a workflow's token is made for: the account's own address."
  type        = string

  validation {
    condition = (
      startswith(var.oidc_audience, "https://")
      && endswith(var.oidc_audience, ".snowflakecomputing.com")
    )
    error_message = "Use the account's address, https://ORG-ACCOUNT.snowflakecomputing.com."
  }
}

variable "credit_quota" {
  description = "The most credits the warehouses may use in a month before they are suspended."
  type        = number
  default     = 20

  validation {
    condition     = var.credit_quota > 0 && var.credit_quota <= 100
    error_message = "Keep the quota between 1 and 100 credits a month."
  }
}
