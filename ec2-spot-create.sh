#!/bin/sh
if [ -z "$1" ]; then
    echo "Usage: ${0##*/} {ubuntu[-focal[-arm]] | amazon2[-arm]} [instance-type] [instance-Name] []"
    echo "(example) ${0##*/} ubuntu-arm c6gd.large ar-common"
    exit 1
fi

if [ ! -e $HOME/code/ami.env ]; then 
    $HOME/code/update-ami.sh
fi
. $HOME/code/ami.env

if [ "$1" = "ubuntu" ]; then
    AMI="$AMI_Ubuntu_jammy_x86_64"
    IMG=ami-Ocd7ad8676931d727 #Ubuntu, 22.04 LTS, amd64 jammy image build on 2023-01-15 (ap-northeast-1)
    ARCH=x86_64
    PACKAGE_SYSTEM=apt
elif [ "$1" = "ubuntu-arm" ]; then
    AMI="$AMI_Ubuntu_jammy_arm64"
    IMG=ami-0a09e744e6643e376 #Ubuntu, 22.04 LTS, arm64 jammy image build on 2023-01-15
    ARCH=aarch64
    PACKAGE_SYSTEM=apt
elif [ "$1" = "amazon2" ]; then
    AMI="$AMI_AmazonLinux2_x86_64"
    IMG=ami-Oad64728720227ff8 #Amazon Linux 2 IMG 2.0.20230119.1 x86 _64 HVM gp2 (ap-northeast-1)
    ARCH=x86_64
    PACKAGE_SYSTEM=yum
elif [ "$1" = "amazon2-arm" ]; then
    AMI="$AMI_AmazonLinux2_arm64"
    IMG=ami-01da3269d11eeb9c9 #Amazon Linux 2 LTS Arm64 IMG 2.0.20230119.1 arm64 HVM gp2
    ARCH=aarch64
    PACKAGE_SYSTEM=yum
elif [ "$1" = "ubuntu-focal" ]; then
    AMI="$AMI_Ubuntu_focal_x86_64"
    ARCH=x86_64
    PACKAGE_SYSTEM=apt
elif [ "$1" = "ubuntu-focal-arm" ]; then
    AMI="$AMI_Ubuntu_focal_arm64"
    ARCH=aarch64
    PACKAGE_SYSTEM=apt
else
    echo "Usage: ${0##*/} {ubuntu[-arm] | amazon2[-arm]} [instance-type] [instance-Name] [lifetime] [Note]"
    echo "(example) ${0##*/} ubuntu-arm c6gd.large ar-common 1week \"Common Use\""
    exit 1
fi

#sed -e "s/_PACKAGE_SYSTEM_/$PACKAGE_SYSTEM/g" -e "s/_ARCH_/$ARCH/g" ~/code/cloud-init-ec2-template.yaml > ~/code/cloud-init-ec2-"$1". yaml
sed -e "s/_ARCH_/$ARCH/g" ~/code/cloud-init-ec2-template.yaml > ~/code/cloud-init-ec2-"$1".yaml
CREATOR=masahiro.arai
DEFAULT_SUBNET=subnet-0ecf3bf78d3c1991a #ar-private-subnet-1a
DEFAULT_SG=sg-02fc9e1067c9f6567 #ar-sg-default
DATE=$(date +%Y-%m-%d)
KEY_PAIR=key-masahiro2022-tokyo
#PROFILE_ARN="arn:aws:iam::430027127626:instance-profile/AmazonSSMRoleForInstancesQuickSetup"
PROFILE_NAME="AmazonSSMRoleForInstancesQuickSetup"

#Default Value if $2,$3, $4, $5 are omitted
#Instance-Type
if [ -z "$2" ]; then
    if [ "${1##*-}" = "arm" ]; then
        INSTANCE_TYPE=t4g.micro
    else
        INSTANCE_TYPE=t3.micro
    fi
else
    INSTANCE_TYPE="$2"
fi
#Instance-Name
if [ -z "$3" ]; then
    NAME="ar-common"
else
    NAME="$3"
fi
#LifeTime
if [ -z "$4" ]; then
    LIFE="1week"
else
    LIFE="$4"
fi
#Note
if [ -z "$5" ]; then
    NOTE="Common Use"
else
    NOTE="$5"
fi

aws ec2 run-instances --subnet-id "$DEFAULT_SUBNET" --security-group-ids "$DEFAULT_SG" --key-name "$KEY_PAIR" \
--instance-type "$INSTANCE_TYPE" \
--image-id "$AMI" \
--block-device-mappings \
'DeviceName="/dev/sda1",Ebs={DeleteOnTermination=true,VolumeSize=8,VolumeType=gp3,Iops=3000,Throughput=125}' \
--private-dns-name-options 'HostnameType=resource-name,EnableResourceNameDnsARecord=true,EnableResourceNameDnsAAAARecord=false' \
--instance-market-options 'MarketType=spot,SpotOptions={SpotInstanceType=one-time,InstanceInterruptionBehavior=terminate}' \
--ebs-optimized \
--tag-specifications "ResourceType=instance, Tags=[{Key=Name,Value=$NAME}, {Key=Creator,Value=$CREATOR}, {Key=CreationDate,Value=$DATE}, \
{Key=SSM, Value=enable}]" \
--iam-instance-profile "Name=$PROFILE_NAME" \
--user-data file://"$HOME/code/cloud-init-ec2-$1.yaml"
#(Key=Lifetime, Value=$LIFE), (Key=Note, Value=$NOTE}, (Key=SSM, Value=enable}]" \
