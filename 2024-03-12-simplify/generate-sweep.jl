#!/usr/bin/env julia

println("(Annoying Julia compilation delay...)")

using Random
using SQLite
import SQLite.DBInterface.execute
using DelimitedFiles

# Get relevant paths and cd to the script path.
# NB: use actual relative locations of varmodel3 root relative to your script.

SCRIPT_PATH = abspath(dirname(PROGRAM_FILE))

VERSION_SUFFIX = ARGS[1]
VARMODEL3_SUBPATH = "varmodel3-$(VERSION_SUFFIX)"
ROOT_PATH = abspath(joinpath(SCRIPT_PATH, VARMODEL3_SUBPATH))

include(joinpath(VARMODEL3_SUBPATH, "preamble.jl"))

ROOT_RUN_SCRIPT = joinpath(ROOT_PATH, "run.jl")
ROOT_RUNMANY_SCRIPT = joinpath(ROOT_PATH, "runmany.jl")

cd(SCRIPT_PATH)

OUTPUT_DIR = abspath("output")
OUTPUT_SUBDIR = joinpath(OUTPUT_DIR, VERSION_SUFFIX)
RUNS_DIR = joinpath(OUTPUT_SUBDIR, "runs")
JOBS_DIR = joinpath(OUTPUT_SUBDIR, "jobs")
SWEEP_DB_FILENAME = joinpath(OUTPUT_SUBDIR, "sweep_db.sqlite")

# Number of replicates for each parameter combination.
const N_REPLICATES = 15

# Number of jobs to generate (one machine with > 15 cores)
const N_JOBS_MAX = 1
const N_CORES_PER_JOB_MAX = 15

function main()
    if !ispath(OUTPUT_DIR)
        mkdir(OUTPUT_DIR)
    end

    if ispath(OUTPUT_SUBDIR)
        error("$(OUTPUT_SUBDIR) already exists; please move or delete.")
    end
    mkdir(OUTPUT_SUBDIR)

    # Root run & job directories
    mkdir(RUNS_DIR)
    mkdir(JOBS_DIR)

    # Database of experiment information.
    if ispath(SWEEP_DB_FILENAME)
        error("$(SWEEP_DB_FILENAME) already exists; please move or delete")
    end
    db = SQLite.DB(SWEEP_DB_FILENAME)
    execute(db, "CREATE TABLE meta (key, value)")
    execute(db, "CREATE TABLE param_combos (combo_id INTEGER)")
    execute(db, "CREATE TABLE runs (run_id INTEGER, combo_id INTEGER, replicate INTEGER, rng_seed INTEGER, run_dir TEXT, params TEXT)")
    execute(db, "CREATE TABLE jobs (job_id INTEGER, job_dir TEXT)")
    execute(db, "CREATE TABLE job_runs (job_id INTEGER, run_id INTEGER)")

    generate_runs(db)
    generate_jobs(db)
end

function generate_runs(db)
    # System random device used to generate seeds.
    seed_rng = RandomDevice()

    # Base parameter set, copied/modified for each combination/replicate.
    base_params = init_base_params()
    validate(base_params)
    execute(db, "INSERT INTO meta VALUES (?, ?)", ("base_params", pretty_json(base_params)))

    # Loop through parameter combinations and replicates, generating a run directory
    # `runs/c<combo_id>/r<replicate>` for each one.
    combo_id = 1
    run_id = 1
    begin # placeholder block for parameter combination loop
        println("Processing c$(combo_id)")

        execute(db, "INSERT INTO param_combos VALUES (?)", (combo_id,))

        for replicate in 1:N_REPLICATES
            rng_seed = rand(seed_rng, 1:typemax(Int64))
            params = Params(
                base_params;
                rng_seed = rng_seed,
            )

            run_dir = joinpath(RUNS_DIR, "c$(combo_id)", "r$(replicate)")
            @assert !ispath(run_dir)
            mkpath(run_dir)

            # Generate parameters file.
            params_json = pretty_json(params)
            open(joinpath(run_dir, "parameters.json"), "w") do f
                println(f, params_json)
            end

            # Generate shell script to perform a single run.
            run_script = joinpath(run_dir, "run.sh")
            open(run_script, "w") do f
                print(f, """
                #!/bin/sh

                cd `dirname \$0`
                julia --check-bounds=no -O3 $(ROOT_RUN_SCRIPT) parameters.json &> output.txt
                """)
            end
            run(`chmod +x $(run_script)`) # Make run script executable

            # Save all run info (including redundant stuff for reference) into DB.
            execute(db, "INSERT INTO runs VALUES (?, ?, ?, ?, ?, ?)", (run_id, combo_id, replicate, rng_seed, run_dir, params_json))

            run_id += 1
        end
        combo_id += 1
    end
