using JuMP
using Ipopt

"""
Direct Lookahead Approximation (DLA) policy.

Rolling single-period quadratic optimisation.
"""
struct HydroDLA
    Q_max::Float64
    c1::Float64   # linear revenue coefficient
    c2::Float64   # quadratic cost coefficient
end

function run_dla(policy::HydroDLA = HydroDLA(500.0, 100.0, 0.01))
    model = Model(Ipopt.Optimizer)
    set_silent(model)

    @variable(model, 0 <= Qtur <= policy.Q_max)
    @objective(model, Max, policy.c1 * Qtur - policy.c2 * Qtur^2)

    optimize!(model)
    return value(Qtur)
end
