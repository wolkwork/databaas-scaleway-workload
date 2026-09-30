# Databaas workload environment on Scaleway.
#
# This module provisions Scaleway infrastructure only: a VPC, private network,
# Kapsule cluster, node pools, API-server ACL, object-storage buckets, and the
# bucket policies that restrict those buckets. Kubernetes software and IAM
# identities are deliberately outside this module.

locals {
  tags = ["databaas", "managed-by=databaas-scaleway-workload", "env=${var.environment}"]

  # Fixed storage roles form part of the module's public contract. The caller's
  # IAM implementation supplies a distinct principal for each consumer grant.
  buckets = toset(["lakehouse", "metadata", "logs", "backups"])

  # Enough to list a bucket and fetch objects - Airflow reading its DAGs - and
  # nothing that mutates. Read grants are already capped by ObjectStorageReadOnly
  # in IAM; spelling the actions out here as well means neither control is solely
  # load-bearing, so widening the IAM set by mistake does not silently grant
  # writes.
  #
  # Split by the resource each action can name, which Scaleway enforces: a
  # statement whose actions can apply to none of its resources is rejected with
  # "Action does not apply to any resource(s) in statement", and it rejects the
  # whole POLICY, not just that statement. Object-level actions need a
  # "<bucket>/<key>" resource; bucket-level ones need the bare bucket. A prefixed
  # grant's Resource list is object-only, so it can only carry the first set.
  bucket_read_object_actions = [
    "s3:GetObject",
    "s3:GetObjectVersion",
  ]

  bucket_read_bucket_actions = [
    "s3:ListBucket",
    "s3:GetBucketLocation",
  ]

  # One or two statements per grant:
  #
  #   unprefixed  a single statement over [bucket, bucket/*]
  #   prefixed    an object statement over [bucket/<prefix>*], plus a
  #               bucket-scoped ListBucket statement carrying a StringLike
  #               condition on s3:prefix - ListBucket targets the bucket itself,
  #               so a Resource pattern cannot narrow it and the condition is the
  #               only way to stop the grant listing the whole bucket
  #
  # Writers get s3:*, bounded by ObjectStorageFullAccess in IAM; the policy's job
  # for them is bucket and prefix isolation, not action isolation.
  bucket_policy_statements = {
    for role in local.buckets : role => flatten([
      # Sids drop the dashes: Scaleway's own examples keep them alphanumeric.
      for grant in var.bucket_policy_principals.grants[role] : concat(
        [{
          Sid       = "${replace(grant.name, "-", "")}Objects"
          Effect    = "Allow"
          Principal = { SCW = grant.principal }
          # An unprefixed grant names the bare bucket below, so bucket-level
          # reads apply and belong here. A prefixed one does not, and adding
          # them anyway is what Scaleway rejects; it gets ListBucket from its
          # List statement instead. readwrite takes s3:*, which always contains
          # an action matching whichever resources are listed.
          Action = grant.access == "readwrite" ? ["s3:*"] : (
            length(grant.prefixes) == 0
            ? concat(local.bucket_read_bucket_actions, local.bucket_read_object_actions)
            : local.bucket_read_object_actions
          )
          Resource = length(grant.prefixes) == 0 ? [
            "${var.name}-${role}",
            "${var.name}-${role}/*",
            ] : [
            for prefix in grant.prefixes : "${var.name}-${role}/${prefix}*"
          ]
        }],
        length(grant.prefixes) == 0 ? [] : [{
          Sid       = "${replace(grant.name, "-", "")}List"
          Effect    = "Allow"
          Principal = { SCW = grant.principal }
          # ListBucket only. s3:GetBucketLocation would be legal here - it is
          # bucket-level and so is the resource - but it carries no s3:prefix, so
          # the condition below can never match it and the grant would be dead.
          # Granting it to a prefixed grant needs a third, unconditioned
          # statement. Consumers that require it need a separate unconditioned
          # statement, which would also consume another policy statement.
          Action   = ["s3:ListBucket"]
          Resource = ["${var.name}-${role}"]
          Condition = {
            StringLike = { "s3:prefix" = [for prefix in grant.prefixes : "${prefix}*"] }
          }
        }],
      )
    ])
  }
}

# One VPC per deployment: a VPC is project-scoped, and projects created after
# 13 May 2025 start without one.
resource "scaleway_vpc" "this" {
  name       = "${var.name}-vpc"
  region     = var.region
  project_id = var.project_id
  tags       = local.tags
}

# Cross-cluster traffic goes over the tailnet.
resource "scaleway_vpc_private_network" "this" {
  name       = "${var.name}-network"
  vpc_id     = scaleway_vpc.this.id
  region     = var.region
  project_id = var.project_id
  tags       = local.tags

  # Scaleway assigns a subnet unless one is given.
  dynamic "ipv4_subnet" {
    for_each = var.private_network_subnet == null ? [] : [var.private_network_subnet]
    content {
      subnet = ipv4_subnet.value
    }
  }
}

