## Aggregation threshold in gold.zone_demand_daily

The gold layer applies `HAVING COUNT(*) >= 5`, suppressing any
(date, pickup_zip) group with fewer than 5 trips.

Measured impact on the current dataset:
- 3271 groups before suppression
- 1679 groups suppressed (51.3%)
- 828 of those were singletons — a single trip on a single day in a single ZIP

Rationale: aggregation alone does not anonymise. A row reporting one trip
discloses that individual trip as directly as the raw record would. The NYC
TLC 2014 release demonstrated this in practice, when supposedly anonymised
trip data was re-identified shortly after publication.

Trade-off accepted: roughly half of the daily zone groups are lost. Broad
read access to gold is only defensible because this cost is paid. The
alternative — unrestricted access to unsuppressed aggregates — would make
the layer separation decorative rather than protective.