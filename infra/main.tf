user_data = <<-USERDATA
              #!/bin/bash
              exec > /var/log/user-data.log 2>&1
              set -ex

              apt-get update -y
              apt-get install -y git curl jq nginx ffmpeg build-essential python3-dev python3 python3-pip python3-venv

              mkdir -p /opt/ai-voice-assistant
              git clone ${var.github_repo_url}.git /opt/ai-voice-assistant

              cat << 'ENVEOF' > /opt/ai-voice-assistant/backend/.env
              ${var.env_content}
              ENVEOF
              chmod 600 /opt/ai-voice-assistant/backend/.env
              chown -R ubuntu:ubuntu /opt/ai-voice-assistant

              cd /opt/ai-voice-assistant/backend
              python3 -m venv venv
              ./venv/bin/pip install --upgrade pip
              ./venv/bin/pip install -r requirements.txt

              cat << 'SERVICE' > /etc/systemd/system/ai-voice-backend.service
              [Unit]
              Description=AI Voice Assistant FastAPI Backend
              After=network.target

              [Service]
              User=ubuntu
              WorkingDirectory=/opt/ai-voice-assistant/backend
              EnvironmentFile=/opt/ai-voice-assistant/backend/.env
              ExecStart=/opt/ai-voice-assistant/backend/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
              Restart=always
              RestartSec=3

              [Install]
              WantedBy=multi-user.target
              SERVICE

              systemctl daemon-reload
              systemctl enable ai-voice-backend
              systemctl start ai-voice-backend

              cat << 'NGINX' > /etc/nginx/sites-available/ai-voice
              server {
                  listen 80;
                  server_name _;
                  client_max_body_size 25M;
                  location / {
                      proxy_pass http://127.0.0.1:8000;
                      proxy_http_version 1.1;
                      proxy_set_header Upgrade $http_upgrade;
                      proxy_set_header Connection "upgrade";
                      proxy_set_header Host $host;
                  }
              }
              NGINX

              ln -sf /etc/nginx/sites-available/ai-voice /etc/nginx/sites-enabled/ai-voice
              rm -f /etc/nginx/sites-enabled/default
              nginx -t && systemctl restart nginx

              mkdir -p /home/ubuntu/actions-runner
              cd /home/ubuntu/actions-runner
              RUNNER_VER=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | tr -d 'v')
              curl -sL "https://github.com/actions/runner/releases/download/v$${RUNNER_VER}/actions-runner-linux-x64-$${RUNNER_VER}.tar.gz" -o actions-runner.tar.gz
              tar xzf actions-runner.tar.gz
              rm -f actions-runner.tar.gz
              chown -R ubuntu:ubuntu /home/ubuntu/actions-runner

              su - ubuntu -c "cd /home/ubuntu/actions-runner && ./config.sh --url ${var.github_repo_url} --token ${var.github_runner_token} --unattended --replace"
              ./svc.sh install ubuntu
              ./svc.sh start
              USERDATA