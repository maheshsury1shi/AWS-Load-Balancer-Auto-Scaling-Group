# Deployment Guide

This deployment guide follows the architecture shown in the diagrams: an internet-facing ALB fronts two EC2 instances in public subnets, an Auto Scaling Group maintains capacity, and CloudWatch monitors CPU utilization.

## Step 1: Create the Network Foundation
- Create a VPC for the application.
- Create two public subnets in different Availability Zones.
- Create an Internet Gateway and attach it to the VPC.
- Create a public route table with a default route to the Internet Gateway.
- Associate both public subnets with the public route table.

## Step 2: Create Security Groups
- Create an ALB security group that allows inbound TCP 80 and 443 from 0.0.0.0/0.
- Create an EC2 security group that allows inbound TCP 80 from the ALB security group and TCP 22 from your trusted IP only.
- Keep access rules minimal and follow least-privilege principles.

## Step 3: Create a Launch Template
- Use an Ubuntu-based AMI.
- Configure instance type, security group, and user data script.
- Ensure the user data installs Apache and serves a simple web page.

## Step 4: Create the ALB and Target Group
- Create an internet-facing ALB and attach it to the two public subnets.
- Create a target group for the web instances.
- Configure health checks on HTTP port 80 and ensure the health path returns success.

## Step 5: Launch the EC2 Instances
- Launch two EC2 instances into the two public subnets.
- Register both instances with the target group.

## Step 6: Create the Auto Scaling Group
- Set Min: 2, Desired: 2, Max: 4.
- Use the launch template.
- Attach the target group.

## Step 7: Configure CloudWatch Scaling
- Monitor CPU utilization.
- Create a target-tracking policy to scale out when CPU exceeds 50% and scale in when it drops below 20%.
