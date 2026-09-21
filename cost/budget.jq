def within_budget($baseline; $budget; $period):
  (try (.totalMonthlyCost | tonumber) catch null) as $incremental
  | ($incremental != null)
    and (.currency == "USD")
    and ($incremental >= 0)
    and ($baseline >= 0 and $budget > 0)
    and ($period == (now | strftime("%Y-%m")))
    and ($incremental + $baseline <= $budget)
    and (.summary.totalUnsupportedResources == 0)
    and ([.projects[].breakdown.resources[]?
          | select(.name == "module.storage.google_storage_bucket.shared_artifacts")]
         | length) == 1;
