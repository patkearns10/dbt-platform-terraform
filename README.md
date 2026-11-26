# dbt platform project factory (Terraform)

Terraform that creates a dbt platform project on Snowflake with a standard set of environments and starter jobs, and keeps it under state so drift is visible.

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

- **Build** runs `dbt build` on a schedule. **Merge** and **CI** run `dbt build --select state:modified+` and defer to their target environment.
- CI runs in its own environment, so it can use its own schema, role and warehouse.
- All job triggers are **off** until you turn them on with `job_triggers`.
- The project uses an **existing** account-level connection. Connections are shared, so the module never creates one.
- Deployment credentials are optional. When set, they are Snowflake key-pair credentials and the private key is never written to state or plan.
- No repository is attached yet. See [docs/roadmap.md](docs/roadmap.md).

## Layout

```
modules/dbt_project/     reusable module: project, environments, credentials, jobs
  tests/                 offline tests (mocked provider, no token needed)
projects/example/        one root per dbt project; copy this directory for each new project
app/                     Streamlit front door (optional)
docs/state.md            where state lives and how to run this in a pipeline
docs/roadmap.md          GitLab repository, Streamlit in Snowflake, groups
```

## Quick start (local)

Needs Terraform 1.11 or later and a dbt platform token that can create projects.

```bash
cd projects/example
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`: set `dbt_account_id`, `dbt_host_url`, `project_name` and `connection_id`. Then:

```bash
export DBT_CLOUD_TOKEN=<token>
terraform init
terraform plan
terraform apply
```

That creates the project, three environments and three jobs, with no deployment credentials. To have Terraform create the credentials too, uncomment `snowflake_deployment` in `terraform.tfvars` and supply the key:

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

The form writes `terraform.tfvars`. With the Terraform CLI on PATH it also creates `projects/<name>/` and runs plan and apply there, so state stays with the project rather than the browser session. Without the CLI it only produces the file.

## Inputs

All inputs are documented in [`modules/dbt_project/variables.tf`](modules/dbt_project/variables.tf). The ones that matter most:

| Variable | Default | Purpose |
| --- | --- | --- |
| `project_name` | required | Project name |
| `connection_id` | required | Existing account-level Snowflake connection |
| `dbt_version` | `latest-fusion` | Release track for every environment |
| `enable_dbt_state` | `false` | dbt State on deployment environments; jobs inherit it |
| `staging_branch` | `null` | Set to add the staging environments |
| `snowflake_deployment` | `null` | Service user, database, role, warehouse for deployment credentials |
| `environment_overrides` | `{}` | Per-environment database, schema, role, warehouse, user |
| `job_triggers` | all `false` | Switch on `schedule`, `ci`, `merge` |
| `create_default_jobs` | `true` | Set `false` when teams own their jobs |
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

- **Who owns what after creation.** Terraform owns everything it creates. A change made in the UI shows up as drift on the next `terraform plan` and is reverted on the next apply. If teams should own their jobs, set `create_default_jobs = false`, or treat the first apply as a bootstrap and stop applying.
- **Adopting an existing project.** Add an `import` block to the project's root, then plan:
  ```hcl
  import {
    to = module.dbt_project.dbtcloud_project.this
    id = "<project_id>"
  }
  ```
- **Before turning on CI and Merge triggers**, attach a repository and run Production - Build once. Those jobs compare against the last successful run in their target environment.
- **`latest-fusion` and dbt State** need to be available on the account. Otherwise set `dbt_version = "latest"` and leave `enable_dbt_state = false`.
- **Not yet applied against a live account.** The configuration validates, plans cleanly and passes its offline tests against provider 1.13, but the first real `terraform apply` is still to be done. The two places most likely to need a tweak are deployment environments created without credentials, and CI or Merge jobs created with their triggers off.
