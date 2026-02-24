# AWS Production Deployment Blueprint (Single VM Hardened)

This document serves as the definitive guide for deploying the hardened Node.js backend to a single AWS EC2 instance. It outlines the complete infrastructure perimeter, including OS hardening, Nginx tuning, PM2 containment, and AWS Security Group discipline.

## 🛡️ 1. AWS Network Perimeter (Security Groups)

Your AWS Security Group is the first true firewall layer.

**Inbound Rules (CRITICAL):**
| Port | Source | Purpose |
| :--- | :--- | :--- |
| **22** | **YOUR_IP_ONLY/32** | SSH Administration |
| **80** | **0.0.0.0/0** | HTTP Redirect to HTTPS |
| **443** | **0.0.0.0/0** | HTTPS API Traffic |

**🚨 NEVER open:**
- `3000`, `4000`, `5000` (Node ports)
- Redis / Database ports

**SSH Hardening:**
After your first login, disable password and root login:
```bash
sudo nano /etc/ssh/sshd_config
# Modify:
# PermitRootLogin no
# PasswordAuthentication no

sudo systemctl restart ssh
```

## 🛡️ 2. EC2 OS Hardening (Ubuntu 22.04 LTS)

**System Updates:**
Keep the system patched.
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install unattended-upgrades
```

**UFW (Uncomplicated Firewall):**
Reinforce the AWS SG at the OS level.
```bash
sudo apt install ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Strict SSH access
sudo ufw allow from YOUR_IP to any port 22
sudo ufw allow 80
sudo ufw allow 443

sudo ufw enable
```

## 🛡️ 3. Nginx Production Config (AWS Edition)

Nginx handles TLS termination, request rate limits, payload size caps, and slow-client drops before traffic ever reaches Node. 

**Main Config (`/etc/nginx/nginx.conf`):**
```nginx
user www-data;
worker_processes auto;
worker_rlimit_nofile 100000;

events {
    worker_connections 4096;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;

    keepalive_timeout 15;
    types_hash_max_size 2048;
    server_tokens off;

    # Payload Caps
    client_max_body_size 10M;
    client_body_timeout 10s;
    client_header_timeout 10s;
    send_timeout 10s;

    # Rate Limiting Zones
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
```

**Site Reverse Proxy (`/etc/nginx/sites-available/backend`):**
```nginx
server {
    listen 80;
    server_name yourdomain.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    add_header Strict-Transport-Security "max-age=63072000" always;

    location /api/ {
        # Strict Rate Limiting
        limit_req zone=api_limit burst=20 nodelay;
        limit_conn conn_limit 20;

        # Localhost bindings!
        proxy_pass http://127.0.0.1:4000;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        proxy_read_timeout 30s;
        proxy_connect_timeout 5s;
    }

    # Hide all other endpoints
    location / {
        return 404;
    }
}
```
Apply config:
```bash
sudo ln -s /etc/nginx/sites-available/backend /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

## 🛡️ 4. Node + PM2 Containment

**1. Binding to Localhost Only**
Ensure `index.js` or `app.listen()` explicitly defines the host:
```javascript
app.listen(4000, '127.0.0.1'); // Never 0.0.0.0
```

**2. PM2 Memory Boundaries**
Start PM2 with strict boundaries so the process gets restarted if an attacker exploits a memory payload issue.
```bash
npm install -g pm2
pm2 start src/index.js --name "og-backend" \
    --max-memory-restart 600M \
    --node-args="--max-old-space-size=512"

pm2 startup
pm2 save
```

## 🛡️ 5. Fail2Ban Integration

Jail abusive IPs who are consistently hitting the Nginx rate limits or tripping our Node `PenaltyBox` 429s.

Install:
```bash
sudo apt install fail2ban
```

**Custom Filter (`/etc/fail2ban/filter.d/nginx-rate-limit.conf`):**
```ini
[Definition]
failregex = <HOST> -.*"(GET|POST).*" 429
```

**Jail Setup (`/etc/fail2ban/jail.local`):**
```ini
[nginx-rate-limit]
enabled = true
filter = nginx-rate-limit
logpath = /var/log/nginx/access.log
maxretry = 20
findtime = 600
bantime = 3600
```
```bash
sudo systemctl restart fail2ban
```

## 🛡️ 6. AWS IAM Discipline
1. Never store secrets directly on the instance code. Use AWS Parameter Store or an un-tracked `.env` file with strict file permissions (`chmod 600 .env`).
2. **EC2 IAM Role:**
   Attach an instance profile role with exact zero-trust permissions.
   For example, if the instance uploads directly to R2/S3, it should only have the `s3:PutObject` permission restricted to the specific bucket ARN.

---

### Realistic Threat Model Conclusion
| Threat Vector | Mitigation Strategy |
| :--- | :--- |
| **SYN Pack Flood** | Stopped gracefully by AWS Shield standard |
| **Large App Payload (OOM)** | Nginx `client_max_body_size` drops it |
| **Slowloris** | Nginx `client_body_timeout 10s` drops connection |
| **Auth Bruteforce** | Node `PenaltyBox` + `Fail2ban` 1-hour jail |
| **Application Memory Leak** | PM2 graceful bounds restart (`--max-memory-restart 600M`) |

*This constitutes the final layer (Layer 5 - Perimeter). The platform is ready for production scaling.*
