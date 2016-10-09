#!/bin/bash
set -eu

red='\033[0;31m'
green='\033[0;32m'
NC='\033[0m' # No Color

log_info() {
  echo -e "\n${green}$1${NC}"
}

log_error() {
  echo -e "\n${red}$1${NC}"
}

usage() {
  log_info "usage: $0 <task_definitions_path> <environment>"
  echo "  <task_definition_path>: /path/to/task/definitions"
  echo "  <environment>: [ prod | stag | pre ]"
}

del_ALB_name() {
  DNSName=$(aws --profile aws-project-$ENV elbv2 describe-load-balancers --names $name_alb | jq '.LoadBalancers[0].DNSName')
  cp $task_folder/../del_record.json /tmp/
  sed -i'.bk' 's/NAME_ELB/'$name_alb'/' /tmp/del_record.json
  sed -i'.bk' 's/ENV/'$ENV'/' /tmp/del_record.json
  sed -i'.bk' 's/"LOAD_BALANCER"/'$DNSName'/' /tmp/del_record.json
  aws --profile aws-project-$ENV route53 change-resource-record-sets --hosted-zone-id $hosted_zone --change-batch file:///tmp/del_record.json
  rm /tmp/del_record.json
  echo "ALB name changed"
}

if [ "$#" -ne 2 ]; then
  usage
  exit 1
fi

task_folder=$1

if [ ! -d "$task_folder" ]; then
  usage
  log_error "ERROR: '$task_folder' does not exist or is not a directory"
  exit 1
fi

if [[ ! $task_folder = /* ]]; then
  usage
  log_error "ERROR: '$task_folder' must be an absolute path"
  exit 1
fi

ENV=$2

if [ "$ENV" != "prod" ] && [ "$ENV" != "stag" ] && [ "$ENV" != "pre" ]; then
  usage
  log_error "ERROR: '$ENV' must be [ prod | stag | pre ]"
  exit 1
fi
if [ "$ENV" == "pre" ]; then
  subnet=subnet-xxxxxxxx
  int_sg=sg-yyyyyyyy
  ext_sg=sg-zzzzzzzz
  hosted_zone="XXXXXXXXXXXXXX"
fi
if [ "$ENV" == "prod" ]; then
  subnet=subnet-rrrrrrrr
  int_sg=sg-tttttttt
  ext_sg=sg-ssssssss
  hosted_zone="YYYYYYYYYYYYYY"
fi

#Delete-albs
num_task=$(ls -l $task_folder | wc -l)
desired_alb=`expr 1 + $num_task / 10`

for (( i=1; i<=$desired_alb; i++ ))
do
  name_alb=$i-alb-$ENV
  arn_alb=$(aws --profile aws-project-$ENV elbv2 describe-load-balancers | jq '.LoadBalancers[0].LoadBalancerArn' | sed -e 's/^"//' -e 's/"$//')
  del_ALB_name
  aws --profile aws-project-$ENV elbv2 delete-load-balancer --load-balancer-arn $arn_alb
done
sleep 5
#Delete target-groups
tasks_list=$(ls $task_folder | grep -v front-proxy)
for task in $tasks_list
do
  sleep 5
  aux_name_tg=$(echo ${task:3})
  name_tg=$(echo ${aux_name_tg%-td.*})
  arn_tg_group=$(aws --profile aws-project-$ENV elbv2 describe-target-groups --names tg-$name_tg-svc | jq '.TargetGroups[0].TargetGroupArn' | sed -e 's/^"//' -e 's/"$//')
  aws --profile aws-project-$ENV elbv2 delete-target-group --target-group-arn $arn_tg_group
done
