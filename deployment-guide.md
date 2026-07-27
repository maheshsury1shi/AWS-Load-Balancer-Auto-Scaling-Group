# Deployment Guide: Step-by-Step AWS Configuration

## Prerequisites
- AWS Account with billing enabled
- AWS CLI v2 installed and configured
- SSH key pair created and downloaded
- EC2 permissions in IAM

---

## Quick Start (10 Minutes)

If you just want to deploy quickly without understanding every step:

```bash
# 1. Clone this repository
git clone https://github.com/your-username/AWS-Load-Balancer-Auto-Scaling-Group.git
cd AWS-Load-Balancer-Auto-Scaling-Group

# 2. Create VPC and Subnets
bash scripts/01-create-vpc.sh

# 3. Create Security Groups
bash scripts/02-create-security-groups.sh

# 4. Create Launch Template
bash scripts/03-create-launch-template.sh

# 5. Create ALB and Target Group
bash scripts/04-create-alb.sh

# 6. Create Auto Scaling Group
bash scripts/05-create-asg.sh

# 7. Create Scaling Policy
bash scripts/06-create-scaling-policy.sh

# 8. Test Application
open http://web-asg-XXXXX.us-east-1.elb.amazonaws.com
```

---

## Detailed Step-by-Step Deployment

### Step 1: Create VPC and Networking

**AWS Console Method:**

1. Go to VPC Dashboard
2. Click "Create VPC"
3. Configure:
   - Name: `alb-asg-project-vpc`
   - IPv4 CIDR: `10.0.0.0/16`
   - Click "Create VPC"

4. Create Subnets:
   - Subnet 1: Name: `alb-asg-project-subnet-public1-us-east-1a`
     - VPC: `alb-asg-project-vpc`
     - Availability Zone: `us-east-1a`
     - IPv4 CIDR: `10.0.1.0/24`
   - Subnet 2: Name: `alb-asg-project-subnet-public2-us-east-1b`
     - VPC: `alb-asg-project-vpc`
     - Availability Zone: `us-east-1b`
     - IPv4 CIDR: `10.0.2.0/24`

5. Create Internet Gateway:
   - Name: `alb-asg-project-igw`
   - Attach to VPC

6. Create Route Table:
   - Name: `alb-asg-project-rtb-public`
   - Add route: `0.0.0.0/0 → Internet Gateway`
   - Associate with both subnets

**AWS CLI Method:**

```bash
# Get VPC CIDR
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=alb-asg-project-vpc}]' \
  --query 'Vpc.VpcId' \
  --output text)

echo "VPC ID: $VPC_ID"

# Create subnets
SUBNET1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=alb-asg-project-subnet-public1-us-east-1a}]' \
  --query 'Subnet.SubnetId' \
  --output text)

SUBNET2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=alb-asg-project-subnet-public2-us-east-1b}]' \
  --query 'Subnet.SubnetId' \
  --output text)

# Create and attach Internet Gateway
IGW=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=alb-asg-project-igw}]' \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 attach-internet-gateway --internet-gateway-id $IGW --vpc-id $VPC_ID

# Create route table
RTB=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=alb-asg-project-rtb-public}]' \
  --query 'RouteTable.RouteTableId' \
  --output text)

# Add route
aws ec2 create-route --route-table-id $RTB --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW

# Associate subnets
aws ec2 associate-route-table --subnet-id $SUBNET1 --route-table-id $RTB
aws ec2 associate-route-table --subnet-id $SUBNET2 --route-table-id $RTB

# Enable auto-assign public IP
aws ec2 modify-subnet-attribute --subnet-id $SUBNET1 --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id $SUBNET2 --map-public-ip-on-launch

echo "VPC Setup Complete!"
echo "VPC: $VPC_ID"
echo "Subnets: $SUBNET1, $SUBNET2"
```

---

### Step 2: Create Security Groups

