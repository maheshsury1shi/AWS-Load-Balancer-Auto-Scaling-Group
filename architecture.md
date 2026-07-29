# AWS Architecture Deep Dive

This document captures the four architecture views used by this project:
1. the full architecture diagram,
2. the request flow,
3. the Auto Scaling workflow,
4. the high availability workflow.

## 1) Full Architecture Diagram

```text
                                      Internet
                                          │
                                          │
                               HTTP / HTTPS (80/443)
                                          │
                                          ▼
                      ┌─────────────────────────────────┐
                      │  Application Load Balancer      │
                      │             (ALB)               │
                      └───────────────┬─────────────────┘
                                      │
                         Routes Traffic to Healthy Targets
                                      │
                                      ▼
                      ┌─────────────────────────────────┐
                      │          Target Group           │
                      │      Health Check: HTTP :80     │
                      └───────────────┬─────────────────┘
                                      │
                  ┌───────────────────┴───────────────────┐
                  │                                       │
                  ▼                                       ▼
        ┌─────────────────────┐                ┌─────────────────────┐
        │     EC2 Instance 1  │                │     EC2 Instance 2  │
        │ Ubuntu + Apache     │                │ Ubuntu + Apache     │
        │ Public Subnet (AZ-A)│                │ Public Subnet (AZ-B)│
        └──────────┬──────────┘                └──────────┬──────────┘
                   ▲                                      ▲
                   │                                      │
                   └──────────────┬───────────────────────┘
                                  │
                      ┌────────────────────────────┐
                      │   Auto Scaling Group       │
                      │ Min: 2  Desired: 2  Max: 4 │
                      └──────────────┬─────────────┘
                                     │
                          Uses Launch Template
                                     │
                                     ▼
                      ┌────────────────────────────┐
                      │      Launch Template       │
                      │ - Amazon Machine Image     │
                      │ - Instance Type            │
                      │ - Security Group           │
                      │ - User Data Script         │
                      └──────────────┬─────────────┘
                                     │
                                     ▼
                      ┌────────────────────────────┐
                      │     Amazon Machine Image   │
                      └────────────────────────────┘

                    Amazon CloudWatch Monitoring
                             │
                             ▼
              CPU Utilization → Auto Scaling Policies
```

Short explanation: This is the overall system view showing the public entry point, the target group, the two web servers, the scaling layer, and the monitoring layer.

## 2) Request Flow

```text
User
  │
  ▼
Application Load Balancer
  │
  ▼
Target Group
  │
  ├────────► EC2 Instance 1
  │
  └────────► EC2 Instance 2
                │
                ▼
          Apache Web Server
                │
                ▼
          HTML Response
```

Short explanation: This diagram shows the path of a user request from the internet to the web servers and back to the user.

## 3) Auto Scaling Workflow

```text
CloudWatch
     │
     ▼
Monitor CPU Utilization
     │
     ▼
CPU > 50% ?
     │
 ┌───┴────┐
 │  Yes   │
 ▼        │
Launch New EC2
 │
 ▼
Register with Target Group
 │
 ▼
ALB Starts Routing Traffic
```

Short explanation: This flow shows how CloudWatch metrics trigger scale-out actions when CPU is high.

## 4) High Availability Workflow

```text
EC2 Instance Failure
        │
        ▼
Health Check Fails
        │
        ▼
Target Group Marks Instance Unhealthy
        │
        ▼
ALB Stops Sending Traffic
        │
        ▼
Auto Scaling Group Launches New EC2
        │
        ▼
Instance Passes Health Check
        │
        ▼
ALB Resumes Traffic Routing
```

Short explanation: This diagram highlights self-healing behavior. When one web server fails, the ALB stops sending traffic to it and the ASG replaces it automatically.

## Design Summary

- The ALB is the public entry point.
- The target group routes requests to healthy web servers.
- Two instances are deployed in different public subnets for availability.
- The ASG keeps the environment scalable and resilient.
- CloudWatch provides the monitoring signal for scaling decisions.
