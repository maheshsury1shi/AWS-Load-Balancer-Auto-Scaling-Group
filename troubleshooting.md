# Troubleshooting Guide: ALB, Target Groups, EC2, and Auto Scaling

## Table of Contents
1. [Common ALB Issues](#common-alb-issues)
2. [Target Group & Health Check Problems](#target-group--health-check-problems)
3. [Auto Scaling Issues](#auto-scaling-issues)
4. [EC2 Instance Problems](#ec2-instance-problems)
5. [Performance & Optimization Issues](#performance--optimization-issues)
6. [Security & Access Issues](#security--access-issues)

---

## Common ALB Issues

### Issue 1: ALB Returns 503 Service Unavailable

**Symptoms:**
- Browser shows: "Service Temporarily Unavailable"
- ALB has no healthy targets
- All instances marked unhealthy

**Diagnostic Steps:**

```bash
# Check target group health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:... \
  --region us-east-1

# Output: All targets should be "healthy"
# If showing "unhealthy", note the reason
```

**Possible Causes & Solutions:**

| Cause | Check | Fix |
|-------|-------|-----|
| **Security Group Blocks Traffic** | `aws ec2 describe-security-groups --group-ids sg-...` | Add ALB security group as source |
| **Apache Not Running** | `ssh ubuntu@10.0.1.5 && sudo systemctl status apache2` | `sudo systemctl restart apache2` |
| **Wrong Health Check Path** | ALB target group settings | Change path to `/` or valid endpoint |
| **High Instance Load** | `top` command on instance | Increase instance size or scale out |
| **Network Connectivity** | `curl -v http://10.0.1.5:80/` | Check VPC routing and NACLs |

**Quick Fix:**
```bash
# 1. Check if instances are running
aws ec2 describe-instances --filters "Name=tag:Name,Values=Apache-Instance" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]'

# 2. If not running, check ASG
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names Apache-ASG

# 3. Force refresh of target group
aws elbv2 deregister-targets --target-group-arn arn:... \
  --targets Id=i-...

aws elbv2 register-targets --target-group-arn arn:... \
  --targets Id=i-...
```

---

### Issue 2: ALB Response Time is Slow (> 1 second)

**Symptoms:**
- Requests taking 1-5 seconds to complete
- Users complaining about lag
- CloudWatch shows high Target Response Time

**Root Causes & Diagnostics:**

```
Possible causes:
1. Instances overloaded (high CPU)
   └─ Check: AWS CloudWatch CPU metrics

2. Network latency/congestion
   └─ Check: CloudWatch NetworkIn/Out

3. Application slowness
   └─ Check: SSH to instance, check logs

4. ALB uneven load distribution
   └─ Check: Instance-by-instance response times

5. Long connection timeout
   └─ Check: ALB connection settings
```

**Diagnostic Commands:**

```bash
# Check CPU utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# Check ALB response time
aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average,Maximum

# Check per-instance performance
curl -w "@curl-format.txt" -o /dev/null -s https://web-asg-1392539259.us-east-1.elb.amazonaws.com/

# curl-format.txt content:
# time_namelookup:  %{time_namelookup}s\n
# time_connect:     %{time_connect}s\n
# time_appconnect:  %{time_appconnect}s\n
# time_pretransfer: %{time_pretransfer}s\n
# time_redirect:    %{time_redirect}s\n
# time_starttransfer: %{time_starttransfer}s\n
# ----------\n
# time_total:       %{time_total}s\n
```

**Solutions:**

```bash
# Solution 1: Scale out (add more instances)
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name Apache-ASG \
  --desired-capacity 3

# Solution 2: Increase instance size
# (Requires updating launch template)
aws ec2 create-launch-template-version \
  --launch-template-id lt-... \
  --launch-template-data '{"InstanceType":"t3.small"}'

# Solution 3: Optimize application code
# SSH to instance and check logs
ssh -i awsEC2.pem ubuntu@10.0.1.5
tail -f /var/log/apache2/access.log | grep slow

# Solution 4: Enable connection multiplexing
# Update ALB settings
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn arn:... \
  --attributes Key=idle_timeout.connection_termination.enabled,Value=true
```

---

### Issue 3: ALB DNS Name Not Resolving

**Symptoms:**
- `nslookup web-asg-1392539259.us-east-1.elb.amazonaws.com` hangs or fails
- Browser shows: "DNS_PROBE_FINISHED_NXDOMAIN"
- Can't access application

**Root Causes:**

```
1. ALB not created properly
   └─ Check: AWS Console, verify ALB exists

2. DNS propagation delay
   └─ Wait: Up to 60 minutes for full propagation

3. Corporate firewall blocking DNS
   └─ Check: Try from different network

4. DNS resolver issues
   └─ Fix: Try different DNS (8.8.8.8, 1.1.1.1)
```

**Diagnostic Commands:**

```bash
# Check if ALB exists
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?LoadBalancerName==`web-ASG`]'

# Get ALB DNS name directly
aws elbv2 describe-load-balancers \
  --load-balancer-arns arn:... \
  --query 'LoadBalancers[0].DNSName'

# Test DNS resolution
nslookup web-asg-1392539259.us-east-1.elb.amazonaws.com
dig web-asg-1392539259.us-east-1.elb.amazonaws.com

# Try with specific DNS server
nslookup web-asg-1392539259.us-east-1.elb.amazonaws.com 8.8.8.8

# Check from EC2 instance
aws ec2-instance-connect send-ssh-public-key ...
ssh ubuntu@10.0.1.5
nslookup web-asg-1392539259.us-east-1.elb.amazonaws.com
```

**Solutions:**

```bash
# Solution 1: Wait for DNS propagation
# No action needed, just wait 5-60 minutes

# Solution 2: Clear DNS cache (local machine)
# macOS:
sudo dscacheutil -flushcache

# Windows:
ipconfig /flushdns

# Linux:
sudo systemctl restart systemd-resolved

# Solution 3: Use IP directly (temporary)
# Get ALB IP
nslookup web-asg-1392539259.us-east-1.elb.amazonaws.com

# Use IP in /etc/hosts
echo "50.19.100.123 web-asg-1392539259.us-east-1.elb.amazonaws.com" | sudo tee -a /etc/hosts
```

---

## Target Group & Health Check Problems

### Issue 4: Targets Marked Unhealthy but Application Running

**Symptoms:**
- EC2 instances running Apache
- Health check requests failing
- `curl http://10.0.1.5:80/` works locally
- ALB shows target unhealthy

**Root Cause: Security Group Misconfiguration**

```bash
# Check current security group
aws ec2 describe-security-groups --group-ids sg-045d6beb

# Expected output: HTTP:80 should be open
# "Inbound Rules":
#   - Protocol: tcp
#   - Port: 80
#   - CIDR: 0.0.0.0/0 (or ALB security group)

# Check if ALB security group is allowed
# ALB and EC2 might be in different security groups
```

**Solution:**

```bash
# Option 1: Allow from 0.0.0.0/0 (if public)
aws ec2 authorize-security-group-ingress \
  --group-id sg-045d6beb \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

# Option 2: Allow from ALB security group (better)
aws ec2 authorize-security-group-ingress \
  --group-id sg-ec2-... \
  --protocol tcp \
  --port 80 \
  --source-security-group-id sg-alb-...

# Verify fix
aws elbv2 describe-target-health --target-group-arn arn:...
# Should now show "healthy"
```

---

### Issue 5: Connection Draining Not Working

**Symptoms:**
- Instance terminated while requests in-flight
- Requests suddenly end with 500 error
- No graceful shutdown

**Root Cause: Deregistration delay timeout too short**

```bash
# Check current deregistration delay
aws elbv2 describe-target-group-attributes \
  --target-group-arn arn:... \
  --query 'Attributes[?Key==`deregistration_delay.timeout_seconds`]'

# If value is 0 or 30, it's too short for long requests
```

**Solution:**

```bash
# Increase connection draining timeout
aws elbv2 modify-target-group-attributes \
  --target-group-arn arn:... \
  --attributes Key=deregistration_delay.timeout_seconds,Value=300

# Verify change
aws elbv2 describe-target-group-attributes \
  --target-group-arn arn:...
```

---

### Issue 6: Health Check Threshold Too Sensitive

**Symptoms:**
- Instances flapping between healthy/unhealthy
- Frequent errors in logs around check time
- Unnecessary instance replacements

**Root Cause: Thresholds too aggressive**

```bash
# Check current health check configuration
aws elbv2 describe-target-groups \
  --target-group-arns arn:... \
  --query 'TargetGroups[0].HealthCheckConfig'

# Output:
# {
#   "Protocol": "HTTP",
#   "Port": "80",
#   "Path": "/",
#   "IntervalSeconds": 30,
#   "TimeoutSeconds": 5,
#   "HealthyThresholdCount": 2,
#   "UnhealthyThresholdCount": 2
# }
```

**Solution:**

```bash
# Increase thresholds for more tolerance
aws elbv2 modify-target-group \
  --target-group-arn arn:... \
  --health-check-interval-seconds 30 \
  --health-check-timeout-seconds 6 \
  --healthy-threshold-count 3 \
  --unhealthy-threshold-count 3

# Explanation:
# - More tolerant of temporary issues
# - 3 consecutive failures before marking unhealthy
# - 3 consecutive successes before marking healthy
# - Reduces false positives
```

---

## Auto Scaling Issues

### Issue 7: ASG Not Scaling Out Despite High CPU

**Symptoms:**
- CPU at 80%
- Still have < Max instances
- No new instances launching
- CloudWatch shows no scaling activity

**Diagnostic Steps:**

```bash
# 1. Check if scaling policy exists
aws autoscaling describe-policies \
  --auto-scaling-group-name Apache-ASG

# 2. Check scaling policy details
aws autoscaling describe-policies \
  --auto-scaling-group-name Apache-ASG \
  --policy-names CPU-Target-Tracking

# 3. Check if ASG is at max capacity
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names Apache-ASG \
  --query 'AutoScalingGroups[0].[DesiredCapacity, MaxSize, Instances]'

# 4. Check recent scaling activities
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name Apache-ASG \
  --max-records 5
```

**Root Causes & Solutions:**

| Cause | Check | Solution |
|-------|-------|----------|
| **At MaxSize** | `Desired == Max` | Increase MaxSize limit |
| **Cooldown Active** | Last scale time | Wait for cooldown (60s) |
| **Policy Disabled** | `Enabled: false` in policy | Enable scaling policy |
| **Scaling Suspended** | ASG suspended processes | Resume scaling processes |
| **Wrong Metric** | Policy uses wrong metric | Create new policy with CPU |

**Quick Fixes:**

```bash
# Fix 1: Increase MaxSize
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name Apache-ASG \
  --max-size 6

# Fix 2: Resume suspended processes
aws autoscaling resume-processes \
  --auto-scaling-group-name Apache-ASG \
  --scaling-processes "Launch" "Terminate"

# Fix 3: Force scaling activity
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name Apache-ASG \
  --desired-capacity 3

# Fix 4: Create new scaling policy
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name Apache-ASG \
  --policy-name CPU-Scaling-Policy \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration \
    TargetValue=50.0,PredefinedMetricSpecification={PredefinedMetricType=ASGAverageCPUUtilization}
```

---

### Issue 8: ASG Scaling In Too Aggressively

**Symptoms:**
- Instances terminating too quickly
- Capacity drops too fast during traffic dips
- Performance degradation

**Root Cause: Scale-in cooldown too short**

```bash
# Check current cooldown settings
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names Apache-ASG \
  --query 'AutoScalingGroups[0].DefaultCooldown'

# Check policy cooldown
aws autoscaling describe-policies \
  --auto-scaling-group-name Apache-ASG \
  --policy-names CPU-Target-Tracking \
  --query 'ScalingPolicies[0].TargetTrackingScalingPolicyConfiguration.ScaleInCooldown'
```

**Solution:**

```bash
# Increase scale-in cooldown
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name Apache-ASG \
  --policy-name CPU-Target-Tracking \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "TargetValue": 50.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "ScaleInCooldown": 600,
    "ScaleOutCooldown": 60
  }'

# Explanation:
# - ScaleOutCooldown: 60s (launch instances quickly)
# - ScaleInCooldown: 600s (wait 10min before scaling in)
# - Asymmetric cooldown is recommended
```

---

### Issue 9: ASG Stuck in Pending State

**Symptoms:**
- New instances not transitioning to "In-Service"
- ASG shows instances as "Pending" for > 5 minutes
- Desired capacity not reached

**Diagnostic Steps:**

```bash
# Check ASG status
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names Apache-ASG \
  --query 'AutoScalingGroups[0].[Instances, DesiredCapacity]'

# Get more details on pending instances
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names Apache-ASG \
  --query 'AutoScalingGroups[0].Instances[] | [?LifecycleState==`Pending`]'

# Check EC2 instances
aws ec2 describe-instances \
  --instance-ids i-xxxxx \
  --query 'Reservations[0].Instances[0].[State.Name, StateTransitionReason]'
```

**Root Causes & Solutions:**

| Cause | Fix |
|-------|-----|
| **Launch Template Issue** | Check if AMI deleted, instance type available |
| **Capacity Constraint** | AWS account has insufficient capacity in AZ |
| **IAM Permissions** | ASG lacks EC2:RunInstances permission |
| **Subnet Full** | VPC subnet has no available IPs |
| **Stuck Health Check** | Grace period waiting for health check |

**Quick Fixes:**

```bash
# Fix 1: Update ASG with new launch template
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name Apache-ASG \
  --launch-template LaunchTemplateName=Apache-Template,Version='$Latest'

# Fix 2: Increase health check grace period
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name Apache-ASG \
  --health-check-grace-period 600

# Fix 3: Manually trigger instance launch
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name Apache-ASG \
  --desired-capacity 3 \
  --honor-cooldown

# Fix 4: Check CloudTrail for IAM errors
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=Apache-ASG \
  --max-results 10
```

---

## EC2 Instance Problems

### Issue 10: Instance Status Checks Failing

**Symptoms:**
- Instance shows "Impaired" in AWS Console
- "System Status Check Failed"
- ALB marks instance unhealthy

**Root Causes:**

```
1. Hardware Issues (AWS manages, usually auto-recovered)
   ├─ Disk problem
   ├─ Network interface issue
   └─ Power supply failure

2. Software Issues (You must fix)
   ├─ OS kernel panic
   ├─ SSH daemon crashed
   ├─ Network configuration corrupted
   └─ Filesystem corruption
```

**Diagnostic Commands:**

```bash
# Check instance status
aws ec2 describe-instance-status \
  --instance-ids i-... \
  --query 'InstanceStatuses[0]'

# Output:
# {
#   "InstanceStatus": {
#     "Status": "impaired",  # ❌ This is bad
#     "Details": [
#       {
#         "Name": "instance-state-transition-reason",
#         "Status": "failed",
#         "ImpairedSince": "2026-07-27T10:00:00.000Z"
#       }
#     ]
#   },
#   "SystemStatus": {
#     "Status": "failed"  # ❌ Hardware issue
#   }
# }
```

**Solutions:**

```bash
# Solution 1: Stop and start instance (restart doesn't work for hardware issues)
aws ec2 stop-instances --instance-ids i-...
aws ec2 start-instances --instance-ids i-...

# Solution 2: If still failing, terminate and let ASG replace
aws ec2 terminate-instances --instance-ids i-...
# ASG will automatically launch replacement

# Solution 3: Reboot instance (for software issues)
aws ec2 reboot-instances --instance-ids i-...

# Solution 4: Create AMI from healthy instance and redeploy
# (if multiple instances affected)
```

---

### Issue 11: Out of Memory on Instance

**Symptoms:**
- Application crashes
- Health checks fail
- CloudWatch memory metrics high
- Apache process killed by OOM killer

**Diagnostic Commands:**

```bash
# SSH to instance
ssh -i awsEC2.pem ubuntu@10.0.1.5

# Check memory status
free -h

# Output:
#              total        used        free      shared  buff/cache   available
# Mem:          973Mi       850Mi        50Mi        12Mi        72Mi        50Mi
# Swap:            0B         0B         0B

# Check process memory usage
ps aux --sort=-%mem | head

# Check kernel messages (OOM killer log)
sudo tail -f /var/log/kern.log | grep -i oom

# Check Apache memory usage
ps aux | grep apache2 | awk '{print $6}'
```

**Root Causes:**

```
1. Application memory leak
   └─ Fix: Restart application, fix code

2. Too many Apache processes
   └─ Fix: Reduce MaxRequestWorkers in Apache config

3. Instance too small for workload
   └─ Fix: Increase instance size (t3.small, t3.medium)

4. Missing swap space
   └─ Fix: Add swap or increase instance size
```

**Solutions:**

```bash
# Solution 1: Increase instance size
aws ec2 create-launch-template-version \
  --launch-template-id lt-... \
  --launch-template-data '{"InstanceType":"t3.small"}'

# Update ASG to use new template version
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name Apache-ASG \
  --launch-template LaunchTemplateName=Apache-Template,Version='$Latest'

# Solution 2: Optimize Apache configuration
ssh -i awsEC2.pem ubuntu@10.0.1.5

# Edit Apache config
sudo nano /etc/apache2/mods-available/mpm_prefork.conf

# Reduce MaxRequestWorkers (default: 256)
# StartServers          2
# MinSpareServers       6
# MaxSpareServers      10
# MaxRequestWorkers    10  # <- Reduce this
# MaxConnectionsPerChild 3000

# Restart Apache
sudo systemctl restart apache2

# Solution 3: Set up swap space (temporary)
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

---

## Performance & Optimization Issues

### Issue 12: High Network Latency from Client to ALB

**Symptoms:**
- DNS resolution: 50ms
- Connection establishment: 500ms
- Total time to first byte: 2 seconds

**Root Cause Analysis:**

```
Network Latency Breakdown:
├─ DNS: 50ms (acceptable)
├─ TCP Handshake: 100ms (check geographic distance)
├─ TLS Handshake: 300ms (if using HTTPS)
├─ Backend processing: 500ms
└─ Total: 950ms
```

**Solutions:**

```
1. Use AWS Global Accelerator
   ├─ Route traffic through AWS network
   ├─ Lower latency from anywhere globally
   └─ Cost: +$0.025/hour

2. Use CloudFront CDN
   ├─ Cache static content at edge locations
   ├─ Much lower latency for edge locations
   └─ Cost: $0.075/GB transferred

3. Optimize backend performance
   ├─ Check application code
   ├─ Enable gzip compression
   ├─ Cache responses in ALB
   └─ Reduce database queries

4. Use HTTP/2
   ├─ Enable in ALB listener
   ├─ Multiplexing reduces latency
   └─ Most modern browsers support
```

---

## Security & Access Issues

### Issue 13: Cannot SSH to EC2 Instance

**Symptoms:**
- `ssh: connect to host 10.0.1.5 port 22: Operation timed out`
- SSH key not working
- Connection refused

**Root Cause: Security Group or Network Issue**

```bash
# Check if SSH port is open
aws ec2 describe-security-groups \
  --group-ids sg-045d6beb \
  --query 'SecurityGroups[0].IpPermissions'

# Should show:
# [{
#   "IpProtocol": "tcp",
#   "FromPort": 22,
#   "ToPort": 22,
#   "IpRanges": [{"CidrIp": "0.0.0.0/0"}]  # or your IP
# }]
```

**Solutions:**

```bash
# Solution 1: Allow SSH from your IP
YOUR_IP=$(curl -s https://api.ipify.org)
aws ec2 authorize-security-group-ingress \
  --group-id sg-045d6beb \
  --protocol tcp \
  --port 22 \
  --cidr $YOUR_IP/32

# Solution 2: Fix SSH key permissions
chmod 600 awsEC2.pem

# Solution 3: Verify key matches instance
# Check key pair in AWS Console
aws ec2 describe-instances --instance-ids i-... \
  --query 'Reservations[0].Instances[0].KeyName'

# Solution 4: Use Session Manager (recommended)
# No SSH key needed, uses IAM
aws ssm start-session --target i-...
```

---

### Issue 14: Application Can't Connect to Database

**Symptoms:**
- Application error: "Connection refused"
- Health check passes (application responding)
- Database operations fail

**Diagnostic Steps:**

```bash
# SSH to instance
ssh -i awsEC2.pem ubuntu@10.0.1.5

# Test database connectivity
mysql -h rds-endpoint.us-east-1.rds.amazonaws.com -u admin -p

# Check application logs
tail -f /var/log/apache2/error.log

# Check network connectivity to RDS
curl -v telnet://rds-endpoint.us-east-1.rds.amazonaws.com:3306

# Check security group on RDS
aws ec2 describe-security-groups --group-ids sg-rds-...
```

**Root Causes:**

```
1. RDS Security Group blocks EC2
   └─ Fix: Add EC2 security group to RDS inbound rules

2. Wrong database credentials
   └─ Fix: Verify username, password, database name

3. RDS endpoint wrong
   └─ Fix: Use RDS endpoint from AWS Console

4. RDS not in same VPC
   └─ Fix: Create VPC peering or move to same VPC
```

**Solutions:**

```bash
# Solution 1: Allow EC2 to connect to RDS
aws ec2 authorize-security-group-ingress \
  --group-id sg-rds-... \
  --protocol tcp \
  --port 3306 \
  --source-security-group-id sg-ec2-...

# Solution 2: Test connection
ssh -i awsEC2.pem ubuntu@10.0.1.5
mysql -h mydb.c9z...us-east-1.rds.amazonaws.com \
  -u admin -p mypassword -e "SELECT 1"

# Solution 3: Update application connection string
# /var/www/html/config/database.php
# ENDPOINT: mydb.c9z...us-east-1.rds.amazonaws.com
# USERNAME: admin
# PASSWORD: from Secrets Manager
# DATABASE: mydb
```

---

## Quick Reference: Command Cheatsheet

### Check Infrastructure Health

```bash
# Full health check
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names Apache-ASG
aws elbv2 describe-target-health --target-group-arn arn:...
aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization
```

### View Recent Logs

```bash
# Scaling activities
aws autoscaling describe-scaling-activities --auto-scaling-group-name Apache-ASG --max-records 10

# CloudTrail
aws cloudtrail lookup-events --max-results 20 --lookup-attributes AttributeKey=EventName,AttributeValue=PutMetricAlarm

# Application logs
ssh -i awsEC2.pem ubuntu@10.0.1.5
sudo tail -f /var/log/apache2/error.log
```

### Emergency Recovery

```bash
# Force new instance launch
aws autoscaling set-desired-capacity --auto-scaling-group-name Apache-ASG --desired-capacity 2 --honor-cooldown

# Terminate problematic instance
aws ec2 terminate-instances --instance-ids i-...

# Increase capacity temporarily
aws autoscaling update-auto-scaling-group --auto-scaling-group-name Apache-ASG --max-size 8

# Suspend problematic process
aws autoscaling suspend-processes --auto-scaling-group-name Apache-ASG --scaling-processes Terminate
```

---

**Last Updated:** July 27, 2026
