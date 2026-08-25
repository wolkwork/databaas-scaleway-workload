output "cluster_id" {
  description = "Kapsule cluster ID. `scw k8s kubeconfig install <id>` for admin access."
  value       = scaleway_k8s_cluster.this.id
}

output "cluster_name" {
  description = "Kapsule cluster name."
  value       = scaleway_k8s_cluster.this.name
}

output "cluster_endpoint" {
  description = "API server URL. Reachable only from the allowed IPs."
  value       = scaleway_k8s_cluster.this.apiserver_url
}

output "vpc_id" {
  description = "VPC holding the deployment's private networks."
  value       = scaleway_vpc.this.id
}

output "private_network_id" {
  description = "Private network the cluster is attached to."
  value       = scaleway_vpc_private_network.this.id
}

output "bucket_names" {
  description = "Object storage bucket names, keyed by role (lakehouse, metadata, logs, backups)."
  value       = { for role, b in scaleway_object_bucket.this : role => b.name }
}

output "bucket_endpoint" {
  description = "S3-compatible endpoint shared by all buckets in this environment's region."
  value       = "https://s3.${var.region}.scw.cloud"
}
