#!/bin/bash

# Parse command line arguments
usage() {
    echo "Usage: $0 --db <db> --table <table> --stable <stable> --type <forecast|anomaly> --algorithm <name> --params <params> --start <start_time> [--ts_col <ts_col>] [--val_col <val_col>] [--step <step>] [--window <window>]"
    echo "Examples:"
    echo "  Forecasting:"
    echo "    $0 --db tdgpt_demo --table electricity_demand --stable single_val --type forecast --algorithm holtwinters --params \"period=48,trend=add\" --start \"2024-08-01\" --window 30d --step 1d"
    echo "  Anomaly Detection:"
    echo "    $0 --db tdgpt_demo --table ec2_failure --stable single_val --type anomaly --algorithm ksigma --params \"k=3\" --start \"2014-03-07\" --window 7d --step 5m"
    echo "Time Formats:"
    echo "  - window: 30d (days), 24h (hours), 1440m (minutes)"
    echo "  - step:   1d (days), 4h (hours), 15m (minutes)"
    exit 1
}

# Initialize variables with defaults
DB_NAME=""
TABLE_NAME=""
STABLE_NAME=""
ANALYSIS_TYPE=""
ALGORITHM_NAME=""
ALGORITHM_PARAMS=""
START_TS=""
TS_COL="ts"
VAL_COL="val"
STEP="1d"
WINDOW="30d"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)        DB_NAME="$2"; shift 2 ;;
        --table)     TABLE_NAME="$2"; shift 2 ;;
        --stable)    STABLE_NAME="$2"; shift 2 ;;
        --type)      ANALYSIS_TYPE="$2"; shift 2 ;;
        --algorithm) ALGORITHM_NAME="$2"; shift 2 ;;
        --params)    ALGORITHM_PARAMS="$2"; shift 2 ;;
        --start)     START_TS="$2"; shift 2 ;;
        --ts_col)    TS_COL="$2"; shift 2 ;;
        --val_col)   VAL_COL="$2"; shift 2 ;;
        --step)      STEP="$2"; shift 2 ;;
        --window)    WINDOW="$2"; shift 2 ;;
        *)           echo "Unknown parameter: $1"; usage ;;
    esac
done

# Validate required parameters
[[ -z "$DB_NAME" || -z "$TABLE_NAME" || -z "$ANALYSIS_TYPE" || 
  -z "$ALGORITHM_NAME" ]] && {
    echo "Error: Missing required parameters!"
    usage
}

# Validate analysis type
[[ "$ANALYSIS_TYPE" =~ ^(forecast|anomaly)$ ]] || {
    echo "Invalid analysis type: $ANALYSIS_TYPE. Must be 'forecast' or 'anomaly'"
    exit 1
}

# Convert time parameters to seconds
time_to_seconds() {
    local input=$1
    local unit=${input//[0-9]/}
    local value=${input//[^0-9]/}
    case "$unit" in
        d) echo $((value * 86400)) ;;  # Days to seconds
        h) echo $((value * 3600)) ;;   # Hours to seconds
        m) echo $((value * 60)) ;;     # Minutes to seconds
        *) echo "Invalid time unit: $unit"; exit 1 ;;
    esac
}

WINDOW_SECONDS=$(time_to_seconds "$WINDOW")
STEP_SECONDS=$(time_to_seconds "$STEP")

# Time conversion functions using UTC
timestamp_to_utc() {
    date -u -d "@$1" "+%Y-%m-%d %H:%M:%S"
}

datetime_to_timestamp() {
    date -u -d "$1" "+%s"
}


# TDengine connection command
TAOS_CMD="taos -d $DB_NAME -s"


# Set start time
if [[ -z "$START_TS" ]]; then
    echo "No start time specified, using earliest available timestamp"
    echo "Querying minimum timestamp from table: $TABLE_NAME"
    SQL_MIN_TS="SELECT first($TS_COL) FROM $TABLE_NAME"
    MIN_TS=$($TAOS_CMD "$SQL_MIN_TS" | awk 'NR==7 {print $1" "$2}')
    
    if [[ -z "$MIN_TS" ]]; then
        echo "Error: Failed to get minimum timestamp from table"
        exit 1
    fi
    echo "Using minimum timestamp from data: $MIN_TS"
    START_TS_EPOCH=$(datetime_to_timestamp "$MIN_TS")
