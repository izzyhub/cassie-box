#!/bin/bash

rsync -av --exclude='.git' . izzy@192.168.1.140:~/cassie-box-orig
ssh izzy@192.168.1.140 "cd ~/cassie-box-orig && git add . && nix flake check"
