using JuMP
using Ipopt

"""
    run_market_clearing(offers, bids, PTDF, RAM) -> NamedTuple

Single-period market clearing with FBMC congestion constraints.
`offers` and `bids` are vectors of (price, quantity) tuples.
"""
function run_market_clearing(
    offers::Vector{Tuple{Float64,Float64}},
    bids::Vector{Tuple{Float64,Float64}},
    PTDF::AbstractMatrix,
    RAM::AbstractVector
)
    n_gen = length(offers)
    n_load = length(bids)
    model = Model(Ipopt.Optimizer)
    set_silent(model)

    @variable(model, 0 <= p[i=1:n_gen] <= offers[i][2])
    @variable(model, 0 <= d[j=1:n_load] <= bids[j][2])

    # Energy balance
    @constraint(model, sum(p) == sum(d))

    # FBMC: flows ≤ RAM
    NP = [sum(p[i] for i in 1:n_gen) - sum(d[j] for j in 1:n_load)]
    for l in eachindex(RAM)
        @constraint(model, PTDF[l, 1] * NP[1] <= RAM[l])
    end

    @objective(model, Max,
        sum(bids[j][1] * d[j] for j in 1:n_load) -
        sum(offers[i][1] * p[i] for i in 1:n_gen)
    )

    optimize!(model)
    return (dispatch = value.(p), demand = value.(d),
            status = termination_status(model))
end
