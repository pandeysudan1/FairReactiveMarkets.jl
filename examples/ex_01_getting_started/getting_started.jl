# ============================================================================
# Example 01 — Getting Started with FairReactiveMarkets.jl
#
# USN Postdoctoral position #300665:
#   "Fair and Effective Pricing Model for Reactive Power
#    in Electricity Market"
#
# Research question:
#   How can Nordic hydropower flexibility be optimally coordinated to
#   provide fair reactive power compensation while respecting FBMC
#   congestion constraints under uncertainty?
#
# This script walks through the four core modules in ~60 lines of code.
# No external solver or package installation is needed for Steps 1–3.
# Step 4 (DLA) requires JuMP + Ipopt if run via the full package.
# ============================================================================

using Statistics

# Load pure-Julia modules directly so the script is self-contained
# (no need to Pkg.add anything beyond stdlib).
_src = joinpath(@__DIR__, "..", "..", "src")
include(joinpath(_src, "hydro",    "turbine.jl"))
include(joinpath(_src, "hydro",    "watervalue.jl"))
include(joinpath(_src, "reactive", "pricing.jl"))
include(joinpath(_src, "reactive", "voltage.jl"))
include(joinpath(_src, "reactive", "fairness.jl"))
include(joinpath(_src, "fbmc",     "ptdf.jl"))
include(joinpath(_src, "fbmc",     "ram.jl"))
include(joinpath(_src, "policies", "pfa.jl"))
include(joinpath(_src, "policies", "cfa.jl"))
include(joinpath(_src, "policies", "vfa.jl"))

println("=" ^ 60)
println("FairReactiveMarkets.jl — Getting Started")
println("USN Postdoc #300665 · Nordic Reactive Power Pricing")
println("=" ^ 60)

# ── Step 1: Hydropower Generation ───────────────────────────────────────────
println("\n=== Step 1: Hydropower Generation (NO2 reservoir) ===")

η    = 0.92          # turbine efficiency
ρ    = 1000.0        # water density [kg/m³]
g    = 9.81          # gravity [m/s²]
H    = 120.0         # net head [m]
Q    = 200.0         # turbine flow [m³/s]

P_W  = compute_generation(η, ρ, g, H, Q)   # watts
P_MW = P_W / 1e6

println("  Turbine flow Q  = $Q m³/s")
println("  Net head H      = $H m")
println("  Generation P    = $(round(P_MW, digits=3)) MW")

# ── Step 2: Reactive Pricing & Fairness ─────────────────────────────────────
println("\n=== Step 2: Reactive Pricing & Fairness ===")

# Dual variables (Lagrange multipliers) from a hypothetical OPF solution
# for three Norwegian hydro generators: Tonstad, Sima, Aurland.
λQ_dual = [10.0, 12.0, 8.0]   # €/MVAr
names   = ["Tonstad", "Sima", "Aurland"]

for (i, name) in enumerate(names)
    price = reactive_price(λQ_dual[i])
    println("  $(rpad(name, 8)) λQ = $(price) €/MVAr")
end

F    = fairness_metric(λQ_dual)
λ̄    = mean(λQ_dual)
println("  ─────────────────────────────")
println("  Mean price         λ̄  = $λ̄ €/MVAr")
println("  Fairness metric    F  = $F  (variance; lower = fairer)")

if F > 0
    println("  → Price spread detected — compensation is not yet equitable.")
    println("    Target: redesign policy to drive F → 0.")
end

# Voltage deviation check (per-unit)
V_measured = 1.03   # measured bus voltage [pu]
V_ref      = 1.0
dV         = voltage_deviation(V_measured, V_ref)
println("  Bus voltage        V  = $V_measured pu  (deviation² = $dV)")

# ── Step 3: FBMC Congestion Check ───────────────────────────────────────────
println("\n=== Step 3: FBMC Congestion — NO2 / SE3 / DK1 corridor ===")

# Simplified 2-line, 2-zone PTDF for the NO2→SE3→DK1 corridor.
# Row = line (NO2–SE3, SE3–DK1), Col = zone (NO2, DK1).
PTDF = [0.4  0.2;    # line 1: NO2–SE3
        0.1  0.5]    # line 2: SE3–DK1

# Net positions [MW]: NO2 exports 100 MW, DK1 imports 50 MW
NP   = [100.0; 50.0]

