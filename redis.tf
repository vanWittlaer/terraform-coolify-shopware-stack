# Redis DSN handling. internal_db_url does NOT round-trip (null on every refresh) and — unlike
# MariaDB — the provider exposes no redis password to reconstruct from (see FINDINGS). So each
# Redis URL is CAPTURED ONCE into a terraform_data keyed on the Redis DB itself, NOT on the app:
#   - `input` is evaluated at create when internal_db_url is still valid; ignore_changes freezes
#     it against the provider's refresh-nulling.
#   - keyed on the DB (via for_each + triggers_replace on the DB uuid) so the captured value
#     SURVIVES a replacement of the web/workers resource — the envs_bulk below can be recreated
#     freely and still reads the correct URL from here. Only an actual replacement of the Redis
#     DB re-captures (triggers_replace), which is correct (new instance ⇒ new URL).
#   - coalesce order: live URL on a fresh create; var.redis_url_seed repairs a pre-nulled
#     existing deployment; the loud MISSING_SEED sentinel prevents writing a null/empty URL.
resource "terraform_data" "redis_url" {
  for_each         = toset(["cache", "session"])
  triggers_replace = [coolify_database_redis.r[each.key].uuid]
  input            = coalesce(coolify_database_redis.r[each.key].internal_db_url, try(var.redis_url_seed[each.key], ""), "MISSING_SEED")

  lifecycle {
    ignore_changes = [input]
  }
}

# The two Redis vars in their OWN envs_bulk (not local.shared_env), targeting web (application)
# + workers (service); the backup sidecar uses no Redis. The value comes from the stable
# terraform_data above, so NO ignore_changes is needed here — if this bulk is recreated (web or
# workers replaced), it re-reads the frozen URL and stays correct. See locals.tf (redis_env).
resource "coolify_envs_bulk" "redis_dsns" {
  for_each      = local.redis_targets
  resource_type = each.value.type
  resource_uuid = each.value.uuid
  variables     = local.redis_env
}
