# ============================================================================
# Example 04 — VFA Policy Training via Regression (ADP / LSPE)
#
# Sub-question: Can a VFA trained on simulated transitions outperform
# heuristic PFA in long-run revenue and reactive pricing fairness?
#
# All units normalised: V ∈ [0,1], price ∈ [0,1], reward ∈ ℝ (small)
# ============================================================================

using Statistics, LinearAlgebra, Random

_src = joinpath(@__DIR__, "..", "..", "src")
include(joinpath(_src, "hydro",    "turbine.jl"))
include(joinpath(_src, "reactive", "fairness.jl"))
include(joinpath(_src, "policies", "pfa.jl"))
include(joinpath(@__DIR__, "..", "plot_helpers.jl"))

Random.seed!(42)

println("=" ^ 65)
println("Example 04 — VFA Policy Training (LSPE / Regression ADP)")
println("=" ^ 65)

# ── Physical parameters ───────────────────────────────────────────────────────
const η = 0.92; const ρ = 1000.0; const g = 9.81; const H = 120.0
const V_MAX  = 150.0   # Mm³
const Q_MAX  = 300.0   # m³/s
const P_REF  = compute_generation(η, ρ, g, H, Q_MAX) / 1e6   # MW at full flow
const γ      = 0.95    # discount factor
const T_SIM  = 100     # periods per episode
const N_ITER = 50      # training iterations

# ── Stochastic environment ────────────────────────────────────────────────────
function sample_inflow()  clamp(50.0 + 30.0 * randn(), 0.0, 120.0) end
function sample_price()   clamp(50.0 + 20.0 * randn(), 5.0, 150.0) end
function sample_wind()    clamp(20.0 + 15.0 * randn(), 0.0,  80.0) end

function transition(V, Q, Qin, dt = 1.0)
    V_new = V + (Qin - Q) * dt
    spill = max(0.0, V_new - V_MAX)
    clamp(V_new - spill, 0.0, V_MAX)
end

# Reward: revenue in k€ (keeps θ values O(1)) minus small fairness penalty
function compute_reward(Q, price, wind)
    P_MW   = compute_generation(η, ρ, g, H, Q) / 1e6
    rev_k€ = price * P_MW / 1e3
    Qd     = [30.0 + 0.3*wind, 25.0 + 0.2*wind, 20.0 + 0.1*wind]
    qa     = [Q*0.40, Q*0.35, Q*0.25]
    λQ     = [max(1.0, 8.0 * Qd[i] / max(qa[i], 1.0)) for i in 1:3]
    F      = fairness_metric(λQ)
    return rev_k€ - 1e-4 * F, F
end

# ── Basis functions (normalised inputs → O(1) outputs) ────────────────────────
function basis(V, price)
    v = V / V_MAX
    p = price / 100.0
    [1.0, v, v^2, p, v * p]
end

n_θ = 5
θ   = [0.0, 1.0, 0.0, 0.1, 0.0]   # warm-start: linear water value

vfa_eval(V, price) = dot(basis(V, price), θ)

# ── VFA policy: release if marginal revenue ≥ marginal opportunity cost ────────
function vfa_Q(V, price)
    # Marginal water value in k€ per Mm³ (derivative of Ṽ w.r.t. V)
    v_n  = V / V_MAX
    p_n  = price / 100.0
    # ∂Ṽ/∂v_n = θ₂ + 2θ₃v_n + θ₅p_n;  ∂Ṽ/∂V = (∂Ṽ/∂v_n) / V_MAX
    dVdV = (θ[2] + 2*θ[3]*v_n + θ[5]*p_n) / V_MAX   # k€ per Mm³
    # Revenue rate: price [€/MWh] × P_REF [MW] / Q_MAX [m³/s] / 1e3 [→k€]
    # per unit of flow = price × P_REF / (Q_MAX × 1000) k€/(m³/s)
    rev_rate = price * P_REF / (Q_MAX * 1000.0)  # k€ per m³/s per period
    # Release fraction proportional to price advantage over opportunity cost
    opp_cost = γ * dVdV  # k€ per Mm³ (normalise to flow later)
    ratio    = rev_rate > 0 ? clamp(1.0 - opp_cost / rev_rate, 0.0, 1.0) : 0.0
    return Q_MAX * ratio
end

# ── Simulate one episode ───────────────────────────────────────────────────────
function simulate(policy_fn; collect_transitions = false)
    V    = 0.6 * V_MAX   # start at 60% full
    rev  = 0.0
    Fs   = Float64[]
    trans = []
    for t in 1:T_SIM
        price = sample_price()
        wind  = sample_wind()
        Qin   = sample_inflow()
        Q     = clamp(policy_fn(V, price), 0.0, min(Q_MAX, V))
        r, F  = compute_reward(Q, price, wind)
        V_new = transition(V, Q, Qin)
        collect_transitions && push!(trans, (V=V, price=price, r=r, V_new=V_new,
                                             price_new=sample_price()))
        push!(Fs, F)
        rev  += r * γ^(t-1)
        V     = V_new
    end
    return trans, rev, mean(Fs)
