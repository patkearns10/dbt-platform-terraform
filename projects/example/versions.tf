terraform {
  required_version = ">= 1.11"

  required_providers {
    dbtcloud = {
      source  = "dbt-labs/dbtcloud"
      version = "~> 1.13"
    }
  }

  # No backend block: state is a local terraform.tfstate, which is fine for a
  # first test. Before sharing, copy backend.tf.example to backend.tf.
  # See docs/state.md.
}
