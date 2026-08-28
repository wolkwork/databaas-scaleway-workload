variable "name" {
  description = "Base name for the VPC, network, cluster, pool, and object storage buckets (bucket name = \"<name>-<role>\"), e.g. databaas-workload-dev."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,50}$", var.name))
    error_message = "name must be lowercase alphanumeric with dashes."
  }
}

variable "environment" {
  description = "Environment this workload environment serves (dev, prod). Tags and descriptions only - does not affect resource names."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,20}$", var.environment))
    error_message = "environment must be lowercase alphanumeric with dashes."
  }
}

variable "project_id" {
  description = "Scaleway project to create resources in. Defaults to the provider's project (the deploy key's default project)."
  type        = string
  default     = null

  validation {
    condition     = var.project_id == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.project_id))
    error_message = "project_id must be null or a lowercase UUID."
  }
}

variable "region" {
  description = "Scaleway region."
  type        = string
  default     = "nl-ams"
}

variable "zone" {
  description = "Scaleway zone for the node pool."
  type        = string
  default     = "nl-ams-1"
}

variable "kubernetes_version" {
  description = "Kapsule Kubernetes version."
  type        = string
  default     = "1.34"
}

variable "auto_upgrade_enabled" {
  description = "Enable automatic Kapsule Kubernetes upgrades during the configured maintenance window."
  type        = bool
  default     = true
}

variable "maintenance_window_start_hour" {
  description = "UTC hour at which the weekly Kubernetes maintenance window starts."
  type        = number
  default     = 3

  validation {
    condition     = var.maintenance_window_start_hour >= 0 && var.maintenance_window_start_hour <= 23 && floor(var.maintenance_window_start_hour) == var.maintenance_window_start_hour
    error_message = "maintenance_window_start_hour must be a whole number from 0 through 23."
  }
}

variable "maintenance_window_day" {
  description = "Lowercase weekday for the Kubernetes maintenance window."
  type        = string
  default     = "sunday"

  validation {
    condition     = contains(["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"], var.maintenance_window_day)
    error_message = "maintenance_window_day must be a lowercase weekday name."
  }
}

variable "delete_additional_resources" {
  description = "Delete additional cluster-created resources when the cluster is destroyed. Disabled by default to avoid cascading deletion during customer handover or recovery."
  type        = bool
  default     = false
}

variable "private_network_subnet" {
  description = "IPv4 CIDR for the cluster's private network, e.g. 172.16.32.0/22, sitting outside pod_cidr. Scaleway assigns one when null."
  type        = string
  default     = null

  validation {
    condition     = var.private_network_subnet == null || can(cidrnetmask(var.private_network_subnet))
    error_message = "private_network_subnet must be null or a valid IPv4 CIDR."
  }
}

variable "pod_cidr" {
  description = "Pod CIDR, set to sit outside the Tailscale IP range."
  type        = string
  default     = "10.244.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.pod_cidr))
    error_message = "pod_cidr must be a valid IPv4 CIDR."
  }
}

variable "node_type" {
  description = "Node pool instance type."
  type        = string
}

variable "node_count" {
  description = "Initial node count. Must sit between min_nodes and max_nodes."
  type        = number

  validation {
    condition     = var.node_count >= 1 && floor(var.node_count) == var.node_count
    error_message = "node_count must be a positive whole number."
  }
}

variable "min_nodes" {
  description = "Autoscaler lower bound."
  type        = number

  validation {
    condition     = var.min_nodes >= 1 && floor(var.min_nodes) == var.min_nodes
    error_message = "min_nodes must be a positive whole number."
  }
}

variable "max_nodes" {
  description = "Autoscaler upper bound."
  type        = number

  validation {
    condition     = var.max_nodes >= 1 && floor(var.max_nodes) == var.max_nodes
    error_message = "max_nodes must be a positive whole number."
  }
}

# Kapsule's minimum is 20GB, which the image cache can fill and trigger
# DiskPressure evictions, so the default sits above it.
#
# 40 rather than more because it is the largest value valid on every node type
# we use: local-storage types (DEV1-*) root onto the instance's local SSD, whose
# size the type fixes - 40GB on DEV1-M - and the API rejects anything larger.
variable "root_volume_size_in_gb" {
  description = "System volume size per node, above Kapsule's 20GB minimum for image cache headroom. Defaults to the largest value every supported node type accepts; raise it on block-backed types (PRO2-*, POP2-*)."
  type        = number
  default     = 40

  validation {
    condition     = var.root_volume_size_in_gb >= 20 && floor(var.root_volume_size_in_gb) == var.root_volume_size_in_gb
    error_message = "root_volume_size_in_gb must be a whole number of at least 20."
  }
}

variable "api_server_allowed_ips" {
  description = "Public IPs allowed to reach the cluster API server."
  type = list(object({
    ip          = string
    description = optional(string, "")
  }))

  validation {
    condition     = length(var.api_server_allowed_ips) > 0
    error_message = "api_server_allowed_ips must contain at least one approved administrative route."
  }

  validation {
    condition     = alltrue([for rule in var.api_server_allowed_ips : can(cidrhost(rule.ip, 0))])
    error_message = "Every api_server_allowed_ips entry must contain a valid CIDR."
  }
}

