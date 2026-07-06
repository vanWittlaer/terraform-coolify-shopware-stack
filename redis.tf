# REDIS_CACHE_URL / REDIS_SESSION_URL live in their OWN envs_bulk (not local.shared_env) with
# ignore_changes on variables: the value is written once at create (when internal_db_url is
# valid) and never touched again, so the provider's refresh-nulling of internal_db_url can't
# push a null Redis URL to the app. Targets web (application) + workers (service); the backup
# sidecar uses no Redis. See locals.tf (redis_env / redis_targets) and FINDINGS.
resource "coolify_envs_bulk" "redis_dsns" {
  for_each      = local.redis_targets
  resource_type = each.value.type
  resource_uuid = each.value.uuid
  variables     = local.redis_env

  lifecycle {
    ignore_changes = [variables]
  }
}
