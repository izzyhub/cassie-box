#!/bin/bash

rsync -av --exclude='.git' . izzy@192.168.1.140:~/cassie-box-orig
echo "=== Check homepage service status ==="
ssh izzy@192.168.1.140 'systemctl status podman-homepage.service --no-pager'
echo "=== Check homepage logs ==="
ssh izzy@192.168.1.140 'journalctl -u podman-homepage.service --no-pager -n 5'
echo "=== Test if homepage container is running ==="
ssh izzy@192.168.1.140 'podman ps | grep homepage || echo "No homepage container running"'
