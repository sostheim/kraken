provider "aws" {
  access_key  = "${var.aws_access_key}"
  secret_key  = "${var.aws_secret_key}"
  shared_credentials_file = "${var.aws_shared_credentials_file}"
  profile     = "${var.aws_profile}"
  region      = "${var.aws_region}"
  max_retries = "${var.max_retries}"
}

resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags {
    Name = "${var.aws_user_prefix}_${var.cluster_name}_vpc"
  }
}

resource "aws_vpc_dhcp_options" "vpc_dhcp" {
  domain_name         = "${var.aws_region}.compute.internal"
  domain_name_servers = ["AmazonProvidedDNS"]

  tags {
    Name = "${var.aws_user_prefix}_${var.cluster_name}_dhcp"
  }
}

resource "aws_vpc_dhcp_options_association" "vpc_dhcp_association" {
  vpc_id          = "${aws_vpc.vpc.id}"
  dhcp_options_id = "${aws_vpc_dhcp_options.vpc_dhcp.id}"
}

resource "aws_internet_gateway" "vpc_gateway" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags {
    Name = "${var.aws_user_prefix}_${var.cluster_name}_gateway"
  }
}

resource "aws_route_table" "vpc_rt" {
  vpc_id = "${aws_vpc.vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.vpc_gateway.id}"
  }

  tags {
    Name = "${var.aws_user_prefix}_${var.cluster_name}_rt"
  }
}

resource "aws_network_acl" "vpc_acl" {
  vpc_id = "${aws_vpc.vpc.id}"

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags {
    Name = "${var.aws_user_prefix}_${var.cluster_name}_acl"
  }
}

resource "aws_key_pair" "keypair" {
  key_name   = "${var.aws_user_prefix}_${var.cluster_name}_key"
  public_key = "${file(var.aws_local_public_key)}"
}

resource "aws_subnet" "vpc_subnet_main" {
  vpc_id                  = "${aws_vpc.vpc.id}"
  cidr_block              = "10.0.0.0/22"
  map_public_ip_on_launch = true

  tags {
    Name = "${var.aws_user_prefix}_${var.cluster_name}_subnet"
  }
}

resource "aws_subnet" "vpc_subnet_asg" {
  availability_zone       = "${element(split(",", lookup(var.aws_region_azs, var.aws_region)), count.index)}"
  vpc_id                  = "${aws_vpc.vpc.id}"
  cidr_block              = "10.0.${(count.index + 1) * 4}.0/22"
  map_public_ip_on_launch = true
  count = "${length(split(",", var.aws_region))}"

  tags {
    Name = "${concat("${var.aws_user_prefix}_${var.cluster_name}_subnet_asg_", count.index)}"
    propagate_at_launch = true
  }
}

resource "aws_route_table_association" "vpc_subnet_main_rt_association" {
  subnet_id      = "${aws_subnet.vpc_subnet_main.id}"
  route_table_id = "${aws_route_table.vpc_rt.id}"
}

resource "aws_route_table_association" "vpc_subnet_asg_rt_association" {
  subnet_id      = "${element(aws_subnet.vpc_subnet_asg.*.id, count.index)}"
  route_table_id = "${aws_route_table.vpc_rt.id}"
  count = "${length(split(",", var.aws_region))}"
}

