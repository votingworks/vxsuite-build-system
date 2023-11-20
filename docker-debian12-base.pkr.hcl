packer {
  required_plugins {
    docker = {
      version = ">= 0.0.7"
      source = "github.com/hashicorp/docker"
    }
  }
}

variable "version" {
  type = string
  default = "12.2.0"
}

source "docker" "debian12" {
  image = "debian:12.2"
  platform = "linux/amd64"
  commit = true
}

build {
  name = "debian12"
  sources = ["source.docker.debian12"]

  provisioner "shell" {
    scripts = [
      "scripts/install-base-packages.sh",
      "scripts/install-ansible.sh",
    ]
  }

  post-processor "docker-tag" {
    repository = "votingworks/cimg-debian12"
    tags = ["${var.version}"]
  }

}
