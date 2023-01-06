packer {
  required_version = ">= 1.7.0, < 2.0.0"

  required_plugins {
    parallels = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/parallels"
    }
  }
}

source "parallels-pvm" "debian11-6" {

  output_directory = "./build"
  parallels_tools_flavor = "mac"
  prlctl_version_file = ".prlctl_version"
  ssh_port = 22
  ssh_username = "vx"
  ssh_password = "insecure"
  ssh_timeout = "10m"
  shutdown_command = "echo 'insecure' | sudo -S shutdown -P now"
  source_path = "/Users/amcmanus/work/debian-11.6.0-arm64.pvm2.pvm"
  vm_name = "debian-11-6-packer"
}

build {
  name = "parallels-pvm-demo"
  sources = ["source.parallels-pvm.debian11-6"]
}