resource "aws_security_group" "vpc_secgroup" {
  name        = "${var.aws_user_prefix}_${var.cluster_name}_secgroup"
  description = "Security group for ${var.aws_user_prefix}_${var.cluster_name} cluster"
  vpc_id      = "${aws_vpc.vpc.id}"

  # inbound ssh access from the world
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # XXX: all of the ports below are hardcodes / copy-pasta from ansible/roles/kubernetes/defaults/main.yaml

  # inbound kube-apiserver http access from the world
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # inbound kube-apiserver https access from the world
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # inbound cadvisor access from the world
  ingress {
    from_port   = 8094
    to_port     = 8094
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # intra-group kubelet http access
  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "TCP"
    self        = true
  }

  # intra-group kube-scheduler http access
  ingress {
    from_port   = 10251
    to_port     = 10251
    protocol    = "TCP"
    self        = true
  }

  # intra-group kube-controller-manager http access
  ingress {
    from_port   = 10252
    to_port     = 10252
    protocol    = "TCP"
    self        = true
  }

  # intra-group kubelet/healthz http access
  ingress {
    from_port   = 10254
    to_port     = 10254
    protocol    = "TCP"
    self        = true
  }

  # intra-group all ports / all protocols
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    self            = true
  }

  # inbound all ports / all protocols from the vpc's default secgroup
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = ["${aws_vpc.vpc.default_security_group_id}"]
  }

  # kubelet nodeport range
  ingress {
    from_port   = "${var.kraken_port_low}"
    to_port     = "${var.kraken_port_high}"
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # icmp (outbound)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${var.aws_user_prefix}_${var.cluster_name}_secgroup"
  }
}

resource "coreosbox_ami" "latest_ami" {
  channel        = "${var.coreos_update_channel}"
  virtualization = "hvm"
  region         = "${var.aws_region}"
  version        = "${var.coreos_version}"
}

resource "template_file" "etcd_cloudinit" {
  template = "${file("${path.module}/templates/etcd.yaml.tpl")}"

  vars {
    ansible_docker_image      = "${var.ansible_docker_image}"
    ansible_playbook_command  = "${var.ansible_playbook_command}"
    ansible_playbook_file     = "${var.ansible_playbook_file}"
    coreos_reboot_strategy    = "${var.coreos_reboot_strategy}"
    coreos_update_channel     = "${var.coreos_update_channel}"
    format_docker_storage_mnt = "${lookup(var.format_docker_storage_mnt, var.aws_storage_type_etcd)}"
    kraken_branch             = "${var.kraken_repo.branch}"
    kraken_commit             = "${var.kraken_repo.commit_sha}"
    kraken_repo               = "${var.kraken_repo.repo}"
    kubernetes_binaries_uri   = "${var.kubernetes_binaries_uri}"
    logentries_token          = "${var.logentries_token}"
    logentries_url            = "${var.logentries_url}"
    sysdigcloud_access_key    = "${var.sysdigcloud_access_key}"
  }
}

resource "aws_instance" "kubernetes_etcd" {
  depends_on                  = ["aws_internet_gateway.vpc_gateway"]      # explicit dependency
  ami                         = "${coreosbox_ami.latest_ami.box_string}"
  instance_type               = "${var.aws_etcd_type}"
  key_name                    = "${aws_key_pair.keypair.key_name}"
  vpc_security_group_ids      = ["${aws_security_group.vpc_secgroup.id}"]
  subnet_id                   = "${aws_subnet.vpc_subnet_main.id}"
  associate_public_ip_address = true

  ebs_block_device {
    device_name = "${var.aws_storage_path.ebs}"
    volume_size = "${var.aws_volume_size_etcd}"
    volume_type = "${var.aws_volume_type_etcd}"
  }

  ephemeral_block_device {
    device_name  = "${var.aws_storage_path.ephemeral}"
    virtual_name = "ephemeral0"
  }

  user_data = "${template_file.etcd_cloudinit.rendered}"

  tags {
    Name      = "${var.aws_user_prefix}_${var.cluster_name}_etcd"
    ShortName = "etcd"
    ClusterId = "${var.aws_user_prefix}_${var.cluster_name}"
    Role      = "etcd"
  }
}

