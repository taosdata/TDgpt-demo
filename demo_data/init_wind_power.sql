CREATE DATABASE IF NOT EXISTS tdgpt_demo KEEP 36500d;
USE tdgpt_demo;
CREATE STABLE IF NOT EXISTS single_val (ts timestamp, val float) tags(scene varchar(64));
INSERT INTO wind_power using single_val tags('wind_power') FILE '/var/lib/taos/demo_data/wind_power.csv';