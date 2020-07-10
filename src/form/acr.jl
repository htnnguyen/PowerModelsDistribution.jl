""
function variable_mc_bus_voltage(pm::_PM.AbstractACRModel; nw::Int=pm.cnw, bounded::Bool=true, kwargs...)
    variable_mc_bus_voltage_real(pm; nw=nw, bounded=bounded, kwargs...)
    variable_mc_bus_voltage_imaginary(pm; nw=nw, bounded=bounded, kwargs...)

    # local infeasbility issues without proper initialization;
    # convergence issues start when the equivalent angles of the starting point
    # are further away than 90 degrees from the solution (as given by ACP)
    # this is the default behaviour of _PM, initialize all phases as (1,0)
    # the magnitude seems to have little effect on the convergence (>0.05)
    # updating the starting point to a balanced phasor does the job
    for id in ids(pm, nw, :bus)
        busref = ref(pm, nw, :bus, id)
        terminals = busref["terminals"]
        grounded = busref["grounded"]

        ncnd = length(terminals)

        vm = haskey(busref, "vm_start") ? busref["vm_start"] : fill(0.0, ncnd)
        vm[.!grounded] .= 1.0

        # TODO how to support non-integer terminals?
        nph = 3
        va = haskey(busref, "va_start") ? busref["va_start"] : [c <= nph ? _wrap_to_pi(2 * pi / nph * (1-c)) : 0.0 for c in terminals]

        vr = vm .* cos.(va)
        vi = vm .* sin.(va)
        for (idx,t) in enumerate(terminals)
            JuMP.set_start_value(var(pm, nw, :vr, id)[t], vr[idx])
            JuMP.set_start_value(var(pm, nw, :vi, id)[t], vi[idx])
        end
    end

    # apply bounds if bounded
    if bounded
        for i in ids(pm, nw, :bus)
            constraint_mc_voltage_magnitude_bounds(pm, i, nw=nw)
        end
    end
end


""
function variable_mc_bus_voltage_on_off(pm::_PM.AbstractACRModel; kwargs...)
    variable_mc_bus_voltage_real_on_off(pm; kwargs...)
    variable_mc_bus_voltage_imaginary_on_off(pm; kwargs...)

    nw = get(kwargs, :nw, pm.cnw)

    ncnd = length(conductor_ids(pm, nw))
    theta = [_wrap_to_pi(2 * pi / ncnd * (1-c)) for c in 1:ncnd]

    vm = 1
    for id in ids(pm, nw, :bus)
        busref = ref(pm, nw, :bus, id)
        if !haskey(busref, "va_start")
        # if it has this key, it was set at PM level
            for (idx, t) in enumerate(busref["terminals"])
                vr = vm*cos(theta[idx])
                vi = vm*sin(theta[idx])
                JuMP.set_start_value(var(pm, nw, :vr, id)[t], vr)
                JuMP.set_start_value(var(pm, nw, :vi, id)[t], vi)
            end
        end
    end
end


""
function variable_mc_bus_voltage_real_on_off(pm::_PM.AbstractACRModel; nw::Int=pm.cnw, bounded::Bool=true, report::Bool=true)
    terminals = Dict(i => ref(pm, nw, :bus, i)["terminals"] for i in ids(pm, nw, :bus))
    vr = var(pm, nw)[:vr] = Dict(i => JuMP.@variable(pm.model,
            [t in terminals[i]], base_name="$(nw)_vr_$(i)",
            start = comp_start_value(ref(pm, nw, :bus, i), "vr_start", t, 0.0)
        ) for i in ids(pm, nw, :bus)
    )

    if bounded
        for (i,bus) in ref(pm, nw, :bus)
            if haskey(bus, "vmax")
                for (idx, t) in enumerate(terminals[i])
                    set_lower_bound(vr[i][t], -bus["vmax"][idx])
                    set_upper_bound(vr[i][t],  bus["vmax"][idx])
                end
            end
        end
    end

    report && _IM.sol_component_value(pm, nw, :bus, :vr, ids(pm, nw, :bus), vr)
end


""
function variable_mc_bus_voltage_imaginary_on_off(pm::_PM.AbstractACRModel; nw::Int=pm.cnw, bounded::Bool=true, report::Bool=true)
    terminals = Dict(i => ref(pm, nw, :bus, i)["terminals"] for i in ids(pm, nw, :bus))
    vi = var(pm, nw)[:vi] = Dict(i => JuMP.@variable(pm.model,
            [t in terminals[i]], base_name="$(nw)_vi_$(i)",
            start = comp_start_value(ref(pm, nw, :bus, i), "vi_start", t, 0.0)
        ) for i in ids(pm, nw, :bus)
    )

    if bounded
        for (i,bus) in ref(pm, nw, :bus)
            if haskey(bus, "vmax")
                for (idx, t) in enumerate(terminals[i])
                    set_lower_bound(vi[i][t], -bus["vmax"][idx])
                    set_upper_bound(vi[i][t],  bus["vmax"][idx])
                end
            end
        end
    end

    report && _IM.sol_component_value(pm, nw, :bus, :vi, ids(pm, nw, :bus), vi)
end


"`vmin <= vm[i] <= vmax`"
function constraint_mc_voltage_magnitude_bounds(pm::_PM.AbstractACRModel, nw::Int, i::Int, vmin::Vector{<:Real}, vmax::Vector{<:Real})
    @assert all(vmin .<= vmax)
    vr = var(pm, nw, :vr, i)
    vi = var(pm, nw, :vi, i)

    for (idx,t) in enumerate(ref(pm, nw, :bus, i)["terminals"])
        JuMP.@constraint(pm.model, vmin[idx]^2 <= vr[t]^2 + vi[t]^2)
        if vmax[idx] < Inf
            JuMP.@constraint(pm.model, vmax[idx]^2 >= vr[t]^2 + vi[t]^2)
        end
    end
