packer {
  required_version = ">= 1.7.0, < 2.0.0"

  required_plugins {
    parallels = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/parallels"
    }
  }
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
  default = "e482910626b30f9a7de9b0cc142c3d4a079fbfa96110083be1d0b473671ce08d"
}

variable "iso_name" {
  type = string
  default = "debian-11.6.0-amd64-netinst.iso"
}

variable "local_user" {
  type = string
  default = "vx"
}

variable "memory" {
  type = number
  default = 1024
}

variable "mirror" {
  type = string
  default = "http://cdimage.debian.org/cdimage/archive"
}

variable "mirror_directory" {
  type = string
  default = "11.6.0/amd64/iso-cd"
}

variable "name" {
  type = string
  default = "debian-11.6-amd64"
}

variable "no_proxy" {
  type = string
  default = "{{env `no_proxy`}}"
}

variable "preseed_path" {
  type = string
  default = "preseeds/base-preseed.cfg"
}

variable "qemu_display" {
  type = string
  default = "none"
}

variable "repo" {
  type = string
  default = "vxsuite"
}

variable "shared_path" {
  type = string
  default = "/tmp"
}

variable "enable_shared_path" {
  type = string
  default = "disable"
}

variable "version" {
  type = string
  default = "TIMESTAMP"
}

variable "vm_name" {
  type = string
  default = "debian-11.6-amd64"
}

variable "vm_cpus" {
  type = number
  default = "4"
}

variable "vm_memory" {
  type = number
  default = "16384"
}

source "parallels-iso" "debian11-intel" {
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
  output_directory = "${var.build_directory}/${var.vm_name}"
  parallels_tools_flavor = "lin"
  parallels_tools_mode = "upload"
  prlctl_version_file = ".prlctl_version"
  shutdown_command = "sudo su root -c \"userdel -rf packer; rm /etc/sudoers.d/packer; /sbin/shutdown -hP now\""
  ssh_password = "packer"
  ssh_port = 22
  ssh_timeout = "30m"
  ssh_username = "packer"
  vm_name = "${var.vm_name}"

  prlctl = [
    ["set", "{{ .Name }}", "--cpus", "${var.vm_cpus}"],
    ["set", "{{ .Name }}", "--memsize", "${var.vm_memory}"], 
    ["set", "{{ .Name }}", "--shf-host-add", "Shared", "--path", "${var.shared_path}", "--mode", "rw", "--${var.enable_shared_path}"],
    ["set", "{{ .Name }}", "--shf-host", "on"],
    ["set", "{{ .Name }}", "--sync-host-printers", "off"],
    ["set", "{{ .Name }}", "--sync-ssh-ids", "on"]
  ]
}

build {
  name = "parallels-demo"
  sources = ["source.parallels-iso.debian11-intel"]

  provisioner "file" {
    source = "scripts/packer-sudo"
    destination = "/tmp/packer-sudo"
  }

  provisioner "shell" {
    inline = [
      "echo 'packer' | TERM=xterm sudo -S mv /tmp/packer-sudo /etc/sudoers.d/packer",
      "echo 'packer' | TERM=xterm sudo -S chown root.root /etc/sudoers.d/packer",
    ]
  }

  provisioner "shell" {
    inline = [
      "TERM=xterm sudo -S mkdir -p /tmp/parallels",
      "TERM=xterm sudo -S mount -o loop /home/packer/prl-tools-lin.iso /tmp/parallels",
      "TERM=xterm sudo -S /tmp/parallels/install --install-unattended-with-deps"
    ]
  }

  provisioner "shell" {
    scripts = [ 
      "scripts/install-base-packages.sh",
      "scripts/install-ansible.sh"
    ]
  }

  provisioner "ansible-local" {
    playbook_dir = "./playbooks"
    playbook_files  = [
      "playbooks/create_local_user.yaml",
      "playbooks/clone_repos.yaml",
      "playbooks/install-vxsuite-packages.yaml",
      "playbooks/install-node.yaml",
      "playbooks/install-rust.yaml"
    ]
    extra_arguments = ["--extra-vars", "local_user=${var.local_user}"]
  }

  provisioner "shell" {
    inline = [
      "echo \"VM IP: `hostname -I | cut -d' ' -f1`\""
    ]
  }

  #-- Need to think through this a bit more, but also need feedback
  post-processor "shell-local" {
    inline = [
      "mv ${var.build_directory}/${var.vm_name}/${var.vm_name}.pvm ~/Parallels/",
      "rmdir ${var.build_directory}/${var.vm_name}"
    ]
  }
}



