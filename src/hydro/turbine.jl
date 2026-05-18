"""
    compute_generation(η, ρ, g, H, Qtur) -> Float64

Hydropower generation P = η·ρ·g·H·Q [W].
"""
function compute_generation(η, ρ, g, H, Qtur)
    return η * ρ * g * H * Qtur
end
