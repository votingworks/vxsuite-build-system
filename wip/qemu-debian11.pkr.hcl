#-- NOTE: While this packer config will build successfully, it is
#--       incredibly slow. QEMU is likely not a good choice for this
#--
packer {
  required_version = ">= 1.7.0, < 2.0.0"
}

variable "box_basename" {
  type = string
  default = "debian-11.6-amd64"
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
  default = 10240
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
  #default = "522706a58317915aceb5eef9b777d04ab573982b36670705e2e6d83dd4669e52"
  default = "e482910626b30f9a7de9b0cc142c3d4a079fbfa96110083be1d0b473671ce08d"
}

variable "iso_name" {
  type = string
  default = "debian-11.6.0-amd64-netinst.iso"
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
  default = "base-preseed.cfg"
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

variable "template" {
  type = string
  default = "qemu-debian-11.6-amd64"
}

variable "version" {
  type = string
  default = "TIMESTAMP"
}


source "qemu" "debian11-iso" {
  boot_command = [
    "<esc><wait>",
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
    "grub-installer/bootdev=default <wait>",
    "<enter><wait>"
  ]

  boot_wait = "30s"
  cpus = "${var.cpus}"
  disk_image = false
  disk_size = "${var.disk_size}"
  #headless = true
  http_directory = "${var.http_directory}"
  iso_checksum = "${var.iso_checksum}"
  #iso_url = "${var.mirror}/${var.mirror_directory}/${var.iso_name}"
  iso_url = "/Users/amcmanus/Downloads/debian-11.6.0-amd64-netinst.iso"
  memory = "${var.memory}"
  output_directory = "${var.build_directory}/packer-${var.template}-iso"
  shutdown_command = "echo 'packer' | sudo -S /sbin/shutdown -hP now"
  ssh_password = "packer"
  #ssh_port = 22
  ssh_timeout = "60m"
  ssh_username = "packer"
  vm_name = "${var.template}-iso"
  use_default_display = true
  #display = "none"
  #cdrom_interface = "virtio"
  disk_interface = "virtio"
  #cd_files = ["./somedirectory/meta-data", "./somedirectory/user-data"],
  #cd_label = "cidata",
  #net_device = "virtio-net"
  #qemuargs = [ ["-boot", "order=c,menu=on"] ] 
}

build {
  name = "iso"

  sources = ["source.qemu.debian11-iso"]
}


