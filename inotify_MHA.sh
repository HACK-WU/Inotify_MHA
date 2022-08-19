 #!/usr/bin/bash
set -u
mha_conf=/etc/mha/app1.conf
mha_log="/usr/local/mha/manager.log"
mha_check_slave="/usr/local/mha/check_slave.sh"
function find_str {             #参数：$1,要查找的文件路径。$2:要查找的关键字。
	echo -e "\033[33m检查中，请稍后。。。。\033[0m"
        for i in {1..30}	#默认等待30秒
        do
                num=$( tail $1 -n1 |grep -E "$2" -c )
                [ "$num" -eq 1 ]&& break
                sleep 1

        done
        if [ "$num" -ne 1 ];then
	 	if [ "$2" == "successfully" ];then
	                num=$( tail $1 -n1 |grep -E "Not master dead" -c )
                	if [ "$num" -eq 1 ];then
				echo "状态良好,服务正在运行"
				return 12
			fi 

			echo "正在检查slave服务器"
			bash $mha_check_slave
			if [ "$?" -eq 0 ];then
				return 0 
				echo "检查成功"
			else
				echo "检查失败"
				exit
			fi	
					
		fi

                exit
        fi
        echo "finished"
}


/usr/bin/inotifywait -mq -e modify,attrib $mha_log |while read events
do
    /usr/bin/masterha_check_status --conf=$mha_conf
 if [ $? -eq 0 ];then
    echo "MHA 运行中"
 else
    pkill inotifywait
    find_str $mha_log  successfully
    tag_12=$?
    if [ "$tag_12" -eq 12 ];then
#	nohup /usr/bin/masterha_manager --conf=$mha_conf --remove_dead_master_conf --ignore_last_failover &
	source $0  &
	exit
    fi	

    for item in 1 2 3
    do
       echo "MHA 准备重启"
 
       masterha_check_repl --conf=$mha_conf &>/tmp/mha_tmpfile

       if [ "$?" -eq 0  ];then
             nohup /usr/bin/masterha_manager --conf=$mha_conf --remove_dead_master_conf --ignore_last_failover &
             tag="$?"
             find_str $mha_log  ".+succeeded.+respond"
  
             if [ "$tag" -eq 0  ];then
                 echo -e "\033[33mMHA 启动成功\033[0m"
                 source $0 &
                 exit  
             fi
       fi
       echo "MHA 启动失败"
       sleep 1
    done
  fi
done

