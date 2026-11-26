# The API token is read from the DBT_CLOUD_TOKEN environment variable and is
# deliberately not a Terraform variable, so it cannot end up in a tfvars file.
# Account and host are explicit so a project is never applied to the wrong account.
provider "dbtcloud" {
  account_id = var.dbt_account_id
  host_url   = var.dbt_host_url
}
