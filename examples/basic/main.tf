provider "scaleway" {
  region = "nl-ams"
  zone   = "nl-ams-1"
}

module "databaas_workload" {
  source = "../.."

  name        = "example-databaas-dev"
  environment = "dev"

  node_type  = "DEV1-M"
  node_count = 2
  min_nodes  = 2
  max_nodes  = 4

  root_volume_size_in_gb = 40

  api_server_allowed_ips = [
    {
      ip          = "192.0.2.10/32"
      description = "Documentation-only administrative route"
    }
  ]

  bucket_policy_principals = {
    grants = {
      lakehouse = [
        {
          name      = "lakekeeper"
          principal = "application_id:11111111-1111-4111-8111-111111111111"
          access    = "readwrite"
          prefixes  = []
        }
      ]
      metadata = [
        {
          name      = "jupyterhub"
          principal = "application_id:22222222-2222-4222-8222-222222222222"
          access    = "readwrite"
          prefixes  = ["jupyter/"]
        },
        {
          name      = "airflow-dags"
          principal = "application_id:33333333-3333-4333-8333-333333333333"
          access    = "read"
          prefixes  = ["dags/"]
        }
      ]
      logs = [
        {
          name      = "airflow-logs"
          principal = "application_id:44444444-4444-4444-8444-444444444444"
          access    = "readwrite"
          prefixes  = ["logs/airflow/"]
        }
      ]
      backups = [
        {
          name      = "cnpg"
          principal = "application_id:55555555-5555-4555-8555-555555555555"
          access    = "readwrite"
          prefixes  = ["database-backups/"]
        }
      ]
    }
    management = [
      "application_id:aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      "application_id:bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    ]
  }
}
