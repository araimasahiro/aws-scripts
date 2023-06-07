#!/bin/bash

AMI_ENV_FILE="$HOME/code/aws/ami.env"
REGION="ap-northeast-1"

if [ -e "$AMI_ENV_FILE" ]; then
    mv "$AMI_ENV_FILE" "$AMI_ENV_FILE.bak" 
else
    touch "$AMI_ENV_FILE"
fi

for ARCH in x86_64 arm64; do
    #Amazon Linux2
    _ret=$(aws ec2 describe-images \
    --region "$REGION" \
    --query 'reverse(sort_by(Images, &CreationDate))[:1]' \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-2.0.*-gp2" "Name=architecture,Values=$ARCH" \
    --output json \
    | jq -r '.[]|[.ImageId, .Architecture, .Description] | @tsv')
    echo "# $_ret"
    echo "export AMI_AmazonLinux2_$ARCH=$(echo "$_ret" | awk -F'\t' '{print $1 " #" $3}')" >> "$AMI_ENV_FILE"
    #Ubuntu 22.04, 20.04
    for VER in jammy focal; do
        _ret=$(aws ec2 describe-images \
        --region "$REGION" \
        --owners 099720109477 \
        --query 'reverse(sort_by(Images, &CreationDate))[:1]' \
        --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-$VER-*-server-*" "Name=architecture,Values=$ARCH" \
        --output json \
        | jq -r '.[]|[.ImageId, .Architecture, .Description] | @tsv')
        echo "# $_ret"
        echo "export AMI_Ubuntu_${VER}_${ARCH}=$(echo "$_ret" | awk -F'\t' '{print $1 " #" $3}')" >> "$AMI_ENV_FILE"
    done
done
echo "Export environment value: $AMI_ENV_FILE"