end


"bus voltage on/off constraint for load shed problem"
function constraint_mc_bus_voltage_on_off(pm::_PM.AbstractACRModel; nw::Int=pm.cnw, kwargs...)
    for (i,bus) in ref(pm, nw, :bus)
        constraint_mc_bus_voltage_magnitude_on_off(pm, i; nw=nw)
    end
end


"on/off bus voltage magnitude constraint"
function constraint_mc_bus_voltage_magnitude_on_off(pm::_PM.AbstractACRModel, nw::Int, i::Int, vmin, vmax)
    vr = var(pm, nw, :vr, i)
    vi = var(pm, nw, :vi, i)
    z_voltage = var(pm, nw, :z_voltage, i)

    # TODO: non-convex constraints, look into ways to avoid in the future
    # z_voltage*vr_lb[c] <= vr[c] <= z_voltage*vr_ub[c]
    # z_voltage*vi_lb[c] <= vi[c] <= z_voltage*vi_ub[c]
    for (idx, t) in enumerate(ref(pm, nw, :bus, i)["terminals"])
        if isfinite(vmax[idx])
            JuMP.@constraint(pm.model, vr[t]^2 + vi[t]^2 <= vmax[idx]^2*z_voltage)
        end

        if isfinite(vmin[idx])
            JuMP.@constraint(pm.model, vr[t]^2 + vi[t]^2 >= vmin[idx]^2*z_voltage)
        end
    end
end


"Creates phase angle constraints at reference buses"
function constraint_mc_theta_ref(pm::_PM.AbstractACRModel, nw::Int, i::Int, va_ref::Vector{<:Real})
    vr = var(pm, nw, :vr, i)
    vi = var(pm, nw, :vi, i)

    # deal with cases first where tan(theta)==Inf or tan(theta)==0
    for (idx, t) in enumerate(ref(pm, nw, :bus, i)["terminals"])
        if va_ref[t] == pi/2
            JuMP.@constraint(pm.model, vr[t] == 0)
            JuMP.@constraint(pm.model, vi[t] >= 0)
        elseif va_ref[t] == -pi/2
            JuMP.@constraint(pm.model, vr[t] == 0)
            JuMP.@constraint(pm.model, vi[t] <= 0)
        elseif va_ref[t] == 0
            JuMP.@constraint(pm.model, vr[t] >= 0)
            JuMP.@constraint(pm.model, vi[t] == 0)
        elseif va_ref[t] == pi
            JuMP.@constraint(pm.model, vr[t] >= 0)
            JuMP.@constraint(pm.model, vi[t] == 0)
        else
            JuMP.@constraint(pm.model, vi[t] == tan(va_ref[t])*vr[t])
            # va_ref also implies a sign for vr, vi
            if 0<=va_ref[t] && va_ref[t] <= pi
                JuMP.@constraint(pm.model, vi[t] >= 0)
            else
                JuMP.@constraint(pm.model, vi[t] <= 0)
            end
        end
    end
end


""
function constraint_mc_voltage_angle_difference(pm::_PM.AbstractACRModel, nw::Int, f_idx::Tuple{Int,Int,Int}, angmin::Vector{<:Real}, angmax::Vector{<:Real})
    i, f_bus, t_bus = f_idx

    vr_fr = var(pm, nw, :vr, f_bus)
    vi_fr = var(pm, nw, :vi, f_bus)
    vr_to = var(pm, nw, :vr, t_bus)
    vi_to = var(pm, nw, :vi, t_bus)

    f_connections = ref(pm, nw, :branch, i)["f_connections"]
    t_connections = ref(pm, nw, :branch, i)["t_connections"]

    for (idx, (fc,tc)) in enumerate(zip(f_connections, t_connections))
        JuMP.@constraint(pm.model, (vi_fr[fc] * vr_to[tc] .- vr_fr[fc] * vi_to[tc]) <= tan(angmax[idx]) * (vr_fr[fc] * vr_to[tc] .+ vi_fr[fc] * vi_to[tc]))
        JuMP.@constraint(pm.model, (vi_fr[fc] * vr_to[tc] .- vr_fr[fc] * vi_to[tc]) >= tan(angmin[idx]) * (vr_fr[fc] * vr_to[tc] .+ vi_fr[fc] * vi_to[tc]))
    end
end