resource "scaleway_k8s_cluster" "this" {
  name       = var.name
  type       = var.cluster_type
  version    = var.kubernetes_version
  cni        = "cilium"
  region     = var.region
  project_id = var.project_id
  pod_cidr   = var.pod_cidr

  private_network_id = scaleway_vpc_private_network.this.id

  tags = local.tags

  delete_additional_resources = var.delete_additional_resources

  auto_upgrade {
    enable                        = var.auto_upgrade_enabled
    maintenance_window_start_hour = var.maintenance_window_start_hour
    maintenance_window_day        = var.maintenance_window_day
  }

  autoscaler_config {
    disable_scale_down              = false
    scale_down_delay_after_add      = "5m"
    scale_down_unneeded_time        = "5m"
    estimator                       = "binpacking"
    expander                        = "random"
    ignore_daemonsets_utilization   = true
    balance_similar_node_groups     = true
    expendable_pods_priority_cutoff = -10
  }
}

# One pool per zone is how a cluster spreads across a region: the control plane
# is regional, a pool is not. balance_similar_node_groups above keeps pools of
# the same node type scaled evenly.
resource "scaleway_k8s_pool" "this" {
  for_each = var.node_pools

  cluster_id = scaleway_k8s_cluster.this.id
  name       = "${var.name}-${each.key}"
  node_type  = each.value.node_type
  size       = each.value.node_count
  region     = var.region
  zone       = each.value.zone

  autoscaling = true
  min_size    = each.value.min_nodes
  max_size    = each.value.max_nodes

  root_volume_size_in_gb = each.value.root_volume_size_in_gb

  autohealing         = true
  container_runtime   = "containerd"
  wait_for_pool_ready = true

  labels = each.value.labels
  tags   = concat(local.tags, ["node-pool=${each.key}"])

  # `value` is required by the provider; the variable defaults it to "" so a
  # valueless Kubernetes taint stays expressible.
  dynamic "taints" {
    for_each = each.value.taints
    content {
      key    = taints.value.key
      value  = taints.value.value
      effect = taints.value.effect
    }
  }

  upgrade_policy {
    max_unavailable = 1
    max_surge       = 1
  }
}

resource "scaleway_k8s_acl" "this" {
  cluster_id = scaleway_k8s_cluster.this.id
  region     = var.region

  dynamic "acl_rules" {
    for_each = var.api_server_allowed_ips
    content {
      ip          = acl_rules.value.ip
      description = acl_rules.value.description
    }
  }

  dynamic "acl_rules" {
    for_each = var.api_server_allow_scaleway_ranges ? [1] : []
    content {
      scaleway_ranges = true
      description     = "Scaleway internal ranges"
    }
  }
}

# -----------------------------------------------------------------------------
# Object Storage - lakehouse (Iceberg tables), metadata (JupyterHub user/shared
# folders and DAGs), logs (application logs), and backups (CNPG WAL + base
# backups). One bucket each, unversioned unless var.bucket_versioning says
# otherwise.
#
# Credentials and IAM policies are created by the caller's IAM authority. The
# resource policies that scope those credentials are created here, so each
# bucket and its restrictive policy are managed in the same apply. The IAM
# principal IDs enter through var.bucket_policy_principals.
# -----------------------------------------------------------------------------

resource "scaleway_object_bucket" "this" {
  for_each = local.buckets

  name          = "${var.name}-${each.key}"
  region        = var.region
  project_id    = var.project_id
  force_destroy = var.bucket_force_destroy

  tags = {
    databaas    = "true"
    managed-by  = "databaas-scaleway-workload"
    environment = var.environment
    role        = each.key
  }

  versioning {
    enabled = lookup(var.bucket_versioning, each.key, false)
  }
}

# Scaleway IAM Object Storage permissions are project-wide, because
# Scaleway has no bucket-scoped permission sets. These policies are what confine
# each one to a single bucket - without them the metadata key, which lands in
# JupyterHub pods running arbitrary user notebook code, could read the whole
# lakehouse and delete every CNPG backup.
#
# Two Scaleway semantics shape them:
#
#   1. IAM and bucket policies are an INTERSECTION - an action needs an allow
#      from both. The caller's project-scoped Object Storage IAM permissions
#      therefore stay; removing them revokes access rather than
#      tightening it. (databaas-infra/CLAUDE.md claims the bucket policy alone
#      authorizes the key. That is wrong - do not port that assumption over.)
#   2. A policy is DENY-BY-DEFAULT once attached: "All actions that are not
#      explicitly allowed are denied". Every principal that touches the bucket
#      must be named, including ones that only read its configuration.
#
# The intersection is also why the management statement can be a blanket s3:*
# without widening anything: each principal is still capped by its own IAM
# policy, so the plan identity stays read-only. That avoids having to enumerate
# the exact configuration reads a refresh performs.
resource "scaleway_object_bucket_policy" "this" {
  for_each = local.buckets

  bucket     = scaleway_object_bucket.this[each.key].name
  project_id = var.project_id

  policy = jsonencode({
    Version = "2023-04-17"
    Id      = "${var.name}-${each.key}"
    Statement = concat(
      local.bucket_policy_statements[each.key],
      [{
        Sid       = "ManagementAccess"
        Effect    = "Allow"
        Principal = { SCW = var.bucket_policy_principals.management }
        Action    = ["s3:*"]
        Resource = [
          scaleway_object_bucket.this[each.key].name,
          "${scaleway_object_bucket.this[each.key].name}/*",
        ]
      }],
    )
  })
}

check "zones_match_region" {
  assert {
    condition     = alltrue([for pool in var.node_pools : startswith(pool.zone, "${var.region}-")])
    error_message = "Every node pool's zone must belong to region (for example, nl-ams-1 belongs to nl-ams)."
  }
}
