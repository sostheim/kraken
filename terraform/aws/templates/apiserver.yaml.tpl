#cloud-config

---
write_files:
  - path: /etc/ansible/hosts
    content: |
      [apiserver]
      apiserver ansible_ssh_host=$private_ipv4
  - path: /etc/ansible/group_vars/apiserver
    content: |
      ---
        ansible_connection: ssh
        ansible_python_interpreter: "PATH=/home/core/bin:$PATH python"
        ansible_ssh_private_key_file: /opt/ansible/private_key
        ansible_ssh_user: core
        cluster_name: ${cluster_name}
        kubernetes_basic_auth_user:
          name: ${cluster_user}
          password: ${cluster_passwd}
        dns_domain: ${dns_domain}
        dns_ip: ${dns_ip}
        dockercfg_base64: ${dockercfg_base64}
        etcd_private_ip: ${etcd_private_ip}
        etcd_public_ip: ${etcd_public_ip}
        deployment_mode: ${deployment_mode}
        hyperkube_image: ${hyperkube_image}
        interface_name: ${interface_name}
        kraken_local_dir: ${kraken_local_dir}
        kraken_services_branch: ${kraken_services_branch}
        kraken_services_dirs: ${kraken_services_dirs}
        kraken_services_repo: ${kraken_services_repo}
        kubernetes_api_version: ${kubernetes_api_version}
        kubernetes_binaries_uri: ${kubernetes_binaries_uri}
        kubernetes_cert_dir: ${kubernetes_cert_dir}
        logentries_token: ${logentries_token}
        logentries_url: ${logentries_url}
        access_port: "${access_port}"
        access_scheme: ${access_scheme}
        sysdigcloud_access_key: ${sysdigcloud_access_key}
  - path: /etc/cni/net.d/10-cninet.conf
    content: |
      {
        "name": "cninet",
        "type": "flannel",
        "subnetFile": "/var/run/flannel/subnet.env",
        "delegate": {
          "bridge": "cni0",
          "mtu": 1450,
          "isDefaultGateway": true
        }
      }
