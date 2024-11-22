#!/bin/bash
SCRIPT_VER="2.0"
SCRIPT_NAME="${0##*/}"
SCRIPT_DIR="${0%/*}"
#CONF_DIR="$HOME/.aws"
CONF_DIR=$SCRIPT_DIR

func_usage() {
    echo "Usage: ${1##*/} <OS_name> [<instance_type>] [-p|--profile <value>] [--spot] [-n|--name <value>] [-t|--tag <key:value>] [-u|--userdata <template>]"
    echo " "
    echo "<OS_name> =  ubuntu[-arm] | ubuntu24[-arm] | ubuntu22[-arm] | amazon2023[-arm] | amazon2[-arm] | rhel[-arm] | suse15[-arm] | suse12"
    echo "              ubuntu      Ubuntu latest LTS, currently, same as ubuntu24"
    echo "              ubuntu24    Ubuntu 24.04 LTS, noble"
    echo "              ubuntu22    Ubuntu 22.04 LTS, jammy"
    echo "              al2023      Amazon Linux 2023"
    echo "              amazon2023  (alias) Amazon Linux 2023"
    echo "              amazon2     Amazon Linux 2"
    echo "              rhel        Red Hat Enterprise Linux 9"
    echo "              suse15      SUSE Linux Enterprise Server 15 SP6"
    echo "              suse12      SUSE Linux Enterprise Server 12 SP5 (x86_64 only)"
    echo "              *-arm       Needed for arm64 instance"
    echo "<instance_type>"
    echo "      <instance_type> can be refer to https://instances.vantage.sh/, etc."
    echo "      The architecture must be the same as the OS selected."
    echo "      If not specified, t3.micro(X86_64) or t4g.micro(aarch64) will be used."
    echo "OPTIONS:"
    echo "-p,--profile:"
    echo "      Refer to ec2-create.conf; you should configure the profile"
    echo "      If not specified, default profile will be used."
    echo "-n,--name:"
    echo "      It will be set as the <value> of tag::Name."
    echo "-t,--tag:"
    echo "      It will be set as the <value> of tag::<key>"
    echo "-u,--userdata:"
    echo "      Specify the UserData template.yaml for cloud-init."
    echo "      If not specified, userdata-default.yaml will be used."
    echo "--version:"
    echo "      Show version and exit."
    echo "example1:"
    echo "      ${1##*/} ubuntu-arm c7gn.xlarge -n ar-common -r DPS1-role-ec2-default --tag AutoStop:no --tag 'Note:Common Use'"
    echo "example2:"
    echo "      ${1##*/} amazon2023 m6a.8xlarge -p aws3-perf -n ar-ec2-measure "
}

func_read_conf() {
  #Usage: read_conf conf_file section
  # confの[section]からkey=valueだけを抽出して変数設定する
  conf_file="$1"
  section="$2"
  declare -A TAG #TAGを連想配列として宣言
  # evalで実行した変数を出力する
  # /^\['"$section"'\]/,/^$/ [$section]〜空行の間に対してsedを実行
  # /^[[:space:]]*#/d  コメント行は無視
  # s/^[[:space:]]*([^[:space:]=]+)[[:space:]]*=[[:space:]]*([^[:space:]#]+).*$/\1="\2"/p
  # key = value #comment の形式の行を抽出し、\1="\2" として出力; \1=key, \2=value;
  eval "$(
    sed -En '/^\['"$section"'\]/,/^$/{
      /^[[:space:]]*#/d
      s/^[[:space:]]*([^[:space:]=]+)[[:space:]]*=[[:space:]]*([^[:space:]#]+).*$/\1="\2"/p
    }' $conf_file
  )"
}

#OSの定義
if [ ! -e $CONF_DIR/ami.env ]; then 
    $SCRIPT_DIR/update-ami.sh
fi
. $CONF_DIR/ami.env
ami["ubuntu"]="$AMI_Ubuntu_noble_x86_64"
ami["ubuntu24"]="$AMI_Ubuntu_noble_x86_64"
ami["ubuntu22"]="$AMI_Ubuntu_jammy_x86_64"
ami["ubuntu-focal"]="$AMI_Ubuntu_focal_x86_64"
ami["al2023"]="$AMI_AmazonLinux2023_x86_64"
ami["amazon2023"]="$AMI_AmazonLinux2023_x86_64"
ami["amazon2"]="$AMI_AmazonLinux2_x86_64"
ami["rhel"]="$AMI_RHEL9_x86_64"
ami["suse15"]="$AMI_SUSE15_x86_64"
ami["suse12"]="$AMI_SUSE12_x86_64"
ami["ubuntu-arm"]="$AMI_Ubuntu_noble_arm64"
ami["ubuntu24-arm"]="$AMI_Ubuntu_noble_arm64"
ami["ubuntu22-arm"]="$AMI_Ubuntu_jammy_arm64"
ami["al2023-arm"]="$AMI_AmazonLinux2023_arm64"
ami["amazon2023-arm"]="$AMI_AmazonLinux2023_arm64"
ami["amazon2-arm"]="$AMI_AmazonLinux2_arm64"
ami["rhel-arm"]="$AMI_RHEL9_arm64"
ami["suse15-arm"]="$AMI_SUSE15_arm64"
#ami["suse12-arm"]="$AMI_SUSE12_arm64" DOES NOT EXIST
ami["ubuntu-focal-arm"]="$AMI_Ubuntu_focal_arm64"

#引数オプション解析
## OS指定がなければエラー
if [ -z "$1" ]; then
    func_usage "$SCRIPT_NAME"
    exit 1
fi
##OS(AMI)の設定; 指定ミスの場合には$AMIが未定義になる
AMI=${ami["$1"]}
if [ -z "$AMI" ]; then
    echo "Error. Unknown OS_name: $1"
    func_usage "$SCRIPT_NAME"
    exit 1
