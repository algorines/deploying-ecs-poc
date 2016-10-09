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

set_ELB_name() {
  DNSName=$(aws --profile aws-project-$ENV elbv2 describe-load-balancers --names $name_alb | jq '.LoadBalancers[0].DNSName')
  cp $task_folder/../add_record.json /tmp/
  sed -i'.bk' 's/NAME_ELB/'$name_alb'/' /tmp/add_record.json
  sed -i'.bk' 's/ENV/'$ENV'/' /tmp/add_record.json
  sed -i'.bk' 's/"LOAD_BALANCER"/'$DNSName'/' /tmp/add_record.json
  aws --profile aws-project-$ENV route53 change-resource-record-sets --hosted-zone-id $hosted_zone --change-batch file:///tmp/add_record.json
  rm /tmp/add_record.json
  echo "ELB name changed"
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
  #subnet eu-west-1b
  #subnet=subnet-951f0bf0
  #subnet eu-west-1c
  subnet1=subnet-xxxxxxxx
  subnet2=subnet-yyyyyyyy
  int_sg=sg-tttttttt
  ext_sg=sg-rrrrrrrr
  vpc_id=vpc-zzzzzzz
  hosted_zone="XXXXXXXXXX"
fi
if [ "$ENV" == "prod" ]; then
  subnet1=subnet-aaaaaaaa
  subnet2=subnet-bbbbbbbb
  int_sg=sg-cccccccc
  ext_sg=sg-dddddddd
  vpc_id=vpc-eeeeeeee
  hosted_zone="YYYYYYYYYYY"
fi

#Create-albs
num_task=$(ls -l $task_folder | wc -l)
desired_alb=`expr 1 + $num_task / 10`

# Aplying security groups to ELBs
sg_id=$(aws --profile aws-project-$ENV ec2 describe-security-groups --filters Name=tag-key,Values=Name   Name=tag-value,Values=sg-InternalELB-$ENV --query 'SecurityGroups[*].{Name:GroupName,ID:GroupId}' | jq '.[0].ID')
sg_id_no_quotes=$(echo "$sg_id" | sed -e 's/^"//'  -e 's/"$//')

for (( i=1; i<=$desired_alb; i++ ))
do
  name_alb=$i-alb-$ENV
  aws --profile aws-project-$ENV elbv2 create-load-balancer --name $name_alb \
  --scheme internal --subnets $subnet1 $subnet2 --security-groups $sg_id_no_quotes
  sleep 5
  set_ELB_name
done

#Create target-group
port=8082
tasks_list=$(ls $task_folder | grep -v front-proxy)
for task in $tasks_list
do
  i=$(($port % 2))
  sleep 5
  aux_name_tg=$(echo ${task:3})
  name_tg=$(echo ${aux_name_tg%-td.*})
  arn_alb=$(aws --profile aws-project-$ENV elbv2 describe-load-balancers | jq '.LoadBalancers['$i'].LoadBalancerArn' | sed -e 's/^"//' -e 's/"$//')
  arn_tg_group=$(aws --profile aws-project-$ENV elbv2 create-target-group --name tg-$name_tg-svc --protocol HTTP --port $port --vpc-id $vpc_id --health-check-protocol HTTP --health-check-path /health | jq '.TargetGroups[0].TargetGroupArn')

  #Create listeners
  aws --profile aws-project-$ENV elbv2 create-listener --load-balancer-arn $arn_alb --protocol HTTP --port $port --default-actions Type=forward,TargetGroupArn=$arn_tg_group
  port=`expr $port + 1`
done
