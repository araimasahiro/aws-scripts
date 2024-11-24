#!/usr/bin/env bash

SCRIPT_VER="2.0"
SCRIPT_NAME="${0##*/}"
SCRIPT_DIR="${0%/*}"
#CONF_DIR="$HOME/.aws"
CONF_DIR=$SCRIPT_DIR

func_usage() {
    echo "Usage: ${SCRIPT_NAME} <OS_name [instance_type]> [-s|--spot] [-p|--profile <value>] [-n|--name <value>] [-t|--tag <key:value>] [-u|--userdata <template>]"
    echo " "
    echo "OS_name:"
    echo "      ubuntu[-arm] | ubuntu24[-arm] | ubuntu22[-arm] | al2023[-arm] | amazon2023[-arm] | amazon2[-arm] | rhel[-arm] | suse15[-arm] | suse12"
    echo "      ubuntu      Ubuntu latest LTS, currently, same as ubuntu24"
    echo "      ubuntu24    Ubuntu 24.04 LTS, noble"
    echo "      ubuntu22    Ubuntu 22.04 LTS, jammy"
    echo "      al2023      Amazon Linux 2023"
    echo "      amazon2023  (alias) Amazon Linux 2023"
    echo "      amazon2     Amazon Linux 2"
    echo "      rhel        Red Hat Enterprise Linux 9"
    echo "      suse15      SUSE Linux Enterprise Server 15 SP6"
    echo "      suse12      SUSE Linux Enterprise Server 12 SP5 (x86_64 only)"
    echo "      *-arm       Needed for each arm64 instance"
    echo "instance_type:"
    echo "      <instance_type> can be refer to https://instances.vantage.sh/, etc."
    echo "      The architecture must be the same as the OS selected."
    echo "      If not specified, t3.micro(X86_64) or t4g.micro(aarch64) will be used."
    echo "OPTIONS:"
    echo "-s,--spot"
    echo "      Create a spot instance request."
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
    echo "-h,--help:"
    echo "      Show this help and exit."
    echo "example1:"
    echo "      ${SCRIPT_NAME} ubuntu-arm c7gn.xlarge -n ar-common -r DPS1-role-ec2-default --tag AutoStop:no --tag 'Note:Common Use'"
    echo "example2:"
    echo "      ${SCRIPT_NAME} amazon2023 m6a.8xlarge -p aws3-perf -n ar-ec2-measure "
}

