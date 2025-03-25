CREATE DATABASE IF NOT EXISTS tdgpt_demo KEEP 36500d;
USE tdgpt_demo;
CREATE STABLE IF NOT EXISTS single_val (ts timestamp, val float) tags(scene varchar(64));
INSERT INTO electricity_demand using single_val tags('electricity_demand') FILE '/var/lib/taos/demo_data/electricity_demand.csv';