resource "template_file" "apiserver_cloudinit" {
  template = "${file("${path.module}/templates/apiserver.yaml.tpl")}"

  vars {
    access_port               = "${var.access_port}"
    access_scheme             = "${var.access_scheme}"
    ansible_docker_image      = "${var.ansible_docker_image}"
    ansible_playbook_command  = "${var.ansible_playbook_command}"
    ansible_playbook_file     = "${var.ansible_playbook_file}"
    cluster_name              = "${var.cluster_name}"
    cluster_passwd            = "${var.cluster_passwd}"
    cluster_user              = "${var.aws_user_prefix}"
    coreos_reboot_strategy    = "${var.coreos_reboot_strategy}"
    coreos_update_channel     = "${var.coreos_update_channel}"
    dns_domain                = "${var.dns_domain}"
    dns_ip                    = "${var.dns_ip}"
    dockercfg_base64          = "${var.dockercfg_base64}"
    etcd_private_ip           = "${aws_instance.kubernetes_etcd.private_ip}"
    etcd_public_ip            = "${aws_instance.kubernetes_etcd.public_ip}"
    format_docker_storage_mnt = "${lookup(var.format_docker_storage_mnt, var.aws_storage_type_apiserver)}"
    deployment_mode           = "${var.deployment_mode}"
    hyperkube_image           = "${var.hyperkube_image}"
    interface_name            = "eth0"
    kraken_branch             = "${var.kraken_repo.branch}"
    kraken_commit             = "${var.kraken_repo.commit_sha}"
    kraken_local_dir          = "${var.kraken_local_dir}"
    kraken_repo               = "${var.kraken_repo.repo}"
    kraken_services_branch    = "${var.kraken_services_branch}"
    kraken_services_dirs      = "${var.kraken_services_dirs}"
    kraken_services_repo      = "${var.kraken_services_repo}"
    kubernetes_api_version    = "${var.kubernetes_api_version}"
    kubernetes_binaries_uri   = "${var.kubernetes_binaries_uri}"
    kubernetes_cert_dir       = "${var.kubernetes_cert_dir}"
    logentries_token          = "${var.logentries_token}"
    logentries_url            = "${var.logentries_url}"
    sysdigcloud_access_key    = "${var.sysdigcloud_access_key}"
  }
}

resource "aws_instance" "kubernetes_apiserver" {
  depends_on                  = ["aws_instance.kubernetes_etcd"]
  count                       = "${var.apiserver_count}"
  ami                         = "${coreosbox_ami.latest_ami.box_string}"
  instance_type               = "${var.aws_apiserver_type}"
  key_name                    = "${aws_key_pair.keypair.key_name}"
  vpc_security_group_ids      = ["${aws_security_group.vpc_secgroup.id}"]
  subnet_id                   = "${aws_subnet.vpc_subnet_main.id}"
  associate_public_ip_address = true

  ebs_block_device {
    device_name = "${var.aws_storage_path.ebs}"
    volume_size = "${var.aws_volume_size_apiserver}"
    volume_type = "${var.aws_volume_type_apiserver}"
  }

  ephemeral_block_device {
    device_name  = "${var.aws_storage_path.ephemeral}"
    virtual_name = "ephemeral0"
  }

  user_data = "${template_file.apiserver_cloudinit.rendered}"

  tags {
    Name      = "${var.aws_user_prefix}_${var.cluster_name}_apiserver-${format("%03d", count.index+1)}"
    ShortName = "${format("apiserver-%03d", count.index+1)}"
    ClusterId = "${var.aws_user_prefix}_${var.cluster_name}"
    Role      = "apiserver"
  }
}

