#!/usr/bin/bash

set -u
ip=192.168.23.
mha_conf=/etc/mha/app1.conf
mha_log="/usr/local/mha/manager.log"
tmpfile=/tmp/mha_tmpfile

function find_num { 
local num=$1
num=${num#*$ip}
num=${num%$ip*}
num=$(echo "$num" | cut -d '(' -f 1)
ip="$ip$num"
}

check_type=slave_down
function find_ip {
if [ "$check_type" == "slave_down"  ];then 
	local str=$(tail $mha_log -n7 | grep -E  "$ip.* ERROR: Could not be reachable so couldn't recover")
else
	local str=$(grep -E  "\[error\].*Server.*$ip" $tmpfile)
fi
IFS=$'\n'
for item in $str
do   
     find_num $item
     break
done
}


function up {
	find_ip
	numup=$(grep "hostname=$ip" $mha_conf -n | cut -d ":" -f 1 )
	if [ -z "$numup" ];then
		echo "$ip:查无结果！"
		exit 1

	fi
	if [[ ! "$numup" =~ [0-9]+$ ]];then
		echo "$numup 值错误"
	fi
	num=$numup
	local str=$1
	for item in {1..10}
	do
		result=$(awk ' /server/{if(NR=='''$numup''') print NR}' $mha_conf)
		[[ "$result" =~ [0-9]+ ]] && break
		 let numup=numup"$str"1 
	done
	echo $result
}

function man {
	numup=$(up  "-" )
	numdown=$(up  "+" )
	let numdown=$numdown-1
	[ "$numdown" -le 1 ]&&let numdown=$numup+10
	sed -i "$numup,$numdown d " $mha_conf
}

check_type=slave_down	#删除宕机的slave
man	
		
masterha_check_repl --conf=$mha_conf &> $tmpfile
check_type=slave_down_false #删除原先宕机的master
man
>$tmpfile	#清空这个临时文件



msterha_check_repl --conf=$mha_conf &> $tmpfile

if [ "$?" -eq 0  ];then
	echo "检查成功"
	 exit 0
else
for i in 2 3
do 
	sleep 2
	echo "第$i次检查"
	masterha_check_repl --conf=$mha_conf &> $tmpfile
	[ "$?" -eq 0 ] && echo "检查成功" &&exit 0
done
	 echo "检查失败"
	 exit 1
fi