```bash
# Create security group for EC2 instances
SG_EC2=$(aws ec2 create-security-group \
  --group-name Web-SG-ASG \
  --description "Allow web traffic for ASG" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

# Add inbound rules
# Allow HTTP
aws ec2 authorize-security-group-ingress \
  --group-id $SG_EC2 \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

# Allow HTTPS
aws ec2 authorize-security-group-ingress \
  --group-id $SG_EC2 \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0

# Allow SSH (replace with your IP)
YOUR_IP="x.x.x.x"  # Replace with your public IP
aws ec2 authorize-security-group-ingress \
  --group-id $SG_EC2 \
  --protocol tcp \
  --port 22 \
  --cidr $YOUR_IP/32

echo "Security Group: $SG_EC2"
```

---

### Step 3: Create Launch Template

```bash
# Download latest Ubuntu AMI
AMI_ID=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
  "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)

echo "Ubuntu AMI: $AMI_ID"

# Create launch template with user data
cat > /tmp/user-data.txt << 'EOF'
#!/bin/bash
apt-get update
apt-get install -y apache2
systemctl start apache2
systemctl enable apache2

# Create HTML page
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
cat > /var/www/html/index.html << HTML
<!DOCTYPE html>
<html>
<head><title>AWS ALB ASG Project</title></head>
<body>
  <h1>Web Server is Running Successfully</h1>
  <p>Instance ID: $INSTANCE_ID</p>
</body>
</html>
HTML
EOF

# Base64 encode user data
USER_DATA=$(base64 -w 0 /tmp/user-data.txt)

# Create launch template
LAUNCH_TEMPLATE=$(aws ec2 create-launch-template \
  --launch-template-name Apache-Template \
  --version-description "v1 - Apache with custom HTML" \
  --launch-template-data "{
    \"ImageId\": \"$AMI_ID\",
    \"InstanceType\": \"t3.micro\",
    \"KeyName\": \"awsEC2\",
    \"SecurityGroupIds\": [\"$SG_EC2\"],
    \"UserData\": \"$USER_DATA\",
    \"Monitoring\": {\"Enabled\": true}
  }" \
  --query 'LaunchTemplate.LaunchTemplateId' \
  --output text)

echo "Launch Template: $LAUNCH_TEMPLATE"
```

---

### Step 4: Create Application Load Balancer

```bash
# Create ALB
ALB=$(aws elbv2 create-load-balancer \
  --name web-ASG \
  --subnets $SUBNET1 $SUBNET2 \
  --security-groups $SG_EC2 \
  --scheme internet-facing \
  --tags Key=Name,Value=web-ASG Key=Environment,Value=Production \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

echo "ALB: $ALB"

# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "ALB DNS: $ALB_DNS"

# Create Target Group
TARGET_GROUP=$(aws elbv2 create-target-group \
  --name Web-TG \
  --protocol HTTP \
  --port 80 \
  --vpc-id $VPC_ID \
  --health-check-enabled \
  --health-check-protocol HTTP \
  --health-check-path / \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2 \
  --matcher HttpCode=200-299 \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

echo "Target Group: $TARGET_GROUP"

# Create Listener
LISTENER=$(aws elbv2 create-listener \
  --load-balancer-arn $ALB \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TARGET_GROUP \
  --query 'Listeners[0].ListenerArn' \
  --output text)

echo "Listener: $LISTENER"
```

---

### Step 5: Create Auto Scaling Group

```bash
# Create Auto Scaling Group
ASG=$(aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name Apache-ASG \
  --launch-template LaunchTemplateName=Apache-Template,Version='$Latest' \
  --min-size 2 \
  --max-size 4 \
  --desired-capacity 2 \
  --default-cooldown 300 \
  --health-check-type ELB \
  --health-check-grace-period 300 \
  --vpc-zone-identifier "$SUBNET1,$SUBNET2" \
  --target-group-arns $TARGET_GROUP \
  --tags "Key=Name,Value=Apache-Instance,PropagateAtLaunch=true" \
         "Key=Environment,Value=Production,PropagateAtLaunch=true")

echo "Auto Scaling Group created: Apache-ASG"

# Verify ASG
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names Apache-ASG
```

---

### Step 6: Create Scaling Policy

```bash
# Create Target Tracking Scaling Policy
POLICY=$(aws autoscaling put-scaling-policy \
  --auto-scaling-group-name Apache-ASG \
  --policy-name CPU-Target-Tracking \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "TargetValue": 50.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "ScaleOutCooldown": 60,
    "ScaleInCooldown": 300
  }' \
  --query 'PolicyARN' \
  --output text)

echo "Scaling Policy: $POLICY"
```

