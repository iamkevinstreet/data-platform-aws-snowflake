# Author:            Kevin Street
# Created on:        2026-11-10
# Last modified on:  2026-11-10
#
# Everything a deploying project's warehouse needs in Snowflake: one
# database with a schema per layer and one for each load's staging, a
# warehouse per job that suspends after a minute idle, a monthly credit
# quota over all three, a role per job with what it may do, and a
# service user for each deploying repository and job. A service user
# signs in with its workflow's GitHub OIDC token, so no password or key
# exists for it. Loaders write raw; builders read raw and write the
# models; readers read the marts. Every schema has managed access, so
# only this root grants on what is in it.

locals {
  raw_schemas = {
    RAW_AI_OPS     = "AI operations: the apps' committed results, loaded by dlt at pinned commits."
    RAW_REVIEWS    = "EEOC charge intake: review exports under contract v1, names masked."
    RAW_EEOC_STATS = "EEOC charge intake: the EEOC's Table E1a, charge receipts by basis."
  }
  # dlt merges each load through a schema of its own beside the dataset,
  # named with _STAGING.
  load_schemas = {
    for name in keys(local.raw_schemas) :
    "${name}_STAGING" => "dlt's staging for ${name}: each load's rows before they merge."
  }
  model_schemas = {
    STAGING      = "dbt staging views: one per raw table, named for its source."
    INTERMEDIATE = "dbt views that line each project's sources up to one grain."
    REFERENCE    = "dbt seeds: reference tables kept in each project's repository."
  }
  mart_schemas = {
    AI_OPS   = "The AI operations mart: runs, cases, calls, spans and costs."
    CHARGES  = "The EEOC charges mart: reviewed charges, field reviews, bridges and dimensions."
    NATIONAL = "The EEOC's national statistics, the charges' context."
  }
  schemas = merge(
    local.raw_schemas, local.load_schemas, local.model_schemas, local.mart_schemas,
  )

  roles = {
    LOADER               = "Loads raw data: makes and merges into the raw tables, and their masks."
    BUILDER              = "Builds the models: reads raw, writes the views and the marts."
    READER               = "Reads the published marts, and nothing under them."
    PERSONAL_DATA_READER = "Sees a personal field unmasked. Granted to no one."
  }

  # A warehouse for each job, so each job's credits show on their own.
  warehouses = {
    LOAD_WH  = { role = "LOADER", comment = "The loads: dlt's copies and merges into raw." }
    BUILD_WH = { role = "BUILDER", comment = "The builds: dbt's views, tables and tests." }
    READ_WH  = { role = "READER", comment = "Reading the marts: dashboards and people." }
  }

  # What loaders may do where they land data: make and merge into
  # tables, stage files, and keep the masks on what they loaded.
  loading = ["USAGE", "CREATE TABLE", "CREATE STAGE", "CREATE MASKING POLICY"]

  # What builders may do in the schemas dbt writes.
  building = ["USAGE", "CREATE TABLE", "CREATE VIEW"]

  # Each schema's grants, by role and schema.
  schema_grants = merge(
    {
      for s in keys(merge(local.raw_schemas, local.load_schemas)) :
      "LOADER.${s}" => { role = "LOADER", schema = s, privileges = local.loading }
    },
    {
      for s in keys(local.raw_schemas) :
      "BUILDER.${s}" => { role = "BUILDER", schema = s, privileges = ["USAGE"] }
    },
    {
      for s in keys(merge(local.model_schemas, local.mart_schemas)) :
      "BUILDER.${s}" => { role = "BUILDER", schema = s, privileges = local.building }
    },
    {
      for s in keys(local.mart_schemas) :
      "READER.${s}" => { role = "READER", schema = s, privileges = ["USAGE"] }
    },
  )

  # What each role may read of the tables and views made later: builders
  # what was loaded, readers the marts.
  future_reads = merge(
    {
      for s in keys(local.raw_schemas) :
      "BUILDER.${s}.TABLES" => { role = "BUILDER", schema = s, kind = "TABLES" }
    },
    {
      for pair in setproduct(keys(local.mart_schemas), ["TABLES", "VIEWS"]) :
      "READER.${pair[0]}.${pair[1]}" => { role = "READER", schema = pair[0], kind = pair[1] }
    },
  )

  # A service user for each deploying repository and job. Its workflow's
  # job names a GitHub environment, snowflake-load or snowflake-build, so
  # its OIDC subject, which names the repository by name and id, is that
  # job's alone.
  job_users = {
    for pair in setproduct(var.deployers, ["LOAD", "BUILD"]) :
    "${upper(replace(split("/", pair[0].repository)[1], "-", "_"))}_${pair[1]}" => {
      repository = pair[0].repository
      job        = lower(pair[1])
      role       = pair[1] == "LOAD" ? "LOADER" : "BUILDER"
      warehouse  = "${pair[1]}_WH"
      subject = format(
        "repo:%s@%d/%s@%d:environment:snowflake-%s",
        split("/", pair[0].repository)[0],
        var.github_owner_id,
        split("/", pair[0].repository)[1],
        pair[0].id,
        lower(pair[1]),
      )
    }
  }
}