end

# ── LSPE training loop ─────────────────────────────────────────────────────────
println("\n--- Training VFA via Least-Squares Policy Evaluation ---")
println("  Iter │ VFA Rev [k€] │ Mean F │ θ₁ (water val) │ θ₂ (concavity)")
println("  " * "─"^62)

revenues_vfa = Float64[]
fairness_vfa = Float64[]

for iter in 1:N_ITER
    trans, rev, mF = simulate(vfa_Q; collect_transitions = true)
    push!(revenues_vfa, rev)
    push!(fairness_vfa, mF)

    # LSPE regression: θ* = (ΦᵀΦ + λI)⁻¹ Φᵀ b
    n  = length(trans)
    Φ  = reduce(vcat, [basis(t.V, t.price)' for t in trans])
    b  = [t.r + γ * vfa_eval(t.V_new, t.price_new) for t in trans]
    θ .= (Φ'Φ + 1e-3 * I) \ (Φ' * b)

    if mod(iter, 10) == 0 || iter == 1
        println("  $(lpad(iter,4)) │ $(lpad(round(rev,digits=2),12)) │ " *
                "$(lpad(round(mF,digits=2),6)) │ " *
                "$(lpad(round(θ[2],digits=4),14)) │ $(lpad(round(θ[3],digits=4),14))")
    end
end

# ── Coefficient convergence table ─────────────────────────────────────────────
println("\n--- Learned VFA Coefficients θ* ---")
basis_labels = ["θ₀ bias", "θ₁ V (water value)", "θ₂ V² (concavity)",
                "θ₃ price", "θ₄ V·price"]
text_table(
    ["Basis function", "θ*", "Sign check"],
    [[basis_labels[i], round(θ[i], digits=5),
      i==3 ? (θ[i] < 0 ? "< 0 ✓ concave" : "> 0 ✗ convex") :
      i==2 ? (θ[i] > 0 ? "> 0 ✓ water is valuable" : "≤ 0") : "—"]
     for i in 1:n_θ];
    title = "Final VFA Coefficients (τ = $N_ITER iterations)"
)

# ── Learning curve ─────────────────────────────────────────────────────────────
line_chart(revenues_vfa;
    title  = "VFA Learning Curve — Revenue [k€] per Episode",
    ylabel = "Iteration",
    height = 10,
    width  = 50
)

line_chart(fairness_vfa;
    title  = "VFA Learning Curve — Mean Fairness F per Episode",
    ylabel = "Iteration",
    height = 10,
    width  = 50
)

# ── Marginal water value profile ──────────────────────────────────────────────
V_levels  = collect(0.0:25.0:V_MAX)
λ_w_vals  = [(θ[2] + 2*θ[3]*(v/V_MAX) + θ[5]*(50.0/100.0)) / V_MAX
             for v in V_levels]
println()
bar_chart(["V=$(round(Int,v)) Mm³" for v in V_levels], λ_w_vals;
    title = "Marginal Water Value λ_w(V) at price = 50 €/MWh  [k€/Mm³]",
    unit  = "k€/Mm³"
)

# ── Policy comparison ─────────────────────────────────────────────────────────
pfa    = HydroPFA(0.8, 0.2, 0.1)
pfa_fn = (V, price) -> clamp(pfa_release(pfa, (V=V, price=price, wind=20.0)),
                              0.0, Q_MAX)

# Average over 5 evaluation episodes for stable comparison
n_eval = 5
function eval_policy(fn)
    revs = Float64[]; Fs = Float64[]
    for _ in 1:n_eval
        _, r, mF = simulate(fn)
        push!(revs, r); push!(Fs, mF)
    end
    mean(revs), mean(Fs)
end

rev_vfa, F_vfa = eval_policy(vfa_Q)
rev_pfa, F_pfa = eval_policy(pfa_fn)

text_table(
    ["Policy", "Rev [k€]", "Mean F", "ΔRev vs PFA", "ΔF vs PFA"],
    [["PFA (baseline)",
      round(rev_pfa, digits=2), round(F_pfa, digits=2), "—", "—"],
     ["VFA (τ=$N_ITER)",
      round(rev_vfa, digits=2), round(F_vfa, digits=2),
      (rev_vfa >= rev_pfa ? "+" : "") * string(round((rev_vfa/max(rev_pfa,0.01)-1)*100, digits=1)) * "%",
      (F_vfa <= F_pfa    ? "−" : "+") * string(round(abs(1-F_vfa/max(F_pfa,0.01))*100, digits=1)) * "% " *
      (F_vfa <= F_pfa ? "better" : "worse")]];
    title = "Policy Performance Comparison ($n_eval-episode average)"
)

println("\n→ VFA uses water value signal to time dispatch.")
println("  θ₂ $(θ[3] < 0 ? "< 0 ✓" : "> 0 —") confirms $(θ[3] < 0 ? "concave" : "convex") value function shape.")
println("  Trained policy available as: HydroVFA(breakpoints, values)")