""
function constraint_mc_slack_power_balance(pm::_PM.AbstractACRModel, nw::Int, i::Int, bus_arcs, bus_arcs_sw, bus_arcs_trans, bus_gens, bus_storage, bus_pd, bus_qd, bus_gs, bus_bs)
    vr = var(pm, nw, :vr, i)
    vi = var(pm, nw, :vi, i)
    p    = get(var(pm, nw),    :p, Dict()); _PM._check_var_keys(p, bus_arcs, "active power", "branch")
    q    = get(var(pm, nw),    :q, Dict()); _PM._check_var_keys(q, bus_arcs, "reactive power", "branch")
    pg   = get(var(pm, nw),   :pg, Dict()); _PM._check_var_keys(pg, bus_gens, "active power", "generator")
    qg   = get(var(pm, nw),   :qg, Dict()); _PM._check_var_keys(qg, bus_gens, "reactive power", "generator")
    ps   = get(var(pm, nw),   :ps, Dict()); _PM._check_var_keys(ps, bus_storage, "active power", "storage")
    qs   = get(var(pm, nw),   :qs, Dict()); _PM._check_var_keys(qs, bus_storage, "reactive power", "storage")
    psw  = get(var(pm, nw),  :psw, Dict()); _PM._check_var_keys(psw, bus_arcs_sw, "active power", "switch")
    qsw  = get(var(pm, nw),  :qsw, Dict()); _PM._check_var_keys(qsw, bus_arcs_sw, "reactive power", "switch")
    pt   = get(var(pm, nw),   :pt, Dict()); _PM._check_var_keys(pt, bus_arcs_trans, "active power", "transformer")
    qt   = get(var(pm, nw),   :qt, Dict()); _PM._check_var_keys(qt, bus_arcs_trans, "reactive power", "transformer")
    p_slack = var(pm, nw, :p_slack, i)
    q_slack = var(pm, nw, :q_slack, i)

    cstr_p = []
    cstr_q = []

    for c in conductor_ids(pm; nw=nw)
        cp = JuMP.@constraint(pm.model,
            sum(p[a][c] for a in bus_arcs)
            + sum(psw[a_sw][c] for a_sw in bus_arcs_sw)
            + sum(pt[a_trans][c] for a_trans in bus_arcs_trans)
            ==
            sum(pg[g][c] for g in bus_gens)
            - sum(ps[s][c] for s in bus_storage)
            - sum(pd[c] for pd in values(bus_pd))
            - sum(gs[c] for gs in values(bus_gs))*(vr[c]^2 + vi[c]^2)
            + p_slack[c]
        )
        push!(cstr_p, cp)

        cq = JuMP.@constraint(pm.model,
            sum(q[a][c] for a in bus_arcs)
            + sum(qsw[a_sw][c] for a_sw in bus_arcs_sw)
            + sum(qt[a_trans][c] for a_trans in bus_arcs_trans)
            ==
            sum(qg[g][c] for g in bus_gens)
            - sum(qs[s][c] for s in bus_storage)
            - sum(qd[c] for qd in values(bus_qd))
            + sum(bs[c] for bs in values(bus_bs))*(vr[c]^2 + vi[c]^2)
            + q_slack[c]
        )
        push!(cstr_q, cq)
    end

    con(pm, nw, :lam_kcl_r)[i] = isa(cstr_p, Array) ? cstr_p : [cstr_p]
    con(pm, nw, :lam_kcl_i)[i] = isa(cstr_q, Array) ? cstr_q : [cstr_q]

    if _IM.report_duals(pm)
        sol(pm, nw, :bus, i)[:lam_kcl_r] = cstr_p
        sol(pm, nw, :bus, i)[:lam_kcl_i] = cstr_q
    end
end


""
function constraint_mc_power_balance(pm::_PM.AbstractACRModel, nw::Int, i::Int, bus_arcs, bus_arcs_sw, bus_arcs_trans, bus_gens, bus_storage, bus_pd, bus_qd, bus_gs, bus_bs)
    vr = var(pm, nw, :vr, i)
    vi = var(pm, nw, :vi, i)
    p    = get(var(pm, nw),    :p, Dict()); _PM._check_var_keys(p, bus_arcs, "active power", "branch")
    q    = get(var(pm, nw),    :q, Dict()); _PM._check_var_keys(q, bus_arcs, "reactive power", "branch")
    pg   = get(var(pm, nw),   :pg, Dict()); _PM._check_var_keys(pg, bus_gens, "active power", "generator")
    qg   = get(var(pm, nw),   :qg, Dict()); _PM._check_var_keys(qg, bus_gens, "reactive power", "generator")
    ps   = get(var(pm, nw),   :ps, Dict()); _PM._check_var_keys(ps, bus_storage, "active power", "storage")
    qs   = get(var(pm, nw),   :qs, Dict()); _PM._check_var_keys(qs, bus_storage, "reactive power", "storage")
    psw  = get(var(pm, nw),  :psw, Dict()); _PM._check_var_keys(psw, bus_arcs_sw, "active power", "switch")
    qsw  = get(var(pm, nw),  :qsw, Dict()); _PM._check_var_keys(qsw, bus_arcs_sw, "reactive power", "switch")
    pt   = get(var(pm, nw),   :pt, Dict()); _PM._check_var_keys(pt, bus_arcs_trans, "active power", "transformer")
    qt   = get(var(pm, nw),   :qt, Dict()); _PM._check_var_keys(qt, bus_arcs_trans, "reactive power", "transformer")

    cnds = conductor_ids(pm; nw=nw)
    ncnds = length(cnds)

    Gt = isempty(bus_gs) ? fill(0.0, ncnds, ncnds) : sum(values(bus_gs))
    Bt = isempty(bus_bs) ? fill(0.0, ncnds, ncnds) : sum(values(bus_bs))

    cstr_p = JuMP.@constraint(pm.model,
        sum(p[a] for a in bus_arcs)
        + sum(psw[a_sw] for a_sw in bus_arcs_sw)
        + sum(pt[a_trans] for a_trans in bus_arcs_trans)
        .==
        sum(pg[g] for g in bus_gens)
        - sum(ps[s] for s in bus_storage)
        - sum(pd for pd in values(bus_pd))
        # shunt
        - (vr.*(Gt*vr-Bt*vi) + vi.*(Gt*vi+Bt*vr))
    )

    cstr_q = JuMP.@constraint(pm.model,
        sum(q[a] for a in bus_arcs)
        + sum(qsw[a_sw] for a_sw in bus_arcs_sw)
        + sum(qt[a_trans] for a_trans in bus_arcs_trans)
        .==
        sum(qg[g] for g in bus_gens)
        - sum(qs[s] for s in bus_storage)
        - sum(qd for qd in values(bus_qd))
        # shunt
        - (-vr.*(Gt*vi+Bt*vr) + vi.*(Gt*vr-Bt*vi))
    )

    con(pm, nw, :lam_kcl_r)[i] = isa(cstr_p, Array) ? cstr_p : [cstr_p]
    con(pm, nw, :lam_kcl_i)[i] = isa(cstr_q, Array) ? cstr_q : [cstr_q]

    if _IM.report_duals(pm)
        sol(pm, nw, :bus, i)[:lam_kcl_r] = cstr_p
        sol(pm, nw, :bus, i)[:lam_kcl_i] = cstr_q
    end
end