func_read_conf() {
    #Usage: read_conf conf_file section
    # confの[section]からkey=valueだけを抽出して変数設定する
    conf_file="$1"
    section="$2"
    if [ -z "$conf_file" ] || [ -z "$section" ]; then
        echo "Error: Missing conf_file or section"
        return 1
    fi
    # evalで実行した変数を出力する
    # /^\['"$section"'\]/,/^$/ [$section]〜空行の間に対してsedを実行
    # /^[[:space:]]*#/d  コメント行は無視
    # s/^[[:space:]]*([^[:space:]=]+)[[:space:]]*=[[:space:]]*([^[:space:]#][.*?[^[:space:]]?):[[:space]]*(#.*)?$/\1="\2"/p
    # key = value #comment の形式の行を抽出し、\1=\2として出力 ; \1=key, \2=value;
    # または tag:key = value #commentから、_tag_key=valueとして出力
    ## ^[[:space:]]*                        行頭の空白を除く  
    ## ([^[:space:]=]+)                     空白と＝以外の文字列; (グループ\1)
    ## [[:space:]]*=[[:space:]]*            ＝と周辺の空白
    ## ([^#]+)                              ＃を除く1文字以上の文字列; (グループ\2)
    ## .*$                                  行末まで読み飛ばし
    ## ※正規表現の"?"は非貪欲モードを表すらしいがMacではうまく解釈されず
    eval "$(
        sed -rn '/^\['"${section}"'\]/,/^$/{
            /^[[:space:]]*#/d
            s/^[[:space:]]*tag:([^[:space:]=]+)[[:space:]]*=[[:space:]]*([^#]+).*$/_tag_\1=\2/p
            s/^[[:space:]]*([^[:space:]=]+)[[:space:]]*=[[:space:]]*([^#]+).*$/\1=\2/p
        }' "${conf_file}"
    )"
}

#引数オプション解析
## OS指定がなければエラー
if [ -z "$1" ]; then
    func_usage
    exit 1
fi

# AMI定義ファイルの読み込み
if [ ! -e "$CONF_DIR/ami.env" ]; then 
    echo "Creating $CONF_DIR/ami.env..."
    "$SCRIPT_DIR/update-ami.sh" || { echo "Failed to execute update-ami.sh"; exit 1; }
fi
if [ -e "$CONF_DIR/ami.env" ]; then
    . "$CONF_DIR/ami.env"
else
    echo "Error: $CONF_DIR/ami.env not found after update."
    exit 1
fi
declare -A ami
ami=(
    [ubuntu]="$AMI_Ubuntu_noble_x86_64"
    [ubuntu24]="$AMI_Ubuntu_noble_x86_64"
    [ubuntu22]="$AMI_Ubuntu_jammy_x86_64"
    [ubuntu-focal]="$AMI_Ubuntu_focal_x86_64"
    [al2023]="$AMI_AmazonLinux2023_x86_64"
    [amazon2023]="$AMI_AmazonLinux2023_x86_64"
    [amazon2]="$AMI_AmazonLinux2_x86_64"
    [rhel]="$AMI_RHEL9_x86_64"
    [suse15]="$AMI_SUSE15_x86_64"
    [suse12]="$AMI_SUSE12_x86_64"
    [ubuntu-arm]="$AMI_Ubuntu_noble_arm64"
    [ubuntu24-arm]="$AMI_Ubuntu_noble_arm64"
    [ubuntu22-arm]="$AMI_Ubuntu_jammy_arm64"
    [al2023-arm]="$AMI_AmazonLinux2023_arm64"
    [amazon2023-arm]="$AMI_AmazonLinux2023_arm64"
    [amazon2-arm]="$AMI_AmazonLinux2_arm64"
    [rhel-arm]="$AMI_RHEL9_arm64"
    #[suse12-arm]="$AMI_SUSE12_arm64" DOES NOT EXIST
    [suse15-arm]="$AMI_SUSE15_arm64"
    [ubuntu-focal-arm]="$AMI_Ubuntu_focal_arm64"
)

##オプションチェック
while [ $# -gt 0 ]; do
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
            _key="${2%%:*}"
            _value="${2#*:}"
            OPT_TAGS="$OPT_TAGS,{Key=$_key,Value=$_value}"
            shift 2
            ;;
        -s | --spot)
            SPOT_OPTION="--instance-market-options MarketType=spot,SpotOptions={SpotInstanceType=persistent,InstanceInterruptionBehavior=stop}"
            shift 1
            ;;
        --version)
            echo "${SCRIPT_NAME} $SCRIPT_VER"
            exit 0
            ;;
        -h | --help)
            func_usage
            exit 0
            ;;
        -*)
            echo "Error. Illegal option: $1"
            exit 1
            ;;
        *)
            ##"-"なしならOS_nameと仮定
            if [ -z "$OS_name" ]; then
                OS_name="$1"
                #AMIの設定
                AMI="${ami[$OS_name]}"
                if [ -z "$AMI" ]; then
                    echo "Error. Unknown OS_name: $OS_name"
                    exit 1
                else
                    if [ ${OS_name##*-} = "arm" ]; then ARCH="aarch64"; else ARCH="x86_64"; fi
                fi
                ##インスタンスタイプが設定されているかチェック
                if [ -n "$2" ] && [ "${2:0:1}" != "-" ]; then
                    _instance_type="$2"
                    shift 1
                fi
            else
                echo "Error. Too many arguments."
                exit 1
            fi
            shift 1
            ;;
    esac
done

## インスタンスタイプ未指定の場合、t4g.micro または t3.microを使用
if [ -z "$_instance_type" ]; then
    if [ "$ARCH" = "aarch64" ]; then INSTANCE_TYPE="t4g.micro"; else INSTANCE_TYPE="t3.micro"; fi
else
    INSTANCE_TYPE="$_instance_type"
fi
## 設定ファイルからプロファイルをリード
CONF_PROFILE=${CONF_PROFILE:-default}
func_read_conf "$CONF_DIR/${SCRIPT_NAME/.sh/.conf}" "global" #先にグローバルセクションをリード
func_read_conf "$CONF_DIR/${SCRIPT_NAME/.sh/.conf}" "$CONF_PROFILE"
## タグ設定の展開
for x in ${!_tag_*}; do
    _key="${x#_tag_}"
    _val="${!x}"
    CONF_TAGS="$CONF_TAGS,{Key=$_key,Value=$_val}"
done
# ## 引数でキーペアが指定されている場合はそちらで上書
# KEY_PAIR=${_key_pair+$_key_pair}
## Name未指定の場合、confにDEFAULT_INSTANCE_NAMEが定義されていれば使用、引数があれば上書き
NAME=${NAME:-$DEFAULT_INSTANCE_NAME}
if [ -n "$_name" ]; then NAME="$_name"; fi
## Role未指定の場合、confにATTACHED_ROLEが定義されていれば使用、引数があれば上書き
ROLE=${ROLE:-$ATTACHED_ROLE}
if [ -n "$_role" ]; then ROLE="$_role"; fi
if [ -n "$ROLE" ]; then
    INSTANCE_PROFILE_OPTION="--iam-instance-profile Name=$ROLE"
fi
## 作成日の設定
DATE=$(date +%Y-%m-%d)
## CREATOR,SUBNET_ID,SECURITY_GROUP_ID,KEY_PAIRが未定義ならエラー
if [ -z "$CREATOR" ] || [ -z "$SUBNET_ID" ] || [ -z "$SECURITY_GROUP_ID" ] || [ -z "$KEY_PAIR" ]; then
    echo "Error. CREATOR, SUBNET_ID, SECURITY_GROUP_ID, KEY_PAIR are not specified."
    exit 1
fi

#UserDataの設定
## パッケージシステムの設定
str="${OS_name:0:4}"
case $str in
    "ubun")
        PACKAGE_SYSTEM="apt"
        USER_NAME="ubuntu"
        ;;
    "amaz" | "al20" | "rhel")
        PACKAGE_SYSTEM="dnf"
        USER_NAME="ec2-user"
        ;;
    "suse")
        PACKAGE_SYSTEM="zypper"
        USER_NAME="ec2-user"
        ;;
    *)
        echo "Error. Unknown OS_name: $OS_name"
        exit 1
