_SingleComponentLoad = Union{PSY.PowerLoad, PSY.ExponentialLoad, PSY.InterruptiblePowerLoad}
get_total_p(l::_SingleComponentLoad) = PSY.get_active_power(l)
get_total_q(l::_SingleComponentLoad) = PSY.get_reactive_power(l)

function get_total_p(l::PSY.StandardLoad)
    return PSY.get_constant_active_power(l) +
           PSY.get_current_active_power(l) +
           PSY.get_impedance_active_power(l)
end

function get_total_q(l::PSY.StandardLoad)
    return PSY.get_constant_reactive_power(l) +
           PSY.get_current_reactive_power(l) +
           PSY.get_impedance_reactive_power(l)
end

"""
Return the reactive power limits that should be used in power flow calculations and PSS/E
exports. Redirects to `PSY.get_reactive_power_limits` in all but special cases.
"""
get_reactive_power_limits_for_power_flow(gen::PSY.Device) =
    PSY.get_reactive_power_limits(gen)

function get_reactive_power_limits_for_power_flow(gen::PSY.RenewableNonDispatch)
    val = PSY.get_reactive_power(gen)
    return (min = val, max = val)
end

function get_reactive_power_limits_for_power_flow(gen::PSY.Storage)
    limits = PSY.get_reactive_power_limits(gen)
    isnothing(limits) && return (min = -Inf, max = Inf)  # TODO decide on proper behavior in this case
    return limits
end

"""
Return the active power limits that should be used in power flow calculations and PSS/E
exports. Redirects to `PSY.get_active_power_limits` in all but special cases.
"""
get_active_power_limits_for_power_flow(gen::PSY.Device) = PSY.get_active_power_limits(gen)

get_active_power_limits_for_power_flow(::PSY.Source) = (min = -Inf, max = Inf)

function get_active_power_limits_for_power_flow(gen::PSY.RenewableNonDispatch)
    val = PSY.get_active_power(gen)
    return (min = val, max = val)
end

get_active_power_limits_for_power_flow(gen::PSY.RenewableDispatch) =
    (min = 0.0, max = PSY.get_rating(gen))

# TODO verify whether this is the correct behavior for Storage, (a) for redistribution and (b) for exporting
get_active_power_limits_for_power_flow(gen::PSY.Storage) =
    (min = 0.0, max = PSY.get_output_active_power_limits(gen).max)

function _get_injections!(
    bus_activepower_injection::Vector{Float64},
    bus_reactivepower_injection::Vector{Float64},
    bus_lookup::Dict{Int, Int},
    sys::PSY.System,
)
    sources = PSY.get_components(d -> !isa(d, PSY.ElectricLoad), PSY.StaticInjection, sys)
    for source in sources
        !PSY.get_available(source) && continue
        bus = PSY.get_bus(source)
        bus_ix = bus_lookup[PSY.get_number(bus)]
        bus_activepower_injection[bus_ix] += PSY.get_active_power(source)
        bus_reactivepower_injection[bus_ix] += PSY.get_reactive_power(source)
    end
    return
end

function _get_withdrawals!(
    bus_activepower_withdrawals::Vector{Float64},
    bus_reactivepower_withdrawals::Vector{Float64},
    bus_lookup::Dict{Int, Int},
    sys::PSY.System,
)
    loads = PSY.get_components(x -> !isa(x, PSY.FixedAdmittance), PSY.ElectricLoad, sys)
    for l in loads
        !PSY.get_available(l) && continue
        bus = PSY.get_bus(l)
        bus_ix = bus_lookup[PSY.get_number(bus)]
        bus_activepower_withdrawals[bus_ix] += get_total_p(l)
        bus_reactivepower_withdrawals[bus_ix] += get_total_q(l)
    end
    return
end

# TODO: Might need changes if we have SwitchedAdmittances
function _get_reactive_power_bound!(
    bus_reactivepower_bounds::Vector{Vector{Float64}},
    bus_lookup::Dict{Int, Int},
    sys::PSY.System)
    sources = PSY.get_components(d -> !isa(d, PSY.ElectricLoad), PSY.StaticInjection, sys)
    for source in sources
        !PSY.get_available(source) && continue
        bus = PSY.get_bus(source)
        bus_ix = bus_lookup[PSY.get_number(bus)]
        reactive_power_limits = get_reactive_power_limits_for_power_flow(source)
        if reactive_power_limits !== nothing
            bus_reactivepower_bounds[bus_ix][1] += min(0, reactive_power_limits.min)
            bus_reactivepower_bounds[bus_ix][2] += max(0, reactive_power_limits.max)
        else
            @warn("Reactive Power Bounds at Bus $(PSY.get_name(bus)) set to (-Inf, Inf)")
            bus_reactivepower_bounds[bus_ix][1] = -Inf
            bus_reactivepower_bounds[bus_ix][2] = Inf
        end
    end
