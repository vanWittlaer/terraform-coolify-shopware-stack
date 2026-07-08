# terraform-coolify-shopware-stack

An OpenTofu module that provisions a full Shopware 6 runtime on [Coolify](https://coolify.io):
web app + workers/scheduler (one image), MariaDB, 2× Redis (cache/session), RabbitMQ,
Elasticsearch, optional Mailpit (staging) and an optional backup sidecar.

Provider quirks and version couplings are documented in [`FINDINGS.md`](./FINDINGS.md) and
[`COMPATIBILITY.md`](./COMPATIBILITY.md).

## Intended usage: day-0 bootstrap

This module is built to be applied **once**, at setup time — after that the
**Coolify UI is the single source of truth** for the running environment.
The Coolify provider pushes env vars write-only (re-sent on every apply, UI
drift invisible), so re-applying against a UI-managed environment silently
overwrites changes made there. Provision, verify, then archive your state and
secrets off-machine; upgrade running shops via the Coolify UI, not by
re-applying a newer module version.

The turnkey consumer is the
[`ddev-coolify-bootstrap`](https://github.com/vanWittlaer/ddev-coolify-bootstrap)
ddev add-on (`ddev coolify-bootstrap init && ddev coolify-bootstrap up`), with
[swoofy](https://github.com/vanWittlaer/swoofy) as the full reference project.

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

## Adopting this module

1. Copy [`examples/two-environment/`](./examples/two-environment/) as your root config and point
   `source` at a pinned `?ref=`.
2. Work through [`PREREQUISITES.md`](./PREREQUISITES.md) — what must be true around `tofu apply`
   (Coolify token + server, a built web image in a registry, S3 buckets, DNS, secrets) and the
   one-time manual steps after it (log-dir chown, `.htpasswd`, ES index build).
3. Decide state handling in [`STATE.md`](./STATE.md) — local + backup by default; S3 if shared.
4. `tofu init && tofu plan && tofu apply`.

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
| `log_host_base` | Host BASE dir for bind mounts; the module appends `/<environment_name>/var/log` (and `/auth`). Empty ⇒ no log mount. |
| `enable_basic_auth` | Bind-mount `<log_host_base>/<env>/auth` (`.htpasswd`) into the web app — typically `true` for staging, `false` for production. |
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
