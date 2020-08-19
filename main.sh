#!/bin/bash

HOST=$1

FREQUENCY=$2

#BASE_PATH=$3

# this will be updated automatically
data_time=''
current_date=''
current_time=''

# get current date and time AAAA-MM-DD HH:MM:SS 
function get_date_time()
{
    date_time=`date --rfc-3339=seconds`
}

function get_current_date
{
    current_date=`echo $date_time | cut -d\  -f1`
}

function get_current_time
{
    current_time=`echo $date_time | cut -d\  -f2 | awk 'BEGIN{FS="-"}{print $1}'`
}

function update_date_time
{
    get_date_time
    get_current_date
    get_current_time
}
function get_running
{
    URL=$(echo "$HOST/containers/json?status=running") 
    curl -s $URL
}
function get_stats_container
{
 URL=$(echo "$HOST/containers/$1/stats?stream=false ")
 curl -s $URL
}

function get_container_processes
{
    URL=$(echo "$HOST/containers/$1/top?ps_args=aux")
    curl -s $URL
}
function calc
{ 
    awk "BEGIN { print "$*" }"; 
}

function get_container_header
{
    echo "used_memory;available_memory;memory_percent;number_cpus;cpu_percent;blkio_read_bytes;blkio_write_bytes;blkio_sync_bytes;blkio_async_bytes;blkio_discard_bytes;blkio_total_bytes;date;time" 
}
function get_container_network_header
{
    echo "rx_bytes;rx_packets;rx_errors;rx_dropped;tx_bytes;tx_packets;tx_errors;tx_dropped;date;time" 
}
function get_container_processes_header
{
    echo "user;pid;%cpu;%mem;vsz;rss;tty;stat;start;time;command;date;hour"
}
update_date_time   
directory_name=`echo "data-$current_date-$current_time"`
#

