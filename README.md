# 🚀 AWS Load Balancer & Auto Scaling Group | High Availability on AWS

A production-style AWS architecture project demonstrating how to build a resilient, highly available web application using Application Load Balancer, EC2, Auto Scaling Group, Target Groups, Launch Templates, and CloudWatch.

![AWS](https://img.shields.io/badge/AWS-Cloud%20Architecture-FF9900?logo=amazonaws)
![Load Balancer](https://img.shields.io/badge/Service-ALB%20%2B%20ASG-4A90E2)
![Auto Scaling](https://img.shields.io/badge/Scaling-Auto%20Scaling-2E8555)
![DevOps](https://img.shields.io/badge/Focus-High%20Availability-8A2BE2)

## 📑 Table of Contents

- [🚀 AWS Load Balancer \& Auto Scaling Group | High Availability on AWS](#-aws-load-balancer--auto-scaling-group--high-availability-on-aws)
  - [📑 Table of Contents](#-table-of-contents)
  - [🧭 Project Overview](#-project-overview)
  - [🎯 Problem Statement](#-problem-statement)
  - [🛠️ Solution Overview](#️-solution-overview)
  - [🏗️ Architecture Diagram](#️-architecture-diagram)
    - [ASCII Diagram](#ascii-diagram)
    - [Mermaid Diagram](#mermaid-diagram)
  - [☁️ AWS Services Used](#️-aws-services-used)
  - [✨ Key Features](#-key-features)
  - [🧩 Architecture Components](#-architecture-components)
  - [🔄 Project Workflow](#-project-workflow)
  - [🚀 Deployment Steps](#-deployment-steps)
  - [📁 Project Structure](#-project-structure)
  - [🧪 Testing \& Validation](#-testing--validation)
  - [📸 Screenshots](#-screenshots)
  - [⚠️ Challenges \& Solutions](#️-challenges--solutions)
  - [🎓 Learning Outcomes](#-learning-outcomes)
  - [Author](#author)
  - [📄 License](#-license)

## 🧭 Project Overview

This repository showcases an AWS-based web architecture designed for availability, scalability, and fault tolerance. The solution uses an internet-facing Application Load Balancer to distribute traffic across healthy EC2 instances hosted in multiple Availability Zones.

> [!NOTE]
> This project is ideal for recruiters, hiring managers, and interview discussions because it demonstrates real-world cloud design thinking around resilience, scalability, and operational reliability.

## 🎯 Problem Statement

A single-instance web application is vulnerable to:

- traffic spikes and performance degradation,
- single points of failure,
- limited recovery during instance failures,
- poor scalability under increasing demand.

The goal is to design a solution that remains available and responsive even during load increases or EC2 failures.

## 🛠️ Solution Overview

The solution introduces a layered AWS architecture:

- a VPC with two public subnets in separate Availability Zones,
- an Internet Gateway and public route table to provide internet access,
- an Application Load Balancer as the public entry point,
- a Target Group to route traffic to healthy instances,
- two EC2 instances deployed in separate Availability Zones,
- an Auto Scaling Group to dynamically maintain capacity,
- CloudWatch to monitor performance and trigger scaling actions.

## 🏗️ Architecture Diagram

### ASCII Diagram

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

### Mermaid Diagram

```mermaid
flowchart TD
    User[Internet User] --> ALB[Application Load Balancer]
    ALB --> TG[Target Group]
    TG --> EC1[EC2 Instance 1]
    TG --> EC2[EC2 Instance 2]
    EC1 --> ASG[Auto Scaling Group]
    EC2 --> ASG
    ASG --> LT[Launch Template]
    LT --> AMI[Amazon Machine Image]
    EC1 --> CW[CloudWatch]
    EC2 --> CW
    CW --> SCALE[Scaling Policies]
```

## ☁️ AWS Services Used

| Service | Purpose |
|---|---|
| Amazon VPC | Provides the isolated network boundary for the deployment |
| Internet Gateway | Enables internet access for the public subnets |
| Route Table | Directs traffic between subnets and the internet gateway |
| Public Subnets | Hosts the ALB and EC2 instances across two Availability Zones |
| Application Load Balancer | Distributes inbound traffic to healthy targets |
| EC2 | Hosts the web application across multiple instances |
| Target Group | Maintains healthy instance routing and health checks |
| Auto Scaling Group | Automatically adjusts capacity based on demand |
| Launch Template | Defines instance configuration for scaling |
| Amazon Machine Image | Provides the base image for new instances |
| CloudWatch | Monitors metrics and triggers scaling decisions |
| Security Group | Controls inbound and outbound traffic |

## ✨ Key Features

- High availability across multiple Availability Zones
- Load balancing for efficient traffic distribution
- Auto scaling for dynamic capacity management
- Health-based routing through Target Groups
- Monitoring and alerting through CloudWatch
- Modular architecture suitable for interviews and portfolio presentation

## 🧩 Architecture Components

- VPC: provides the isolated network environment
- Internet Gateway: allows public access to the web tier
- Route Table: controls traffic flow to and from the internet
- Public Subnets: place the ALB and app instances across two Availability Zones
- Application Load Balancer: entry point for public access
- Target Group: manages healthy backend instances
- EC2 Instances: run the application and web services
- Auto Scaling Group: scales up or down based on metrics
- Launch Template: standardizes new instance creation
- CloudWatch: observes CPU and performance trends

## 🔄 Project Workflow

1. User sends requests to the Application Load Balancer.
2. The ALB routes traffic to healthy EC2 instances in the Target Group.
3. CloudWatch monitors CPU utilization and health signals.
4. The Auto Scaling Group adds or removes instances as needed.
5. New instances are created from the Launch Template and AMI.

## 🚀 Deployment Steps

1. Create a VPC and provision two public subnets in different Availability Zones.
2. Attach an Internet Gateway and add a default route in the public route table.
3. Create security groups with least-privilege rules: ALB allows 80/443 from the internet, EC2 allows 80 from the ALB security group, and SSH from a trusted IP.
4. Launch EC2 instances, install Apache using the user data script, and register them with the target group.
5. Create an internet-facing Application Load Balancer and attach the target group.
6. Configure health checks on the target group.
7. Create an Auto Scaling Group using the Launch Template and connect CloudWatch metrics to scaling policies.

> [!TIP]
> For production-style deployments, keep security groups minimal and avoid exposing the web servers directly to the internet.

<details>
<summary>View deployment notes</summary>

- Use a simple web server such as Apache or Nginx on the EC2 instances.
- Ensure the health check path returns success for the ALB to route traffic correctly.
- Validate that instances are registered and passing health checks before production use.

</details>

## 📁 Project Structure

```text
AWS-Load-Balancer-Auto-Scaling-Group/
├── README.md
├── architecture.md
├── deployment-guide.md
├── troubleshooting.md
├── userdata.sh
├── LICENSE
├── architecture images/
└── Images/
```

## 🧪 Testing & Validation

| Test | What to Validate | Expected Result |
|---|---|---|
| Load Balancer Test | Access the public ALB endpoint | Traffic is distributed successfully |
| Target Group Health Check | Verify instance health status | Targets show healthy state |
| Auto Scaling Test | Increase load or CPU usage | New EC2 instances are launched |
| Instance Recovery Test | Stop or fail one instance | Replacement instance is launched automatically |

## 📸 Screenshots

The repository includes real AWS console screenshots that illustrate the deployment and monitoring workflow:

- [Architecture Overview](architecture%20images/Architecture-Diagram-Complete-Flow.png)
- [Apache Service Status](Images/01-Terminal-Apache-Service-Status.png)
- [Target Group Health](Images/02-TargetGroup-Web-TG-Healthy-Instances.png)
- [Auto Scaling Capacity](Images/03-ASG-Capacity-Overview.png)
- [Scaling Events](Images/04-ASG-Activity-History-Scaling-Events.png)
- [CloudWatch Metrics](Images/06-CloudWatch-CPU-Utilization-Metrics.png)

## ⚠️ Challenges & Solutions

| Challenge | Solution |
|---|---|
| Single point of failure | Introduced multi-instance architecture with ALB |
| Traffic spikes | Added Auto Scaling Group for dynamic capacity |
| Instance failure impact | Used health checks and replacement automation |
| Operational visibility | Integrated CloudWatch monitoring |

## 🎓 Learning Outcomes

- Stronger understanding of AWS high-availability design
- Practical exposure to load balancing and fault tolerance
- Improved ability to explain cloud architecture in interviews
- Better appreciation of monitoring and scaling strategies

# Author

Mahesh Suryawanshi 

https://www.linkedin.com/in/maheshsury1shi/

maheshsury1shi@gmail.com

## 📄 License

This project is licensed under the MIT License.
