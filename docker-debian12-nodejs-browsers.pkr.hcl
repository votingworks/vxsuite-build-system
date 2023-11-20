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
  default = "2.0.4"
}

source "docker" "debian12-browsers" {
  image = "debian:12.2"
  platform = "linux/amd64"
  commit = true
}

build {
  name = "debian12"
  sources = ["source.docker.debian12-browsers"]

  provisioner "shell" {
    scripts = [
      "scripts/install-base-packages.sh",
      "scripts/install-ansible.sh",
    ]
  }

  provisioner "ansible-local" {
    playbook_dir = "./playbooks"
    playbook_files  = [
      "playbooks/install-vxsuite-packages.yaml",
      "playbooks/install-node.yaml",
      "playbooks/install-rust.yaml",
      "playbooks/install-selenium.yaml"
    ]
  }

  provisioner "shell" {
    script = "scripts/package-cleanup.sh"
  }

  post-processor "docker-tag" {
    repository = "votingworks/cimg-debian12-browsers"
    tags = ["${var.version}"]
  }

}
