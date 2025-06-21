#!/bin/bash

set -o errexit

download(){
  # wget安装
  if [[ ! `which wget` ]]; then
    if check_sys sysRelease ubuntu;then
        apt-get install -y wget dmidecode
    elif check_sys sysRelease centos;then
        yum install -y wget dmidecode
    fi 
  fi

  local url1=$1
  local url2=$2
  local filename=$3

  # 检查文件是否存在
  # if [[ -f $filename ]]; then
  #   echo "$filename 文件已经存在，忽略"
  #   return
  # fi

  speed1=`curl -m 5 -L -s -w '%{speed_download}' "$url1" -o /dev/null || true`
  speed1=${speed1%%.*}
  speed2=`curl -m 5 -L -s -w '%{speed_download}' "$url2" -o /dev/null || true`
  speed2=${speed2%%.*}
  echo "speed1:"$speed1
  echo "speed2:"$speed2
  url="$url1\n$url2"
  if [[ $speed2 -gt $speed1 ]]; then
    url="$url2\n$url1"
  fi
  echo -e $url | while read l;do
    echo "using url:"$l
    wget --dns-timeout=5 --connect-timeout=5 --read-timeout=10 --tries=2 "$l" -O $filename && break
  done
  
}


#判断系统版本
check_sys(){
    local checkType=$1
    local value=$2

    local release=''
    local systemPackage=''
    local packageSupport=''

    if [[ "$release" == "" ]] || [[ "$systemPackage" == "" ]] || [[ "$packageSupport" == "" ]];then

        if [[ -f /etc/redhat-release ]];then
            release="centos"
            systemPackage="yum"
            packageSupport=true

        elif cat /etc/issue | grep -q -E -i "debian";then
            release="debian"
            systemPackage="apt"
            packageSupport=true

        elif cat /etc/issue | grep -q -E -i "ubuntu";then
            release="ubuntu"
            systemPackage="apt"
            packageSupport=true

        elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat";then
            release="centos"
            systemPackage="yum"
            packageSupport=true

        elif cat /proc/version | grep -q -E -i "debian";then
            release="debian"
            systemPackage="apt"
            packageSupport=true

        elif cat /proc/version | grep -q -E -i "ubuntu";then
            release="ubuntu"
            systemPackage="apt"
            packageSupport=true

        elif cat /proc/version | grep -q -E -i "centos|red hat|redhat";then
            release="centos"
            systemPackage="yum"
            packageSupport=true

        else
            release="other"
            systemPackage="other"
            packageSupport=false
        fi
    fi

    echo -e "release=$release\nsystemPackage=$systemPackage\npackageSupport=$packageSupport\n" > /tmp/ezhttp_sys_check_result

    if [[ $checkType == "sysRelease" ]]; then
        if [ "$value" == "$release" ];then
            return 0
        else
            return 1
        fi

    elif [[ $checkType == "packageManager" ]]; then
        if [ "$value" == "$systemPackage" ];then
            return 0
        else
            return 1
        fi

    elif [[ $checkType == "packageSupport" ]]; then
        if $packageSupport;then
            return 0
        else
            return 1
        fi
    fi
}

# 安装mysql
install_mysql() {
    if mysql -uroot -p@cdnflypass -e 'select 1';then
        return 0
    fi

    if check_sys sysRelease ubuntu;then
        export DEBIAN_FRONTEND="noninteractive"
        debconf-set-selections <<< "mariadb-server mysql-server/root_password password @cdnflypass"
        debconf-set-selections <<< "mariadb-server mysql-server/root_password_again password @cdnflypass"         
        apt-get update
        apt-get install -y mariadb-server
        systemctl start mysql
        systemctl enable mysql

    elif check_sys sysRelease centos;then
        yum install -y mariadb-server
        my_cnf_path="/etc/my.cnf"
        if [[ ! -f "$my_cnf_path" ]];then
          my_cnf_path="/etc/my.cnf.d/server.cnf"
        fi

        if [[ `grep max_allowed_packet $my_cnf_path` == "" ]];then
            sed -i '/\[mysqld\]/amax_allowed_packet=10M' $my_cnf_path
            sed -i '/\[mysqld\]/a\bind-address=127.0.0.1' $my_cnf_path
            sed -i '/\[mysqld\]/a\max_connections=1000' $my_cnf_path
        fi    
        systemctl start mariadb
        systemctl enable mariadb    
    fi    

    /usr/bin/mysqladmin -u root password '@cdnflypass'
    mysql -uroot -p@cdnflypass -e "CREATE DATABASE cdn CHARSET=UTF8;"
    mysql -uroot -p@cdnflypass -e 'grant all privileges on *.* to "root"@"127.0.0.1" identified by "@cdnflypass"'
    mysql -uroot -p@cdnflypass -e "grant all privileges on *.* to \"root\"@\"$MASTER_IP\" identified by '@cdnflypass'"
    mysql -uroot -p@cdnflypass -e 'grant all privileges on *.* to "root"@"localhost" identified by "@cdnflypass"'

}

