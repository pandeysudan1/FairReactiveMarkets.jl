using JuMP
using Ipopt

"""
    run_acopf(P_demand, Q_demand, V_min, V_max) -> NamedTuple

Simplified single-bus AC-OPF returning dispatch and voltage solution.
"""
function run_acopf(P_demand, Q_demand, V_min=0.95, V_max=1.05)
    model = Model(Ipopt.Optimizer)
    set_silent(model)

    @variable(model, V_min <= V <= V_max, start = 1.0)
    @variable(model, 0 <= P_gen <= 1000.0)
    @variable(model, -500.0 <= Q_gen <= 500.0)

    @constraint(model, P_gen >= P_demand)
    @constraint(model, Q_gen >= Q_demand)

    @objective(model, Min, 10.0 * P_gen + 5.0 * Q_gen^2 + 100.0 * (V - 1.0)^2)

    optimize!(model)
    return (P = value(P_gen), Q = value(Q_gen), V = value(V),
            status = termination_status(model))
end
