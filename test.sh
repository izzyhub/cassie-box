#!/bin/bash

rsync -av --exclude='.git' . izzy@192.168.1.140:~/cassie-box
ssh izzy@192.168.1.140 "cd ~/cassie-box && git add . && nixos-rebuild build --show-trace --flake .#cassie-box --option eval-cache false"