# 安装pip模块
install_pip_module() {
    if check_sys sysRelease ubuntu;then
        apt-get -y install gcc python-dev libmysqlclient-dev libffi-dev libssl-dev
        apt-get install python-imaging -y
        apt-get install libjpeg62-dev -y
        apt-get install zlib1g-dev -y
        apt-get install libfreetype6-dev -y
        apt-get install python-cffi -y
        apt install python-pip -y

    elif check_sys sysRelease centos;then
        cd /etc/yum.repos.d
        mv epel.repo epel.repo_bak_bak
        download "https://github.com/LoveesYe/cdnflydadao/raw/main/master/epel.repo" "https://github.com/LoveesYe/cdnflydadao/raw/main/master/epel.repo" "epel.repo"

        sed -i 's#https://#http://#g' /etc/yum.repos.d/epel*repo
        yum --enablerepo=epel install python-pip gcc python-devel mariadb-devel libffi-devel -y || true
        if [[ `yum list installed  | grep python2-pip` == "" ]]; then
            sed -i 's#mirrors.aliyun.com#mirrors.tuna.tsinghua.edu.cn#' /etc/yum.repos.d/epel.repo
            yum --enablerepo=epel install python-pip gcc python-devel mariadb-devel libffi-devel -y
        fi
    fi    
    

    cd /tmp
    download "https://github.com/wyusgw/CDN/releases/download/v1.11.0/pymodule-master-20211219.tar.gz" "https://github.com/wyusgw/CDN/releases/download/v1.11.0/pymodule-master-20211219.tar.gz" "pymodule-master-20211219.tar.gz"
    tar xf pymodule-master-20211219.tar.gz
    cd pymodule-master-20211219

    # 系统环境安装
    ## pip
    pip install pip-20.1.1-py2.py3-none-any.whl 
    ## setuptools
    pip install setuptools-30.1.0-py2.py3-none-any.whl
    ## supervisor
    pip install supervisor-4.2.0-py2.py3-none-any.whl
    ## virtualenv
    pip install configparser-4.0.2-py2.py3-none-any.whl
    pip install scandir-1.10.0.tar.gz
    pip install typing-3.7.4.1-py2-none-any.whl
    pip install contextlib2-0.6.0.post1-py2.py3-none-any.whl
    pip install zipp-1.2.0-py2.py3-none-any.whl
    pip install six-1.15.0-py2.py3-none-any.whl
    pip install singledispatch-3.4.0.3-py2.py3-none-any.whl
    pip install distlib-0.3.0.zip
    pip install pathlib2-2.3.5-py2.py3-none-any.whl
    pip install importlib_metadata-1.6.1-py2.py3-none-any.whl
    pip install appdirs-1.4.4-py2.py3-none-any.whl
    pip install filelock-3.0.12.tar.gz
    pip install importlib_resources-2.0.1-py2.py3-none-any.whl
    pip install virtualenv-20.0.25-py2.py3-none-any.whl

    # 创建虚拟环境
    cd /opt
    python -m virtualenv -vv --extra-search-dir /tmp/pymodule-master-20211219 --no-download --no-periodic-update venv
    ## 激活环境
    source /opt/venv/bin/activate

    # 虚拟环境安装
    cd /tmp/pymodule-master-20211219

    ## Flask
    pip install click-7.1.2-py2.py3-none-any.whl
    pip install itsdangerous-1.1.0-py2.py3-none-any.whl
    pip install Werkzeug-1.0.1-py2.py3-none-any.whl 
    pip install MarkupSafe-1.1.1-cp27-cp27mu-manylinux1_x86_64.whl 
    pip install Jinja2-2.11.2-py2.py3-none-any.whl 
    pip install Flask-1.1.1-py2.py3-none-any.whl
    ## PyMySQL
    pip install PyMySQL-0.9.3-py2.py3-none-any.whl 
    ## Pillow
    pip install Pillow-6.2.2-cp27-cp27mu-manylinux1_x86_64.whl 
    ## pycryptodome
    pip install pycryptodome-3.9.7-cp27-cp27mu-manylinux1_x86_64.whl 
    ## bcrypt
    pip install pycparser-2.20-py2.py3-none-any.whl 
    pip install cffi-1.14.0-cp27-cp27mu-manylinux1_x86_64.whl 
    pip install six-1.15.0-py2.py3-none-any.whl 
    pip install bcrypt-3.1.7-cp27-cp27mu-manylinux1_x86_64.whl
    ## pyOpenSSL
    pip install ipaddress-1.0.23-py2.py3-none-any.whl 
    pip install enum34-1.1.10-py2-none-any.whl 
    pip install cryptography-2.9.2-cp27-cp27mu-manylinux2010_x86_64.whl
    pip install pyOpenSSL-19.1.0-py2.py3-none-any.whl 
    ## python_dateutil
    pip install python_dateutil-2.8.1-py2.py3-none-any.whl
    ## aliyun-python-sdk-core
    pip install jmespath-0.10.0-py2.py3-none-any.whl 
    pip install aliyun-python-sdk-core-2.13.19.tar.gz
    ## aliyun-python-sdk-alidns
    pip install aliyun-python-sdk-alidns-2.0.18.tar.gz 
    ## qcloudapi-sdk-python
    pip install qcloudapi-sdk-python-2.0.15.tar.gz
    ## requests
    pip install certifi-2020.4.5.2-py2.py3-none-any.whl 
    pip install idna-2.9-py2.py3-none-any.whl
    pip install chardet-3.0.4-py2.py3-none-any.whl 
    pip install urllib3-1.25.9-py2.py3-none-any.whl
    pip install requests-2.24.0-py2.py3-none-any.whl
    pip install forcediphttpsadapter-1.0.2.tar.gz

    ## psutil
    pip install psutil-5.7.0.tar.gz
    ## dnspython
    pip install dnspython-1.16.0-py2.py3-none-any.whl
    ## Flask-Compress
    pip install Brotli-1.0.7-cp27-cp27mu-manylinux1_x86_64.whl 
    pip install Flask-Compress-1.5.0.tar.gz
    ## supervisor
    pip install supervisor-4.2.0-py2.py3-none-any.whl
    ## APScheduler
    pip install funcsigs-1.0.2-py2.py3-none-any.whl 
    pip install futures-3.3.0-py2-none-any.whl 
    pip install pytz-2020.1-py2.py3-none-any.whl 
    pip install tzlocal-2.1-py2.py3-none-any.whl 
    pip install APScheduler-3.6.3-py2.py3-none-any.whl 
    ## gunicorn
    pip install gunicorn-19.10.0-py2.py3-none-any.whl
    ## gevent
    pip install zope.event-4.4-py2.py3-none-any.whl 
    pip install greenlet-0.4.16-cp27-cp27mu-manylinux1_x86_64.whl
    pip install zope.interface-5.1.0-cp27-cp27mu-manylinux2010_x86_64.whl 
    pip install gevent-20.6.2-cp27-cp27mu-manylinux2010_x86_64.whl 
    ## python_daemon
    pip install docutils-0.16-py2.py3-none-any.whl
    pip install lockfile-0.12.2-py2.py3-none-any.whl
    pip install python_daemon-2.2.4-py2.py3-none-any.whl

    ## weixin-python
    pip install lxml-4.5.2-cp27-cp27mu-manylinux1_x86_64.whl
    pip install weixin-python-0.5.7.tar.gz

    ## alipay-sdk-python
    pip install pyasn1-0.4.8-py2.py3-none-any.whl
    pip install rsa-4.5-py2.py3-none-any.whl
    pip install pycrypto-2.6.1.tar.gz
    pip install alipay-sdk-python-3.3.398.tar.gz
    
    deactivate

}

