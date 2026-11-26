locals {
  has_staging = var.staging_branch != null

  # Environments that hold deployed data. Each one gets a Build and a Merge job.
  target_environments = {
    for k, env in {
      production = {
        name            = "Production"
        deployment_type = "production"
        custom_branch   = null # repository default branch
        default_schema  = "analytics"
        enabled         = true
      }
      staging = {
        name            = "Staging"
        deployment_type = "staging"
        custom_branch   = var.staging_branch
        default_schema  = "analytics_staging"
        enabled         = local.has_staging
      }
    } : k => env if env.enabled
  }

  # One dedicated CI environment per target. It follows the same branch, so it
  # picks up pull requests aimed at that branch, and defers to the target.
  ci_environments = {
    for k, env in local.target_environments : "${k}_ci" => {
      name            = "${env.name} CI"
      deployment_type = null
      custom_branch   = env.custom_branch
      default_schema  = "dbt_ci"
      defers_to       = k
    }
  }

  deployment_environments = merge(
    { for k, env in local.target_environments : k => merge(env, { defers_to = k }) },
    local.ci_environments,
  )

  # Resolved Snowflake settings per environment: override, else shared default.
  snowflake = var.snowflake_deployment == null ? {} : {
    for k, env in local.deployment_environments : k => {
      user      = try(coalesce(var.environment_overrides[k].user), var.snowflake_deployment.user)
      database  = try(coalesce(var.environment_overrides[k].database), var.snowflake_deployment.database)
      schema    = try(coalesce(var.environment_overrides[k].schema), env.default_schema)
      role      = try(coalesce(var.environment_overrides[k].role), var.snowflake_deployment.role)
      warehouse = try(coalesce(var.environment_overrides[k].warehouse), var.snowflake_deployment.warehouse)
    }
  }
}

resource "dbtcloud_snowflake_credential" "deployment" {
  for_each = local.snowflake

  project_id  = dbtcloud_project.this.id
  auth_type   = "keypair"
  num_threads = var.snowflake_deployment.num_threads

  user      = each.value.user
  database  = each.value.database
  schema    = each.value.schema
  role      = each.value.role
  warehouse = each.value.warehouse

  # Write-only: sent to the dbt platform, never written to state.
  private_key_wo                    = var.snowflake_private_key
  private_key_wo_version            = var.snowflake_private_key_version
  private_key_passphrase_wo         = var.snowflake_private_key_passphrase
  private_key_passphrase_wo_version = var.snowflake_private_key_version
}

# Developers set their own credentials, so Development has none.
resource "dbtcloud_environment" "development" {
  project_id        = dbtcloud_project.this.id
  name              = "Development"
  type              = "development"
  connection_id     = var.connection_id
  dbt_version       = var.dbt_version
  use_custom_branch = local.has_staging
  custom_branch     = var.staging_branch
}

resource "dbtcloud_environment" "deployment" {
  for_each = local.deployment_environments

  project_id        = dbtcloud_project.this.id
  name              = each.value.name
  type              = "deployment"
  deployment_type   = each.value.deployment_type
  connection_id     = var.connection_id
  credential_id     = try(dbtcloud_snowflake_credential.deployment[each.key].credential_id, null)
  dbt_version       = var.dbt_version
  use_custom_branch = each.value.custom_branch != null
  custom_branch     = each.value.custom_branch
  enable_dbt_state  = var.enable_dbt_state ? true : null
}