""
function constraint_mc_load_power_balance(pm::_PM.AbstractACRModel, nw::Int, i::Int, bus_arcs, bus_arcs_sw, bus_arcs_trans, bus_gens, bus_storage, bus_loads, bus_shunts, Gt, Bt)
    bus = ref(pm, nw, :bus, i)
    terminals = bus["terminals"]
    grounded = bus["grounded"]

    vr = var(pm, nw, :vr, i)
    vi = var(pm, nw, :vi, i)
    p    = get(var(pm, nw), :p,      Dict()); _PM._check_var_keys(p,   bus_arcs,       "active power",   "branch")
    q    = get(var(pm, nw), :q,      Dict()); _PM._check_var_keys(q,   bus_arcs,       "reactive power", "branch")
    pg   = get(var(pm, nw), :pg_bus, Dict()); _PM._check_var_keys(pg,  bus_gens,       "active power",   "generator")
    qg   = get(var(pm, nw), :qg_bus, Dict()); _PM._check_var_keys(qg,  bus_gens,       "reactive power", "generator")
    ps   = get(var(pm, nw), :ps,     Dict()); _PM._check_var_keys(ps,  bus_storage,    "active power",   "storage")
    qs   = get(var(pm, nw), :qs,     Dict()); _PM._check_var_keys(qs,  bus_storage,    "reactive power", "storage")
    psw  = get(var(pm, nw), :psw,    Dict()); _PM._check_var_keys(psw, bus_arcs_sw,    "active power",   "switch")
    qsw  = get(var(pm, nw), :qsw,    Dict()); _PM._check_var_keys(qsw, bus_arcs_sw,    "reactive power", "switch")
    pt   = get(var(pm, nw), :pt,     Dict()); _PM._check_var_keys(pt,  bus_arcs_trans, "active power",   "transformer")
    qt   = get(var(pm, nw), :qt,     Dict()); _PM._check_var_keys(qt,  bus_arcs_trans, "reactive power", "transformer")
    pd   = get(var(pm, nw), :pd_bus, Dict()); _PM._check_var_keys(pd,  bus_loads,      "active power",   "load")
    qd   = get(var(pm, nw), :qd_bus, Dict()); _PM._check_var_keys(pd,  bus_loads,      "reactive power", "load")

    cstr_p = []
    cstr_q = []

    # pd/qd can be NLexpressions, so cannot be vectorized
    for (i, t) in [(idx,t) for (idx,t) in enumerate(terminals) if !grounded[idx]]
        crsh = sum(Gt[i,j]*vr[s]-Bt[i,j]*vi[s] for (j,s) in enumerate(terminals) if !grounded[j])
        cish = sum(Gt[i,j]*vi[s]+Bt[i,j]*vr[s] for (j,s) in enumerate(terminals) if !grounded[j])

        cp = JuMP.@constraint(pm.model,
              sum(p[arc][t] for (arc, conns) in bus_arcs if t in conns)
            + sum(psw[arc][t] for (arc, conns) in bus_arcs_sw if t in conns)
            + sum(pt[arc][t] for (arc, conns) in bus_arcs_trans if t in conns)
            + sum(pd[load][t] for (load, conns) in bus_loads if t in conns)
            - sum(pg[gen][t] for (gen, conns) in bus_gens if t in conns)
            - sum(ps[strg][t] for (strg, conns) in bus_storage if t in conns)
            - (-vr[t] * crsh - vi[t] * cish)
            == 0
        )
        push!(cstr_p, cp)

        cq = JuMP.@constraint(pm.model,
              sum(q[arc][t] for (arc, conns) in bus_arcs if t in conns)
            + sum(qsw[arc][t] for (arc, conns) in bus_arcs_sw if t in conns)
            + sum(qt[arc][t] for (arc, conns) in bus_arcs_trans if t in conns)
            + sum(qd[load][t] for (load, conns) in bus_loads if t in conns)
            - sum(qg[gen][t] for (gen, conns) in bus_gens if t in conns)
            - sum(qs[strg][t] for (strg, conns) in bus_storage if t in conns)
            - ( vr[t] * cish - vi[t] * crsh)
            == 0
        )
        push!(cstr_q, cq)
    end

    con(pm, nw, :lam_kcl_r)[i] = cstr_p
    con(pm, nw, :lam_kcl_i)[i] = cstr_q

    if _IM.report_duals(pm)
        sol(pm, nw, :bus, i)[:lam_kcl_r] = cstr_p
        sol(pm, nw, :bus, i)[:lam_kcl_i] = cstr_q
    end
end


