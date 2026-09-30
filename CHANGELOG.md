# Changelog

All notable changes to this module are documented here.

## Unreleased

- No changes yet.

## 0.1.0

- Extract the Scaleway workload environment into a standalone module.
- Declare node pools as a `node_pools` map, one zone per pool, with optional
  taints and labels.
- Select the control-plane offer with `cluster_type`, including the dedicated
  Kapsule offers.
- Default `kubernetes_version` to `1.37`.
- Make the Kubernetes maintenance window configurable.
- Disable cascading deletion of cluster-created resources by default.
- Add customer-facing IAM, operations, validation, and versioning contracts.