end

function _initialize_bus_data!(
    bus_type::Vector{PSY.ACBusTypes},
    bus_angles::Vector{Float64},
    bus_magnitude::Vector{Float64},
    temp_bus_map::Dict{Int, String},
    bus_lookup::Dict{Int, Int},
    sys::PSY.System,
)
    for (bus_no, ix) in bus_lookup
        bus_name = temp_bus_map[bus_no]
        bus = PSY.get_component(PSY.Bus, sys, bus_name)
        bt = PSY.get_bustype(bus)
        bus_type[ix] = bt
        if bus_type[ix] == PSY.ACBusTypes.REF
            bus_angles[ix] = 0.0
        else
            bus_angles[ix] = PSY.get_angle(bus)
        end
        bus_vm = PSY.get_magnitude(bus)
        # prevent unfeasible starting values for voltage magnitude at PQ buses (for PV and REF buses we cannot do this):
        if bt == PSY.ACBusTypes.PQ && bus_vm < BUS_VOLTAGE_MAGNITUDE_CUTOFF_MIN
            @warn(
                "Initial bus voltage magnitude of $bus_vm p.u. at PQ bus $bus_name is below the plausible minimum cut-off value of $BUS_VOLTAGE_MAGNITUDE_CUTOFF_MIN p.u. and has been set to $BUS_VOLTAGE_MAGNITUDE_CUTOFF_MIN p.u."
            )
            bus_vm = BUS_VOLTAGE_MAGNITUDE_CUTOFF_MIN
        elseif bt == PSY.ACBusTypes.PQ && bus_vm > BUS_VOLTAGE_MAGNITUDE_CUTOFF_MAX
            @warn(
                "Initial bus voltage magnitude of $bus_vm p.u. at PQ bus $bus_name is above the plausible maximum cut-off value of $BUS_VOLTAGE_MAGNITUDE_CUTOFF_MAX p.u. and has been set to $BUS_VOLTAGE_MAGNITUDE_CUTOFF_MAX p.u."
            )
            bus_vm = BUS_VOLTAGE_MAGNITUDE_CUTOFF_MAX
        end
        bus_magnitude[ix] = bus_vm
    end
end
##############################################################################
# Matrix Methods #############################################################

"""Matrix multiplication A*x. Written this way because a VirtualPTDF 
matrix does not store all of its entries: instead, it calculates
them (or retrieves them from cache), one element or one row at a time."""
function my_mul_mt(
    A::PNM.VirtualPTDF,
    x::Vector{Float64},
)
    y = zeros(length(A.axes[1]))
    for i in 1:length(A.axes[1])
        name_ = A.axes[1][i]
        y[i] = LinearAlgebra.dot(A[name_, :], x)
    end
    return y
end

