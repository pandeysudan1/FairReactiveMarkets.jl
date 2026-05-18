module FairReactiveMarkets

using ModelingToolkit
using DifferentialEquations
using JuMP
using Ipopt
using LinearAlgebra
using Statistics

include("hydro/reservoir.jl")
include("hydro/turbine.jl")
include("hydro/watervalue.jl")

include("reactive/pricing.jl")
include("reactive/voltage.jl")
include("reactive/fairness.jl")

include("fbmc/ptdf.jl")
include("fbmc/ram.jl")
include("fbmc/coupling.jl")

include("policies/pfa.jl")
include("policies/cfa.jl")
include("policies/vfa.jl")
include("policies/dla.jl")
include("policies/hybrid.jl")

include("optimization/acopf.jl")
include("optimization/market.jl")

include("digital_twin/realtime.jl")

export ReservoirSystem
export compute_generation
export water_value

export reactive_price
export voltage_deviation
export fairness_metric

export run_fbmc
export compute_ram
export zone_coupling

export HydroPFA, pfa_release
export HydroCFA, cfa_release
export HydroVFA, vfa_release
export HydroDLA, run_dla
export HybridPolicy, hybrid_release

export run_acopf
export run_market_clearing

export DigitalTwin, update_state!

end