resource "template_file" "master_cloudinit" {
  template = "${file("${path.module}/templates/master.yaml.tpl")}"

  vars {
    access_port               = "${var.access_port}"
    access_scheme             = "${var.access_scheme}"
    ansible_docker_image      = "${var.ansible_docker_image}"
    ansible_playbook_command  = "${var.ansible_playbook_command}"
    ansible_playbook_file     = "${var.ansible_playbook_file}"
    apiserver_ip_pool         = "${join(",", concat(formatlist("%v", aws_instance.kubernetes_apiserver.*.private_ip)))}"
    apiserver_nginx_pool      = "${join(" ", concat(formatlist("server %v:443;", aws_instance.kubernetes_apiserver.*.private_ip)))}"
    cluster_name              = "${var.cluster_name}"
    cluster_passwd            = "${var.cluster_passwd}"
    cluster_user              = "${var.aws_user_prefix}"
    command_passwd            = "${var.command_passwd}"
    coreos_reboot_strategy    = "${var.coreos_reboot_strategy}"
    coreos_update_channel     = "${var.coreos_update_channel}"
    dns_domain                = "${var.dns_domain}"
    dns_ip                    = "${var.dns_ip}"
    dockercfg_base64          = "${var.dockercfg_base64}"
    etcd_private_ip           = "${aws_instance.kubernetes_etcd.private_ip}"
    etcd_public_ip            = "${aws_instance.kubernetes_etcd.public_ip}"
    format_docker_storage_mnt = "${lookup(var.format_docker_storage_mnt, var.aws_storage_type_master)}"
    deployment_mode           = "${var.deployment_mode}"
    hyperkube_image           = "${var.hyperkube_image}"
    interface_name            = "eth0"
    kraken_branch             = "${var.kraken_repo.branch}"
    kraken_commit             = "${var.kraken_repo.commit_sha}"
    kraken_local_dir          = "${var.kraken_local_dir}"
    kraken_repo               = "${var.kraken_repo.repo}"
    kraken_services_branch    = "${var.kraken_services_branch}"
    kraken_services_dirs      = "${var.kraken_services_dirs}"
    kraken_services_repo      = "${var.kraken_services_repo}"
    kubernetes_api_version    = "${var.kubernetes_api_version}"
    kubernetes_binaries_uri   = "${var.kubernetes_binaries_uri}"
    kubernetes_cert_dir       = "${var.kubernetes_cert_dir}"
    logentries_token          = "${var.logentries_token}"
    logentries_url            = "${var.logentries_url}"
    master_record             = "${var.access_scheme}://${replace(var.aws_user_prefix,"_","-")}-${replace(var.cluster_name,"_","-")}-master.${var.aws_cluster_domain}:${var.access_port}"
    proxy_record              = "${replace(var.aws_user_prefix,"_","-")}-${replace(var.cluster_name,"_","-")}-proxy.${var.aws_cluster_domain}"
    short_name                = "master"
    sysdigcloud_access_key    = "${var.sysdigcloud_access_key}"
    thirdparty_scheduler      = "${var.thirdparty_scheduler}"
  }
}

resource "aws_instance" "kubernetes_master" {
  depends_on                  = ["aws_instance.kubernetes_apiserver"]
  ami                         = "${coreosbox_ami.latest_ami.box_string}"
  instance_type               = "${var.aws_master_type}"
  key_name                    = "${aws_key_pair.keypair.key_name}"
  vpc_security_group_ids      = ["${aws_security_group.vpc_secgroup.id}"]
  subnet_id                   = "${aws_subnet.vpc_subnet_main.id}"
  associate_public_ip_address = true

  ebs_block_device {
    device_name = "${var.aws_storage_path.ebs}"
    volume_size = "${var.aws_volume_size_master}"
    volume_type = "${var.aws_volume_type_master}"
  }

  ephemeral_block_device {
    device_name  = "${var.aws_storage_path.ephemeral}"
    virtual_name = "ephemeral0"
  }

  user_data = "${template_file.master_cloudinit.rendered}"

  tags {
    Name      = "${var.aws_user_prefix}_${var.cluster_name}_master"
    ShortName = "master"
    ClusterId = "${var.aws_user_prefix}_${var.cluster_name}"
    Role      = "master"
  }
}

