#!/bin/bash
set -e
SHELL_FOLDER=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )


configOfca(){
    cat>ca.conf<<EOF
[ req ]
default_bits       = 4096
distinguished_name = req_distinguished_name

[ req_distinguished_name ]
countryName                 = Country Name (2 letter code)
countryName_default         = CN
stateOrProvinceName         = State or Province Name (full name)
stateOrProvinceName_default = JiangSu
localityName                = Locality Name (eg, city)
localityName_default        = NanJing
organizationName            = Organization Name (eg, company)
organizationName_default    = Sheld
commonName                  = Common Name (e.g. server FQDN or YOUR name)
commonName_max              = 64
commonName_default          = Ted CA Test
EOF
}

configOfServer(){
    cat>server.conf<<EOF
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = req_ext

[ req_distinguished_name ]
countryName                 = Country Name (2 letter code)
countryName_default         = CN
stateOrProvinceName         = State or Province Name (full name)
stateOrProvinceName_default = JiangSu
localityName                = Locality Name (eg, city)
localityName_default        = NanJing
organizationName            = Organization Name (eg, company)
organizationName_default    = Sheld
commonName                  = Common Name (e.g. server FQDN or YOUR name)
commonName_max              = 64
commonName_default          = xiamotong    # 此处尤为重要，需要用该服务名字填写到客户端的代码中

[ req_ext ]
subjectAltName = @alt_names

[alt_names]
DNS.1   = www.cjw.com
IP      = 127.0.0.1
EOF
}


PREFIX="certs"
# 新建文件夹
if [ ! -d "certs" ]; then 
    echo "创目录"
    mkdir $SHELL_FOLDER/$PREFIX
fi

cd $SHELL_FOLDER/$PREFIX

# 生成ca秘钥，得到ca.key
openssl genrsa -out ca.key 4096

# 2.4生成ca证书签发请求，得到ca.csr
configOfca

openssl req \
  -new \
  -sha256 \
  -out ca.csr \
  -key ca.key \
  -config ca.conf

# 2.5 生成ca根证书，得到ca.crt
openssl x509 \
    -req \
    -days 3650 \
    -in ca.csr \
    -signkey ca.key \
    -out ca.crt

# 生成秘钥，得到server.key
openssl genrsa -out server.key 2048

# 3.3生成证书签发请求，得到server.csr
configOfServer
openssl req \
  -new \
  -sha256 \
  -out server.csr \
  -key server.key \
  -config server.conf

# 3.4用CA证书生成终端用户证书，得到server.crt
openssl x509 \
  -req \
  -days 3650 \
  -CA ca.crt \
  -CAkey ca.key \
  -CAcreateserial \
  -in server.csr \
  -out server.pem\
  -extensions req_ext \
  -extfile server.conf
