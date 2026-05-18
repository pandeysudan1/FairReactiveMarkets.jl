"""
    voltage_deviation(V, V_ref) -> Float64

Squared per-unit voltage deviation penalty.
"""
function voltage_deviation(V, V_ref)
    return (V - V_ref)^2
end
