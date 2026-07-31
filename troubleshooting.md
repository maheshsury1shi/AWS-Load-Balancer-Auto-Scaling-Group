# Troubleshooting Guide

This project uses an internet-facing Application Load Balancer (ALB), a target group, Ubuntu EC2 instances running Apache, an Auto Scaling Group (ASG), and CloudWatch CPU metrics. Use the checks below in this order: target health, network access, instance bootstrap, and then scaling.

## Project Configuration To Verify

Keep these values consistent across the ALB, target group, launch template, and ASG:

| Component | Expected configuration |
|---|---|
| Network | One VPC with two public subnets in different Availability Zones |
| ALB | Internet-facing; listeners on TCP 80 and, when HTTPS is configured, TCP 443 |
| Target group | HTTP targets on port 80; health-check path `/health` |
| EC2 security group | TCP 80 from the ALB security group; TCP 22 only from a trusted IP |
| ASG | Minimum 2, desired 2, maximum 4 instances; attached to the target group |
| Launch template | Ubuntu AMI, correct EC2 security group, and the contents of `userdata.sh` as user data |
| Scaling | CloudWatch CPU-based policy; the deployment guide describes scale-out above 50% and scale-in below 20% |

Replace the placeholder IDs in the AWS CLI examples with values from the current AWS account and region.

## First Diagnostic Pass

1. Check the ALB target group **Targets** tab and record each target's state and reason. This is usually more useful than testing the ALB repeatedly.
2. Confirm the EC2 instances are `running`, have the expected security group, and are in the two intended subnets.
3. Confirm the target group is using HTTP port 80 and `/health`, not `/` or a different port.
4. Check the ASG activity history and the launch template version used by the ASG.
5. Check CloudWatch CPU metrics only after target health and bootstrap status are correct.

Useful AWS CLI checks:

```bash
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <asg-name>
aws autoscaling describe-scaling-activities --auto-scaling-group-name <asg-name>
aws cloudwatch list-metrics --namespace AWS/EC2 --metric-name CPUUtilization
```

## ALB Returns 503

An ALB returns 503 when it has no healthy targets available. Check the target health reason first, then:

- Confirm both instances are registered in the target group and are listening on port 80.
- Confirm the target group health check is HTTP on port 80 with path `/health`.
- Confirm the EC2 security group allows port 80 **from the ALB security group**, not only from your laptop IP.
- Confirm the ALB security group allows inbound port 80 from the internet. Add port 443 only when an HTTPS listener and certificate are configured.
- Confirm the instance subnet route table has a default route to the Internet Gateway, because this project places the web instances in public subnets.

If an instance is healthy but the ALB still returns 503, verify that the listener forwards to the intended target group and that the target group's port matches Apache's listening port.

## Target Is Unhealthy

The user data script creates `/var/www/html/health` with an `OK` response. Test the endpoint directly from an SSH session:

```bash
curl -i http://localhost/health
curl -i http://localhost/
sudo ss -ltnp | grep ':80'
```

Expected results are an HTTP 200 response for `/health` and a process listening on port 80. If they fail, inspect Apache and bootstrap logs:

```bash
sudo systemctl status apache2 --no-pager
sudo apache2ctl configtest
sudo journalctl -u apache2 --no-pager -n 100
sudo tail -n 100 /var/log/userdata-log.txt
sudo tail -n 100 /var/log/apache2/error.log
```

Also check the target group's health-check timeout, interval, and success codes. A slow response, a redirect that is not accepted by the configured matcher, or a path that returns 404 will keep the target unhealthy.

## User Data Did Not Complete

`userdata.sh` uses `set -e`, so an error in package installation, metadata lookup, Apache configuration, or another command can stop the script. The script redirects output to `/var/log/userdata-log.txt` and runs `apache2ctl configtest` before starting Apache.

Check the following:

```bash
sudo test -f /var/log/userdata-log.txt && sudo tail -n 150 /var/log/userdata-log.txt
sudo systemctl is-enabled apache2
sudo systemctl is-active apache2
ls -l /var/www/html/index.html /var/www/html/health
```

If the log stops during `apt-get update` or `apt-get install`, verify that the instance has outbound internet access through its subnet route and Internet Gateway. If the page loads but instance details are blank, check the instance metadata settings: the script requests metadata without an IMDSv2 token, so an instance configured to require IMDSv2 may need the metadata section updated or user data adjusted.

## Cannot Reach Apache Directly

Direct access to an instance is not the normal application path; users should connect through the ALB DNS name. For SSH diagnostics, confirm all of the following:

