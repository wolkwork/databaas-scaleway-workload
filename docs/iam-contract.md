# IAM integration contract

This module owns Scaleway infrastructure resources and Object Storage bucket
policies. It intentionally does not own IAM identities or credentials.

## Responsibilities

The customer IAM authority must create:

- one deployment identity with the product permissions needed to create and
  manage the module's resources;
- one read-only plan identity;
- one IAM application and API key for every application-to-bucket grant;
- a secure delivery path for runtime credentials;
- rotation and revocation procedures for every credential.

The deployment identity requires the appropriate project-scoped permissions for
Kubernetes, VPC, private networks, Object Storage, and bucket policies. The plan
identity should receive read-only equivalents. Neither identity needs permission
to create IAM resources.

The exact Scaleway permission-set names must be verified against the customer
organization before deployment. Provider permission sets can change independently
of this module.

## Principal value

`bucket_policy_principals` has this shape:

```hcl
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
      }
    ]
    logs = [
      {
        name      = "airflow-logs"
        principal = "application_id:33333333-3333-4333-8333-333333333333"
        access    = "readwrite"
        prefixes  = ["logs/airflow/"]
      }
    ]
    backups = [
      {
        name      = "cnpg"
        principal = "application_id:44444444-4444-4444-8444-444444444444"
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
```

All identifiers above are documentation-only values.

## Access model

Scaleway evaluates IAM permissions and bucket policies as an intersection.
Bucket policies do not replace IAM permission sets:

- IAM bounds what operations a principal may perform inside the project.
- The bucket policy narrows that principal to a bucket and optional prefixes.

Use one principal per grant. Do not share a credential between applications or
combine read-only and read-write responsibilities into one grant. Independent
principals provide independent rotation, revocation, and audit trails.

## Prefix behavior

A prefixed grant produces two policy statements:

1. object access scoped to `<bucket>/<prefix>*`;
2. `ListBucket` scoped with an `s3:prefix` condition.

Prefixes must end with `/`. The application configuration must use the same
prefix; otherwise access fails closed.

## Ten-statement policy limit

Scaleway limits a bucket policy to ten statements. Each unprefixed grant costs
one statement, each prefixed grant costs two, and management principals share
one statement. The module validates this limit before apply.

If a bucket reaches the limit, create a new storage role/module capability in a
reviewed module release. Do not merge unrelated grants or widen prefixes merely
to fit the policy.

## Secret delivery

API keys must never be passed through module variables, committed to Git, or
returned as module outputs. Deliver them through the customer-selected secret
backend and synchronize them to Kubernetes with the customer's approved secret
delivery mechanism.

The customer must be able to revoke Wolk-operated identities without affecting
its own administrative access.

## Remote-state isolation

Runtime Object Storage credentials receive project-scoped IAM permission sets.
The four buckets created by this module are protected by restrictive bucket
policies, but a different unprotected bucket in the same project falls back to
IAM-only authorization. That includes a remote-state bucket if it is placed in
the workload project without its own policy.

OpenTofu state can contain sensitive computed attributes, including cluster
administrative material. Therefore either:

- keep state in a separate customer-owned project; or
- attach a deny-by-default policy that names only the state plan, deployment,
  and approved recovery identities.

Do not grant runtime application principals access to infrastructure state.
