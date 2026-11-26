output "project_id" {
  description = "ID of the dbt platform project."
  value       = dbtcloud_project.this.id
}

output "environment_ids" {
  description = "Environment IDs keyed by environment (development, production, production_ci, ...)."
  value = merge(
    { development = dbtcloud_environment.development.environment_id },
    { for k, env in dbtcloud_environment.deployment : k => env.environment_id },
  )
}

output "job_ids" {
  description = "Job IDs keyed by job (production_build, production_merge, production_ci, ...)."
  value       = { for k, job in dbtcloud_job.this : k => job.job_id }
}

output "repository_id" {
  description = "ID of the attached repository. null when none is attached."
  value       = try(dbtcloud_repository.this[0].repository_id, null)
}
