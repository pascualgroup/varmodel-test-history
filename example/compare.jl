#!/usr/bin/env julia

import StatsAPI.pvalue
import StatsBase.mean
import StatsBase.mad
import HypothesisTests.ApproximateTwoSampleKSTest
using SQLite
import SQLite.Stmt
import SQLite.DBInterface.execute
using Distributions
import JSON.json

include("kscomparefuncs.jl")


function main()
    cd(dirname(PROGRAM_FILE))

    db1 = SQLite.DB("output/before/sweep_db_gathered.sqlite")
    db2 = SQLite.DB("output/after/sweep_db_gathered.sqlite")

    compdb_filename = "compare.sqlite"
    if ispath(compdb_filename)
        error("$(compdb_filename) already exists; please move or delete")
    end

    # Copy parameter combinations into comparison DB
    execute(db1, "ATTACH DATABASE \'$(compdb_filename)\' AS compdb")
    execute(db1, "CREATE TABLE compdb.param_combos AS SELECT * FROM param_combos")
    execute(db1, "DETACH DATABASE compdb")

    compdb = SQLite.DB(compdb_filename)

    # Create comparison output table
    # Note: values1 (before) and values2 (after) contain raw samples as JSON arrays
    execute(compdb, "CREATE TABLE comparisons (comparison_name, combo_id, ks_pvalue, frac_diff, mean1, mean2, mad1, mad2, values1, values2)")
    comp_insert = Stmt(compdb, "INSERT INTO comparisons VALUES (?,?,?,?,?,?,?,?,?,?)")

    # Function to do a comparison
    function do_comparison(comparison_name, q1; q2 = q1)
        for (combo_id, (test, (values1, mean1, mad1), (values2, mean2, mad2))) in compare(db1, db2, q1; q2 = q2)
            println("Testing $(comparison_name) for param combo $(combo_id)...")
            println("    (mean1 $(mean1), mad1 $(mad1))")
            println("    (mean2 $(mean2), mad2 $(mad2))")

            pval = pvalue(test)
            println("    p-value: $(pval)")
            if pval < 0.01
                println("    DIFFERENT distributions w/ p < 0.01")
            else
                println("    undetectable difference between distributions w/ p < 0.01")
            end
            frac_diff = (mean2 - mean1) / mean1
            println("    fractional difference: $(frac_diff)")

            execute(comp_insert, [comparison_name, combo_id, pval, frac_diff, mean1, mean2, mad1, mad2, json(values1), json(values2)])
        end
    end

    # Construct time predicate part of WHERE clause
    year_start = 90
    year_end = 100
    time_predicate = "(time >= $(year_start) * 360) AND (time <= $(year_end) * 360)"

    do_comparison(
        "elapsed_time",
        "SELECT value FROM run_meta WHERE key = \"elapsed_time\" AND run_id = ?"
    )

    do_comparison(
        "max_rss_gb",
        "SELECT value FROM run_meta WHERE key = \"max_rss_gb\" AND run_id = ?"
    )

    do_comparison(
        "n_infected_active",
        "SELECT AVG(n_infected_active) FROM summary WHERE run_id = ? AND $(time_predicate)"
    )

    do_comparison(
        "n_infections_active",
        "SELECT AVG(n_infections_active) FROM summary WHERE run_id = ? AND $(time_predicate)"
    )

    do_comparison(
        "n_bites",
        "SELECT AVG(n_bites) FROM summary WHERE run_id = ? AND $(time_predicate)"
    )

    do_comparison(
        "n_circulating_genes_blood",
        "SELECT AVG(n_circulating_genes_blood) FROM gene_strain_counts WHERE run_id = ? AND $(time_predicate)"
    )

    do_comparison(
        "n_circulating_strains_blood",
        "SELECT AVG(n_circulating_genes_blood) FROM gene_strain_counts WHERE run_id = ? AND $(time_predicate)"
    )
end

main()
