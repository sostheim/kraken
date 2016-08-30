#!/bin/bash
docker exec $(docker ps | grep dnsmasq | awk '{print $1}') cat /var/lib/misc/dnsmasq.leases
