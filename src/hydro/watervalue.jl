"""
    water_value(V, V_ref, λ_water) -> Float64

Linear water value: marginal value of reservoir storage [€/m³].
"""
function water_value(V, V_ref, λ_water)
    return λ_water * (V - V_ref)
end
