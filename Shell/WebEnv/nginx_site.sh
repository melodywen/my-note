#!/bin/bash

CURRENT_DIR=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
source ${CURRENT_DIR}/common/common.sh

[ $(id -u) != "0" ] && { ansi -n --bold --bg-red "请用 root 账户执行本脚本"; exit 1; }

# 1. 可选参数
usage="$(basename "$0") -- nginx site manager tool

where:
    -h  Help
    -r  Set project directory
    -f  Set the version of php-fpm in nginx site （such as ：7.0 、7.1）
    -p  Set project name
    -d  set project domain
    -t  set fastcgi_pass type (such as: sock、php-cgi );
"

while getopts 'r:f:p:d:t:h' OPT; do
    case $OPT in
        r)
            ROOT_DIR="$OPTARG";;
        f)
            FPM="$OPTARG";;
        p)
            PROJECT="$OPTARG";;
        d)
            DOMAIN="$OPTARG";;
        t)
            PASS_TYPE="$OPTARG";;
        h)
            ansi --bold --magenta "$usage"
            exit 1
            ;;
        ?)
            ansi --bold --red "Usage: `basename ` [options] filename"
            echo "\n"
            ansi --bold --magenta "$usage"
            exit 1
            ;;
    esac
done


# 2.初始化值

ansi --bold --green "nginx 的站点管理
"

if [[ ! -n $ROOT_DIR ]]; then
    read -r -p "请输入站点的项目根目录（默认值为：/vagrant ）：" ROOT_DIR
    if [[ ! -n $ROOT_DIR ]]; then
        ROOT_DIR="/vagrant"
    fi
fi
if [[ ! -n $FPM ]]; then
    read -r -p "请输入使用php-fpm的php版本（默认值为：7.1，比如：7.0、7.1 ）：" FPM
    if [[ ! -n $FPM ]]; then
        FPM="7.1"
    fi
fi
if [[ ! -n $PROJECT ]]; then
    read -r -p "请输入对应的项目名称（比如：laravel-blog）：" PROJECT
fi
if [[ ! -n $DOMAIN ]]; then
    read -r -p "请输入对应的项目的域名（比如：www.laravel.local）：" DOMAIN
fi
if [[ ! -n $PASS_TYPE ]]; then
    read -r -p "请输入使用php-fpm的类型（默认值为：sock，比如：sock、php-cgi ）：" PASS_TYPE
    if [[ ! -n $PASS_TYPE ]]; then
        PASS_TYPE="sock"
    fi
fi

ansi -n --bold --green "域名：${DOMAIN}"
ansi -n --bold --green "项目名：${PROJECT}"
ansi -n --bold --green "项目根路径：${ROOT_DIR}"
ansi -n --bold --green "反向代理的方式：${PASS_TYPE}"
ansi -n --bold --green "使用的php-fpm版本：${FPM}"

read -r -p "是否确认？ [y/N] " response
case "$response" in
    [yY][eE][sS]|[yY])
        ;;
    *)
        ansi -n --bold --bg-red "用户取消"
        exit 1
        ;;
esac

# 3. 生成站点
ROOT_DIR=$(echo $ROOT_DIR | sed "s/\/$//")

NGINX_SITE_PATH="/etc/nginx/sites-available/${DOMAIN}"

cp ${CURRENT_DIR}/nginx_site_conf.tpl ${NGINX_SITE_PATH}

sed -i "s|{{domain}}|${DOMAIN}|g" ${NGINX_SITE_PATH}
sed -i "s|{{project}}|${PROJECT}|g" ${NGINX_SITE_PATH}
sed -i "s|{{project_dir}}|${ROOT_DIR}/${PROJECT}|g" ${NGINX_SITE_PATH}

if [[ $PASS_TYPE == 'sock' ]]; then
    sed -i "s|{{fastcgi_pass_value}}|unix:/var/run/php/php{{php_fpm}}-fpm.sock|g" ${NGINX_SITE_PATH}
fi
if [[ $PASS_TYPE == 'php-cgi' ]]; then
    sed -i "s|{{fastcgi_pass_value}}|127.0.0.1:9000|g" ${NGINX_SITE_PATH}
fi

sed -i "s|{{php_fpm}}|${FPM}|g" ${NGINX_SITE_PATH}

ln -sf $NGINX_SITE_PATH /etc/nginx/sites-enabled/${DOMAIN}

# 4. 最后重启并提示
ansi -n --bold --green "配置文件创建成功";

mkdir -p ${ROOT_DIR} && chown -R ${WWW_USER}:${WWW_USER_GROUP} ${ROOT_DIR}

systemctl restart nginx.service

ansi -n --bold --green "Nginx 重启成功";