end

function generate_jobs(db)
    println("Assigning runs to jobs...")

    # Assign runs to jobs (round-robin).
    job_id = 1
    for (run_id, run_dir) in execute(db, "SELECT run_id, run_dir FROM runs ORDER BY replicate, combo_id")
        execute(db, "INSERT INTO job_runs VALUES (?,?)", (job_id, run_id))

        # Mod-increment job ID.
        job_id = (job_id % N_JOBS_MAX) + 1
    end

    # Create job directories containing job scripts and script to submit all jobs.
    submit_filename = joinpath(OUTPUT_SUBDIR, "submit_jobs.sh")
    submit_file = open(submit_filename, "w")
    println(submit_file, """
    #!/bin/sh

    cd `dirname \$0`
    """)
    for (job_id,) in execute(db, "SELECT DISTINCT job_id FROM job_runs ORDER BY job_id")
        job_dir = joinpath(JOBS_DIR, "$(job_id)")
        mkpath(job_dir)

        # Get all run directories for this job.
        run_dirs = [run_dir for (run_dir,) in execute(db,
            """
            SELECT run_dir FROM job_runs, runs
            WHERE job_runs.job_id = ?
            AND runs.run_id = job_runs.run_id
            """,
            (job_id,)
        )]
        n_cores = min(length(run_dirs), N_CORES_PER_JOB_MAX)

        # Write out list of runs.
        open(joinpath(job_dir, "runs.txt"), "w") do f
            for run_dir in run_dirs
                run_script = joinpath(SCRIPT_PATH, run_dir, "run.sh")
                println(f, run_script)
            end
        end

        # Create job sbatch file.
        job_sbatch = joinpath(job_dir, "job.sbatch")
        open(job_sbatch, "w") do f
            print(f, """
            #!/bin/sh

            #SBATCH --account=pi-pascualmm
            #SBATCH --partition=broadwl

            #SBATCH --job-name=var-$(job_id)

            #SBATCH --tasks=1
            #SBATCH --cpus-per-task=$(n_cores)
            #SBATCH --mem-per-cpu=2000m
            #SBATCH --time=4:00:00

            #SBATCH --chdir=$(joinpath(SCRIPT_PATH, job_dir))
            #SBATCH --output=output.txt

            # Uncomment this to use the Midway-provided Julia:
            # module load julia

            cd $(job_dir)
            julia $(ROOT_RUNMANY_SCRIPT) $(n_cores) runs.txt
            """)
        end
        run(`chmod +x $(job_sbatch)`) # Make run script executable (for local testing)

        execute(db, "INSERT INTO jobs VALUES (?,?)", (job_id, job_dir,))
#         println(submit_file, "sbatch $(job_sbatch)")
        println(submit_file, job_sbatch) # Just run locally
    end
    close(submit_file)
    run(`chmod +x $(submit_filename)`) # Make submit script executable
end

function pretty_json(params)
    d = Dict(fn => getfield(params, fn) for fn in fieldnames(typeof(params)))
    io = IOBuffer()
    JSON.print(io, d, 2)
    String(take!(io))
end

function init_base_params()
    t_year = 360
