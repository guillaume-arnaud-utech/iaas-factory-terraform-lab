#!/bin/bash

TERRAFORM_VERSION="1.13.2"

mkdir -p ~/.ssh

gcloud secrets versions access latest --secret=github-terraform-lab --project=iaastraining-s-0dwp > ~/.ssh/github-terraform-lab

chmod 600 ~/.ssh/github-terraform-lab

cat >> ~/.ssh/config <<EOF
Host github.com
  IdentityFile ~/.ssh/github-terraform-lab
  StrictHostKeyChecking no
EOF

git config --global url."git@github.com:".insteadOf "https://github.com/"

curl -fsSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip -o terraform.zip \
  && unzip terraform.zip \
  && sudo mv terraform /usr/local/bin/ \
  && rm terraform.zip LICENSE.txt