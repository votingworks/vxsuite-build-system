packer {
  required_version = ">= 1.7.0, < 2.0.0"

  required_plugins {
    parallels = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/parallels"
    }
  }
}

variable "box_basename" {
  type = string
  default = "debian-11.6-arm64"
}

variable "branch" {
  type = string
  default = "main"
}

variable "build_directory" {
  type = string
  default = "./builds"
}

variable "build_timestamp" {
  type = string
  default = "{{isotime \"20060102150405\"}}"
}

variable "cpus" {
  type = number
  default = 4
}

variable "disk_size" {
  type = number
  default = 65536
}

variable "git_revision" {
  type = string
  default = "__unknown_git_revision__"
}

variable "guest_additions_url" {
  type = string
  default = ""
}

variable "headless" {
  type = string
  default = ""
}

variable "http_directory" {
  type = string
  default = "./"
}

variable "http_proxy" {
  type = string
  default = "{{env `http_proxy`}}"
}

variable "https_proxy" {
  type = string
  default = "{{env `https_proxy`}}"
}

variable "iso_checksum" {
  type = string
  default = "522706a58317915aceb5eef9b777d04ab573982b36670705e2e6d83dd4669e52"
}

variable "iso_name" {
  type = string
  default = "debian-11.6.0-arm64-netinst.iso"
}

variable "memory" {
  type = number
  default = 1024
}

variable "mirror" {
  type = string
  default = "http://cdimage.debian.org/cdimage/release"
}

variable "mirror_directory" {
  type = string
  default = "11.6.0/arm64/iso-cd"
}

variable "name" {
  type = string
  default = "debian-11.6-arm64"
}

variable "no_proxy" {
  type = string
  default = "{{env `no_proxy`}}"
}

variable "preseed_path" {
  type = string
  default = "base-preseed.cfg"
}

variable "provisioner_script" {
  type = string
  default = "vxsuite_config.sh"
}

variable "qemu_display" {
  type = string
  default = "none"
}

variable "shared_path" {
  type = string
  default = "/tmp"
}

variable "enable_shared_path" {
  type = string
  default = "disable"
}

variable "template" {
  type = string
  default = "debian-11.6-arm64"
}

variable "version" {
  type = string
  default = "TIMESTAMP"
}


source "parallels-iso" "debian11" {
  boot_command = [
    "e<wait>",
    "<down><down><down><right><right><right><right><right><right><right><right><right><right>",
    "<right><right><right><right><right><right><right><right><right><right><right><right><right>",
    "<right><right><right><right><right><right><right><right><right><right><right><wait>",
    "install <wait>",
    " preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/${var.preseed_path} <wait>",
    "debian-installer=en_US.UTF-8 <wait>",
    "auto <wait>",
    "locale=en_US.UTF-8 <wait>",
    "kbd-chooser/method=us <wait>",
    "keyboard-configuration/xkb-keymap=us <wait>",
    "netcfg/get_hostname=vx <wait>",
    "netcfg/get_domain=dev <wait>",
    "fb=false <wait>",
    "debconf/frontend=noninteractive <wait>",
    "console-setup/ask_detect=false <wait>",
    "console-keymaps-at/keymap=us <wait>",
    "grub-installer/bootdev=/dev/sda <wait>",
    "<f10><wait>"
  ]

  boot_wait = "5s"
  cpus = "${var.cpus}"
  disk_size = "${var.disk_size}"
  guest_os_type = "debian"
  http_directory = "${var.http_directory}"
  iso_checksum = "${var.iso_checksum}"
  iso_url = "${var.mirror}/${var.mirror_directory}/${var.iso_name}"
  memory = "${var.memory}"
  output_directory = "${var.build_directory}/packer-${var.template}-parallels"
  parallels_tools_flavor = "lin-arm"
  parallels_tools_mode = "upload"
  prlctl_version_file = ".prlctl_version"
  shutdown_command = "echo 'packer' | sudo -S /sbin/shutdown -hP now"
  ssh_password = "packer"
  ssh_port = 22
  ssh_timeout = "15m"
  ssh_username = "packer"
  vm_name = "${var.template}"

  prlctl = [
    ["set", "{{ .Name }}", "--cpus", "2"],
    ["set", "{{ .Name }}", "--memsize", "8192"], 
    ["set", "{{ .Name }}", "--shf-host-add", "Shared", "--path", "${var.shared_path}", "--mode", "rw", "--${var.enable_shared_path}"],
    ["set", "{{ .Name }}", "--shf-host", "on"],
    ["set", "{{ .Name }}", "--sync-host-printers", "off"],
    ["set", "{{ .Name }}", "--sync-ssh-ids", "on"]
  ]
}

build {
  name = "parallels-demo"
  sources = ["source.parallels-iso.debian11"]

  provisioner "file" {
    source = "${var.provisioner_script}"
    destination = "/tmp/${var.provisioner_script}"
  }

  provisioner "file" {
    source = "packer-sudo"
    destination = "/tmp/packer-sudo"
  }

  provisioner "shell" {
    inline = [
      "echo 'packer' | TERM=xterm sudo -S mkdir -p /tmp/parallels",
      "echo 'packer' | TERM=xterm sudo -S mount -o loop /home/packer/prl-tools-lin-arm.iso /tmp/parallels",
      "echo 'packer' | TERM=xterm sudo -S /tmp/parallels/install --install-unattended-with-deps"
    ]
  }

  provisioner "shell" {
    inline = [
      "echo 'packer' | TERM=xterm sudo -S mv /tmp/packer-sudo /etc/sudoers.d/packer",
      "echo 'packer' | TERM=xterm sudo -S chown root.root /etc/sudoers.d/packer",
      "/tmp/${var.provisioner_script} ${var.branch}"
    ]
  }
}