resource "template_file" "node_cloudinit_special" {
  template = "${file("${path.module}/templates/node.yaml.tpl")}"
  count    = "${var.special_node_count}"

  vars {
    access_port                = "${var.access_port}"
    access_scheme              = "${var.access_scheme}"
    ansible_docker_image       = "${var.ansible_docker_image}"
    ansible_playbook_command   = "${var.ansible_playbook_command}"
    ansible_playbook_file      = "${var.ansible_playbook_file}"
    cluster_name               = "${var.cluster_name}"
    cluster_name               = "${var.cluster_name}"
    cluster_passwd             = "${var.cluster_passwd}"
    cluster_user               = "${var.aws_user_prefix}"
    coreos_reboot_strategy     = "${var.coreos_reboot_strategy}"
    coreos_update_channel      = "${var.coreos_update_channel}"
    dns_domain                 = "${var.dns_domain}"
    dns_ip                     = "${var.dns_ip}"
    dockercfg_base64           = "${var.dockercfg_base64}"
    etcd_private_ip            = "${aws_instance.kubernetes_etcd.private_ip}"
    etcd_public_ip             = "${aws_instance.kubernetes_etcd.public_ip}"
    format_docker_storage_mnt  = "${lookup(var.format_docker_storage_mnt, element(split(",", var.aws_storage_type_special_docker), count.index))}"
    format_kubelet_storage_mnt = "${lookup(var.format_kubelet_storage_mnt, element(split(",", var.aws_storage_type_special_kubelet), count.index))}"
    deployment_mode            = "${var.deployment_mode}"
    hyperkube_image            = "${var.hyperkube_image}"
    interface_name             = "eth0"
    kraken_branch              = "${var.kraken_repo.branch}"
    kraken_commit              = "${var.kraken_repo.commit_sha}"
    kraken_local_dir           = "${var.kraken_local_dir}"
    kraken_repo                = "${var.kraken_repo.repo}"
    kraken_services_branch     = "${var.kraken_services_branch}"
    kraken_services_dirs       = "${var.kraken_services_dirs}"
    kraken_services_repo       = "${var.kraken_services_repo}"
    kubernetes_api_version     = "${var.kubernetes_api_version}"
    kubernetes_binaries_uri    = "${var.kubernetes_binaries_uri}"
    kubernetes_cert_dir        = "${var.kubernetes_cert_dir}"
    logentries_token           = "${var.logentries_token}"
    logentries_url             = "${var.logentries_url}"
    master_private_ip          = "${aws_instance.kubernetes_master.private_ip}"
    master_public_ip           = "${aws_instance.kubernetes_master.public_ip}"
    master_record              = "${var.access_scheme}://${replace(var.aws_user_prefix,"_","-")}-${replace(var.cluster_name,"_","-")}-master.${var.aws_cluster_domain}:${var.access_port}"
    proxy_record               = "${replace(var.aws_user_prefix,"_","-")}-${replace(var.cluster_name,"_","-")}-proxy.${var.aws_cluster_domain}"
    short_name                 = "node-${format("%03d", count.index+1)}"
    sysdigcloud_access_key     = "${var.sysdigcloud_access_key}"
  }
}

resource "aws_instance" "kubernetes_node_special" {
  count                       = "${var.special_node_count}"
  ami                         = "${coreosbox_ami.latest_ami.box_string}"
  instance_type               = "${element(split(",", var.aws_special_node_type), count.index)}"
  key_name                    = "${aws_key_pair.keypair.key_name}"
  vpc_security_group_ids      = ["${aws_security_group.vpc_secgroup.id}"]
  subnet_id                   = "${aws_subnet.vpc_subnet_main.id}"
  associate_public_ip_address = true

  ebs_block_device {
    device_name = "/dev/sdf"
    volume_size = "${element(split(",", var.aws_volume_size_special_docker), count.index)}"
    volume_type = "${element(split(",", var.aws_volume_type_special_docker), count.index)}"
  }

  ebs_block_device {
    device_name = "/dev/sdg"
    volume_size = "${element(split(",", var.aws_volume_size_special_kubelet), count.index)}"
    volume_type = "${element(split(",", var.aws_volume_type_special_kubelet), count.index)}"
  }

  ephemeral_block_device {
    device_name  = "/dev/sdb"
    virtual_name = "ephemeral0"
  }

  ephemeral_block_device {
    device_name  = "/dev/sdc"
    virtual_name = "ephemeral1"
  }

  user_data = "${element(template_file.node_cloudinit_special.*.rendered, count.index)}"

  tags {
    Name      = "${var.aws_user_prefix}_${var.cluster_name}_node-${format("%03d", count.index+1)}"
    ShortName = "${format("node-%03d", count.index+1)}"
    ClusterId = "${var.aws_user_prefix}_${var.cluster_name}"
    Role      = "special"
  }
}

