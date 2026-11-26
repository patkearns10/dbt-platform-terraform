resource "dbtcloud_project" "this" {
  name                     = var.project_name
  description              = var.project_description
  dbt_project_subdirectory = var.dbt_project_subdirectory
}
