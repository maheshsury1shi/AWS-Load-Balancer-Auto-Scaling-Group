# Troubleshooting Guide

This guide follows the same architecture as the diagrams: ALB → target group → EC2 instances → ASG → CloudWatch.

## Common Issues

### 1. ALB returns 503
Cause: no healthy targets are registered in the target group.
Solution: verify the EC2 instances are running, Apache is active, the health check path is returning success, and the EC2 security group permits traffic from the ALB.

### 2. Requests are slow
Cause: EC2 instances are under heavy CPU load or the application is slow.
Solution: review CloudWatch metrics, check Apache logs, and scale out if needed.

### 3. Auto Scaling does not add instances
Cause: CloudWatch metrics are not crossing the threshold, or the ASG is not attached to the target group correctly.
Solution: check the scaling policy, verify the ASG configuration, and ensure the launch template is valid.

### 4. Instance is marked unhealthy
Cause: the health check is failing.
Solution: confirm the web server responds on port 80 and the target group health check path is correct.

### 5. High availability is not maintained
Cause: one instance failed and replacement did not happen.
Solution: review the ASG activity history and ensure the launch template, AMI, and subnet placement are valid.