install_acme() {
    if [[ ! -d "/root/.acme.sh/" ]]; then
        if check_sys sysRelease ubuntu;then
            apt-get install -y unzip openssl ca-certificates
        elif check_sys sysRelease centos;then
            yum install -y unzip  openssl ca-certificates
        fi  

        cd /tmp
        download "https://github.com/LoveesYe/cdnflydadao/raw/main/master/acme.sh-3.0.1.zip" "https://github.com/LoveesYe/cdnflydadao/raw/main/master/acme.sh-3.0.1.zip" "acme.sh-3.0.1.zip"
        unzip acme.sh-3.0.1.zip
        cd acme.sh-3.0.1
        ./acme.sh --install --nocron    
        cd  /root/.acme.sh/dnsapi
        ln -s /opt/cdnfly/master/conf/dnsdun.sh
    fi

}

sync_time(){
    echo "start to sync time and add sync command to cronjob..."

    if [[ $ignore_ntp == false ]]; then
      if check_sys sysRelease ubuntu || check_sys sysRelease debian;then
          apt-get -y update
          apt-get -y install ntpdate wget
          /usr/sbin/ntpdate -u pool.ntp.org || true
          ! grep -q "/usr/sbin/ntpdate -u pool.ntp.org" /var/spool/cron/crontabs/root > /dev/null 2>&1 && echo '*/10 * * * * /usr/sbin/ntpdate -u pool.ntp.org > /dev/null 2>&1 || (date_str=`curl update.cdnfly.cn/common/datetime` && timedatectl set-ntp false && echo $date_str && timedatectl set-time "$date_str" )'  >> /var/spool/cron/crontabs/root
          service cron restart
      elif check_sys sysRelease centos; then
          yum -y install ntpdate wget
          /usr/sbin/ntpdate -u pool.ntp.org || true
          ! grep -q "/usr/sbin/ntpdate -u pool.ntp.org" /var/spool/cron/root > /dev/null 2>&1 && echo '*/10 * * * * /usr/sbin/ntpdate -u pool.ntp.org > /dev/null 2>&1 || (date_str=`curl update.cdnfly.cn/common/datetime` && timedatectl set-ntp false && echo $date_str && timedatectl set-time "$date_str" )' >> /var/spool/cron/root
          service crond restart
      fi
    fi

    # 时区
    rm -f /etc/localtime
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

    if /sbin/hwclock -w;then
        return
    fi 

}