resource "snowflake_database" "warehouse" {
  name                        = var.database
  comment                     = "The data platform's warehouse, managed by Terraform."
  data_retention_time_in_days = 1
}

resource "snowflake_schema" "layer" {
  for_each            = local.schemas
  database            = snowflake_database.warehouse.name
  name                = each.key
  comment             = each.value
  with_managed_access = true
}

# A monthly quota over every warehouse: a notice at half and at four
# fifths, then each warehouse suspends once its running queries end, and
# at once past a tenth over.
resource "snowflake_resource_monitor" "monthly" {
  name                      = "KDS_MONTHLY"
  credit_quota              = var.credit_quota
  notify_triggers           = [50, 80]
  suspend_trigger           = 100
  suspend_immediate_trigger = 110
}

resource "snowflake_warehouse" "job" {
  for_each            = local.warehouses
  name                = each.key
  warehouse_size      = "XSMALL"
  auto_suspend        = 60
  auto_resume         = true
  initially_suspended = true
  resource_monitor    = snowflake_resource_monitor.monthly.fully_qualified_name
  comment             = each.value.comment
}

resource "snowflake_account_role" "job" {
  for_each = local.roles
  name     = each.key
  comment  = each.value
}

# The job roles sit under SYSADMIN, as Snowflake advises, so the account's
# administrators can manage what the jobs make. The role that sees
# personal fields is left out, so no administrator sees them either.
resource "snowflake_grant_account_role" "under_sysadmin" {
  for_each         = toset(["LOADER", "BUILDER", "READER"])
  role_name        = snowflake_account_role.job[each.key].name
  parent_role_name = "SYSADMIN"
}

resource "snowflake_grant_privileges_to_account_role" "warehouse" {
  for_each          = local.warehouses
  account_role_name = snowflake_account_role.job[each.value.role].name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = snowflake_warehouse.job[each.key].name
  }
}

resource "snowflake_grant_privileges_to_account_role" "database" {
  for_each          = toset(["LOADER", "BUILDER", "READER"])
  account_role_name = snowflake_account_role.job[each.key].name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.warehouse.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "schema" {
  for_each          = local.schema_grants
  account_role_name = snowflake_account_role.job[each.value.role].name
  privileges        = each.value.privileges

  on_schema {
    schema_name = snowflake_schema.layer[each.value.schema].fully_qualified_name
  }
}

resource "snowflake_grant_privileges_to_account_role" "future_reads" {
  for_each          = local.future_reads
  account_role_name = snowflake_account_role.job[each.value.role].name
  privileges        = ["SELECT"]

  on_schema_object {
    future {
      object_type_plural = each.value.kind
      in_schema          = snowflake_schema.layer[each.value.schema].fully_qualified_name
    }
  }
}

resource "snowflake_service_user" "job" {
  for_each                       = local.job_users
  name                           = each.key
  comment                        = "${each.value.repository}: its ${each.value.job} job."
  default_role                   = snowflake_account_role.job[each.value.role].name
  default_warehouse              = snowflake_warehouse.job[each.value.warehouse].name
  default_secondary_roles_option = "NONE"

  default_workload_identity {
    oidc {
      issuer             = "https://token.actions.githubusercontent.com"
      subject            = each.value.subject
      oidc_audience_list = [var.oidc_audience]
    }
  }
}

resource "snowflake_grant_account_role" "job_user" {
  for_each  = local.job_users
  role_name = snowflake_account_role.job[each.value.role].name
  user_name = snowflake_service_user.job[each.key].name
}