"""Similar to above: A*X where X is a matrix."""
my_mul_mt(
    A::PNM.VirtualPTDF,
    X::Matrix{Float64},
) = vcat((A[name_, :]' * X for name_ in A.axes[1])...)

function make_dc_powerflowdata(
    sys,
    time_steps,
    timestep_names,
    power_network_matrix,
    aux_network_matrix,
    n_buses,
    n_branches,
    bus_lookup,
    branch_lookup,
    temp_bus_map,
    valid_ix,
    converged,
    loss_factors,
    calculate_loss_factors,
)
    branch_type = Vector{DataType}(undef, length(branch_lookup))
    for (ix, b) in enumerate(PNM.get_ac_branches(sys))
        branch_type[ix] = typeof(b)
    end
    bus_reactivepower_bounds = Vector{Vector{Float64}}(undef, n_buses)
    timestep_map = Dict(zip([i for i in 1:time_steps], timestep_names))
    neighbors = Vector{Set{Int}}()
    return make_powerflowdata(
        sys,
        time_steps,
        power_network_matrix,
        aux_network_matrix,
        n_buses,
        n_branches,
        bus_lookup,
        branch_lookup,
        temp_bus_map,
        branch_type,
        timestep_map,
        valid_ix,
        neighbors,
        converged,
        loss_factors,
        calculate_loss_factors,
    )
end

function make_powerflowdata(
    sys,
    time_steps,
    power_network_matrix,
    aux_network_matrix,
    n_buses,
    n_branches,
    bus_lookup,
    branch_lookup,
    temp_bus_map,
    branch_type,
    timestep_map,
    valid_ix,
    neighbors,
    converged,
    loss_factors,
    calculate_loss_factors,
)
    bus_type = Vector{PSY.ACBusTypes}(undef, n_buses)
    bus_angles = zeros(Float64, n_buses)
    bus_magnitude = ones(Float64, n_buses)

    _initialize_bus_data!(
        bus_type,
        bus_angles,
        bus_magnitude,
        temp_bus_map,
        bus_lookup,
        sys,
    )

    # define injection vectors related to the first timestep
    bus_activepower_injection = zeros(Float64, n_buses)
    bus_reactivepower_injection = zeros(Float64, n_buses)
    _get_injections!(
        bus_activepower_injection,
        bus_reactivepower_injection,
        bus_lookup,
        sys,
    )

    bus_activepower_withdrawals = zeros(Float64, n_buses)
    bus_reactivepower_withdrawals = zeros(Float64, n_buses)
    _get_withdrawals!(
        bus_activepower_withdrawals,
        bus_reactivepower_withdrawals,
        bus_lookup,
        sys,
    )

    # Define fields as matrices whose number of columns is equal to the number of time_steps
    bus_activepower_injection_1 = zeros(Float64, n_buses, time_steps)
    bus_reactivepower_injection_1 = zeros(Float64, n_buses, time_steps)
    bus_activepower_withdrawals_1 = zeros(Float64, n_buses, time_steps)
    bus_reactivepower_withdrawals_1 = zeros(Float64, n_buses, time_steps)
    bus_reactivepower_bounds_1 = Matrix{Vector{Float64}}(undef, n_buses, time_steps)
    bus_magnitude_1 = ones(Float64, n_buses, time_steps)
    bus_angles_1 = zeros(Float64, n_buses, time_steps)

    # Initial values related to first timestep allocated in the first column
    bus_activepower_injection_1[:, 1] .= bus_activepower_injection
    bus_reactivepower_injection_1[:, 1] .= bus_reactivepower_injection
    bus_activepower_withdrawals_1[:, 1] .= bus_activepower_withdrawals
    bus_reactivepower_withdrawals_1[:, 1] .= bus_reactivepower_withdrawals
    bus_magnitude_1[:, 1] .= bus_magnitude
    bus_angles_1[:, 1] .= bus_angles

    bus_reactivepower_bounds = Vector{Vector{Float64}}(undef, n_buses)
    for i in 1:n_buses
        bus_reactivepower_bounds[i] = [0.0, 0.0]
    end
    _get_reactive_power_bound!(bus_reactivepower_bounds, bus_lookup, sys)
    bus_reactivepower_bounds_1[:, 1] .= bus_reactivepower_bounds

    # Initial bus types are same for every time period
    bus_type_1 = repeat(bus_type; outer = [1, time_steps])
    @assert size(bus_type_1) == (n_buses, time_steps)

    # Initial flows are all zero
    branch_activepower_flow_from_to = zeros(Float64, n_branches, time_steps)
    branch_reactivepower_flow_from_to = zeros(Float64, n_branches, time_steps)
    branch_activepower_flow_to_from = zeros(Float64, n_branches, time_steps)
    branch_reactivepower_flow_to_from = zeros(Float64, n_branches, time_steps)

    return PowerFlowData(
        bus_lookup,
        branch_lookup,
        bus_activepower_injection_1,
        bus_reactivepower_injection_1,
        bus_activepower_withdrawals_1,
        bus_reactivepower_withdrawals_1,
        bus_reactivepower_bounds_1,
        bus_type_1,
        branch_type,
        bus_magnitude_1,
        bus_angles_1,
        branch_activepower_flow_from_to,
        branch_reactivepower_flow_from_to,
        branch_activepower_flow_to_from,
        branch_reactivepower_flow_to_from,
        timestep_map,
        valid_ix,
        power_network_matrix,
        aux_network_matrix,
        neighbors,
        converged,
        loss_factors,
        calculate_loss_factors,
    )
end
