#!/bin/sh

DATE=`date +%Y%m%d.%H`
DIR=$PWD/backup

DIR=$DIR/$DATE

# Backup object per project for easy restore
mkdir -p $DIR/projects
cd $DIR/projects
for i in `oc get projects --no-headers |grep Active |awk '{print $1}'`
do
  mkdir $i
  cd $i
  oc export namespace $i >ns.yml
  oc export project   $i >project.yml
  for j in pods replicationcontrollers deploymentconfigs buildconfigs services routes pvc quota hpa secrets configmaps daemonsets deployments endpoints imagestreams ingress scheduledjobs jobs limitranges policies policybindings roles rolebindings resourcequotas replicasets serviceaccounts templates oauthclients petsets
  do
    mkdir $j
    cd $j
    for k in `oc get $j -n $i --no-headers |awk '{print $1}'`
    do
      echo export $j $k '-n' $i
      oc export $j $k -n $i >$k.yml
    done
    cd ..
  done
  cd ..
done


### Databases ###
for i in `oc get projects --no-headers |grep Active |awk '{print $1}'`
do
  oc observe -n $i --once pods \
    -a '{ .metadata.labels.deploymentconfig }'   \
    -a '{ .metadata.labels.backup     }'   -- echo \
   |grep -v ^# \
   |while read PROJECT POD DC BACKUP
  do
    [ "$BACKUP" == "" ] && continue
    echo "$POD in $PROJECT has the following BACKUP label: $BACKUP"
    for TECH in ${BACKUP//,/ }
    do
      mkdir -p $DIR/../$TECH/$PROJECT  2>/dev/null
      case $TECH in
        mysql)
          oc -n $PROJECT exec $POD -- /usr/bin/sh -c 'PATH=$PATH:/opt/rh/mysql55/root/usr/bin:/opt/rh/rh-mysql56/root/usr/bin/ mysqldump -h 127.0.0.1 -u $MYSQL_USER --password=$MYSQL_PASSWORD $MYSQL_DATABASE' >$DIR/../mysql/$PROJECT/$DC.sql
          ;;
        postgresql)
          oc -n $PROJECT exec $POD -- /usr/bin/sh -c 'LD_LIBRARY_PATH=/opt/rh/rh-postgresql95/root/usr/lib64 PATH=$PATH:/opt/rh/rh-postgresql95/root/usr/bin pg_dump -Fc $POSTGRESQL_DATABASE ' >$DIR/../postgresql/$PROJECT/$DC.pg_dump_custom
          ;;
        fs:*)
          array=(${TECH//:/ })
	  FS=${array[1]}
          if oc -n $PROJECT exec $POD -- test -d $FS
          then
            rsync -azv --dry-run --rsh='oc rsh' jenkins-4-dzd8c:$FS $DIR/../fs/$PROJECT/$FS
          else
            echo "ERROR: FS $FS is no valid directory in POD $POD!"
          fi
          ;;
        *)
          echo "ERROR: Unknown technology $TECH"
          ;;
      esac
    done
  done
done

