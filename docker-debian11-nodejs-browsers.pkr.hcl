packer {
  required_plugins {
    docker = {
      version = ">= 0.0.7"
      source = "github.com/hashicorp/docker"
    }
  }
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
      "playbooks/setup-node.yaml",
      "playbooks/install-selenium.yaml"
    ]
  }

  post-processor "docker-tag" {
    repository = "adammcmanus/cimg-debian11-browsers"
    tags = ["latest"]
  }

}
