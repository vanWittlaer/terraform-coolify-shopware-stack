resource "coolify_project" "shopware" {
  name        = var.project_name
  description = var.project_description
}

# "production" exists by default in a new Coolify project; create "staging".
resource "coolify_environment" "staging" {
  project_uuid = coolify_project.shopware.uuid
  name         = "staging"
  description  = "Staging environment"
}

locals {
  # TRUSTED_PROXIES is a required invariant for correct HTTPS behind Coolify's proxy, NOT a
  # tuning knob — so it is merged into static_env here rather than left in the tfvars/default,
  # where overriding static_env (a map => replace, not merge) would silently drop it and break
  # admin/storefront assets as mixed content. var.static_env wins, so an operator can still
  # override the key deliberately.
  #
  # Coolify's proxy terminates TLS and forwards plain HTTP to the container, so Symfony must
  # trust X-Forwarded-Proto (wired in config/packages/framework.yaml) to generate https URLs.
  # Must be a literal IP/CIDR list: the "private_ranges" magic token is only expanded by
  # Symfony's framework-bundle normalizer for a LITERAL yaml value; read via %env(TRUSTED_PROXIES)%
  # it would reach Request::setTrustedProxies() unexpanded and match no IP. 0.0.0.0/0 trusts any
  # upstream — safe because the container's :8000 is only reachable via Traefik on Coolify's
  # internal docker network, never directly.
  base_static_env = {
    TRUSTED_PROXIES = "0.0.0.0/0"
  }
}

module "production" {
  source           = "../../"
  environment_name = "production"
  project_uuid     = coolify_project.shopware.uuid
  server_uuid      = var.secrets_production.server_uuid
  coolify_endpoint = var.coolify_endpoint
  coolify_token    = var.coolify_token

  web_image         = var.production.web_image
  web_image_tag     = var.production.web_image_tag
  web_domain        = var.production.web_domain
  app_env           = var.production.app_env
  app_debug         = var.production.app_debug
  monolog_log_level = var.production.monolog_log_level

  mariadb_conf = var.production.mariadb_conf
  redis_conf   = var.production.redis_conf

  enable_elasticsearch = var.production.enable_elasticsearch
  enable_mailpit       = var.production.enable_mailpit
  enable_backup        = var.production.enable_backup
  backup               = var.production.backup
  backup_image         = var.backup_image
  backup_image_tag     = var.backup_image_tag

  static_env    = merge(local.base_static_env, var.static_env)
  log_host_base = var.log_host_base
  # enable_basic_auth defaults false — production runs the final-prod image (no basic-auth layer)
  rabbitmq_mgmt_port = 25672
  s3                 = var.production.s3
  mailer_dsn         = var.secrets_production.mailer_dsn # production: real SMTP (secret)
  secrets            = var.secrets_production
}

module "staging" {
  source           = "../../"
  environment_name = "staging"
  project_uuid     = coolify_project.shopware.uuid
  server_uuid      = var.secrets_staging.server_uuid
  coolify_endpoint = var.coolify_endpoint
  coolify_token    = var.coolify_token

  web_image         = var.staging.web_image
  web_image_tag     = var.staging.web_image_tag
  web_domain        = var.staging.web_domain
  app_env           = var.staging.app_env
  app_debug         = var.staging.app_debug
  monolog_log_level = var.staging.monolog_log_level
  # mailer_dsn omitted → staging uses the in-project Mailpit (enable_mailpit = true)

  mariadb_conf = var.staging.mariadb_conf
  redis_conf   = var.staging.redis_conf

  enable_elasticsearch = var.staging.enable_elasticsearch
  enable_mailpit       = var.staging.enable_mailpit
  mailpit_domain       = var.staging.mailpit_domain
  enable_backup        = var.staging.enable_backup
  backup               = var.staging.backup
  backup_image         = var.backup_image
  backup_image_tag     = var.backup_image_tag

  static_env         = merge(local.base_static_env, var.static_env)
  log_host_base      = var.log_host_base
  enable_basic_auth  = true # staging runs the final-protected image (nginx basic-auth)
  rabbitmq_mgmt_port = 35672
  s3                 = var.staging.s3
  secrets            = var.secrets_staging

  depends_on = [coolify_environment.staging]
}