config() {
    ES_PWD=`cat /opt/es_pwd`
    sed -i "s/localhost/$MYSQL_IP/" /opt/cdnfly/master/conf/config.py
    sed -i "s/192.168.0.30/$ES_IP/" /opt/cdnfly/master/conf/config.py
    sed -i "s#ES_PWD#$ES_PWD#" /opt/cdnfly/master/conf/config.py
    rnd=`head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16`
    sed -i "s/69294a1afed3f1f4/$rnd/" /opt/cdnfly/master/conf/config.py
    kernel_tune
}

install_es() {
if [[ ! -f "/etc/elasticsearch/elasticsearch.yml" ]]; then
    if check_sys sysRelease ubuntu;then
        cd /tmp
        download "https://github.com/LoveesYe/cdnflydadao/raw/main/master/GPG-KEY-elasticsearch" "https://github.com/LoveesYe/cdnflydadao/raw/main/master/GPG-KEY-elasticsearch" "GPG-KEY-elasticsearch"
        cat GPG-KEY-elasticsearch | sudo apt-key add -
        download "https://mirrors.huaweicloud.com/elasticsearch/7.6.1/elasticsearch-7.6.1-amd64.deb" "https://mirrors.huaweicloud.com/elasticsearch/7.6.1/elasticsearch-7.6.1-amd64.deb" "elasticsearch-7.6.1-amd64.deb"
        dpkg -i elasticsearch-7.6.1-amd64.deb
    elif check_sys sysRelease centos; then
        cd /tmp
        download "https://mirrors.huaweicloud.com/elasticsearch/7.6.1/elasticsearch-7.6.1-x86_64.rpm" "https://mirrors.huaweicloud.com/elasticsearch/7.6.1/elasticsearch-7.6.1-x86_64.rpm" "elasticsearch-7.6.1-x86_64.rpm"
        rpm --install elasticsearch-7.6.1-x86_64.rpm
    fi    

    cat >> /etc/elasticsearch/elasticsearch.yml <<EOF
network.host: 0.0.0.0
node.name: "node-1"
cluster.initial_master_nodes: ["node-1"]
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
EOF

# 设置es目录
sed -i "s#path.data.*#path.data: $ES_DIR#g" /etc/elasticsearch/elasticsearch.yml
mkdir -p $ES_DIR
chown -R elasticsearch $ES_DIR

sed -i '/Service/a\TimeoutSec=600' /usr/lib/systemd/system/elasticsearch.service
systemctl daemon-reload
systemctl enable elasticsearch

# 配置heap_size
sed -i "s/^-Xms.*/-Xms${HEAP_SIZE}m/" /etc/elasticsearch/jvm.options
sed -i "s/^-Xmx.*/-Xmx${HEAP_SIZE}m/" /etc/elasticsearch/jvm.options


# 设置密码
password=`tr -cd '[:alnum:]' </dev/urandom | head -c 32`
password=${password:0:10}
ES_PWD=$password
echo "$ES_PWD" > /opt/es_pwd

echo $password | /usr/share/elasticsearch/bin/elasticsearch-keystore add -xf bootstrap.password
service elasticsearch start
sleep 5
curl -H "Content-Type:application/json" -XPOST -u elastic:$password 'http://127.0.0.1:9200/_xpack/security/user/elastic/_password' -d "{ \"password\" : \"$password\" }"

curl -u elastic:$password -X PUT "localhost:9200/_ilm/policy/access_log_policy" -H 'Content-Type: application/json' -d'
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_size": "200gb",
            "max_age": "1d" 
          }
        }
      },
      "delete": {
        "min_age": "7d",
        "actions": {
          "delete": {} 
        }
      }
    }
  }
}
'

