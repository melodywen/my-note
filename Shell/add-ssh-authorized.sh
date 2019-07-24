#!/bin/bash
set -e

# 需要设置公私钥的地址
REMOTE_ADDRESS=(
    root@10.6.5.181
    root@10.6.5.182
)


# 1. 首先判断 宿主机 是否存在 公私钥 ，没有则提示是否进行进行生成
if [ ! -f ~/.ssh/id_rsa.pub ]; then
    read -p "发现宿主机没用公私钥，是否需要新建公私钥？[y/n]" input
    case $input in
	    [yY])
			ssh-keygen -t rsa
			;;
	    *)
			echo "因为没有宿主机的公私钥，程序将停止运行"
			exit 1
			;;
	esac
fi

ID_RSA_PUB=`cat ~/.ssh/id_rsa.pub`
echo -e "1. 读取宿主机的公钥信息：$ID_RSA_PUB \n"

# 2. 编写 远程 服务器运行的shell脚本
REMOTE_SCRIPT=`cat<<EOF
#!/bin/bash

# 首先判断是否存在 .ssh 目录
if [ ! -d ~/.ssh ]; then
    mkdir ~/.ssh
    chmod 700 ~/.ssh/
fi

ID_RSA_PUB=\"$ID_RSA_PUB\"

# 查看是否已经存在authorized_keys
if [ -f ~/.ssh/authorized_keys ]; then
    grep \"$ID_RSA_PUB\"  ~/.ssh/authorized_keys > /dev/null
    if [ @#@ -eq 0 ]; then
        echo "已经存在宿主机的公私钥，跳过authorized_keys的配置..."
        exit 0;
    fi
fi

# 开始配置公私钥
echo \"$ID_RSA_PUB\" >> ~/.ssh/authorized_keys
echo "成功配置公私钥..."

EOF
`

# 2. 登录远程服务器
STEP=1
function add_remote_authorized_key() {

STEP=`expr $STEP + 1`
echo -e "\n$STEP. 登录远程服务器:$1,执行远程的 shell 脚本 "

ssh -o StrictHostKeyChecking=no $1 << EOF
    echo "$REMOTE_SCRIPT" > /tmp/add-master-node-id_rsa_pub.sh && chmod a+x /tmp/add-master-node-id_rsa_pub.sh
    sed -i s/@#@/\@#?/g /tmp/add-master-node-id_rsa_pub.sh
    sed -i s/@#/\$/g /tmp/add-master-node-id_rsa_pub.sh
    #cat /tmp/add-master-node-id_rsa_pub.sh
    /tmp/add-master-node-id_rsa_pub.sh
EOF
}

# 3.先执行配置文件的地址
for ITEM in ${REMOTE_ADDRESS[@]}
do
    add_remote_authorized_key $ITEM
done

# 4.再询问其他的地址
while true
do
    echo -e "\n请输入其他还需要添加ssh公私钥的地址，如果不需要请输入n (格式如 root@10.6.5.181) :"
    read host
    case "$host" in
        n|no  )
            echo -e "\n退出脚本"
            exit 0
            ;;
        * )
            add_remote_authorized_key $host
            ;;
   esac
done
