CREATE DATABASE IF NOT EXISTS tdgpt_demo KEEP 36500d;
USE tdgpt_demo;
CREATE STABLE IF NOT EXISTS single_val (ts timestamp, val float) tags(scene varchar(64));
INSERT INTO ec2_failure using single_val tags('ec2_failure') FILE '/var/lib/taos/demo_data/ec2_failure.csv';