curl -u elastic:$password  -X PUT "localhost:9200/_ilm/policy/node_log_policy" -H 'Content-Type: application/json' -d'
{
  "policy": {
    "phases": {
      "hot": {
        "actions": {
          "rollover": {
            "max_age": "1d" 
          }
        }
      },
      "delete": {
        "min_age": "7d",
        "actions": {
          "delete": {} 
        }
      }
    }
  }
}
'

curl -u elastic:$password  -X PUT "localhost:9200/_template/http_access_template" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "nid":    { "type": "keyword" },  
      "uid":    { "type": "keyword" },  
      "upid":    { "type": "keyword" },  
      "time":   { "type": "date"  ,"format":"dd/MMM/yyyy:HH:mm:ss Z"},
      "addr":  { "type": "keyword"  }, 
      "method":  { "type": "text" , "index":false }, 
      "scheme":  { "type": "keyword"  }, 
      "host":  { "type": "keyword"  }, 
      "server_port":  { "type": "keyword"  }, 
      "req_uri":  { "type": "keyword"  }, 
      "protocol":  { "type": "text" , "index":false }, 
      "status":  { "type": "keyword"  }, 
      "bytes_sent":  { "type": "integer"  }, 
      "referer":  { "type": "keyword"  }, 
      "user_agent":  { "type": "text" , "index":false }, 
      "content_type":  { "type": "text" , "index":false }, 
      "up_resp_time":  { "type": "float" , "index":false,"ignore_malformed": true }, 
      "cache_status":  { "type": "keyword"  }, 
      "up_recv":  { "type": "integer", "index":false,"ignore_malformed": true  }
    }
  },  
  "index_patterns": ["http_access-*"], 
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "index.lifecycle.name": "access_log_policy", 
    "index.lifecycle.rollover_alias": "http_access"
  }
}
'

curl -u elastic:$password  -X PUT "localhost:9200/http_access-000001?pretty" -H 'Content-Type: application/json' -d'
{

  "aliases": {
    "http_access":{
      "is_write_index": true 
    }
  }  
}
'

curl -u elastic:$password  -X PUT "localhost:9200/_template/stream_access_template" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "nid":    { "type": "keyword" },
      "uid":    { "type": "keyword" },
      "upid":    { "type": "keyword" },
      "port":  { "type": "keyword"  }, 
      "addr":  { "type": "keyword"  }, 
      "time":   { "type": "date"  ,"format":"dd/MMM/yyyy:HH:mm:ss Z"},
      "status":  { "type": "keyword"  }, 
      "bytes_sent":  { "type": "integer" , "index":false }, 
      "bytes_received":  { "type": "keyword"  }, 
      "session_time":  { "type": "integer" , "index":false }
    }
  },  
  "index_patterns": ["stream_access-*"], 
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "index.lifecycle.name": "access_log_policy", 
    "index.lifecycle.rollover_alias": "stream_access"
  }
}
'
curl -u elastic:$password  -X PUT "localhost:9200/stream_access-000001?pretty" -H 'Content-Type: application/json' -d'
{
  "aliases": {
    "stream_access":{
      "is_write_index": true 
    }
  } 
}
'

curl -u elastic:$password  -X PUT "localhost:9200/_template/bandwidth_template" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "time":   { "type": "date"  ,"format":"yyyy-MM-dd HH:mm:ss"},
      "node_id":  { "type": "keyword"  },
      "nic":  { "type": "keyword"  },
      "inbound":  { "type": "long", "index":false  },
      "outbound":  { "type": "long", "index":false  }
    }
  },  
  "index_patterns": ["bandwidth-*"], 
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "index.lifecycle.name": "node_log_policy", 
    "index.lifecycle.rollover_alias": "bandwidth"
  }
}
'
curl -u elastic:$password  -X PUT "localhost:9200/bandwidth-000001?pretty" -H 'Content-Type: application/json' -d'
{
  "aliases": {
    "bandwidth":{
      "is_write_index": true 
    }
  } 
}
'

