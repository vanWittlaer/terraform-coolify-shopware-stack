# Host bind mounts for the WEB app: var/log (monolog's rotating_file handler) and, for envs whose
# FQDN is in the image's host-gated basic-auth map ($auth_host_gate, typically staging), the
# directory holding .htpasswd (the image's nginx/basic-auth.inc reads /var/www/auth/.htpasswd). Both are Coolify "directory mounts" (`type: file`, `is_directory: true`,
# `fs_path` = absolute host dir) — the same thing the UI's "Directory Mount" creates.
#
# NOT coolify_storage: the provider's resource only knows `host_path`, which Coolify >= 4.6
# rejects with HTTP 422 ("This field is not allowed" — a request allow-list, not a host check),
# and it has no `type`/`fs_path`/`is_directory`, so a bind mount can't be expressed with it.
# We call the storages API directly instead, like the connect_to_docker_network null_resources.
#
# API facts (verified against Coolify 4.6.0):
#  - POST /api/v1/applications/{uuid}/storages  body {type, fs_path, is_directory, mount_path}
#  - `name` is rejected for type=file (422); `host_path` and `resource_uuid` are never accepted.
#  - fs_path is kept verbatim as the host source.
#
# Idempotent: a GET first, skip when a mount with that mount_path already exists (so adopting an
# environment whose mounts were added by hand in the UI is a no-op, never a duplicate).
#
# No destroy provisioner on purpose: destroy-time provisioners can't see var.*, and passing the
# token through `triggers` would write it to state in plaintext. Coolify deletes an application's
# storages together with the application, so tearing the env down needs nothing extra. Flipping
# log_host_base to "" later leaves an existing mount in place — remove it in the UI.
#
# The host directories are NOT created here (the API can't): create them out-of-band and
# `chown 82:82` (README: post-bootstrap checklist). A new mount takes effect on the next deploy
# of the web app (redeploy once after the first apply).
locals {
  # Empty host path => mount disabled (log_host_base == "", or basic auth off).
  web_bind_mounts = {
    for k, m in {
      var_log = {
        fs_path    = local.log_host_path
        mount_path = "/var/www/html/var/log"
      }
      basic_auth = {
        fs_path    = local.basic_auth_host_path
        mount_path = "/var/www/auth"
      }
    } : k => m if m.fs_path != ""
  }

  bind_mount_cmd = <<-EOT
    set -eu
    existing="$(curl -fsS -H "Authorization: Bearer $TOK" "$EP/api/v1/applications/$UUID/storages" | tr -d '\\')"
    if printf '%s' "$existing" | grep -F "\"mount_path\":\"$MOUNT_PATH\"" >/dev/null; then
      echo "bind mount $MOUNT_PATH already present on $UUID — skipping"
      exit 0
    fi
    curl -fsS -X POST -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
      -d "{\"type\":\"file\",\"is_directory\":true,\"fs_path\":\"$FS_PATH\",\"mount_path\":\"$MOUNT_PATH\"}" \
      "$EP/api/v1/applications/$UUID/storages" >/dev/null
    echo "created bind mount $FS_PATH -> $MOUNT_PATH on $UUID"
  EOT
}

resource "null_resource" "web_bind_mount" {
  for_each = local.web_bind_mounts

  triggers = {
    application_uuid = coolify_application_docker_image.web.uuid
    fs_path          = each.value.fs_path
    mount_path       = each.value.mount_path
  }

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    environment = {
      EP         = var.coolify_endpoint
      TOK        = var.coolify_token
      UUID       = coolify_application_docker_image.web.uuid
      FS_PATH    = each.value.fs_path
      MOUNT_PATH = each.value.mount_path
    }
    command = local.bind_mount_cmd
  }
}
