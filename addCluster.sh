#!/bin/bash
: << "END"

Argument parser

  @ Output : NS CENTRAL_RELEASE TARGET_DOMAIN

END

echo "\n0️⃣" "\033[32;1m"  Argument check"\033[0m" "\n\n"

checkDNS(){
  if [ "$(nslookup $TARGET_DOMAIN | grep "NXDOMAIN")" ] ; then
    echo "🚫 Fail : Domain is unreachable\n"
    exit 0
  else
    echo "✅ Pass : Domain is reachable\n"
  fi
}
help(){
  echo "sh updateQuery.sh [OPTIONS]"
	echo "  -h    help"
	echo "  -n <ARGUMENT> namespace ( default : default )"
	echo "  -d <ARGUMENT> target's ingress domain"
	echo "  -r <ARGUMENT> central's thanos release name ( default : central-thanos ) "
	exit 0
}

NS=monitoring
CENTRAL_RELEASE=observer

while getopts "n:d:r:h" opt
do
  case $opt in
    n) NS=$OPTARG
    ;;
    d) TARGET_DOMAIN=$OPTARG
    ;;
    r) CENTRAL_RELEASE=$OPTARG
    ;;
    h) help ;;
    ?) help ;;
  esac
done


if [ -z "$TARGET_DOMAIN" ] ; then
  echo "🚫 Fail : Need to specify target's domain"
  echo "    -h will help you"
  exit 0
else
  echo "✅ Pass : Enough arguments\n"
fi

checkDNS

: << "END"

Cluster selector

   @ Output : CENTRAL_CLUSTER TARGET_CLUSTER

END

ESC=`printf "\033"`;

input_key() {
    read -s -n3 INPUT;
    echo $INPUT;
}

check_selected() {
    if [ $1 = $2 ];
    then echo " => "
    else echo "    "
    fi
}

