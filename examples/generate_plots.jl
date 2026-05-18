# ============================================================================
# generate_plots.jl — Generate all SVG figures for ex_01 through ex_05
# Run from package root:  julia examples/generate_plots.jl
# ============================================================================

using Plots, Statistics, LinearAlgebra, Random
gr()

const OUTDIR = joinpath(@__DIR__, "plot_figures")
mkpath(OUTDIR)
println("Output directory: ", OUTDIR)

_src = joinpath(@__DIR__, "..", "src")
include(joinpath(_src, "hydro",    "turbine.jl"))
include(joinpath(_src, "reactive", "pricing.jl"))
include(joinpath(_src, "reactive", "voltage.jl"))
include(joinpath(_src, "reactive", "fairness.jl"))
include(joinpath(_src, "fbmc",     "ptdf.jl"))
include(joinpath(_src, "fbmc",     "ram.jl"))
include(joinpath(_src, "fbmc",     "coupling.jl"))
include(joinpath(_src, "policies", "pfa.jl"))
include(joinpath(_src, "policies", "cfa.jl"))
include(joinpath(_src, "policies", "vfa.jl"))

sv(name, p) = (savefig(p, joinpath(OUTDIR, "$name.svg")); println("  ✓  $name.svg"))

# Manual grouped bar chart (avoids StatsPlots dependency)
function grouped_bars(data; labels=nothing, colors=nothing, xlabel="", ylabel="", title="",
                      xtick_labels=nothing, kwargs...)
    ng = size(data, 1)   # number of groups (x positions)
    ns = size(data, 2)   # number of series
    w  = 0.75 / ns
    p  = plot(; xlabel, ylabel, title,
               xticks  = (1:ng, isnothing(xtick_labels) ? string.(1:ng) : xtick_labels),
               xlims   = (0.3, ng + 0.7),
               kwargs...)
    for j in 1:ns
        offset = (j - (ns + 1) / 2) * w
        xs = collect(1:ng) .+ offset
        c  = isnothing(colors) ? :auto : colors[j]
        l  = isnothing(labels) ? "S$j"  : labels[j]
        bar!(p, xs, data[:, j]; bar_width = w * 0.90, color = c, label = l, alpha = 0.88)
    end
    p
end

default(
    fontfamily     = "Helvetica",
    titlefontsize  = 12,
    guidefontsize  = 10,
    tickfontsize   = 9,
    legendfontsize = 9,
    linewidth      = 2.2,
    markersize     = 6,
    framestyle     = :box,
    grid           = true,
    gridalpha      = 0.25,
    size           = (720, 440),
    background_color = :white,
    foreground_color = :black,
    dpi            = 130,
)

# Colour palette
C = (
    pfa  = RGB(0.20, 0.52, 0.78),
    cfa  = RGB(0.90, 0.50, 0.10),
    vfa  = RGB(0.15, 0.62, 0.18),
    dla  = RGB(0.84, 0.15, 0.16),
    no1  = RGB(0.12, 0.47, 0.71),
    no2  = RGB(0.17, 0.63, 0.17),
    no5  = RGB(0.98, 0.50, 0.08),
    se3  = RGB(0.58, 0.40, 0.74),
    dk1  = RGB(0.84, 0.15, 0.16),
    grid = RGBA(0.6, 0.6, 0.6, 0.4),
)

# ─────────────────────────────────────────────────────────────────────────────
println("\n── ex_01: Getting Started ──────────────────────────────────────────")

# Fig 1 — Hydropower generation curve
Q_range = 50.0:5.0:310.0
η, ρ, g, H = 0.92, 1000.0, 9.81, 120.0
P_curve = [compute_generation(η, ρ, g, H, q) / 1e6 for q in Q_range]
Q_op    = 200.0
P_op    = compute_generation(η, ρ, g, H, Q_op) / 1e6

p = plot(Q_range, P_curve;
         xlabel = "Turbine Flow Q [m³/s]",
         ylabel = "Active Power P [MW]",
         title  = "Hydropower Generation Curve\n(η = 0.92, H = 120 m, ρ = 1000 kg/m³)",
         color  = C.no1,
         fill   = (0, 0.12, C.no1),
         label  = "P = η·ρ·g·H·Q")
vline!([Q_op]; linestyle = :dash, color = C.cfa, label = "Operating point Q=200")
scatter!([Q_op], [P_op]; markersize = 9, color = C.cfa,
         label = "P = $(round(P_op, digits=1)) MW")
