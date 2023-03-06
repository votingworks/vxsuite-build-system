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
  default = "1.0.0"
}

source "docker" "debian11" {
  image = "debian:11.6"
  platform = "linux/amd64"
  commit = true
}

build {
  name = "debian11"
  sources = ["source.docker.debian11"]

  provisioner "shell" {
    scripts = [
      "scripts/install-base-packages.sh",
      "scripts/install-ansible.sh",
    ]
  }

  provisioner "ansible-local" {
    playbook_files  = [
      "playbooks/install-app-packages.yaml",
      "playbooks/setup-node.yaml"
    ]
  }

  provisioner "shell" {
    script = "scripts/package-cleanup.sh"
  }

  post-processor "docker-tag" {
    repository = "adammcmanus/cimg-debian11"
    tags = ["${var.version}"]
  }

}
