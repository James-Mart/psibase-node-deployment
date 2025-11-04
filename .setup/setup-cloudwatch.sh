# This OPTIONAL script is used to help setup the CloudWatch agent for this ec2 instance on AWS.
# This has not been deeply tested.

# 1) Get arch (x86_64=amd64, arm64=aarch64)
ARCH=$(dpkg --print-architecture)

# 2) Download the agent .deb from AWS
URL="https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/${ARCH}/latest/amazon-cloudwatch-agent.deb"
curl -fsSL "$URL" -o /tmp/amazon-cloudwatch-agent.deb

# 3) Install
sudo dpkg -i /tmp/amazon-cloudwatch-agent.deb
sudo apt -f install -y   # fix deps if prompted

# 4) Confirm
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status

sudo tee /opt/aws/amazon-cloudwatch-agent/bin/config.json >/dev/null <<'JSON'
{
  "agent": { "metrics_collection_interval": 60, "run_as_user": "cwagent" },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": { "InstanceId": "${aws:InstanceId}" },
    "aggregation_dimensions": [["InstanceId","path"]],
    "metrics_collected": {
      "disk": {
        "measurement": ["used_percent","inodes_free","inodes_used"],
        "resources": ["*"],
        "ignore_file_system_types": ["sysfs","devtmpfs","overlay","squashfs","tmpfs","devfs","proc","nsfs","rpc_pipefs","autofs"],
        "metrics_collection_interval": 60
      },
      "mem": { "measurement": ["mem_used_percent"], "metrics_collection_interval": 60 }
    }
  }
}
JSON

sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/bin/config.json -s

sudo systemctl enable amazon-cloudwatch-agent
sudo systemctl status amazon-cloudwatch-agent --no-pager
