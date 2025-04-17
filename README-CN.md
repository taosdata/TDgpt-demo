简体中文 | [English](README.md)

# TDgpt体验测试环境使用指南

## 1. TDgpt是什么

TDgpt是TDengine内置的时序数据分析智能体，它基于TDengine的时序数据查询功能，通过SQL提供运行时可动态扩展和切换的时序数据高级分析能力，包括：
- 时序数据预测
- 时序数据异常检测

## 2. 已支持模型
| 功能维度       | 算法/模型                                    | 版本支持     |
|----------------|------------------------------------------|-------------|
| **预测模型**   | Arima、HoltWinters、LSTM、MLP、TDtsfm_1（自研）  | ≥3.3.6.0    |
| **异常检测**   | k-Sigma、IQR、Grubbs、SHESD、LOF、Autoencoder | ≥3.3.6.0    |


---

## 3. 环境准备
### 3.1 基础环境要求
1. Git
2. Docker Engine (v20.10+)
3. Docker Compose (v2.20+)

### 3.2 组件要求
| 组件名称                  | 版本要求     | 功能描述           |
|------------------------|--------------|----------------|
| analyse.sh          | 1.0.0.0      | 生成预测/异常检测结果并存储 |
| TDengine Community Edition| ≥3.3.6.0     | TDengine时序数据库  |
| TDgpt Community Edition| ≥3.3.6.0     | 集成多种时序分析算法     |
| Grafana            | ≥11.0.11     | 数据可视化展示        |

---

## 4. 环境初始化
### 4.1 克隆仓库
```bash
git clone https://github.com/taosdata/TDgpt-demo
cd TDgpt-demo
chmod 775 analyse.sh
```
### 4.2 数据简介
TDgpt-demo/demo_data下包含三个csv文件（electricity_demand.csv、wind_power.csv、ec2_failure.csv），以及三个同前缀sql脚本，分别对应电力需求预测、风力发电预测和运维监控异常检测场景。

TDgpt-demo/demo_dashboard下包含了三个json文件（electricity_demand_forecast.json , wind_power_forecast.json , and ec2_failure_anomaly.json），分别对应三个场景的看板。

docker-compose.yml中已经定义了TDengine容器的持久化卷：tdengine-data，待容器启动后，使用docker cp命令将demo_data拷贝至容器内使用。

## 5. 运行demo
**注意：在运行demo前，请根据您宿主机的架构（CPU类型），编辑docker-compose.yml文件，为TDengine指定对应的platform参数：linux/amd64（Intel/AMD CPU）或linux/arm64（ARM CPU）。TDgpt必须统一使用linux/amd64参数。**
### 5.1 服务启停
在TDgpt-demo目录下执行如下命令：
```bash
# 启动服务
docker-compose up -d
```
首次运行时，等待10s后请执行如下命令将TDgpt的Anode节点注册到TDengine：
```bash
# 注册Anode
docker exec -it tdengine taos -s "create anode 'tdgpt:6090'"
```

运行完demo后，使用下面的命令停止所有容器
```bash
# 停止服务
docker-compose down
```

### 5.2 数据初始化

```bash
# 拷贝数据和脚本到容器
docker cp analyse.sh tdengine:/var/lib/taos
docker cp demo_data tdengine:/var/lib/taos
# 初始化数据
docker exec -it tdengine taos -s "source /var/lib/taos/demo_data/init_electricity_demand.sql"
docker exec -it tdengine taos -s "source /var/lib/taos/demo_data/init_wind_power.sql"
docker exec -it tdengine taos -s "source /var/lib/taos/demo_data/init_ec2_failure.sql"
```
### 5.3 配置Grafana看板

1. 打开浏览器，输入http://localhost:3000，并用默认的用户名口令 admin/admin 登录Grafana。
2. 登录成功后，进入路径"Home → Dashboards"页面，并且依次导入electricity_demand_forecast.json、wind_power_forecast.json、ec2_failure_anomaly.json文件。 
4. 选择看板并查看结果。 初始看板上只显示electricity_demand、wind_power、ec2_failure数据的真实值。
5. 按照下列步骤，执行shell脚本命令，将基于原始的数据，生成动态的预测结果，并呈现在看板上。看板配置为5s刷新，在执行过程中可查看动态预测曲线。

### 5.4 复现预测过程

