English | [简体中文](README-CN.md)

# TDgpt Demo Environment Usage Guide

## 1. What is TDgpt

TDgpt is a time-series data analysis intelligent agent built into TDengine. It provides advanced time-series data analysis capabilities, including:
- Time-series data forecasting
- Time-series data anomaly detection

## 2. Supported Models

| Function Dimension | Algorithm/Model       | Version Support |
|--------------------|-----------------------|-----------------|
| **Forecasting**    | Arima, HoltWinters, LSTM, MLP, TDtsfm_1 (self-developed) | ≥3.3.6.0 |
| **Anomaly Detection** | k-Sigma, IQR, Grubbs, SHESD, LOF, Autoencoder | ≥3.3.6.0 |

## 3. Environment Preparation

### 3.1 Basic Environment Requirements
1. Git
2. Docker Engine (v20.10+)
3. Docker Compose (v2.20+)

### 3.2 Component Requirements

| Component Name                  | Version Requirement | Function Description           |
|------------------------|----------------------|-----------------------------|
| analyse.sh          | 1.0.0.0            | Generate and store forecasting/anomaly detection results |
| TDengine Community Edition| ≥3.3.6.0           | TDengine time-series database |
| TDgpt Community Edition| ≥3.3.6.0           | Integrates multiple time-series analysis algorithms |
| Grafana            | ≥11.0.11           | Data visualization |

## 4. Environment Initialization

### 4.1 Clone Repository
```bash
git clone https://github.com/taosdata/TDgpt-demo
cd TDgpt-demo
chmod 775 analyse.sh
```

### 4.2 Data Introduction

The TDgpt-demo/demo_data directory contains three CSV files (electricity_demand.csv, wind_power.csv, ec2_failure.csv) and three SQL scripts with the same prefix, corresponding to electricity demand forecasting, wind power generation forecasting, and operation monitoring anomaly detection scenarios respectively. 

The TDgpt-demo/demo_dashboard directory contains three JSON files ( electricity_demand.json , wind_power.json , and ec2_failure.json ), each corresponding to a dashboard for a specific scenario. 

The docker-compose.yml has defined a persistent volume tdengine-data for the TDengine container. After the container starts, use the docker cp command to copy demo_data into the container for use.

## 5. Running the Demo

### 5.1 Starting and Stopping Services

In the TDgpt-demo directory, execute the following commands:
```bash
# Start services
docker-compose up -d
```
Upon the first run, wait for 10 seconds, then execute the following command to register the Anode of TDgpt to TDengine:
```bash
# Register Anode
docker exec -it tdengine taos -s "create anode 'tdgpt:6090'"
```

After running the demo, use the following command to stop all containers:
```bash
# Stop services
docker-compose down
```

### 5.2 Data Initialization

```bash
# Copy data and scripts to the container
docker cp analyse.sh tdengine:/var/lib/taos
docker cp demo_data tdengine:/var/lib/taos
# Initialize data
docker exec -it tdengine taos -s "source /var/lib/taos/demo_data/init_electricity_demand.sql"
docker exec -it tdengine taos -s "source /var/lib/taos/demo_data/init_wind_power.sql"
docker exec -it tdengine taos -s "source /var/lib/taos/demo_data/init_ec2_failure.sql"
```

### 5.3 Configuring the Grafana Dashboard

1. Open your browser and enter http://localhost:3000, then log in to Grafana with the default username and password admin/admin.
2. After logging in, go to the "Home → Dashboards" page and import the electricity_demand_forecast.json, wind_power.json, and ec2_failure_anomaly.json files one by one.
4. Select the dashboard to view the results. The initial dashboard only shows the actual values of electricity_demand, wind_power, and ec2_failure.
5. Follow the steps below to execute the shell script command, which will generate dynamic forecasting results based on the original data and display them on the dashboard. The dashboard is configured to refresh every 5 seconds, so you can view the dynamic forecasting curve during execution.

### 5.4 Reproducing the Forecasting Process

#### 5.4.1 Electricity Demand Forecasting

Take the electricity demand forecasting scenario as an example using the analyse.sh script to achieve forecasting results. First, complete the demonstration of the TDtsfm_1 algorithm by executing the following command on the host:
```bash
docker exec -it tdengine /var/lib/taos/analyse.sh --type forecast --db tdgpt_demo \
--table electricity_demand --stable single_val --algorithm tdtsfm_1 \
--params "fc_rows=48,wncheck=0" --start "2024-01-01" --window 30d --step 1d
```

The above shell script will start from the specified start time (2024-01-01), use the data from the previous month as input, and use the TDtsfm_1 algorithm to forecast the electricity demand every 30 minutes for the next day (a total of 48 data points) until it reaches the last day of the electricity_demand table, and write the results into the electricity_demand_tdtsfm_1_result table. Before executing a new forecast, the script will create or clear the corresponding result table. During execution, it will continuously output the execution results on the console on a daily basis:

```bash
Processing window: 2024-01-12 00:00:00 → 2024-02-11 00:00:00
Welcome to the TDengine Command Line Interface, Client Version:3.3.6.0
Copyright (c) 2023 by TDengine, all rights reserved.

taos> INSERT INTO tdgpt_demo.electricity_demand_tdtsfm_1_result SELECT _frowts, forecast(val, 'algorithm=tdtsfm_1,fc_rows=48,wncheck=0') 
               FROM tdgpt_demo.electricity_demand
               WHERE ts >= '2024-01-12 00:00:00' AND ts < '2024-02-11 00:00:00'
Insert OK, 48 row(s) affected (0.238208s)
```

We then complete the demonstration of the HotWinters algorithm by executing the following command:
```bash
docker exec -it tdengine /var/lib/taos/analyse.sh --type forecast --db tdgpt_demo \
--table electricity_demand --stable single_val --algorithm holtwinters \
--params "rows=48,period=48,wncheck=0,trend=add,seasonal=add" --start "2024-01-01" --window 30d --step 1d
```

#### 5.4.2 Wind Power Generation Forecasting

```bash
docker exec -it tdengine /var/lib/taos/analyse.sh --type forecast --db tdgpt_demo \
--table wind_power --stable single_val --algorithm tdtsfm_1 \
--params "fc_rows=96,wncheck=0" --start "2024-07-12" --window 30d --step 1d 
```
```bash
docker exec -it tdengine /var/lib/taos/analyse.sh --type forecast --db tdgpt_demo \
--table wind_power --stable single_val --algorithm holtwinters \
--params "rows=96,period=96,wncheck=0,trend=add,seasonal=add" --start "2024-07-12" --window 30d --step 1d 
```

#### 5.4.3 Operation Monitoring Anomaly Detection

```bash
docker exec -it tdengine /var/lib/taos/analyse.sh --type anomaly --db tdgpt_demo \
--table ec2_failure --stable single_val --algorithm ksigma \
--params "k=3" --start "2014-03-07" --window 7d --step 1h
```
```bash
docker exec -it tdengine /var/lib/taos/analyse.sh --type anomaly --db tdgpt_demo \
--table ec2_failure --stable single_val --algorithm grubbs \
--start "2014-03-07" --window 7d --step 1h
```

## 6. TDengine Time-Series Analysis Script Usage Guide

### 6.1 Script Overview

This script is used to perform forecasting (forecast) and anomaly detection (anomaly) analysis on the TDengine time-series database, and supports processing time-series data with a sliding window mechanism. The script achieves flexible time window management and invocation of multiple algorithms through parameterized configuration.

### 6.2 Parameter Description

#### 6.2.1 Required Parameters

| Parameter Name | Description | Example Value |
|----------------|-------------|---------------|
| `--db` | Target database name | `tdgpt_demo` |
| `--table` | Source data table name | `electricity_demand` |
| `--stable` | Super table name | `single_val` |
| `--type` | Analysis type (`forecast`/`anomaly`) | `forecast` |
| `--algorithm` | Algorithm name | `holtwinters` |
| `--params` | Algorithm parameter key-value pairs | `"period=48,trend=add"` |
| `--start` | Analysis start time | `"2024-08-01"` |

#### 6.2.2 Optional Parameters

| Parameter Name | Default Value | Description | Example Value |
|----------------|---------------|-------------|---------------|
| `--ts_col` | `ts` | Timestamp column name | `timestamp` |
| `--val_col` | `val` | Value column name | `voltage` |
| `--step` | `1d` | Window sliding step length | `15m` |
| `--window` | `30d` | Analysis window size | `24h` |

### 6.3 Time Format Specifications

| Unit Character | Time Unit | Valid Value Range | Example Conversion |
|----------------|-----------|-------------------|---------------------|
| `d` | Days | ≥1 | `30d=2592000 seconds` |
| `h` | Hours | ≥1 | `24h=86400 seconds` |
| `m` | Minutes | ≥1 | `15m=900 seconds` |

### 6.4 Usage Examples

#### 6.4.1 Electricity Demand Forecasting

```bash
./analyse.sh \
  --db tdgpt_demo \
  --table electricity_demand \
  --stable single_val \
  --type forecast \
  --algorithm holtwinters \
  --params "period=48,trend=add" \
  --start "2024-08-01" \
  --window 30d \
  --step 1d
```

## 7. Using More Data

Refer to the content of the "5.2 Data Initialization" and "5.4 Reproducing the Forecast" sections, execute the corresponding SQL commands, and ensure that the data is prepared in CSV format (comma-separated, and values need to be enclosed in English double quotes) to import the data into TDengine. Then, use the methods in Section 5 to generate forecasting results and adjust the Grafana dashboard to compare with the actual data.