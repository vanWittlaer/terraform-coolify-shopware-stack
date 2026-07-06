# terraform-coolify-shopware-stack

An OpenTofu module that provisions a full Shopware 6 runtime on [Coolify](https://coolify.io):
web app + workers/scheduler (one image), MariaDB, 2× Redis (cache/session), RabbitMQ,
Elasticsearch, optional Mailpit (staging) and an optional backup sidecar.

Provider quirks and version couplings are documented in [`FINDINGS.md`](./FINDINGS.md) and
[`COMPATIBILITY.md`](./COMPATIBILITY.md).

## Usage

```hcl
provider "coolify" {
  endpoint = var.coolify_endpoint
  token    = var.coolify_token
}

module "production" {
  source = "github.com/vanWittlaer/terraform-coolify-shopware-stack?ref=v0.1.0"

  environment_name = "production"
  project_uuid     = coolify_project.shopware.uuid
  server_uuid      = var.server_uuid
  coolify_endpoint = var.coolify_endpoint
  coolify_token    = var.coolify_token
  web_image        = "ghcr.io/you/app/prod"
  web_image_tag    = "latest"
  web_domain       = "https://shop.example.com"
  app_env          = "prod"
  app_debug        = "0"
  # ... see Inputs below and examples/two-environment/
}
```

A complete two-environment (production + staging) wiring is in
[`examples/two-environment/`](./examples/two-environment/).

> **Providers:** this module has no `provider` block — it inherits the configured `coolify` and
> `null` providers from the calling configuration. The `aws` provider used for S3 bucket CORS is a
> *consumer* concern and lives outside this module (see the example).

## Inputs

| Name | Description |
|------|-------------|
| `environment_name` | Coolify environment name (`production` / `staging`). |
| `project_uuid` | UUID of the owning Coolify project. |
| `server_uuid` | UUID of the target Coolify server. |
| `coolify_endpoint` / `coolify_token` | Control-plane URL + token (used by the module's `local-exec` API calls). |
| `web_image` / `web_image_tag` / `web_domain` | The app image and its public domain. |
| `app_env` / `app_debug` / `monolog_log_level` | Per-environment runtime settings. |
| `static_env` | Map of extra env vars fanned out to every app process. |
| `mailer_dsn` | Production SMTP DSN (ignored when `enable_mailpit`). |
| `enable_elasticsearch` / `enable_mailpit` / `enable_backup` | Feature toggles. |
| `mailpit_domain` | Public FQDN for the staging Mailpit UI (Traefik → :8025). |
| `backup` / `backup_image` / `backup_image_tag` | Backup sidecar config + image. |
| `mariadb_conf` / `redis_conf` | Per-service tuning (`redis_conf` is a `{cache,session}` map). |
| `mariadb_public_port` / `rabbitmq_mgmt_port` | Host ports for DB / RabbitMQ mgmt UI. |
| `log_host_path` / `basic_auth_host_path` | Host bind-mount paths (`var/log`, staging `.htpasswd` dir). |
| `s3` | Object-storage object (buckets/region/endpoint/cdn). |
| `secrets` | Sensitive object (`app_secret`, `instance_id`, S3/RabbitMQ/backup creds, `server_uuid`). |

## Outputs

| Name | Description |
|------|-------------|
| `web_uuid` | Coolify UUID of the web application. |
| `workers_service_uuid` | UUID of the workers/scheduler service. |
| `mariadb_uuid` | UUID of the MariaDB database. |
| `rabbitmq_uuid` | UUID of the RabbitMQ service. |

## Requirements

- OpenTofu ≥ 1.7
- Provider `coolify-terraform/coolify` ≥ 0.1.7, `hashicorp/null`
- A running Coolify v4 control plane (validated against 4.1.2 — see `COMPATIBILITY.md`)
