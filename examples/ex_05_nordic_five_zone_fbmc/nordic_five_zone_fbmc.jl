# ============================================================================
# Example 05 — Nordic Five-Zone FBMC Case Study
#
# Sub-question: How does FBMC across NO1/NO2/NO5/SE3/DK1 affect congestion
# patterns, reactive pricing, and inter-zone fairness over 24 hours?
# ============================================================================

using Statistics, LinearAlgebra

_src = joinpath(@__DIR__, "..", "..", "src")
include(joinpath(_src, "reactive", "pricing.jl"))
include(joinpath(_src, "reactive", "fairness.jl"))
include(joinpath(_src, "fbmc",     "ptdf.jl"))
include(joinpath(_src, "fbmc",     "ram.jl"))
include(joinpath(_src, "fbmc",     "coupling.jl"))
include(joinpath(@__DIR__, "..", "plot_helpers.jl"))

println("=" ^ 65)
println("Example 05 — Nordic Five-Zone FBMC Case Study")
println("=" ^ 65)

# ── Zone and network definition ───────────────────────────────────────────────
zones      = ["NO1", "NO2", "NO5", "SE3", "DK1"]
line_names = ["L1 NO2-SE3", "L2 NO1-SE3", "L3 NO5-NO2", "L4 SE3-DK1", "L5 NO1-NO2"]
n_zones = 5;  n_lines = 5

# PTDF matrix: rows=lines, cols=zones [NO1,NO2,NO5,SE3,DK1]
PTDF = [
    0.20   0.45   0.10  -0.30   0.15;   # L1 NO2-SE3
    0.50   0.15   0.05  -0.40   0.10;   # L2 NO1-SE3
    0.05   0.30   0.60   0.05   0.02;   # L3 NO5-NO2
    0.10   0.20   0.05   0.45  -0.55;   # L4 SE3-DK1
    0.40   0.35   0.10  -0.15   0.08    # L5 NO1-NO2
]

# Thermal limits [MW] per line → RAM after FRM and FAV
NTC  = [1400.0, 800.0, 600.0, 1700.0, 900.0]
FRM  = [  50.0,  30.0,  20.0,   60.0,  35.0]   # Flow Reliability Margin
FAV  = [  30.0,  20.0,  15.0,   40.0,  25.0]   # Final Adjustment Value
RAM  = compute_ram.(NTC, FRM, FAV)

println("\n--- Network Data ---")
text_table(
    ["Line", "NTC [MW]", "FRM [MW]", "FAV [MW]", "RAM [MW]"],
    [[line_names[i], NTC[i], FRM[i], FAV[i], RAM[i]] for i in 1:n_lines];
    title = "Line Ratings and Remaining Available Margins"
)

# ── 24-hour demand and generation profiles ─────────────────────────────────────
# Net positions NP_z(t) = generation - demand per zone [MW]
# Positive = exporter.  Profile designed to be realistic for a winter weekday.
function net_positions(h)
    # Norwegian hydro follows a flat-to-peak pattern
    hydro_scale = 1.0 + 0.2 * sin(π * (h - 6) / 12)   # peak at noon
    # Swedish nuclear + hydro (relatively flat, slight daytime dip)
    se3_np = -150.0 + 80.0 * sin(π * (h - 12) / 12)
    # Danish wind: morning/evening peaks
    wind_dk = 200.0 * (0.5 + 0.5 * sin(2π * (h - 6) / 24))
    # Net positions
    return [
        280.0 * hydro_scale,             # NO1: large hydro exporter
        180.0 + 100.0 * (h >= 10 && h <= 20 ? 1.0 : 0.0) * hydro_scale,  # NO2: peak dispatch
        140.0 * hydro_scale,             # NO5: medium hydro
        se3_np,                          # SE3: sometimes import
        -(wind_dk + 300.0)               # DK1: net importer (wind partial offset)
    ]
end

# ── Hourly FBMC simulation ─────────────────────────────────────────────────────
hours       = 0:23
all_flows   = zeros(n_lines, 24)
all_viol    = zeros(n_lines, 24)
utilisation = zeros(n_lines, 24)
congested_hours = Dict(l => Int[] for l in 1:n_lines)

# Reactive price proxy: proportional to flow/RAM ratio (congested = expensive)
zone_λQ     = zeros(n_zones, 24)
zone_F      = zeros(24)

for (ti, h) in enumerate(hours)
    NP = net_positions(h)
    flows, viol = run_fbmc(PTDF, NP, RAM)
    all_flows[:, ti]   = flows
    all_viol[:, ti]    = viol
    utilisation[:, ti] = abs.(flows) ./ RAM .* 100.0

    for l in 1:n_lines
        viol[l] > 0 && push!(congested_hours[l], h)
    end

    # Reactive prices: zones near congested lines pay/receive more
    congestion_signal = max.(viol, 0.0) ./ RAM   # congestion intensity
    for z in 1:n_zones
        λQ_base = 8.0 + 4.0 * abs(NP[z]) / 500.0    # scales with dispatch
        λQ_surcharge = sum(PTDF[l, z]^2 * congestion_signal[l] * 20.0
                           for l in 1:n_lines)
        zone_λQ[z, ti] = reactive_price(λQ_base + λQ_surcharge)
    end
    zone_F[ti] = fairness_metric(zone_λQ[:, ti])
