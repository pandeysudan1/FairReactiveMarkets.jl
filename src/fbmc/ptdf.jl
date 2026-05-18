"""
    run_fbmc(PTDF, NP, RAM) -> (flows, violations)

Compute line flows and identify RAM violations under FBMC.

    F_l = Σ_z PTDF_{l,z} · NP_z  ≤  RAM_l
"""
function run_fbmc(PTDF::AbstractMatrix, NP::AbstractVector, RAM::AbstractVector)
    flows      = PTDF * NP
    violations = flows .- RAM
    return flows, violations
end
