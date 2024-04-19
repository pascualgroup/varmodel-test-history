# Statistical regression test history for varmodel3

This is an auxiliary repository for [https://github.com/pascualgroup/varmodel3](varmodel3) containing a recent history (as of 2024-04-19) of changes to the repository, which roughly align with merged pull requests, along with scripts to compare each change to a previous version using the [https://wikipedia.org/wiki/Kolmogorov-Smirnov_test](Kolmogorov-Smirnov test) run across multiple parameter sets.
The comparison results are also stored in the repository, in SQLite format.

To fully automate this approach, these tests could be integrated into the testing phase of a continuous integration system (e.g., GitHub Actions)—so that every push caused all tests to get run in the cloud—but that would require a bit more organizational structure and ongoing support.


## Organization

Each directory named with a date and tag (e.g., `2024-04-18-parameter-loading`) contains scripts needed to perform the following steps:

1. Clone the "before" and "after" versions of the repository into `varmodel3-before` and `varmodel3-after` subdirectories (`clone-versions.sh`)
2. Generate parameter sweep scripts (`generate-sweep.jl` or `generate-sweep-{before|after}.jl`) and run the sweeps locally (`run-sweeps.sh`)
3. Gather output for parameter sweeps into one SQLite database for each version of the code (`gather-output.jl`)
4. Compare the output using the two-sample Kolmogorov-Smirnov test applied to multiple metrics (`compare.jl`)

It is intentional that *every directory contains its own copy of the scripts*.
This is to ensure that old tests can be re-run without modification, and test-specific modifications can be made to the scripts to account for exceptional circumstances.

The `example` directory contains the most recent version of the scripts as of 2024-04-19, and contains an additional script to perform all steps sequentially: `run-everything.sh`.

## Testing a New Change

### 1. Set up the "before" and "after" working copies:

To test a new change to the code, clone the repository (or use an existing clone) and copy the `example` directory or a more recent version of the scripts:

```sh
git clone git@github.com:pascualgroup/varmodel-test-history
cd varmodel-test-history
cp -r example 2024-04-19-example
```

Next, clone the `varmodel3` repository and checkout the "before" version of the code:

```sh
git clone git@github.com:pascualgroup/varmodel3 varmodel3-before
cd varmodel3-before

# If your "before" is the current commit on the `main` branch, do nothing, i.e.,
git checkout main

# If your "before" is the latest commit on some other branch, e.g.:
git checkout test-example-before # This is an actual branch you can try

# If you want to create a new "before" branch, e.g., to add some output code
# that needs to be present in both versions of the code, e.g.:
git checkout -b 2024-04-19-example-before

# If your "before" is an existing arbitrary git commit, e.g.:
git checkout a231dd080e57bb96a7bc54159f10a332c99ef8ec

cd ..
```

Finally, clone repository again and checkout the "after" version of the code:

```sh
git clone git@github.com:pascualgroup/varmodel3 varmodel3-after
cd varmodel3-after

# If your "after" is the latest commit on an existing branch, e.g.:
git checkout test-example-after # This is an actual branch that is slower than test-example-before

# If you want to create a new "after" branch to add changes, e.g.:
git checkout <branch, tag, or commit to start from>
git checkout -b 2024-04-19-example-after

# If your "after" is an existing arbitrary git commit, e.g.:
git checkout a231dd080e57bb96a7bc54159f10a332c99ef8ec

cd ..
```

### 2. Make changes to the code

You can repeatedly run the test scripts before committing as you go, but, to simplify, we'll assume here that you make and commit the changes before running the test scripts.

If you need to add some missing measurement code to `before`, do that like so:

```sh
cd varmodel3-before
# [make some changes]
# [git add the changes]
git commit -m "Added code to output number of chickens per square mile over time"
git config push.autoSetupRemote true # if needed
git push
cd ..
```

Do the same thing with the `after` code:

```sh
cd varmodel3-after
# [make some changes]
# [git add the changes]
git commit -m "Refactored chicken density diffusion equation code for clarity"
git config push.autoSetupRemote true # if needed
git push
cd ..
```

### 3. Set up the tests

If you need to, modify `generate-sweep.jl` to cover the parameter sets that you need to cover.

Note that performance profiling is *off* in this example.
If you want to gather profiling data for each run in order to identify slow parts of the code, uncomment and set `profile_delay` to the delay in seconds between samples, chosen to avoid producing too many stack traces.

```jl
        profile_on = true,
        profile_delay = 0.01
```

By default, the script is set up to do 15 replicates per parameter combination and run them all on the same machine in parallel, which makes the assumption that there are 15 physical cores available.
If this is not true, modify the script accordingly:

```sh
const N_REPLICATES = 15
# ...
const N_CORES_PER_JOB_MAX = 15
```

If you need separate sweep scripts for the "before" and "after" versions of the code, make two files `generate-sweep-before.jl` and `generate-sweep-after.jl`, hardcode `VERSION_SUFFIX` near the top of the script, e.g.:

```jl
VERSION_SUFFIX = "after"
#VERSION_SUFFIX = "before"
```

and modify `generate-sweeps.sh` to use the version-specific sweep scripts:

```sh
# ./generate-sweep.jl before
./generate-sweep-before.jl

# ./generate-sweep.jl after
./generate-sweep-after.jl 
```

Finally, if you need to add comparisons, make changes to `compare.jl`.


### 4. Run the tests

The script `run-everything.sh` generates directories for the parameter sweeps, runs the parameter sweeps (locally), gathers all output into individual directories, and compares the code using Kolmogorov-Smirnov:

```sh
#!/bin/sh

# Uncomment this if you want to clone the code from scratch too
# ./clone-versions.sh

./generate-sweep.jl before
#./generate-sweep-before.jl

./generate-sweep.jl after
#./generate-sweep-after.jl 

./output/before/submit_jobs.sh
./gather-output.jl output/before

./output/after/submit_jobs.sh
./gather-output.jl output/after

./compare.jl
```

You can re-run just the `after` jobs via `run-after-only.sh`:

```sh
rm -r output/after
rm compare.sqlite
./run-after-only.sh
```

The sweep scripts were originally designed for the U of C cluster in a complicated way (to avoid exceeding job limits by batching runs together into jobs).
The code to perform runs individually on a SLURM cluster is still present and could be reactivated.
But it's easier to just run the whole script on a single cluster node (or on a multicore laptop or desktop) if you aren't in a hurry.

The `compare.jl` script writes output to the console and also creates a SQLite file containing comparison results in a single table:

```sql
CREATE TABLE comparisons (
    comparison_name,    # Name of the comparison, as specified in calls to `do_comparison()`
    combo_id,           # Combo ID, as created in sweep script
    ks_pvalue,          # P-value for Kolmogorov-Smirnov test. Small numbers indicate a CHANGE
    frac_diff,          # Fractional difference in means (mean_after - mean_before) / mean_before
    mean1, mean2,       # Means
    mad1, mad2,         # Mean absolute differences
    values1, values2    # Raw sample values as JSON arrays
)
```

The `values1` and `values2` column are not present in old tests but may be useful in the future in order to make comparisons with old results without re-running any simulations.
(At the time of writing these values are not used by any of the scripts.)


### Commit the test scripts and results

If there is a regression in performance or a change in behavior, it is a good idea to commit the completed test so the history is saved in the repository.

Once the performance or behavior problem is fixed, you will of course want to commit a final version of the test scripts/code/results.

To finalize the test, first make sure you have *committed and pushed* any changes inside `varmodel3-before` and `varmodel3-after`.

Then, record the *specific active commit in those working directories* via:

```sh
./record-commits.sh
```

This will save the git commit ID into `commit-before.txt` and `commit-after.txt`.

Finally, commit (and push) everything in this directory except the `output` directory and the working copies `varmodel3-{before|after}`, which are used only transiently:

```sh
git add *.jl *.txt *.sh compare.sqlite
git commit -m "Test result for example slowdown"
git push
```

### Re-running the tests

To re-run a test from a clean copy from GitHub, you can do:

```sh
git clone git@github.com:pascualgroup/varmodel-test-history # if needed
cd 2024-04-19-example
rm compare.sqlite
./clone-versions.sh # Clones varmodel3-before varmodel3-after using versions in commit-before.txt and commit-after.txt
./run-everything.sh
```
