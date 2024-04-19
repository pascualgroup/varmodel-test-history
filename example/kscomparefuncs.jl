"""
    Functions to compare outputs using K-S tests
"""

using SQLite
import SQLite.Stmt
import SQLite.DBInterface.execute
using Distributions
import StatsAPI.pvalue
import StatsBase.mean
import StatsBase.mad
import HypothesisTests.ApproximateTwoSampleKSTest

"""
    Do K-S tests using SQLite queries that take one parameter, run_id.

    `db1` and `db2` are assumed to have identical parameter combinations labeled the same way,
    via the `combo_id` column in the `runs` table.

    The query should return a single value for the provided run_id.

    If values from db2 need to be extracted with a different query, provide a value for `q2`.
"""
function compare(db1, db2, q1; q2 = q1)
    combo_ids = get_combo_ids(db1)
    @assert all(combo_ids .== get_combo_ids(db2))
    [(combo_id, compare(db1, db2, combo_id, q1; q2 = q2)) for combo_id in combo_ids]
end

function get_combo_ids(db)
    [combo_id for (combo_id,) in execute(db, "SELECT DISTINCT combo_id FROM runs ORDER BY combo_id")]
end

function get_run_ids(db, combo_id)
    [run_id for (run_id,) in execute(db, "SELECT run_id FROM runs WHERE combo_id = ?", [combo_id])]
end

function compare(db1, db2, combo_id, q1; q2 = q1)
    v1 = query_values_for_combo_id(db1, combo_id, q1)
    mean1 = mean(v1)
    mad1 = mad(v1; center = mean1)

    v2 = query_values_for_combo_id(db2, combo_id, q2)
    mean2 = mean(v2)
    mad2 = mad(v2; center = mean2)

    (ApproximateTwoSampleKSTest(v1, v2), (v1, mean1, mad1), (v2, mean2, mad2))
end

function query_values_for_combo_id(db, combo_id, q)
    stmt = Stmt(db, q)
    run_ids = get_run_ids(db, combo_id)

    [query_value_for_run_id(stmt, run_id) for run_id in run_ids]
end

function query_value_for_run_id(stmt, run_id)
    for (value,) in execute(stmt, (run_id,))
        return value
    end
end