#!/usr/bin/env bash

SCRIPT_DIR="${0%/*}"
AMI_ENV_FILE="$SCRIPT_DIR/ami.env"
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
    #Amazon Linux 2023
    _ret=$(aws ec2 describe-images \
    --region "$REGION" \
    --query 'reverse(sort_by(Images, &CreationDate))[:1]' \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023.*" "Name=architecture,Values=$ARCH" \
    --output json \
    | jq -r '.[]|[.ImageId, .Architecture, .Description] | @tsv')
    echo "# $_ret"
    echo "export AMI_AmazonLinux2023_$ARCH=$(echo "$_ret" | awk -F'\t' '{print $1 " #" $3}')" >> "$AMI_ENV_FILE"
    #Ubuntu 24.04 noble, 22.04 jammy, 20.04 focal
    for VER in noble jammy focal; do
        _ret=$(aws ec2 describe-images \
        --region "$REGION" \
        --owners 099720109477 \
        --query 'reverse(sort_by(Images, &CreationDate))[:1]' \
        --filters "Name=name,Values=ubuntu/images/hvm-ssd*/ubuntu-$VER-*-server-*" "Name=architecture,Values=$ARCH" \
        --output json \
        | jq -r '.[]|[.ImageId, .Architecture, .Description] | @tsv')
        echo "# $_ret"
        echo "export AMI_Ubuntu_${VER}_${ARCH}=$(echo "$_ret" | awk -F'\t' '{print $1 " #" $3}')" >> "$AMI_ENV_FILE"
    done
    #SUSE Linux Enterprise Server 15
    for VER in 15 12; do
        if [ "$VER" = "12" ] && [ "$ARCH" = "arm64" ]; then break; fi
        _ret=$(aws ec2 describe-images \
        --region "$REGION" \
        --owners amazon \
        --query 'reverse(sort_by(Images, &CreationDate))[:1]' \
        --filters "Name=name,Values=suse-sles-$VER-sp*-v????????-hvm-ssd-*" "Name=architecture,Values=$ARCH" \
        --output json \
        | jq -r '.[]|[.ImageId, .Architecture, .Description] | @tsv')
        echo "# $_ret"
        echo "export AMI_SUSE${VER}_${ARCH}=$(echo "$_ret" | awk -F'\t' '{print $1 " #" $3}')" >> "$AMI_ENV_FILE"
    done
    #Redhat Enterprise Linux 9
    _ret=$(aws ec2 describe-images \
    --region "$REGION" \
    --owners amazon \
    --query 'reverse(sort_by(Images, &CreationDate))[:1]' \
    --filters "Name=name,Values=RHEL-9.*_HVM-*-$ARCH-*" "Name=architecture,Values=$ARCH" \
    --output json \
    | jq -r '.[]|[.ImageId, .Architecture, .Description] | @tsv')
    echo "# $_ret"
    echo "export AMI_RHEL9_$ARCH=$(echo "$_ret" | awk -F'\t' '{print $1 " #" $3}')" >> "$AMI_ENV_FILE"    
done
echo "Export environment value: $AMI_ENV_FILE"