else
    if [ ${1##*-} = "arm" ]; then ARCH="aarch64"; else ARCH="x86_64"; fi
fi
##インスタンスタイプが設定されているかチェック
if [ ${2:0:1} != "-" ]; then
    _instance_type="$2"
fi
##それ以外のオプションチェック
while ($# > 0); do
    case "$1" in
        -n | --name)
            if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
                echo "Error. Name is not specified."
                exit 1
            fi
            _name="$2"
            shift 2
            ;;
        -r | --role)
            if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
                echo "Error. Role is not specified."
                exit 1
            fi
            _role="$2"
            shift 2
            ;;
        # -k | --key-pair)
        #     if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
        #         echo "Error. Key pair is not specified."
        #         exit 1
        #     fi
        #     _key_pair="$2"
        #     shift 2
        #     ;;
        -p | --profile)
            if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
                echo "Error. Profile is not specified."
                exit 1
            fi
            #.confをリード
            CONF_PROFILE="$2"
            shift 2
            ;;
        -t | --tag)
            if [ -z "$2" ] || [ ${2:0:1} = "-" ]; then
                echo "Error. Tag is not specified."
                exit 1
            fi
            tag_key="{$2%%:*}"
            tag_value="{$2#*:}"
            OPT_TAG="$OPT_TAG,{Key=$tag_key, Value=$tag_value}"
            shift 2
            ;;
        --spot)
            SPOT_OPTION="--instance-market-options 'MarketType=spot,SpotOptions={SpotInstanceType=persistent,InstanceInterruptionBehavior=stop}'"
            ;;
        --version)
            echo "${${0##*/}/.sh/.conf} $SCRIPT_VER"
            exit 0
        -*)
            echo "Error. Illegal option: $1"
            exit 1
            ;;
        *)
            shift #それ以外は無視1(OS_name, instance_typeなど)
            ;;
    esac
done
## 設定ファイルからプロファイルをリード
CONF_PROFILE=${CONF_PROFILE}
func_read_conf "$CONF_DIR/${SCRIPT_NAME/.sh/.conf}" "global" #先にグローバルセクションをリード
func_read_conf "$CONF_DIR/${SCRIPT_NAME/.sh/.conf}" "$CONF_PROFILE"
## インスタンスタイプ未指定の場合、t4g.micro または t3.microを使用
if [ -z $_instance_type ]; then
    if [ $ARCH = "aarch64" ]; then INSTANCE_TYPE="t4g.micro"; else INSTANCE_TYPE="t3.micro"; fi
else
    INSTANCE_TYPE=$_instance_type
fi
# ## 引数でキーペアが指定されている場合はそちらで上書
# KEY_PAIR=${_key_pair+$_key_pair}
## Name未指定の場合、confにDEDAULT_NAMEが定義されていれば使用、引数があれば上書き
NAME=${NAME:-$DEFAULT_NAME}
NAME=${_name+$_name}
## Role未指定の場合、confにDEFAULT_ROLEが定義されていれば使用、引数があれば上書き
ROLE=${ROLE:-$DEFAULT_ROLE}
ROLE=${_role+$_role}
## 作成日の設定
DATE=$(date +%Y-%m-%d)
## CREATOR,SUBNET,SECURITY_GROUP,KEY_PAIRが未定義ならエラー
if [ -z "$CREATOR" ] || [ -z "$SUBNET" ] || [ -z "$SECURITY_GROUP" ] || [ -z "$KEY_PAIR" ]; then
    echo "Error. CREATOR, SUBNET, SECURITY_GROUP, KEY_PAIR are not specified."
    exit 1
fi

#UserDataの設定
## パッケージシステムの設定
str="${1:0:4}"
case $str in
    "ubun")
        PACKAGE_SYSTEM="apt"
        USER_NAME="ubuntu"
        ;;
    "amaz")
    "al20")
    "rhel")
        PACKAGE_SYSTEM="dnf"
        USER_NAME="ec2-user"
        ;;
    "suse")
        PACKAGE_SYSTEM="zypper"
        USER_NAME="ec2-user"
        ;;
    *)
        echo "Error. Unknown OS_name: $1"
        exit 1
esac
## UserDataの生成
USER_DATA={$USER_DATA:-"userdata-default.yaml"}
sed -e "s/_PACKAGE_SYSTEM_/$PACKAGE_SYSTEM/g" -e "s/_ARCH_/$ARCH/g" -e "s/_USER_NAME_/$USER_NAME/g" $USER_DATA > /tmp/userdata-ec2-"$1".yaml

#インスタンスの起動
TAGS="{Key=Name,Value=$NAME}, {Key=Creator,Value=$CREATOR}, {Key=CreationDate,Value=$DATE}, {Key=SSM, Value=enable}"
TAGS=${OPT_TAG:-"$TAGS,$OPT_TAG"}
aws ec2 run-instances --subnet-id "$SUBNET" --security-group-ids "$SECURITY_GROUP" --key-name "$KEY_PAIR" \
--instance-type "$INSTANCE_TYPE" \
--image-id "$AMI" \
--block-device-mappings \
'DeviceName="/dev/sda1",Ebs={DeleteOnTermination=true,VolumeSize=8,VolumeType=gp3,Iops=3000,Throughput=125}' \
--private-dns-name-options 'HostnameType=resource-name,EnableResourceNameDnsARecord=true,EnableResourceNameDnsAAAARecord=false' \
--ebs-optimized $SPOT_OPTION \
--tag-specifications "ResourceType=instance, Tags=[$TAGS]" \
--iam-instance-profile "Name=$PROFILE_NAME" \
--user-data file://"/tmp/userdata-ec2-"$1".yaml"