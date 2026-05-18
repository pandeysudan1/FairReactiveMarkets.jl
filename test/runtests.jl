using Test
using LinearAlgebra
using Statistics

# Load only the pure-Julia modules (no MTK/JuMP deps needed for unit tests)
include("../src/hydro/turbine.jl")
include("../src/hydro/watervalue.jl")
include("../src/reactive/pricing.jl")
include("../src/reactive/voltage.jl")
include("../src/reactive/fairness.jl")
include("../src/fbmc/ptdf.jl")
include("../src/fbmc/ram.jl")
include("../src/fbmc/coupling.jl")
include("../src/policies/pfa.jl")
include("../src/policies/cfa.jl")
include("../src/policies/vfa.jl")

@testset "FairReactiveMarkets.jl" begin

    # ── Hydro ──────────────────────────────────────────────────────────────
    @testset "Hydropower generation" begin
        P = compute_generation(1.0, 1000.0, 9.81, 100.0, 100.0)
        @test P ≈ 98_100_000.0

        # η scales linearly
        @test compute_generation(0.5, 1000.0, 9.81, 100.0, 100.0) ≈ P / 2

        # zero flow → zero power
        @test compute_generation(0.92, 1000.0, 9.81, 120.0, 0.0) == 0.0
    end

    @testset "Water value" begin
        @test water_value(100.0, 100.0, 5.0) == 0.0
        @test water_value(110.0, 100.0, 5.0) ≈ 50.0
        @test water_value(90.0,  100.0, 5.0) ≈ -50.0
    end

    # ── Reactive ───────────────────────────────────────────────────────────
    @testset "Reactive pricing" begin
        @test reactive_price(42.0)  == 42.0
        @test reactive_price(-3.0)  == -3.0
        @test reactive_price(0.0)   == 0.0
    end

    @testset "Voltage deviation" begin
        @test voltage_deviation(1.0, 1.0)  == 0.0
        @test voltage_deviation(1.05, 1.0) ≈ 0.0025
        @test voltage_deviation(0.95, 1.0) ≈ 0.0025
    end

    @testset "Fairness metric" begin
        # Identical prices → zero variance
        @test fairness_metric([10.0, 10.0, 10.0]) ≈ 0.0 atol=1e-12

        # Known variance: [8,10,12] → mean=10, sum of sq dev = 4+0+4 = 8
        @test fairness_metric([8.0, 10.0, 12.0]) ≈ 8.0

        # Single element → zero
        @test fairness_metric([5.0]) ≈ 0.0 atol=1e-12
    end

    # ── FBMC ───────────────────────────────────────────────────────────────
    @testset "FBMC run_fbmc" begin
        PTDF = [0.4  0.2;
                0.1  0.5]
        NP   = [100.0; 50.0]
        RAM  = [80.0; 70.0]

        flows, viol = run_fbmc(PTDF, NP, RAM)

        @test flows ≈ [50.0; 35.0]
        @test viol  ≈ [-30.0; -35.0]   # both within limits (negative = slack)

        # Test that a violation is detected
        NP_high = [300.0; 200.0]
        _, viol2 = run_fbmc(PTDF, NP_high, RAM)
        @test any(viol2 .> 0)
    end

    @testset "RAM computation" begin
        @test compute_ram(1000.0, 100.0, 50.0) ≈ 850.0
        @test compute_ram(500.0, 0.0, 0.0)     ≈ 500.0
    end

    @testset "Zone coupling" begin
        PTDF  = [0.4  0.2; 0.1  0.5]
        zones = [1, 2]
        C     = zone_coupling(zones, PTDF)

        @test size(C) == (2, 2)
        @test C[1, 1] ≈ sum(abs.(PTDF[:, 1] .* PTDF[:, 1]))
        @test C[1, 2] ≈ C[2, 1]   # symmetric
    end

    # ── Policies ───────────────────────────────────────────────────────────
    @testset "PFA policy" begin
        p     = HydroPFA(0.8, 0.2, 0.1)
        state = (V = 100.0, price = 50.0, wind = 20.0)

        q = pfa_release(p, state)
        @test q ≈ 0.8*100.0 + 0.2*50.0 - 0.1*20.0   # = 88.0
        @test q ≈ 88.0
    end

    @testset "CFA policy" begin
        p     = HydroCFA(0.8, 0.2, 0.1, 1.0, 120.0)
        state = (V = 100.0, price = 50.0, wind = 20.0)

        q = cfa_release(p, state)
        # scarcity = 1.0*(120-100) = 20 → base 88 - 20 = 68
        @test q ≈ 68.0
        @test q >= 0.0

        # When V > V_ref, no scarcity penalty
        state_full = (V = 130.0, price = 50.0, wind = 20.0)
        q_full = cfa_release(p, state_full)
        @test q_full ≈ 0.8*130 + 0.2*50 - 0.1*20  # = 112
    end

    @testset "VFA policy" begin
        vfa   = HydroVFA([0.0, 50.0, 100.0, 150.0], [0.0, 200.0, 350.0, 400.0])
        state = (V = 100.0, price = 50.0, wind = 20.0)

        q_high = vfa_release(vfa, state, 999.0)   # very high price → release
        q_low  = vfa_release(vfa, state, 0.0)     # price below λ_water → no release

        @test q_high > 0.0
        @test q_low  == 0.0
    end

end
