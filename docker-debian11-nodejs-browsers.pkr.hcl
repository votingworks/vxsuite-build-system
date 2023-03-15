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
  default = "2.0.1"
}

source "docker" "debian11-browsers" {
  image = "debian:11.6"
  platform = "linux/amd64"
  commit = true
}

build {
  name = "debian11"
  sources = ["source.docker.debian11-browsers"]

  provisioner "shell" {
    scripts = [
      "scripts/install-base-packages.sh",
      "scripts/install-ansible.sh",
    ]
  }

  provisioner "ansible-local" {
    playbook_files  = [
      "playbooks/install-vxsuite-packages.yaml",
      "playbooks/install-node.yaml",
      "playbooks/install-selenium.yaml"
    ]
  }

  provisioner "shell" {
    script = "scripts/package-cleanup.sh"
  }

  post-processor "docker-tag" {
    repository = "votingworks/cimg-debian11-browsers"
    tags = ["${var.version}"]
  }

}
