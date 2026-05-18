"""
Parametric Function Approximation (PFA) policy.

Affine release rule:  Q = θ₁·V + θ₂·price − θ₃·wind
"""
struct HydroPFA
    θ1::Float64
    θ2::Float64
    θ3::Float64
end

function pfa_release(policy::HydroPFA, state)
    return policy.θ1 * state.V +
           policy.θ2 * state.price -
           policy.θ3 * state.wind
end
