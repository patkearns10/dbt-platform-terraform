locals {
  modified_only = "dbt build --select state:modified+"

  build_jobs = {
    for k, env in local.target_environments : "${k}_build" => {
      environment   = k
      defers_to     = null
      name          = "${env.name} - Build"
      description   = "Scheduled full build of the ${env.name} environment."
      job_type      = null
      steps         = ["dbt build"]
      generate_docs = env.deployment_type == "production"
      freshness     = env.deployment_type == "production"
      scheduled     = true
      triggers = {
        github_webhook       = false
        git_provider_webhook = false
        on_merge             = false
        schedule             = var.job_triggers.schedule
      }
    }
  }

  merge_jobs = {
    for k, env in local.target_environments : "${k}_merge" => {
      environment   = k
      defers_to     = k
      name          = "${env.name} - Merge"
      description   = "Builds only what changed when a pull request is merged into the ${env.name} branch."
      job_type      = "merge"
      steps         = [local.modified_only]
      generate_docs = false
      freshness     = false
      scheduled     = false
      triggers = {
        github_webhook       = false
        git_provider_webhook = false
        on_merge             = var.job_triggers.merge
        schedule             = false
      }
    }
  }

  ci_jobs = {
    for k, env in local.ci_environments : k => {
      environment   = k
      defers_to     = env.defers_to
      name          = "${local.target_environments[env.defers_to].name} - CI"
      description   = "Builds only what changed, in a temporary schema, on every pull request into the ${local.target_environments[env.defers_to].name} branch."
      job_type      = "ci"
      steps         = ["dbt ls --select state:modified", local.modified_only]
      generate_docs = false
      freshness     = false
      scheduled     = false
      triggers = {
        github_webhook       = var.job_triggers.ci
        git_provider_webhook = var.job_triggers.ci
        on_merge             = false
        schedule             = false
      }
    }
  }

  jobs = merge(local.build_jobs, local.merge_jobs, local.ci_jobs)
}

# The same job definition is declared twice because Terraform's lifecycle
# rules cannot be switched by a variable. Exactly one of the two is created.

# job_management = "bootstrap": created once, then left to the team.
# A job deleted in the UI is recreated on the next apply; to drop one for
# good, remove it from state with `terraform state rm`.
resource "dbtcloud_job" "bootstrap" {
  for_each = var.job_management == "bootstrap" ? local.jobs : {}

  project_id     = dbtcloud_project.this.id
  environment_id = dbtcloud_environment.deployment[each.value.environment].environment_id
  name           = each.value.name
  description    = each.value.description
  job_type       = each.value.job_type
  execute_steps  = each.value.steps
  triggers       = each.value.triggers

  # CI and Merge jobs compare against the last successful run of their target.
  deferring_environment_id = (
    each.value.defers_to == null ? null :
    dbtcloud_environment.deployment[each.value.defers_to].environment_id
  )

  generate_docs        = each.value.generate_docs
  run_generate_sources = each.value.freshness

  schedule_type = each.value.scheduled ? "custom_cron" : null
  schedule_cron = each.value.scheduled ? var.schedule_cron : null

  cost_optimization_features = var.enable_dbt_state ? ["inherit_environment"] : null

  lifecycle {
    ignore_changes = all
  }
}

# job_management = "managed": Terraform keeps the jobs in line with this file.
resource "dbtcloud_job" "managed" {
  for_each = var.job_management == "managed" ? local.jobs : {}

  project_id     = dbtcloud_project.this.id
  environment_id = dbtcloud_environment.deployment[each.value.environment].environment_id
  name           = each.value.name
  description    = each.value.description
  job_type       = each.value.job_type
  execute_steps  = each.value.steps
  triggers       = each.value.triggers

  deferring_environment_id = (
    each.value.defers_to == null ? null :
    dbtcloud_environment.deployment[each.value.defers_to].environment_id
  )

  generate_docs        = each.value.generate_docs
  run_generate_sources = each.value.freshness

  schedule_type = each.value.scheduled ? "custom_cron" : null
  schedule_cron = each.value.scheduled ? var.schedule_cron : null

  cost_optimization_features = var.enable_dbt_state ? ["inherit_environment"] : null
}

# Jobs created by the first version of this module lived at dbtcloud_job.this.
moved {
  from = dbtcloud_job.this
  to   = dbtcloud_job.bootstrap
}