---

### Step 7: Verify Deployment

```bash
# Check ALB
echo "Checking ALB..."
aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB \
  --query 'LoadBalancers[0].[LoadBalancerName,State.Code,DNSName]'

# Check Target Group
echo "Checking Target Group Health..."
aws elbv2 describe-target-health \
  --target-group-arn $TARGET_GROUP

# Check ASG
echo "Checking ASG..."
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names Apache-ASG \
  --query 'AutoScalingGroups[0].[DesiredCapacity,MinSize,MaxSize,Instances]'

# Wait for instances to become healthy (2-3 minutes)
echo "Waiting for instances to become healthy..."
while true; do
  HEALTHY=$(aws elbv2 describe-target-health \
    --target-group-arn $TARGET_GROUP \
    --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`] | length(@)' \
    --output text)
  
  if [ "$HEALTHY" == "2" ]; then
    echo "✅ All instances healthy!"
    break
  else
    echo "Healthy: $HEALTHY/2 (waiting...)"
    sleep 10
  fi
done

# Test application
echo "Testing application..."
curl -v http://$ALB_DNS/
```

---

### Step 8: Test Auto Scaling

**Generate Load:**

```bash
# SSH to one instance
INSTANCE=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=Apache-Instance" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

ssh -i awsEC2.pem ubuntu@10.0.1.5

# Install Apache Bench
sudo apt-get install -y apache2-utils

# Generate load (from your laptop, NOT instance)
ab -n 100000 -c 1000 http://$ALB_DNS/

# Monitor scaling in another terminal
watch -n 5 'aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names Apache-ASG --query "AutoScalingGroups[0].[DesiredCapacity,Instances[].InstanceId]"'
```

---

### Step 9: Test Fault Tolerance

```bash
# Get instance IDs
INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=Apache-Instance" \
            "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

echo "Current instances: $INSTANCES"

# Terminate one instance
INSTANCE_TO_KILL=$(echo $INSTANCES | awk '{print $1}')
echo "Terminating: $INSTANCE_TO_KILL"

aws ec2 terminate-instances --instance-ids $INSTANCE_TO_KILL

# Monitor replacement
watch -n 5 'aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names Apache-ASG --query "AutoScalingGroups[0].Instances[].[InstanceId,LifecycleState]"'

# Test application (should still work!)
curl -v http://$ALB_DNS/
```

---

### Step 10: Cleanup (Save Money!)

When you're done testing:

```bash
# Delete Auto Scaling Group
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name Apache-ASG \
  --force-delete

# Delete ALB
aws elbv2 delete-load-balancer --load-balancer-arn $ALB

# Delete Target Group
aws elbv2 delete-target-group --target-group-arn $TARGET_GROUP

# Delete Launch Template
aws ec2 delete-launch-template --launch-template-id $LAUNCH_TEMPLATE

# Delete VPC (deletes subnets, security groups, etc.)
aws ec2 delete-vpc --vpc-id $VPC_ID

echo "✅ All resources deleted!"
```

---

## Troubleshooting Deployment

### Instances not becoming healthy

```bash
# Check target group health
aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP

# If unhealthy, check instance
ssh -i awsEC2.pem ubuntu@<INSTANCE_IP>
sudo systemctl status apache2
sudo tail -f /var/log/apache2/error.log
```

### ALB not responding

```bash
# Check ALB state
aws elbv2 describe-load-balancers --load-balancer-arns $ALB

# Check if DNS resolves
nslookup $ALB_DNS
```

### Auto Scaling not working

```bash
# Check scaling policy
aws autoscaling describe-policies \
  --auto-scaling-group-name Apache-ASG \
  --policy-names CPU-Target-Tracking

# Check scaling activities
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name Apache-ASG \
  --max-records 5
```

---

**Next Steps:**
- Read [architecture.md](./architecture.md) to understand the design
- Review [interview-questions.md](./interview-questions.md) for technical depth
- Check [troubleshooting.md](./troubleshooting.md) for common issues

---

**Last Updated:** July 27, 2026
