#!/usr/bin/env python3
"""
Simple Terraform/Ansible Deployer
A minimal wrapper for infrastructure deployment with credential validation.

Designed for Ubuntu 24.04 LTS with Python 3.12 and Ansible Core 2.20.0.
Uses boto3 for direct AWS API calls and passes variables to Ansible via --extra-vars.
"""

import os
import json
import subprocess
import sys
import time
from typing import Dict, List
import boto3
from botocore.exceptions import ClientError, NoCredentialsError


class SimpleDeployer:

    def __init__(self):
        self.aws_session = None
        self.terraform_vars = {}

    def _print_deployment_summary(self) -> None:
        """Print a compact, well-formatted summary of deployed resources"""
        tv = self.terraform_vars

        def val(key: str, default: str = "N/A") -> str:
            return str(tv.get(key) or default)

        print("\nDeployment — Summary")
        print("")
        print("Core:")
        print(f"  - Operation:  {val('operation_name')}")
        print(f"  - Region:     {val('aws_region')}")
        print(f"  - VPC CIDR:   {val('vpc_cidr')}")
        print(f"  - S3 Bucket:  {val('s3_bucket_name')}")
        print(f"  - EFS:        {val('efs_dns_name')}")

        print("")
        print("Servers:")
        servers = [
            ("VPN", "vpn"),
            ("Redirector", "redirector"),
            ("C2", "c2"),
            ("Attack", "attack"),
        ]

        for display, key in servers:
            pub_ip = val(f"{key}_public_ip")
            priv_ip = val(f"{key}_private_ip")
            inst_id = val(f"{key}_instance_id")
            print(f"  - {display:10s} | public: {pub_ip:15s} | private: {priv_ip:15s} | id: {inst_id}")

        print("")
        print("Access:")
        # Sliver C2 endpoints (reachable via VPN)
        c2_ip = tv.get('c2_private_ip')
        s3_bucket = tv.get('s3_bucket_name', 'unknown')
        op_name = tv.get('operation_name', 'unknown')
        if c2_ip:
            print(f"  - Sliver mTLS    : {c2_ip}:4444  (VPN subnet only)")
            print(f"  - Sliver operator: {c2_ip}:31337 (VPN subnet only)")
            print(f"  - HTTP C2 port   : {c2_ip}:8888  (redirector only)")
        print(f"  - Operator .cfg  : s3://{s3_bucket}/sliver/operator-{op_name}.cfg")
        vpn_ip = tv.get('vpn_public_ip')
        if vpn_ip:
            print(f"  - VPN Public IP:   {vpn_ip}")
        attack_ip = tv.get('attack_public_ip')
        if attack_ip:
            print(f"  - Attack EIP:      {attack_ip}")

        # CloudFront summary (if enabled)
        cloudfront_domains = tv.get('cloudfront_domains', [])
        if cloudfront_domains:
            print("")
            print("CloudFront:")
            print(f"  - C2 Subdomain:    {val('c2_subdomain')}")
            print(f"  - Distributions:   {len(cloudfront_domains)}")
    
    def check_aws_credentials(self) -> bool:
        """Check if AWS credentials are available and valid"""
        print("Checking AWS credentials...")
        
        # Check for required environment variables
        required_vars = ['AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY']
        missing_vars = [var for var in required_vars if not os.getenv(var)]
        
        # Check for session token (required for temporary credentials)
        session_token = os.getenv('AWS_SESSION_TOKEN')
        has_session_token = bool(session_token)
        
        if missing_vars:
            print(f"Missing required environment variables: {', '.join(missing_vars)}")
            print("Please export your AWS credentials:")
            print("  export AWS_ACCESS_KEY_ID=your_access_key")
            print("  export AWS_SECRET_ACCESS_KEY=your_secret_key")
            if has_session_token:
                print("  export AWS_SESSION_TOKEN=your_session_token")
            print("  export AWS_DEFAULT_REGION=your_preferred_region (optional)")
            return False
        
        # Inform about session token status
        if has_session_token:
            print("AWS_SESSION_TOKEN found (using temporary credentials)")
        else:
            print("No AWS_SESSION_TOKEN (using long-term credentials)")
            
        try:
            # Create session and test credentials
            self.aws_session = boto3.Session()
            sts = self.aws_session.client('sts')
            identity = sts.get_caller_identity()
            
            print(f"AWS credentials valid!")
            print(f"   Account: {identity['Account']}")
            print(f"   User/Role: {identity['Arn']}")
            
            return True
            
        except (NoCredentialsError, ClientError) as e:
            print(f"AWS credential validation failed: {e}")
            return False

    def wait_for_ssm_ready(self, instance_ids: List[str], region: str, 
                           max_retries: int = 20, retry_delay: int = 15) -> bool:
        """
        Wait for instances to be registered with SSM and online.
        
        Uses boto3 SSM client directly for faster, more reliable checks than
        going through Ansible's SSM connection plugin.
        
        Args:
            instance_ids: List of EC2 instance IDs to check
            region: AWS region where instances are deployed
            max_retries: Maximum number of retry attempts (default: 20 = ~5 minutes)
            retry_delay: Seconds between retries (default: 15)
            
        Returns:
            True if all instances are SSM-ready, False if timeout
        """
        if not instance_ids:
            print("No instance IDs provided for SSM check")
            return False
        
        # Filter out None/empty values
        instance_ids = [i for i in instance_ids if i]
        if not instance_ids:
            print("No valid instance IDs to check")
            return False
        
        print(f"\nWaiting for {len(instance_ids)} instances to register with SSM...")
        print(f"   Instance IDs: {', '.join(instance_ids)}")
        
        ssm = self.aws_session.client('ssm', region_name=region)
        
        # Initialize missing to all instances (will be updated in loop)
        missing = set(instance_ids)
        
        for attempt in range(max_retries):
            try:
                # Query SSM for instance information
                response = ssm.describe_instance_information(
                    Filters=[{'Key': 'InstanceIds', 'Values': instance_ids}]
                )
                
                # Build set of instances that are online
                online_instances = set()
                instance_status = {}
                
                for info in response.get('InstanceInformationList', []):
                    inst_id = info['InstanceId']
                    ping_status = info.get('PingStatus', 'Unknown')
                    instance_status[inst_id] = ping_status
                    
                    if ping_status == 'Online':
                        online_instances.add(inst_id)
                
                # Check which instances are still missing/offline
                missing = set(instance_ids) - online_instances
                
                if not missing:
                    print(f"✓ All {len(instance_ids)} instances are SSM-ready")
                    return True
                
                # Show progress
                online_count = len(online_instances)
                total_count = len(instance_ids)
                
                # Build status message
                status_parts = []
                for inst_id in instance_ids:
                    if inst_id in online_instances:
                        status_parts.append(f"{inst_id[:10]}..=Online")
                    elif inst_id in instance_status:
                        status_parts.append(f"{inst_id[:10]}..={instance_status[inst_id]}")
                    else:
                        status_parts.append(f"{inst_id[:10]}..=NotRegistered")
                
                print(f"   Attempt {attempt + 1}/{max_retries}: {online_count}/{total_count} online")
                print(f"   Status: {', '.join(status_parts)}")
                
                if attempt < max_retries - 1:
                    print(f"   Retrying in {retry_delay}s...")
                    time.sleep(retry_delay)
                    
            except ClientError as e:
                error_code = e.response.get('Error', {}).get('Code', 'Unknown')
                print(f"   Attempt {attempt + 1}/{max_retries}: SSM API error ({error_code})")
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
        
        # Final failure - show which instances never came online
        print(f"\n✗ Timed out waiting for SSM registration after {max_retries * retry_delay}s")
        print(f"   Missing instances: {', '.join(missing)}")
        print("\nTroubleshooting tips:")
        print("   1. Check that SSM agent is installed and running on instances")
        print("   2. Verify IAM instance profile has SSM permissions")
        print("   3. Ensure instances have network path to SSM endpoints")
        print("   4. Check instance system logs in EC2 console")
        return False

    def get_available_regions(self) -> List[str]:
        """Get list of available AWS regions"""
        try:
            if self.aws_session is None:
                raise ValueError("AWS session not initialized")
            
            ec2 = self.aws_session.client('ec2', region_name='us-east-1')
            regions = ec2.describe_regions()
            return sorted([region['RegionName'] for region in regions['Regions']])
        except Exception as e:
            print(f"Could not fetch regions: {e}")
            # Fallback to common regions
            return [
                'us-east-1', 'us-east-2', 'us-west-1', 'us-west-2',
                'eu-west-1', 'eu-west-2', 'eu-central-1',
                'ap-southeast-1', 'ap-southeast-2', 'ap-northeast-1'
            ]
    
    def select_region(self) -> str:
        """Prompt user to enter an available AWS deployment region."""
        print("\nSelect deployment region:")
        print("   Examples: us-east-1, ap-south-1, eu-west-1")

        regions = self.get_available_regions()
        default_region = os.getenv('AWS_DEFAULT_REGION', 'eu-west-1').strip().lower()

        if default_region not in regions:
            fallback_region = 'eu-west-1' if 'eu-west-1' in regions else regions[0]
            print(f"   AWS_DEFAULT_REGION '{default_region}' is unavailable; using {fallback_region} as the default")
            default_region = fallback_region

        while True:
            try:
                choice = input(f"Enter AWS region (default: {default_region}): ").strip().lower()
                selected_region = choice or default_region

                if selected_region in regions:
                    print(f"Selected AWS region: {selected_region}")
                    return selected_region

                print(f"Region '{selected_region}' is not available to this AWS account")
            except KeyboardInterrupt:
                print(f"Using default region: {default_region}")
                return default_region
    
    def select_operation_name(self) -> str:
        """Prompt user to enter operation name"""
        print("\nEnter operation name:")
        print("   This will be used to identify and tag all resources")
        print("   Examples: iron_sentinel, silent_bastion, northern_lance")
        print("   Format: lowercase letters, numbers, and underscores only")
        
        while True:
            try:
                choice = input("Enter operation name (default: default_op): ").strip()
                
                if not choice:
                    return "default_op"
                
                # Validate format (lowercase, numbers, underscores only - no hyphens)
                import re
                if re.match(r'^[a-z0-9_]+$', choice):
                    print(f"Operation name: {choice}")
                    return choice
                else:
                    print("Operation name must contain only lowercase letters, numbers, and underscores")
                    
            except KeyboardInterrupt:
                print("Using default operation name: default_op")
                return "default_op"

    def select_vpc_octet(self) -> int:
        """Prompt user to select second octet for VPC CIDR (10.x.0.0/16)"""
        print("\nSelect VPC CIDR second octet (10.x.0.0/16):")
        print("   This determines your VPC's IP range")
        print("   Examples: 10.0.0.0/16, 10.1.0.0/16, 10.100.0.0/16")
        
        while True:
            try:
                choice = input("Enter second octet (0-255, default: 0): ").strip()
                
                if not choice:
                    return 0
                    
                octet = int(choice)
                if 0 <= octet <= 255:
                    print(f"Selected VPC CIDR: 10.{octet}.0.0/16")
                    return octet
                else:
                    print("Please enter a number between 0 and 255")
                    
            except (ValueError, KeyboardInterrupt):
                print("Using default octet: 0")
                return 0

    def select_cloudfront_config(self) -> tuple:
        """Prompt user to configure CloudFront — domain and distribution count."""
        print("\nCloudFront Configuration:")
        print("   CloudFront provides domain fronting for C2 traffic.")
        print("   A random subdomain will be created under your Route53 hosted zone.")
        print("   Enter 0 distributions to disable CloudFront entirely.")

        # Prompt for domain
        while True:
            domain = input("\nRoute53 hosted zone domain (e.g. example.com): ").strip().lower()
            if domain and '.' in domain:
                break
            print("Enter a valid domain name.")

        # Prompt for distribution count
        print(f"\nSelect number of CloudFront distributions for {domain}:")
        print("   Each distribution provides a unique *.cloudfront.net domain.")
        print("   More distributions = more fallback if one gets burned.")

        while True:
            try:
                choice = input("Enter count (0-25, default: 10): ").strip()
                if not choice:
                    print(f"Selected: 10 CloudFront distributions pointing to {domain}")
                    return (10, domain)
                count = int(choice)
                if count == 0:
                    print("CloudFront disabled")
                    return (0, "")
                if 1 <= count <= 25:
                    print(f"Selected: {count} CloudFront distribution{'s' if count > 1 else ''} pointing to {domain}")
                    return (count, domain)
                print("Please enter a number between 0 and 25")
            except (ValueError, KeyboardInterrupt):
                print(f"Using default: 10 distributions pointing to {domain}")
                return (10, domain)
    
    def create_terraform_vars(self, region: str, vpc_octet: int, operation_name: str, 
                              cloudfront_count: int, domain_name: str) -> Dict:
        """Create terraform variables"""
        terraform_vars = {
            'aws_region': region,
            'vpc_cidr': f'10.{vpc_octet}.0.0/16',
            'operation_name': operation_name,
            'enable_cloudfront': cloudfront_count > 0,
            'cloudfront_distribution_count': cloudfront_count if cloudfront_count > 0 else 1,
            'domain_name': domain_name if domain_name else "disabled.local"
        }
        
        # Write to terraform.tfvars file in terraform subdirectory
        with open('terraform/terraform.tfvars', 'w') as f:
            for key, value in terraform_vars.items():
                if isinstance(value, bool):
                    f.write(f'{key} = {str(value).lower()}\n')
                elif isinstance(value, int):
                    f.write(f'{key} = {value}\n')
                else:
                    f.write(f'{key} = "{value}"\n')
        
        print(f"\nCreated terraform/terraform.tfvars:")
        for key, value in terraform_vars.items():
            print(f"   {key} = {value}")
            
        return terraform_vars
    
    def run_terraform(self) -> bool:
        """Execute terraform commands"""
        print("\nRunning Terraform...")
        
        commands = [
            ['terraform', 'init'],
            ['terraform', 'plan'],
            ['terraform', 'apply', '-auto-approve']
        ]
        
        # Change to terraform directory
        original_dir = os.getcwd()
        os.chdir('terraform')
        
        try:
            for cmd in commands:
                print(f"\nRunning: {' '.join(cmd)} (in terraform/ directory)")
                try:
                    result = subprocess.run(cmd, check=True, capture_output=False)
                    print(f"Command completed successfully")
                except subprocess.CalledProcessError as e:
                    print(f"Command failed with exit code {e.returncode}")
                    return False
                except FileNotFoundError:
                    print("Terraform not found. Please install terraform first.")
                    print("   Visit: https://www.terraform.io/downloads.html")
                    return False
            
            return True
            
        finally:
            # Always return to original directory
            os.chdir(original_dir)

    def upload_terraform_state(self) -> bool:
        """Upload terraform state file to S3 for team access"""
        print("\nUploading Terraform state to S3...")
        
        try:
            # Get S3 bucket name from terraform output
            result = subprocess.run(
                ['terraform', 'output', '-raw', 's3_bucket_name'],
                cwd='terraform', capture_output=True, text=True, check=True
            )
            bucket_name = result.stdout.strip()
            
            # Get region for the upload
            region = self.terraform_vars.get('aws_region', 'eu-west-1')
            
            # Upload state file to S3
            state_file = 'terraform/terraform.tfstate'
            s3_key = 'terraform/terraform.tfstate'
            
            s3 = self.aws_session.client('s3', region_name=region)
            s3.upload_file(state_file, bucket_name, s3_key)
            
            print(f"   State uploaded to: s3://{bucket_name}/{s3_key}")
            self.terraform_vars['state_s3_path'] = f"s3://{bucket_name}/{s3_key}"
            return True
            
        except subprocess.CalledProcessError as e:
            print(f"   Failed to get bucket name: {e}")
            return False
        except Exception as e:
            print(f"   Failed to upload state: {e}")
            return False

    def install_ansible_collections(self) -> bool:
        """Install required Ansible Galaxy collections"""
        print("\nInstalling Ansible Galaxy collections...")
        
        requirements_file = 'ansible/requirements.yml'
        if not os.path.exists(requirements_file):
            print(f"   Warning: {requirements_file} not found, skipping collection install")
            return True
        
        try:
            result = subprocess.run(
                ['ansible-galaxy', 'collection', 'install', '-r', requirements_file, '--upgrade'],
                capture_output=True, text=True, check=True
            )
            print("   Collections installed successfully")
            return True
        except subprocess.CalledProcessError as e:
            print(f"   Failed to install collections: {e}")
            print(f"   stderr: {e.stderr}")
            return False
        except FileNotFoundError:
            print("   ansible-galaxy not found. Run: uv sync --locked")
            return False

    def run_ansible(self) -> bool:
        """Execute ansible playbooks for server configuration"""
        print("\nConfiguring servers with Ansible...")

        # Install required Ansible collections
        if not self.install_ansible_collections():
            print("   Warning: Collection installation failed, attempting to continue...")

        # Set environment variables from Terraform outputs and user config
        region = self.terraform_vars.get('aws_region', 'eu-west-1')
        operation_name = self.terraform_vars.get('operation_name', 'default-op')

        # Set environment variables for Ansible and AWS SDK
        # These are inherited by subprocess and used by aws_ec2 inventory and aws_ssm connection
        os.environ['AWS_DEFAULT_REGION'] = region
        os.environ['OPERATION_NAME'] = operation_name
        
        # AWS SDK retry configuration for better resilience
        os.environ['AWS_MAX_ATTEMPTS'] = '3'
        os.environ['AWS_RETRY_MODE'] = 'standard'
        
        print(f"Using AWS region: {region}")
        print(f"Operation name: {operation_name}")
        
        # Get infrastructure IPs from Terraform output
        terraform_vars = {}
        try:
            # Get S3 bucket name
            result = subprocess.run(['terraform', 'output', '-raw', 's3_bucket_name'], 
                                  cwd='terraform', capture_output=True, text=True, check=True)
            bucket_name = result.stdout.strip()
            os.environ['TERRAFORM_S3_BUCKET'] = bucket_name
            terraform_vars['s3_bucket_name'] = bucket_name
            print(f"Using S3 bucket: {bucket_name}")
            
            # Get EFS DNS name
            result = subprocess.run(['terraform', 'output', '-raw', 'efs_dns_name'], 
                                  cwd='terraform', capture_output=True, text=True, check=True)
            efs_dns_name = result.stdout.strip()
            os.environ['TERRAFORM_EFS_DNS_NAME'] = efs_dns_name
            terraform_vars['efs_dns_name'] = efs_dns_name
            print(f"Using EFS: {efs_dns_name}")
            
            # Get CloudFront domains (if enabled)
            try:
                result = subprocess.run(['terraform', 'output', '-json', 'cloudfront_domains'], 
                                      cwd='terraform', capture_output=True, text=True, check=True)
                cloudfront_domains = json.loads(result.stdout)
                if cloudfront_domains:
                    terraform_vars['cloudfront_domains'] = cloudfront_domains
                    print(f"CloudFront distributions: {len(cloudfront_domains)} created")
                    
                result = subprocess.run(['terraform', 'output', '-raw', 'c2_subdomain'], 
                                      cwd='terraform', capture_output=True, text=True, check=True)
                c2_subdomain = result.stdout.strip()
                if c2_subdomain:
                    terraform_vars['c2_subdomain'] = c2_subdomain
                    print(f"C2 subdomain: {c2_subdomain}")
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                # CloudFront might be disabled, that's OK
                pass
            
            # Get C2 private IP from Terraform inventory output
            result = subprocess.run(['terraform', 'output', '-json', 'ansible_inventory'], 
                                  cwd='terraform', capture_output=True, text=True, check=True)
            inventory_data = json.loads(result.stdout)
            
            # Extract all server IPs from inventory for Ansible variables
            for group_name, group_data in inventory_data.items():
                for host_name, host_vars in group_data.get('hosts', {}).items():
                    server_type = group_name.replace('_servers', '')  # redirector, c2, vpn, attack
                    
                    # Store both private and public IPs for each server type
                    terraform_vars[f'{server_type}_private_ip'] = host_vars.get('private_ip')
                    # Note: For some hosts (e.g. C2), ansible_host is intentionally set to the
                    # private IP for SSM-based management. Only treat ansible_host as "public"
                    # if it differs from the private IP.
                    ansible_host = host_vars.get('ansible_host')
                    private_ip = host_vars.get('private_ip')
                    terraform_vars[f'{server_type}_public_ip'] = ansible_host if (ansible_host and ansible_host != private_ip) else None
                    terraform_vars[f'{server_type}_instance_id'] = host_vars.get('instance_id')
            
            # Verify we have the essential C2 private IP
            if not terraform_vars.get('c2_private_ip'):
                print("Could not find C2 server private IP in Terraform inventory")
                return False
            
            print(f"Infrastructure ready - C2 server at {terraform_vars['c2_private_ip']}")
            # Persist discovered infra variables for later messages
            self.terraform_vars.update(terraform_vars)
            
        except subprocess.CalledProcessError as e:
            print(f"Could not get Terraform outputs: {e}")
            return False
        except (json.JSONDecodeError, KeyError) as e:
            print(f"Error parsing Terraform inventory: {e}")
            return False

        # Collect all instance IDs for SSM readiness check
        instance_ids = [
            terraform_vars.get('vpn_instance_id'),
            terraform_vars.get('redirector_instance_id'),
            terraform_vars.get('c2_instance_id'),
            terraform_vars.get('attack_instance_id'),
        ]
        
        # Wait for all instances to be SSM-ready using boto3
        if not self.wait_for_ssm_ready(instance_ids, region):
            print("\nFailed to establish SSM connectivity to all instances")
            return False
        
        # Change to project root
        original_dir = os.getcwd()
        
        try:
            # Build extra variables for Ansible
            extra_vars_dict = terraform_vars.copy()

            extra_vars_json = json.dumps(extra_vars_dict)
            
            # Run complete server configuration using site.yml orchestrator
            print("\nRunning complete server configuration...")
            print("   This will configure all servers: VPN, Redirector, C2, and apply hardening")
            site_cmd = ['ansible-playbook', 'site.yml', '--timeout=600', '-v', '--extra-vars', extra_vars_json]

            try:
                # Run from ansible directory where ansible.cfg is located
                subprocess.run(site_cmd, cwd='ansible', check=True, capture_output=False)
                print("Complete server configuration successful")
                print("   VPN configured")
                print("   Redirector configured") 
                print("   C2 configured")
                print("   Updated and hardened")
            except subprocess.CalledProcessError as e:
                print(f"Server configuration failed with exit code {e.returncode}")
                return False
            except FileNotFoundError:
                print("Ansible not found in the project environment.")
                print("   uv sync --locked")
                return False
            
            return True
            
        finally:
            # Always return to original directory
            os.chdir(original_dir)
    
    def run(self):
        """Main deployment workflow"""
        print(r"""


▄█████ ▄▄▄▄▄▄ ▄▄▄▄   ▄▄▄  ▄▄ ▄▄ ▄▄    ▄▄  ▄▄▄▄ ▄▄ ▄▄ ▄▄▄▄▄▄
▀▀▀▄▄▄   ██   ██▄█▄ ██▀██ ▀███▀ ██    ██ ██ ▄▄ ██▄██   ██
█████▀   ██   ██ ██ ██▀██   █   ██▄▄▄ ██ ▀███▀ ██ ██   ██

""".rstrip("\n"))
        print("Straylight Deployer (Tessiaformer + Ansipool)")
        print("")
        
        # Step 1: Check credentials
        if not self.check_aws_credentials():
            sys.exit(1)

        # Step 2: Select region
        region = self.select_region()

        # Step 3: Select operation name
        operation_name = self.select_operation_name()

        # Step 4: Select VPC octet
        vpc_octet = self.select_vpc_octet()

        # Step 5: Configure CloudFront (domain and distribution count)
        cloudfront_count, domain_name = self.select_cloudfront_config()

        # Step 6: Create terraform vars
        self.terraform_vars = self.create_terraform_vars(region, vpc_octet, operation_name, cloudfront_count, domain_name)

        # Step 7: Confirm deployment
        if cloudfront_count > 0:
            cf_status = f"{cloudfront_count} CloudFront distributions → {domain_name}"
        else:
            cf_status = "CloudFront disabled"
        print(f"\nReady to deploy '{operation_name}' operation to {region}")
        print(f"   VPC: 10.{vpc_octet}.0.0/16")
        print(f"   CDN: {cf_status}")
        confirm = input("Proceed with deployment? (y/N): ").strip().lower()
        
        if confirm not in ['y', 'yes']:
            print("Deployment cancelled")
            sys.exit(0)
        
        # Step 8: Run terraform
        terraform_success = self.run_terraform()

        if not terraform_success:
            print("\nTerraform deployment failed!")
            sys.exit(1)

        # Step 9: Upload terraform state to S3 for team access
        state_uploaded = self.upload_terraform_state()
        if not state_uploaded:
            print("   Warning: State upload failed, but continuing with deployment")

        # Step 10: Run ansible for server configuration
        ansible_success = self.run_ansible()
        
        if terraform_success and ansible_success:
            print("\nComplete deployment successful!")
            print(f"\nVPN (Wireguard) configured:")
            print(f"   Operator configs in S3:")
            bucket_name = self.terraform_vars.get('s3_bucket_name', 'unknown')
            print(f"   Bucket: {bucket_name}")
            print(f"   Path: wireguard/operator-configs-{self.terraform_vars.get('operation_name', 'unknown')}.tar.gz")
            print(f"\nRedirector (Apache) configured:")
            print(f"   HTTPS redirector ready for C2 traffic routing")
            print(f"   Logs shipped to CloudWatch: /aws/ec2/{self.terraform_vars.get('operation_name', 'unknown')}/apache")
            print(f"\nSliver C2 configured:")
            c2_ip = self.terraform_vars.get('c2_private_ip') or 'unknown'
            s3_bucket = self.terraform_vars.get('s3_bucket_name', 'unknown')
            op_name = self.terraform_vars.get('operation_name', 'unknown')
            print(f"   Install dir      : /opt/sliver/")
            print(f"   Sliver daemon    : systemd sliver-server (auto-restart)")
            print(f"   HTTP C2 listener : 0.0.0.0:8888  (proxied via redirector)")
            print(f"   mTLS listener    : {c2_ip}:4444   (VPN subnet only)")
            print(f"   Operator port    : {c2_ip}:31337  (VPN subnet only)")
            print(f"   Operator config  : s3://{s3_bucket}/sliver/operator-{op_name}.cfg")
            print(f"\nEFS Shared Storage:")
            print(f"   Mounted at /mnt/shared on C2 and Attack servers")
            print(f"\nSecurity hardening applied:")
            print(f"   SSH hardened, system updated, packages installed")
            
            # CloudFront domains (if enabled)
            cloudfront_domains = self.terraform_vars.get('cloudfront_domains', [])
            if cloudfront_domains:
                print(f"\nCloudFront Domain Fronting ({len(cloudfront_domains)} distributions):")
                print(f"   C2 Subdomain: {self.terraform_vars.get('c2_subdomain', 'N/A')}")
                print(f"   CloudFront Domains:")
                for i, domain in enumerate(cloudfront_domains, 1):
                    print(f"      {i:2d}. https://{domain}/")
                print(f"   Usage: Clients connect to any CloudFront domain above")
                print(f"          Traffic is forwarded to the redirector via the subdomain")
            
            if self.terraform_vars.get('state_s3_path'):
                print(f"\nTerraform State (for team handoff):")
                print(f"   {self.terraform_vars['state_s3_path']}")
            # Final compact summary
            self._print_deployment_summary()
        else:
            print("\nDeployment completed with errors!")
            if not ansible_success:
                print("   Infrastructure deployed but server configuration failed")
                print("   You can run ansible manually: uv run --locked ansible-playbook ansible/site.yml")
            sys.exit(1)


if __name__ == "__main__":
    deployer = SimpleDeployer()
    deployer.run() 