""
function constraint_mc_shed_load_power_balance(pm::_PM.AbstractACRModel, nw::Int, i::Int, bus_arcs, bus_arcs_sw, bus_arcs_trans, bus_gens, bus_storage, bus_loads, bus_shunts, Gt, Bt)
    bus = ref(pm, nw, :bus, i)
    terminals = bus["terminals"]
    grounded = bus["grounded"]

    vr = var(pm, nw, :vr, i)
    vi = var(pm, nw, :vi, i)
    p    = get(var(pm, nw), :p,      Dict()); _PM._check_var_keys(p,   bus_arcs,       "active power",   "branch")
    q    = get(var(pm, nw), :q,      Dict()); _PM._check_var_keys(q,   bus_arcs,       "reactive power", "branch")
    pg   = get(var(pm, nw), :pg, Dict()); _PM._check_var_keys(pg,  bus_gens,       "active power",   "generator")
    qg   = get(var(pm, nw), :qg, Dict()); _PM._check_var_keys(qg,  bus_gens,       "reactive power", "generator")
    ps   = get(var(pm, nw), :ps,     Dict()); _PM._check_var_keys(ps,  bus_storage,    "active power",   "storage")
    qs   = get(var(pm, nw), :qs,     Dict()); _PM._check_var_keys(qs,  bus_storage,    "reactive power", "storage")
    psw  = get(var(pm, nw), :psw,    Dict()); _PM._check_var_keys(psw, bus_arcs_sw,    "active power",   "switch")
    qsw  = get(var(pm, nw), :qsw,    Dict()); _PM._check_var_keys(qsw, bus_arcs_sw,    "reactive power", "switch")
    pt   = get(var(pm, nw), :pt,     Dict()); _PM._check_var_keys(pt,  bus_arcs_trans, "active power",   "transformer")
    qt   = get(var(pm, nw), :qt,     Dict()); _PM._check_var_keys(qt,  bus_arcs_trans, "reactive power", "transformer")
    pd   = get(var(pm, nw), :pd_bus, Dict()); _PM._check_var_keys(pd,  bus_loads,      "active power",   "load")
    qd   = get(var(pm, nw), :qd_bus, Dict()); _PM._check_var_keys(pd,  bus_loads,      "reactive power", "load")
    z_demand = var(pm, nw, :z_demand)
    z_shunt  = var(pm, nw, :z_shunt)
    z_gen = var(pm, nw, :z_gen)
    z_storage = var(pm, nw, :z_storage)

    cstr_p = []
    cstr_q = []

    # pd/qd can be NLexpressions, so cannot be vectorized
    for (i, t) in [(idx,t) for (idx,t) in enumerate(terminals) if !grounded[idx]]
        crsh = sum(Gt[i,j]*vr[s]-Bt[i,j]*vi[s] for (j,s) in enumerate(terminals) if !grounded[j])
        cish = sum(Gt[i,j]*vi[s]+Bt[i,j]*vr[s] for (j,s) in enumerate(terminals) if !grounded[j])

        cp = JuMP.@constraint(pm.model,
              sum(p[arc][t] for (arc, conns) in bus_arcs if t in conns)
            + sum(psw[arc][t] for (arc, conns) in bus_arcs_sw if t in conns)
            + sum(pt[arc][t] for (arc, conns) in bus_arcs_trans if t in conns)
            + sum(pd[load][t]*z_demand[load] for (load, conns) in bus_loads if t in conns)
            - sum(pg[gen][t]*z_gen[gen] for (gen, conns) in bus_gens if t in conns)
            - sum(ps[strg][t]*z_storage[strg] for (strg, conns) in bus_storage if t in conns)
            - (-vr[t] * crsh - vi[t] * cish)
            == 0
        )
        push!(cstr_p, cp)

        cq = JuMP.@constraint(pm.model,
              sum(q[arc][t] for (arc, conns) in bus_arcs if t in conns)
            + sum(qsw[arc][t] for (arc, conns) in bus_arcs_sw if t in conns)
            + sum(qt[arc][t] for (arc, conns) in bus_arcs_trans if t in conns)
            + sum(qd[load][t]*z_demand[load] for (load, conns) in bus_loads if t in conns)
            - sum(qg[gen][t]*z_gen[gen] for (gen, conns) in bus_gens if t in conns)
            - sum(qs[strg][t]*z_storage[strg] for (strg, conns) in bus_storage if t in conns)
            - ( vr[t] * cish - vi[t] * crsh)
            == 0
        )
        push!(cstr_q, cq)
    end

    con(pm, nw, :lam_kcl_r)[i] = isa(cstr_p, Array) ? cstr_p : [cstr_p]
    con(pm, nw, :lam_kcl_i)[i] = isa(cstr_q, Array) ? cstr_q : [cstr_q]

    if _IM.report_duals(pm)
        sol(pm, nw, :bus, i)[:lam_kcl_r] = cstr_p
        sol(pm, nw, :bus, i)[:lam_kcl_i] = cstr_q
    end
end


"""
Creates Ohms constraints

s_fr = v_fr.*conj(Y*(v_fr-v_to))
s_fr = (vr_fr+im*vi_fr).*(G-im*B)*([vr_fr-vr_to]-im*[vi_fr-vi_to])
s_fr = (vr_fr+im*vi_fr).*([G*vr_fr-G*vr_to-B*vi_fr+B*vi_to]-im*[G*vi_fr-G*vi_to+B*vr_fr-B*vr_to])
"""
function constraint_mc_ohms_yt_from(pm::_PM.AbstractACRModel, nw::Int, f_bus::Int, t_bus::Int, f_idx::Tuple{Int,Int,Int}, t_idx::Tuple{Int,Int,Int}, G::Matrix{<:Real}, B::Matrix{<:Real}, G_fr::Matrix{<:Real}, B_fr::Matrix{<:Real})
    f_connections = ref(pm, nw, :branch, f_idx[1])["f_connections"]
    t_connections = ref(pm, nw, :branch, f_idx[1])["t_connections"]

    p_fr  = [var(pm, nw, :p, f_idx)[t] for t in f_connections]
    q_fr  = [var(pm, nw, :q, f_idx)[t] for t in f_connections]
    vr_fr = [var(pm, nw, :vr, f_bus)[t] for t in f_connections]
    vr_to = [var(pm, nw, :vr, t_bus)[t] for t in t_connections]
    vi_fr = [var(pm, nw, :vi, f_bus)[t] for t in f_connections]
    vi_to = [var(pm, nw, :vi, t_bus)[t] for t in t_connections]

    JuMP.@constraint(pm.model,
            p_fr .==  vr_fr.*(G*vr_fr-G*vr_to-B*vi_fr+B*vi_to)
                     +vi_fr.*(G*vi_fr-G*vi_to+B*vr_fr-B*vr_to)
                     # shunt
                     +vr_fr.*(G_fr*vr_fr-B_fr*vi_fr)
                     +vi_fr.*(G_fr*vi_fr+B_fr*vr_fr)
    )
    JuMP.@constraint(pm.model,
            q_fr .== -vr_fr.*(G*vi_fr-G*vi_to+B*vr_fr-B*vr_to)
                     +vi_fr.*(G*vr_fr-G*vr_to-B*vi_fr+B*vi_to)
                     # shunt
                     -vr_fr.*(G_fr*vi_fr+B_fr*vr_fr)
                     +vi_fr.*(G_fr*vr_fr-B_fr*vi_fr)
    )
