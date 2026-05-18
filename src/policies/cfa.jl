"""
Cost Function Approximation (CFA) policy.

Adds a future-cost term penalising low reservoir levels.
"""
struct HydroCFA
    θ1::Float64   # state weight
    θ2::Float64   # price weight
    θ3::Float64   # wind offset
    θ4::Float64   # future-cost scarcity weight
    V_ref::Float64
end

function cfa_release(policy::HydroCFA, state)
    base   = policy.θ1 * state.V +
             policy.θ2 * state.price -
             policy.θ3 * state.wind
    scarcity = policy.θ4 * max(0.0, policy.V_ref - state.V)
    return max(0.0, base - scarcity)
end
