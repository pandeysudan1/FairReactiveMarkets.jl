# ============================================================================
# Example 02 — Stochastic Wind Scenarios & Policy Robustness
#
# Sub-question: How does wind uncertainty propagate to reactive pricing
# fairness, and which policy is most robust across a scenario tree?
# ============================================================================

using Statistics
_src = joinpath(@__DIR__, "..", "..", "src")
include(joinpath(_src, "hydro",    "turbine.jl"))
include(joinpath(_src, "reactive", "fairness.jl"))
include(joinpath(_src, "reactive", "pricing.jl"))
include(joinpath(_src, "fbmc",     "ptdf.jl"))
include(joinpath(_src, "fbmc",     "ram.jl"))
include(joinpath(_src, "policies", "pfa.jl"))
include(joinpath(_src, "policies", "cfa.jl"))
include(joinpath(_src, "policies", "vfa.jl"))
include(joinpath(@__DIR__, "..", "plot_helpers.jl"))

println("=" ^ 65)
println("Example 02 — Stochastic Wind Scenarios & Policy Robustness")
println("=" ^ 65)

# ── Scenario tree definition ─────────────────────────────────────────────────
scenarios = (
    names  = ["ω₁ Low", "ω₂ Mid", "ω₃ High"],
    wind   = [5.0,       20.0,      45.0],    # MW
    prob   = [0.3,        0.4,       0.3],
    price  = [55.0,       50.0,      42.0],   # price inversely correlated with wind
)

# Base reservoir state (here-and-now, shared across scenarios)
V_base = 100.0   # Mm³

println("\n--- Scenario Tree ---")
text_table(
    ["Scenario", "Wind [MW]", "Prob", "Price [€/MWh]"],
    [[scenarios.names[i], scenarios.wind[i], scenarios.prob[i], scenarios.price[i]]
     for i in 1:3];
    title = "Wind Scenario Parameterisation"
)

# ── Policy definitions ────────────────────────────────────────────────────────
pfa = HydroPFA(0.8, 0.2, 0.1)
cfa = HydroCFA(0.8, 0.2, 0.1, 1.0, 120.0)
vfa = HydroVFA([0.0, 50.0, 100.0, 150.0], [0.0, 200.0, 350.0, 400.0])

# ── Simulate each scenario × policy ──────────────────────────────────────────
function reactive_prices_from_release(Q, wind)
    # Simplified: reactive price proportional to (Q_demand / Q_available)
    # Three generators: Tonstad, Sima, Aurland
    Q_demand = [30.0 + 0.3*wind, 25.0 + 0.2*wind, 20.0 + 0.1*wind]
    Q_avail  = [Q * 0.4,          Q * 0.35,         Q * 0.25]
    λQ = [reactive_price(max(1.0, 8.0 * Q_demand[i] / max(Q_avail[i], 1.0)))
          for i in 1:3]
    return λQ
end

results = []
for (i, sc) in enumerate(scenarios.names)
    state = (V = V_base, price = scenarios.price[i], wind = scenarios.wind[i])
    q_pfa = pfa_release(pfa, state)
    q_cfa = cfa_release(cfa, state)
    q_vfa = vfa_release(vfa, state, state.price)

    for (pname, q) in [("PFA", q_pfa), ("CFA", q_cfa), ("VFA", q_vfa)]
        λQ = reactive_prices_from_release(q, scenarios.wind[i])
        F  = fairness_metric(λQ)
        rev = q * scenarios.price[i] * 0.1    # simplified revenue proxy
        push!(results, (sc=sc, policy=pname, Q=round(q,digits=1),
                        F=round(F,digits=2), rev=round(rev,digits=1),
                        prob=scenarios.prob[i], λQ=λQ))
    end
end

# ── Table: scenario outcomes ──────────────────────────────────────────────────
println("\n--- Scenario × Policy Dispatch ---")
text_table(
    ["Scenario", "Policy", "Q [m³/s]", "F (fairness)", "Revenue [€]"],
    [[r.sc, r.policy, r.Q, r.F, r.rev] for r in results];
    title = "Dispatch and Fairness per Scenario"
)

# ── Expected metrics per policy ───────────────────────────────────────────────
println("\n--- Expected Metrics (probability-weighted) ---")
policies = ["PFA", "CFA", "VFA"]
E_F   = Dict{String,Float64}()
E_rev = Dict{String,Float64}()

for p in policies
    rs = filter(r -> r.policy == p, results)
    E_F[p]   = sum(r.F   * r.prob for r in rs)
    E_rev[p] = sum(r.rev * r.prob for r in rs)
end

bar_chart(policies, [E_F[p] for p in policies];
    title="Expected Fairness E[F]  (lower = fairer)", unit="€²/MVAr²")
bar_chart(policies, [E_rev[p] for p in policies];
    title="Expected Revenue E[Rev]", unit="€")

# ── CVaR of fairness (worst scenario) ─────────────────────────────────────────
println("\n--- CVaR₀.₉ of Fairness (tail risk) ---")
cvar = Dict{String,Float64}()
for p in policies
    rs      = filter(r -> r.policy == p, results)
    fs      = sort([r.F for r in rs]; rev=true)
    cvar[p] = fs[1]   # worst single scenario (3-scenario tree)
end

bar_chart(policies, [cvar[p] for p in policies];
    title="CVaR₀.₉[F] — worst-case fairness per policy", unit="€²/MVAr²")

# ── FBMC check across scenarios ───────────────────────────────────────────────
println("\n--- FBMC Feasibility Across Scenarios ---")
PTDF = [0.4  0.2; 0.1  0.5]
RAM  = [compute_ram(200.0, 80.0, 40.0); compute_ram(150.0, 50.0, 30.0)]
println("  RAM: line 1 = $(RAM[1]) MW,  line 2 = $(RAM[2]) MW")

any_viol = false
for (i, sc) in enumerate(scenarios.names)
    NP     = [100.0 + scenarios.wind[i]; 50.0]
    flows, viol = run_fbmc(PTDF, NP, RAM)
    status = all(viol .<= 0) ? "✓ feasible" : "✗ VIOLATED"
    println("  $sc: flows = $(round.(flows,digits=1)) MW   $status")
    global any_viol = any_viol || any(viol .> 0)
end
println(any_viol ? "\n  ⚠ FBMC violations exist!" :
                   "\n  All scenarios FBMC-feasible.")

# ── Summary table ─────────────────────────────────────────────────────────────
println("\n--- Summary ---")
best_F    = policies[argmin([E_F[p]   for p in policies])]
best_rev  = policies[argmax([E_rev[p] for p in policies])]

text_table(
    ["Policy", "E[F]", "CVaR[F]", "E[Rev €]", "Fairness winner?", "Revenue winner?"],
    [[p,
      round(E_F[p],   digits=2),
      round(cvar[p],  digits=2),
      round(E_rev[p], digits=1),
      p == best_F   ? "✓ Fairest"    : "—",
      p == best_rev ? "✓ Highest Rev" : "—"]
     for p in policies];
    title = "Policy Comparison (3-scenario wind tree)"
)

println("\n→ Best fairness (lowest E[F]):  $best_F")
println("  Best revenue (highest E[Rev]): $best_rev")
println("  Note: fairness and revenue trade off — VFA conserves water,")
println("  concentrating reactive demand; PFA dispatches more, spreading Q.")
println("  The optimal policy depends on the regulator's fairness weight.")
