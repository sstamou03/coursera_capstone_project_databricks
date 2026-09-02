CREATE TABLE IF NOT EXISTS capstone_gov.bronze.trips_raw (
  tpep_pickup_datetime  TIMESTAMP COMMENT 'Second-level pickup time. SENSITIVE: acts as a quasi-identifier when combined with zip codes.',
  tpep_dropoff_datetime TIMESTAMP COMMENT 'Second-level dropoff time. Same re-identification risk.',
  trip_distance         DOUBLE    COMMENT 'Trip distance in miles as recorded by the meter. Unvalidated: contains zeros and outliers.',
  fare_amount           DOUBLE    COMMENT 'Fare in USD excluding tips and surcharges. Unvalidated: contains negatives from cancellations.',
  pickup_zip            INT       COMMENT 'Pickup ZIP code. SENSITIVE as location data.',
  dropoff_zip           INT       COMMENT 'Dropoff ZIP code. SENSITIVE as location data.',
  source_system         STRING    COMMENT 'Originating system, for lineage across multiple sources.',
  ingested_at           TIMESTAMP COMMENT 'Bronze ingestion time. Basis for the freshness check in Lakehouse Monitoring.'
)
USING DELTA
COMMENT 'Raw taxi trips as received. No validation. Contains exact timestamps and location data.';


INSERT INTO capstone_gov.bronze.trips_raw
SELECT
  tpep_pickup_datetime,
  tpep_dropoff_datetime,
  trip_distance,
  fare_amount,
  pickup_zip,
  dropoff_zip,
  'nyc_tlc_samples' AS source_system,
  current_timestamp() AS ingested_at
FROM samples.nyctaxi.trips;


CREATE TABLE IF NOT EXISTS capstone_gov.bronze.zone_reference_raw (
  zip_code    INT       COMMENT 'ZIP code, join key to trip records.',
  borough     STRING    COMMENT 'NYC borough (Manhattan, Brooklyn, Queens, Bronx, Staten Island).',
  zone_name   STRING    COMMENT 'Neighbourhood name for BI readability.',
  is_airport  BOOLEAN   COMMENT 'Airport flag: these trips have a distinct fare profile.',
  ingested_at TIMESTAMP COMMENT 'Bronze ingestion time.'
)
USING DELTA
COMMENT 'Zone reference data. Static enrichment lookup, contains no personal data.';


INSERT INTO capstone_gov.bronze.zone_reference_raw VALUES
  (10001, 'Manhattan', 'Chelsea',          false, current_timestamp()),
  (10019, 'Manhattan', 'Midtown West',     false, current_timestamp()),
  (10011, 'Manhattan', 'Greenwich West',   false, current_timestamp()),
  (10022, 'Manhattan', 'Midtown East',     false, current_timestamp()),
  (11371, 'Queens',    'LaGuardia',        true,  current_timestamp()),
  (11430, 'Queens',    'JFK Airport',      true,  current_timestamp()),
  (11201, 'Brooklyn',  'Brooklyn Heights', false, current_timestamp()),
  (10451, 'Bronx',     'Concourse',        false, current_timestamp());


-- ============================= SILVER =============================

CREATE TABLE IF NOT EXISTS capstone_gov.silver.trips_clean (
  trip_id           STRING    COMMENT 'Surrogate trip key, replacing the composite time-and-location identity.',
  pickup_hour       TIMESTAMP COMMENT 'Pickup time truncated to the hour. Reduced precision limits re-identification risk.',
  trip_date         DATE      COMMENT 'Trip date, grouping key for daily metrics.',
  duration_minutes  DOUBLE    COMMENT 'Trip duration in minutes, derived from timestamps. Validated as positive.',
  trip_distance     DOUBLE    COMMENT 'Distance in miles, filtered to a plausible range (0 to 100).',
  fare_amount       DOUBLE    COMMENT 'Fare in USD, filtered to positive values.',
  pickup_zip        INT       COMMENT 'Pickup ZIP. Retained for spatial analysis; access remains restricted.',
  dropoff_zip       INT       COMMENT 'Dropoff ZIP.'
)
USING DELTA
COMMENT 'Validated trips with reduced temporal precision. Source of truth for gold aggregates.';


INSERT INTO capstone_gov.silver.trips_clean
SELECT
  md5(concat_ws('|', tpep_pickup_datetime, pickup_zip, dropoff_zip, fare_amount)) AS trip_id,
  date_trunc('hour', tpep_pickup_datetime) AS pickup_hour,
  CAST(tpep_pickup_datetime AS DATE) AS trip_date,
  (unix_timestamp(tpep_dropoff_datetime) - unix_timestamp(tpep_pickup_datetime)) / 60.0 AS duration_minutes,
  trip_distance,
  fare_amount,
  pickup_zip,
  dropoff_zip