else
    START_TS_EPOCH=$(datetime_to_timestamp "$START_TS")
fi

# Get maximum timestamp from source table
SQL_MAX_TS="SELECT last($TS_COL) FROM $TABLE_NAME"
MAX_TS=$($TAOS_CMD "$SQL_MAX_TS" | awk 'NR==7 {print $1" "$2}')
MAX_TS_EPOCH=$(datetime_to_timestamp "$MAX_TS")
MAX_TS_EPOCH=$((MAX_TS_EPOCH + STEP_SECONDS))

echo "Processing range: $(timestamp_to_utc $START_TS_EPOCH) to $(timestamp_to_utc $MAX_TS_EPOCH)"

# Generate result table name
RESULT_TABLE="${TABLE_NAME}_${ALGORITHM_NAME}_result"

# SQL generation based on analysis type
generate_sql() {
    local window_start=$1
    local window_end=$2
    local algo_params=""
    
    if [[ -n "$ALGORITHM_PARAMS" ]] ; then 
    		algo_params=",$ALGORITHM_PARAMS" 
    fi
    
    case "$ANALYSIS_TYPE" in
        "forecast")
            echo "INSERT INTO $RESULT_TABLE 
                  SELECT _frowts AS $TS_COL, 
                         forecast($VAL_COL, 'algo=$ALGORITHM_NAME$algo_params') AS $VAL_COL
                  FROM $TABLE_NAME 
                  WHERE $TS_COL >= '$window_start' AND $TS_COL < '$window_end'"
            ;;
        "anomaly")
            echo "INSERT INTO $RESULT_TABLE 
                  SELECT _wstart, 
                         avg($VAL_COL)
                  FROM $TABLE_NAME 
                  WHERE $TS_COL >= '$window_start' AND $TS_COL < '$window_end'
                  ANOMALY_WINDOW($VAL_COL, 'algo=$ALGORITHM_NAME$algo_params')"
            ;;
    esac
}

## Table management functions
prepare_result_table() {
    echo "Checking table: $RESULT_TABLE"
    EXISTS=$($TAOS_CMD "SHOW TABLES LIKE '$RESULT_TABLE'" | grep "table_name")
    
    if [[ -n "$EXISTS" ]]; then
        echo "Clearing existing table"
        $TAOS_CMD "DELETE FROM $RESULT_TABLE"
    else
        echo "Creating new table"
        $TAOS_CMD "CREATE TABLE $RESULT_TABLE USING $STABLE_NAME TAGS ('$RESULT_TABLE')"
    fi
}

# Initialize processing window
CURRENT_END_TS_EPOCH=$((START_TS_EPOCH + WINDOW_SECONDS))

# Create result table
prepare_result_table

# Main processing loop with internal condition check
while [[ $CURRENT_END_TS_EPOCH -le $MAX_TS_EPOCH ]] ; do
    # Convert timestamps to UTC strings
    WINDOW_START=$(timestamp_to_utc $START_TS_EPOCH)
    WINDOW_END=$(timestamp_to_utc $CURRENT_END_TS_EPOCH)
    
    # Generate appropriate SQL
    PREDICT_SQL=$(generate_sql "$WINDOW_START" "$WINDOW_END")
    
    echo "Processing window: $WINDOW_START → $WINDOW_END"
    $TAOS_CMD "$PREDICT_SQL"

    # Advance window
    START_TS_EPOCH=$((START_TS_EPOCH + STEP_SECONDS))
    CURRENT_END_TS_EPOCH=$((CURRENT_END_TS_EPOCH + STEP_SECONDS))
    
done

echo "Processing completed successfully. Results stored in: $RESULT_TABLE"