curl -u elastic:$password  -X PUT "localhost:9200/_template/nginx_status_template" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "time":   { "type": "date"  ,"format":"yyyy-MM-dd HH:mm:ss"},
      "node_id":  { "type": "keyword"  },
      "active_conn":  { "type": "integer" , "index":false }, 
      "reading":  { "type": "integer" , "index":false }, 
      "writing":  { "type": "integer" , "index":false }, 
      "waiting":  { "type": "integer" , "index":false }
    }
  },  
  "index_patterns": ["nginx_status-*"], 
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "index.lifecycle.name": "node_log_policy", 
    "index.lifecycle.rollover_alias": "nginx_status"
  }
}
'
curl -u elastic:$password  -X PUT "localhost:9200/nginx_status-000001?pretty" -H 'Content-Type: application/json' -d'
{
  "aliases": {
    "nginx_status":{
      "is_write_index": true 
    }
  } 
}
'

curl -u elastic:$password  -X PUT "localhost:9200/_template/sys_load_template" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "time":   { "type": "date"  ,"format":"yyyy-MM-dd HH:mm:ss"},
      "node_id":  { "type": "keyword"  },
      "cpu":  { "type": "float" , "index":false },
      "load":  { "type": "float" , "index":false },
      "mem":  { "type": "float" , "index":false }
    }
  },  
  "index_patterns": ["sys_load-*"], 
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "index.lifecycle.name": "node_log_policy", 
    "index.lifecycle.rollover_alias": "sys_load"
  }
}
'
curl -u elastic:$password  -X PUT "localhost:9200/sys_load-000001?pretty" -H 'Content-Type: application/json' -d'
{
  "aliases": {
    "sys_load":{
      "is_write_index": true 
    }
  } 
}
'

curl -u elastic:$password  -X PUT "localhost:9200/_template/disk_usage_template" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "time":   { "type": "date"  ,"format":"yyyy-MM-dd HH:mm:ss"},
      "node_id":  { "type": "keyword"  },
      "path":  { "type": "keyword"  },
      "space":  { "type": "float" , "index":false },
      "inode":  { "type": "float" , "index":false }      
    }
  },  
  "index_patterns": ["disk_usage-*"], 
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "index.lifecycle.name": "node_log_policy", 
    "index.lifecycle.rollover_alias": "disk_usage"
  }
}
'
curl -u elastic:$password  -X PUT "localhost:9200/disk_usage-000001?pretty" -H 'Content-Type: application/json' -d'
{
  "aliases": {
    "disk_usage":{
      "is_write_index": true 
    }
  } 
}
'

curl -u elastic:$password  -X PUT "localhost:9200/_template/tcp_conn_template" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "time":   { "type": "date"  ,"format":"yyyy-MM-dd HH:mm:ss"},
      "node_id":  { "type": "keyword"  },
      "conn":  { "type": "integer" , "index":false }
    }
  },  
  "index_patterns": ["tcp_conn-*"], 
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "index.lifecycle.name": "node_log_policy", 
    "index.lifecycle.rollover_alias": "tcp_conn"
  }
}
'
curl -u elastic:$password  -X PUT "localhost:9200/tcp_conn-000001?pretty" -H 'Content-Type: application/json' -d'
{
  "aliases": {
    "tcp_conn":{
      "is_write_index": true 
    }
  } 
}
'

# pipeline nginx_access_pipeline
curl -u elastic:$password -X PUT "localhost:9200/_ingest/pipeline/nginx_access_pipeline?pretty" -H 'Content-Type: application/json' -d'
{
  "description" : "nginx access pipeline",
  "processors" : [
      {
        "grok": {
          "field": "message",
          "patterns": ["%{DATA:nid}\t%{DATA:uid}\t%{DATA:upid}\t%{DATA:time}\t%{DATA:addr}\t%{DATA:method}\t%{DATA:scheme}\t%{DATA:host}\t%{DATA:server_port}\t%{DATA:req_uri}\t%{DATA:protocol}\t%{DATA:status}\t%{DATA:bytes_sent}\t%{DATA:referer}\t%{DATA:user_agent}\t%{DATA:content_type}\t%{DATA:up_resp_time}\t%{DATA:cache_status}\t%{GREEDYDATA:up_recv}"]
        }
      },
      {
          "remove": {
            "field": "message"
          }      
      }       
  ]
}
'

# stream_access_pipeline
curl -u elastic:$password -X PUT "localhost:9200/_ingest/pipeline/stream_access_pipeline?pretty" -H 'Content-Type: application/json' -d'
{
  "description" : "stream access pipeline",
  "processors" : [
      {
        "grok": {
          "field": "message",
          "patterns": ["%{DATA:nid}\t%{DATA:uid}\t%{DATA:upid}\t%{DATA:port}\t%{DATA:addr}\t%{DATA:time}\t%{DATA:status}\t%{DATA:bytes_sent}\t%{DATA:bytes_received}\t%{GREEDYDATA:session_time}"]
        }
      },
      {
          "remove": {
            "field": "message"
          }      
      } 
  ]
}
'

