#!/bin/bash

WORK_DIR="$HOME/code"
REGION="ap-northeast-1"

if [ -e "$WORK_DIR/ami.txt" ]; then
    mv "$WORK_DIR/ami.txt" "$WORK_DIR/ami.bak"
else
    touch "$WORK_DIR/ami.txt"
fi

for ARCH in x86_64 arm64; do
    #Amazon Linux2
    aws ec2 describe-images \
    --region "$REGION" \
    --query 'reverse(sort_by(Images, &CreationDate))[:1]' \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-2.0.*-gp2" "Name=architecture,Values=$ARCH" \
    --output json \
    | jq -r '.[]|[.ImageId, .Architecture, .Description] | @tsv' | tee -a "$WORK_DIR/ami.txt"
    ami-amazon2-$ARCH=$(tail -n 1 $WORK_DIR/ami.txt | awk '{print $1}')
    #Ubuntu 22.04, 20.04
    for VER in jammy focal; do
        aws ec2 describe-images \
        --region "$REGION" \
        --owners 099720109477 \
        --query 'reverse(sort_by(Images, &CreationDate))[:1]' \
        --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-$VER-*-server-*" "Name=architecture,Values=$ARCH" \
        --output json \
        | jq -r '.[]|[.ImageId, .Architecture, .Description] | @tsv' | tee -a "$WORK_DIR/ami.txt"
        ami-ubuntu-$VER-$ARCH=$(tail -n 1 $WORK_DIR/ami.txt | awk '{print $1}')
    done
done
