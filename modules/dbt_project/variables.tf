# -----------------------------------------------------------------------------
# Project
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the dbt platform project."
  type        = string

  validation {
    condition     = trimspace(var.project_name) == var.project_name && length(var.project_name) > 0
    error_message = "project_name must not be empty or have leading/trailing spaces."
  }
}

variable "project_description" {
  description = "Short description of the project. Shown in dbt Catalog."
  type        = string
  default     = ""
}

variable "dbt_project_subdirectory" {
  description = "Subdirectory of the repository that holds dbt_project.yml. Leave null when the dbt project is at the repository root."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Connection
# -----------------------------------------------------------------------------

variable "connection_id" {
  description = "ID of an existing account-level (global) Snowflake connection. Connections are shared across projects, so this module never creates one."
  type        = number
}

# -----------------------------------------------------------------------------
# Environments
# -----------------------------------------------------------------------------

variable "dbt_version" {
  description = "dbt release track for all environments, e.g. latest-fusion, fusion-stable, latest, compatible, extended."
  type        = string
  default     = "latest-fusion"
}

variable "enable_dbt_state" {
  description = "Turn on dbt State in the deployment environments; jobs inherit the setting. Requires dbt State to be enabled on the account."
  type        = bool
  default     = false
}

variable "staging_branch" {
  description = "Long-lived staging branch. null (default) gives a single-trunk layout: Development, Production and Production CI. Setting it adds Staging and Staging CI and points Development at this branch."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Deployment credentials (Snowflake service account, key pair)
# -----------------------------------------------------------------------------

variable "snowflake_deployment" {
  description = <<-EOT
    Snowflake service-account settings used by every deployment environment.
    null (default) creates the environments without credentials, to be finished
    in the dbt platform UI. Per-environment differences go in environment_overrides.
  EOT
  type = object({
    user        = string
    database    = string
    role        = optional(string)
    warehouse   = optional(string)
    num_threads = optional(number, 8)
  })
  default = null
}

variable "environment_overrides" {
  description = <<-EOT
    Optional per-environment overrides of snowflake_deployment, keyed by
    environment: production, production_ci, staging, staging_ci.
    Default schemas: production = analytics, staging = analytics_staging, CI = dbt_ci.
  EOT
  type = map(object({
    user      = optional(string)
    database  = optional(string)
    schema    = optional(string)
    role      = optional(string)
    warehouse = optional(string)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k in keys(var.environment_overrides) :
      contains(["production", "production_ci", "staging", "staging_ci"], k)
    ])
    error_message = "environment_overrides keys must be one of: production, production_ci, staging, staging_ci."
  }
}

variable "snowflake_private_key" {
  description = "PEM private key of the Snowflake service account. Ephemeral and write-only: never stored in state or plan. Supply with TF_VAR_snowflake_private_key."
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true
}

variable "snowflake_private_key_passphrase" {
  description = "Passphrase for an encrypted private key. Leave null for an unencrypted key."
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true
}

variable "snowflake_private_key_version" {
  description = "Increase by one to push a rotated private key (or passphrase) to the dbt platform. Write-only values are only sent when this number changes."
  type        = number
  default     = 1
}

# -----------------------------------------------------------------------------
# Jobs
# -----------------------------------------------------------------------------

variable "create_default_jobs" {
  description = "Create the starter jobs (Build and Merge per target environment, CI per CI environment). Set false if teams own their jobs entirely."
  type        = bool
  default     = true
}

variable "job_triggers" {
  description = <<-EOT
    Which automatic triggers are switched on. All off by default so a new
    project is created quiet. Turn them on once a repository is attached and
    the Build job has run once (CI and Merge jobs defer to that run's state).
  EOT
  type = object({
    schedule = optional(bool, false)
    ci       = optional(bool, false)
    merge    = optional(bool, false)
  })
  default = {}
}

variable "schedule_cron" {
  description = "Cron expression (UTC) for the scheduled Build jobs."
  type        = string
  default     = "0 9 * * 1-5"
}

# -----------------------------------------------------------------------------
# Repository (iteration 2 - off by default)
# -----------------------------------------------------------------------------

variable "repository" {
  description = <<-EOT
    GitLab repository to attach through the dbt platform's native GitLab
    integration. null (default) attaches nothing.
    remote_url is "<group>/<project>"; gitlab_project_id is the numeric project ID.
  EOT
  type = object({
    remote_url        = string
    gitlab_project_id = number
  })
  default = null
}
