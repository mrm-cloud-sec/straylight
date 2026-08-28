# Ansible Configuration

Ansible playbooks for server configuration after Terraform deployment.

## Quick Start

```bash
uv run --locked ansible-playbook site.yml -i aws_ec2.yml
```

## Playbook Execution Order

`site.yml` orchestrates playbooks in the correct order:
1. **base-hardening.yml** — must run first (handles apt updates with retries for NAT timing)
2. **vpn-wireguard.yml** — WireGuard VPN setup
3. **redirector-apache.yml** — Apache redirector with SSL
4. **c2-sliver.yml** — Sliver C2 provisioning
5. **attack-server.yml** — Penetration testing tools
6. **efs-mount.yml** — Shared EFS storage

## Server Types

- **base-hardening.yml**: Security baseline for all servers
- **vpn-wireguard.yml**: WireGuard VPN with operator configs uploaded to S3
- **redirector-apache.yml**: Apache traffic redirector with SSL termination
- **c2-sliver.yml**: Sliver C2 — downloads binary, unpacks assets, starts daemon, drops operator cert to S3
- **attack-server.yml**: Penetration testing tools
- **efs-mount.yml**: Shared EFS storage

## Configuration

### Group Variables

- `all.yml`: Common settings (SSM connection, packages, AWS region)
- `vpn_servers.yml`: WireGuard configuration
- `redirector_servers.yml`: Apache modules, SSL paths, proxy ports
- `c2_servers.yml`: Sliver ports, install path
- `attack_servers.yml`: Tool packages

### Key Variables

- `operation_name`: Set by `deployer.py` via `OPERATION_NAME` env var
- `aws_region`: From `AWS_DEFAULT_REGION` env var
- `c2_private_ip`: Passed from Terraform outputs via `deployer.py`

### Connection

All servers use **AWS SSM** (no SSH keys required):
- `ansible_connection: aws_ssm`
- `ansible_aws_ssm_bucket_name`: S3 bucket for SSM file transfers

### Dynamic Inventory

`aws_ec2.yml` discovers instances by `tag:Operation == $OPERATION_NAME`.
Groups: `c2_servers`, `redirector_servers`, `vpn_servers`, `attack_servers`.

## VPN Operator Configs

WireGuard generates 5 operator configs and uploads to S3:
```bash
aws s3 cp s3://{bucket}/wireguard/operator-configs-{operation}.tar.gz .
tar xzf operator-configs-{operation}.tar.gz
```

## Tips

```bash
uv run --locked ansible-playbook site.yml -i aws_ec2.yml --check      # dry run
uv run --locked ansible-playbook site.yml -i aws_ec2.yml --limit redirector_servers
uv run --locked ansible-playbook site.yml -i aws_ec2.yml --syntax-check
```