sv("ex01_fig01_generation_curve", p)

# Fig 2 — Reactive price bar chart
gen_names = ["Tonstad", "Sima", "Aurland"]
λQ_vals   = [10.0, 12.0, 8.0]
λ_mean    = mean(λQ_vals)
F_val     = fairness_metric(λQ_vals)

p = bar(gen_names, λQ_vals;
        xlabel    = "Generator",
        ylabel    = "Reactive Price λᴼ [€/MVAr]",
        title     = "Reactive Power Prices — Three NO2 Generators\n(Fairness F = $(F_val)  →  target F → 0)",
        color     = [C.no1, C.no5, C.vfa],
        bar_width = 0.55,
        legend    = false,
        ylims     = (0, 15))
hline!([λ_mean]; linestyle = :dash, color = C.dla, linewidth = 2,
       label = "Mean $(λ_mean) €/MVAr")
annotate!(2.0, λ_mean + 0.4,
          text("Mean = $(λ_mean) €/MVAr", C.dla, :center, 9))
sv("ex01_fig02_reactive_prices", p)

# ─────────────────────────────────────────────────────────────────────────────
println("\n── ex_02: Stochastic Scenarios ─────────────────────────────────────")

sc = (names  = ["ω₁ Low\n(W=5 MW)", "ω₂ Mid\n(W=20 MW)", "ω₃ High\n(W=45 MW)"],
      wind   = [5.0, 20.0, 45.0],
      prob   = [0.3, 0.4,  0.3],
      price  = [55.0, 50.0, 42.0])

pfa_p = HydroPFA(0.8, 0.2, 0.1)
cfa_p = HydroCFA(0.8, 0.2, 0.1, 1.0, 120.0)
vfa_p = HydroVFA([0.0, 50.0, 100.0, 150.0], [0.0, 200.0, 350.0, 400.0])

λQ_from_Q(Q, wind) = begin
    Qd = [30 + 0.3wind, 25 + 0.2wind, 20 + 0.1wind]
    qa = [Q*0.40, Q*0.35, Q*0.25]
    [max(1.0, 8.0 * Qd[i] / max(qa[i], 1.0)) for i in 1:3]
end

Q_mat  = zeros(3, 3)    # rows=scenarios, cols=policies
F_mat  = zeros(3, 3)
rev_mat = zeros(3, 3)

for i in 1:3
    s = (V=100.0, price=sc.price[i], wind=sc.wind[i])
    qs = [pfa_release(pfa_p, s), cfa_release(cfa_p, s), vfa_release(vfa_p, s, s.price)]
    for j in 1:3
        Q_mat[i,j]   = qs[j]
        F_mat[i,j]   = fairness_metric(λQ_from_Q(qs[j], sc.wind[i]))
        rev_mat[i,j] = qs[j] * sc.price[i] * 0.1
    end
end

pol_labels = ["PFA", "CFA", "VFA"]
pol_colors = [C.pfa, C.cfa, C.vfa]

# Fig 1 — Grouped bar: releases by scenario × policy
p = grouped_bars(Q_mat;
               labels      = pol_labels,
               colors      = pol_colors,
               xlabel      = "Wind Scenario",
               ylabel      = "Turbine Release Q [m³/s]",
               title       = "Policy Dispatch Across Wind Scenarios",
               xtick_labels = ["ω₁ Low", "ω₂ Mid", "ω₃ High"])
sv("ex02_fig01_scenario_releases", p)

# Fig 2 — Expected fairness per policy
E_F   = [sum(F_mat[i,j]   * sc.prob[i] for i in 1:3) for j in 1:3]
p = bar(pol_labels, E_F;
        xlabel    = "Policy",
        ylabel    = "Expected Fairness E[F]  [€²/MVAr²]",
        title     = "Expected Reactive Pricing Fairness\n(lower = fairer)",
        color     = pol_colors,
        bar_width = 0.55,
        legend    = false)
sv("ex02_fig02_expected_fairness", p)

# Fig 3 — Expected revenue per policy
E_rev = [sum(rev_mat[i,j] * sc.prob[i] for i in 1:3) for j in 1:3]
p = bar(pol_labels, E_rev;
        xlabel    = "Policy",
        ylabel    = "Expected Revenue E[Rev]  [€]",
        title     = "Expected Revenue Across Wind Scenarios",
        color     = pol_colors,
        bar_width = 0.55,
        legend    = false)
