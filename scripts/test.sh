#!/bin/bash

set -e

PID=$$

function usage()
{
    echo "This tool is test"
}


function get_env()
{
    cluster=$1
    app_name=$2
    key=$3

    log_file="./test_log"
    echo -e "use ${app_name}\n get_app_envs" | ./run.sh shell --cluster ${cluster} &>${log_file}
    get_fail=`grep 'get app env failed' ${log_file} | wc -l`
    if [ ${get_fail} -eq 1 ]; then
        echo "ERROR: get app envs failed, refer to ${log_file}"
        exit 1
    fi
    grep "^${key} =" ${log_file} | awk '{print $3}'
}

function get_nodes()
{
    cluster=$1
    

    log_file="./scripts/nodes_test_log"
    echo -e "nodes" | ./run.sh shell -n ${cluster} &>${log_file}
    get_fail=`grep 'get app env failed' ${log_file} | wc -l`
    if [ ${get_fail} -eq 1 ]; then
        echo "ERROR: get app envs failed, refer to ${log_file}"
        exit 1
    fi
    grep "ALIVE" ${log_file} | awk '{print $1}'
}

function propose_primary()
{
    cluster=$1
    app_name=$2
    app_id=$3


    log_file="./scripts/app_table_log"
    echo -e "app ${app_name} -d" | ./run.sh shell -n ${cluster} &>${log_file}
    get_fail=`grep 'get app env failed' ${log_file} | wc -l`
    if [ ${get_fail} -eq 1 ]; then
        echo "ERROR: get app envs failed, refer to ${log_file}"
        exit 1
    fi
    pid_array=($(grep "10.132.5.21:22801" ${log_file} | awk '{print $1}'))
    secondaries_array=($(grep "10.132.5.21:22801" ${log_file} | awk '{print $5}'))
    echo "pids are leak primary,they are ${pid_array[@]}"

    propose_log_file="./scripts/propose_log"

    for(( i=0;i<${#pid_array[@]};i++)) do
        target_pid=${pid_array[i]}

        #deal with string,remove '[' and ']''
        second=${secondaries_array[i]}
        second=${second#*[}
        second=${second%]*}
        echo "pid ${target_pid} should be cure,and now it has second ${second}";

        alive_second=""
        #遍历get_nodes获取的ALIVE数组
        for(( i=0;i<${#alive_array[@]};i++)) do 
            alive_second=${alive_array[i]}
            if [ ${alive_second} -ne ${second} ]; then
                echo "${alive_second}is ALIVE and free,set it to be ${target_pid}'s primary"
                break
            fi
        done

        if [ "${alive_second}" == "" ]; then
            echo "ERROR: can't find a suitble ALIVE second: ${cluster}"
            exit 1
        fi

        #实际去做propose
        echo -e "propose -g ${app_id}.${target_pid} -p ASSIGN_PRIMARY -t ${alive_second} -n ${alive_second}" | ./run.sh shell -n ${cluster} &>${propose_log_file}

        echo "now we do: propose -g ${app_id}.${target_pid} -p ASSIGN_PRIMARY -t ${alive_second} -n ${alive_second}\n "
    done

}









# cd to shell dir
pwd="$(cd "$(dirname "$0")" && pwd)"
shell_dir="$(cd ${pwd}/.. && pwd )"
cd ${shell_dir}

# set_env cluster app_name key value

get_env
echo "the result is: $?"



