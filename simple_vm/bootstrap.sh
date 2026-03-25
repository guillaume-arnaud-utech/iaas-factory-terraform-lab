#!/bin/bash

mkdir -p ~/.ssh

gcloud secrets versions access latest --secret=github-ssh-key --project=tec-iaasint-s-ws49 > ~/.ssh/terraform-lab

chmod 600 ~/.ssh/terraform-lab

cat >> ~/.ssh/config <<EOF
Host github.com
  IdentityFile ~/.ssh/terraform-lab
  StrictHostKeyChecking no
EOF

git config --global url."git@github.com:".insteadOf "https://github.com/"

curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip -o terraform.zip \
  && unzip terraform.zip \
  && mv terraform /usr/local/bin/ \
  && rm terraform.zip