sv("ex02_fig03_expected_revenue", p)

# Fig 4 — FBMC flows vs RAM across scenarios
PTDF2 = [0.4 0.2; 0.1 0.5]
RAM2  = [compute_ram(200.0,80.0,40.0), compute_ram(150.0,50.0,30.0)]
flow_mat = zeros(3, 2)
for i in 1:3
    fl, _ = run_fbmc(PTDF2, [100.0 + sc.wind[i]; 50.0], RAM2)
    flow_mat[i, :] = fl
end
p = grouped_bars(flow_mat;
               labels       = ["Line 1 (NO2–SE3)", "Line 2 (SE3–DK1)"],
               colors       = [C.no2, C.se3],
               xlabel       = "Wind Scenario",
               ylabel       = "Line Flow [MW]",
               title        = "FBMC Line Flows vs RAM (NO2-SE3 corridor)",
               xtick_labels = ["ω₁ Low","ω₂ Mid","ω₃ High"])
hline!([RAM2[1]]; linestyle=:dash, color=C.no2, linewidth=1.8, label="RAM L1")
hline!([RAM2[2]]; linestyle=:dashdot, color=C.se3, linewidth=1.8, label="RAM L2")
sv("ex02_fig04_fbmc_flows", p)

# ─────────────────────────────────────────────────────────────────────────────
println("\n── ex_03: AC-OPF Voltage Security ──────────────────────────────────")

const V_MIN3 = 0.95; const V_MAX3 = 1.05; const V_REF3 = 1.0
P_MAX3 = [400.0,300.0,250.0]; Q_MAX3 = [200.0,150.0,125.0]
Q_MIN3 = [-100.0,-75.0,-62.5]; c_Q3  = [0.020, 0.022, 0.018]

function opf3(P_d)
    Q_d = P_d * 0.3
    P_g = [pmax / sum(P_MAX3) * P_d for pmax in P_MAX3]
    order = sortperm(c_Q3)
    Q_g = zeros(3); rem = Q_d
    for i in order
        q = clamp(rem, Q_MIN3[i], Q_MAX3[i]); Q_g[i] = q; rem -= q
    end
    V = clamp(V_REF3 + 0.002*(sum(Q_g)-Q_d+0.05)/max(Q_d,1.0), V_MIN3, V_MAX3)
    λQ = [max(0.0, 2c_Q3[i]*Q_g[i]) for i in 1:3]
    P_g, Q_g, V, λQ, fairness_metric(λQ)
end

loads3 = 100.0:5.0:600.0
Vs3    = [opf3(P)[3] for P in loads3]
Fs3    = [opf3(P)[5] for P in loads3]
λ̄s3   = [mean(opf3(P)[4]) for P in loads3]
dVs3   = voltage_deviation.(Vs3, V_REF3)

# Fig 1 — Voltage profile
p = plot(loads3, Vs3;
         xlabel = "Active Load P_d [MW]",
         ylabel = "Bus Voltage V [pu]",
         title  = "Voltage Profile vs Load",
         color  = C.no1, fill = (V_MIN3, 0.10, C.no1), label = "V(P_d)")
hline!([V_MIN3]; linestyle=:dash, color=:red,       linewidth=2, label="V_min = $(V_MIN3) pu")
hline!([V_MAX3]; linestyle=:dash, color=:darkgreen, linewidth=2, label="V_max = $(V_MAX3) pu")
hline!([V_REF3]; linestyle=:dot,  color=:gray,      linewidth=1, label="V_ref = 1.0 pu")
sv("ex03_fig01_voltage_profile", p)

# Fig 2 — P-Q capability ellipse + operating arc
θ_u = range(0, π, length=200)
θ_l = range(π, 2π, length=200)
Pu  = 400.0 .* cos.(θ_u)
Qu  = 200.0 .* sin.(θ_u)
Pl  = 400.0 .* cos.(θ_l)
Ql  = 100.0 .* sin.(θ_l .- π) .* (-1)   # absorption side

p = plot(vcat(Pu, reverse(Pl)), vcat(Qu, reverse(Ql));
         xlabel = "Active Power P [MW]",
         ylabel = "Reactive Power Q [MVAr]",
         title  = "Generator P–Q Capability Diagram (Tonstad, 400 MW)",
         color  = C.no1, fill = (0, 0.08, C.no1), label = "Capability boundary",
         size   = (520, 520))