coreos:
  etcd2:
    proxy: on
    listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
    advertise-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
    initial-cluster: etcd=http://${etcd_private_ip}:2380
  fleet:
    etcd-servers: http://$private_ipv4:4001
    public-ip: $public_ipv4
    metadata: "role=master"
  flannel:
    etcd-endpoints: http://${etcd_private_ip}:4001
    interface: $private_ipv4
  units:
    - name: format-storage.service
      command: start
      content: |
        [Unit]
        Description=Formats a drive
        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStart=/usr/sbin/wipefs -f ${format_docker_storage_mnt}
        ExecStart=/usr/sbin/mkfs.ext4 -F ${format_docker_storage_mnt}
    - name: docker.service
      drop-ins:
        - name: 50-docker-opts.conf
          content: |
            [Service]
            Environment="DOCKER_OPTS=--log-level=warn"
    - name: var-lib-docker.mount
      command: start
      content: |
        [Unit]
        Description=Mount to /var/lib/docker
        Requires=format-storage.service
        After=format-storage.service
        Before=docker.service
        [Mount]
        What=${format_docker_storage_mnt}
        Where=/var/lib/docker
        Type=ext4
    - name: etcd2.service
      command: start
    - name: setup-network-environment.service
      command: start
      content: |
        [Unit]
        Description=Setup Network Environment
        Requires=network-online.target
        After=network-online.target
        Before=flanneld.service

        [Service]
        ExecStartPre=-/usr/bin/mkdir -p /opt/bin
        ExecStartPre=/usr/bin/wget -N -P /opt/bin https://github.com/kelseyhightower/setup-network-environment/releases/download/v1.0.0/setup-network-environment
        ExecStartPre=/usr/bin/chmod +x /opt/bin/setup-network-environment
        ExecStart=/opt/bin/setup-network-environment
        RemainAfterExit=yes
        Type=oneshot
    - name: flanneld.service
      command: start
      drop-ins:
        - name: 50-network-config.conf
          content: |
            [Unit]
            After=flannelconfig.service
            Before=docker.service

            [Service]
            ExecStartPre=-/usr/bin/etcdctl set /coreos.com/network/config '{"Network":"10.244.0.0/14", "Backend": {"Type": "vxlan"}}'
      content: |
        [Unit]
        Description=Flannel CNI Service
        Documentation=https://github.com/containernetworking/cni/blob/master/Documentation/flannel.md
        Requires=early-docker.service
	After=etcd2.service early-docker.service
        Before=early-docker.target

        [Service]
	# Flannel Service
	Type=notify
	Restart=always
	RestartSec=5
	Environment="TMPDIR=/var/tmp/"
	Environment="FLANNEL_VER=0.5.5"
	Environment="FLANNEL_IMG=quay.io/coreos/flannel"
	Environment="FLANNEL_ENV_FILE=/run/flannel/options.env"
	ExecStartPre=/usr/bin/mkdir -p /run/flannel
	ExecStartPre=-/usr/bin/touch /run/flannel/options.env

	# CNI options
	ExecStartPre=-/usr/bin/mkdir -p /opt/cni
        ExecStartPre=/usr/bin/wget -N -P /opt/cni https://storage.googleapis.com/kubernetes-release/network-plugins/cni-8a936732094c0941e1543ef5d292a1f4fffa1ac5.tar.gz
        ExecStartPre=/usr/bin/tar -xzf /opt/cni/cni-8a936732094c0941e1543ef5d292a1f4fffa1ac5.tar.gz -C /opt/cni/
        ExecStartPre=/usr/bin/rm /opt/cni/cni-8a936732094c0941e1543ef5d292a1f4fffa1ac5.tar.gz

	ExecStart=/usr/libexec/sdnotify-proxy /run/flannel/sd.sock \
	  /usr/bin/docker run --net=host --privileged=true --rm \
	    --voluame=/run/flannel:/run/flannel \
	    --env=NOTIFY_SOCKET=/run/flannel/sd.sock \
	    --env-file=/run/flannel/options.env \
	    --volume=/usr/share/ca-certificates:/etc/ssl/certs:ro \
	      quay.io/coreos/flannel:0.5.5 /opt/bin/flanneld --ip-masq=true

	# Update docker options
	ExecStartPost=/usr/bin/docker run --net=host --rm --volume=/run:/run \
	  quay.io/coreos/flannel:0.5.5 \
	  /opt/bin/mk-docker-opts.sh -d /run/flannel_docker_opts.env -i

	[Install]
	WantedBy=multi-user.target
    - name: fleet.service
      command: start
    - name: systemd-journal-gatewayd.socket
      command: start
      enable: yes
      content: |
        [Unit]
        Description=Journal Gateway Service Socket
        [Socket]
        ListenStream=/var/run/journald.sock
        Service=systemd-journal-gatewayd.service
        [Install]
        WantedBy=sockets.target
    - name: generate-ansible-keys.service
      command: start
      content: |
        [Unit]
        Description=Generates SSH keys for ansible container
        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStartPre=-/usr/bin/rm /home/core/.ssh/ansible_rsa*
        ExecStartPre=/usr/bin/bash -c "ssh-keygen -f /home/core/.ssh/ansible_rsa -N ''"
        ExecStart=/usr/bin/bash -c "cat /home/core/.ssh/ansible_rsa.pub >> /home/core/.ssh/authorized_keys"
    - name: kraken-git-pull.service
      command: start
      content: |
        [Unit]
        Requires=generate-ansible-keys.service
        After=generate-ansible-keys.service
        Description=Fetches kraken repo
        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStartPre=/usr/bin/rm -rf /opt/kraken
        ExecStart=/usr/bin/git clone -b ${kraken_branch} ${kraken_repo} /opt/kraken
    - name: write-sha-file.service
      command: start
      content: |
        [Unit]
        Requires=kraken-git-pull.service
        After=kraken-git-pull.service
        Description=writes optional sha to a file
        [Service]
        Type=oneshot
        ExecStart=/usr/bin/bash -c '/usr/bin/echo "${kraken_commit}" > /opt/kraken/commit.sha'
    - name: fetch-kraken-commit.service
      command: start
      content: |
        [Unit]
        Requires=write-sha-file.service
        After=write-sha-file.service
        Description=fetches an optional commit
        ConditionFileNotEmpty=/opt/kraken/commit.sha
        [Service]
        Type=oneshot
        RemainAfterExit=yes
        WorkingDirectory=/opt/kraken
        ExecStartPre=/usr/bin/git fetch ${kraken_repo} +refs/pull/*:refs/remotes/origin/pr/*
        ExecStart=/usr/bin/git checkout -f ${kraken_commit}
    - name: ansible-in-docker.service
      command: start
      content: |
        [Unit]
        Requires=write-sha-file.service
        After=fetch-kraken-commit.service
        Description=Runs a prebaked ansible container
        [Service]
        Type=simple
        Restart=on-failure
        RestartSec=5
        ExecStartPre=-/usr/bin/docker rm -f ansible-docker
        ExecStart=/usr/bin/docker run --name ansible-docker -v /etc/ansible:/etc/ansible -v /opt/kraken:/opt/kraken -v /home/core/.ssh/ansible_rsa:/opt/ansible/private_key -v /var/run:/ansible -v /srv:/srv -e ANSIBLE_HOST_KEY_CHECKING=False ${ansible_docker_image} /sbin/my_init --skip-startup-files --skip-runit -- ${ansible_playbook_command} ${ansible_playbook_file}
  update:
    group: ${coreos_update_channel}
    reboot-strategy: ${coreos_reboot_strategy}