#### 5.4.1 电力需求预测
我们以电力需求预测场景为例analyze.sh脚本，来实现预测结果。首先完成TDtsfm_1算法的演示，在宿主机上执行如下命令：
```bash
docker exec -it tdengine /var/lib/taos/analyse.sh --type forecast --db tdgpt_demo \
--table electricity_demand --stable single_val --algorithm tdtsfm_1 \
--params "rows=48,wncheck=0" --start "2024-01-01" --window 30d --step 1d
```
上述shell脚本，将从指定的起始时间开始（2024-01-01）以前一个月的数据为输入，使用TDtsfm_1算法预测当前下一天的每30mins的电力需求（共计48个数据点），直到达到electricity_demand 表中最后一天的记录，并将结果写入electricity_demand_tdtsfm_1_result 表中。执行新的预测前，脚本会新建/清空对应的结果表。执行过程中将持续在控制台上，按照天为单位推进输出如下的执行结果：

```bash
Processing window: 2024-01-12 00:00:00 → 2024-02-11 00:00:00
Welcome to the TDengine Command Line Interface, Client Version:3.3.6.0
Copyright (c) 2023 by TDengine, all rights reserved.

taos> INSERT INTO tdgpt_demo.electricity_demand_tdtsfm_1_result SELECT _frowts, forecast(val, 'algo=tdtsfm_1,rows=48,wncheck=0') 
               FROM tdgpt_demo.electricity_demand
               WHERE ts >= '2024-01-12 00:00:00' AND ts < '2024-02-11 00:00:00'
Insert OK, 48 row(s) affected (0.238208s)
```
我们再完成HotWinters算法的演示，在宿主机上执行如下命令：
```bash
docker exec -it tdengine /var/lib/taos/analyse.sh --type forecast --db tdgpt_demo \
--table electricity_demand --stable single_val --algorithm holtwinters \
--params "rows=48,period=48,wncheck=0,trend=add,seasonal=add" --start "2024-01-01" --window 30d --step 1d
```

#### 5.4.2 风力发电量预测
```bash
docker exec -it tdengine /var/lib/taos/analyse.sh --type forecast --db tdgpt_demo \
--table wind_power --stable single_val --algorithm tdtsfm_1 \
--params "rows=96,wncheck=0" --start "2024-07-12" --window 30d --step 1d 
```
```bash
docker exec -it tdengine /var/lib/taos/analyse.sh --type forecast --db tdgpt_demo \
--table wind_power --stable single_val --algorithm holtwinters \
--params "rows=96,period=96,wncheck=0,trend=add,seasonal=add" --start "2024-07-12" --window 30d --step 1d 
```

#### 5.4.3 运维监控异常检测

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

---

## 6. TDengine 时序分析脚本使用说明

### 6.1 脚本概述
本脚本用于在TDengine时序数据库上执行预测(forecast)和异常检测(anomaly)分析，支持滑动窗口机制处理时序数据。脚本通过参数化配置实现灵活的时间窗口管理和多种算法调用。

### 6.2 参数说明

#### 6.2.1 必选参数
| 参数名       | 描述                 | 示例值            |
|--------------|----------------------|-------------------|
| `--db`       | 目标数据库名称       | `tdgpt_demo`      |
| `--table`    | 源数据表名           | `electricity_demand` |
| `--stable`   | 超级表名称           | `single_val`      |
| `--type`     | 分析类型(`forecast/anomaly`)| `forecast`       |
| `--algorithm`| 算法名称             | `holtwinters`     |
| `--params`   | 算法参数键值对       | `"period=48,trend=add"` |
| `--start`    | 分析起始时间         | `"2024-08-01"`    |

#### 6.2.2 可选参数
| 参数名      | 默认值 | 描述                  | 示例值       |
|-------------|--------|-----------------------|--------------|
| `--ts_col`  | `ts`   | 时间戳列名            | `timestamp`  |
| `--val_col` | `val`  | 数值列名              | `voltage`    |
| `--step`    | `1d`   | 窗口滑动步长          | `15m`        |
| `--window`  | `30d`  | 分析窗口大小          | `24h`        |

---

### 6.3 时间格式规范
| 单位字符 | 时间单位 | 有效值范围     | 示例换算      |
|----------|----------|----------------|---------------|
| `d`      | 天数     | ≥1             | `30d=2592000秒` |
| `h`      | 小时数   | ≥1             | `24h=86400秒`   |
| `m`      | 分钟数   | ≥1             | `15m=900秒`     |

---

### 6.4 使用示例

#### 6.4.1 电力需求预测
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

## 7. 使用更多的数据
参考“5.2 数据初始化”和“5.4 复现预测”章节内容，执行对应的sql，并确保按照规定格式将数据准备为csv格式（逗号分隔，值需要用英文双引号括起来），即可将数据导入TDengine。然后，请使用章节5中的方法来生成预测结果，并调整Grafana中的看板以实现和实际数据的对比。
