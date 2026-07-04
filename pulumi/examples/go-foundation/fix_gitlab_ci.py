import re
import sys

def add_gcloud(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    gcloud_install = """
    - apt-get update && apt-get install -y apt-transport-https ca-certificates gnupg curl
    - curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
    - echo "deb https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
    - apt-get update && apt-get install -y google-cloud-cli
"""
    if "apt-get install -y google-cloud-cli" not in content:
        content = re.sub(r'(\s*- curl -fsSL https://get\.pulumi\.com \| sh)', gcloud_install + r'\1', content)
        with open(filepath, 'w') as f:
            f.write(content)

add_gcloud('../pulumi_ts-example-foundation/build/gitlab-ci.yml')
add_gcloud('../pulumi_go-example-foundation/build/gitlab-ci.yml')