# monitor_pipeline
curl -u elastic:$password -X PUT "localhost:9200/_ingest/pipeline/monitor_pipeline?pretty" -H 'Content-Type: application/json' -d'
{
  "description" : "monitor pipeline",
  "processors" : [
      {
        "json" : {
          "field" : "message",
          "add_to_root" : true
        }
      },
      {
          "remove": {
            "field": "message"
          }      
      } 
  ]
}
'

# black_ip
curl -u elastic:$password  -X PUT "localhost:9200/black_ip" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "site_id":    { "type": "keyword" },  
      "ip":    { "type": "keyword" },  
      "filter":    { "type": "text" , "index":false }, 
      "uid":  { "type": "keyword"  }, 
      "exp":  { "type": "keyword"  }, 
      "create_at":  { "type": "keyword"  }
    }
  }
}
'

# white_ip
curl -u elastic:$password  -X PUT "localhost:9200/white_ip" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "site_id":    { "type": "keyword" },  
      "ip":    { "type": "keyword" },  
      "exp":  { "type": "keyword"  }, 
      "create_at":  { "type": "keyword"  }
    }
  }
}
'

# auto_swtich
curl -u elastic:$password  -X PUT "localhost:9200/auto_switch" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "host":  { "type": "text" , "index":false },
      "rule":  { "type": "text" , "index":false },
      "end_at":  { "type": "integer", "index":true }
    }
  }
}
'

# up_res_usage
curl -u elastic:$password  -X PUT "localhost:9200/up_res_usage" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "upid":    { "type": "keyword" },  
      "node_id":    { "type": "keyword" },  
      "bandwidth":    { "type": "integer" , "index":false }, 
      "connection":  { "type": "integer" , "index":false }, 
      "time": { "type": "keyword" }
    }
  }
}
'

# up_res_limit
curl -u elastic:$password  -X PUT "localhost:9200/up_res_limit" -H 'Content-Type: application/json' -d'
{
  "mappings": {
    "properties": {
      "upid":    { "type": "keyword" },  
      "node_id":    { "type": "keyword" },  
      "bandwidth":    { "type": "integer" , "index":false }, 
      "connection":  { "type": "integer" , "index":false }, 
      "expire":  { "type": "keyword" }
    }
  }
}
'

echo "es user:elastic"
echo "es password:$password"

fi    

kernel_tune

}

kernel_tune(){
ulimit -n 65535
ulimit -u 4096
swapoff -a
sysctl -w vm.max_map_count=262144

if [[ ! `grep -q 65535 /etc/security/limits.conf` ]]; then
  echo "*  -  nofile  65535" >> /etc/security/limits.conf
fi

if [[ ! `grep -q 4096 /etc/security/limits.conf` ]]; then
  echo "*  -  nproc  4096" >> /etc/security/limits.conf
fi

if [[ ! `grep -q max_map_count /etc/sysctl.conf` ]]; then
  echo "vm.max_map_count = 262144" >> /etc/sysctl.conf
fi

sed -i -r 's/(.*swap.*)/#\1/' /etc/fstab

}

start_on_boot(){
    local cmd="$1"
    if [[ -f "/etc/rc.local" ]]; then
        sed -i '/exit 0/d' /etc/rc.local
        if [[ `grep "${cmd}" /etc/rc.local` == "" ]];then 
            echo "${cmd}" >> /etc/rc.local
        fi 
        chmod +x /etc/rc.local
    fi


    if [[ -f "/etc/rc.d/rc.local" ]]; then
        sed -i '/exit 0/d' /etc/rc.local
        if [[ `grep "${cmd}" /etc/rc.d/rc.local` == "" ]];then 
            echo "${cmd}" >> /etc/rc.d/rc.local
        fi 
        chmod +x /etc/rc.d/rc.local 
    fi 
}

