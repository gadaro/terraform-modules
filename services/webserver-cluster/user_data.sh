#!bin/bash

yum install -y httpd
echo "Connected to `curl -s http://169.254.169.254/latest/meta-data/local-hostname`<br>" > /var/www/html/index.html
echo "Available db = ${db_address}:${db_port}" >> /var/www/html/index.html
echo "${additional_text}" >> /var/www/html/index.html
sed 's/Listen 80/Listen ${server_port}/' /etc/httpd/conf/httpd.conf -i
service httpd start