while [ True ]
do
    if [ ! -z $FREQUENCY ]
    then
        sleep $FREQUENCY
    fi
    names=$(get_running | jq '.[].Names' | tr '["/]' ' ')
    containers=($names)
    
    for container in "${containers[@]}"; 
    do 
        # make directories
        directory_results=$(echo "$directory_name/$container")
        log_container=$(echo "$directory_results/syslog.csv")
        jsons=$(echo "$directory_results/jsons")
        processes_path=$(echo "$directory_results/processes")
        if [ ! -d "$directory_results" ]
        then
            mkdir -p $jsons
            mkdir -p $processes_path
            get_container_header > $log_container
        fi
        
        stat=$(get_stats_container $container)
        update_date_time
        json_file=$(echo "$jsons/$current_date-$current_time.json")
        echo $stat > $json_file
        used_memory=$(echo $stat | jq '.memory_stats.usage - .memory_stats.stats.cache')
        available_memory=$(echo $stat | jq '.memory_stats.limit')
        memory_percent=$(calc $used_memory*100.0/$available_memory)
        cpu_delta=$(echo $stat | jq '.cpu_stats.cpu_usage.total_usage - .precpu_stats.cpu_usage.total_usage')
        system_cpu_delta=$(echo $stat | jq '.cpu_stats.system_cpu_usage - .precpu_stats.system_cpu_usage')
        number_cpus=$(echo $stat | jq '.cpu_stats.online_cpus')
        cpu_percent=$(calc $cpu_delta*$number_cpus*100.0/$system_cpu_delta)
        blkio_read_bytes_recursive=$(echo $stat | jq '.blkio_stats.io_service_bytes_recursive[0].value')
        blkio_write_bytes_recursive=$(echo $stat | jq '.blkio_stats.io_service_bytes_recursive[1].value')
        blkio_sync_bytes_recursive=$(echo $stat | jq '.blkio_stats.io_service_bytes_recursive[2].value')
        blkio_async_bytes_recursive=$(echo $stat | jq '.blkio_stats.io_service_bytes_recursive[3].value')
        blkio_discard_bytes_recursive=$(echo $stat | jq '.blkio_stats.io_service_bytes_recursive[4].value')
        blkio_total_bytes_recursive=$(echo $stat | jq '.blkio_stats.io_service_bytes_recursive[5].value')

        echo "$used_memory;$available_memory;$memory_percent;$number_cpus;$cpu_percent;$blkio_read_bytes_recursive;$blkio_write_bytes_recursive;$blkio_sync_bytes_recursive;$blkio_async_bytes_recursive;$blkio_discard_bytes_recursive;$blkio_total_bytes_recursive;$current_date;$current_time" >> $log_container

        networks=$(echo $stat | jq '.networks')
        interfaces=($(echo $networks | jq 'keys' | tr '["/]' ' ' ))
        
        for interface in "${interfaces[@]}"; 
        do
            interface_directory=$(echo "$directory_results/$interface")
            log_interface=$(echo "$interface_directory/network.csv")
            if [ ! -d "$interface_directory" ]
            then
                mkdir -p $interface_directory
                get_container_network_header > $log_interface
            fi

            aux=$(echo ".$interface.rx_bytes")
            rx_bytes=$(echo $networks | jq $aux)   
            aux=$(echo ".$interface.rx_packets")
            rx_packets=$(echo $networks | jq $aux)   
            aux=$(echo ".$interface.rx_errors")
            rx_errors=$(echo $networks | jq $aux)   
            aux=$(echo ".$interface.rx_dropped")
            rx_dropped=$(echo $networks | jq $aux)   
            aux=$(echo ".$interface.tx_bytes")
            tx_bytes=$(echo $networks | jq $aux)   
            aux=$(echo ".$interface.tx_packets")
            tx_packets=$(echo $networks | jq $aux) 
            aux=$(echo ".$interface.tx_errors")
            tx_errors=$(echo $networks | jq $aux) 
            aux=$(echo ".$interface.tx_dropped")
            tx_dropped=$(echo $networks | jq $aux) 

            echo "$rx_bytes;$rx_packets;$rx_errors;$rx_dropped;$tx_bytes;$tx_packets;$tx_errors;$tx_dropped;$current_data;$current_time" >> $log_interface
        done

        top_container=$( get_container_processes $container )
        number_of_processes=$(echo $top_container | jq '.Processes | length - 1')
    
        for i in $(seq 0 $number_of_processes);
        do
            pid=$(echo ".Processes[$i][1]")
            pid=$(echo $top_container | jq $pid)
            aux_path=$(echo "$processes_path/$pid")
            log_process=$(echo "$aux_path/$pid.csv")
            if [ ! -d "$aux_path" ]
            then
                mkdir -p $aux_path
                get_container_processes_header > $log_process
            fi
            user=$(echo ".Processes[$i][0]"  )
            user=$(echo $top_container | jq $user | tr '"' ' ')
            cpu_percent=$(echo ".Processes[$i][2]")
            cpu_percent=$(echo $top_container | jq $cpu_percent | tr '"' ' ')
            mem_percent=$(echo ".Processes[$i][3]")
            mem_percent=$(echo $top_container | jq $mem_percent | tr '"' ' ')
            vsz=$(echo ".Processes[$i][4]")
            vsz=$(echo $top_container | jq $vsz | tr '"' ' ')
            rss=$(echo ".Processes[$i][5]")
            rss=$(echo $top_container | jq $rss | tr '"' ' ')
            tty=$(echo ".Processes[$i][6]")
            tty=$(echo $top_container | jq $tty | tr '"' ' ')
            stat=$(echo ".Processes[$i][7]")
            stat=$(echo $top_container | jq $stat | tr '"' ' ')
            start=$(echo ".Processes[$i][8]")
            start=$(echo $top_container | jq $start | tr '"' ' ')
            time=$(echo ".Processes[$i][9]")
            time=$(echo $top_container | jq $time | tr '"' ' ')
            command=$(echo ".Processes[$i][10]")
            command=$(echo $top_container | jq $command | tr '"' ' ')
            echo "$user;$pid;$cpu_percent;$mem_percent;$vsz;$rss;$tty;$stat;$start;$time;$command;$current_date;$current_time" >> $log_process
        done
    done
done