start() {
    mkdir -p /var/log/cdnfly/
    start_on_boot "supervisord -c /opt/cdnfly/master/conf/supervisord.conf"
    
    if ! supervisord -c /opt/cdnfly/master/conf/supervisord.conf > /dev/null 2>&1;then
        supervisorctl -c /opt/cdnfly/master/conf/supervisord.conf reload
    fi

    # 导入mysql
    if check_sys sysRelease ubuntu;then
        apt-get install mariadb-client -y

    elif check_sys sysRelease centos;then
        yum install -y mariadb
        systemctl stop firewalld.service || true
        systemctl disable firewalld.service || true 
    fi    

    # 替换__OPENRESTY_KEY__
    key=`tr -cd '[:alnum:]' </dev/urandom | head -c 32`
    key=${key:0:10}
    sed -i "s/__OPENRESTY_KEY__/$key/" /opt/cdnfly/master/conf/db.sql 
    mysql -uroot -p@cdnflypass -h $MYSQL_IP cdn < /opt/cdnfly/master/conf/db.sql 

    # 获取授权
    source /opt/venv/bin/activate
    cd /opt/cdnfly/master/view
    ret=`python -c "import util;print util.get_auth_code()" || true`
    [[ $ret == "(True, None)" ]] && echo "已获取到授权" || echo "未授权，请先购买"
    deactivate

    echo "安装主控成功！"
}

need_sys() {
    SYS_VER=`python -c "import platform;import re;sys_ver = platform.platform();sys_ver = re.sub(r'.*-with-(.*)-.*','\g<1>',sys_ver);print sys_ver;"`
    if [[ $SYS_VER =~ "Ubuntu-16.04" ]];then
      echo "$sys_ver"
    elif [[ $SYS_VER =~ "centos-7" ]]; then
      SYS_VER="centos-7"
      echo $SYS_VER
    else  
      echo "目前只支持ubuntu-16.04和Centos-7"
    fi
}

# 检查系统
need_sys

# 解析命令行参数
TEMP=`getopt -o h --long help,no-mysql,only-mysql,no-es,only-es,master-ip:,es-ip:,es-pwd:,es-dir:,mysql-ip: -- "$@"`
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi
eval set -- "$TEMP"

nomysql=false
noes=false
onlymysql=false
onlyes=false
ignore_ntp=false
ES_DIR="/home/es"

while true ; do
    case "$1" in
        -h|--help) help ; exit 1 ;;
        --es-ip) ES_IP=$2 ; shift 2 ;;
        --es-pwd) ES_PWD=$2 ; shift 2 ;;
        --es-dir) ES_DIR=$2 ; shift 2 ;;
        --master-ip) MASTER_IP=$2 ; shift 2 ;;
        --mysql-ip) MYSQL_IP=$2 ; shift 2 ;;
        --no-mysql) nomysql=true ; shift 1 ;;
        --only-mysql) onlymysql=true ; shift 1 ;;
        --no-es) noes=true ; shift 1 ;;
        --only-es) onlyes=true ; shift 1 ;;
        --ignore-ntp) ignore_ntp=true ; shift 1 ;;
        --) shift ; break ;;
        *) echo "Internal error!" ; exit 1 ;;
    esac
done

total_mem=`awk '/MemTotal/{print $2}' /proc/meminfo`
sync_time

# 只安装mysql
if [[ $onlymysql == true ]]; then
    if [[ "$MASTER_IP" == "" ]]; then
        echo "please specify master ip with --master-ip 1.1.1.1 "
        exit 1
    fi

    install_mysql

# 只安装es
elif [[ $onlyes == true ]]; then
    HEAP_SIZE=`awk -v total_mem=$total_mem 'BEGIN{printf ("%.0f", total_mem*0.5/1024)}'`
    install_es

else
    HEAP_SIZE=`awk -v total_mem=$total_mem 'BEGIN{printf ("%.0f", total_mem*0.4/1024)}'`

    # 安装es
    if [[ $noes == false ]]; then
       install_es
       ES_IP="127.0.0.1"

    else
        # 不安装时提供
        if [[ "$ES_IP" == "" ]]; then
            echo "please specify elasticsearch ip with --es-ip 1.1.1.1 "
            exit 1
        fi       

        if [[ "$ES_PWD" == "" ]]; then
            echo "please specify elasticsearch password with --es-pwd [password] "
            exit 1
        fi

        echo "$ES_PWD" > /opt/es_pwd

        # 验证是否能连接
        http_code=`curl -s -w  %{http_code}  -u elastic:$ES_PWD  -X GET "$ES_IP:9200/_cluster/health" -o /dev/null`
        if [[ $http_code == "401" ]]; then
          echo "密码错误，无法连接es"
          exit 1
        fi

        if [[ $http_code != "200" ]]; then
          echo "无法连接es，可能是没有安装"
          exit 1
        fi
    fi
    
    # 安装mysql
    if [[ $nomysql == false ]]; then
        install_mysql
        MYSQL_IP="127.0.0.1"
    else
        # 不安装mysql需要提供ip
        if [[ "$MYSQL_IP" == "" ]]; then
            echo "please specify mysql ip with --mysql-ip 1.1.1.1 "
            exit 1
        fi            
    fi

    install_pip_module
    install_acme
    config
    start    
fi