esac
## UserDataの生成
USER_DATA=${USER_DATA:-"userdata-default.yaml"}
sed -e "s/_PACKAGE_SYSTEM_/$PACKAGE_SYSTEM/g" -e "s/_ARCH_/$ARCH/g" -e "s/_USER_NAME_/$USER_NAME/g" $CONF_DIR/$USER_DATA > "/tmp/userdata-ec2-${OS_name}.yaml"
#インスタンスの起動
## タグのマージ
if [ -n "$NAME" ]; then
    TAGS="{Key=Name,Value=$NAME},{Key=Creator,Value=$CREATOR},{Key=CreationDate,Value=$DATE}"
else
    TAGS="{Key=Creator,Value=$CREATOR},{Key=CreationDate,Value=$DATE}"
fi
TAGS="${TAGS}${OPT_TAGS}${CONF_TAGS}"
TAGS=${TAGS%,}

aws ec2 run-instances --subnet-id "$SUBNET_ID" --security-group-ids "$SECURITY_GROUP_ID" --key-name "$KEY_PAIR" \
--instance-type "$INSTANCE_TYPE" \
--image-id "$AMI" \
--block-device-mappings \
'DeviceName="/dev/sda1",Ebs={DeleteOnTermination=true,VolumeSize=8,VolumeType=gp3,Iops=3000,Throughput=125}' \
--private-dns-name-options 'HostnameType=resource-name,EnableResourceNameDnsARecord=true,EnableResourceNameDnsAAAARecord=false' \
--ebs-optimized $SPOT_OPTION $INSTANCE_PROFILE_OPTION \
--tag-specifications "ResourceType=instance, Tags=[$TAGS]" \
--user-data file://"/tmp/userdata-ec2-${OS_name}.yaml"