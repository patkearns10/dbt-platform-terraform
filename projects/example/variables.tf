# -----------------------------------------------------------------------------
# dbt platform account (the token comes from DBT_CLOUD_TOKEN)
# -----------------------------------------------------------------------------

variable "dbt_account_id" {
  description = "dbt platform account ID."
  type        = number
}

variable "dbt_host_url" {
  description = "API URL of the dbt platform account, ending in /api. For example https://cloud.getdbt.com/api, https://au.dbt.com/api or https://<prefix>.us1.dbt.com/api."
  type        = string
  default     = "https://cloud.getdbt.com/api"
}

# Everything below is passed straight through to modules/dbt_project, which
# also holds the validation rules.

# -----------------------------------------------------------------------------
# Project
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the dbt platform project."
  type        = string
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
  description = "ID of an existing account-level (global) Snowflake connection. The default is the shared connection for this account; change the default once per account rather than per project."
  type        = number
  default     = 51284 # TODO: replace with the shared Snowflake connection ID of your account
}

# -----------------------------------------------------------------------------
# Environments
# -----------------------------------------------------------------------------

variable "dbt_version" {
  description = "dbt release track for all environments, e.g. fusion-stable, latest-fusion, latest, compatible, extended."
  type        = string
  default     = "fusion-stable"
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

variable "job_management" {
  description = <<-EOT
    Who owns the starter jobs (Build and Merge per target environment, CI per CI environment).
      bootstrap  Terraform creates them once, then ignores every later change, so teams
                 can edit them in the UI without Terraform reverting it. (default)
      managed    Terraform owns them; UI edits show as drift and are reverted on apply.
      none       No jobs are created.
  EOT
  type        = string
  default     = "bootstrap"
}

variable "job_triggers" {
  description = <<-EOT
    Which automatic triggers are switched on. All off by default so a new
    project is created quiet. Turn them on once a repository is attached and
    the Build job has run once (CI and Merge jobs defer to that run's state).
    With job_management = "bootstrap" this only applies when the jobs are
    first created; after that, change triggers in the UI.
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
# Groups
# -----------------------------------------------------------------------------

variable "create_groups" {
  description = "Create <PROJECT_NAME>_ADMIN (Admin) and <PROJECT_NAME>_DEVS (Developer), both scoped to this project with write access to all environments. The prefix is the project name in upper case with anything other than letters and digits replaced by underscores."
  type        = bool
  default     = true
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
