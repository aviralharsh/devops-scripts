#!/bin/sh
set -e

release_name=$1
namespace=$2

function check_events(){
    reason=$(echo ${pod_details} | jq -r '.items[].reason' | tail -1)
    message=$(echo ${pod_details} | jq -r '.items[].message' | tail -1)
    liveness_failed=$(echo ${message} | grep 'Liveness probe failed' | tail -1)
    mount_failed=$(echo ${reason} | grep 'FailedMount' | tail -1)
    if [ -n "$liveness_failed" ]
    then
        echo ${liveness_failed}
        echo "Liveness probe is failing for Pod ${latest_pod}, try increasing initialDelay and check pod logs"
        echo "#######################################"
    elif [ -n "$mount_failed" ]
    then
        echo "Mount Failed for pod ${latest_pod}"
        echo "Error Message - ${message}"
        echo "#######################################"
    elif [  -n "$reason" ] || [ -n "$message" ]
    then
        echo "Last recorded Event: ${reason}"
        echo "Last recorded Message: ${message}"
        echo "Please check pod logs and kubernetes-dashboard for more details"
        echo "#######################################"
    else
        echo "No events found"
        echo "Please check pod logs and kubernetes-dashboard for more details"
        echo "#######################################"
    fi
}

function check_oom_killed(){
    if [ -n "$(kubectl describe pod ${latest_pod} -n ${namespace} | grep OOMKilled)" ]
    then
        echo "${latest_pod} was OOM Killed previously, Please increase the resources and deploy"
        echo "#######################################"
    else
        check_events
    fi
}

function pod_status(){
    pod_status=$(echo ${get_pod_info} | awk '{print $3}' | tail -1)
    running_containers=$(echo ${get_pod_info} | awk '{print $2}' | tail -1 | cut -d / -f 1)
    total_containers=$(echo ${get_pod_info} | awk '{print $2}' | tail -1 | cut -d / -f 2)
    case ${pod_status} in
        Pending)
            echo "Pods are in Pending state"
            echo "Message: "$(echo ${pod_details} | jq -r '.items[].message' | tail -1)
            echo "Please check toleration and affinity values and reach out to DevOps"
            echo "#######################################"
        ;;
        CrashLoopBackOff | Error)
            echo "Pods are in CrashLoopBackoff or Error state"
            echo "Checking if any restarts"
            restart_calculator
        ;;
        ContainerCreating)
            echo "Pods are in ContainerCreating State, checking if any restarts..."
            restart_calculator
        ;;
        Running)
            if [ ${running_containers} -lt ${total_containers} ]
            then
                echo "Pods are in ${pod_status} status, checking further"
                restart_calculator
            else
                echo "All containers are running, check the pipeline logs for any errors or refer k8s-dashboard for pod description."
                echo "#######################################"
            fi
        ;;
        ImagePullBackOff)
            echo "Pods are in ImagePullBackOff State, please check if the right image is defined"
            check_events
        ;;
        *)
            echo "Pods are in ${pod_status} status, checking further"
            restart_calculator
        ;;
        esac
}

function restart_calculator(){
    restart_count=$(echo ${get_pod_info} | awk '{print $4}')
    if [ ${restart_count} -gt 0 ]
    then
        echo "Restart count for the lastest pod ( ${latest_pod} ) is ${restart_count}"
        check_oom_killed
    else
        echo "No restarts"
        check_events
    fi
}

latest_pod=$(kubectl get pod --sort-by=.metadata.creationTimestamp -n ${namespace} | grep ${release_name} | awk '{print $1}' | tail -1)
get_pod_info=$(kubectl get pod -n ${namespace} ${latest_pod} | grep -v "NAME")
pod_details=$(kubectl get events --field-selector involvedObject.kind=Pod,involvedObject.name=${latest_pod} -n ${namespace} -o json)
echo "#######################################"
echo "Checking for ${release_name}"
pod_status $latest_pod
