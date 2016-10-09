# deploying-ecs-poc

## This proof of concept has been performed using the following elements

+ AWS Cloud Formation
+ AWS EC2
+ AWS ECS
+ AWS Route 53
+ AWS ALB and ELB
+ Docker
+ Dockerhub
+ Consul
+ Fluentd  

The purpose of this POC is deploy three environments (stagging, pre-production, production) using Cloud Formation, Amazon ECS, and bash scripting from our local machine.

## Requirements before execute scripts

+ AWS cli must to be installed and configured.
+ VPC's and subnnets must to be created manually.
+ Route 53 hosted zones must to be created manually.
+ Dockerhub repositories must to be created.
