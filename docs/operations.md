# Operational contract

## Before deployment

- Confirm the Scaleway project is customer-owned.
- Protect and version the remote-state bucket. Prefer a separate customer-owned
  state project; otherwise apply a restrictive policy that excludes every
  runtime Object Storage principal.
- Use separate read-only plan and write-capable deployment identities.
- Review Kapsule node sizing and regional availability.
- Confirm the pod CIDR, private-network CIDR, and administrative routes do not
  overlap.
- Create and validate every IAM principal referenced by the bucket policies.
- Confirm backup retention, restore objectives, and offboarding requirements.

## Changes requiring extra review

- Reducing `min_nodes` or `node_count`.
- Changing `node_type`, which can replace the node pool.
- Changing `cluster_type`, which replaces the cluster unless Scaleway offers the
  new type as an in-place upgrade.
- Changing `cluster_type`, which replaces the cluster unless Scaleway offers the
  new type as an in-place upgrade.
- Changing network or pod CIDRs.
- Removing an API-server allowlist entry.
- Changing bucket-policy principals or prefixes.
- Enabling `bucket_force_destroy`.
- Enabling `delete_additional_resources`.
- Disabling automatic Kubernetes upgrades.

## Destruction

Production deployments should keep `bucket_force_destroy = false` and
`delete_additional_resources = false`. Before destroying a customer environment:

1. freeze or redirect writes;
2. export the lakehouse objects and catalog metadata;
3. export PostgreSQL and identity data;
4. verify checksums and restoration in a customer-controlled destination;
5. obtain customer approval;
6. revoke Wolk access;
7. apply the agreed retention and deletion policy.

Object files alone are not a complete Iceberg handover. Catalog metadata and
table locations must also be exported or rewritten.

## Recovery

Remote state, application data, and backups have different recovery procedures.
Protecting state does not protect customer data, and bucket versioning does not
replace tested database and lakehouse restores.
