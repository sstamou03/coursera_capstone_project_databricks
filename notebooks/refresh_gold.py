CATALOG = "capstone_gov"

spark.sql(f"""
INSERT OVERWRITE {CATALOG}.gold.zone_demand_daily
SELECT
  t.trip_date,
  t.pickup_zip,
  z.borough,
  z.zone_name,
  COUNT(*) AS trip_count,
  ROUND(AVG(t.fare_amount), 2) AS avg_fare,
  ROUND(AVG(t.trip_distance), 2) AS avg_distance
FROM {CATALOG}.silver.trips_clean t
LEFT JOIN {CATALOG}.silver.zones z ON t.pickup_zip = z.zip_code
GROUP BY t.trip_date, t.pickup_zip, z.borough, z.zone_name
HAVING COUNT(*) >= 5
""")

print("zone_demand_daily refreshed")


spark.sql(f"""
INSERT OVERWRITE {CATALOG}.gold.revenue_hourly
SELECT
  trip_date,
  HOUR(pickup_hour) AS hour_of_day,
  COUNT(*) AS trip_count,
  ROUND(SUM(fare_amount), 2) AS total_fare,
  ROUND(AVG(duration_minutes), 2) AS avg_duration_min
FROM {CATALOG}.silver.trips_clean
GROUP BY trip_date, HOUR(pickup_hour)
""")

print("revenue_hourly refreshed")

display(spark.sql(f"""
SELECT 'gold.zone_demand_daily' AS table_name, COUNT(*) AS row_count
FROM {CATALOG}.gold.zone_demand_daily
UNION ALL
SELECT 'gold.revenue_hourly', COUNT(*)
FROM {CATALOG}.gold.revenue_hourly
"""))