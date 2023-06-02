#!/bin/bash
current_ip_register='false'
# 定义方法，循环10次，每次休眠10秒。成功查询到结果退出或者10次后退出
run_sql(){
  j=0
  while [ $j -lt 10 ]
  do
    set +e
    results=$(mysql -uroot -h$FE_IPADDRESS -P$FE_PORT -N -e "SHOW PROC '/frontends';")

    if [ -n "$results" ]
    then
      echo "SQL query frontends executed successfully！"

      # 获取执行结果
      echo "$results" | while read -a row; do
        # Loop through the fields in each row
        row_ip=''
        row_edit_port=''
        row_alive=''
        row_master=''
	i=0
        for item in ${row[*]}
	do
          # Do something with the field value
          if [ 1 -eq $i ]
          then
             row_ip=${item}
          elif [ 3 -eq $i ]
          then
             row_edit_port=${item}
          elif [ 7 -eq $i ]
          then
             row_role=${item}
          elif [ 8 -eq $i ]
          then
             row_master=${item}
          elif [ 11 -eq $i ]
          then
             row_alive=${item}
          fi
	i=$((i+1))
        done

        # 处理每一条记录
        # 删除无法连接的fe节点
        if [ 'false' = $row_alive ]
        then
           echo "节点:${row_ip} is not alive,remove it!"
           mysql -h${FE_IPADDRESS} -P${FE_PORT} -uroot -e "ALTER SYSTEM DROP ${row_role} '${row_ip}:${row_edit_port}'"
        fi
        # 判断数据库中当前节点是否注册
        if [[ $FE_IPADDRESS = $row_ip ]] && [[ 'true' = $row_alive ]]
        then
           current_ip_register='true'
           echo "当前节点:${row_ip} 已经成功注册!"
        fi
      done

      # 若当前节点没有注册，则重新注册
      if [ 'true' != $current_ip_register ]
      then
         echo "当前节点:${FE_IPADDRESS} 未注册,开始注册fe节点!"
         mysql -h${FE_IPADDRESS} -P${FE_PORT} -uroot -e "ALTER SYSTEM ADD FOLLOWER '${FE_IPADDRESS}:${FE_EDIT_PORT}'"
         echo "查看fe状态！"
	 sleep 1
         mysql -h${FE_IPADDRESS} -P${FE_PORT} -uroot -e "SHOW PROC '/frontends'"
      fi

      break
    fi

    j=$((j+1))
	echo "第${j}次循环结束！"
    sleep 10
  done

  if [ $j -ge 10 ]
  then
    echo "SQL execution failed after 10 tries"
  fi
}
# 执行方法
run_sql
