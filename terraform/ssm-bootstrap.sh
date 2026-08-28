#!/bin/bash
# SSM Bootstrap Script for EC2 Instances
# Single purpose: Install SSM agent so Ansible can connect

echo "Starting SSM agent bootstrap at $(date)" >> /var/log/ssm-bootstrap.log

# Get instance region for S3 download (IMDSv2-aware with safe fallback)
# Request IMDSv2 token (silently continue on failure)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)
# Try IMDSv2 placement/region first
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region || echo "")
# Fallback to environment variable or a sane default
if [ -z "$REGION" ]; then
    REGION="${AWS_DEFAULT_REGION:-us-east-1}"
fi
echo "Detected region: $REGION" >> /var/log/ssm-bootstrap.log

# Check if SSM agent is already installed
if which amazon-ssm-agent >/dev/null 2>&1; then
    echo "SSM agent already installed" >> /var/log/ssm-bootstrap.log
    systemctl start amazon-ssm-agent 2>/dev/null || true
else
    echo "Installing SSM agent..." >> /var/log/ssm-bootstrap.log
    
    # Download SSM agent from S3 (works via VPC endpoint, no NAT needed)
    cd /tmp
    SSM_URL="https://s3.$REGION.amazonaws.com/amazon-ssm-$REGION/latest/debian_amd64/amazon-ssm-agent.deb"
    
    if wget -O amazon-ssm-agent.deb "$SSM_URL" >> /var/log/ssm-bootstrap.log 2>&1; then
        # Install the package
        dpkg -i amazon-ssm-agent.deb >> /var/log/ssm-bootstrap.log 2>&1
        
        # Start the service
        systemctl enable amazon-ssm-agent >> /var/log/ssm-bootstrap.log 2>&1 || true
        systemctl start amazon-ssm-agent >> /var/log/ssm-bootstrap.log 2>&1 || true
        
        echo "SSM agent installed and started" >> /var/log/ssm-bootstrap.log
    else
        echo "ERROR: Failed to download SSM agent from $SSM_URL" >> /var/log/ssm-bootstrap.log
    fi
    
    rm -f amazon-ssm-agent.deb
fi

echo "SSM agent bootstrap completed at $(date)" >> /var/log/ssm-bootstrap.log 