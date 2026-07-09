# DB credentials are OURS (random_password, alphanumeric — same shape as Coolify's own
# generator): Coolify's API hides sensitive fields (internal_db_url, redis_password, …) from
# every response unless the token has the read:sensitive ability, so a Coolify-generated
# password is invisible to the provider and no DSN could be built from it. Supplying the
# passwords at create keeps every DSN reconstructable from values the state already owns —
# self-healing across refreshes, no sensitive read, no capture/seed machinery. See FINDINGS
# ("read:sensitive").
resource "random_password" "mariadb" {
  for_each = toset(["user", "root"])
  length   = 64
  special  = false # alphanumeric only → no percent-encoding needed in the DSN
}

resource "coolify_database_mariadb" "main" {
  name                  = "mariadb"
  project_uuid          = var.project_uuid
  server_uuid           = var.server_uuid
  environment_name      = var.environment_name
  image                 = "mariadb:11.8"
  mariadb_user          = "shopware"
  mariadb_password      = random_password.mariadb["user"].result
  mariadb_database      = "shopware"
  mariadb_root_password = random_password.mariadb["root"].result
  # Optional public exposure (host port -> container 3306). Set on an existing DB this
  # goes through the Update path (SetUpdateExtendedDiff = only changed fields), so unlike
  # mariadb_conf it does NOT drag in the forbidden enable_ssl/is_log_drain_enabled/
  # is_include_timestamps fields. null = internal-only.
  is_public   = var.mariadb_public_port != null
  public_port = var.mariadb_public_port
  # DB tuning is DISABLED via tofu against this Coolify version. conf can only be set
  # through the provider's "extended fields" UPDATE call (Create triggers it whenever
  # MariadbConf is configured). 0.1.7 bundles enable_ssl / is_log_drain_enabled /
  # is_include_timestamps into that payload, and this Coolify API rejects them
  # (HTTP 422 "This field is not allowed"), so ANY conf value fails the update and taints
  # the DB. Forcing null skips the update entirely → clean create.
  # Apply my.cnf tuning in the Coolify UI until the provider/API align;
  # var.mariadb_conf (production.tfvars) is kept as the intended config. See FINDINGS.
  mariadb_conf   = null
  instant_deploy = true
}

# Two dedicated Redis instances (cache / session) with module-owned passwords (above);
# the DSNs are reconstructed in locals.tf, mirroring mariadb_dsn. Symfony lock uses the
# shared DB (LOCK_DSN=DATABASE_URL), so no dedicated lock Redis.
resource "random_password" "redis" {
  for_each = toset(["cache", "session"])
  length   = 64
  special  = false # alphanumeric only → no percent-encoding needed in the DSN
}

resource "coolify_database_redis" "r" {
  for_each         = toset(["cache", "session"])
  name             = "redis-${each.key}"
  project_uuid     = var.project_uuid
  server_uuid      = var.server_uuid
  environment_name = var.environment_name
  image            = "redis:7.4"
  # Becomes the container's REDIS_PASSWORD (create_standalone_redis honors a supplied
  # redis_password); provider 0.1.7 sends it in the CREATE payload, not the 422-prone
  # extended-fields update.
  redis_password = random_password.redis[each.key].result
  # DISABLED — same forbidden-field 422 on the extended-fields update as mariadb_conf
  # (see note above). null skips the update; set redis.conf in the Coolify UI for now.
  redis_conf     = null
  instant_deploy = true
}