# Remaining Available Margins [MW]
RAM  = [compute_ram(200.0, 80.0, 40.0);    # line 1: NTC=200, FRM=80, FAV=40
        compute_ram(150.0, 50.0, 30.0)]    # line 2: NTC=150, FRM=50, FAV=30

flows, violations = run_fbmc(PTDF, NP, RAM)

line_names = ["NO2–SE3", "SE3–DK1"]
for (i, lname) in enumerate(line_names)
    status = violations[i] <= 0 ? "✓ within limit" : "✗ VIOLATED"
    println("  $(rpad(lname, 8))  flow=$(round(flows[i],digits=1)) MW  " *
            "RAM=$(round(RAM[i],digits=1)) MW   $status")
end

if any(violations .> 0)
    println("  → Congestion detected — reduce NP or re-dispatch reactive support.")
else
    println("  → No congestion. FBMC constraints satisfied.")
end

# ── Step 4: Policy Comparison ────────────────────────────────────────────────
println("\n=== Step 4: Sequential Decision Policy Comparison ===")

# Current system state
state = (
    V     = 100.0,   # reservoir level [Mm³]
    price = 50.0,    # spot price [€/MWh]
    wind  = 20.0     # wind generation [MW]
)

println("  State: V=$(state.V) Mm³  price=$(state.price) €/MWh  wind=$(state.wind) MW")
println()

# 4a. PFA — Parametric Function Approximation (heuristic affine rule)
pfa = HydroPFA(0.8, 0.2, 0.1)
q_pfa = pfa_release(pfa, state)
println("  PFA  (affine rule)          Q = $(round(q_pfa, digits=1)) m³/s")
println("       θ = [$(pfa.θ1), $(pfa.θ2), $(pfa.θ3)]  →  fastest, no future info")

# 4b. CFA — Cost Function Approximation (scarcity-aware)
cfa = HydroCFA(0.8, 0.2, 0.1, 1.0, 120.0)
q_cfa = cfa_release(cfa, state)
println("  CFA  (scarcity penalty)     Q = $(round(q_cfa, digits=1)) m³/s")
println("       V_ref=$(cfa.V_ref) Mm³: conserves water when reservoir is low")

# 4c. VFA — Value Function Approximation (learned water value)
#   Piecewise-linear Ṽ(V) calibrated to a stylised price-duration curve.
vfa = HydroVFA(
    [0.0,  50.0, 100.0, 150.0],     # reservoir breakpoints [Mm³]
    [0.0, 200.0, 350.0, 400.0]      # Ṽ(V) [€ × 10³]
)
q_vfa = vfa_release(vfa, state, state.price)
println("  VFA  (learned value fn)     Q = $(round(q_vfa, digits=1)) m³/s")
println("       releases only when market price ≥ marginal water value")

# 4d. DLA requires JuMP/Ipopt — shown as pseudo-result if deps not loaded
println("  DLA  (rolling optimisation) → run `include(src/policies/dla.jl)`")
println("       then: run_dla(HydroDLA(500.0, 100.0, 0.01))")

println()
println("─" ^ 60)
println("Policy summary:")
println("  Policy  Release     Requires future info?  Complexity")
println("  PFA     $(rpad(round(q_pfa,digits=1),10))  No                     Low")
println("  CFA     $(rpad(round(q_cfa,digits=1),10))  Partial (V_ref)        Low")
println("  VFA     $(rpad(round(q_vfa,digits=1),10))  Yes (offline training) Medium")
println("  DLA     rolling opt  Yes (rolling horizon)  High")

# ── Research Question Answer ─────────────────────────────────────────────────
println()
println("=" ^ 60)
println("Research Question: Can Nordic hydropower provide FAIR reactive")
println("compensation under FBMC constraints?")
println()
println("  This example shows:")
println("  1. Hydropower CAN generate $(round(P_MW,digits=1)) MW of active power")
println("     — but reactive pricing fairness (F=$F) is non-zero.")
println("  2. FBMC constraints are currently satisfied (no congestion),")
println("     giving headroom for coordinated reactive dispatch.")
println("  3. Policy choice matters: PFA releases $(round(q_pfa,digits=1)) m³/s")
println("     vs CFA $(round(q_cfa,digits=1)) m³/s — a $(round(q_pfa-q_cfa,digits=1)) m³/s gap")
println("     driven purely by scarcity-awareness.")
println("  → Full answer requires stochastic simulation over uncertainty")
println("    (wind, prices) — see ex_02 for the scenario tree extension.")
println("=" ^ 60)
