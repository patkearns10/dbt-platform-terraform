# Offline tests: the provider is mocked, so no token or account is needed.
#   cd modules/dbt_project && terraform init && terraform test

mock_provider "dbtcloud" {}

variables {
  project_name  = "Test project"
  connection_id = 123
}

run "single_trunk_defaults" {
  command = plan

  assert {
    condition     = sort(keys(dbtcloud_environment.deployment)) == tolist(["production", "production_ci"])
    error_message = "Default layout should be Production and Production CI."
  }

  assert {
    condition     = length(dbtcloud_snowflake_credential.deployment) == 0
    error_message = "No credentials should be created when snowflake_deployment is null."
  }

  assert {
    condition     = sort(keys(dbtcloud_job.this)) == tolist(["production_build", "production_ci", "production_merge"])
    error_message = "Default layout should have Build, CI and Merge jobs for Production."
  }

  assert {
    condition = alltrue([
      for job in dbtcloud_job.this :
      !job.triggers.schedule && !job.triggers.on_merge && !job.triggers.github_webhook && !job.triggers.git_provider_webhook
    ])
    error_message = "All triggers should be off by default."
  }

  assert {
    condition     = length(dbtcloud_repository.this) == 0
    error_message = "No repository should be attached by default."
  }

  assert {
    condition     = dbtcloud_environment.development.use_custom_branch == false
    error_message = "Development should follow the default branch without staging."
  }
}

run "staging_layout_with_credentials" {
  command = plan

  variables {
    staging_branch = "staging"
    snowflake_deployment = {
      user      = "SVC_DBT"
      database  = "ANALYTICS"
      role      = "TRANSFORMER"
      warehouse = "TRANSFORMING"
    }
    environment_overrides = {
      staging = { database = "ANALYTICS_STAGING", schema = "analytics" }
    }
    snowflake_private_key = "not-a-real-key"
    job_triggers          = { schedule = true, ci = true, merge = true }
  }

  assert {
    condition     = length(dbtcloud_environment.deployment) == 4 && length(dbtcloud_job.this) == 6
    error_message = "Staging layout should have 4 deployment environments and 6 jobs."
  }

  assert {
    condition     = dbtcloud_environment.development.custom_branch == "staging"
    error_message = "Development should branch from staging."
  }

  assert {
    condition     = dbtcloud_environment.deployment["staging_ci"].custom_branch == "staging"
    error_message = "Staging CI should follow the staging branch."
  }

  assert {
    condition     = dbtcloud_snowflake_credential.deployment["staging"].database == "ANALYTICS_STAGING" && dbtcloud_snowflake_credential.deployment["staging"].schema == "analytics"
    error_message = "Overrides should win over the shared defaults."
  }

  assert {
    condition     = dbtcloud_snowflake_credential.deployment["production"].database == "ANALYTICS" && dbtcloud_snowflake_credential.deployment["production"].schema == "analytics"
    error_message = "Production should use the shared defaults."
  }

  assert {
    condition     = dbtcloud_snowflake_credential.deployment["production_ci"].schema == "dbt_ci"
    error_message = "CI should default to the dbt_ci schema."
  }

  assert {
    condition     = dbtcloud_job.this["production_ci"].triggers.git_provider_webhook && dbtcloud_job.this["production_merge"].triggers.on_merge && dbtcloud_job.this["production_build"].triggers.schedule
    error_message = "Triggers should switch on per job type."
  }

  assert {
    condition     = !dbtcloud_job.this["production_merge"].triggers.schedule && !dbtcloud_job.this["production_merge"].triggers.git_provider_webhook
    error_message = "A merge job must have every other trigger off."
  }
}

run "no_jobs" {
  command = plan

  variables {
    create_default_jobs = false
  }

  assert {
    condition     = length(dbtcloud_job.this) == 0
    error_message = "create_default_jobs = false should create no jobs."
  }
}

run "gitlab_repository" {
  command = plan

  variables {
    repository = {
      remote_url        = "data/dbt-example"
      gitlab_project_id = 4242
    }
  }

  assert {
    condition     = dbtcloud_repository.this[0].git_clone_strategy == "deploy_token" && dbtcloud_repository.this[0].gitlab_project_id == 4242 && length(dbtcloud_project_repository.this) == 1
    error_message = "GitLab repository should attach through the native integration."
  }
}
