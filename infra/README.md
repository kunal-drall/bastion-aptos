# Infrastructure

Infrastructure as Code (IaC) and deployment scripts for Bastion Aptos.

## Structure

- `terraform/` - Terraform configurations for cloud infrastructure
- `scripts/` - Deployment and utility scripts
- `kubernetes/` - Kubernetes manifests (if applicable)

## Usage

### Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### Scripts

```bash
# Deploy to staging
./scripts/deploy-staging.sh

# Deploy to production
./scripts/deploy-production.sh
```

## Requirements

- Terraform >= 1.0
- Cloud provider CLI tools (AWS CLI, gcloud, etc.)
- kubectl (for Kubernetes deployments)
