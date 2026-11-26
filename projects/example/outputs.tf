output "project_id" {
  description = "ID of the dbt platform project."
  value       = module.dbt_project.project_id
}

output "environment_ids" {
  description = "Environment IDs keyed by environment."
  value       = module.dbt_project.environment_ids
}

output "job_ids" {
  description = "Job IDs keyed by job."
  value       = module.dbt_project.job_ids
}
