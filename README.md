# Inotify实现监控MHA以及从服务器健康状况

* MHA 版本 0.57

* 此*MHA* 架构中，当masterha_manager处于监控状态时，如果有slave服务器宕机，之后MHA进行故障切换时，可能会导致故障切换失败。

* 但是如果在配置文件中，给[server]加上`ignore_fail=1`，启动时加上选项`--ignore_fail_on_start`那么故障切换时就可以忽略宕机的服务器了，从而可以切换master成功。

  ```shell
  [root@server1 ~]# vim /etc/mha/app1.conf
  ......
  [server1]
  hostname=10.0.0.21
  candidate_master=1    #可以成为 master
  ignore_fail=1        #如果此节点宕机，则自动忽略这个配置，但是需要配合--ignore_fail_on_start启动才有效果
  
  
  [root@server1 ~]# nohup masterha_manager --conf=/etc/mha/app1.conf --remove_dead_master_conf  \
  --ignore_last_failover --ignore_fail_on_start &
  ```

* 但是用这个方法，即使启动选项加上了`--remove_dead_master_conf`但实际上，并不会移除宕机的服务器的信息，无论是slave还是master，简单来说就是不会对配置文件有任何的更改。
* 并且只要故障切换之后，masterha_manager,就会停止工作。如果需要继续监控，就需要手动启动。

## 提出问题

* 那么有没有什么方法可以实现，MHA架构中，故障切换之后masterha_manager可以自动启动。
* 并且就算，mster_manager监控过程中有slave服务器宕机，也不影响再次启动。
* 而且会将宕机的服务器的信息从mha/app1.conf配置文件中删除呢？

## 解决办法

* 可以用inotify监控日志文件，如有任何动向就判断MHA的运行状态
  * masterha_check_status --conf=/etc/mha/app1.conf
* 如果状态为running，就停止操作。
* 如果状态为停止服务，就自动分析日志文件的内容，判断其是否在执行故障切换操作。
* 并且还会检查有无从服务器宕机，如果有从服务器宕机，就将其对应的信息从配置文件中删除。
* 最后会自动重启masterha_manager.





# 环境准备

* 第一步：搭建一主多从复制架构

*  第二步：检测集群状态

  ```shell
   masterha_check_repl --conf=/etc/mha/app1.conf 
  ```

