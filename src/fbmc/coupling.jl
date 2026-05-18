"""
    zone_coupling(zones, PTDF) -> Matrix

Return the zone-to-zone coupling matrix implied by the PTDF.
"""
function zone_coupling(zones::AbstractVector, PTDF::AbstractMatrix)
    n = length(zones)
    C = zeros(n, n)
    for i in 1:n, j in 1:n
        C[i, j] = sum(abs.(PTDF[:, i] .* PTDF[:, j]))
    end
    return C
end
