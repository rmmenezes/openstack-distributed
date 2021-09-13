#!/bin/bash
set -x #echo on

########################
#        Update        #
########################

sudo mv /etc/apt/sources.list /etc/apt/sources.list.original
sudo cat ./files/debian/sources.list > /etc/apt/sources.list 

sudo apt-get install gnupg wget -y
sudo apt-get install curl -y
sudo curl http://osbpo.debian.net/osbpo/dists/pubkey.gpg | sudo apt-key add -

sudo apt-get update -y
sudo apt-get upgrade -y

########################
#        Openstack     #
########################

apt install python3-pip -y
pip install python-openstackclient

########################
#        Mysql         #
########################

apt install mariadb-server python3-pymysql -y
touch /etc/mysql/mariadb.conf.d/99-openstack.cnf
cat > /etc/mysql/mariadb.conf.d/99-openstack.cnf << EOF
[mysqld]
bind-address = 10.0.0.11
default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF

sudo systemctl restart mysql

mysql_secure_installation

sed -i '/bind-address            = 127.0.0.1/d' /etc/mysql/mariadb.conf.d/50-server.cnf
sed -i '/\[mysqld\]$/a bind-address            = 0.0.0.0' /etc/mysql/mariadb.conf.d/50-server.cnf

sudo DEBIAN_FRONTEND=noninteractive apt install iptables-persistent -yq

########################
#        Rabbitmq      #
########################

apt install rabbitmq-server -y
rabbitmqctl add_user openstack RABBIT_PASS
rabbitmqctl set_permissions openstack ".*" ".*" ".*"

########################
#        Memcached     #
########################

apt install memcached python3-memcache -y
sed -i 's/-l 127.0.0.1/-l 10.0.0.11/g' /etc/memcached.conf
sudo systemctl restart memcached

########################
#        Keystone      #
########################
export OS_USERNAME=admin
export OS_PASSWORD=ADMIN_PASS
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_TENANT_NAME=admin

mysql --user="root" --password="password" --execute="CREATE DATABASE IF NOT EXISTS keystone;"
mysql --user="root" --password="password" --execute="GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'KEYSTONE_DBPASS';"
mysql --user="root" --password="password" --execute="GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'KEYSTONE_DBPASS';"

sudo DEBIAN_FRONTEND=noninteractive apt install keystone apache2 libapache2-mod-wsgi-py3 -y

mv /etc/keystone/keystone.conf /etc/keystone/keystone.conf.original
cp ./files/keystone/keystone.conf /etc/keystone/keystone.conf 
chgrp keystone /etc/keystone/keystone.conf 

su -s /bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone


keystone-manage bootstrap --bootstrap-password ADMIN_PASS --bootstrap-admin-url http://controller:5000/v3/ --bootstrap-internal-url http://controller:5000/v3/ --bootstrap-public-url http://controller:5000/v3/ --bootstrap-region-id RegionOne
  
service apache2 restart

openstack domain create --description "An Example Domain" example
openstack project create --domain default --description "Service Project" service
openstack project create --domain default --description "Demo Project" myproject
openstack user create --domain default --password password myuser
openstack role create myrole
openstack role add --project myproject --user myuser myrole


########################
#        Glance        #
########################
export OS_USERNAME=admin
export OS_PASSWORD=ADMIN_PASS
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_TENANT_NAME=admin

mysql --user="root" --password="password" --execute="CREATE DATABASE IF NOT EXISTS glance;"
mysql --user="root" --password="password" --execute="GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY 'GLANCE_DBPASS';"
mysql --user="root" --password="password" --execute="GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY 'GLANCE_DBPASS';"
	
sudo DEBIAN_FRONTEND=noninteractive apt install glance -y

mv /etc/glance/glance-api.conf /etc/glance/glance-api.conf.original
cp ./files/glance/glance-api.conf /etc/glance/glance-api.conf
chgrp glance /etc/glance/glance-api.conf

