locals {
  # BHP_SANDBOX stays BHP_SANDBOX; "Finance mart" becomes FINANCE_MART.
  group_prefix = upper(replace(var.project_name, "/[^A-Za-z0-9]+/", "_"))

  groups = var.create_groups ? {
    admin = { name = "${local.group_prefix}_ADMIN", permission_set = "admin" }
    devs  = { name = "${local.group_prefix}_DEVS", permission_set = "developer" }
  } : {}
}

# Terraform owns the group and its permissions. Membership is not managed
# here, so adding or removing people in the UI (or through SSO) is not drift.
resource "dbtcloud_group" "this" {
  for_each = local.groups

  name = each.value.name

  group_permissions {
    permission_set                  = each.value.permission_set
    all_projects                    = false
    project_id                      = dbtcloud_project.this.id
    writable_environment_categories = ["all"]
  }
}
