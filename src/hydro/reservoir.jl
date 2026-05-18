using ModelingToolkit

@independent_variables t
D = Differential(t)

@variables V(t) Qin(t) Qtur(t) Qspill(t)
@parameters V_min V_max

eqs = [
    D(V) ~ Qin - Qtur - Qspill
]

# Reservoir ODESystem: state V, inputs Qin/Qtur/Qspill
@named ReservoirSystem = ODESystem(eqs, t, [V, Qin, Qtur, Qspill], [V_min, V_max])
