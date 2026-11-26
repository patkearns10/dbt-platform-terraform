# State and where to run it

Terraform state is the record of what Terraform created. Without it, Terraform cannot update or remove a project, and a second apply would create duplicates.

## Rules

1. **One state per dbt project.** Each directory under `projects/` has its own state, so a bad change is contained to one project and plans stay fast.
2. **Remote, locked and versioned** for anything shared. Local state (`terraform.tfstate` beside the code) is only for a first test on a laptop.
3. **Treat state as sensitive.** This repo keeps the Snowflake private key out of state by using write-only arguments, but restrict access to the state store anyway.
4. **Never commit state.** `*.tfstate*` is in `.gitignore`.
5. **Secrets come from the runner's secret store** as environment variables: `DBT_CLOUD_TOKEN`, `TF_VAR_snowflake_private_key`.

## Backend options

`projects/example/backend.tf.example` has a block for each. Copy it to `backend.tf`, keep one, then:

```bash
terraform init -migrate-state
```

| Backend | Good fit when | Locking |
| --- | --- | --- |
| GitLab-managed Terraform state (`http`) | Terraform runs in GitLab pipelines; no extra infrastructure | Built in |
| S3 | An AWS account is already used for platform state | `use_lockfile = true` |
| Azure Blob Storage (`azurerm`) | Azure is the platform cloud | Built in (blob lease) |

### GitLab-managed state

The `http` backend block is left empty and everything is passed at init time. Use the dbt project's directory name as the state name.

```bash
STATE_NAME=example
STATE_URL="https://<gitlab-host>/api/v4/projects/<gitlab_project_id>/terraform/state/${STATE_NAME}"

terraform init \
  -backend-config="address=${STATE_URL}" \
  -backend-config="lock_address=${STATE_URL}/lock" \
  -backend-config="unlock_address=${STATE_URL}/lock" \
  -backend-config="lock_method=POST" \
  -backend-config="unlock_method=DELETE" \
  -backend-config="username=<gitlab_username>" \
  -backend-config="password=<gitlab_access_token>" \
  -backend-config="retry_wait_min=5"
```

In a pipeline, the username is `gitlab-ci-token` and the password is `$CI_JOB_TOKEN`.

## Running it in a pipeline

The usual shape, whatever the runner:

| Trigger | Step | Purpose |
| --- | --- | --- |
| Merge request touching `projects/<name>/` or `modules/` | `fmt -check`, `validate`, `test`, `plan` | Review the plan with the code |
| Merge to the default branch | `apply` (manual approval) | Only the pipeline applies; people do not |
| Schedule (for example nightly) | `plan -detailed-exitcode` | Exit code 2 means someone changed something in the UI |

A starting point for GitLab CI. It has not been run; adjust the image, runner tags and variables to your setup.

```yaml
# .gitlab-ci.yml
# Set PROJECT (a directory under projects/) when triggering, or add one job per project.
# CI/CD variables (masked): DBT_CLOUD_TOKEN, TF_VAR_snowflake_private_key

image:
  name: hashicorp/terraform:1.14
  entrypoint: [""]

variables:
  TF_IN_AUTOMATION: "true"
  TF_ROOT: projects/${PROJECT}
  STATE_URL: ${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/terraform/state/${PROJECT}

.init: &init
  - cd ${TF_ROOT}
  - >
    terraform init -input=false
    -backend-config="address=${STATE_URL}"
    -backend-config="lock_address=${STATE_URL}/lock"
    -backend-config="unlock_address=${STATE_URL}/lock"
    -backend-config="lock_method=POST"
    -backend-config="unlock_method=DELETE"
    -backend-config="username=gitlab-ci-token"
    -backend-config="password=${CI_JOB_TOKEN}"

stages: [check, plan, apply]

check:
  stage: check
  script:
    - terraform fmt -check -recursive
    - cd modules/dbt_project && terraform init -input=false && terraform test

plan:
  stage: plan
  script:
    - *init
    - terraform plan -input=false -out=tfplan
  artifacts:
    paths: ["${TF_ROOT}/tfplan"]

apply:
  stage: apply
  script:
    - *init
    - terraform apply -input=false tfplan
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      when: manual

drift:
  stage: plan
  script:
    - *init
    - terraform plan -input=false -detailed-exitcode
  rules:
    - if: $CI_PIPELINE_SOURCE == "schedule"
```

## Open questions to settle

- Which backend, and who can read it.
- Which identity runs apply: a dbt platform service token scoped to project creation, held only by the pipeline.
- Whether Terraform keeps owning jobs after creation, or only project, environments and credentials (see "Who owns what" in the README).
- How the Snowflake service-account key reaches the runner (CI/CD variable, or a secrets manager).
