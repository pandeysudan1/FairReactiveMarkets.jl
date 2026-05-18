using FairReactiveMarkets

# ── System data ──────────────────────────────────────────────────────────────

η    = 0.92
ρ    = 1000.0
g    = 9.81
H    = 120.0
Qtur = 200.0

# ── Hydropower generation ────────────────────────────────────────────────────

P = compute_generation(η, ρ, g, H, Qtur)
println("Hydropower generation = ", round(P / 1e6, digits=2), " MW")

# ── Reactive pricing & fairness ──────────────────────────────────────────────

λQ       = [10.0, 12.0, 8.0]
fairness = fairness_metric(λQ)
println("Reactive prices [€/MVAr]: ", λQ)
println("Fairness metric (variance) = ", fairness)

# ── FBMC ─────────────────────────────────────────────────────────────────────

PTDF = [0.4  0.2;
        0.1  0.5]

NP  = [100.0; 50.0]
RAM = [80.0;  70.0]

flows, violations = run_fbmc(PTDF, NP, RAM)
println("\nLine flows:      ", flows)
println("RAM violations:  ", violations)

# ── PFA policy ───────────────────────────────────────────────────────────────

policy = HydroPFA(0.8, 0.2, 0.1)
state  = (V = 100.0, price = 50.0, wind = 20.0)
q_pfa  = pfa_release(policy, state)
println("\nPFA release = ", q_pfa, " m³/s")

# ── DLA policy ───────────────────────────────────────────────────────────────

q_dla = run_dla()
println("DLA optimal release = ", round(q_dla, digits=2), " m³/s")

# ── VFA policy ───────────────────────────────────────────────────────────────

vfa    = HydroVFA([0.0, 50.0, 100.0, 150.0], [0.0, 200.0, 350.0, 400.0])
q_vfa  = vfa_release(vfa, state, state.price)
println("VFA release = ", q_vfa, " m³/s")

# ── Hybrid DLA+VFA ───────────────────────────────────────────────────────────

hybrid = HybridPolicy(HydroDLA(500.0, 100.0, 0.01), vfa, 0.5)
q_hyb  = hybrid_release(hybrid, state, state.price)
println("Hybrid release = ", round(q_hyb, digits=2), " m³/s")

# ── AC-OPF ───────────────────────────────────────────────────────────────────

opf = run_acopf(300.0, 100.0)
println("\nOPF: P=", opf.P, " Q=", opf.Q, " V=", round(opf.V, digits=4),
        " status=", opf.status)