hline!([0]; color=:black, linewidth=0.8, label=false)
vline!([0]; color=:black, linewidth=0.8, label=false)
for (Pd, col, lab) in [(200.0, C.vfa, "P_d=200"), (350.0, C.cfa, "P_d=350"), (500.0, C.dla, "P_d=500")]
    _, Q_g, _, _, _ = opf3(Pd)
    scatter!([Pd/3], [Q_g[1]]; markersize=9, color=col, label=lab)
end
sv("ex03_fig02_pq_capability", p)

# Fig 3 — λ vs load
p = plot(loads3, λ̄s3;
         xlabel = "Active Load P_d [MW]",
         ylabel = "Mean Reactive Price λ̄ᴼ [€/MVAr]",
         title  = "Reactive Power Price vs Active Load",
         color  = C.cfa, fill = (0, 0.12, C.cfa), label = "λ̄ᴼ(P_d)")
sv("ex03_fig03_reactive_price", p)

# Fig 4 — Fairness vs load
p = plot(loads3, Fs3;
         xlabel = "Active Load P_d [MW]",
         ylabel = "Fairness Metric F  [lower = fairer]",
         title  = "Reactive Pricing Fairness vs Load",
         color  = C.vfa, fill = (0, 0.12, C.vfa), label = "F(P_d)")
hline!([0]; linestyle=:dot, color=:gray, linewidth=1.2, label="F = 0 (perfectly fair)")
sv("ex03_fig04_fairness_vs_load", p)

# Fig 5 — Voltage deviation vs load
p = plot(loads3, dVs3;
         xlabel = "Active Load P_d [MW]",
         ylabel = "(V − V_ref)²  [pu²]",
         title  = "Voltage Deviation Penalty vs Load",
         color  = C.dla, fill = (0, 0.12, C.dla), label = "(V−1)²")
sv("ex03_fig05_voltage_deviation", p)

# ─────────────────────────────────────────────────────────────────────────────
println("\n── ex_04: VFA Training ─────────────────────────────────────────────")

Random.seed!(42)
const V_MAX4 = 150.0; const Q_MAX4 = 300.0
const P_REF4 = compute_generation(0.92, 1000.0, 9.81, 120.0, Q_MAX4) / 1e6
const γ4 = 0.95; const T4 = 100; const N4 = 50

rw4(Q, price, wind) = begin
    Qd = [30+0.3wind, 25+0.2wind, 20+0.1wind]
    qa = [Q*0.40, Q*0.35, Q*0.25]
    λQ = [max(1.0, 8.0*Qd[i]/max(qa[i],1.0)) for i in 1:3]
    price * compute_generation(0.92,1000.0,9.81,120.0,Q)/1e9 - 1e-4*fairness_metric(λQ),
    fairness_metric(λQ)
end

bf4(V,p) = (v=V/V_MAX4; pp=p/100.0; [1.0, v, v^2, pp, v*pp])
θ4 = [0.0, 1.0, 0.0, 0.1, 0.0]
ev4(V,p) = dot(bf4(V,p), θ4)
tr4(V,Q,Qi) = (v2=V+(Qi-Q); sp=max(0.0,v2-V_MAX4); clamp(v2-sp,0.0,V_MAX4))

vp4(V,p) = begin
    vn=V/V_MAX4; pn=p/100.0
    dVdV = (θ4[2]+2*θ4[3]*vn+θ4[5]*pn)/V_MAX4
    rr   = p*P_REF4/(Q_MAX4*1000.0)
    Q_MAX4 * clamp(rr > 0 ? 1.0-γ4*dVdV/rr : 0.0, 0.0, 1.0)
end

pfa4  = HydroPFA(0.8, 0.2, 0.1)
pf4(V,p) = clamp(pfa_release(pfa4,(V=V,price=p,wind=20.0)),0.0,Q_MAX4)

revs_v=Float64[]; Fs_v=Float64[]
revs_p=Float64[]; Fs_p=Float64[]

