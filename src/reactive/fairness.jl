"""
    fairness_metric(λQ::AbstractVector) -> Float64

Variance of reactive prices across generators — lower is fairer.
F = Σᵢ (λᵢᴼ - λ̄ᴼ)²
"""
function fairness_metric(λQ::AbstractVector)
    avg = mean(λQ)
    return sum((λ - avg)^2 for λ in λQ)
end