resource "template_file" "node_cloudinit" {
  template = "${file("${path.module}/templates/node.yaml.tpl")}"

  vars {
    access_port                 = "${var.access_port}"
    access_scheme               = "${var.access_scheme}"
    ansible_docker_image        = "${var.ansible_docker_image}"
    ansible_playbook_command    = "${var.ansible_playbook_command}"
    ansible_playbook_file       = "${var.ansible_playbook_file}"
    cluster_name                = "${var.cluster_name}"
    cluster_name                = "${var.cluster_name}"
    cluster_passwd              = "${var.cluster_passwd}"
    cluster_user                = "${var.aws_user_prefix}"
    coreos_reboot_strategy      = "${var.coreos_reboot_strategy}"
    coreos_update_channel       = "${var.coreos_update_channel}"
    dns_domain                  = "${var.dns_domain}"
    dns_ip                      = "${var.dns_ip}"
    dockercfg_base64            = "${var.dockercfg_base64}"
    etcd_private_ip             = "${aws_instance.kubernetes_etcd.private_ip}"
    etcd_public_ip              = "${aws_instance.kubernetes_etcd.public_ip}"
    format_docker_storage_mnt   = "${lookup(var.format_docker_storage_mnt, var.aws_storage_type_node_docker)}"
    format_kubelet_storage_mnt  = "${lookup(var.format_kubelet_storage_mnt, var.aws_storage_type_node_kubelet)}"
    deployment_mode             = "${var.deployment_mode}"
    hyperkube_image             = "${var.hyperkube_image}"
    interface_name              = "eth0"
    kraken_branch               = "${var.kraken_repo.branch}"
    kraken_commit               = "${var.kraken_repo.commit_sha}"
    kraken_local_dir            = "${var.kraken_local_dir}"
    kraken_repo                 = "${var.kraken_repo.repo}"
    kraken_services_branch      = "${var.kraken_services_branch}"
    kraken_services_dirs        = "${var.kraken_services_dirs}"
    kraken_services_repo        = "${var.kraken_services_repo}"
    kubernetes_api_version      = "${var.kubernetes_api_version}"
    kubernetes_binaries_uri     = "${var.kubernetes_binaries_uri}"
    kubernetes_cert_dir         = "${var.kubernetes_cert_dir}"
    logentries_token            = "${var.logentries_token}"
    logentries_url              = "${var.logentries_url}"
    master_private_ip           = "${aws_instance.kubernetes_master.private_ip}"
    master_public_ip            = "${aws_instance.kubernetes_master.public_ip}"
    master_record               = "${var.access_scheme}://${replace(var.aws_user_prefix,"_","-")}-${replace(var.cluster_name,"_","-")}-master.${var.aws_cluster_domain}:${var.access_port}"
    proxy_record                = "${replace(var.aws_user_prefix,"_","-")}-${replace(var.cluster_name,"_","-")}-proxy.${var.aws_cluster_domain}"
    short_name                  = "autoscaled"
    sysdigcloud_access_key      = "${var.sysdigcloud_access_key}"
  }
}

resource "aws_launch_configuration" "kubernetes_node" {
  name                        = "${var.aws_user_prefix}_${var.cluster_name}_launch_configuration"
  image_id                    = "${coreosbox_ami.latest_ami.box_string}"
  instance_type               = "${var.aws_node_type}"
  key_name                    = "${aws_key_pair.keypair.key_name}"
  security_groups             = ["${aws_security_group.vpc_secgroup.id}"]
  associate_public_ip_address = true
  user_data                   = "${template_file.node_cloudinit.rendered}"

  ebs_block_device {
    device_name = "/dev/sdf"
    volume_size = "${var.aws_volume_size_node_docker}"
    volume_type = "${var.aws_volume_type_node_docker}"
  }

  ebs_block_device {
    device_name = "/dev/sdg"
    volume_size = "${var.aws_volume_size_node_kubelet}"
    volume_type = "${var.aws_volume_type_node_kubelet}"
  }

  ephemeral_block_device {
    device_name  = "/dev/sdb"
    virtual_name = "ephemeral0"
  }

  ephemeral_block_device {
    device_name  = "/dev/sdc"
    virtual_name = "ephemeral1"
  }
}

