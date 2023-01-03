#!/bin/bash
set -e

PID=$$

function usage()
{
    echo "This tool is for manual compact specified table(app)."
    echo "USAGE: $0 -c cluster -a app-name -i app_id"
    echo "Options:"
    echo "  -h|--help                   print help message"
    echo
    echo "  -c|--cluster <str>          cluster name, such as c4tst-function1 "
    echo
    echo "  -a|--app_name <str>         target table(app) name"
    echo
    echo "  -i|--app_id <str>           taget table(app) id,to check if app chosen correct"
    echo
}



function check_app_id(){
    cluster=$1
    app_name=$2
    app_id=$3

    log_file="/tmp/$UID.$PID.pegasus.check_app_id.${app_name}"
    echo -e "ls" | ./run.sh shell -n ${cluster} &>${log_file}
    get_fail=`grep 'get app env failed' ${log_file} | wc -l`
    if [ ${get_fail} -eq 1 ]; then
        echo "ERROR: get app envs failed, refer to ${log_file}"
        exit 1
    fi  
    check_id="$(grep "${app_name}" ${log_file} | awk '{print $1}')"
    echo ${check_id}
    if [ ${check_id}  -ne ${app_id} ];then
        echo "ERROR: app_name or app_id is not correct, check it and retry"
        exit 1
    fi  

    #echo "【debug】:now finish check_app_id \n"
}

function get_nodes()
{
    cluster=$1
    
    log_file="/tmp/$UID.$PID.pegasus.get_nodes.${app_name}"
    echo -e "nodes" | ./run.sh shell -n ${cluster} &>${log_file}
    get_fail=`grep 'get app env failed' ${log_file} | wc -l`
    if [ ${get_fail} -eq 1 ]; then
        echo "ERROR: get app envs failed, refer to ${log_file}"
        exit 1
    fi  
    #grep "ALIVE" ${log_file} | awk '{print $1}'
    alive_array=($(grep -w "ALIVE" ${log_file} | awk '{print $1}'))

    #echo "【debug】:now finish get_nodes \n"
    echo ${alive_array[@]}
}

function propose_primary()
{
    cluster=$1
    app_name=$2
    app_id=$3


    log_file="/tmp/$UID.$PID.pegasus.app_table_log.${app_name}"
    echo -e "app ${app_name} -d" | ./run.sh shell -n ${cluster} &>${log_file}
    get_fail=`grep 'get app env failed' ${log_file} | wc -l`
    if [ ${get_fail} -eq 1 ]; then
        echo "ERROR: get app envs failed, refer to ${log_file}"
        exit 1
    fi
    pid_array=($(grep "1/3" ${log_file} | awk '{print $1}'))
    if [ ${#pid_array[@]} -eq 0 ]; then
        echo "ERROR: there are no partition need to propose,check your app"
        exit 1
    fi


    secondaries_array=($(grep "1/3" ${log_file} | awk '{print $5}'))
    echo "pids are leak primary,they are ${pid_array[@]}"

    propose_log_file="/tmp/$UID.$PID.pegasus.propose_log.${app_name}"
    ####test###
    #propose_log_file="./scripts/propose_log"
    

    for(( id=0;id<${#pid_array[@]};id++)) do
        echo "*****************************"
        target_pid=${pid_array[id]}

        #deal with string,remove '[' and ']''
        second=${secondaries_array[id]}
        second=${second#*[}
        second=${second%]*}
        echo "pid ${target_pid} should be cure,and now it has second ${second}";

        alive_second=""
        #遍历get_nodes获取的ALIVE数组
        for(( i=0;i<${#alive_array[@]};i++)) do 
            alive_second=${alive_array[i]}
            if [ ${alive_second} != ${second} ]; then
                echo "${alive_second} is ALIVE and free,set it to be ${target_pid}'s primary"
                break
            fi
        done

        if [ "${alive_second}" == "" ]; then
            echo "ERROR: can't find a suitble ALIVE second: ${cluster}"
            exit 1
        fi

        #实际去做propose
        echo -e "propose -g ${app_id}.${target_pid} -p ASSIGN_PRIMARY -t ${alive_second} -n ${alive_second}" | ./run.sh shell -n ${cluster} &>${propose_log_file}
        sleep 5
        line=$[${i}+1]
        #grep -n显示行号   grep "^xxx"
        propose_result=$(grep 'send proposal response' ${propose_log_file} |grep -n ""|grep "^${line}")
             
        echo "now we do: propose -g ${app_id}.${target_pid} -p ASSIGN_PRIMARY -t ${alive_second} -n ${alive_second},and it's result is ${propose_result}"

        echo "*****************************"
        sleep 10
        ###test###
        break
    done
}



#初始化
if [ $# -eq 0 ]; then
    usage
    exit 0
fi

# parse parameters
cluster=""
app_name=""
app_id=""
unset alive_array


while [[ $# > 0 ]]; do
    option_key="$1"
    case ${option_key} in
        -c|--cluster)
            cluster="$2"
            shift
            ;;
        -a|--app_name)
            app_name="$2"
            shift
            ;;
        -i|--app_id)
            app_id="$2"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
    esac
    shift
done


# cd to shell dir
pwd="$(cd "$(dirname "$0")" && pwd)"
shell_dir="$(cd ${pwd}/.. && pwd )"
cd ${shell_dir}


# check cluster
if [ "${cluster}" == "" ]; then
    echo "ERROR: invalid cluster: ${cluster}"
    exit 1
fi

# check app_name
if [ "${app_name}" == "" ]; then
    echo "ERROR: invalid app_name: ${app_name}"
    exit 1
fi


#check if appid correct
check_app_id ${cluster} ${app_name} ${app_id}
sleep 1

#put ALIVE ndoes to alive_array
get_nodes ${cluster}
sleep 2

#begin propose
propose_primary ${cluster} ${app_name} ${app_id}



#end
rm -f /tmp/$UID.$PID.pegasus.* &>/dev/null

