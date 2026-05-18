"""
Value Function Approximation (VFA) policy.

Piecewise-linear value function over reservoir level.
"""
struct HydroVFA
    breakpoints::Vector{Float64}   # reservoir levels
    values::Vector{Float64}        # V̂(V) at each breakpoint
end

function vfa_release(policy::HydroVFA, state, price)
    # Marginal water value via finite-difference on piecewise-linear V̂
    idx = searchsortedfirst(policy.breakpoints, state.V)
    idx = clamp(idx, 2, length(policy.breakpoints))
    dV  = policy.breakpoints[idx] - policy.breakpoints[idx-1]
    dVhat = policy.values[idx]    - policy.values[idx-1]
    λ_water = dVhat / dV
    # Release when market price exceeds marginal water value
    return price >= λ_water ? state.V * 0.1 : 0.0
end
