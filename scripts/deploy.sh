#!/usr/bin/env bash
set -e

# Ensure we're in the repository root
cd "$(dirname "$0")/.."

# Check if deploy-rs is installed
if ! command -v deploy &> /dev/null; then
    echo "deploy-rs not found. Installing..."
    nix profile install github:serokell/deploy-rs
fi

# Deploy to cassie-box
echo "Deploying to cassie-box..."
deploy .#cassie-box

# Check deployment status
if [ $? -eq 0 ]; then
    echo "Deployment successful!"
else
    echo "Deployment failed!"
    exit 1
fi
