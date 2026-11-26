terraform {
  # 1.11+ is required for write-only arguments (private_key_wo) and ephemeral
  # variables, which keep the Snowflake private key out of state and plan files.
  required_version = ">= 1.11"

  required_providers {
    dbtcloud = {
      source  = "dbt-labs/dbtcloud"
      version = "~> 1.13"
    }
  }
}
