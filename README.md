# SecScan Minimal Stack (HTTP toggle + NAT strategy)

## Quick start (CloudShell)
```
unzip secscan-stack-v5.zip -d secscan
cd secscan

# set your dev values
nano envs/dev.tfvars

terraform init
terraform plan -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
```

Open the `alb_dns_name` output in your browser with `http://`.

## Notable toggles
- `use_https = false` to skip ACM/domain
- `health_check_path = "/"` for nginx
- `nat_strategy = "single"` for low-cost sandbox