variable "api_server_allow_scaleway_ranges" {
  description = "Admit Scaleway's internal ranges to the API server. Required by internal services."
  type        = bool
  default     = true
}

variable "bucket_force_destroy" {
  description = "Allow destroying the workload buckets even when they still hold objects. Set true in dev, keep false in prod."
  type        = bool
  default     = false
}

# Off by default: versioning keeps every overwritten and deleted object, which
# costs storage and, without lifecycle rules to expire noncurrent versions, grows
# without bound. Enable it per bucket where recovering an overwrite is worth that
# - `backups` is the first candidate in an environment holding real data.
variable "bucket_versioning" {
  description = "Buckets to enable object versioning on, keyed by role, e.g. { backups = true }. Roles left out stay unversioned."
  type        = map(bool)
  default     = {}

  validation {
    condition     = length(setsubtract(keys(var.bucket_versioning), ["lakehouse", "metadata", "logs", "backups"])) == 0
    error_message = "bucket_versioning keys must be bucket roles: lakehouse, metadata, logs, backups."
  }
}

# Supplied by the caller's IAM authority. This module intentionally does not
# create or query IAM identities. Bucket policies are deny-by-default, so an
# incomplete value here locks the deployment out of its own buckets.
variable "bucket_policy_principals" {
  description = "What each bucket's policy authorizes. `grants` maps a bucket role to the per-application grants on it: `name` (lowercase alphanumeric, used in resource names and statement IDs), `principal`, `access` (\"readwrite\" or \"read\") and `prefixes` (key prefixes the grant is confined to, empty for the whole bucket). `management` lists the identities that manage or plan the buckets and must never be omitted."
  type = object({
    grants = map(list(object({
      name      = string
      principal = string
      access    = string
      prefixes  = list(string)
    })))
    management = list(string)
  })

  validation {
    condition     = length(setsubtract(["lakehouse", "metadata", "logs", "backups"], keys(var.bucket_policy_principals.grants))) == 0 && length(setsubtract(keys(var.bucket_policy_principals.grants), ["lakehouse", "metadata", "logs", "backups"])) == 0
    error_message = "bucket_policy_principals.grants must contain exactly these bucket roles: lakehouse, metadata, logs, backups."
  }

  # Scaleway caps a bucket policy at 10 statements and rejects the 11th at
  # APPLY, not plan. So validate here ourselves
  validation {
    condition = alltrue([
      for role, grants in var.bucket_policy_principals.grants :
      1 + length(grants) + length([for grant in grants : grant if length(grant.prefixes) > 0]) <= 10
    ])
    error_message = "A bucket policy would exceed Scaleway's limit of 10 statements. Each grant costs one statement, prefixed grants two, plus one for management. Move grants to their own bucket role rather than merging them - merging unions their prefixes across principals, which widens access."
  }

  validation {
    condition = alltrue([
      for role, grants in var.bucket_policy_principals.grants : length(grants) > 0
    ])
    error_message = "Every bucket role needs at least one grant; a bucket whose policy names no application is unusable by the services that depend on it."
  }

  validation {
    condition = alltrue(flatten([
      for role, grants in var.bucket_policy_principals.grants : [
        for grant in grants : contains(["readwrite", "read"], grant.access)
      ]
    ]))
    error_message = "Each grant's access must be \"readwrite\" or \"read\"."
  }

  validation {
    condition = alltrue(flatten([
      for role, grants in var.bucket_policy_principals.grants : [
        for grant in grants : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", grant.name))
      ]
    ]))
    error_message = "Each grant's name must be lowercase alphanumeric, optionally dash-separated, e.g. \"airflow-logs\"."
  }

  # Statement IDs strip the dashes, so two names differing only by dashes would
  # produce one Sid and a confusing policy.
  validation {
    condition = alltrue([
      for role, grants in var.bucket_policy_principals.grants :
      length(distinct([for grant in grants : replace(grant.name, "-", "")])) == length(grants)
    ])
    error_message = "Grant names on the same bucket role must stay distinct once dashes are removed (\"airflow-logs\" and \"airflowlogs\" collide)."
  }

  # A prefix without its trailing slash would also match sibling keys sharing the
  # same leading characters ("dag" matching "dags-archive/").
  validation {
    condition = alltrue(flatten([
      for role, grants in var.bucket_policy_principals.grants : [
        for grant in grants : [
          for prefix in grant.prefixes : can(regex("^[^/].*/$", prefix))
        ]
      ]
    ]))
    error_message = "Each prefix must end with \"/\" and must not start with one, e.g. \"dags/\" or \"jupyter/shared/\"."
  }

  validation {
    condition     = length(var.bucket_policy_principals.management) > 0
    error_message = "bucket_policy_principals.management must not be empty: bucket policies are deny-by-default, so omitting the deploy identity leaves this root unable to manage or destroy its own buckets."
  }

  validation {
    condition = alltrue([
      for principal in concat(
        flatten([for role, grants in var.bucket_policy_principals.grants : [for grant in grants : grant.principal]]),
        var.bucket_policy_principals.management,
      ) :
      can(regex("^(application_id|user_id|project_id):[0-9a-f-]{36}$", principal))
    ])
    error_message = "Every principal must be \"application_id:<uuid>\", \"user_id:<uuid>\" or \"project_id:<uuid>\" - Scaleway silently accepts a malformed principal and the policy then denies it."
  }
}
