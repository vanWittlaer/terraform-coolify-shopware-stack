terraform {
  required_providers {
    coolify = {
      source = "coolify-terraform/coolify"
    }
    # Used only to run a local-exec that flips the rabbitmq service's
    # connect_to_docker_network flag via the Coolify API (the coolify provider can't
    # round-trip that attribute — see services.tf / FINDINGS).
    null = {
      source = "hashicorp/null"
    }
    # DB credentials are module-generated (databases.tf) so every DSN can be built
    # without reading sensitive fields back from the Coolify API — see FINDINGS
    # ("read:sensitive").
    random = {
      source = "hashicorp/random"
    }
  }
}
