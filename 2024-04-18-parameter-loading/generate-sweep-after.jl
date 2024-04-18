#!/usr/bin/env julia

println("(Annoying Julia compilation delay...)")

using Random
using SQLite
import SQLite.DBInterface.execute
using DelimitedFiles
import DataStructures.OrderedDict

# Get relevant paths and cd to the script path.
# NB: use actual relative locations of varmodel3 root relative to your script.

SCRIPT_PATH = abspath(dirname(PROGRAM_FILE))

#VERSION_SUFFIX = ARGS[1]
VERSION_SUFFIX = "after"
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

# Run 15 jobs at the same time
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
    execute(db, "CREATE TABLE param_combos (combo_id, biting_rate, immigration_rate_fraction, immunity_loss_rate, n_genes_initial, switching_rate_A, switching_rate_BC, ectopic_recombination_rate_A, ectopic_recombination_rate_BC, functionality_BC)")
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
    daily_biting_rate_multiplier = readdlm("mosquito_population.txt", Float64)[:,1]
    # validate(base_params)
    execute(db, "INSERT INTO meta VALUES (?, ?)", ("base_params", pretty_json(base_params)))

    # Construct parameter combinations
    combos = []

    # biting rate endpoints
    for biting_rate in (1e-5, 1e-4)
        push!(combos, (
            biting_rate = biting_rate,
            immigration_rate_fraction = 3e-4,
            immunity_loss_rate = 3e-4,
            n_genes_initial = 10000,
            switching_rate_A = 0.25,
            switching_rate_BC = 0.20,
            ectopic_recombination_rate_A = 2e-5,
            ectopic_recombination_rate_BC = 7e-4,
            functionality_BC = 0.4
        ))
    end

    # immigration rate endpoints
    for immigration_rate_fraction in (3e-4, 3e-2)
        push!(combos, (
            biting_rate = 1e-5,
            immigration_rate_fraction = immigration_rate_fraction,
            immunity_loss_rate = 3e-4,
            n_genes_initial = 10000,
            switching_rate_A = 0.25,
            switching_rate_BC = 0.20,
            ectopic_recombination_rate_A = 2e-5,
            ectopic_recombination_rate_BC = 7e-4,
            functionality_BC = 0.4
        ))
    end

    # immunity loss endpoints
    for immunity_loss_rate in (3e-4, 2e-3)
        push!(combos, (
            biting_rate = 1e-5,
            immigration_rate_fraction = 3e-4,
            immunity_loss_rate = immunity_loss_rate,
            n_genes_initial = 10000,
            switching_rate_A = 0.25,
            switching_rate_BC = 0.20,
            ectopic_recombination_rate_A = 2e-5,
            ectopic_recombination_rate_BC = 7e-4,
            functionality_BC = 0.4
        ))
    end

    # switching rate endpoints
    for switching_rate_A in (0.125, 0.25)
        push!(combos, (
            biting_rate = 1e-5,
            immigration_rate_fraction = 3e-4,
            immunity_loss_rate = 3e-4,
            n_genes_initial = 10000,
            switching_rate_A = switching_rate_A,
            switching_rate_BC = switching_rate_A * 0.8,
            ectopic_recombination_rate_A = 2e-5,
            ectopic_recombination_rate_BC = 7e-4,
            functionality_BC = 0.4
        ))
    end

    # ectopic recombination endpoints
    for ectopic_recombination_rate_A in (2e-5, 7e-4)
        push!(combos, (
            biting_rate = 1e-5,
            immigration_rate_fraction = 3e-4,
            immunity_loss_rate = 3e-4,
            n_genes_initial = 10000,
            switching_rate_A = 0.25,
            switching_rate_BC = 0.20,
            ectopic_recombination_rate_A = ectopic_recombination_rate_A,
            ectopic_recombination_rate_BC = ectopic_recombination_rate_A * 2.0,
            functionality_BC = 0.4
        ))
    end

    # functionality endpoints
    for functionality_BC in (0.4, 1.0)
        push!(combos, (
            biting_rate = 1e-5,
            immigration_rate_fraction = 3e-4,
            immunity_loss_rate = 3e-4,
            n_genes_initial = 10000,
            switching_rate_A = 0.25,
            switching_rate_BC = 0.20,
            ectopic_recombination_rate_A = 2e-5,
            ectopic_recombination_rate_BC = 7e-4,
            functionality_BC = functionality_BC
        ))
    end

    # Loop through parameter combinations and replicates, generating a run directory
    # `runs/c<combo_id>/r<replicate>` for each one.
    run_id = 1
    for (combo_id, combo_params) in enumerate(combos)
        println("Processing c$(combo_id)")

        execute(db, "INSERT INTO param_combos VALUES (?,?,?,?,?,?,?,?,?,?)", vcat([combo_id,], collect(combo_params)))

        for replicate in 1:N_REPLICATES
            rng_seed = rand(seed_rng, 1:typemax(Int64))
            params = Params(base_params)
            assign_fields!(params, (
                rng_seed = rng_seed,
                biting_rate = combo_params[:biting_rate] * daily_biting_rate_multiplier,
                immigration_rate_fraction = combo_params[:immigration_rate_fraction],
                immunity_loss_rate = combo_params[:immunity_loss_rate],
                n_genes_initial = combo_params[:n_genes_initial],
                switching_rate = [combo_params[:switching_rate_A], combo_params[:switching_rate_BC]],
                ectopic_recombination_rate = [combo_params[:ectopic_recombination_rate_A], combo_params[:ectopic_recombination_rate_BC]],
                var_groups_functionality = [1.0, combo_params[:functionality_BC]]
            ))
            validate(params)

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

    # Make one job for each parameter combo
    combo_ids = [combo_id for (combo_id,) in execute(db, "SELECT DISTINCT combo_id FROM runs ORDER BY combo_id")]
    for combo_id in combo_ids
        for (run_id, run_dir) in execute(db, "SELECT run_id, run_dir FROM runs WHERE combo_id = ? ORDER BY replicate", [combo_id])
            execute(db, "INSERT INTO job_runs VALUES (?,?)", (combo_id, run_id))
        end
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
    d = OrderedDict(fn => getfield(params, fn) for fn in fieldnames(typeof(params)))
    io = IOBuffer()
    JSON.print(io, d, 2)
    String(take!(io))