resource "aws_autoscaling_group" "kubernetes_nodes" {
  name                      = "${var.aws_user_prefix}_${var.cluster_name}_node_asg"
  vpc_zone_identifier       = ["${aws_subnet.vpc_subnet_asg.*.id}"]
  max_size                  = "${var.node_count}"
  min_size                  = "${var.node_count}"
  desired_capacity          = "${var.node_count}"
  force_delete              = true
  wait_for_capacity_timeout = "0"
  health_check_grace_period = "30"
  default_cooldown          = "10"
  vpc_zone_identifier       = ["${aws_subnet.vpc_subnet_main.id}"]
  launch_configuration      = "${aws_launch_configuration.kubernetes_node.name}"
  health_check_type         = "EC2"

  tag {
    key                 = "Name"
    value               = "${var.aws_user_prefix}_${var.cluster_name}_node-autoscaled"
    propagate_at_launch = true
  }

  tag {
    key                 = "ShortName"
    value               = "node-autoscaled"
    propagate_at_launch = true
  }

  tag {
    key                 = "ClusterId"
    value               = "${var.aws_user_prefix}_${var.cluster_name}"
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "node"
    propagate_at_launch = true
  }
}

resource "aws_route53_record" "master_record" {
  zone_id = "${var.aws_zone_id}"
  name    = "${replace(var.aws_user_prefix,"_","-")}-${replace(var.cluster_name,"_","-")}-master.${var.aws_cluster_domain}"
  type    = "A"
  ttl     = "30"
  records = ["${aws_instance.kubernetes_master.public_ip}"]
}

resource "aws_route53_record" "proxy_record" {
  zone_id = "${var.aws_zone_id}"
  name    = "${replace(var.aws_user_prefix,"_","-")}-${replace(var.cluster_name,"_","-")}-proxy.${var.aws_cluster_domain}"
  type    = "A"
  ttl     = "30"
  records = ["${aws_instance.kubernetes_node_special.0.public_ip}"]
}

resource "template_file" "ansible_inventory" {
  template                        = "${file("${path.module}/templates/hosts.tpl")}"

  vars {
    master_public_ip              = "${aws_instance.kubernetes_master.public_ip}"
    etcd_public_ip                = "${aws_instance.kubernetes_etcd.public_ip}"
    apiservers_inventory_info     = "${join("\n", concat(formatlist("%v ansible_ssh_host=%v", aws_instance.kubernetes_apiserver.*.tags.ShortName, aws_instance.kubernetes_apiserver.*.public_ip)))}"
    nodes_inventory_info          = "${join("\n", formatlist("%v ansible_ssh_host=%v", aws_instance.kubernetes_node_special.*.tags.ShortName, aws_instance.kubernetes_node_special.*.public_ip))}"
  }

  provisioner "local-exec" {
    command = "cat << 'EOF' > ${path.module}/rendered/hosts\n${self.rendered}\nEOF"
  }
}

resource "template_file" "local_groupvars" {
  depends_on                      = ["template_file.ansible_inventory"]
  template                        = "${file("${path.module}/templates/local.tpl")}"

  vars {
  }

  provisioner "local-exec" {
    command = "cat << 'EOF' > ${path.module}/rendered/group_vars/local\n${self.rendered}\nEOF"
  }
}

