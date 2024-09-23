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
  default = "4.1.0"
}

source "docker" "debian12" {
  image = "votingworks/cimg-debian12:12.2.0"
  platform = "linux/amd64"
  commit = true
}

build {
  name = "debian12"
  sources = ["source.docker.debian12"]

  provisioner "ansible-local" {
    command = ". /.virtualenv/ansible/bin/activate && ANSIBLE_FORCE_COLOR=1 PYTHONUNBUFFERED=1 /.virtualenv/ansible/bin/ansible-playbook"
    playbook_dir = "./playbooks"
    playbook_files  = [
      "playbooks/install-vxsuite-packages.yaml",
      "playbooks/install-node.yaml",
      "playbooks/install-rust.yaml"
    ]
  }

  provisioner "shell" {
    script = "scripts/package-cleanup.sh"
  }

  post-processor "docker-tag" {
    repository = "votingworks/cimg-debian12"
    tags = ["${var.version}"]
  }

}
