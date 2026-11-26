module "dbt_project" {
  source = "../../modules/dbt_project"

  project_name             = var.project_name
  project_description      = var.project_description
  dbt_project_subdirectory = var.dbt_project_subdirectory

  connection_id = var.connection_id

  dbt_version      = var.dbt_version
  enable_dbt_state = var.enable_dbt_state
  staging_branch   = var.staging_branch

  snowflake_deployment             = var.snowflake_deployment
  environment_overrides            = var.environment_overrides
  snowflake_private_key            = var.snowflake_private_key
  snowflake_private_key_passphrase = var.snowflake_private_key_passphrase
  snowflake_private_key_version    = var.snowflake_private_key_version

  create_default_jobs = var.create_default_jobs
  job_triggers        = var.job_triggers
  schedule_cron       = var.schedule_cron

  repository = var.repository
}