end

function init_base_params()
    t_year = 360
#     daily_biting_rate_multiplier = readdlm("../mosquito_population.txt", Float64)[:,1]

    t_end_years = 100
    t_end = t_end_years * t_year

    # Uncomment this, and argument to Params() below, to enable an intervention
    # for some subset of years.
#     biting_rate_multiplier_by_year = repeat([1.0], t_end_years)
#     biting_rate_multiplier_by_year[61:62] .= 0.5

    t_burnin_years = 0
    t_burnin = t_burnin_years * t_year

    params = Params()
    assign_fields!(params, (
        upper_bound_recomputation_period = 30,

        output_db_filename = "output.sqlite",

        summary_period = 360,
        gene_strain_count_period = 360,

        host_sampling_period = [],
        host_sample_size = 0,

        verification_period = t_end,

        sample_infection_duration_every = 1000000,

        rng_seed = nothing,
        whole_gene_immune = false,

        t_year = t_year,
        t_end = t_end,

        t_burnin = t_burnin,

        n_hosts = 2000,
        n_initial_infections = 20,

        n_genes_initial = 25000,
        n_genes_per_strain = 60,

        n_loci = 2,

        n_alleles_per_locus_initial = 2000, 

        transmissibility = 1.0,
        coinfection_reduces_transmission = true,

        # ectopic_recombination_rate = 1.8e-7,
#         ectopic_recombination_rate = [4.242641e-4, 4.242641e-4],
        ectopic_recombination_rate = [0.0, 0.0],
        p_ectopic_recombination_is_conversion = 0.0,

        ectopic_recombination_generates_new_alleles = true,
        p_ectopic_recombination_generates_new_allele = 0.2,

        rho_recombination_tolerance = 0.8,
        mean_n_mutations_per_epitope = 5.0,

        immunity_level_max = 100,
        immunity_loss_rate = 0.0,
#         immunity_loss_rate = 0.001,

        # mutation_rate = 0.0,
        mutation_rate = 1.42e-8,

        t_liver_stage = 14.0,

        switching_rate = [1.0/6.0, 1.0/6.0],
        # switching_rate = 1.0/6.0,

        mean_host_lifetime = 23.38837487739662,
        max_host_lifetime = nothing,

        background_clearance_rate = 0.0,
        immigration_rate_fraction = 0.0026,

        n_infections_liver_max = 20,
        n_infections_active_max = 20,

        # biting_rate = repeat([0.5], t_year),
        biting_rate_mean = nothing, # DOES NOTHING?
#         biting_rate = 0.00002 * daily_biting_rate_multiplier, # 0.0005

#         biting_rate_multiplier_by_year = biting_rate_multiplier_by_year,

        migrants_match_local_prevalence = false,
#         migrants_match_local_prevalence = true,
        migration_rate_update_period = 30,


        
        # parameters for var groups implementation
        var_groups_functionality = [1, 1],
        var_groups_ratio = [0.25, 0.75],
        var_groups_fix_ratio = true,
        var_groups_do_not_share_alleles = true,
        var_groups_high_functionality_express_earlier = true,
        gene_group_id_association_recomputation_period = 30,

        n_snps_per_strain = 0,
        snp_linkage_disequilibrium = false,
        
        # Profiling parameters
        profile_on = true,
        profile_delay = 0.01
    ))
    params
end

main()