FROM capstone_gov.bronze.trips_raw
WHERE fare_amount > 0
  AND trip_distance > 0
  AND trip_distance < 100
  AND tpep_dropoff_datetime > tpep_pickup_datetime;


CREATE TABLE IF NOT EXISTS capstone_gov.silver.zones (
  zip_code   INT     COMMENT 'ZIP code, deduplicated and validated.',
  borough    STRING  COMMENT 'Borough, normalised to a fixed value set.',
  zone_name  STRING  COMMENT 'Neighbourhood name.',
  is_airport BOOLEAN COMMENT 'Airport flag.'
)
USING DELTA
COMMENT 'Cleaned zone lookup used to enrich gold metrics.';


INSERT INTO capstone_gov.silver.zones
SELECT DISTINCT zip_code, borough, zone_name, is_airport
FROM capstone_gov.bronze.zone_reference_raw
WHERE zip_code IS NOT NULL;


-- ============================== GOLD ==============================

CREATE TABLE IF NOT EXISTS capstone_gov.gold.zone_demand_daily (
  trip_date    DATE   COMMENT 'Reporting date.',
  pickup_zip   INT    COMMENT 'Pickup ZIP, safe at aggregate level.',
  borough      STRING COMMENT 'Borough, from the zone lookup.',
  zone_name    STRING COMMENT 'Neighbourhood name for BI.',
  trip_count   BIGINT COMMENT 'Number of trips. Rows with fewer than 5 trips are excluded so individual trips are never exposed (k-anonymity, k=5).',
  avg_fare     DOUBLE COMMENT 'Mean fare in USD.',
  avg_distance DOUBLE COMMENT 'Mean distance in miles.'
)
USING DELTA
COMMENT 'Daily demand per zone. Aggregated with a k=5 threshold; safe for broad read access.';


INSERT INTO capstone_gov.gold.zone_demand_daily
SELECT
  t.trip_date,
  t.pickup_zip,
  z.borough,
  z.zone_name,
  COUNT(*) AS trip_count,
  ROUND(AVG(t.fare_amount), 2) AS avg_fare,
  ROUND(AVG(t.trip_distance), 2) AS avg_distance
FROM capstone_gov.silver.trips_clean t
LEFT JOIN capstone_gov.silver.zones z
  ON t.pickup_zip = z.zip_code
GROUP BY t.trip_date, t.pickup_zip, z.borough, z.zone_name
HAVING COUNT(*) >= 5;


CREATE TABLE IF NOT EXISTS capstone_gov.gold.revenue_hourly (
  trip_date        DATE   COMMENT 'Reporting date.',
  hour_of_day      INT    COMMENT 'Hour of day, 0 to 23, for peak-demand analysis.',
  trip_count       BIGINT COMMENT 'Number of trips in that hour.',
  total_fare       DOUBLE COMMENT 'Total revenue in USD.',
  avg_duration_min DOUBLE COMMENT 'Mean trip duration in minutes, a proxy for traffic congestion.'
)
USING DELTA
COMMENT 'Hourly revenue and demand intensity. Fully aggregated, no spatial breakdown.';


INSERT INTO capstone_gov.gold.revenue_hourly
SELECT
  trip_date,
  HOUR(pickup_hour) AS hour_of_day,
  COUNT(*) AS trip_count,
  ROUND(SUM(fare_amount), 2) AS total_fare,
  ROUND(AVG(duration_minutes), 2) AS avg_duration_min
FROM capstone_gov.silver.trips_clean
GROUP BY trip_date, HOUR(pickup_hour);


-- ============================ VERIFY ==============================

SELECT 'bronze.trips_raw'        AS table_name, COUNT(*) AS row_count FROM capstone_gov.bronze.trips_raw
UNION ALL SELECT 'bronze.zone_reference_raw', COUNT(*) FROM capstone_gov.bronze.zone_reference_raw
UNION ALL SELECT 'silver.trips_clean',        COUNT(*) FROM capstone_gov.silver.trips_clean
UNION ALL SELECT 'silver.zones',              COUNT(*) FROM capstone_gov.silver.zones
UNION ALL SELECT 'gold.zone_demand_daily',    COUNT(*) FROM capstone_gov.gold.zone_demand_daily
UNION ALL SELECT 'gold.revenue_hourly',       COUNT(*) FROM capstone_gov.gold.revenue_hourly;