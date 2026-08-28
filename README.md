# Databaas Scaleway workload

Reusable OpenTofu module for provisioning an isolated Databaas workload
environment in a customer-owned Scaleway project.

The module creates:

- one VPC and private network;
- one Kapsule Kubernetes cluster with Cilium;
- one autoscaled and auto-healed node pool;
- an explicit Kubernetes API-server allowlist;
- dedicated `lakehouse`, `metadata`, `logs`, and `backups` buckets;
- deny-by-default bucket policies scoped to caller-supplied IAM principals.

It does **not** create Scaleway projects, IAM applications, IAM policies, API
keys, remote state, DNS, Tailscale, Argo CD, Kubernetes workloads, or secrets.
Those remain under the control of the customer infrastructure and delivery
repositories.

## Why this is a separate module

Databaas customers can own their cloud account, infrastructure state, and
deployment credentials while consuming the same reviewed infrastructure
implementation. Customer-specific sizing, networking, retention, and access
configuration stays in the customer infrastructure repository. No customer
configuration belongs in this repository.

## Versioning

Consume an immutable release tag. Do not point a customer environment at
`main`.

```hcl
module "databaas_workload" {
  source = "git::ssh://git@github.com/wolkwork/databaas-scaleway-workload.git?ref=v0.1.0"

  # Customer-specific inputs follow.
}
```

Before `v1.0.0`, a minor release may contain an intentional breaking change.
After `v1.0.0`, releases follow Semantic Versioning.

## Usage

The example below uses documentation-only principal IDs and an RFC 5737 IP
address. Replace every value with customer-owned configuration.

```hcl
module "databaas_workload" {
  source = "git::ssh://git@github.com/wolkwork/databaas-scaleway-workload.git?ref=v0.1.0"

  name        = "example-databaas-prod"
  environment = "prod"
  project_id  = var.scaleway_project_id

  region = "nl-ams"
  zone   = "nl-ams-1"

  node_type  = "REPLACE_WITH_REVIEWED_NODE_TYPE"
  node_count = 3
  min_nodes  = 3
  max_nodes  = 10

  root_volume_size_in_gb = 100

  api_server_allowed_ips = [
    {
      ip          = "192.0.2.10/32"
      description = "Replace with an approved administrative route"
    }
  ]

  bucket_force_destroy = false
  bucket_versioning = {
    backups = true
  }

  bucket_policy_principals = var.bucket_policy_principals
}
```

The complete validation-only example is in [`examples/basic`](examples/basic).

## IAM contract

Scaleway Object Storage IAM permissions are project-scoped rather than
bucket-scoped. The caller must therefore create a separate IAM principal for
each application grant and pass those principal IDs into this module. This
module creates the bucket policies that narrow each principal to the intended
bucket and optional prefixes.

IAM and bucket policies are evaluated together. A consumer needs both:

1. a customer-managed Scaleway IAM policy granting the required Object Storage
   permission set in the project; and
2. a bucket-policy grant supplied through `bucket_policy_principals`.

The deployment and plan identities must be included in `management`, otherwise
the deny-by-default policy can prevent later plans and applies from reading the
bucket configuration.

See [`docs/iam-contract.md`](docs/iam-contract.md) before integrating the
module with a customer IAM implementation.

## Safety defaults

- `bucket_force_destroy` defaults to `false`.
- `delete_additional_resources` defaults to `false`.
- API-server access requires at least one explicit CIDR.
- Bucket policy roles must be exactly `lakehouse`, `metadata`, `logs`, and
  `backups`.
- Every bucket needs at least one application grant and a management principal.
- Bucket-policy statement counts are validated against Scaleway's ten-statement
  limit.
- Automatic Kubernetes upgrades are enabled in a configurable maintenance
  window.

These controls reduce accidental deletion, but they do not replace protected
branches, reviewed plans, remote-state protection, backups, restore tests, or a
customer offboarding procedure.

The remote-state bucket needs special treatment. Runtime Object Storage IAM
permissions are project-scoped, so a state bucket in the workload project must
have its own restrictive bucket policy naming only the state plan/deployment
identities. Using a separate customer-owned state project is stronger. Never
leave a state bucket in the workload project governed by IAM alone.

## Storage roles

| Role | Intended data |
|---|---|
| `lakehouse` | Iceberg/Parquet data managed through Lakekeeper |
| `metadata` | Notebook files, shared files, and Airflow DAG artifacts |
| `logs` | High-churn application logs such as Airflow remote logs |
| `backups` | CNPG base backups and WAL archives |

Bucket names are derived as `<name>-<role>` and cannot be overridden
individually. This makes the naming contract predictable across customer
environments.

Versioning retains overwritten and deleted objects and can grow without bound
without lifecycle rules. Enabling it is a customer retention decision, not a
substitute for tested backups and restores.

## Inputs

| Name | Required | Default | Purpose |
|---|---:|---|---|
| `name` | yes | — | Base name for the cluster, network, and buckets |
| `environment` | yes | — | Environment label such as `dev` or `prod` |
| `project_id` | no | provider default | Customer Scaleway project ID |
| `region` | no | `nl-ams` | Scaleway region |
| `zone` | no | `nl-ams-1` | Node-pool zone; must belong to `region` |
| `kubernetes_version` | no | `1.34` | Kapsule Kubernetes version |
| `node_type` | yes | — | Scaleway node-pool instance type |
| `node_count` | yes | — | Initial node count |
| `min_nodes` | yes | — | Autoscaler minimum |
| `max_nodes` | yes | — | Autoscaler maximum |
| `root_volume_size_in_gb` | no | `40` | Node root-volume size |
| `private_network_subnet` | no | assigned by Scaleway | Optional private-network CIDR |
| `pod_cidr` | no | `10.244.0.0/16` | Kubernetes pod CIDR |
| `api_server_allowed_ips` | yes | — | Approved CIDRs for the public API endpoint |
| `api_server_allow_scaleway_ranges` | no | `true` | Allow required Scaleway internal ranges |
| `auto_upgrade_enabled` | no | `true` | Enable Kapsule automatic upgrades |
| `maintenance_window_day` | no | `sunday` | Upgrade weekday |
| `maintenance_window_start_hour` | no | `3` | Upgrade start hour in UTC |
| `delete_additional_resources` | no | `false` | Cascade deletion of cluster-created resources |
| `bucket_force_destroy` | no | `false` | Permit deletion of non-empty data buckets |
| `bucket_versioning` | no | `{}` | Per-role Object Storage versioning |
| `bucket_policy_principals` | yes | — | Caller-managed application and management principals |

## Outputs

| Name | Purpose |
|---|---|
| `cluster_id` | Kapsule cluster ID |
| `cluster_name` | Kapsule cluster name |
| `cluster_endpoint` | Kubernetes API-server URL |
| `vpc_id` | VPC ID |
| `private_network_id` | Private-network ID |
| `bucket_names` | Bucket names keyed by storage role |
| `bucket_endpoint` | Regional S3-compatible endpoint |

No credential or kubeconfig is returned as an output.

## Validation

```bash
./scripts/validate.sh
```

Validation requires OpenTofu 1.10 or newer and network access to download the
Scaleway provider.

## License

Apache License 2.0. See [`LICENSE`](LICENSE).