su -s /bin/sh -c "glance-manage db_sync" glance
service glance-api restart

openstack user create --domain default --password GLANCE_PASS glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image service" image
openstack endpoint create --region RegionOne image public http://controller:9292
openstack endpoint create --region RegionOne image internal http://controller:9292
openstack endpoint create --region RegionOne image admin http://controller:9292

wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img
glance image-create --name "cirros" --file cirros-0.4.0-x86_64-disk.img --disk-format qcow2 --container-format bare --visibility=public


########################
#        Placement     #
########################
export OS_USERNAME=admin
export OS_PASSWORD=ADMIN_PASS
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_TENANT_NAME=admin

mysql --user="root" --password="password" --execute="CREATE DATABASE IF NOT EXISTS placement;"
mysql --user="root" --password="password" --password="password" --execute="GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY 'PLACEMENT_DBPASS';"
mysql --user="root" --password="password" --execute="GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY 'PLACEMENT_DBPASS';"

openstack user create --domain default --password PLACEMENT_PASS placement
openstack role add --project service --user placement admin
openstack service create --name placement --description "Placement API" placement

openstack endpoint create --region RegionOne placement public http://controller:8778
openstack endpoint create --region RegionOne placement internal http://controller:8778
openstack endpoint create --region RegionOne placement admin http://controller:8778

mkdir /home/placement
sudo DEBIAN_FRONTEND=noninteractive  apt install python3-pip -y
sudo DEBIAN_FRONTEND=noninteractive apt install placement-api -y

mv /etc/placement/placement.conf /etc/placement/placement.conf.original
cp ./files/placement/placement.conf /etc/placement/placement.conf
chgrp placement /etc/placement/placement.conf

sudo systemctl restart placement-api
su -s /bin/sh -c "placement-manage db sync" placement
sudo systemctl restart apache2

pip3 install osc-placement
openstack --os-placement-api-version 1.2 resource class list --sort-column name
openstack --os-placement-api-version 1.6 trait list --sort-column name

########################
#    Nova Controller   #
########################
export OS_USERNAME=admin
export OS_PASSWORD=ADMIN_PASS
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_TENANT_NAME=admin


mysql --user="root" --password="password" --execute="CREATE DATABASE IF NOT EXISTS nova_api;"
mysql --user="root" --password="password" --execute="CREATE DATABASE IF NOT EXISTS nova;"
mysql --user="root" --password="password" --execute="CREATE DATABASE IF NOT EXISTS nova_cell0;"

mysql --user="root" --password="password" --execute="GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY 'NOVA_DBPASS';"
mysql --user="root" --password="password" --execute="GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY 'NOVA_DBPASS';"

mysql --user="root" --password="password" --execute="GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY 'NOVA_DBPASS';"
mysql --user="root" --password="password" --execute="GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY 'NOVA_DBPASS';"

mysql --user="root" --password="password" --execute="GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY 'NOVA_DBPASS';"
mysql --user="root" --password="password" --execute="GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY 'NOVA_DBPASS';"

openstack user create --domain default --password NOVA_PASS nova
openstack service create --name nova --description "OpenStack Compute" compute
openstack role add --project service --user nova admin
openstack endpoint create --region RegionOne compute public http://controller:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://controller:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://controller:8774/v2.1

sudo DEBIAN_FRONTEND=noninteractive apt install nova-api nova-conductor nova-novncproxy nova-scheduler

mv /etc/nova/nova.conf /etc/nova/nova.conf.original
cp ./files/nova/nova.conf /etc/nova/nova.conf
chgrp nova /etc/nova/nova.conf

su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
su -s /bin/sh -c "nova-manage db sync" nova

su -s /bin/sh -c "nova-manage cell_v2 list_cells" nova

systemctl restart nova-api
systemctl restart nova-scheduler
systemctl restart nova-conductor
systemctl restart nova-novncproxy