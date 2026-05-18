"""
Digital twin stub for real-time state tracking.
"""
mutable struct DigitalTwin
    V::Float64        # reservoir level [m³]
    Q_flow::Float64   # current turbine flow [m³/s]
    price::Float64    # spot price [€/MWh]
    timestamp::Float64
end

DigitalTwin() = DigitalTwin(0.0, 0.0, 0.0, 0.0)

"""
    update_state!(dt, V, Q_flow, price, t)

Push new measurement into the digital twin.
"""
function update_state!(dt::DigitalTwin, V, Q_flow, price, t)
    dt.V         = V
    dt.Q_flow    = Q_flow
    dt.price     = price
    dt.timestamp = t
    return dt
end
