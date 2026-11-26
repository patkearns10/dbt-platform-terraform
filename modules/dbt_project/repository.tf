# Iteration 2: attach a repository. Nothing here is created while
# var.repository is null. See docs/roadmap.md for creating the GitLab
# repository itself from a template.

resource "dbtcloud_repository" "this" {
  count = var.repository == null ? 0 : 1

  project_id         = dbtcloud_project.this.id
  remote_url         = var.repository.remote_url
  gitlab_project_id  = var.repository.gitlab_project_id
  git_clone_strategy = "deploy_token" # GitLab native integration
}

resource "dbtcloud_project_repository" "this" {
  count = var.repository == null ? 0 : 1

  project_id    = dbtcloud_project.this.id
  repository_id = dbtcloud_repository.this[0].repository_id
}
