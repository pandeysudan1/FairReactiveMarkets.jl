"""
Hybrid DLA+VFA policy.

Uses VFA water value as terminal cost in the DLA horizon.
"""
struct HybridPolicy
    dla::HydroDLA
    vfa::HydroVFA
    λ_blend::Float64   # weight on VFA water value in objective
end

function hybrid_release(policy::HybridPolicy, state, price)
    model = Model(Ipopt.Optimizer)
    set_silent(model)

    @variable(model, 0 <= Qtur <= policy.dla.Q_max)

    # Marginal water value from VFA
    idx     = searchsortedfirst(policy.vfa.breakpoints, state.V)
    idx     = clamp(idx, 2, length(policy.vfa.breakpoints))
    dV      = policy.vfa.breakpoints[idx] - policy.vfa.breakpoints[idx-1]
    dVhat   = policy.vfa.values[idx]      - policy.vfa.values[idx-1]
    λ_water = dVhat / dV

    @objective(model, Max,
        price * Qtur -
        policy.dla.c2 * Qtur^2 -
        policy.λ_blend * λ_water * Qtur
    )

    optimize!(model)
    return value(Qtur)
end