- The instance has a reachable public IPv4 address, or you are connecting through an approved management path.
- TCP 22 is allowed from your current trusted IP, not from `0.0.0.0/0`.
- The key pair and OS username match the Ubuntu AMI.
- The instance security group allows port 80 from the ALB security group.
- The network ACL and route table are not blocking return traffic.

Do not expose the EC2 web servers broadly just to work around an ALB security-group rule. Fix the source security group relationship instead.

## ALB DNS Name Does Not Open

Verify that the ALB is `active`, internet-facing, attached to both public subnets, and has a listener forwarding to the expected target group:

```bash
aws elbv2 describe-load-balancers --load-balancer-arns <load-balancer-arn>
aws elbv2 describe-listeners --load-balancer-arn <load-balancer-arn>
aws elbv2 describe-rules --listener-arn <listener-arn>
```

If the browser shows a connection timeout, inspect the ALB security group and the public subnet route table. A 503 instead indicates that the ALB is reachable but has no healthy target.

## Requests Are Slow or Unevenly Distributed

The page generated by the user data script displays the instance ID, Availability Zone, private IP, region, and launch time. Refresh the ALB DNS name and use those values to confirm requests reach both instances.

Then review:

- CloudWatch `CPUUtilization` for every instance and the ASG activity history.
- Apache access and error logs under `/var/log/apache2/`.
- Target health and response time for each target.
- Whether one target is repeatedly becoming unhealthy and being removed from rotation.

The script enables Apache compression and keep-alive, but those settings do not replace capacity scaling. Sustained CPU pressure should be investigated with the scaling checks below.

## Auto Scaling Does Not Add Instances

Check the ASG's minimum, desired, and maximum values, the attached target group, and the active launch template version:

```bash
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <asg-name> \
	--query 'AutoScalingGroups[0].{Min:MinSize,Desired:DesiredCapacity,Max:MaxSize,Instances:Instances[*].{Id:InstanceId,Health:HealthStatus,Lifecycle:LifecycleState}}'
```

If desired capacity is already 4, the project maximum has been reached. If CPU is below the policy threshold, no scale-out is expected. If CPU is high but capacity does not change, inspect scaling activities for launch failures, subnet capacity, quota errors, invalid AMI or security-group references, and missing permissions for the service-linked Auto Scaling role.

Remember that a new instance must finish user data, start Apache, register with the target group, and pass `/health` before the ALB can send it traffic.

## Instances Scale In or Out Unexpectedly

Check the CloudWatch metric, policy target, cooldown or warm-up settings, and ASG activity history. The documented policy uses CPU utilization, with scale-out above 50% and scale-in below 20%. Short CPU spikes may not trigger an immediate action, and a new instance may remain in warm-up while it completes the launch template's user data.

Avoid manually terminating instances to test recovery unless you have confirmed the ASG is attached to the correct subnets and target group. Otherwise, the test can hide a configuration problem rather than demonstrate self-healing.

## Failed Instance Is Not Replaced

The expected recovery path is: target health fails, the ALB stops routing to that target, and the ASG launches a replacement. Check:

1. The instance is managed by the ASG rather than manually registered only in the target group.
2. The ASG desired capacity is at least 2 and its subnets span both Availability Zones.
3. The ASG activity history contains a replacement attempt and a useful failure reason.
4. The launch template still references a valid Ubuntu AMI, security group, key pair, and user data.
5. The replacement can reach the package repositories and complete `/var/log/userdata-log.txt`.

An instance that is merely unhealthy in the target group may be removed from traffic without being replaced unless the ASG's health-check type and grace period are configured to use the intended health signal.

## Safe Recovery Checklist

Before changing resources, save the target health reason, ASG activity history, user data log, and relevant CloudWatch time range. Then:

- Correct the listener, target group, route, security-group, or launch-template setting that caused the failure.
- Recheck `/health` locally and through the ALB.
- Confirm both targets return to `healthy` before testing scaling again.
- For a failed launch, create a new launch-template version and update the ASG only after validating it with one instance.
- Do not reduce the ASG below 2 during normal operation; that removes the project's multi-AZ availability baseline.

## Validation After a Fix

1. Open the ALB DNS name and confirm an HTTP 200 response.
2. Refresh several times and verify the instance metadata changes between healthy targets.
3. Confirm both targets are healthy in the target group.
4. Review ASG capacity and activity history.
5. Check CloudWatch CPU metrics and confirm no new Apache or user-data errors appear.