for iter in 1:N4
    # VFA episode
    Vv=0.6*V_MAX4; rv=0.0; Fv=Float64[]; tr_buf=[]
    for t_step in 1:T4
        pr=clamp(50+20randn(),5,150); wi=clamp(20+15randn(),0,80)
        Qi=clamp(50+30randn(),0,120)
        Q=clamp(vp4(Vv,pr),0.0,min(Q_MAX4,Vv))
        r,F=rw4(Q,pr,wi); Vn=tr4(Vv,Q,Qi)
        push!(tr_buf,(V=Vv,pr=pr,r=r,Vn=Vn,pn=clamp(50+20randn(),5,150)))
        push!(Fv,F); rv+=r*γ4^(t_step-1); Vv=Vn
    end
    push!(revs_v,rv); push!(Fs_v,mean(Fv))
    Φ=reduce(vcat,[bf4(t.V,t.pr)' for t in tr_buf])
    b=[t.r+γ4*ev4(t.Vn,t.pn) for t in tr_buf]
    θ4 .= (Φ'Φ+1e-3*I)\(Φ'*b)

    # PFA episode
    Vp=0.6*V_MAX4; rp=0.0; Fp=Float64[]
    for t_step in 1:T4
        pr=clamp(50+20randn(),5,150); wi=clamp(20+15randn(),0,80)
        Qi=clamp(50+30randn(),0,120)
        Q=clamp(pf4(Vp,pr),0.0,min(Q_MAX4,Vp))
        r,F=rw4(Q,pr,wi); push!(Fp,F); rp+=r*γ4^(t_step-1); Vp=tr4(Vp,Q,Qi)
    end
    push!(revs_p,rp); push!(Fs_p,mean(Fp))
end

# Fig 1 — Learning curve revenue
p = plot(1:N4, revs_v;
         xlabel = "Training Iteration τ",
         ylabel = "Episode Revenue  [×10⁻³ k€]",
         title  = "VFA Learning Curve — Revenue per Episode",
         color  = C.vfa, label = "VFA")
plot!(1:N4, revs_p; color=C.pfa, linestyle=:dash, label="PFA baseline")
sv("ex04_fig01_learning_curve_revenue", p)

# Fig 2 — Learning curve fairness
p = plot(1:N4, Fs_v;
         xlabel = "Training Iteration τ",
         ylabel = "Mean Fairness F per Episode",
         title  = "VFA Learning Curve — Fairness",
         color  = C.cfa, label = "VFA")
plot!(1:N4, Fs_p; color=C.pfa, linestyle=:dash, label="PFA baseline")
sv("ex04_fig02_learning_curve_fairness", p)

# Fig 3 — Marginal water value profile
V_pts  = 0.0:2.0:V_MAX4
λ_w    = [(θ4[2]+2θ4[3]*(v/V_MAX4)+θ4[5]*0.50)/V_MAX4 for v in V_pts]
p = plot(V_pts, λ_w;
         xlabel = "Reservoir Level V [Mm³]",
         ylabel = "Marginal Water Value λ_w  [k€/Mm³]",
         title  = "Learned Marginal Water Value λ_w(V)\n(evaluated at price = 50 €/MWh)",
         color  = C.se3,
         fill   = (minimum(λ_w), 0.12, C.se3),
         label  = "λ_w(V; θ*)")
hline!([0]; linestyle=:dot, color=:gray, linewidth=1, label=false)
sv("ex04_fig03_marginal_water_value", p)

# Fig 4 — Policy comparison bar (final-iteration averages)
pol_rev = [mean(revs_v[max(1,N4-9):N4]), mean(revs_p[max(1,N4-9):N4])]
pol_F   = [mean(Fs_v[max(1,N4-9):N4]),   mean(Fs_p[max(1,N4-9):N4])]
p = bar(["VFA (τ=$N4)", "PFA (baseline)"], pol_rev;
        ylabel    = "Mean Revenue (last 10 episodes)",
        title     = "Policy Revenue Comparison",
        color     = [C.vfa, C.pfa],
        bar_width = 0.5,
        legend    = false)
sv("ex04_fig04_policy_comparison_revenue", p)

# ─────────────────────────────────────────────────────────────────────────────
println("\n── ex_05: Nordic Five-Zone FBMC ────────────────────────────────────")

zones5 = ["NO1","NO2","NO5","SE3","DK1"]
lns5   = ["L1 NO2-SE3","L2 NO1-SE3","L3 NO5-NO2","L4 SE3-DK1","L5 NO1-NO2"]
nz=5; nl=5

PTDF5 = [0.20  0.45  0.10 -0.30  0.15;
         0.50  0.15  0.05 -0.40  0.10;
         0.05  0.30  0.60  0.05  0.02;
         0.10  0.20  0.05  0.45 -0.55;
         0.40  0.35  0.10 -0.15  0.08]
RAM5  = compute_ram.([1400,800,600,1700,900.0],[50,30,20,60,35.0],[30,20,15,40,25.0])

np5(h) = begin
    hs  = 1.0+0.2*sin(π*(h-6)/12)
    se3 = -150.0+80.0*sin(π*(h-12)/12)
    wnd = 200*(0.5+0.5*sin(2π*(h-6)/24))
    [280.0*hs, 180.0+100*(10<=h<=20 ? 1.0 : 0.0)*hs, 140.0*hs, se3, -(wnd+300.0)]
end

flows5  = zeros(nl,24); util5 = zeros(nl,24)
zλQ5    = zeros(nz,24); zF5   = zeros(24)

for (ti,h) in enumerate(0:23)
    NP = np5(h)
    fl, _ = run_fbmc(PTDF5, NP, RAM5)
    flows5[:,ti] = fl; util5[:,ti] = abs.(fl)./RAM5.*100
    cong = max.(0.0, fl.-RAM5)./RAM5
    for z in 1:nz
        zλQ5[z,ti] = 8.0+4abs(NP[z])/500+sum(PTDF5[l,z]^2*cong[l]*20 for l in 1:nl)
    end
    zF5[ti] = fairness_metric(zλQ5[:,ti])
end

zone_colors = [C.no1, C.no2, C.no5, C.se3, C.dk1]

# Fig 1 — 24-hour line flows
p = plot(; xlabel="Hour of Day", ylabel="Line Flow [MW]",
         title="24-Hour Line Flows — Nordic FBMC\n(dashed = RAM limit)")
line_colors = [C.no2, C.no1, C.no5, C.se3, C.dk1]
for i in 1:nl
    plot!(0:23, flows5[i,:]; label=lns5[i], color=line_colors[i])
    hline!([RAM5[i]]; color=line_colors[i], linestyle=:dash, alpha=0.55, label=false)
end
sv("ex05_fig01_hourly_flows", p)

# Fig 2 — Congestion heatmap
p = heatmap(0:23, lns5, util5;
            xlabel = "Hour of Day",
            ylabel = "Corridor",
            title  = "Congestion Intensity [% of RAM]",
            color  = :YlOrRd,
            clim   = (0, 100),
            size   = (760, 360))
sv("ex05_fig02_congestion_heatmap", p)

# Fig 3 — Zone coupling heatmap
C5 = zone_coupling(1:nz, PTDF5)
p = heatmap(zones5, zones5, C5;
            xlabel = "Zone",
            ylabel = "Zone",
            title  = "Zone Electrical Coupling Matrix  C_ij\n(stronger = more price spillover)",
            color  = :Blues,
            size   = (480, 460))
sv("ex05_fig03_zone_coupling", p)

# Fig 4 — Mean reactive price by zone
mean_λQ5 = [mean(zλQ5[z,:]) for z in 1:nz]
ū = mean(mean_λQ5)
p = bar(zones5, mean_λQ5;
        xlabel    = "Zone",
        ylabel    = "Mean Reactive Price [€/MVAr]",
        title     = "24-Hour Mean Reactive Price by Zone",
        color     = zone_colors,
        bar_width = 0.6,
        legend    = false)
hline!([ū]; linestyle=:dash, color=:black, linewidth=2, label=false)
annotate!(3.0, ū+0.08, text("Uniform = $(round(ū,digits=2))", :black, :center, 9))
sv("ex05_fig04_reactive_prices_by_zone", p)

# Fig 5 — Inter-zone fairness over 24h
p = plot(0:23, zF5;
         xlabel = "Hour of Day",
         ylabel = "Inter-Zone Fairness F_zones",
         title  = "Reactive Pricing Fairness Across 5 Zones — 24 Hours\n(lower = fairer)",
         color  = C.vfa,
         fill   = (0, 0.14, C.vfa),
         label  = "F_zones(t)")
hline!([10.0]; linestyle=:dash, color=:red, linewidth=2,
       label="Design target F < 10")
sv("ex05_fig05_fairness_24h", p)

println("\n✓ All plots saved to $(OUTDIR)")
println("  Files: $(join(readdir(OUTDIR), ", "))")