select_value() {
    SELECTED=1;
    INPUT="";
    MIN_MENU=1;
    MAX_MENU=$#;
    while true;
    do
        for (( i=1; i<=$#; i++))
        do
            printf "$ESC[2K$(check_selected $i $SELECTED) $i. ${!i}\n";
        done
        printf "\n$ESC[2KUse Arrow key to select and input Enter to select\n$ESC[2K(selected : ${!SELECTED})\n";
        INPUT=$(input_key);
        if [[ $INPUT = "" ]];
        then
		  break;
        fi

        if [[ $INPUT = $ESC[A ]];
        then SELECTED=$(expr $SELECTED - 1);
        elif [[ $INPUT = $ESC[B ]];
        then SELECTED=$(expr $SELECTED + 1);
        fi

        if [[ $SELECTED -lt $MIN_MENU ]];
        then SELECTED=${MAX_MENU};
        elif [[ $SELECTED -gt $MAX_MENU ]];
        then SELECTED=${MIN_MENU};
        fi

        printf "$ESC[$(expr $# + 3)A";
    done
    return `expr ${SELECTED} - 1`;
}

select_cluster() {
    select_value "${contexts[@]}";
    local SELECTED=$?;
    SELECTED_MODE=${contexts[${SELECTED}]};
}

select_clusters() {
	echo "\nSelect central-cluster"
	contexts=($(kubectl config get-contexts | awk '{if(NR > 1) print $2}'));
	select_cluster;
	CENTRAL_CLUSTER=$SELECTED_MODE
	echo "\nSelect target-cluster"
	select_cluster;
	TARGET_CLUSTER=$SELECTED_MODE
}

: << "END"

Chart value maker

   @ Output : multi-cluster-central/values/hyunkoes/targets multi-cluster-target/values/hyunkoes/targets

END
EXIST=false
isExist(){
  while read LINE; do
    if [ "$1" == "$LINE" ] ; then 
      echo [$LINE]
      EXIST=true
    fi
  done < $2
}

editValues(){
  mkdir -p multi-cluster-central/values/hyunkoes/targets
  mkdir -p multi-cluster-target/values/hyunkoes/clusters
  
  FILE=multi-cluster-central/values/hyunkoes/targets/$TARGET_CLUSTER.yaml
  cp $TARGET_THANOS_VALUE $FILE
  TARGET_THANOS_VALUE=$FILE
  echo '
    stores:
    - dns+'$TARGET_DOMAIN':443
    extraFlags:
    - "--grpc-client-tls-secure"
    - "--grpc-client-server-name='$TARGET_DOMAIN'"' >> $FILE 


  # CENTRAL THANOS VALUE
  EXIST=false # 해당 타겟 클러스터 쿼리가 등록되어 있는지 확인
  while read LINE; do
    if [[ "$LINE" =~ "$TARGET_CLUSTER-thanos-query" ]] ; then 
      EXIST=true
    fi
  done < $CENTRAL_THANOS_VALUE

  # 등록되어 있지 않다면 yaml에 추가
  if [ "$EXIST" == false ] ; then
    line=`expr $(cat ${CENTRAL_THANOS_VALUE} | grep -n stores: | cut -d ':' -f1) + 1`
    awk -v li=$line '{ if (NR==li) { print "    - target-'$TARGET_CLUSTER'-thanos-query-grpc:10901"; print $0 } else { print $0 } }' $CENTRAL_THANOS_VALUE > $TARGET_CLUSTER.dump
    mv $TARGET_CLUSTER.dump $CENTRAL_THANOS_VALUE
  fi

  # TARGET PROMETHEUS VALUE
  cp $TARGET_PROMETHEUS_VALUE multi-cluster-target/values/hyunkoes/clusters/$TARGET_CLUSTER.yaml
  TARGET_PROMETHEUS_VALUE=multi-cluster-target/values/hyunkoes/clusters/$TARGET_CLUSTER.yaml
  echo '      hosts:
      - '$TARGET_DOMAIN'
      tls:
        - hosts:
          - '$TARGET_DOMAIN'' >> $TARGET_PROMETHEUS_VALUE
}

: << "END"

Target cluster env maker
 - Create secret for s3
 - Create prometheus ( + sidecar )

END

ns_check(){
  echo "Check namespace:$NS is exist in \033[32m"$1"\033[0m\n"
  NS_CHECK=$(kubectl get ns --context=$1| awk -v ns=$NS '$1==ns {print $1}')
  if [ -z "$NS_CHECK" ] ; then
   echo "🚫 Fail : Namespace '$NS' is not exist"
   echo "❓Create namespace '$NS' ? ( y / n ) : \c"
   read answer
   if [ "$answer" == "y" ] || [ "$answer" == "Y" ] ; then
  	kubectl create ns $NS --context=$1
   elif [ "$answer" == "n" ] || [ "$answer" == "N" ]; then
  	echo "Exit"
  	exit 0
   else
  	echo "Invalid"
  	exit 0
   fi
  else
   echo "✅ Pass : namespace '$NS' is exist\n"
  fi
   kubectl delete secret $SECRET -n $NS --context=$1
   kubectl create secret generic $SECRET --from-file=$SECRET_PATH -n $NS --context=$1
  echo "\n✅ Pass : Create secret perfectly\n"
}



: << "END"

This is shell script for creating new query looking at prometheusSidecar of target cluster

END

SECRET=objstore-secret
SECRET_PATH=objstore.yml
CENTRAL_THANOS_VALUE=multi-cluster-central/values/hyunkoes/dev-thanos.yaml
CENTRAL_GRAFANA_VALUE=multi-cluster-central/values/hyunkoes/dev-grafana.yaml
TARGET_THANOS_VALUE=multi-cluster-central/values/hyunkoes/dev-query-common.yaml
TARGET_PROMETHEUS_VALUE=multi-cluster-target/values/hyunkoes/dev-prom-common.yaml

echo "\n1️⃣" "\033[32;1m"  Select cluster : Central, Target"\033[0m" "\n\n"

select_clusters

echo "\nCentral-cluster : $CENTRAL_CLUSTER\nTarget-cluster : $TARGET_CLUSTER\nNamespace : $NS \nRelease : $CENTRAL_RELEASE \nTarget domain : $TARGET_DOMAIN\n"

echo "\n2️⃣" "\033[32;1m"  Target cluster : Make secret for S3"\033[0m" "\n\n"

ns_check $CENTRAL_CLUSTER
ns_check $TARGET_CLUSTER

echo "\n3️⃣" "\033[32;1m"  Edit yaml values"\033[0m" "\n\n"

editValues

echo "\n✅"  "\033[44m"Complete add/edit values. Push to github connected with argoCD"\033[0m" "\n"