![image-20220819182708062](https://hackwu-images-1305994922.cos.ap-nanjing.myqcloud.com/images/image-20220819182708062.png)

由上图可知，总共是一主三从，处于健康状态。

* master是：192.168.23.15
  * 192.168.23.26		从
  * 192.168.23.22        从
  * 192.168.23.24        从

**注意点：配置文件中，需要加入ignore_fail=1选项**

~~~shell
[server1]
candidate_master=1
hostname=192.168.23.25
ignore_fail=1
~~~

* 第三步：开启MHA manager监控

```shell
nohup masterha_manager --conf=/etc/mha/app1.conf --remove_dead_master_conf --ignore_last_failover \
--ignore_fail_on_start &

#一定要加上一下选项
#  --remove_dead_master_conf
#  --ignore_fail_on_start
```

![image-20220819183446706](https://hackwu-images-1305994922.cos.ap-nanjing.myqcloud.com/images/image-20220819183446706.png)

> 开启成功！！



# 脚本修改

* 修改check_slave.sh

```shell
vim check_slave.sh

ip=192.168.23.					#MHA架构的网段
mha_conf=/etc/mha/app1.conf     #MHA的配置文件路径
mha_log="/usr/local/mha/manager.log"  #MHA的日志文件路径
tmpfile=/tmp/mha_tmpfile		#指定一个临时文件

cp check_slave.sh /usr/local/mha/	 #并将此文件拷贝到你的某个目录下
chmod a+x /usr/local/mha/check_slave.sh
```

* 修改inotify_MHA.sh

```shell
vim inotify_MHA.sh
#!/usr/bin/bash

mha_conf=/etc/mha/app1.conf					#配置文件路径
mha_log="/usr/local/mha/manager.log"		#日志文件路径
mha_check_slave="/usr/local/mha/check_slave.sh"  #check_slave.sh脚本路径

chmod a+x inotify_MHA.sh
```



 # 启用脚本

* 启用

```shell
nohup ./inotify_MHA.sh &
	
#但是为了效果展示，我这里使用 ./inotify_MHA.sh &，
#	不然看不到输出信息。
# ./inotify_MHA.sh &，
```

* 检查

```shell
[root@server1 ~]# ps -ef | grep "inotify"
root      37114  37113  0 19:02 pts/3    00:00:00 /usr/bin/inotifywait -mq -e modify,attrib /usr/local/mha/manager.log
root      37118   9991  0 19:02 pts/3    00:00:00 grep --color=auto inotify

# 如上，已经开启了对应的进程，开启成功。
```



# 测试-模拟主服务器宕机

1. 手动关闭master服务

```shell
systemctl stop mysqld
```

![image-20220819190554245](https://hackwu-images-1305994922.cos.ap-nanjing.myqcloud.com/images/image-20220819190554245.png)

* 以上为脚本输出的信息，信息显示，MHA已经被脚本重新启动了。
* 再次查看进程信息

```shell
[root@server1 ~]# ps -ef | grep "inotify"
root      37374  37373  0 19:05 pts/3    00:00:00 /usr/bin/inotifywait -mq -e modify,attrib /usr/local/mha/manager.log
root      37525   9991  0 19:07 pts/3    00:00:00 grep --color=auto inotify
 
 # 可以看到，后台依然有一个inotifywait进程执行着，可以继续监控MHA的状态
```

2. 查看日志信息

![image-20220819190944120](https://hackwu-images-1305994922.cos.ap-nanjing.myqcloud.com/images/image-20220819190944120.png)

> 日志信息显示，MHA确实处于监控状态。并且成功执行了故障切换。

```shell
[root@server1 ~]# masterha_check_status --conf=/etc/mha/app1.conf
[root@server1 ~]# masterha_check_status --conf=/etc/mha/app1.conf
app1 (pid:37351) is running(0:PING_OK), master:192.168.23.26
[1]+  完成                  nohup masterha_manager --conf=/etc/mha/app1.conf --remove_dead_master_conf --ignore_last_failover --ignore_fail_on_start

```

> 如上信息可知,主服务器成功由192.168.23.25切换成了192.168.23.26，并且MHA自动重启成功！
>
> 实验成功!!!

3. 再手动关闭一个Master

```shell
[root@server1 ~]# systemctl stop mysqld
```

* 查看脚本输出信息

![image-20220819191729093](https://hackwu-images-1305994922.cos.ap-nanjing.myqcloud.com/images/image-20220819191729093.png)

> 可以看到，又提示重启成功！！

* 在查看 日志信息

  ![image-20220819191853296](https://hackwu-images-1305994922.cos.ap-nanjing.myqcloud.com/images/image-20220819191853296.png)

> 可以看到日志信息也是符合的。
>
> 实验成功！！！



# 模拟有一个从服务器宕机的情况下，主服务器也宕机了

1. 在上面实验的基础下，我们手动恢复两台从服务器的配置，

   * 将他们配置到192.168.23.22 下，因为现在192.168.23.22是master

   * 配置完毕后修改MHA配置文件

   ```shell
   vim /etc/mha/app1.conf
   .....
   [server1]
   candidate_master=1
   hostname=192.168.23.22
   ignore_fail=1
   
   [server2]
   candidate_master=1
   hostname=192.168.23.26
   ignore_fail=1
   
   [server3]
   candidate_master=1
   hostname=192.168.23.25
   ignore_fail=1
   
   [server4]
   candidate_master=1
   hostname=192.168.23.24
   ignore_fail=1
           
   ```

2.检测集群状态

```shell
masterha_check_repl --conf=/etc/mha/app1.conf 
......
Fri Aug 19 19:29:03 2022 - [info] 
192.168.23.22(192.168.23.22:3306) (current master)
 +--192.168.23.26(192.168.23.26:3306)
 +--192.168.23.25(192.168.23.25:3306)
 +--192.168.23.24(192.168.23.24:3306)

Fri Aug 19 19:29:03 2022 - [info] Checking replication health on 192.168.23.26..
Fri Aug 19 19:29:03 2022 - [info]  ok.
Fri Aug 19 19:29:03 2022 - [info] Checking replication health on 192.168.23.25..
Fri Aug 19 19:29:03 2022 - [info]  ok.
Fri Aug 19 19:29:03 2022 - [info] Checking replication health on 192.168.23.24..
Fri Aug 19 19:29:03 2022 - [info]  ok.
Fri Aug 19 19:29:03 2022 - [warning] master_ip_failover_script is not defined.
Fri Aug 19 19:29:03 2022 - [warning] shutdown_script is not defined.
Fri Aug 19 19:29:03 2022 - [info] Got exit code 0 (Not master dead).

MySQL Replication Health is OK.

# 状态良好
```

3.再次启动master_manager

```shell
 nohup masterha_manager --conf=/etc/mha/app1.conf --remove_dead_master_conf --ignore_last_failover --ignore_fail_on_start &

```

* 查看脚本输出信息

  ![image-20220819193229293](https://hackwu-images-1305994922.cos.ap-nanjing.myqcloud.com/images/image-20220819193229293.png)

> 状态良好

* 查看日志文件

```shell
tailf /usr/local/mha/manager.log 
.......
Fri Aug 19 19:31:31 2022 - [info] 
192.168.23.22(192.168.23.22:3306) (current master)
 +--192.168.23.26(192.168.23.26:3306)
 +--192.168.23.25(192.168.23.25:3306)
 +--192.168.23.24(192.168.23.24:3306)

Fri Aug 19 19:31:31 2022 - [warning] master_ip_failover_script is not defined.
Fri Aug 19 19:31:31 2022 - [warning] shutdown_script is not defined.
Fri Aug 19 19:31:31 2022 - [info] Set master ping interval 1 seconds.
Fri Aug 19 19:31:31 2022 - [warning] secondary_check_script is not defined. It is highly recommended setting it to check master reachability from two or more routes.
Fri Aug 19 19:31:31 2022 - [info] Starting ping health check on 192.168.23.22(192.168.23.22:3306)..
Fri Aug 19 19:31:35 2022 - [warning] Got error when monitoring master:  at /usr/share/perl5/vendor_perl/MHA/MasterMonitor.pm line 489.
Fri Aug 19 19:31:35 2022 - [error][/usr/share/perl5/vendor_perl/MHA/MasterMonitor.pm, ln491] Target master's advisory lock is already held by someone. Please check whether you monitor the same master from multiple monitoring processes.
Fri Aug 19 19:31:35 2022 - [error][/usr/share/perl5/vendor_perl/MHA/MasterMonitor.pm, ln511] Error happened on health checking.  at /usr/bin/masterha_manager line 50.
Fri Aug 19 19:31:35 2022 - [error][/usr/share/perl5/vendor_perl/MHA/MasterMonitor.pm, ln525] Error happened on monitoring servers.
Fri Aug 19 19:31:35 2022 - [info] Got exit code 1 (Not master dead).

# 状态良好
```

> 到此MHA服务，再次构建完毕。
>
> 接下来，可以正式做试验了

4.手动关闭一个从服务器，就关闭192.168.23.24 吧

```shell
[root@server1 ~]# systemctl stop mysqld
```

5.在手动关闭主服务器192.168.23.22，

* 这时候可以关注脚本的输出信息和日志信息了

```shell
[root@server1 ~]# systemctl stop mysqld
```

* 查看脚本输出信息

![image-20220819202524803](https://hackwu-images-1305994922.cos.ap-nanjing.myqcloud.com/images/image-20220819202524803.png)

> 可以看到，依然是启动成功的

* 查看MHA状态

```shell
[root@server1 ~]#  masterha_check_status --conf=/etc/mha/app1.conf
app1 (pid:42202) is running(0:PING_OK), master:192.168.23.26
```

* 查看日志信息

  ![image-20220819203300036](https://hackwu-images-1305994922.cos.ap-nanjing.myqcloud.com/images/image-20220819203300036.png)

* 在查看二进制文件

```shell
vim /etc/mha/app1.conf
.....


[server2]
candidate_master=1
hostname=192.168.23.26
ignore_fail=1

[server3]
candidate_master=1
hostname=192.168.23.25
ignore_fail=1

```

> 可以看得到挂掉的两个服务器，已经被程序删除了。
>
> 实验成功！！



# 注意事项

* 使用这个脚本的前提是，需要先搭建出一个健康的MHA架构，不能有任何错误，
  * 否则使用此脚本容易发生报错
* 一定要先开启masterha_manage，才运行此脚本，否则会发生报错。