end


"""
Creates Ohms constraints (yt post fix indicates that Y and T values are in rectangular form)

```
p[t_idx] ==  (g+g_to)*v[t_bus]^2 + (-g*tr-b*ti)/tm*(v[t_bus]*v[f_bus]*cos(t[t_bus]-t[f_bus])) + (-b*tr+g*ti)/tm*(v[t_bus]*v[f_bus]*sin(t[t_bus]-t[f_bus]))
q[t_idx] == -(b+b_to)*v[t_bus]^2 - (-b*tr+g*ti)/tm*(v[t_bus]*v[f_bus]*cos(t[f_bus]-t[t_bus])) + (-g*tr-b*ti)/tm*(v[t_bus]*v[f_bus]*sin(t[t_bus]-t[f_bus]))
```
"""
function constraint_mc_ohms_yt_to(pm::_PM.AbstractACRModel, nw::Int, f_bus::Int, t_bus::Int, f_idx::Tuple{Int,Int,Int}, t_idx::Tuple{Int,Int,Int}, G::Matrix, B::Matrix, G_to::Matrix, B_to::Matrix)
    constraint_mc_ohms_yt_from(pm, nw, t_bus, f_bus, t_idx, f_idx, G, B, G_to, B_to)
end


""
function constraint_mc_load_setpoint_wye(pm::_PM.AbstractACRModel, nw::Int, id::Int, bus_id::Int, a::Vector{<:Real}, alpha::Vector{<:Real}, b::Vector{<:Real}, beta::Vector{<:Real}; report::Bool=true)
    vr = var(pm, nw, :vr, bus_id)
    vi = var(pm, nw, :vi, bus_id)

    connections = ref(pm, nw, :load, id)["connections"]

    bus = ref(pm, nw, :bus, bus_id)
    terminals = bus["terminals"]
    grounded = bus["grounded"]

    # if constant power load
    if all(alpha.==0) && all(beta.==0)
        pd_bus = a
        qd_bus = b
    else
        pd_bus = Vector{JuMP.NonlinearExpression}([])
        qd_bus = Vector{JuMP.NonlinearExpression}([])

        for (i,t) in [(i,t) for (i,t) in enumerate(connections) if !grounded[findfirst(isequal(t), terminals)]]
            crd = JuMP.@NLexpression(pm.model, a[i]*vr[t]*(vr[t]^2+vi[t]^2)^(alpha[i]/2-1)+b[i]*vi[t]*(vr[t]^2+vi[t]^2)^(beta[i]/2 -1))
            cid = JuMP.@NLexpression(pm.model, a[i]*vi[t]*(vr[t]^2+vi[t]^2)^(alpha[i]/2-1)-b[i]*vr[t]*(vr[t]^2+vi[t]^2)^(beta[i]/2 -1))

            push!(pd_bus, JuMP.@NLexpression(pm.model,  vr[t]*crd[i]+vi[t]*cid[i]))
            push!(qd_bus, JuMP.@NLexpression(pm.model, -vr[t]*cid[i]+vi[t]*crd[i]))
        end
    end

    pd_bus = JuMP.Containers.DenseAxisArray(pd_bus, connections)
    qd_bus = JuMP.Containers.DenseAxisArray(qd_bus, connections)

    var(pm, nw, :pd_bus)[id] = pd_bus
    var(pm, nw, :qd_bus)[id] = qd_bus

    if report
        sol(pm, nw, :load, id)[:pd_bus] = pd_bus
        sol(pm, nw, :load, id)[:qd_bus] = qd_bus

        pd = Vector{JuMP.NonlinearExpression}([])
        qd = Vector{JuMP.NonlinearExpression}([])

        for (i,t) in [(i,t) for (i,t) in enumerate(connections) if !grounded[findfirst(isequal(t), terminals)]]
            push!(pd, JuMP.@NLexpression(pm.model, a[i]*(vr[t]^2+vi[t]^2)^(alpha[i]/2) ))
            push!(qd, JuMP.@NLexpression(pm.model, b[i]*(vr[t]^2+vi[t]^2)^(beta[i]/2)  ))
        end
        sol(pm, nw, :load, id)[:pd] = JuMP.Containers.DenseAxisArray(pd, connections)
        sol(pm, nw, :load, id)[:qd] = JuMP.Containers.DenseAxisArray(qd, connections)
    end
end