resource "template_file" "all_groupvars" {
  depends_on                      = ["template_file.ansible_inventory"]
  template                        = "${file("${path.module}/templates/all.tpl")}"

  vars {
    ansible_ssh_private_key_file  = "${var.aws_local_private_key}"
    cluster_name                  = "${var.cluster_name}"
    cluster_passwd                = "${var.cluster_passwd}"
    cluster_user                  = "${var.aws_user_prefix}"
    etcd_public_ip                = "${aws_instance.kubernetes_etcd.public_ip}"
    kubernetes_cert_dir           = "${var.kubernetes_cert_dir}"
    master_public_ip              = "${aws_instance.kubernetes_master.public_ip}"
    master_record                 = "https://${replace(var.aws_user_prefix,"_","-")}-${replace(var.cluster_name,"_","-")}-master.${var.aws_cluster_domain}:${var.access_port}"
  }

  provisioner "local-exec" {
    command = "cat << 'EOF' > ${path.module}/rendered/group_vars/all\n${self.rendered}\nEOF"
  }
}

resource "template_file" "cluster_groupvars" {
  depends_on                      = ["template_file.local_groupvars"]
  template                        = "${file("${path.module}/templates/cluster.tpl")}"

  vars {
    access_port                   = "${var.access_port}"
    access_scheme                 = "${var.access_scheme}"
    ansible_ssh_private_key_file  = "${var.aws_local_private_key}"
    apiserver_ip_pool             = "${join(",", concat(formatlist("%v", aws_instance.kubernetes_apiserver.*.private_ip)))}"
    apiserver_nginx_pool          = "${join(" ", concat(formatlist("server %v:443;", aws_instance.kubernetes_apiserver.*.private_ip)))}"
    cluster_name                  = "${var.cluster_name}"
    cluster_passwd                = "${var.cluster_passwd}"
    cluster_user                  = "${var.aws_user_prefix}"
    command_passwd                = "${var.command_passwd}"
    dns_domain                    = "${var.dns_domain}"
    dns_ip                        = "${var.dns_ip}"
    dockercfg_base64              = "${var.dockercfg_base64}"
    etcd_private_ip               = "${aws_instance.kubernetes_etcd.private_ip}"
    etcd_public_ip                = "${aws_instance.kubernetes_etcd.public_ip}"
    deployment_mode               = "${var.deployment_mode}"
    hyperkube_image               = "${var.hyperkube_image}"
    interface_name                = "eth0"
    kraken_services_branch        = "${var.kraken_services_branch}"
    kraken_services_dirs          = "${var.kraken_services_dirs}"
    kraken_services_repo          = "${var.kraken_services_repo}"
    kubernetes_api_version        = "${var.kubernetes_api_version}"
    kubernetes_binaries_uri       = "${var.kubernetes_binaries_uri}"
    kubernetes_cert_dir           = "${var.kubernetes_cert_dir}"
    logentries_token              = "${var.logentries_token}"
    logentries_url                = "${var.logentries_url}"
    master_private_ip             = "${aws_instance.kubernetes_master.private_ip}"
    master_public_ip              = "${aws_instance.kubernetes_master.public_ip}"
    master_record                 = "https://${replace(var.aws_user_prefix,"_","-")}-${replace(var.cluster_name,"_","-")}-master.${var.aws_cluster_domain}:${var.access_port}"
    proxy_record                  = "${replace(var.aws_user_prefix,"_","-")}-${replace(var.cluster_name,"_","-")}-proxy.${var.aws_cluster_domain}"
    sysdigcloud_access_key        = "${var.sysdigcloud_access_key}"
    thirdparty_scheduler          = "${var.thirdparty_scheduler}"
  }

  provisioner "local-exec" {
    command = "cat << 'EOF' > ${path.module}/rendered/group_vars/cluster\n${self.rendered}\nEOF"
  }

  provisioner "local-exec" {
    command = "AWS_DEFAULT_REGION=${var.aws_region} ${path.module}/kraken_asg_helper.sh --kubeconfig ${var.kubeconfig} --cluster ${var.cluster_name} --limit ${var.node_count + var.special_node_count} --name ${aws_autoscaling_group.kubernetes_nodes.name} --output ${path.module}/rendered/hosts --singlewait ${var.asg_wait_single} --totalwaits ${var.asg_wait_total} --offset ${var.special_node_count} --retries ${var.asg_retries}"
  }
}
