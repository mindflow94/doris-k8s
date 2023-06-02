#!/bin/bash

echo "======开始下线be!====="
tmp=`mysql -h${FE_MASTER_IP} -P${FE_MASTER_PORT} -uroot -e "ALTER SYSTEM DECOMMISSION BACKEND '${BE_IPADDRESS}:${BE_PORT}'"`
status_sql="select * from information_schema.backends where IP='${BE_IPADDRESS}' and HeartbeatPort='${BE_PORT}'"
result='alive'
echo "=====检查be状态!====="
while [[ -n $result ]]
do
    result=`mysql -h${FE_MASTER_IP} -P${FE_MASTER_PORT} -uroot -e "${status_sql}"`
    echo "正在转移数据，请稍后！"
done
echo "下线完成！"