end

println("\n--- 24-Hour Simulation Results ---")

# ── Line utilisation summary ──────────────────────────────────────────────────
mean_util  = [mean(utilisation[l, :]) for l in 1:n_lines]
max_util   = [maximum(utilisation[l, :]) for l in 1:n_lines]
n_congested= [length(congested_hours[l]) for l in 1:n_lines]

text_table(
    ["Line", "Mean util%", "Max util%", "Congested hrs", "Critical?"],
    [[line_names[l],
      round(mean_util[l], digits=1),
      round(max_util[l],  digits=1),
      n_congested[l],
      max_util[l] > 90 ? "⚠ YES" : "✓ No"]
     for l in 1:n_lines];
    title = "Line Utilisation Summary (24-hour)"
)

# ── Congestion heatmap ─────────────────────────────────────────────────────────
heatmap_text(
    utilisation[:, 1:2:24],    # every 2 hours for width
    line_names,
    ["$(h)h" for h in 0:2:22];
    title = "Congestion Intensity [% of RAM]  (every 2 hours)"
)

# ── Zone coupling matrix ───────────────────────────────────────────────────────
C = zone_coupling(1:n_zones, PTDF)
heatmap_text(
    C,
    zones,
    zones;
    title = "Zone Electrical Coupling Matrix C_ij"
)

strongest = argmax(C - Diagonal(diag(C)))
println("  Strongest off-diagonal coupling: $(zones[strongest[1]])–$(zones[strongest[2]])" *
        " = $(round(C[strongest], digits=3))")

# ── Reactive prices per zone ──────────────────────────────────────────────────
mean_λQ = [mean(zone_λQ[z, :]) for z in 1:n_zones]
bar_chart(zones, mean_λQ;
    title = "Mean Reactive Price per Zone [€/MVAr]  (24-hour average)",
    unit  = "€/MVAr"
)

# ── Fairness over 24 hours ────────────────────────────────────────────────────
line_chart(zone_F;
    title  = "Inter-Zone Fairness F_zones over 24 Hours",
    ylabel = "hour of day",
    height = 10,
    width  = 48
)

# ── Hourly summary table (key hours) ─────────────────────────────────────────
key_hours = [0, 6, 12, 18, 23]
text_table(
    ["Hour", "Max flow [MW]", "L1 util%", "λ̄ᴼ [€/MVAr]", "F_zones", "Status"],
    [begin
        ti = h + 1
        max_fl_idx = argmax(abs.(all_flows[:, ti]))
        vstat = zone_F[ti] < 15 ? "✓ Fair" :
                zone_F[ti] < 40 ? "⚠ Moderate" : "✗ Unfair"
        [h,
         round(all_flows[max_fl_idx, ti], digits=0),
         round(utilisation[1, ti], digits=1),
         round(mean(zone_λQ[:, ti]), digits=2),
         round(zone_F[ti], digits=2),
         vstat]
    end for h in key_hours];
    title = "Key-Hour Summary"
)

# ── Revenue and fairness by zone ──────────────────────────────────────────────
println("\n--- Revenue Share and Fairness Contribution per Zone ---")
total_λ = sum(mean_λQ)
text_table(
    ["Zone", "Mean λᴼ [€/MVAr]", "Revenue share%", "Role", "Fairness issue?"],
    [[zones[z],
      round(mean_λQ[z], digits=2),
      round(mean_λQ[z] / total_λ * 100, digits=1),
      z == 1 ? "Large hydro exporter" :
      z == 2 ? "Peak-shaving hydro"   :
      z == 3 ? "Coastal hydro"        :
      z == 4 ? "Nuclear+hydro mix"    : "Wind+import zone",
      mean_λQ[z] > mean(mean_λQ) * 1.2 ? "⚠ Over-compensated" :
      mean_λQ[z] < mean(mean_λQ) * 0.8 ? "⚠ Under-compensated" : "✓ OK"]
     for z in 1:n_zones];
    title = "Per-Zone Reactive Pricing and Equity Assessment"
)

uniform_price = mean(mean_λQ)
cross_subsidy = sum(abs(mean_λQ[z] - uniform_price) * 1000.0 for z in 1:n_zones)
println("\n  Uniform price benchmark: $(round(uniform_price, digits=2)) €/MVAr")
println("  Estimated annual cross-subsidy under uniform pricing:")
println("  $(round(cross_subsidy/1e3, digits=2)) M€/year  (assuming 1000 MW reactive base)")

# ── Final summary ─────────────────────────────────────────────────────────────
println("\n--- Summary ---")
println("  Critical corridor: $(line_names[argmax(max_util)]) " *
        "(max $(round(maximum(max_util),digits=1))% utilisation)")
println("  Most expensive zone: $(zones[argmax(mean_λQ)]) " *
        "($(round(maximum(mean_λQ),digits=2)) €/MVAr)")
println("  Least expensive zone: $(zones[argmin(mean_λQ)]) " *
        "($(round(minimum(mean_λQ),digits=2)) €/MVAr)")
println("  Peak unfairness hour: $(hours[argmax(zone_F)]):00 " *
        "(F = $(round(maximum(zone_F),digits=2)))")
println()
println("  → FBMC-aware locational pricing can eliminate the cross-subsidy")
println("    by weighting λᴼ with the zone's PTDF contribution to L1.")
