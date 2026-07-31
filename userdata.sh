#!/bin/bash
# User Data Script for EC2 Instance
# Installs Apache2 and deploys a web application page
# Executed on instance launch via Launch Template

set -e  # Exit on any error

# Log all output for debugging
exec > >(tee /var/log/userdata-log.txt)
exec 2>&1

echo "=========================================="
echo "Starting User Data Script Execution"
echo "Timestamp: $(date)"
echo "=========================================="

# 1. Update system packages
echo "[STEP 1] Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y apache2 curl apache2-utils

# 2. Install Apache2 web server
echo "[STEP 2] Installing Apache2..."

# 3. Enable Apache modules for better performance
echo "[STEP 3] Enabling Apache modules..."
a2enmod rewrite
a2enmod headers
a2enmod deflate

# 4. Create custom HTML page with instance metadata
echo "[STEP 4] Creating custom HTML page..."

# Get instance metadata. Support both IMDSv2 and instances that still allow IMDSv1.
METADATA_URL="http://169.254.169.254/latest/meta-data"
METADATA_TOKEN=$(curl -fsS --max-time 5 -X PUT \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
    http://169.254.169.254/latest/api/token || true)

metadata_get() {
    local path="$1"

    if [ -n "$METADATA_TOKEN" ]; then
        curl -fsS --max-time 5 -H "X-aws-ec2-metadata-token: $METADATA_TOKEN" \
            "$METADATA_URL/$path" || printf 'unavailable'
    else
        curl -fsS --max-time 5 "$METADATA_URL/$path" || printf 'unavailable'
    fi
}

INSTANCE_ID=$(metadata_get instance-id)
AVAILABILITY_ZONE=$(metadata_get placement/availability-zone)
PRIVATE_IP=$(metadata_get local-ipv4)
AWS_REGION=$(metadata_get placement/region)
INSTANCE_TYPE=$(metadata_get instance-type)
LAUNCH_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create the HTML file
cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AWS Load Balancer & Auto Scaling Project</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }

        .container {
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.3);
            padding: 40px;
            max-width: 600px;
            width: 100%;
            text-align: center;
        }

        .header {
            color: #667eea;
            margin-bottom: 30px;
        }

        h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }

        .subtitle {
            color: #764ba2;
            font-size: 1.2em;
            font-weight: 300;
            margin-bottom: 20px;
        }

        .status {
            background: #10b981;
            color: white;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
            font-weight: bold;
            font-size: 1.1em;
        }

        .info-section {
            background: #f3f4f6;
            border-left: 4px solid #667eea;
            padding: 20px;
            margin: 20px 0;
            text-align: left;
            border-radius: 5px;
        }

        .info-section h3 {
            color: #667eea;
            margin-bottom: 15px;
            font-size: 1.2em;
        }

        .info-item {
            display: flex;
            justify-content: space-between;
            padding: 8px 0;
            border-bottom: 1px solid #e5e7eb;
        }

        .info-item:last-child {
            border-bottom: none;
        }

        .info-label {
            font-weight: bold;
            color: #374151;
            min-width: 150px;
            text-align: left;
        }

        .info-value {
            color: #764ba2;
            font-family: 'Courier New', monospace;
            word-break: break-all;
        }

        .footer {
            margin-top: 30px;
            color: #9ca3af;
            font-size: 0.9em;
        }

        .badge {
            display: inline-block;
            background: #667eea;
            color: white;
            padding: 5px 10px;
            border-radius: 20px;
            margin: 5px;
            font-size: 0.85em;
        }

        .architecture-info {
            background: #ede9fe;
            border: 2px dashed #667eea;
            padding: 15px;
            margin: 20px 0;
            border-radius: 5px;
            font-size: 0.9em;
        }

        @media (max-width: 600px) {
            .container {
                padding: 20px;
            }

            h1 {
                font-size: 1.8em;
            }

            .info-item {
                flex-direction: column;
            }

            .info-label {
                margin-bottom: 5px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>◈҈ AWS Load Balancer & Auto Scaling Project</h1>
            <p class="subtitle">High Availability & Auto Scaling on AWS</p>
        </div>

        <div class="status">✅ Web Server is Running Successfully</div>

        <div class="info-section">
            <h3>📊 Instance Information</h3>
            <div class="info-item">
                <span class="info-label">Instance ID:</span>
                <span class="info-value" id="instance-id">Loading...</span>
            </div>
            <div class="info-item">
                <span class="info-label">Instance Type:</span>
                <span class="info-value" id="instance-type">Loading...</span>
            </div>
            <div class="info-item">
                <span class="info-label">Availability Zone:</span>
                <span class="info-value" id="az">Loading...</span>
            </div>
            <div class="info-item">
                <span class="info-label">Private IP:</span>
                <span class="info-value" id="private-ip">Loading...</span>
            </div>
            <div class="info-item">
                <span class="info-label">AWS Region:</span>
                <span class="info-value" id="region">Loading...</span>
            </div>
            <div class="info-item">
                <span class="info-label">Launch Time:</span>
                <span class="info-value" id="launch-time">Loading...</span>
            </div>
        </div>

        <div class="info-section">
            <h3>🏗️ Architecture</h3>
            <div class="architecture-info">
                <strong>Multi-AZ Deployment:</strong><br>
                Application Load Balancer → Target Group → Auto Scaling Group<br><br>
                <strong>High Availability Features:</strong><br>
                ✅ Health Checks (30s intervals)<br>
                ✅ Automatic Failover<br>
                ✅ Auto Scaling (CPU-based)<br>
                ✅ Load Balancing
            </div>
        </div>

        <div class="info-section">
            <h3>🚀 Technologies</h3>
            <div style="text-align: center;">
                <span class="badge">AWS EC2</span>
                <span class="badge">ALB</span>
                <span class="badge">ASG</span>
                <span class="badge">CloudWatch</span>
                <span class="badge">Apache2</span>
                <span class="badge">Multi-AZ</span>
            </div>
        </div>

        <div class="footer">
            <p>Server responded from instance running Apache2</p>
            <p>Refresh to see load balancing in action</p>
            <p>© 2026 AWS High Availability Project</p>
        </div>
    </div>

    <script>
        // Inject instance metadata from server
        document.getElementById('instance-id').textContent = 'INSTANCE_ID_PLACEHOLDER';
        document.getElementById('instance-type').textContent = 'INSTANCE_TYPE_PLACEHOLDER';
        document.getElementById('az').textContent = 'AZ_PLACEHOLDER';
        document.getElementById('private-ip').textContent = 'PRIVATE_IP_PLACEHOLDER';
        document.getElementById('region').textContent = 'REGION_PLACEHOLDER';
        document.getElementById('launch-time').textContent = 'LAUNCH_TIME_PLACEHOLDER';
    </script>
</body>
</html>
EOF

# Replace placeholders with actual values
sed -i "s/INSTANCE_ID_PLACEHOLDER/$INSTANCE_ID/g" /var/www/html/index.html
sed -i "s/INSTANCE_TYPE_PLACEHOLDER/$INSTANCE_TYPE/g" /var/www/html/index.html
sed -i "s/AZ_PLACEHOLDER/$AVAILABILITY_ZONE/g" /var/www/html/index.html
sed -i "s/PRIVATE_IP_PLACEHOLDER/$PRIVATE_IP/g" /var/www/html/index.html
sed -i "s/REGION_PLACEHOLDER/$AWS_REGION/g" /var/www/html/index.html
sed -i "s/LAUNCH_TIME_PLACEHOLDER/$LAUNCH_TIME/g" /var/www/html/index.html

# 5. Configure Apache for performance
echo "[STEP 5] Configuring Apache2 for optimal performance..."

# Enable gzip compression
cat > /etc/apache2/mods-enabled/deflate.conf << 'APACHE_CONFIG'
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css text/javascript application/javascript
    DeflateCompressionLevel 6
</IfModule>
APACHE_CONFIG

# Set keep-alive and timeout without allowing the KeepAlive rule to match
# KeepAliveTimeout.
sed -i -E 's/^[[:space:]]*KeepAliveTimeout[[:space:]].*/KeepAliveTimeout 5/' /etc/apache2/apache2.conf
sed -i -E 's/^[[:space:]]*KeepAlive[[:space:]]+(On|Off).*/KeepAlive On/' /etc/apache2/apache2.conf

# 6. Create a health check endpoint
echo "[STEP 6] Creating health check endpoint..."
cat > /var/www/html/health << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Health Check</title></head>
<body>OK</body>
</html>
EOF

# 7. Set proper file permissions
echo "[STEP 7] Setting file permissions..."
chmod -R 755 /var/www/html
chown -R www-data:www-data /var/www/html

# 8. Test Apache configuration
echo "[STEP 8] Testing Apache configuration..."
apache2ctl configtest

# 9. Start and enable Apache2
echo "[STEP 9] Starting Apache2 service..."
systemctl start apache2
systemctl enable apache2

# 10. Verify Apache is running
echo "[STEP 10] Verifying Apache2 is running..."
systemctl status apache2

# 11. Create system metrics collection script
echo "[STEP 11] Setting up system monitoring..."
cat > /usr/local/bin/collect-metrics.sh << 'METRICS_SCRIPT'
#!/bin/bash
# Collect and log system metrics
while true; do
    echo "$(date): CPU=$(top -b -n 1 | grep Cpu | awk '{print $2}') Memory=$(free | grep Mem | awk '{print $3/$2 * 100}')%" >> /var/log/system-metrics.log
    sleep 300  # Collect every 5 minutes
done
METRICS_SCRIPT

chmod +x /usr/local/bin/collect-metrics.sh

# 12. Final logging
echo "[STEP 12] User Data script execution completed successfully!"
echo "=========================================="
echo "Summary:"
echo "- Apache2: INSTALLED and RUNNING ✅"
echo "- Instance ID: $INSTANCE_ID"
echo "- Availability Zone: $AVAILABILITY_ZONE"
echo "- Private IP: $PRIVATE_IP"
echo "- Region: $AWS_REGION"
echo "- Instance Type: $INSTANCE_TYPE"
echo "=========================================="

# 13. Notify that instance is ready
echo "Instance is ready to serve traffic!"
