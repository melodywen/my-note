#!/bin/bash

# 配置服务器地址
REMOTE_ADDRESS=(
    root@10.6.5.181
    root@10.6.5.182
)


#初始化运行环境
function wait_a_moment(){
    for i in $(seq 1 ${1-10})
    do
        printf $i...
        #sleep 1s
    done
    printf "\n"
}


function init_environment() {
    rm -f /tmp/local.images.data
    rm -f /tmp/remote.images.data
    touch /tmp/remote.images.data
    touch /tmp/remote.images.data
    docker images --format "{{.ID}}@{{.Repository}}@{{.Tag}}" >> /tmp/local.images.data

    ssh -o StrictHostKeyChecking=no $1 << EOF
        rm -f /tmp/local.images.data
        rm -f /tmp/remote.images.data
        docker images --format "{{.ID}}@{{.Repository}}@{{.Tag}}" >> /tmp/local.images.data
EOF

    scp $1:/tmp/local.images.data /tmp/remote.images.data

    diff_local_to_remote
    diff_remote_to_local
}

# 查看本地 的images 和 远程的images 有什么不同
function diff_local_to_remote() {
    rm -f /tmp/local.images.data.diff
    touch /tmp/local.images.data.diff
    for line in `cat /tmp/local.images.data`
    do
        if [ `grep -c "$line" /tmp/remote.images.data` -eq '0' ]; then
            echo "$line" >> /tmp/local.images.data.diff
        fi

    done
    echo "----------本地镜像与远程的镜像的差异值：/tmp/local.images.data.diff----------"
    cat /tmp/local.images.data.diff
    echo "------------------------------------------------------------------------------"

}

# 查看远程 的images 和 本地的images 有什么不同
function diff_remote_to_local() {
    rm -f /tmp/remote.images.data.diff
    touch /tmp/remote.images.data.diff
    for line in `cat /tmp/remote.images.data`
    do
        if [ `grep -c "$line" /tmp/local.images.data` -eq '0' ]; then
            echo "$line" >> /tmp/remote.images.data.diff
        fi
    done
    echo "----------远程镜像与本地的镜像的差异值：/tmp/remote.images.data.diff----------"
    cat /tmp/remote.images.data.diff
    echo "------------------------------------------------------------------------------"
}

# 同步一个镜像
function remote_add_one_image() {
    # 镜像的字符串
    image_string=$2
    image_string=${image_string#*@}
    # 完整的镜像格式
    image_and_tag=${image_string/@/:}
    # 镜像打包的名称
    image_tar_name=${image_string//[@:\/]/_}.tar

    if [ ! -d /tmp/docker-images ]; then
        mkdir /tmp/docker-images
    fi
    # 生成镜像
    docker save $image_and_tag --output /tmp/docker-images/$image_tar_name

    scp /tmp/docker-images/$image_tar_name $1:/tmp/$image_tar_name
    # 上传镜像
    ssh -o StrictHostKeyChecking=no $1 << EOF
    cd /tmp
    docker load < $image_tar_name
    rm -f $image_tar_name
EOF
}

function remote_remove_one_image() {
     # 镜像的字符串
    image_string=$2
    image_id=${image_string%%@*}

    ssh -o StrictHostKeyChecking=no $1 << EOF
    docker rmi -f $image_id
EOF
}

function remote_remove_all_image() {
    # 镜像的字符串
    echo -e '#!/bin/bash
docker rmi -f `docker images -aq`' > /tmp/cmd.sh
    scp /tmp/cmd.sh $1:/tmp/cmd.sh
    ssh -o StrictHostKeyChecking=no $1 << EOF
    echo "运行脚本为：/tmp/cmd.sh"
    cat /tmp/cmd.sh
    echo ""
    chmod a+x /tmp/cmd.sh && /tmp/cmd.sh
    rm -rf /tmp/cmd.sh
EOF
}

function remote_remove_dangling_image() {
    # 镜像的字符串
    echo -e '#!/bin/bash
docker rmi -f `docker images -q -f dangling=true`' > /tmp/cmd.sh
    scp /tmp/cmd.sh $1:/tmp/cmd.sh
    ssh -o StrictHostKeyChecking=no $1 << EOF
    echo "运行脚本为：/tmp/cmd.sh"
    cat /tmp/cmd.sh
    echo ""
    chmod a+x /tmp/cmd.sh && /tmp/cmd.sh
    rm -rf /tmp/cmd.sh
EOF
}


rm -rf /tmp/REMOTE_ADDRESS
for ITEM in ${REMOTE_ADDRESS[@]}
do
    echo $ITEM >> /tmp/REMOTE_ADDRESS
done

cat <<  EOF
统一管理集群的镜像 shell脚本，请根据指令操作接下来的动作 :

本机的 ip 地址：
`/sbin/ifconfig -a|grep inet|grep -v 127.0.0.1|grep -v inet6|awk '{print $2}'|tr -d "addr:"`

远程需要统一操作的ip地址为：
`cat /tmp/REMOTE_ADDRESS`

需要操作的动作
1> 让所有所有的节点与管理的节点进行镜像对齐（并且删除远程节点其他的镜像）
2> 把管理节点的部分镜像同步到远程，（更加字符串进行模糊匹配 ）
3> 删除远程的所有镜像
4> 删除远程的 dangling 镜像
5> 退出
EOF

while true
do
    read -p "请输入指令：" cmd
    echo  -e ""
    case $cmd in
        1)
            for ITEM in ${REMOTE_ADDRESS[@]}
            do
                echo "----------------------------------------------------------"
                echo "| 正在运行 =》 对齐各个节点的images 》$ITEM  |"
                echo "----------------------------------------------------------"
                init_environment $ITEM
                for line in `cat /tmp/local.images.data.diff`
                do
                    remote_add_one_image $ITEM $line
                    wait_a_moment
                done

                for line in `cat /tmp/remote.images.data.diff`
                do
                    remote_remove_one_image $ITEM $line
                done
            done
            ;;
        2)
            read -p "请输入需要上传镜像的关键字（可以是id 也可以是厂库名、也可以是tag）：" keyword
            for ITEM in ${REMOTE_ADDRESS[@]}
            do
                echo "----------------------------------------------------------"
                echo "| 正在运行 =》上传指定镜像 》$ITEM  |"
                echo "----------------------------------------------------------"
                init_environment $ITEM
                for line in `cat /tmp/local.images.data.diff | grep "$keyword"`
                do
                    remote_add_one_image $ITEM $line
                    wait_a_moment
                done

                for line in `cat /tmp/remote.images.data.diff`
                do
                    remote_remove_one_image $ITEM $line
                done
            done
            ;;
        3)
            for ITEM in ${REMOTE_ADDRESS[@]}
            do
                echo "----------------------------------------------------------"
                echo "| 正在运行 =》 清理各个节点的全部镜像 》$ITEM  |"
                echo "----------------------------------------------------------"
                remote_remove_all_image $ITEM
            done
            ;;
        4)
            for ITEM in ${REMOTE_ADDRESS[@]}
            do
                echo "----------------------------------------------------------"
                echo "| 正在运行 =》 清理各个节点的虚悬镜像 》$ITEM  |"
                echo "----------------------------------------------------------"
                remote_remove_dangling_image $ITEM
            done
            ;;
        5)
            echo "退出程序"
            exit 1
            ;;
        *)
            echo "不好意思,没有这个指令请重新输出"
            ;;
    esac
    echo '=============end=============end=============end=============end=============end=============end============='
done
