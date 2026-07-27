# AWS Load Balancer & Auto Scaling Group - Interview Q&A

## Table of Contents
1. [Architecture & Design](#architecture--design)
2. [ALB & Target Groups](#alb--target-groups)
3. [Auto Scaling](#auto-scaling)
4. [Monitoring & Health Checks](#monitoring--health-checks)
5. [Troubleshooting & Optimization](#troubleshooting--optimization)
6. [Security & Best Practices](#security--best-practices)

---

## Architecture & Design

### Q1: Why use a multi-AZ deployment instead of a single instance?

**Answer:**
A single instance is a single point of failure. Multi-AZ deployment provides:
- **Availability:** If AZ-1 fails, traffic shifts to AZ-2 automatically
- **Fault Tolerance:** Application continues serving traffic during AZ outages
- **SLA Compliance:** Achieves 99.99% uptime vs 99.9% with single AZ
- **AWS Commitment:** AWS SLA for multi-AZ: 99.99% availability
- **Zero Downtime:** Existing connections continue uninterrupted

**Example:**
```
Single Instance (AZ-1 only):
├─ Instance down → 0 traffic
└─ RTO: 15-30 minutes (manual recovery)

Multi-AZ (AZ-1 + AZ-2):
├─ AZ-1 down → Traffic flows to AZ-2
└─ RTO: < 60 seconds (automatic)
```

---

### Q2: What is the difference between a Load Balancer and a Target Group?

**Answer:**

| Component | Purpose | Scope |
|-----------|---------|-------|
| **Load Balancer** | Entry point, distributes incoming traffic | Application level (Layer 7) |
| **Target Group** | Health checks & routing rules for backend targets | Backend pool management |

**Detailed Breakdown:**

**Load Balancer (ALB):**
- Receives all incoming requests from clients
- Uses DNS name to resolve to public IP
- Listens on specific port/protocol
- Routes traffic based on rules
- Can have multiple listeners

**Target Group:**
- Manages pool of EC2 instances
- Performs health checks (30-second intervals)
- Determines which targets receive traffic
- Can have multiple health check rules
- Maintains connection state for draining

**Analogy:**
```
Load Balancer = Receptionist at hotel
├─ Greets all guests
├─ Directs to appropriate room
└─ Monitors elevator status

Target Group = Elevator list
├─ Manages which elevators are available
├─ Tracks which are broken (unhealthy)
├─ Routes guests to working elevators
└─ Ensures smooth operations
```

---

### Q3: Explain the difference between ALB, NLB, and CLB. When would you use each?

**Answer:**

| Feature | ALB | NLB | CLB |
|---------|-----|-----|-----|
| **Layer** | Layer 7 (Application) | Layer 4 (Transport) | Layer 4 |
| **Throughput** | ~1-4 Gbps | ~10-400 Gbps | ~500 Mbps |
| **Latency** | 100-200ms | <100 microseconds | 100-200ms |
| **Use Case** | Web apps, APIs, HTTP(S) | Gaming, IoT, real-time | Legacy apps, simple LB |
| **Cost** | $$ | $$$ | $ |

**When to use each:**

1. **ALB (Recommended for most web apps):**
   - RESTful APIs
   - Microservices with different paths (/api, /images)
   - Host-based routing (api.example.com, www.example.com)
   - Your project! ✅

2. **NLB (High performance):**
   - Online gaming servers (millions of players)
   - IoT data streaming
   - Real-time bidding platforms
   - Extreme latency requirements (< 100 microseconds)

3. **CLB (Legacy):**
   - Old applications requiring simple LB
   - Not recommended for new projects
   - Being phased out by AWS

---

### Q4: How does the ALB decide which target to route traffic to?

**Answer:**

ALB uses **load balancing algorithms** to distribute traffic:

1. **Round Robin (Default):**
   ```
   Request 1 → Instance A
   Request 2 → Instance B
   Request 3 → Instance A
   Request 4 → Instance B
   └─ Equal distribution
   ```

2. **Least Outstanding Requests:**
   ```
   Instance A: 5 active requests
   Instance B: 2 active requests
   New request → Instance B (fewer requests)
   └─ Balances based on active connections
   ```

3. **Source IP Hash (with stickiness):**
   ```
   Same source IP → Always routes to same target
   Useful for: Stateful applications
   Exception: Session persistence
   ```

**Configuration:**
```bash
# Enable stickiness (ALB will prefer same target)
aws elbv2 modify-target-group-attributes \
  --target-group-arn arn:... \
  --attributes \
    Key=stickiness.enabled,Value=true \
    Key=stickiness.type,Value=lb_cookie \
    Key=stickiness.lb_cookie.duration_seconds,Value=86400
```

**Best Practice:**
- Use round-robin for stateless apps (recommended)
- Use stickiness only if application requires it

---

### Q5: What is connection draining and why is it important?

**Answer:**

**Connection Draining** (deregistration delay) ensures graceful instance shutdown:

```
Without Connection Draining:
├─ ALB receives termination signal
├─ ALB immediately stops sending NEW traffic
├─ Active HTTP requests → Abruptly closed (error)
└─ Impact: Users experience broken connections

With Connection Draining (300s):
├─ ALB receives termination signal
├─ ALB stops sending NEW traffic immediately
├─ Active requests allowed to complete (up to 300s)
├─ After 300s, force close any remaining connections
└─ Impact: Zero dropped connections, smooth shutdown
```

**Configuration:**
```bash
# Set connection draining timeout to 300 seconds
aws elbv2 modify-target-group-attributes \
  --target-group-arn arn:aws:elasticloadbalancing:... \
  --attributes Key=deregistration_delay.timeout_seconds,Value=300
```

**Real-World Impact:**

Scenario: Large file upload (5 minutes)
```
Without draining:
├─ Instance terminating
├─ Upload in progress (3 minutes elapsed)
├─ Connection force-closed
└─ Result: Corrupted file, user frustration ❌

With draining (300s):
├─ Instance terminating
├─ Upload continues (3 minutes elapsed)
├─ Connection completes after 4 minutes
└─ Result: Successful upload ✅
```

---

## ALB & Target Groups

### Q6: How do health checks work in a Target Group? What makes a target healthy or unhealthy?

**Answer:**

**Health Check Process:**

```
Every 30 seconds per target:

1. ALB sends HTTP GET to target
   GET / HTTP/1.1
   Host: 10.0.1.5:80
   Connection: close

2. Target responds
   HTTP/1.1 200 OK
   Content-Length: 1024

3. ALB evaluates response
   - Status code: 200 ✅ (matches 200-299)
   - Response time: 45ms ✅ (< 5s timeout)
   - Check passes ✅

4. ALB updates health status
   - Success count: +1
   - When 2 consecutive successes → HEALTHY ✅
```

**Health Status Transitions:**

```
Healthy Target:
├─ Check 1: Success ✅
├─ Check 2: Success ✅ → HEALTHY (eligible for traffic)
├─ Check 3: Success ✅ (maintains healthy state)
└─ Check 4: Failure ❌ (unhealthy count: 1/2)

Becoming Unhealthy:
├─ Check 1: Failure ❌ (unhealthy count: 1/2)
├─ Check 2: Failure ❌ (unhealthy count: 2/2) → UNHEALTHY
├─ ALB removes from rotation immediately
└─ ASG detects and launches replacement

Recovery:
├─ Check 1: Success ✅ (success count: 1/2)
├─ Check 2: Success ✅ (success count: 2/2) → HEALTHY
└─ ALB re-adds to rotation
```

**Configuration Parameters:**
```yaml
Interval:              30 seconds (how often to check)
Timeout:               5 seconds (max response time)
Healthy Threshold:     2 (checks to mark healthy)
Unhealthy Threshold:   2 (checks to mark unhealthy)
Matcher:               200-299 (acceptable status codes)
Path:                  / (URL to check)
```

**Failure Scenarios:**

```
1. TCP Connection Refused
   └─ Service not running (Apache crashed)

2. HTTP 503 Service Unavailable
   └─ Server overloaded or internal error

3. Timeout (no response in 5s)
   └─ Server hanging, network latency

4. Connection Reset
   └─ Network issue or server crash

5. Wrong Status Code (e.g., 404)
   └─ Incorrect health check path
```

---

### Q7: What happens if all targets become unhealthy?

**Answer:**

**Scenario: All targets unhealthy**

```
Step 1: Detection
├─ ALB monitors targets every 30s
├─ Both instances fail health checks
├─ After 60s: All targets marked UNHEALTHY

Step 2: Traffic Handling
├─ ALB has NO healthy targets
├─ New requests arrive
├─ ALB returns: HTTP 503 Service Unavailable
├─ Browser shows: Service temporarily unavailable

Step 3: Auto Scaling Response
├─ ASG detects: Instance count < Desired (1 < 2)
├─ After health check grace period (300s):
│  ├─ ASG marks instance as unhealthy
│  ├─ ASG terminates instance
│  └─ ASG launches replacement (new instance)
├─ New instance boots (~2-5 minutes)
└─ New instance passes health checks

Step 4: Recovery
├─ New instance: HEALTHY ✅
├─ ALB: Starts routing traffic
├─ Service: Back online
└─ Total downtime: ~5 minutes (for this scenario)
```

**Prevention Strategies:**

1. **Better Health Checks:**
   ```bash
   # Check application logic, not just HTTP 200
   aws elbv2 modify-target-group \
     --target-group-arn arn:... \
     --health-check-path /health-check \
     --matcher "HttpCode=200"
   ```

2. **Broader Unhealthy Threshold:**
   ```bash
   # Require 3 failures before marking unhealthy (more tolerant)
   # Prevents false positives from temporary issues
   ```

3. **Monitoring & Alerts:**
   ```bash
   # CloudWatch alarm when all targets unhealthy
   aws cloudwatch put-metric-alarm \
     --alarm-name AllTargetsUnhealthy \
     --metric-name HealthyHostCount \
     --threshold 0 \
     --comparison-operator LessThanOrEqualToThreshold
   ```

---

### Q8: How does ALB handle HTTPS? Should you always use HTTPS?

**Answer:**

**HTTPS Configuration:**

```
Step 1: Get SSL Certificate
├─ AWS Certificate Manager (ACM) - FREE
├─ Request certificate for *.example.com
├─ Verify domain ownership
└─ Certificate ready in minutes

Step 2: Create HTTPS Listener
aws elbv2 create-listener \
  --load-balancer-arn arn:... \
  --protocol HTTPS \
  --port 443 \
  --certificates CertificateArn=arn:aws:acm:...

Step 3: (Optional) Redirect HTTP to HTTPS
aws elbv2 create-rule \
  --listener-arn arn:... \
  --priority 1 \
  --conditions Field=path-pattern,Values=/* \
  --actions Type=redirect,RedirectConfig='StatusCode=301,Protocol=HTTPS,Port=443'
```

**When to use HTTPS:**

| Scenario | Use HTTPS? | Why |
|----------|-----------|-----|
| **Public web app** | ✅ Always | Data confidentiality, SEO ranking |
| **API endpoint** | ✅ Always | Protect API keys, auth tokens |
| **Internal app** | ⚠️ Conditional | If accessing from internet: yes |
| **Local network only** | ❌ Optional | VPN already provides encryption |

**Your Project (HTTP only - Demo):**
```
Current: HTTP://web-asg-1392539259.us-east-1.elb.amazonaws.com
├─ Acceptable for demo
├─ Recommended for production: HTTPS
└─ Cost: FREE (ACM certificate is free)
```

---

## Auto Scaling

### Q9: How does the Auto Scaling Group decide when to scale out or scale in?

**Answer:**

**Target Tracking Scaling (Used in your project):**

```
Algorithm:
1. Measure average CPU utilization across all instances
2. Compare to target value (50%)
3. Calculate desired capacity

Formula:
DesiredCapacity = ceil(CurrentInstances × AverageCPU / TargetCPU)

Examples:

Example 1: Scale Out (CPU > 50%)
├─ Current instances: 2
├─ Average CPU: 65%
├─ Target: 50%
├─ Calculation: 2 × (65/50) = 2.6 ≈ 3
├─ Action: Launch 1 new instance (2 → 3)
└─ Result: 3 × (65/3) = 21.67% CPU per instance (below target)

Example 2: Scale In (CPU < 50%)
├─ Current instances: 4
├─ Average CPU: 25%
├─ Target: 50%
├─ Calculation: 4 × (25/50) = 2.0 = 2
├─ Action: Terminate 2 instances (4 → 2)
└─ Result: 2 × (25/2) = 12.5% CPU per instance (still below target, but at min)

Example 3: Perfect Balance (CPU ≈ 50%)
├─ Current instances: 2
├─ Average CPU: 50%
├─ Target: 50%
├─ Calculation: 2 × (50/50) = 2.0 = 2
├─ Action: No change (maintain desired capacity)
└─ Result: Stable, no oscillation ✅
```

**Cooldown Periods (Prevent Oscillation):**

```
Scale-Out Cooldown (60 seconds):
├─ After scale-out, wait 60s before next scale-out
├─ Reason: New instances need time to process load
└─ Benefit: Prevents launching too many instances

Scale-In Cooldown (300 seconds):
├─ After scale-in, wait 300s before next scale-in
├─ Reason: Reducing too fast can cause load spikes
└─ Benefit: Prevents thrashing, maintains stability

Warm-Up Period (300 seconds):
├─ New instances don't contribute to metrics for 300s
├─ Reason: New instances starting up use more CPU
├─ Benefit: Accurate CPU readings only from stable instances
```

---

### Q10: What's the difference between desired capacity, minimum, and maximum in an ASG?

**Answer:**

```
Auto Scaling Group Constraints:

Min Size (Floor):        2 instances
├─ Absolute minimum
├─ ASG ALWAYS maintains >= 2 instances
├─ Even if all instances deleted, ASG launches 2
└─ Cost floor: At least 2 instances running 24/7

Desired Capacity:        2-4 instances (dynamic)
├─ Target number of instances
├─ ASG adjusts toward this number
├─ Controlled by scaling policies
└─ Currently: 2 (can increase to 4)

Max Size (Ceiling):      4 instances
├─ Absolute maximum
├─ ASG NEVER launches > 4 instances
├─ Even if CPU 100%, stops at 4 instances
└─ Cost ceiling: Maximum 4 instances

Relationship:
Min ≤ Desired ≤ Max
2  ≤  2-4   ≤  4
```

**Practical Example - Restaurant Analogy:**

```
Min = 2: Restaurant ALWAYS has 2 employees
├─ Even on slow Tuesday nights
├─ Covers basic operations
└─ Cost: Baseline salary for 2 people

Max = 4: Restaurant NEVER has > 4 employees
├─ Even on busy Friday nights
├─ Limits overtime costs
└─ Quality control: Too many cooks spoil the broth

Desired = 2-4: Scaling based on customers
├─ 10 customers → Desired = 2 employees ✅
├─ 50 customers → Desired = 3 employees ✅
├─ 100 customers → Desired = 4 employees ✅
└─ 200 customers → Desired = 4 (maxed out, can't handle more)
```

---

### Q11: If you terminate an instance, how does the ASG respond?

**Answer:**

**Instance Termination Handling:**

```
Timeline: User terminates instance i-02d5d5cf8a14c50fe

T=0s:     Instance terminated via AWS Console
├─ AWS starts shutdown sequence
├─ No more requests received
└─ Active connections: Still processing

T=5s:     ALB health check fails
├─ TCP connection refused
├─ Health check count: 1/2 failures
└─ ALB still routes existing connections

T=35s:    ALB health check fails again
├─ Health check count: 2/2 failures
├─ Instance marked UNHEALTHY
└─ ALB removes from targets

T=40s:    ASG detects missing instance
├─ Instance missing from target group
├─ ASG checks if in "In-Service" state
├─ ASG starts countdown (health check grace period)
└─ Grace period: 300 seconds

T=300s:   ASG grace period expires
├─ Instance still considered unhealthy
├─ ASG takes action: LAUNCH REPLACEMENT
├─ New instance: i-new1234567890
└─ ASG desired: 2, current: 1 → Launch 1 instance

T=305s:   New instance boots
├─ EC2 initializes hardware
├─ OS starts loading
├─ User data script execution begins

T=310s:   User data script completes
├─ Apache2 installed
├─ Web page deployed
├─ Application ready

T=320s:   First health check for new instance
├─ ALB sends health check
├─ Apache responds: 200 OK ✅
└─ Success count: 1/2

T=350s:   Second health check passes
├─ Health check response: 200 OK ✅
├─ Success count: 2/2 → HEALTHY ✅
├─ ALB adds new instance to targets
└─ Traffic now flows to new instance

Total time: ~5-6 minutes
Result: Automatic replacement, zero manual intervention ✅
```

**Verification:**
```bash
# View ASG activity
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name Apache-ASG \
  --region us-east-1

# Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:... \
  --region us-east-1
```

---

## Monitoring & Health Checks

### Q12: How do you monitor an Auto Scaling Group? What metrics matter?

**Answer:**

**Key Metrics:**

```
1. CPU Utilization (Most Important)
   ├─ Definition: % of CPU capacity being used
   ├─ Your project: Target = 50%
   ├─ Healthy range: 30-70%
   ├─ If > 90%: Scale out immediately
   └─ If < 10%: Scale in after delay

2. Network In/Out
   ├─ Monitors bandwidth consumption
   ├─ Helps detect traffic spikes
   ├─ Alert if > 100 Mbps sustained

3. Instance Count
   ├─ Desired vs. Actual vs. Terminating
   ├─ Ensures ASG maintaining correct capacity
   ├─ Alert if mismatch for > 5 minutes

4. Group Pending Instances
   ├─ Instances launching but not yet in-service
   ├─ If > 2 for > 5 minutes: Problem with launch

5. Group In-Service Instances
   ├─ Instances actively serving traffic
   ├─ Should = Desired (when stable)

6. Target Group Health
   ├─ Healthy count vs. Unhealthy count
   ├─ Alert if unhealthy > 0

7. Response Time (ALB)
   ├─ Time from request to response
   ├─ Alert if > 1000ms
```

**CloudWatch Dashboard:**

```bash
# Create custom dashboard
aws cloudwatch put-dashboard \
  --dashboard-name ASG-Monitoring \
  --dashboard-body file://dashboard.json

# Content of dashboard.json:
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/EC2", "CPUUtilization", {"stat": "Average"}],
          ["AWS/AutoScaling", "GroupDesiredCapacity"],
          ["AWS/AutoScaling", "GroupInServiceInstances"],
          ["AWS/ApplicationELB", "TargetResponseTime"],
          ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count"]
        ]
      }
    }
  ]
}
```

---

### Q13: What are the differences between system alarms and custom metrics?

**Answer:**

**System Alarms (Default - No Configuration):**

```
Provided by AWS automatically:

CPU Utilization
├─ Measures CPU usage
├─ Available immediately
└─ Example: "CPU > 80% → Send SNS alert"

NetworkIn / NetworkOut
├─ Measures bandwidth
├─ Available immediately
└─ Example: "Network Out > 1 Gbps"

DiskReadOps / DiskWriteOps
├─ Measures disk activity
├─ Available immediately
└─ Example: "Disk reads > 10,000 ops/min"

StatusCheckFailed
├─ Overall instance health
├─ Available immediately
└─ Example: "Instance check failed → Launch replacement"

Instance Count
├─ Desired vs. actual
├─ Available from ASG metrics
└─ Example: "Desired=2, Actual=1 → Alert!"
```

**Custom Metrics (Application-Specific):**

```
You define based on business needs:

Application Metrics:
├─ Request latency (p95, p99)
├─ Error rate (4xx, 5xx)
├─ Database connection pool utilization
├─ Cache hit ratio
├─ Queue depth

Example: Monitor error rate
aws cloudwatch put-metric-data \
  --namespace Custom/Application \
  --metric-name ErrorRate \
  --value 0.5 \
  --unit Percent

Create alarm based on custom metric:
aws cloudwatch put-metric-alarm \
  --alarm-name HighErrorRate \
  --metric-name ErrorRate \
  --namespace Custom/Application \
  --statistic Average \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:...
```

**Best Practice:**
- Use system alarms for infrastructure health
- Use custom metrics for application behavior
- Combine both for comprehensive monitoring

---

## Troubleshooting & Optimization

### Q14: Instances keep failing health checks. How do you diagnose the issue?

**Answer:**

**Diagnostic Steps:**

```
Step 1: Check Target Group Status
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:... \
  --region us-east-1

Output:
{
  "TargetHealthDescriptions": [
    {
      "Target": {"Id": "i-02d5d5cf..."},
      "TargetHealth": {
        "State": "unhealthy",
        "Reason": "Target.ResponseCodeMismatch",
        "Description": "Health checks failed with these codes: [500]"
      }
    }
  ]
}
```

**Common Failure Reasons:**

| Reason | Cause | Fix |
|--------|-------|-----|
| **Target.ResponseCodeMismatch** | Wrong HTTP status (e.g., 404) | Check health check path |
| **Target.Timeout** | No response within 5s | Instance overloaded? Network latency? |
| **Target.FailedHealthChecks** | General failure | SSH to instance, check logs |
| **Elb.RegistrationInProgress** | Still registering | Wait, normal for new instances |
| **Target.ResponseCodeMismatch** | 500 errors | Application crash? Database error? |

**Diagnostic Commands:**

```bash
# SSH to instance
ssh -i awsEC2.pem ubuntu@10.0.1.5

# Check Apache status
sudo systemctl status apache2

# Check Apache error logs
sudo tail -f /var/log/apache2/error.log

# Test health check manually
curl -v http://localhost:80/

# Check if port 80 is listening
sudo netstat -tlnp | grep :80

# Check security group rules
aws ec2 describe-security-groups --group-ids sg-045d6beb

# Verify ALB can reach instance
curl -v http://10.0.1.5:80/ -H "Host: web-asg-1392539259.us-east-1.elb.amazonaws.com"
```

**Common Solutions:**

```
Issue 1: Wrong Health Check Path
├─ Problem: Health check path is "/health" but app only has "/"
├─ Solution: Change health check path to existing endpoint
└─ Command:
    aws elbv2 modify-target-group \
      --target-group-arn arn:... \
      --health-check-path /

Issue 2: Security Group Blocking Traffic
├─ Problem: Security group doesn't allow HTTP:80
├─ Solution: Add ALB security group to inbound rules
└─ Command:
    aws ec2 authorize-security-group-ingress \
      --group-id sg-ec2-... \
      --protocol tcp \
      --port 80 \
      --source-security-group-id sg-alb-...

Issue 3: Application Crash
├─ Problem: Apache process crashed
├─ Solution: Restart Apache or replace instance
└─ Command:
    sudo systemctl restart apache2

Issue 4: Instance Memory Full
├─ Problem: OOM (Out of Memory), application killed
├─ Solution: Increase instance size or fix memory leak
└─ Command:
    free -h  # Check memory
    ps aux  # Check processes
```

---

### Q15: Why is auto scaling not triggering even though CPU is high?

**Answer:**

**Debugging Checklist:**

```
Step 1: Verify Scaling Policy Exists
aws autoscaling describe-policies \
  --auto-scaling-group-name Apache-ASG \
  --region us-east-1

└─ Check if CPU-Target-Tracking policy listed

Step 2: Check Scaling Policy Configuration
aws autoscaling describe-policies \
  --auto-scaling-group-name Apache-ASG \
  --policy-names CPU-Target-Tracking \
  --query 'ScalingPolicies[0].TargetTrackingScalingPolicyConfiguration'

Expected:
{
  "TargetValue": 50.0,
  "PredefinedMetricSpecification": {
    "PredefinedMetricType": "ASGAverageCPUUtilization"
  },
  "ScaleOutCooldown": 60,
  "ScaleInCooldown": 300
}

Step 3: Check if ASG at Max Capacity
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names Apache-ASG \
  --query 'AutoScalingGroups[0].[MaxSize, DesiredCapacity, Instances]'

If DesiredCapacity == MaxSize (e.g., 4 == 4):
├─ Problem: Already at max capacity
├─ ASG can't scale further
└─ Solution: Increase MaxSize parameter

Step 4: Check Cooldown Period
├─ If just scaled: Cooldown active (no new scaling)
├─ Cooldown: 60s (scale-out), 300s (scale-in)
└─ Solution: Wait for cooldown to expire

Step 5: Monitor Scaling Activity
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name Apache-ASG \
  --max-records 10

Check:
├─ Last scaling activity timestamp
├─ Reason for activity (or lack thereof)
└─ Status (Successful, Failed, etc.)
```

**Common Issues & Fixes:**

```
Issue 1: Already at MaxSize
├─ Current: 4 instances, Max: 4
├─ Fix: Increase MaxSize
└─ aws autoscaling update-auto-scaling-group \
     --auto-scaling-group-name Apache-ASG \
     --max-size 6

Issue 2: Scaling Disabled
├─ Problem: ASG suspended scaling processes
├─ Fix: Resume scaling
└─ aws autoscaling resume-processes \
     --auto-scaling-group-name Apache-ASG \
     --scaling-processes "Launch" "Terminate"

Issue 3: Cooldown Active
├─ Problem: Just scaled, waiting for cooldown
├─ Fix: Wait 60-300 seconds

Issue 4: Insufficient IAM Permissions
├─ Problem: IAM user can't describe metrics
├─ Fix: Add cloudwatch:GetMetricStatistics permission

Issue 5: CPU Metric Not Available
├─ Problem: Detailed monitoring not enabled
├─ Fix: Enable detailed monitoring in launch template
└─ aws ec2 create-launch-template \
     --monitoring Enabled=true
```

---

## Security & Best Practices

### Q16: How would you secure this architecture further?

**Answer:**

**Security Enhancements (Priority Order):**

```
Priority 1 - CRITICAL:

1. Enable HTTPS
   ├─ Get free ACM certificate
   ├─ Add HTTPS listener to ALB
   ├─ Redirect HTTP → HTTPS
   └─ Cost: $0 (ACM certificates free)

2. Restrict SSH Access
   ├─ Current: May be open to 0.0.0.0/0
   ├─ Solution: Allow only admin IPs
   └─ Use Systems Manager Session Manager (no SSH key needed)

3. Enable VPC Flow Logs
   ├─ Monitor network traffic
   ├─ Detect suspicious patterns
   └─ aws ec2 create-flow-logs \
        --resource-type VPC \
        --resource-ids vpc-... \
        --traffic-type ALL \
        --log-destination-type CloudWatch

Priority 2 - IMPORTANT:

4. Use AWS Secrets Manager
   ├─ Don't hardcode credentials
   ├─ Rotate secrets automatically
   └─ Grant IAM role to instance

5. Enable CloudTrail
   ├─ Audit all API calls
   ├─ Detect unauthorized changes
   └─ 90-day retention minimum

6. Add AWS WAF (Web Application Firewall)
   ├─ Protect against SQL injection, XSS
   ├─ Rate limiting
   └─ AWS WAF → ALB

Priority 3 - NICE TO HAVE:

7. Enable GuardDuty
   ├─ AI-powered threat detection
   ├─ Identify unusual behavior
   └─ Automatic incident response

8. Use KMS for Encryption
   ├─ EBS encryption with customer-managed keys
   ├─ CloudWatch Logs encryption
   └─ S3 bucket encryption

9. Implement Least Privilege IAM
   ├─ EC2 instance role with specific permissions
   ├─ Not Admin role
   └─ Principle: Only needed permissions
```

---

### Q17: What would happen if the ALB itself fails?

**Answer:**

```
ALB Failure Scenarios:

Scenario 1: ALB Hardware Failure
├─ AWS manages ALB, provides 99.99% SLA
├─ ALB automatically replaces failed components
└─ Zero user-facing impact

Scenario 2: ALB Becomes Unresponsive
├─ Requests timeout after 60 seconds
├─ Client retries, may fail
├─ Impact: ~1-2 second delay for some requests

Scenario 3: All ALBs in AZ Down (Rare)
├─ You have 2 ALB endpoints (us-east-1a, us-east-1b)
├─ Other AZ continues operating
├─ Traffic automatically shifts (DNS)
└─ Minimal impact (usually unnoticed)

Mitigation Strategies:

1. Global Load Balancer Setup (AWS Global Accelerator)
   ├─ Multiple regions
   ├─ Automatic failover between regions
   ├─ Lower latency from anywhere globally
   └─ Cost: Additional $0.025/hour

2. Route 53 Health Checks
   ├─ Monitor ALB endpoint
   ├─ Failover to standby ALB
   ├─ Or use another region
   └─ Provides DNS-level failover

3. Multi-Region Setup
   ├─ Primary region: us-east-1
   ├─ Secondary region: us-west-2
   ├─ Route 53 routes based on health
   └─ RTO: < 30 seconds
```

---

### Q18: How much would this architecture cost?

**Answer:**

**Cost Breakdown (Monthly):**

```
Compute:
├─ EC2 (t3.micro, on-demand): $0.0116/hour
│  ├─ 2 instances × 730 hours/month
│  ├─ 2 × $0.0116 × 730 = $16.94/month
│  └─ During peak: 3-4 instances = $25-34/month
│
├─ ALB:
│  ├─ ALB hourly: $0.0225/hour
│  ├─ LCU (Load Balancer Capacity Unit): $6/month
│  ├─ 730 hours × $0.0225 = $16.43/month
│  └─ Total: ~$22/month
│
├─ Data Transfer:
│  ├─ Within AZ: $0/month
│  ├─ Cross-AZ: $0.01/GB
│  ├─ Assuming 100GB/month cross-AZ
│  └─ Cost: $1/month
│
└─ CloudWatch:
   ├─ Metrics: 5/month (free tier)
   ├─ Custom metrics: $0.30/month each
   ├─ Logs: $0.50/GB ingested
   └─ Total: ~$5/month

TOTAL ESTIMATED: ~$45/month
```

**Cost Optimization:**

```
Option 1: Reserved Instances (40% savings)
├─ Prepay for 1 year: $0.0068/hour (vs $0.0116)
├─ 2 instances × $0.0068 × 8760 = $119/year
├─ On-demand equivalent: $203/year
├─ Savings: ~$84/year (41%)
└─ Total annual: ~$540 (vs $684)

Option 2: Spot Instances (70% savings)
├─ Spot price: $0.0035/hour (vs $0.0116)
├─ 2 instances × $0.0035 × 8760 = $61/year
├─ Risk: Can be interrupted
├─ Mitigation: Use ASG with mixed instances
└─ Total annual: ~$320 (with Spot)

Option 3: Right-Size Instances
├─ t3.micro: 1 vCPU, 1GB RAM, $0.0116/hour
├─ t3.small: 2 vCPU, 2GB RAM, $0.023/hour
├─ For your load: t3.micro is sufficient ✅
└─ Savings: Already optimized

Option 4: Reduce Max Capacity
├─ Current: Max 4 instances
├─ If peak load requires only 3:
│  └─ Max: 3 instances = Save $0.0116/hour
│  └─ Potential annual savings: ~$100

Recommended for Production:
├─ Use Reserved Instances (1-3 year terms)
├─ Use Spot Instances for flexible workloads
├─ Mix: 2 reserved + 2 Spot = Best balance
└─ Estimated savings: 50-60%
```

---

### Q19: What would be your rollout strategy for a new application version?

**Answer:**

**Deployment Strategy: Blue-Green Deployment**

```
Phase 1: Preparation
├─ Create new AMI with updated application code
├─ Name: Apache-Template-v2
├─ Test in dev environment
└─ Verify all health checks pass

Phase 2: Create New Launch Template
aws ec2 create-launch-template-version \
  --launch-template-id lt-035c3ad7240f7661a \
  --source-version 1 \
  --launch-template-data '{"ImageId":"ami-newversion..."}'

Phase 3: Create New ASG (Blue-Green)
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name Apache-ASG-v2 \
  --launch-template LaunchTemplateName=Apache-Template,Version=2 \
  --min-size 2 --max-size 4 --desired-capacity 2 \
  --target-group-arns arn:...

Phase 4: Test New Instances
├─ Verify instances healthy in new ASG
├─ Check application functionality
├─ Run smoke tests
└─ Monitor CPU, memory, network

Phase 5: Switch Traffic (Blue-Green)
# Remove old ASG from target group
aws autoscaling detach-load-balancer-target-groups \
  --auto-scaling-group-name Apache-ASG \
  --target-group-arns arn:...

# Attach new ASG to target group
aws autoscaling attach-load-balancer-target-groups \
  --auto-scaling-group-name Apache-ASG-v2 \
  --target-group-arns arn:...

Phase 6: Monitor & Verify
├─ Monitor error rates
├─ Check response times
├─ Verify no user impact
└─ Watch for 30 minutes

Phase 7: Cleanup
# If all good:
aws autoscaling delete-auto-scaling-group \
  --auto-scaling-group-name Apache-ASG \
  --force-delete

# If rollback needed (< 30s):
# Reattach old ASG instead
```

**Alternative: Rolling Deployment**

```
More gradual approach:

Phase 1: Update 1 instance
├─ Terminate 1 instance (out of 2)
├─ ASG launches replacement from new template
├─ Monitor for 10 minutes
└─ If OK, proceed; else rollback

Phase 2: Update remaining instance
├─ Terminate other old instance
├─ ASG launches replacement from new template
├─ All instances now v2
└─ Complete!

Advantages:
├─ Gradual rollout (no big bang)
├─ Easy rollback if issues detected
├─ Minimal service disruption
└─ Recommended for production

Time:
├─ ~10-15 minutes per instance
├─ Total: 20-30 minutes for 2 instances
└─ Much longer than blue-green
```

---

### Q20: How do you handle database connections in this architecture?

**Answer:**

**Database Connection Architecture:**

```
Without Connection Pooling (BAD):
Every request:
├─ Open database connection
├─ Execute query
├─ Close database connection
└─ Overhead: High latency, poor throughput

With Connection Pooling (GOOD):
Application startup:
├─ Create pool of 10-20 persistent connections
├─ Connections pre-authenticated
├─ Ready for immediate use

Per request:
├─ Get connection from pool (< 1ms)
├─ Execute query
├─ Return connection to pool
└─ Connection reused for next request

Result:
├─ 100x faster than reconnecting each time
├─ Supports 100x more concurrent requests
└─ Database connection limit: Never exceeded
```

**Implementation:**

```bash
# Install connection pooler
apt-get install pgbouncer  # PostgreSQL
# or
apt-get install ProxySQL   # MySQL

# Configuration: /etc/pgbouncer/pgbouncer.ini
[databases]
mydb = host=rds-endpoint.us-east-1.rds.amazonaws.com port=5432 dbname=mydb

[pgbouncer]
pool_mode = transaction  # or session
max_client_conn = 1000
default_pool_size = 20
min_pool_size = 5
```

**Multi-AZ Database Setup:**

```
RDS with Multi-AZ:
├─ Primary instance: us-east-1a
├─ Standby instance: us-east-1b
├─ Synchronous replication
├─ Automatic failover (< 2 minutes)
└─ RTO < 5 minutes, RPO = 0

All EC2 instances connect to:
├─ RDS endpoint: mydb.cxx9xxx.us-east-1.rds.amazonaws.com
├─ DNS automatically resolves to primary
├─ On failover: DNS automatically updates
└─ Application sees no change!

Read Replicas (for scale-out reads):
├─ Primary: Write operations
├─ Read Replica 1: Read operations (us-east-1b)
├─ Read Replica 2: Read operations (us-east-1c)
└─ Application routes SELECT to replicas
```

**Cost Consideration:**

```
RDS Pricing (db.t3.micro):
├─ Single-AZ: $30/month
├─ Multi-AZ: $60/month (2x cost for HA)
├─ Read Replica: $30/month each
└─ Total with 2 replicas: $120/month

Comparison:
├─ 2 instances (your project): $45/month
├─ Add RDS Multi-AZ: +$60/month
├─ Total: ~$105/month
└─ Still very cost-effective for HA
```

---

## Summary

**Key Takeaways:**

1. **High Availability:** Multi-AZ + health checks + auto-replacement = 99.99% uptime
2. **Auto Scaling:** CPU target tracking prevents both over/under-provisioning
3. **Load Balancing:** ALB intelligently distributes traffic across healthy targets
4. **Monitoring:** CloudWatch metrics drive all scaling decisions
5. **Security:** Use HTTPS, restrict SSH, enable logging, implement WAF
6. **Cost:** Very cost-effective (~$45-50/month for this architecture)
7. **Deployment:** Blue-green deployments enable zero-downtime updates

---

**Last Updated:** July 27, 2026