""
function constraint_mc_load_setpoint_delta(pm::_PM.AbstractACRModel, nw::Int, id::Int, bus_id::Int, a::Vector{<:Real}, alpha::Vector{<:Real}, b::Vector{<:Real}, beta::Vector{<:Real}; report::Bool=true)
    vr = var(pm, nw, :vr, bus_id)
    vi = var(pm, nw, :vi, bus_id)

    load = ref(pm, nw, :load, id)
    connections = load["connections"]
    nph = length(load["pd"])
    prev = Dict(i=>connections[(i+nph-2)%nph+1] for i in 1:nph)
    next = Dict(i=>connections[i%nph+1] for i in 1:nph)

    vrd = []
    vid = []
    for (i, c) in enumerate(connections[1:nph])
        push!(vrd, JuMP.@NLexpression(pm.model, vr[c]-vr[next[i]]))
        push!(vid, JuMP.@NLexpression(pm.model, vi[c]-vi[next[i]]))
    end

    # @warn id ref(pm, nw, :load, id) connections nph
    crd = JuMP.@NLexpression(pm.model, [i in 1:nph], a[i]*vrd[i]*(vrd[i]^2+vid[i]^2)^(alpha[i]/2-1)+b[i]*vid[i]*(vrd[i]^2+vid[i]^2)^(beta[i]/2 -1))
    cid = JuMP.@NLexpression(pm.model, [i in 1:nph], a[i]*vid[i]*(vrd[i]^2+vid[i]^2)^(alpha[i]/2-1)-b[i]*vrd[i]*(vrd[i]^2+vid[i]^2)^(beta[i]/2 -1))

    crd_bus = JuMP.@NLexpression(pm.model, [i in 1:nph], crd[i]-crd[prev[i]])
    cid_bus = JuMP.@NLexpression(pm.model, [i in 1:nph], cid[i]-cid[prev[i]])

    pd_bus = Vector{JuMP.NonlinearExpression}([])
    qd_bus = Vector{JuMP.NonlinearExpression}([])
    for (i,c) in enumerate(connections[1:nph])
        push!(pd_bus, JuMP.@NLexpression(pm.model,  vr[c]*crd_bus[i]+vi[c]*cid_bus[i]))
        push!(qd_bus, JuMP.@NLexpression(pm.model, -vr[c]*cid_bus[i]+vi[c]*crd_bus[i]))
    end

    pd_bus = JuMP.Containers.DenseAxisArray(pd_bus, connections[1:nph])
    qd_bus = JuMP.Containers.DenseAxisArray(qd_bus, connections[1:nph])

    var(pm, nw, :pd_bus)[id] = pd_bus
    var(pm, nw, :qd_bus)[id] = qd_bus

    if report
        sol(pm, nw, :load, id)[:pd_bus] = pd_bus
        sol(pm, nw, :load, id)[:qd_bus] = qd_bus

        pd = JuMP.@NLexpression(pm.model, [i in 1:nph], a[i]*(vrd[i]^2+vid[i]^2)^(alpha[i]/2) )
        qd = JuMP.@NLexpression(pm.model, [i in 1:nph], b[i]*(vrd[i]^2+vid[i]^2)^(beta[i]/2)  )
        sol(pm, nw, :load, id)[:pd] = JuMP.Containers.DenseAxisArray(pd, connections[1:nph])
        sol(pm, nw, :load, id)[:qd] = JuMP.Containers.DenseAxisArray(qd, connections[1:nph])
    end
end


"`vm[i] == vmref`"
function constraint_mc_voltage_magnitude_only(pm::_PM.AbstractACRModel, nw::Int, i::Int, vmref)
    vr = [var(pm, nw, :vr, i)[t] for t in ref(pm, nw, :bus, i)["terminals"]]
    vi = [var(pm, nw, :vi, i)[t] for t in ref(pm, nw, :bus, i)["terminals"]]

    JuMP.@constraint(pm.model, vr.^2 + vi.^2  .== vmref.^2)
end


""
function constraint_mc_gen_setpoint_delta(pm::_PM.AbstractACRModel, nw::Int, id::Int, bus_id::Int, pmin::Vector, pmax::Vector, qmin::Vector, qmax::Vector; report::Bool=true, bounded::Bool=true)
    vr = var(pm, nw, :vr, bus_id)
    vi = var(pm, nw, :vi, bus_id)
    pg = var(pm, nw, :pg, id)
    qg = var(pm, nw, :qg, id)

    crg = []
    cig = []

    connections = ref(pm, nw, :gen, id)["connections"]
    nph = length(connections)
    prev = Dict(i=>(i+nph-2)%nph+1 for i in connections)
    next = Dict(i=>i%nph+1 for i in connections)

    vrg = JuMP.@NLexpression(pm.model, [i in connections], vr[i]-vr[next[i]])
    vig = JuMP.@NLexpression(pm.model, [i in connections], vi[i]-vi[next[i]])

    crg = JuMP.@NLexpression(pm.model, [i in connections], (pg[i]*vrg[i]+qg[i]*vig[i])/(vrg[i]^2+vig[i]^2) )
    cig = JuMP.@NLexpression(pm.model, [i in connections], (pg[i]*vig[i]-qg[i]*vrg[i])/(vrg[i]^2+vig[i]^2) )

    crg_bus = JuMP.@NLexpression(pm.model, [i in connections], crg[i]-crg[prev[i]])
    cig_bus = JuMP.@NLexpression(pm.model, [i in connections], cig[i]-cig[prev[i]])

    pg_bus = JuMP.@NLexpression(pm.model, [i in connections],  vr[i]*crg_bus[i]+vi[i]*cig_bus[i])
    qg_bus = JuMP.@NLexpression(pm.model, [i in connections], -vr[i]*cig_bus[i]+vi[i]*crg_bus[i])

    var(pm, nw, :pg_bus)[id] = pg_bus
    var(pm, nw, :qg_bus)[id] = qg_bus

    if report
        sol(pm, nw, :gen, id)[:pg_bus] = pg_bus
        sol(pm, nw, :gen, id)[:qg_bus] = qg_bus
    end
end


"This function adds all constraints required to model a two-winding, wye-wye connected transformer."
function constraint_mc_transformer_power_yy(pm::_PM.AbstractACRModel, nw::Int, trans_id::Int, f_bus::Int, t_bus::Int, f_idx, t_idx, f_cnd, t_cnd, pol, tm_set, tm_fixed, tm_scale)
    vr_fr = [var(pm, nw, :vr, f_bus)[p] for p in f_cnd]
    vr_to = [var(pm, nw, :vr, t_bus)[p] for p in t_cnd]
    vi_fr = [var(pm, nw, :vi, f_bus)[p] for p in f_cnd]
    vi_to = [var(pm, nw, :vi, t_bus)[p] for p in t_cnd]

    # construct tm as a parameter or scaled variable depending on whether it is fixed or not
    tm = [tm_fixed[p] ? tm_set[p] : var(pm, nw, :tap, trans_id)[p] for p in f_cnd]


    for p in conductor_ids(pm)
        if tm_fixed[p]
            JuMP.@constraint(pm.model, vr_fr[p] == pol*tm_scale*tm[p]*vr_to[p])
            JuMP.@constraint(pm.model, vi_fr[p] == pol*tm_scale*tm[p]*vi_to[p])
        else
            JuMP.@constraint(pm.model, vr_fr[p] == pol*tm_scale*tm[p]*vr_to[p])
            JuMP.@constraint(pm.model, vi_fr[p] == pol*tm_scale*tm[p]*vi_to[p])
        end
    end

    p_fr = [var(pm, nw, :pt, f_idx)[p] for p in f_cnd]
    p_to = [var(pm, nw, :pt, t_idx)[p] for p in t_cnd]
    q_fr = [var(pm, nw, :qt, f_idx)[p] for p in f_cnd]
    q_to = [var(pm, nw, :qt, t_idx)[p] for p in t_cnd]

    JuMP.@constraint(pm.model, p_fr + p_to .== 0)
    JuMP.@constraint(pm.model, q_fr + q_to .== 0)
