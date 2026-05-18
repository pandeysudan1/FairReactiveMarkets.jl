"""
    reactive_price(dual_variable) -> Float64

Reactive power price = Lagrange multiplier on Q constraint [€/MVAr].
"""
function reactive_price(dual_variable)
    return dual_variable
end
