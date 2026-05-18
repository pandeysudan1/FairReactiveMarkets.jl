"""
    compute_ram(NTC, FRM, FAV) -> Float64

Remaining Available Margin:  RAM = NTC - FRM - FAV
"""
function compute_ram(NTC, FRM, FAV)
    return NTC - FRM - FAV
end