end


"This function adds all constraints required to model a two-winding, delta-wye connected transformer."
function constraint_mc_transformer_power_dy(pm::_PM.AbstractACRModel, nw::Int, trans_id::Int, f_bus::Int, t_bus::Int, f_idx, t_idx, f_cnd, t_cnd, pol, tm_set, tm_fixed, tm_scale)
    vr_p_fr = [var(pm, nw, :vr, f_bus)[p] for p in f_cnd]
    vr_p_to = [var(pm, nw, :vr, t_bus)[p] for p in t_cnd]
    vi_p_fr = [var(pm, nw, :vi, f_bus)[p] for p in f_cnd]
    vi_p_to = [var(pm, nw, :vi, t_bus)[p] for p in t_cnd]

    @assert length(f_cnd) == length(t_cnd)

    nph = length(tm_set)
    M = _get_delta_transformation_matrix(nph)

    # construct tm as a parameter or scaled variable depending on whether it is fixed or not
    tm = [tm_fixed[p] ? tm_set[p] : var(pm, nw, :tap, trans_id)[p] for p in f_cnd]

    # introduce auxialiary variable vd = Md*v_fr
    vrd = M*vr_p_fr
    vid = M*vi_p_fr

    JuMP.@constraint(pm.model, vrd .== (pol*tm_scale)*tm.*vr_p_to)
    JuMP.@constraint(pm.model, vid .== (pol*tm_scale)*tm.*vi_p_to)

    p_fr = [var(pm, nw, :pt, f_idx)[p] for p in f_cnd]
    p_to = [var(pm, nw, :pt, t_idx)[p] for p in t_cnd]
    q_fr = [var(pm, nw, :qt, f_idx)[p] for p in f_cnd]
    q_to = [var(pm, nw, :qt, t_idx)[p] for p in t_cnd]

    id_re = Array{Any,1}(undef, nph)
    id_im = Array{Any,1}(undef, nph)
    # s/v      = (p+jq)/|v|^2*conj(v)
    #          = (p+jq)/|v|*(cos(va)-j*sin(va))
    # Re(s/v)  = (p*cos(va)+q*sin(va))/|v|
    # -Im(s/v) = -(q*cos(va)-p*sin(va))/|v|
    for p in conductor_ids(pm)
        # id = conj(s_to/v_to)./tm
        id_re[p] = JuMP.@NLexpression(pm.model, (p_to[p]*vr_p_to[p]+q_to[p]*vi_p_to[p])/(tm_scale*tm[p]*pol)/(vr_p_to[p]^2+vi_p_to[p]^2))
        id_im[p] = JuMP.@NLexpression(pm.model, (p_to[p]*vi_p_to[p]-q_to[p]*vr_p_to[p])/(tm_scale*tm[p]*pol)/(vr_p_to[p]^2+vi_p_to[p]^2))
    end
    for (p,q) in zip(f_cnd, _barrel_roll(f_cnd, -1))
        # s_fr  = v_fr*conj(i_fr)
        #       = v_fr*conj(id[q]-id[p])
        #       = v_fr*(id_re[q]-j*id_im[q]-id_re[p]+j*id_im[p])
        JuMP.@NLconstraint(pm.model, p_fr[p] ==
             vr_p_fr[p]*(id_re[q]-id_re[p])
            -vi_p_fr[p]*(-id_im[q]+id_im[p])
        )
        JuMP.@NLconstraint(pm.model, q_fr[p] ==
             vr_p_fr[p]*(-id_im[q]+id_im[p])
            +vi_p_fr[p]*(id_re[q]-id_re[p])
        )
    end
end


""
function constraint_mc_storage_losses(pm::_PM.AbstractACRModel, i::Int; nw::Int=pm.cnw, kwargs...)
    storage = ref(pm, nw, :storage, i)

    vr = var(pm, nw, :vr, storage["storage_bus"])
    vi = var(pm, nw, :vi, storage["storage_bus"])
    ps = var(pm, nw, :ps, i)
    qs = var(pm, nw, :qs, i)
    sc = var(pm, nw, :sc, i)
    sd = var(pm, nw, :sd, i)
    qsc = var(pm, nw, :qsc, i)

    p_loss = storage["p_loss"]
    q_loss = storage["q_loss"]
    r = storage["r"]
    x = storage["x"]

    JuMP.@NLconstraint(pm.model,
        sum(ps[c] for c in conductor_ids(pm)) + (sd - sc)
        ==
        p_loss + sum(r[c]*(ps[c]^2 + qs[c]^2)/(vr[c]^2 + vi[c]^2) for c in conductor_ids(pm))
    )

    JuMP.@NLconstraint(pm.model,
        sum(qs[c] for c in conductor_ids(pm))
        ==
        qsc + q_loss + sum(x[c]*(ps[c]^2 + qs[c]^2)/(vr[c]^2 + vi[c]^2) for c in conductor_ids(pm))
    )
end
