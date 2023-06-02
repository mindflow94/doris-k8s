## 背景

Doris 官网上有 Kubernetes 部署的文档，无奈根据官网的文档，构建完镜像无法成功启动。故参考官网做了一些改动，成功启动 FE、BE 节点。此探索为临时部署方案，还需再完善、优化。

## 版本说明与限制

| 组件         | 版本         |
| ----------- | -----------  |
| Doris       | 1.2.4.1      |
| Docker      | 20.10.23     |
| Kubernetes  | 1.22.12      |

> 使用限制：只支持一个 FE 节点，BE 节点可以弹性扩缩容，支持挂载卷，防止数据丢失。FE、BE 服务挂掉后重新启动，需要短暂等待，节点状态正常后方可访问。

## 部署流程

部署非常简单，创建拷贝 yaml 文件内容，即可启动。若需修改版本，参考下文自定义镜像。以下为示例，详情可以查看 [GitHub doris-k8s](https://github.com/mindflow94/doris-k8s) 

### 启动 FE 服务

fe-pvc-local.yaml
```.yaml
apiVersion: v1
kind: Service              
metadata: 
  name: doris-fe     
  namespace: default       
  labels: 
    app: doris-fe

spec: 
  type: NodePort           
  ports: 
    - name: http
      port: 8030           
      protocol: TCP
      targetPort: 8030       
      nodePort: 32130
    - name: tcp
      port: 9020           
      protocol: TCP
      targetPort: 9020       
      nodePort: 32220
    - name: tcp2
      port: 9030           
      protocol: TCP
      targetPort: 9030       
      nodePort: 32230
    - name: tcp1
      port: 9010           
      protocol: TCP
      targetPort: 9010       
      nodePort: 32210
  selector: 
    app: doris-fe
---
kind: StatefulSet
apiVersion: apps/v1
metadata:
  name: doris-fe
  namespace: default 
  labels:
    app: doris-fe
spec:
  serviceName: "doris-fe-service"
  replicas: 1
  selector:
    matchLabels:
      app: doris-fe
  template:
    metadata:
      labels:
        app: doris-fe
    spec:
      hostNetwork: false
      dnsPolicy: ClusterFirst
      containers:
        - name: doris-fe
          env:
          - name: FE_IPADDRESS
            valueFrom:
              fieldRef:
                fieldPath: status.podIP
          - name: FE_PORT
            value: "9030"
          - name: FE_EDIT_PORT
            value: "9010"
          image: "zyzcenter/apache-doris:1.2.4.1-fe"
          imagePullPolicy: Always
          command: [ "/bin/bash", "-ce", "/opt/apache-doris/fe/bin/start_fe.sh --daemon;tail -f /dev/null" ]
          lifecycle:
            postStart:
              exec:
                command:
                  - bash
                  - -c
                  - '/opt/apache-doris/fe/bin/check_register_fe.sh'
          volumeMounts:
          - mountPath: /opt/apache-doris/fe/doris-meta
            name: volume-fe
          livenessProbe:
            httpGet:
              path: /api/bootstrap
              port: 8030
            initialDelaySeconds: 300
            periodSeconds: 30
            timeoutSeconds: 5
            failureThreshold: 3      
          ports:
            - containerPort: 8030
              protocol: TCP
            - containerPort: 9020
              protocol: TCP
            - containerPort: 9030
              protocol: TCP
            - containerPort: 9010
              protocol: TCP
          resources:
            limits:
              cpu: 2
              memory: 4G
            requests:
              cpu: 200m
              memory: 1G
  volumeClaimTemplates:
  - metadata:
      name: volume-fe
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: "local"
      resources:
        requests:
          storage: 5Gi
```

启动脚本：
```
kubectl create -f fe-pvc-local.yaml
```

### 启动 BE 服务

be-pvc-local.yaml
```.yaml
kind: StatefulSet
apiVersion: apps/v1
metadata:
  name: doris-be
  namespace: default 
  labels:
    app: doris-be
spec:
  serviceName: "doris-be-service"
  replicas: 1
  selector:
    matchLabels:
      app: doris-be
  template:
    metadata:
      labels:
        app: doris-be
    spec:
      hostNetwork: false
      dnsPolicy: ClusterFirst
      terminationGracePeriodSeconds: 120            
      containers:
        - name: doris-be
          env:
            - name: BE_IPADDRESS
              valueFrom:
                 fieldRef:
                   fieldPath: status.podIP
            - name: BE_PORT
              value: "9050"
            - name: FE_MASTER_IP
              value: "doris-fe.default.svc.cluster.local"
            - name: FE_MASTER_PORT
              value: "9030"
            - name: POD_NAME
              valueFrom:
                 fieldRef:
                   fieldPath: metadata.name  
          image: "zyzcenter/apache-doris:1.2.4.1-be"
          imagePullPolicy: Always
          command: [ "/bin/bash", "-ce", "/opt/apache-doris/be/bin/start_be.sh --daemon;tail -f /dev/null" ]
          lifecycle:
            preStop:
              exec:
                command:
                  - bash
                  - -c
                  - '/opt/apache-doris/be/bin/cancel_be.sh;sleep 10'
          volumeMounts:
          - mountPath: /opt/apache-doris/be/storage
            name: volume-be
          livenessProbe:
            httpGet:
              path: /api/health
              port: 8040
            initialDelaySeconds: 300
            periodSeconds: 30
            timeoutSeconds: 5
            failureThreshold: 3 
          ports:
            - containerPort: 9060
              protocol: TCP
            - containerPort: 9070
              protocol: TCP
            - containerPort: 8040
              protocol: TCP
            - containerPort: 9050
              protocol: TCP
            - containerPort: 8060
              protocol: TCP
          resources:
            limits:
              cpu: 2
              memory: 2G
            requests:
              cpu: 200m
              memory: 1G
  volumeClaimTemplates:
  - metadata:
      name: volume-be
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: "local"
      resources:
        requests:
          storage: 10Gi
```

启动脚本：
```
kubectl create -f be-pvc-local.yaml
```

此文件中，需要配置 FE 节点的服务名、端口等信息，若在 `fe-pvc-local.yaml` 中修改了相关信息，需要在`be-pvc-local.yaml`文件中同步修改。

### 访问管理页面

成功启动 FE、BE 服务后，可以登录 Doris 的管理页面，地址为：`集群节点任意IP:32130`，默认用户为：`root`，没有密码，直接登录，可以查看 Doris 的节点、状态等。

## 自定义镜像

本次部署使用的 Doris 版本是 1.2.4.1，若需要其它版本，需要自行构建镜像。构建完镜像，根据`部署流程`流程操作即可，需要修改`fe-pvc-local.yaml`、`be-pvc-local.yaml`，把镜像换成自定义镜像。

### fe镜像

#### 1. 准备二进制包

> 1.1 自行构建二进制包，或者在官网下载，根据服务器配置，选择合适的版本即可。

下载地址：https://archive.apache.org/dist/doris/1.2/1.2.4.1-rc01/

> 1.2 解压二进制包，并且 bin 目录下，新增脚本。

check_register_fe.sh
```.sh
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
```

此脚本会在容器创建后去执行，由于异步执行，和 FE 服务启动的操作无法确定先后顺序，所以会定义循环操作，若 FE 服务未启动，则等待启动；若已经启动，会去检查 frontends 状态，若存在异常退出的 FE 节点，则执行 DROP 操作，若当前节点未注册，则手动注册。

> 1.3 修改start_fe.sh脚本

在start_fe.sh脚本中，增加以下内容：
```
if [ -d "${DORIS_HOME}/doris-meta/image/" ];then
    echo "覆写ROLE信息！"
    cur_timestamp=$((`date '+%s'`*1000+`date '+%N'`/1000000))
    echo "name=${FE_IPADDRESS}_${FE_EDIT_PORT}_${cur_timestamp}" > ${DORIS_HOME}/doris-meta/image/ROLE
    echo "role=FOLLOWER" >> ${DORIS_HOME}/doris-meta/image/ROLE
    echo "查看ROLE信息！"
    cat ${DORIS_HOME}/doris-meta/image/ROLE
    echo "删除bdb的锁文件！"
    find ${DORIS_HOME}/doris-meta/bdb -name *.lck | xargs rm -f
    echo "以节点恢复模式启动"
    echo "metadata_failure_recovery=true" >> ${DORIS_HOME}/conf/fe.conf
else
    echo "首次启动，初始化！"
fi
```

若服务配置了 pvc 挂载，删除服务的时候，pvc 默认不删除。那么，在重新启动服务的时候，会发生 FE 节点无法注册，需要人为修改 FE 节点的 IP、删除异常退出节点的加锁文件、以节点恢复的模式启动等操作。

> 1.4 以上操作完成后，重新打包

```
tar -zcvf apache-doris-fe-1.2.4.1-bin-x86_64.tar.gz apache-doris-fe-1.2.4.1-bin-x86_64
```

#### 2. 构建镜像

fe-Dockerfile
```
# 选择基础镜像
FROM openjdk:8u342-jdk

# 设置环境变量
ENV JAVA_HOME="/usr/local/openjdk-8/" \
    PATH="/opt/apache-doris/fe/bin:$PATH"

ADD apache-doris-fe-1.2.4.1-bin-x86_64.tar.gz /opt

ENV LANG=zh_CN.UTF-8 \
LANGUAGE=zh_CN:zh
ENV DORIS_HOME /opt/apache-doris/fe

RUN apt-get update && \
    apt-get install -y default-mysql-client && \
    apt-get clean && \
    mkdir /opt/apache-doris && \
    mv /opt/apache-doris-fe-1.2.4.1-bin-x86_64 /opt/apache-doris/fe && \
    ls /opt/apache-doris/fe && \
    ls /opt/apache-doris/fe/bin

RUN echo 'priority_networks = ${FE_IPADDRESS}/24' >> /opt/apache-doris/fe/conf/fe.conf

CMD ["tail -f /dev/null"]
```

执行以下命令：
```
# 构建镜像
docker build -f fe-Dockerfile . -t apache-doris:1.2.4.1-fe

# 打tag
docker tag apache-doris:1.2.4.1-fe zyzcenter/apache-doris:1.2.4.1-fe

# 登录自己的私服仓库，并push镜像，保证集群所有节点都可以拉取镜像
docker push zyzcenter/apache-doris:1.2.4.1-fe
```

### be镜像

#### 1. 准备二进制包

> 1.1 自行构建二进制包，或者在官网下载，根据服务器配置，选择合适的版本即可。

下载地址：https://archive.apache.org/dist/doris/1.2/1.2.4.1-rc01/

若 Doris 的版本为 1.2 以上，需要下载 `apache-doris-dependencies-1.2.4.1-bin-x86_64.tar.xz`，解压并把`java-udf-jar-with-dependencies.jar`包拷贝到 BE 二进制包的 `lib` 目录下。

> 1.2 解压二进制包，并且 bin 目录下，新增脚本。

cancel_be.sh
```.sh
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
```

此脚本会在容器退出前执行，配置了`preStop`钩子，暴力退出 BE 节点，会导致某些数据无法访问，所以在缩容的时候，优雅的退出 BE 节点。因为容器退出操作，并不会等`preStop`回调，故可能在容器退出的时候，BE 节点的数据还未转移完，可能需要在`be-pvc-local.yaml`中增加`terminationGracePeriodSeconds`时间，或者需要手动处理异常退出的 BE 节点。这个操作目前的处理方式不够优雅，可以自行修改为更优雅的处理方式。

> 1.3 修改start_be.sh，自动注册到fe节点

修改start_be.sh，增加以下内容：
```
echo "======开始注册 be!====="
mysql -h${FE_MASTER_IP} -P${FE_MASTER_PORT} -uroot -e "ALTER SYSTEM ADD BACKEND '${BE_IPADDRESS}:${BE_PORT}'"
echo "=====检查 be 状态!====="
mysql -h${FE_MASTER_IP} -P${FE_MASTER_PORT} -uroot -e "SHOW PROC '/backends';"
```

在 BE 节点的容器启动脚本中，会自动将自身注册到 FE 服务节点中去，以此来实现扩容的需求。

> 1.4 以上操作完成后，重新打包

```
tar -zcvf apache-doris-be-1.2.4.1-bin-x86_64.tar.gz apache-doris-be-1.2.4.1-bin-x86_64
```

#### 2. 构建镜像

be-Dockerfile
```
# 选择基础镜像
FROM openjdk:8u342-jdk

# 设置环境变量
ENV JAVA_HOME="/usr/local/openjdk-8/" \
    PATH="/opt/apache-doris/be/bin:$PATH"

ADD apache-doris-be-1.2.4.1-bin-x86_64.tar.gz /opt

ENV LANG=zh_CN.UTF-8 \
LANGUAGE=zh_CN:zh
ENV DORIS_HOME /apache-doris/be

RUN apt-get update && \
    apt-get install -y default-mysql-client && \
    apt-get clean && \
    mkdir /opt/apache-doris && \
    mv /opt/apache-doris-be-1.2.4.1-bin-x86_64 /opt/apache-doris/be && \
    ls /opt/apache-doris/be && \
    ls /opt/apache-doris/be/bin

RUN echo 'priority_networks = ${BE_IPADDRESS}/24' >> /opt/apache-doris/be/conf/be.conf

CMD ["tail -f /dev/null"]
```

执行以下脚本：
```
# 构建镜像
docker build -f be-Dockerfile . -t apache-doris:1.2.4.1-be

# 打tag
docker tag apache-doris:1.2.4.1-be zyzcenter/apache-doris:1.2.4.1-be

# 登录自己的私服仓库，并push镜像，保证集群所有节点都可以拉取镜像
docker push zyzcenter/apache-doris:1.2.4.1-be
```