#!/bin/bash
set -e
###
# 借鉴 于 https://github.com/summerblue/laravel-ubuntu-init/blob/master/16.04/install.sh
###
CURRENT_DIR=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
source ${CURRENT_DIR}/common/common.sh

MYSQL_ROOT_PASSWORD="123456"

[ $(id -u) != "0" ] && { ansi -n --bold --bg-red "请用 root 账户执行本脚本"; exit 1; }


function init_system {
    ansi --bold --magenta "描述：
    1. 设置字符集utf-8 并且让其支持中文
    2. 安装 add-apt-repository
    "

    export LC_ALL="en_US.UTF-8"
    echo "LC_ALL=en_US.UTF-8" >> /etc/default/locale
    locale-gen en_US.UTF-8
    locale-gen zh_CN.UTF-8

    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

    apt-get update
    apt-get install -y software-properties-common
}

function init_repositories {
    ansi --bold --magenta "描述：
    1. 更换 php 的源 ppa:ondrej/php
    2. 更换 nginx 的源 ppa:nginx/stable
    3. 为所有的 第三方源 配置中科大的 反向代理
    4. 配置yarn 的源
    5. 配置nodejs的源
    "

    # 1.1 添加源
    add-apt-repository -y ppa:ondrej/php
    #add-apt-repository -y ppa:nginx/stable

    # 1.2 中科大提供的反向代理地址是：http://launchpad.proxy.ustclug.org
    grep -rl ppa.launchpad.net /etc/apt/sources.list.d/ | xargs sed -i 's/ppa.launchpad.net/launchpad.proxy.ustclug.org/g'

    # 2. 添加 yarn 的源
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add -
    echo "deb https://dl.yarnpkg.com/debian/ stable main" > /etc/apt/sources.list.d/yarn.list

    if [ $CODENAME == 'bionic' ]; then
        # 3. 添加 nodejs 的源
        curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add -
        echo 'deb https://mirrors.tuna.tsinghua.edu.cn/nodesource/deb_8.x bionic main' > /etc/apt/sources.list.d/nodesource.list
        echo 'deb-src https://mirrors.tuna.tsinghua.edu.cn/nodesource/deb_8.x bionic main' >> /etc/apt/sources.list.d/nodesource.list
    fi

    if [ $CODENAME == 'xenial' ]; then
        # 3. 添加 nodejs 的源
        curl -s https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add -
        echo 'deb https://mirrors.tuna.tsinghua.edu.cn/nodesource/deb_8.x xenial main' > /etc/apt/sources.list.d/nodesource.list
        echo 'deb-src https://mirrors.tuna.tsinghua.edu.cn/nodesource/deb_8.x xenial main' >> /etc/apt/sources.list.d/nodesource.list
    fi

    apt-get update
}

function install_basic_softwares {
    ansi --bold --magenta "描述：
    1. 安装一些基础软件 : curl git build-essential unzip supervisor
    "

    apt-get install -y curl git build-essential unzip supervisor
}

function install_node_yarn {
    ansi --bold --magenta "描述：
    1. 安装nodejs 和 yarn
    2. 并且把 yarn 换源到 taobao mirror
    "
    apt-get install -y nodejs yarn
    sudo -H -u ${WWW_USER} sh -c 'cd ~ && yarn config set registry https://registry.npm.taobao.org'
}

function install_php {
    ansi --bold --magenta "描述：
    1. 安装php${1} 以及 对应的扩展
    "

    version=$1
    apt-get install -y php${version}-bcmath php${version}-cli php${version}-curl \
    php${version}-fpm php${version}-gd php${version}-mbstring php${version}-mysql \
    php${version}-opcache php${version}-pgsql php${version}-readline \
    php${version}-xml php${version}-zip php${version}-sqlite3
}
function install_php56 {
    install_php 5.6
}
function install_php70 {
    install_php 7.0
}
function install_php71 {
    install_php 7.1
}
function install_php72 {
    install_php 7.2
}

function install_others {
    ansi --bold --magenta "描述：安装一些web需要的应用
    1. mysql, 密码为 ${MYSQL_ROOT_PASSWORD}
    2. 安装nginx 、redis 、memcached 、sqlite3
    3，安装 beanstalkd 轻量级 消息队列
    "

    apt-get remove -y apache2
    debconf-set-selections <<< "mysql-server mysql-server/root_password password ${MYSQL_ROOT_PASSWORD}"
    debconf-set-selections <<< "mysql-server mysql-server/root_password_again password ${MYSQL_ROOT_PASSWORD}"
    apt-get install -y nginx mysql-server redis-server memcached beanstalkd sqlite3
    chown -R ${WWW_USER}.${WWW_USER_GROUP} /var/www/
    systemctl enable nginx.service
}

function install_composer {
    ansi --bold --magenta "描述：
    1. Composer 安装
    2. 并且把 composer 换源到 laravel-china
    "

    wget https://dl.laravel-china.org/composer.phar -O /usr/local/bin/composer
    chmod +x /usr/local/bin/composer
    sudo -H -u ${WWW_USER} sh -c  'cd ~ && composer config -g repo.packagist composer https://packagist.laravel-china.org'
}

call_function init_system "1.正在初始化系统"

call_function init_repositories "2.正在初始化软件源"

call_function install_basic_softwares "3. 正在安装基础软件"

call_function install_php56 "4. 正在安装 PHP5.6"
call_function install_php70 "5. 正在安装 PHP7.0"
call_function install_php71 "6. 正在安装 PHP7.1"
call_function install_php72 "7. 正在安装 PHP7.2"

call_function install_others "8. 正在安装 Mysql / Nginx / Redis / Memcached / Beanstalkd / Sqlite3"

call_function install_node_yarn "9. 正在安装 Nodejs / Yarn"

call_function install_composer "10. 正在安装 Composer"

ansi --green --bold -n "恭喜！！！ linux 环境安装完毕"