#     daily_biting_rate_multiplier = readdlm("../mosquito_population.txt", Float64)[:,1]
    #snp_ld_matrix = readdlm("../pairwise_ld_coefficient_24snps.txt", Float64)

    t_end_years = 100
    t_end = t_end_years * t_year

    # Uncomment this, and argument to Params() below, to enable an intervention
    # for some subset of years.
#     biting_rate_multiplier_by_year = repeat([1.0], t_end_years)
#     biting_rate_multiplier_by_year[61:62] .= 0.5

    t_burnin_years = 0
    t_burnin = t_burnin_years * t_year

    # Use adjusted mean host lifetime to match effective mean for old truncated parameters
    mean_host_lifetime = t_year * (
        if VERSION_SUFFIX == "after"
            23.38837487739662
        else
            30.0
        end
    )

    max_host_lifetime = if VERSION_SUFFIX == "after"
        nothing
    else
        80.0 * t_year
    end

    Params(
        upper_bound_recomputation_period = 30,

        output_db_filename = "output.sqlite",

        summary_period = 30,
        gene_strain_count_period = t_year,

        host_sampling_period = [],
        host_sample_size = 100,

        verification_period = t_end,

        sample_infection_duration_every = 1000,

        rng_seed = nothing,
        whole_gene_immune = false,

        t_year = t_year,
        t_end = t_end,

        t_burnin = t_burnin,

        n_hosts = 2000,
        n_initial_infections = 20,

        n_genes_initial = 1200,
        n_genes_per_strain = 60,

        n_loci = 2,

        n_alleles_per_locus_initial = 960, 

        transmissibility = 0.5,
        coinfection_reduces_transmission = true,

        # ectopic_recombination_rate = 1.8e-7,
#         ectopic_recombination_rate = [4.242641e-4, 4.242641e-4],
        ectopic_recombination_rate = [0.0, 0.0],
        p_ectopic_recombination_is_conversion = 0.0,

        ectopic_recombination_generates_new_alleles = false,

#         ectopic_recombination_generates_new_alleles = true,
#         p_ectopic_recombination_generates_new_allele = 0.5,

        rho_recombination_tolerance = 0.8,
        mean_n_mutations_per_epitope = 5.0,

        immunity_level_max = 100,
        immunity_loss_rate = 0.0,
#         immunity_loss_rate = 0.001,

        mutation_rate = 0.0,
#         mutation_rate = 1.42e-8,

        t_liver_stage = 14.0,

        switching_rate = [1.0/6.0, 1.0/6.0],
        # switching_rate = 1.0/6.0,

        mean_host_lifetime = mean_host_lifetime,
        max_host_lifetime = max_host_lifetime,

        background_clearance_rate = 0.0,
        immigration_rate_fraction = 0.0026,

        n_infections_liver_max = 20,
        n_infections_active_max = 20,

        biting_rate = repeat([0.5], t_year),
        biting_rate_mean = 0.01, # DOES NOTHING???
#         biting_rate = 0.00002 * daily_biting_rate_multiplier, # 0.0005

#         biting_rate_multiplier_by_year = biting_rate_multiplier_by_year,

        migrants_match_local_prevalence = false,
#         migrants_match_local_prevalence = true,
        migration_rate_update_period = 30,

        n_snps_per_strain = 0,

        distinct_initial_snp_allele_frequencies = false,
#         distinct_initial_snp_allele_frequencies = true,
#         initial_snp_allele_frequency = [0.1, 0.9],

        snp_linkage_disequilibrium = false,
#         snp_linkage_disequilibrium = true,
#         snp_pairwise_ld = [snp_ld_matrix[:,i] for i in 1:size(snp_ld_matrix)[2]],


        
        # parameters for var groups implementation
        var_groups_functionality = [1, 1],
        var_groups_ratio = [0.25, 0.75],
        var_groups_fix_ratio = true,
        var_groups_do_not_share_alleles = true,
        var_groups_high_functionality_express_earlier = true,
        gene_group_id_association_recomputation_period = 30,
        
        # Profiling parameters
        profile_on = true,
    )
end

main()
