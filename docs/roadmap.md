# Roadmap

## Iteration 1 (this repo)

Project, environments, optional key-pair credentials, two project groups and starter jobs on an existing Snowflake connection. No repository.

## Iteration 2: attach a GitLab repository

Already in the module, switched off. Set `repository` and apply:

```hcl
repository = {
  remote_url        = "my-group/my-dbt-project"
  gitlab_project_id = 123456
}
```

This uses the dbt platform's native GitLab integration (`deploy_token` strategy). It needs the GitLab integration to be set up on the dbt platform account, and the token Terraform runs with must belong to an identity that can see the GitLab project. That second point is the main thing to confirm: a service token may not carry a GitLab link, in which case a user token is needed for this step. It has not been run against a live account.

Once a repository is attached, run Production - Build once, then set `job_triggers`.

## Iteration 3: create the repository from an example

Add the `gitlabhq/gitlab` provider to the project root and create the GitLab project before the dbt project, then feed its ID into `repository`. Three ways to seed it from an example repository:

| Approach | Argument on `gitlab_project` | Notes |
| --- | --- | --- |
| Group or instance project template | `template_project_id` with `use_custom_template = true` | Cleanest; custom templates need GitLab Premium or Ultimate, and group tokens do not work with them |
| Fork | `forked_from_project_id` | Keeps a fork relationship to the example |
| Import by URL | `import_url` | Works on any tier; one-off copy |

Sketch:

```hcl
resource "gitlab_project" "dbt" {
  name                = "dbt-finance"
  namespace_id        = var.gitlab_group_id
  template_project_id = var.gitlab_template_project_id
  use_custom_template = true
  default_branch      = "main"
}

module "dbt_project" {
  source = "../../modules/dbt_project"
  # ...
  repository = {
    remote_url        = gitlab_project.dbt.path_with_namespace
    gitlab_project_id = gitlab_project.dbt.id
  }
}
```

To decide: which GitLab group new repositories go in, which token creates them, and whether branch protection and merge request rules are set here too.

## Hosting the front door

`app/streamlit_app.py` works in two modes. With the Terraform CLI available it runs plan and apply. Without it, it only produces `terraform.tfvars`.

**Streamlit in Snowflake.** The second mode is the one to plan for. Snowflake's documentation does not say that an app can run an external binary such as Terraform, and even if it can, state and secrets would then have to live inside the app. A cleaner split:

1. The Streamlit in Snowflake app is the form. It validates input and shows the generated `terraform.tfvars`.
2. On submit it opens a merge request in the Terraform repository that adds `projects/<name>/terraform.tfvars` (GitLab API through an external access integration), or writes the request to a table that a pipeline picks up.
3. The GitLab pipeline plans on the merge request and applies on merge, with GitLab-managed state.

That gives one front door and one engine, an approval step, and an audit trail, and Snowflake never holds the dbt token. To confirm with the Snowflake team: whether external access integrations to the GitLab host are allowed, and which runtime (warehouse or container) their Streamlit apps use.

**A container host (Render, or similar).** The `Dockerfile` bundles the Terraform CLI, so the app runs in its first mode. Without a remote backend this is create and destroy in one sitting, with nothing remembered afterwards. That is a fair choice if projects are not going to be maintained from the platform. If they are, each project directory needs a remote backend, at which point the merge request route above is simpler.

## Later

- **SSO mapping** for the two project groups (`sso_mapping_groups`), so membership comes from the identity provider.
- **Shared team groups.** Where one team owns several projects, grant its existing groups access with `dbtcloud_group_partial_permissions` instead of two new groups per project.
- **License mapping** from identity-provider groups (`dbtcloud_license_map`). This is account-level, so it belongs in a separate account root, not in the per-project module.
- **Notifications** on job failure.
- **CI extras**: SQL linting and compare changes (Advanced CI), cloning incremental models before the CI build.
- **Environment variables and extended attributes** per environment.
