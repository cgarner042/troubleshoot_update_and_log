#!/bin/bash

set -x

# Update APT packages
sudo apt update && sudo apt upgrade -y

# Refresh snap packages
sudo snap refresh

# Check if Conda is installed and update
if command -v /home/garner/anaconda3/bin/conda; then
    echo "Updating Conda..."
    /home/garner/anaconda3/bin/conda update conda --yes
    /home/garner/anaconda3/bin/conda update --all --yes
else
    echo "Conda command not found"
fi

# Clean up
sudo apt autoremove -y
sudo apt autoclean

read -p "Press Enter to close..."
