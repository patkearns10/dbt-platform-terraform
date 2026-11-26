# dbt platform project factory (Terraform)

Terraform that creates a dbt platform project on Snowflake with a standard set of environments, two access groups and starter jobs, and keeps it under state so drift is visible.

It combines two earlier repos:

| Taken from | What |
| --- | --- |
| [`patkearns10/tf_dbt`](https://github.com/patkearns10/tf_dbt) | Token from the environment only, dedicated CI environments, optional connection credentials, trigger switches, the Streamlit front door |
| [`dbt-labs/ps-demo-terraform-managed`](https://github.com/dbt-labs/ps-demo-terraform-managed) | Shared module plus thin per-project root, data-driven environments and jobs, key-pair credentials with write-only secrets, remote state with locking |

## What you get

| Layout | Environments | Jobs |
| --- | --- | --- |
| Default (single trunk) | Development, Production, Production CI | Production - Build, Production - Merge, Production - CI |
| With `staging_branch` set | plus Staging, Staging CI; Development branches from staging | plus Staging - Build, Staging - Merge, Staging - CI |

- **Build** runs `dbt build` on a schedule. **Merge** runs `dbt build --select state:modified+`. **CI** runs `dbt ls --select state:modified` and then `dbt build --select state:modified+`. Merge and CI defer to their target environment.
- CI runs in its own environment, so it can use its own schema, role and warehouse.
- All job triggers are **off** when the jobs are created.
- Two groups scoped to the project, both with write access to all environments: `<PROJECT_NAME>_ADMIN` (Admin) and `<PROJECT_NAME>_DEVS` (Developer).
- The project uses an **existing** account-level connection. Connections are shared, so the module never creates one. The shared connection ID is a default in `projects/example/variables.tf`.
- Deployment credentials are optional. When set, they are Snowflake key-pair credentials and the private key is never written to state or plan.
- No repository is attached yet. See [docs/roadmap.md](docs/roadmap.md).

## Who owns what

Terraform cannot make a single setting "managed" or "free" with a variable, so the choice is made per kind of object:

| Object | Owner | What a change in the UI does |
| --- | --- | --- |
| Project name and description | Terraform | Reverted on the next apply |
| Environments (name, branch, dbt version, connection) | Terraform | Reverted on the next apply |
| Deployment credentials | Terraform | Reverted on the next apply |
| Groups and their permissions | Terraform | Reverted on the next apply |
| Group membership | People (UI or SSO) | Kept; Terraform does not look at it |
| Starter jobs, `job_management = "bootstrap"` (default) | Team, after creation | Kept; Terraform creates the jobs once and ignores them afterwards |
| Starter jobs, `job_management = "managed"` | Terraform | Reverted on the next apply |
| Jobs a team adds in the UI | Team | Kept; Terraform does not know about them |
| Development credentials | Each developer | Kept |

With `bootstrap`, later changes to the job definitions in this repo, including `job_triggers`, do not reach projects that already exist. A starter job deleted in the UI is recreated on the next apply; to drop one for good, run `terraform state rm` on it. Switching an existing project between `bootstrap` and `managed` needs a `terraform state mv` from `dbtcloud_job.bootstrap` to `dbtcloud_job.managed` (or back), otherwise the jobs are deleted and recreated.

If projects end up not being maintained from the platform at all, apply once and stop: nothing here requires a second apply.

## Layout

```
modules/dbt_project/     reusable module: project, environments, credentials, groups, jobs
  tests/                 offline tests (mocked provider, no token needed)
projects/example/        one root per dbt project; copy this directory for each new project
scripts/                 check_connection.py: test token, account, host and connection
app/                     Streamlit front door (optional)
Dockerfile               the app with the Terraform CLI bundled
docs/state.md            where state lives and how to run this in a pipeline
docs/roadmap.md          GitLab repository, Streamlit in Snowflake, groups
```

## Quick start (local)

Needs Terraform 1.11 or later and a dbt platform token that can create projects.

```bash
cd projects/example
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`: set `dbt_account_id`, `dbt_host_url` and `project_name` (upper case with underscores, for example `BHP_SANDBOX`). Set the shared connection ID once, as the default of `connection_id` in `variables.tf`. Then check the token, account, host and connection before running Terraform:

```bash
export DBT_CLOUD_TOKEN=<token>
python3 ../../scripts/check_connection.py .
```

It is read-only and prints PASS or FAIL per check. Then:

```bash
terraform init
terraform plan
terraform apply
```

That creates the project, three environments, two groups and three jobs, with no deployment credentials. To have Terraform create the credentials too, uncomment `snowflake_deployment` in `terraform.tfvars` and supply the key:

```bash
export TF_VAR_snowflake_private_key="$(cat ~/.ssh/snowflake_svc_dbt.p8)"
terraform apply
```

To remove everything the example created:

```bash
terraform destroy
```

### A real project

Copy `projects/example` to `projects/<project_name>`, commit its `terraform.tfvars` (it holds no secrets), and give it a remote backend from `backend.tf.example`. One directory and one state per dbt project keeps a mistake in one project from touching another.

### Streamlit front door

```bash
pip install -r app/requirements.txt
streamlit run app/streamlit_app.py
```

The form writes `terraform.tfvars`. With the Terraform CLI on PATH it also creates `projects/<name>/`, tests the connection, and runs plan, apply and destroy there, so state stays with the project rather than the browser session. Without the CLI it only produces the file.

To run it in a container with Terraform bundled (Render, or local Docker):

```bash
docker build -t dbt-project-factory .
docker run -p 8501:8501 dbt-project-factory
```

In a container with no remote backend, state lasts only as long as the container. That is enough to create and destroy in one sitting, as the original `tf_dbt` app did, but not to manage a project over time.

## Inputs

All inputs are documented in [`modules/dbt_project/variables.tf`](modules/dbt_project/variables.tf). The ones that matter most:

| Variable | Default | Purpose |
| --- | --- | --- |
| `project_name` | required | Project name |
| `connection_id` | shared default in `projects/example/variables.tf` | Existing account-level Snowflake connection |
| `dbt_version` | `fusion-stable` | Release track for every environment |
| `enable_dbt_state` | `false` | dbt State on deployment environments; jobs inherit it |
| `staging_branch` | `null` | Set to add the staging environments |
| `snowflake_deployment` | `null` | Service user, database, role, warehouse for deployment credentials |
| `environment_overrides` | `{}` | Per-environment database, schema, role, warehouse, user |
| `create_groups` | `true` | `<PROJECT_NAME>_ADMIN` and `<PROJECT_NAME>_DEVS` |
| `job_management` | `bootstrap` | `bootstrap`, `managed` or `none`; see "Who owns what" |
| `job_triggers` | all `false` | Switch on `schedule`, `ci`, `merge` at creation |
| `repository` | `null` | GitLab repository to attach (iteration 2) |

Secrets come from the environment only:

| Environment variable | Used for |
| --- | --- |
| `DBT_CLOUD_TOKEN` | dbt platform API token |
| `TF_VAR_snowflake_private_key` | Private key for deployment credentials |
| `TF_VAR_snowflake_private_key_passphrase` | Only for an encrypted key |

To rotate the key, export the new one and add 1 to `snowflake_private_key_version`.

## Checks

```bash
terraform fmt -check -recursive
cd modules/dbt_project
terraform init
terraform test
```

The tests mock the provider, so they need no token and create nothing.

## Things to know

- **Adopting an existing project.** Add an `import` block to the project's root, then plan:
  ```hcl
  import {
    to = module.dbt_project.dbtcloud_project.this
    id = "<project_id>"
  }
  ```
- **Before turning on CI and Merge triggers**, attach a repository and run Production - Build once. Those jobs compare against the last successful run in their target environment.
- **Fusion and dbt State** need to be available on the account. Otherwise set `dbt_version = "latest"` and leave `enable_dbt_state = false`. The stable Fusion track is spelled `fusion-stable` in the provider.
- **Token.** Creating projects and groups needs an account-level admin token. The connection check only proves the token can read the account.
- **Upgrading from the first version.** Jobs moved from `dbtcloud_job.this` to `dbtcloud_job.bootstrap`; a `moved` block handles this, so the next plan shows a move, not a delete and create.
- **What has been run for real.** The first version (project, environments, jobs) was applied against a live account. The groups, the two job modes and the connection check were added afterwards and have only been validated, planned and tested offline. The thing to look at on the first apply is whether the Admin group accepts "write access to all environments" without showing drift on the next plan.
