# 🚀 AWS Load Balancer & Auto Scaling Group (ALB + ASG)

**Production-Grade High Availability Infrastructure on AWS**

[![AWS](https://img.shields.io/badge/AWS-Cloud-FF9900?style=flat-square&logo=amazon-aws)](https://aws.amazon.com/)
[![EC2](https://img.shields.io/badge/EC2-Compute-FF9900?style=flat-square)](https://aws.amazon.com/ec2/)
[![ALB](https://img.shields.io/badge/ALB-Load%20Balancer-FF9900?style=flat-square)](https://aws.amazon.com/elasticloadbalancing/)
[![ASG](https://img.shields.io/badge/ASG-Auto%20Scaling-FF9900?style=flat-square)](https://aws.amazon.com/autoscaling/)
[![CloudWatch](https://img.shields.io/badge/CloudWatch-Monitoring-FF9900?style=flat-square)](https://aws.amazon.com/cloudwatch/)
[![Status](https://img.shields.io/badge/Status-Production%20Ready-brightgreen?style=flat-square)](deployment-guide.md)
[![Availability](https://img.shields.io/badge/Availability-99.99%25-success?style=flat-square)](#-performance-metrics)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)

---

## 📚 Table of Contents

- [Overview](#-overview)
- [Key Features](#-key-features)
- [Architecture](#-architecture)
- [Quick Start](#-quick-start)
- [Documentation Map](#-documentation-map)
- [Technology Stack](#-technology-stack)
- [Performance Metrics](#-performance-metrics)
- [File Structure](#-file-structure)
- [Support & Resources](#-support--resources)

---

## 🎯 Overview

This project is an AWS-based implementation of a **highly available web application** built with EC2, an Application Load Balancer, Target Groups, a Launch Template, and an Auto Scaling Group. The design is intended to support traffic distribution, health-based routing, and automatic replacement of unhealthy instances.

**What it does:**
- 🔄 **Distributes traffic** across multiple servers using an Application Load Balancer
- 📈 **Scales up/down** based on CPU usage (as configured in the design)
- 🏥 **Supports self-healing behavior** through health checks and instance replacement
- 🌍 **Uses a multi-AZ layout** for resilience
- 📊 **Includes CloudWatch-based monitoring** for scaling decisions

> Accuracy note: this project includes documented architecture and deployment steps. Any live AWS values shown in the examples (such as DNS names, instance IDs, or performance numbers) should be verified against your own AWS account and deployment state.

---

## ⭐ Key Features

| Feature | Benefit |
|---------|---------|
| **Multi-AZ Deployment** | Survives availability zone failure |
| **Auto Scaling (2-4 instances)** | Automatically handles traffic spikes |
| **Health Checks (30s)** | Failed instances replaced in < 1 minute |
| **Load Balancing** | Traffic evenly distributed |
| **CloudWatch Monitoring** | Real-time metrics and alerts |
| **Connection Draining** | Zero-downtime deployments |
| **Custom AMI** | Consistent configuration across instances |

---

## 🏗️ Architecture

### Complete System Architecture (ASCII Diagram)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              🌐 INTERNET                                    │
│                         (External Users/Requests)                           │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │
                                   │ HTTP:80
                                   │
                    ┌──────────────▼──────────────┐
                    │   📊 APPLICATION LOAD       │
                    │     BALANCER (ALB)          │
                    │  ✓ web-ASG (Active)         │
                    │  ✓ Internet-Facing          │
                    │  ✓ Multi-AZ Distribution    │
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │    🏥 HEALTH CHECKS         │
                    │  ✓ Every 30 seconds         │
                    │  ✓ Matcher: 200-299         │
                    │  ✓ Auto Remove Unhealthy    │
                    └──────────────┬──────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │    🎯 TARGET GROUP          │
                    │     (Web-TG)                │
                    │  ✓ Protocol: HTTP:80        │
                    │  ✓ 2/2 Instances Healthy    │
                    └──────────────┬──────────────┘
                                   │
                 ┌─────────────────┴─────────────────┐
                 │                                   │
    ┌────────────▼───────────────┐    ┌────────────▼───────────────┐
    │  💻 EC2 INSTANCE #1        │    │  💻 EC2 INSTANCE #2        │
    │  ✓ us-east-1a              │    │  ✓ us-east-1b              │
    │  ✓ t3.micro                │    │  ✓ t3.micro                │
    │  ✓ Ubuntu Linux            │    │  ✓ Ubuntu Linux            │
    │  ✓ Apache2 (Port 80)       │    │  ✓ Apache2 (Port 80)       │
    │  ✓ Running & Healthy       │    │  ✓ Running & Healthy       │
    │  ✓ 2-4% CPU avg            │    │  ✓ 2-4% CPU avg            │
    └────────────┬───────────────┘    └────────────┬───────────────┘
                 │                                   │
                 └─────────────────┬─────────────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │  📦 AUTO SCALING GROUP      │
                    │   (Apache-ASG)              │
                    │  ✓ Min: 2 | Desired: 2      │
                    │  ✓ Max: 4 instances         │
                    │  ✓ Multi-AZ Distribution    │
                    └──────────────┬──────────────┘
                                   │
                 ┌─────────────────┴─────────────────┐
                 │                                   │
    ┌────────────▼───────────────┐    ┌────────────▼───────────────┐
    │  🎨 LAUNCH TEMPLATE        │    │  📸 CONNECTION DRAINING    │
    │  (Apache-Template)         │    │  ✓ 300 seconds timeout     │
    │  ✓ AMI: Apache-Web-AMI     │    │  ✓ Graceful shutdown       │
    │  ✓ Instance Type: t3.micro │    │  ✓ Zero-downtime deploy    │
    │  ✓ Auto-configures Apache  │    │  ✓ Active connections OK   │
    │  ✓ User Data: Install+Run  │    │                            │
    └────────────┬───────────────┘    └────────────────────────────┘
                 │
    ┌────────────▼───────────────┐
    │  📊 CLOUDWATCH MONITORING  │
    │  ✓ CPU Utilization Metric  │
    │  ✓ 60-second intervals      │
    │  ✓ Real-time tracking       │
    │  ✓ Custom alarms enabled    │
    └────────────┬───────────────┘
                 │
    ┌────────────▼───────────────────────────────┐
    │  🔄 SCALING POLICY (CPU-Target-Tracking)   │
    │  ┌─────────────────────────────────────┐   │
    │  │ IF CPU > 50%  → SCALE OUT (+1)      │   │
    │  │ IF CPU < 50%  → SCALE IN  (-1)      │   │
    │  │ Min: 2 instances always running     │   │
    │  │ Max: 4 instances limit              │   │
    │  │ Cooldown: 60s (out) / 300s (in)     │   │
    │  └─────────────────────────────────────┘   │
    └────────────────────────────────────────────┘
```

**Architecture Flow:**
1. Users send HTTP requests to ALB
2. ALB performs health checks on instances
3. Traffic routed to healthy instances only
4. CloudWatch monitors CPU utilization
5. Auto Scaling automatically adds/removes instances based on demand

---

## 🚀 Quick Start

### Prerequisites
```bash
# AWS Account with CLI configured
aws configure

# Verify AWS CLI
aws sts get-caller-identity
```

### Deploy in 5 Minutes

```bash
# 1. Clone the project
git clone https://github.com/maheshsury1shi/AWS-Load-Balancer-Auto-Scaling-Group.git
cd AWS-Load-Balancer-Auto-Scaling-Group

# 2. Follow the steps in deployment-guide.md to create the VPC, subnets, security groups,
#    launch template, ALB, target group, ASG, and scaling policy.

# 3. Access the application once the ALB DNS name is available
curl http://<your-alb-dns-name>
```

---

## 📋 Documentation Map

| Document | Purpose | For Whom |
|----------|---------|----------|
| [deployment-guide.md](deployment-guide.md) | Step-by-step AWS setup | DevOps Engineers |
| [architecture.md](architecture.md) | Deep-dive into system design | Architects |
| [ARCHITECTURE_ALIGNMENT.md](ARCHITECTURE_ALIGNMENT.md) | Relationship between design and implementation | Reviewers |
| [troubleshooting.md](troubleshooting.md) | Common problems & solutions | Operators |
| [VISUAL_ARCHITECTURE_GUIDE.md](VISUAL_ARCHITECTURE_GUIDE.md) | Layer-by-layer explanation | Learners |
| [userdata.sh](userdata.sh) | EC2 initialization script | DevOps/SRE |

**🔥 Start Here:** First-time users should read [deployment-guide.md](deployment-guide.md) and [architecture.md](architecture.md).

---

## 🛠️ Technology Stack

### Cloud Services
```
AWS
├── EC2 (Compute)
├── Application Load Balancer (Traffic Distribution)
├── Auto Scaling Group (Capacity Management)
├── CloudWatch (Monitoring & Alerts)
├── VPC (Networking)
└── Security Groups (Firewall)
```

### Application Stack
```
├── Web Server: Apache2 (HTTP)
├── OS: Ubuntu Linux (x86_64)
├── Scripting: Bash (User Data)
├── Frontend: HTML5 + CSS3
├── Version Control: Git
└── IaC: Terraform (optional)
```

### Configuration
```
Instance Type: t3.micro (cost-optimized)
Region: N. Virginia (us-east-1)
Availability Zones: 2 (us-east-1a, us-east-1b)
Min Instances: 2 | Max Instances: 4
CPU Scaling Target: 50%
Health Check: HTTP 200-299 (30s interval)
```

---

## 📊 Performance Metrics

### Example / Expected Metrics

The values below are illustrative examples used in the documentation. They should be validated against your own AWS deployment and the current time window.

| Metric | Example Value | Notes |
|--------|-------|--------|
| **Availability target** | 99.99% | Design target for a highly available setup |
| **Instance Count** | 2/2 healthy | Example state for a balanced deployment |
| **Average CPU** | 2-4% | Typical idle-state example |
| **Response Time** | ~100-200ms | Example benchmark only |
| **Scaling Cooldown** | 60s (scale out) / 300s (scale in) | Configured as part of the example design |

### Scaling Scenarios

**High Load (CPU > 50%):**
- Action: Scale OUT
- Result: New instance launches in 5-7 seconds
- Cost: +~$15/month per instance

**Low Load (CPU < 50%):**
- Action: Scale IN (with 300s cooldown)
- Result: Instance terminates gracefully
- Cost: Saves ~$15/month per instance

---

## 📁 File Structure

```
.
├── README.md                              # This file
├── deployment-guide.md                    # Complete AWS setup guide
├── architecture.md                        # Technical deep-dive
├── ARCHITECTURE_ALIGNMENT.md              # Design-to-implementation alignment notes
├── troubleshooting.md                     # Common issues & fixes
├── VISUAL_ARCHITECTURE_GUIDE.md           # Visual architecture breakdown
│
├── userdata.sh                            # EC2 initialization script
│
├── Images/                                # AWS screenshots and supporting visuals
└── architecture images/                   # Architecture diagram assets
```

**Total Documentation:** 13,000+ lines  
**Total Files:** 16+ files

---

## ❌ Problem We're Solving

**Traditional single-server architecture has problems:**

| Problem | Impact | Our Solution |
|---------|--------|--------------|
| Single point of failure | Outage if server down | Multi-AZ deployment |
| No auto-scaling | Can't handle traffic spikes | CPU-based auto-scaling |
| Manual management | Requires DevOps intervention | Fully automated |
| No health checks | Failed instances serve requests | Health checks every 30s |
| No load distribution | Bottleneck on single server | ALB distributes traffic |

---

## ✅ How We Solve It

```
Problem              Solution                 AWS Service
─────────────────────────────────────────────────────────
Single point of      Deploy in 2 AZs         EC2 + VPC
failure              

No auto-scaling      Monitor CPU → Scale    CloudWatch + ASG

Manual               Automated scaling       ASG Policies
management           & replacement           

No health checks     30-second checks       ALB Target Group

No load              Intelligent            Application Load
distribution         distribution            Balancer
```

---

## 🎓 Learning Outcomes

After completing this project, you'll understand:

✅ **AWS Architecture:**
- How to design highly available systems
- Multi-AZ deployment patterns
- Load balancing strategies

✅ **Auto Scaling:**
- Target tracking policies
- Scaling cooldowns
- Warm-up periods

✅ **Monitoring:**
- CloudWatch metrics
- Custom alarms
- Autoscaling behavior

✅ **DevOps:**
- Infrastructure as Code concepts
- Deployment strategies
- Health check design

✅ **Networking:**
- VPC setup and routing
- Security groups
- NAT gateways

---

## 📈 Capacity Planning

| Scenario | Instances | Est. Cost/Month | Capacity |
|----------|-----------|-----------------|----------|
| Baseline | 2 | ~$45 | ~100 req/sec |
| High Load | 3-4 | ~$60-75 | ~150-200 req/sec |
| Peak | 4 | ~$90 | ~200 req/sec |

---

## 🔧 Common Commands

### View Application
```bash
# Access the web server
curl web-asg-1392539259.us-east-1.elb.amazonaws.com

# Check health
curl -I web-asg-1392539259.us-east-1.elb.amazonaws.com
```

### AWS CLI Commands
```bash
# List instances in ASG
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names Apache-ASG

# View CloudWatch metrics
aws cloudwatch get-metric-statistics --namespace AWS/EC2 \
  --metric-name CPUUtilization --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T01:00:00Z --period 60 --statistics Average

# Check target group health
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:...

# View ALB configuration
aws elbv2 describe-load-balancers --names web-ASG
```

---

## 🚨 Troubleshooting

**Application not responding?**
→ See [troubleshooting.md](troubleshooting.md)

**Want to scale manually?**
→ See [deployment-guide.md](deployment-guide.md)

**Need architecture details?**
→ See [architecture.md](architecture.md)

---

## 📞 Support & Resources

### Documentation
- 📖 [Complete Deployment Guide](deployment-guide.md)
- 🏗️ [Architecture Documentation](architecture.md)
- 🐛 [Troubleshooting Guide](troubleshooting.md)
- 🧭 [Architecture Alignment Notes](ARCHITECTURE_ALIGNMENT.md)

### AWS Resources
- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
- [Application Load Balancer Guide](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/)
- [Auto Scaling Documentation](https://docs.aws.amazon.com/autoscaling/)
- [CloudWatch User Guide](https://docs.aws.amazon.com/cloudwatch/)

### Learning
- [AWS Well-Architected Framework](https://aws.amazon.com/architecture/well-architected/)
- [AWS Best Practices](https://aws.amazon.com/architecture/security-identity-compliance/)

---

## 📝 Next Steps

1. **Read:** [deployment-guide.md](deployment-guide.md) for the step-by-step setup flow
2. **Deploy:** Create the AWS resources in your own account using the guide
3. **Test:** Load the application and verify health checks and scaling behavior
4. **Learn:** Read [architecture.md](architecture.md) for the deep-dive design
5. **Review:** Check [ARCHITECTURE_ALIGNMENT.md](ARCHITECTURE_ALIGNMENT.md) for design-to-implementation notes

---

## 📊 Project Stats

| Metric | Count |
|--------|-------|
| Documentation Files | 6 main docs |
| AWS Services Covered | 5 core services |
| Architecture Layers | 10 conceptual layers |
| Example Troubleshooting Scenarios | 14 |

---

## 📄 License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file for details.

---

## 🎉 Project Status

✅ Highly Available architecture pattern documented  
✅ Auto-scaling design included  
✅ Health monitoring and failover concepts covered  
✅ Multi-AZ deployment pattern described  
✅ Comprehensive documentation provided  

**Status:** ✨ Documentation and architecture guide ready ✨

---

**Last Updated:** July 27, 2026  
**Version:** 2.0  
**Maintainer:** Mahesh Sury  
**Project:** [maheshsury1shi/AWS-Load-Balancer-Auto-Scaling-Group](https://github.com/maheshsury1shi/AWS-Load-Balancer-Auto-Scaling-Group)
